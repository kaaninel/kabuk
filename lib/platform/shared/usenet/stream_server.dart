/// Local HTTP streaming server for Usenet content playback.
///
/// Binds to `127.0.0.1` on an ephemeral port and maps URL paths to active
/// `StreamPipeline` sessions. Media players connect to the per-session URL
/// (e.g. `http://127.0.0.1:PORT/stream/{sessionId}`) and the server handles
/// HTTP Range requests for seamless video seeking.
///
/// The server starts lazily on the first `addSession` call and shuts down
/// automatically when the last session is removed — or explicitly via
/// `dispose`.
///
/// ```
/// ┌──────────┐   GET /stream/{id}   ┌──────────────┐   getBytes()   ┌───────────────┐
/// │  Player  │ ──────────────────▶  │ StreamServer  │ ────────────▶ │ StreamPipeline │
/// │ (VLC …)  │ ◀──────────────────  │  (localhost)  │ ◀──────────── │  (NZB fetch)   │
/// └──────────┘   206 Partial        └──────────────┘   Uint8List    └───────────────┘
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;

import 'package:kabuk/services/usenet.dart';
import 'package:meta/meta.dart';

import 'stream_pipeline.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Chunk size for streaming byte data to the HTTP response (256 KB).
const _chunkSize = 256 * 1024;

/// Byte distance threshold for triggering a pipeline seek when the requested
/// range jumps significantly from the previous read position.
const _seekThreshold = 512 * 1024;

/// Default MIME type used when the pipeline cannot detect one.
const _fallbackMimeType = 'application/octet-stream';

// ---------------------------------------------------------------------------
// _ActiveSession — internal bookkeeping per session
// ---------------------------------------------------------------------------

/// Internal wrapper pairing a [StreamPipeline] with session metadata.
@immutable
class _ActiveSession {
  const _ActiveSession({
    required this.id,
    required this.title,
    required this.pipeline,
  });

  final String id;
  final String title;
  final StreamPipeline pipeline;
}

// ---------------------------------------------------------------------------
// StreamServer
// ---------------------------------------------------------------------------

/// Localhost HTTP server that serves [StreamPipeline] content to media players.
///
/// Each active session is reachable at `/stream/{sessionId}` and supports
/// standard HTTP Range requests (RFC 7233). A lightweight JSON status
/// endpoint is available at `/status/{sessionId}` for UI polling.
class StreamServer {
  /// Creates a [StreamServer].
  StreamServer();

  // -- Internal state -------------------------------------------------------

  HttpServer? _server;
  final Map<String, _ActiveSession> _sessions = {};

  /// Per-session byte counters — tracks how many bytes have been served.
  final Map<String, int> _bytesServed = {};

  /// Per-session last-served byte offset for seek detection.
  final Map<String, int> _lastServedOffset = {};

  // -- Public API -----------------------------------------------------------

  /// The TCP port the server is listening on, or `null` if not started.
  int? get port => _server?.port;

  /// Whether the HTTP server is currently running.
  bool get isRunning => _server != null;

  /// Returns snapshots of all active sessions.
  List<StreamSession> get activeSessions => _sessions.values.map((s) {
        final served = _bytesServed[s.id] ?? 0;
        final total = s.pipeline.totalBytes;
        return StreamSession(
          id: s.id,
          nzbTitle: s.title,
          localUrl: _buildUrl(s.id),
          bytesStreamed: served,
          totalBytes: total,
          state: _deriveState(s.pipeline),
          bytesDownloaded: s.pipeline.bytesDownloaded,
        );
      }).toList(growable: false);

  /// Returns the local URL for [sessionId], or `null` if the session does
  /// not exist or the server is not running.
  String? getSessionUrl(String sessionId) {
    if (!_sessions.containsKey(sessionId) || _server == null) return null;
    return _buildUrl(sessionId);
  }

  /// Registers a new streaming session.
  ///
  /// If the HTTP server is not yet running it is lazily started on
  /// `127.0.0.1` with an OS-assigned ephemeral port. Returns a
  /// [StreamSession] snapshot whose [StreamSession.localUrl] can be
  /// handed to a media player.
  Future<StreamSession> addSession({
    required String sessionId,
    required String title,
    required StreamPipeline pipeline,
  }) async {
    // Ensure the server is running.
    await _ensureServer();

    _sessions[sessionId] = _ActiveSession(
      id: sessionId,
      title: title,
      pipeline: pipeline,
    );
    _bytesServed[sessionId] = 0;
    _lastServedOffset[sessionId] = 0;

    dev.log(
      'StreamServer: session "$sessionId" added – '
      '${pipeline.totalBytes} bytes, '
      'url=${_buildUrl(sessionId)}',
    );

    return StreamSession(
      id: sessionId,
      nzbTitle: title,
      localUrl: _buildUrl(sessionId),
      bytesStreamed: 0,
      totalBytes: pipeline.totalBytes,
      state: _deriveState(pipeline),
      bytesDownloaded: pipeline.bytesDownloaded,
    );
  }

  /// Removes the session identified by [sessionId] and disposes its pipeline.
  ///
  /// If this was the last active session the HTTP server is shut down
  /// automatically.
  Future<void> removeSession(String sessionId) async {
    final session = _sessions.remove(sessionId);
    _bytesServed.remove(sessionId);
    _lastServedOffset.remove(sessionId);

    if (session != null) {
      try {
        await session.pipeline.dispose();
      } catch (e) {
        dev.log('StreamServer: error disposing pipeline for "$sessionId": $e');
      }
    }

    // Auto-shutdown when no sessions remain.
    if (_sessions.isEmpty) {
      await _stopServer();
    }
  }

  /// Shuts down the HTTP server and disposes every active session pipeline.
  Future<void> dispose() async {
    // Dispose all pipelines first.
    final futures = _sessions.values
        .map((s) => s.pipeline.dispose().catchError((_) {}))
        .toList();
    await Future.wait(futures);

    _sessions.clear();
    _bytesServed.clear();
    _lastServedOffset.clear();

    await _stopServer();
  }

  // -- Server lifecycle -----------------------------------------------------

  /// Starts the [HttpServer] on `127.0.0.1` if not already running.
  Future<void> _ensureServer() async {
    if (_server != null) return;

    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0, // OS-assigned port
    );

    dev.log('StreamServer: listening on 127.0.0.1:${_server!.port}');

    // Handle requests in the background — errors are caught per-request.
    unawaited(_server!.forEach(_handleRequest));
  }

  /// Gracefully closes the [HttpServer].
  Future<void> _stopServer() async {
    final server = _server;
    if (server == null) return;
    _server = null;

    try {
      await server.close(force: true);
      dev.log('StreamServer: server stopped');
    } catch (e) {
      dev.log('StreamServer: error stopping server: $e');
    }
  }

  // -- Request routing ------------------------------------------------------

  /// Top-level request dispatcher.
  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;

      if (segments.length == 2 && segments[0] == 'stream') {
        await _handleStreamRequest(request, segments[1]);
      } else if (segments.length == 2 && segments[0] == 'status') {
        await _handleStatusRequest(request, segments[1]);
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found');
        await request.response.close();
      }
    } catch (e, st) {
      dev.log('StreamServer: unhandled error: $e', stackTrace: st);
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // Response may already be committed — best effort.
      }
    }
  }

  // -- /stream/{sessionId} -------------------------------------------------

  /// Serves byte content from the pipeline for the given session.
  ///
  /// Supports:
  /// - Full content (200 OK)
  /// - Single byte-range requests (206 Partial Content)
  /// - HEAD requests (returns headers only)
  Future<void> _handleStreamRequest(
    HttpRequest request,
    String sessionId,
  ) async {
    final session = _sessions[sessionId];
    if (session == null) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Session not found');
      await request.response.close();
      return;
    }

    final pipeline = session.pipeline;

    // Wait for pipeline to become ready (up to 60 seconds).
    if (!pipeline.isReady) {
      var waited = 0;
      while (!pipeline.isReady && waited < 60) {
        await Future<void>.delayed(const Duration(seconds: 1));
        waited++;
        if (!_sessions.containsKey(sessionId)) {
          // Session was removed while waiting.
          request.response
            ..statusCode = HttpStatus.gone
            ..write('Session removed');
          await request.response.close();
          return;
        }
      }
      if (!pipeline.isReady) {
        request.response
          ..statusCode = HttpStatus.serviceUnavailable
          ..headers.set('Retry-After', '5')
          ..write('Pipeline still buffering after 60s');
        await request.response.close();
        return;
      }
    }

    final totalBytes = pipeline.totalBytes;
    final mimeType = pipeline.mimeType ?? _fallbackMimeType;

    // -- Parse Range header -------------------------------------------------
    final rangeHeader = request.headers.value('range');
    var rangeStart = 0;
    var rangeEnd = totalBytes;
    var isRangeRequest = false;

    if (rangeHeader != null) {
      final parsed = _parseRangeHeader(rangeHeader, totalBytes);
      if (parsed != null) {
        rangeStart = parsed.$1;
        rangeEnd = parsed.$2;
        isRangeRequest = true;
      } else {
        // Malformed Range — return 416.
        request.response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set('Content-Range', 'bytes */$totalBytes');
        await request.response.close();
        return;
      }
    }

    final contentLength = rangeEnd - rangeStart;

    // -- Set response headers -----------------------------------------------
    final response = request.response;
    response.headers
      ..set('Content-Type', mimeType)
      ..set('Accept-Ranges', 'bytes')
      ..set('Content-Length', contentLength.toString())
      ..set('Connection', 'keep-alive');

    if (isRangeRequest) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        'Content-Range',
        'bytes $rangeStart-${rangeEnd - 1}/$totalBytes',
      );
    } else {
      response.statusCode = HttpStatus.ok;
    }

    // HEAD requests — send headers only.
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    // -- Seek detection -----------------------------------------------------
    final lastOffset = _lastServedOffset[sessionId] ?? 0;
    final distance = (rangeStart - lastOffset).abs();
    if (distance > _seekThreshold) {
      unawaited(pipeline.seekTo(rangeStart));
    }
    _lastServedOffset[sessionId] = rangeEnd;

    // -- Serve data in chunks -----------------------------------------------
    await _serveChunked(
      response: response,
      pipeline: pipeline,
      sessionId: sessionId,
      start: rangeStart,
      end: rangeEnd,
    );
  }

  /// Writes bytes from [pipeline] to [response] in fixed-size chunks.
  Future<void> _serveChunked({
    required HttpResponse response,
    required StreamPipeline pipeline,
    required String sessionId,
    required int start,
    required int end,
  }) async {
    var offset = start;
    try {
      while (offset < end) {
        final chunkEnd = math.min(offset + _chunkSize, end);
        final bytes = await pipeline.getBytes(offset, chunkEnd);
        if (bytes.isEmpty) break; // Pipeline disposed or EOF.
        response.add(bytes);
        _bytesServed[sessionId] =
            (_bytesServed[sessionId] ?? 0) + bytes.length;
        offset = chunkEnd;
      }
    } catch (e) {
      dev.log('StreamServer: error serving "$sessionId" at offset $offset: $e');
    } finally {
      await response.close();
    }
  }

  // -- /status/{sessionId} -------------------------------------------------

  /// Returns a JSON snapshot of the session's status.
  Future<void> _handleStatusRequest(
    HttpRequest request,
    String sessionId,
  ) async {
    final session = _sessions[sessionId];
    if (session == null) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'Session not found'}));
      await request.response.close();
      return;
    }

    final served = _bytesServed[sessionId] ?? 0;
    final total = session.pipeline.totalBytes;
    final progress = total > 0 ? served / total : 0.0;

    final body = jsonEncode({
      'id': sessionId,
      'title': session.title,
      'state': _deriveState(session.pipeline).name,
      'bytesStreamed': served,
      'bytesDownloaded': session.pipeline.bytesDownloaded,
      'totalBytes': total,
      'progress': double.parse(progress.toStringAsFixed(3)),
    });

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(body);
    await request.response.close();
  }

  // -- Helpers --------------------------------------------------------------

  /// Builds the local stream URL for [sessionId].
  String _buildUrl(String sessionId) =>
      'http://127.0.0.1:${_server!.port}/stream/$sessionId';

  /// Derives a [StreamState] from the current pipeline status.
  StreamState _deriveState(StreamPipeline pipeline) {
    if (!pipeline.isReady) return StreamState.buffering;
    // A pipeline that is ready (has content to serve) is "playing" even if
    // all segments have been downloaded / extraction finished. "stopped"
    // should only be used when the session is explicitly stopped by the user.
    return StreamState.playing;
  }

  /// Parses an HTTP `Range` header value into a `(start, end)` pair where
  /// `end` is exclusive (suitable for [StreamPipeline.getBytes]).
  ///
  /// Supports the single byte-range format `bytes=START-END` and the
  /// open-ended `bytes=START-` form. Returns `null` for unparseable values.
  static (int, int)? _parseRangeHeader(String header, int totalBytes) {
    // Expect format: "bytes=START-END" or "bytes=START-"
    if (!header.startsWith('bytes=')) return null;

    final spec = header.substring(6).trim();
    final dashIndex = spec.indexOf('-');
    if (dashIndex < 0) return null;

    final startStr = spec.substring(0, dashIndex).trim();
    final endStr = spec.substring(dashIndex + 1).trim();

    // Suffix range: "bytes=-500" → last 500 bytes.
    if (startStr.isEmpty) {
      final suffix = int.tryParse(endStr);
      if (suffix == null || suffix <= 0) return null;
      final start = math.max(totalBytes - suffix, 0);
      return (start, totalBytes);
    }

    final start = int.tryParse(startStr);
    if (start == null || start < 0 || start >= totalBytes) return null;

    if (endStr.isEmpty) {
      // Open-ended: "bytes=100-" → from 100 to EOF.
      return (start, totalBytes);
    }

    final end = int.tryParse(endStr);
    if (end == null || end < start) return null;

    // HTTP ranges are inclusive; pipeline.getBytes expects exclusive end.
    return (start, math.min(end + 1, totalBytes));
  }
}
