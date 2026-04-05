/// End-to-end streaming controller for the Usenet binary pipeline.
///
/// Orchestrates the full download-decode-process-cache flow for an NZB
/// document, exposing a byte-stream interface suitable for HTTP range
/// requests (e.g. video playback with seeking).
///
/// Architecture:
/// ```
/// NZB → [Segment Scheduler] → [NntpPool.fetchBatch] → [YencDecoder]
///     → [PostProcessor] → [StreamCache] → byte-stream output
/// ```
///
/// For simple (non-RAR) content the segments map directly to byte ranges
/// and can be served immediately as they arrive. For RAR-archived content
/// the [PostProcessor] buffers internally until extraction completes, then
/// the extracted file is streamed from cache.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'nntp_pool.dart';
import 'nzb_parser.dart';
import 'par2_engine.dart';
import 'post_processor.dart';
import 'rar_extractor.dart';
import 'stream_cache.dart';
import 'yenc_decoder.dart';

// ---------------------------------------------------------------------------
// StreamPipelineEvent
// ---------------------------------------------------------------------------

/// Events emitted by the [StreamPipeline] during download and processing.
///
/// Use exhaustive pattern matching to handle all event types:
///
/// ```dart
/// pipeline.events.listen((event) {
///   switch (event) {
///     case StreamPipelineBuffering():  ...
///     case StreamPipelineReady():      ...
///     case StreamPipelineProgress():   ...
///     case StreamPipelineSeek():       ...
///     case StreamPipelineError():      ...
///     case StreamPipelineDone():       ...
///   }
/// });
/// ```
sealed class StreamPipelineEvent {
  const StreamPipelineEvent();
}

/// Initial buffering phase — emitted while the first segments are fetched.
final class StreamPipelineBuffering extends StreamPipelineEvent {
  /// Creates a [StreamPipelineBuffering] event.
  const StreamPipelineBuffering({required this.percent});

  /// Buffering progress from 0.0 to 1.0.
  final double percent;

  @override
  String toString() =>
      'StreamPipelineBuffering(${(percent * 100).toStringAsFixed(1)}%)';
}

/// Pipeline is ready to serve byte ranges.
final class StreamPipelineReady extends StreamPipelineEvent {
  /// Creates a [StreamPipelineReady] event.
  const StreamPipelineReady({
    required this.totalBytes,
    required this.mimeType,
    required this.filename,
  });

  /// Total content length in bytes.
  final int totalBytes;

  /// Detected MIME type of the primary content file.
  final String? mimeType;

  /// Filename of the primary content file.
  final String filename;

  @override
  String toString() =>
      'StreamPipelineReady($filename, $totalBytes B, $mimeType)';
}

/// Periodic download progress update.
final class StreamPipelineProgress extends StreamPipelineEvent {
  /// Creates a [StreamPipelineProgress] event.
  const StreamPipelineProgress({
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.segmentsFetched,
    required this.totalSegments,
    required this.downloadSpeed,
  });

  /// Bytes downloaded and decoded so far.
  final int bytesDownloaded;

  /// Total expected bytes.
  final int totalBytes;

  /// Number of segments fetched so far.
  final int segmentsFetched;

  /// Total number of segments.
  final int totalSegments;

  /// Current download speed in bytes per second.
  final double downloadSpeed;

  @override
  String toString() =>
      'StreamPipelineProgress($segmentsFetched/$totalSegments, '
      '${(bytesDownloaded / (totalBytes > 0 ? totalBytes : 1) * 100).toStringAsFixed(1)}%, '
      '${(downloadSpeed / 1024).toStringAsFixed(0)} KB/s)';
}

/// Emitted when the pipeline seeks to a new byte position.
final class StreamPipelineSeek extends StreamPipelineEvent {
  /// Creates a [StreamPipelineSeek] event.
  const StreamPipelineSeek({required this.bytePosition});

  /// Target byte offset.
  final int bytePosition;

  @override
  String toString() => 'StreamPipelineSeek($bytePosition)';
}

/// An error occurred during pipeline processing.
final class StreamPipelineError extends StreamPipelineEvent {
  /// Creates a [StreamPipelineError] event.
  const StreamPipelineError({required this.message, this.fatal = false});

  /// Human-readable error description.
  final String message;

  /// Whether this error is fatal (pipeline cannot continue).
  final bool fatal;

  @override
  String toString() => 'StreamPipelineError($message, fatal=$fatal)';
}

/// All segments have been fetched and processed — the content is complete.
final class StreamPipelineDone extends StreamPipelineEvent {
  /// Creates a [StreamPipelineDone] event.
  const StreamPipelineDone();

  @override
  String toString() => 'StreamPipelineDone()';
}

// ---------------------------------------------------------------------------
// _SegmentInfo — internal byte-range → segment mapping
// ---------------------------------------------------------------------------

/// Maps a contiguous byte range to the segment that covers it.
@immutable
class _SegmentInfo {
  const _SegmentInfo({
    required this.index,
    required this.messageId,
    required this.byteStart,
    required this.byteEnd,
    required this.encodedBytes,
  });

  /// Zero-based index into the ordered segment list.
  final int index;

  /// NNTP message-ID for fetching.
  final String messageId;

  /// Inclusive start byte offset within the assembled file.
  final int byteStart;

  /// Exclusive end byte offset within the assembled file.
  final int byteEnd;

  /// Size of the raw (encoded) article as declared in the NZB.
  final int encodedBytes;

  /// Decoded payload size (estimated from the byte range).
  int get decodedBytes => byteEnd - byteStart;
}

// ---------------------------------------------------------------------------
// _FetchPriority — priority ordering for the segment scheduler
// ---------------------------------------------------------------------------

/// Priority levels for the fetch scheduler.
///
/// Lower numeric value = higher priority.
enum _FetchPriority {
  /// Seek-target segments — needed immediately.
  seek(0),

  /// Initial buffering segments.
  buffer(1),

  /// Prefetch-ahead of the current playback position.
  prefetch(2),

  /// Background fill of the remaining segments.
  background(3);

  const _FetchPriority(this.value);

  /// Numeric priority (lower = higher priority).
  final int value;
}

/// Entry in the priority fetch queue.
class _FetchRequest implements Comparable<_FetchRequest> {
  _FetchRequest({
    required this.segmentIndex,
    required this.priority,
  });

  /// Index into the segment map.
  final int segmentIndex;

  /// Current fetch priority.
  _FetchPriority priority;

  @override
  int compareTo(_FetchRequest other) =>
      priority.value.compareTo(other.priority.value);
}

// ---------------------------------------------------------------------------
// StreamPipeline
// ---------------------------------------------------------------------------

/// Central orchestrator connecting NntpPool, YencDecoder, PostProcessor,
/// and StreamCache into a unified streaming pipeline for NZB content.
///
/// ```dart
/// final pipeline = StreamPipeline(
///   pool: nntpPool,
///   cache: streamCache,
/// );
///
/// await pipeline.start(nzbDocument);
///
/// pipeline.events.listen((event) {
///   switch (event) {
///     case StreamPipelineReady(:final totalBytes, :final mimeType):
///       print('Ready: $totalBytes bytes, $mimeType');
///     case StreamPipelineProgress(:final segmentsFetched, :final totalSegments):
///       print('Progress: $segmentsFetched / $totalSegments');
///     // ...
///   }
/// });
///
/// // Serve an HTTP range request
/// final bytes = await pipeline.getBytes(0, 1024 * 1024);
/// ```
class StreamPipeline {
  /// Creates a [StreamPipeline].
  ///
  /// [pool] is the NNTP connection pool for article fetching.
  /// [cache] is the segment/file cache for decoded data.
  /// [prefetchSegments] controls how many segments ahead of the current
  /// position to keep in the fetch queue.
  /// [batchSize] controls how many segments are fetched per batch call.
  StreamPipeline({
    required NntpConnectionPool pool,
    required StreamCache cache,
    this.prefetchSegments = 20,
    this.batchSize = 10,
  })  : _pool = pool,
        _cache = cache;

  final NntpConnectionPool _pool;
  final StreamCache _cache;

  /// Number of segments ahead of the current position to prefetch.
  final int prefetchSegments;

  /// Number of segments per batch fetch call.
  final int batchSize;

  // -- Internal state -------------------------------------------------------

  final StreamController<StreamPipelineEvent> _eventController =
      StreamController<StreamPipelineEvent>.broadcast();

  /// Ordered segment map for the target file.
  final List<_SegmentInfo> _segmentMap = [];

  /// Decoded segment data indexed by segment index.
  final Map<int, Uint8List> _decodedSegments = {};

  /// Set of segment indices currently being fetched.
  final Set<int> _inFlight = {};

  /// Priority queue for the fetch scheduler.
  final SplayTreeSet<_FetchRequest> _fetchQueue =
      SplayTreeSet<_FetchRequest>((a, b) {
    final cmp = a.compareTo(b);
    if (cmp != 0) return cmp;
    return a.segmentIndex.compareTo(b.segmentIndex);
  });

  /// Quick lookup: segmentIndex → _FetchRequest in the queue.
  final Map<int, _FetchRequest> _queuedRequests = {};

  /// The NZB document being processed.
  NzbDocument? _nzb;

  /// The target file entry selected from the NZB.
  NzbFileEntry? _targetFile;

  /// Post-process plan (null until [start] is called).
  PostProcessPlan? _plan;

  /// Cache session identifier.
  String? _cacheSessionId;

  /// Current playback / read position (byte offset).
  int _currentPosition = 0;

  /// Speed tracking: bytes fetched in the current measurement window.
  int _speedBytes = 0;

  /// Speed tracking: start of the current measurement window.
  DateTime _speedWindowStart = DateTime.now();

  /// Current download speed in bytes/second.
  double _currentSpeed = 0;

  /// Whether the pipeline has been started and is ready to serve.
  bool _isReady = false;

  /// Whether all segments have been fetched.
  bool _isComplete = false;

  /// Whether [dispose] has been called.
  bool _disposed = false;

  /// Whether the pipeline is in RAR extraction mode.
  bool _isRarMode = false;

  /// Extracted RAR content (only populated in RAR mode).
  Uint8List? _extractedContent;

  /// Completer completed when initial buffering finishes and [_isReady] is set.
  Completer<void>? _readyCompleter;

  /// Completer signalled when the scheduler loop should wake up.
  Completer<void>? _schedulerWake;

  /// Completers waiting for specific segments to become available.
  final Map<int, List<Completer<void>>> _segmentWaiters = {};

  /// The yEnc decoder instance.
  final YencDecoder _yenc = const YencDecoder();

  // -- Public API -----------------------------------------------------------

  /// Event stream for pipeline state changes and progress.
  Stream<StreamPipelineEvent> get events => _eventController.stream;

  /// Whether the pipeline is ready to serve byte-range requests.
  bool get isReady => _isReady;

  /// Whether all segments have been fetched and processing is complete.
  bool get isComplete => _isComplete;

  /// The NZB document currently being processed, or `null`.
  NzbDocument? get nzb => _nzb;

  /// Total content length in bytes, or 0 if not yet known.
  int get totalBytes {
    if (_isRarMode && _extractedContent != null) {
      return _extractedContent!.length;
    }
    if (_segmentMap.isEmpty) return 0;
    return _segmentMap.last.byteEnd;
  }

  /// Detected MIME type of the primary content file.
  String? get mimeType => _plan?.detectedContentType ?? _targetFile?.detectedContentType;

  /// Active cache session identifier, or `null` if not started.
  String? get cacheSessionId => _cacheSessionId;

  /// Total bytes downloaded from Usenet so far.
  int get bytesDownloaded {
    var total = 0;
    for (final entry in _decodedSegments.values) {
      total += entry.length;
    }
    return total;
  }

  /// Starts the pipeline for the given [nzb] document.
  ///
  /// Selects the target file (largest non-PAR2/non-sample video, or
  /// [targetFile] if explicitly specified), builds the segment map,
  /// initialises the cache session, and begins the fetch loop.
  ///
  /// Emits [StreamPipelineBuffering] events during initial buffering,
  /// then [StreamPipelineReady] when enough data is available to serve.
  Future<void> start(NzbDocument nzb, {String? targetFile}) async {
    if (_disposed) return;

    _nzb = nzb;

    // Analyse the NZB to determine processing strategy.
    // Use stubs for the initial analysis (only needs file classification).
    final analyzeProcessor = PostProcessor(
      yenc: _yenc,
      par2: _createStubPar2(),
      rar: _createStubRar(),
    );
    _plan = analyzeProcessor.analyze(nzb);
    _isRarMode = _plan!.needsRarExtraction;

    // Select the target file.
    _targetFile = _selectTargetFile(nzb, targetFile);
    if (_targetFile == null) {
      _emitError('No suitable content file found in NZB', fatal: true);
      return;
    }

    // Create a cache session.
    try {
      _cacheSessionId =
          await _cache.createSession(nzb.title ?? _targetFile!.filename);
    } catch (e) {
      _emitError('Failed to create cache session: $e', fatal: true);
      return;
    }

    if (_isRarMode) {
      // Create a real processor with actual RAR + PAR2 engines for extraction.
      final processor = PostProcessor(
        yenc: _yenc,
        par2: Par2Engine(),
        rar: RarExtractor(),
      );
      await _startRarPipeline(nzb, processor);
    } else {
      _buildSegmentMap(_targetFile!);
      _seedFetchQueue();

      // Create a completer that the scheduler will complete when buffering
      // finishes and [_isReady] becomes true.
      _readyCompleter = Completer<void>();

      // Start the scheduler in the background.
      unawaited(_runScheduler());

      // Wait for initial buffering to complete (with timeout).
      try {
        await _readyCompleter!.future.timeout(const Duration(seconds: 120));
      } on TimeoutException {
        _emitError('Initial buffering timed out after 120 seconds',
            fatal: true);
        return;
      }
    }
  }

  /// Returns the byte range [start] (inclusive) to [end] (exclusive).
  ///
  /// For non-RAR content this calculates which decoded segments cover
  /// the requested range, waits for any uncached segments, and assembles
  /// the result. For RAR content the extracted file is sliced directly.
  ///
  /// Returns an empty [Uint8List] if the range is invalid.
  Future<Uint8List> getBytes(int start, int end) async {
    if (_disposed || !_isReady) return Uint8List(0);

    final total = totalBytes;
    if (start < 0 || start >= total || end <= start) return Uint8List(0);
    final clampedEnd = end > total ? total : end;

    // RAR mode: slice from extracted content.
    if (_isRarMode) {
      final content = _extractedContent;
      if (content == null) return Uint8List(0);
      return Uint8List.sublistView(content, start, clampedEnd);
    }

    // Direct mode: assemble from decoded segments.
    return _assembleByteRange(start, clampedEnd);
  }

  /// Seeks to [bytePosition], reprioritising the fetch queue so segments
  /// near the seek target are fetched first.
  Future<void> seekTo(int bytePosition) async {
    if (_disposed || _segmentMap.isEmpty) return;

    _currentPosition = bytePosition.clamp(0, totalBytes);
    _emitEvent(StreamPipelineSeek(bytePosition: _currentPosition));

    if (_isRarMode) return; // RAR mode fetches everything anyway.

    // Find the segment containing this byte position.
    final targetIdx = _segmentIndexForByte(_currentPosition);
    if (targetIdx < 0) return;

    // Reprioritise: segments near the seek target get highest priority.
    _reprioritiseFetchQueue(targetIdx);
    _wakeScheduler();
  }

  /// Persists the cached content to [destinationPath].
  ///
  /// Returns the destination path on success, or `null` on failure.
  Future<String?> saveContent(String destinationPath) async {
    final sid = _cacheSessionId;
    if (sid == null) return null;

    try {
      // If we have extracted RAR content, cache it as a file first.
      if (_isRarMode && _extractedContent != null) {
        final filename = _targetFile?.filename ?? 'content';
        await _cache.putFile(sid, filename, _extractedContent!);
      } else if (!_isRarMode && _segmentMap.isNotEmpty) {
        // For direct mode, assemble the full file and cache it.
        final fullData = await _assembleByteRange(0, totalBytes);
        final filename = _targetFile?.filename ?? 'content';
        await _cache.putFile(sid, filename, fullData);
      }
      return await _cache.saveSessionTo(sid, destinationPath);
    } catch (e) {
      _emitError('Failed to save content: $e');
      return null;
    }
  }

  /// Releases all resources and cancels in-flight operations.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    // Complete the ready completer if still pending so start() can return.
    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.completeError(StateError('Pipeline disposed'));
    }

    _fetchQueue.clear();
    _queuedRequests.clear();
    _inFlight.clear();

    // Complete any waiters with errors.
    for (final waiters in _segmentWaiters.values) {
      for (final c in waiters) {
        if (!c.isCompleted) c.completeError(StateError('Pipeline disposed'));
      }
    }
    _segmentWaiters.clear();

    _wakeScheduler(); // Unblock the loop so it can exit.

    // Close the cache session (don't save by default).
    final sid = _cacheSessionId;
    if (sid != null) {
      try {
        await _cache.closeSession(sid);
      } catch (_) {
        // Best-effort.
      }
    }

    await _eventController.close();
  }

  // -----------------------------------------------------------------------
  // Target file selection
  // -----------------------------------------------------------------------

  /// Selects the primary content file from the NZB.
  ///
  /// If [targetFilename] is specified, picks that exact file. Otherwise
  /// selects the largest non-PAR2, non-sample file — preferring video
  /// MIME types.
  NzbFileEntry? _selectTargetFile(NzbDocument nzb, String? targetFilename) {
    if (targetFilename != null) {
      for (final f in nzb.files) {
        if (f.filename == targetFilename) return f;
      }
      return null;
    }

    final candidates = nzb.files
        .where((f) => !f.isPar2 && !f.isSample && !f.isNfo)
        .toList();

    if (candidates.isEmpty) return null;

    // Prefer video files, then largest.
    final videoFiles = candidates
        .where(
            (f) => f.detectedContentType?.startsWith('video/') ?? false)
        .toList();

    if (videoFiles.isNotEmpty) {
      videoFiles.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
      return videoFiles.first;
    }

    // Fall back to the largest file.
    candidates.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
    return candidates.first;
  }

  // -----------------------------------------------------------------------
  // Segment map
  // -----------------------------------------------------------------------

  /// Builds the segment map for [file], assigning byte ranges to each
  /// segment based on the NZB-declared segment sizes.
  ///
  /// The yEnc overhead ratio (~1.5 %) is applied to estimate decoded
  /// sizes from the NZB's encoded byte counts.
  void _buildSegmentMap(NzbFileEntry file) {
    _segmentMap.clear();

    // Sort segments by number to ensure correct order.
    final sorted = List<NzbSegment>.from(file.segments)..sort();

    var byteOffset = 0;
    for (var i = 0; i < sorted.length; i++) {
      final seg = sorted[i];
      // Estimate decoded size: yEnc overhead is ~1–2%, plus NNTP headers.
      // The NZB `bytes` field is the encoded article size including headers.
      // A conservative estimate: decoded ≈ encoded × 0.98, minus ~200 bytes
      // for yEnc/NNTP headers. But since we refine this as segments arrive,
      // we use the raw NZB value as the initial estimate.
      final estimatedDecoded = _estimateDecodedSize(seg.bytes);
      final info = _SegmentInfo(
        index: i,
        messageId: seg.messageId,
        byteStart: byteOffset,
        byteEnd: byteOffset + estimatedDecoded,
        encodedBytes: seg.bytes,
      );
      _segmentMap.add(info);
      byteOffset += estimatedDecoded;
    }
  }

  /// Estimates decoded segment size from encoded article size.
  ///
  /// yEnc articles have ~200 bytes of header/trailer overhead, and the
  /// payload has ~1.5 % encoding expansion.
  static int _estimateDecodedSize(int encodedBytes) {
    if (encodedBytes <= 0) return 0;
    // Subtract header overhead, then remove ~1.5% encoding expansion.
    final payload = math.max(0, encodedBytes - 200);
    return (payload * 0.985).round();
  }

  /// Rebuilds byte offsets in the segment map using actual decoded sizes
  /// for segments that have been fetched, keeping estimates for the rest.
  void _refreshByteOffsets() {
    var offset = 0;
    for (var i = 0; i < _segmentMap.length; i++) {
      final old = _segmentMap[i];
      final decoded = _decodedSegments[i];
      final size = decoded?.length ?? old.decodedBytes;
      _segmentMap[i] = _SegmentInfo(
        index: i,
        messageId: old.messageId,
        byteStart: offset,
        byteEnd: offset + size,
        encodedBytes: old.encodedBytes,
      );
      offset += size;
    }
  }

  /// Returns the segment index containing [byteOffset], or -1.
  int _segmentIndexForByte(int byteOffset) {
    // Binary search on the segment map.
    var lo = 0;
    var hi = _segmentMap.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final seg = _segmentMap[mid];
      if (byteOffset < seg.byteStart) {
        hi = mid - 1;
      } else if (byteOffset >= seg.byteEnd) {
        lo = mid + 1;
      } else {
        return mid;
      }
    }
    return -1;
  }

  /// Returns all segment indices whose byte range overlaps [start, end).
  List<int> _segmentIndicesForRange(int start, int end) {
    final result = <int>[];
    for (var i = 0; i < _segmentMap.length; i++) {
      final seg = _segmentMap[i];
      if (seg.byteEnd <= start) continue;
      if (seg.byteStart >= end) break;
      result.add(i);
    }
    return result;
  }

  // -----------------------------------------------------------------------
  // Fetch scheduler
  // -----------------------------------------------------------------------

  /// Seeds the fetch queue with the initial buffering segments.
  void _seedFetchQueue() {
    final initialCount = math.min(prefetchSegments, _segmentMap.length);
    for (var i = 0; i < initialCount; i++) {
      _enqueueSegment(i, _FetchPriority.buffer);
    }
    // Queue the rest as background.
    for (var i = initialCount; i < _segmentMap.length; i++) {
      _enqueueSegment(i, _FetchPriority.background);
    }
  }

  /// Adds a segment to the fetch queue if not already fetched or in-flight.
  void _enqueueSegment(int index, _FetchPriority priority) {
    if (_decodedSegments.containsKey(index)) return;
    if (_inFlight.contains(index)) return;

    final existing = _queuedRequests[index];
    if (existing != null) {
      // Upgrade priority if needed.
      if (priority.value < existing.priority.value) {
        _fetchQueue.remove(existing);
        existing.priority = priority;
        _fetchQueue.add(existing);
      }
      return;
    }

    final request = _FetchRequest(segmentIndex: index, priority: priority);
    _fetchQueue.add(request);
    _queuedRequests[index] = request;
  }

  /// Reprioritises the fetch queue around [targetIndex] after a seek.
  void _reprioritiseFetchQueue(int targetIndex) {
    // Rebuild the queue with new priorities.
    final pending = _fetchQueue.toList();
    _fetchQueue.clear();
    _queuedRequests.clear();

    for (final req in pending) {
      final distance = (req.segmentIndex - targetIndex).abs();
      final _FetchPriority newPriority;
      if (distance == 0) {
        newPriority = _FetchPriority.seek;
      } else if (distance <= prefetchSegments) {
        newPriority = _FetchPriority.prefetch;
      } else {
        newPriority = _FetchPriority.background;
      }
      req.priority = newPriority;
      _fetchQueue.add(req);
      _queuedRequests[req.segmentIndex] = req;
    }
  }

  /// Wakes the scheduler loop if it is waiting for work.
  void _wakeScheduler() {
    final wake = _schedulerWake;
    if (wake != null && !wake.isCompleted) {
      wake.complete();
    }
  }

  /// Main scheduler loop — runs until all segments are fetched or
  /// the pipeline is disposed.
  Future<void> _runScheduler() async {
    final initialBufferTarget =
        math.min(prefetchSegments, _segmentMap.length);
    var bufferedCount = 0;
    var consecutiveFailures = 0;
    const maxConsecutiveFailures = 10;

    while (!_disposed && _fetchQueue.isNotEmpty) {
      // Collect the next batch.
      final batch = _collectBatch();
      if (batch.isEmpty) {
        // Wait for a wake signal (e.g. seek or new segments needed).
        _schedulerWake = Completer<void>();
        await _schedulerWake!.future.catchError((_) {});
        _schedulerWake = null;
        continue;
      }


      // Mark as in-flight.
      for (final idx in batch) {
        _inFlight.add(idx);
      }

      // Build message ID list.
      final messageIds =
          batch.map((idx) => _segmentMap[idx].messageId).toList();

      try {
        final results = await _pool.fetchBatch(messageIds);
        consecutiveFailures = 0; // Reset on success.

        for (var i = 0; i < batch.length; i++) {
          final segIdx = batch[i];
          _inFlight.remove(segIdx);

          final raw = results[i];
          if (raw.isEmpty) {
            _emitError(
              'Failed to fetch segment ${_segmentMap[segIdx].messageId}',
            );
            continue;
          }

          // Decode yEnc.
          try {
            final decoded = _yenc.decodePart(raw);
            _decodedSegments[segIdx] = decoded.data;

            // Cache the decoded segment.
            final sid = _cacheSessionId;
            if (sid != null) {
              // Fire-and-forget cache write.
              unawaited(_cache
                  .putSegment(sid, _segmentMap[segIdx].messageId, decoded.data)
                  .catchError((_) {}));
            }

            // Update speed tracking.
            _speedBytes += decoded.data.length;
            _updateSpeed();

            // Notify any waiters.
            _notifySegmentWaiters(segIdx);

            if (!decoded.checksumValid) {
              _emitError(
                'Checksum mismatch for segment ${_segmentMap[segIdx].messageId}',
              );
            }
          } on FormatException catch (e) {
            _emitError('yEnc decode failed for segment '
                '${_segmentMap[segIdx].messageId}: ${e.message}');
          }
        }
      } catch (e) {
        // Batch fetch failed — re-queue segments.
        for (final idx in batch) {
          _inFlight.remove(idx);
          _enqueueSegment(idx, _FetchPriority.prefetch);
        }
        consecutiveFailures++;
        _emitError('Batch fetch failed ($consecutiveFailures/$maxConsecutiveFailures): $e');

        if (consecutiveFailures >= maxConsecutiveFailures) {
          _emitError(
            'Too many consecutive failures — aborting stream. '
            'Check provider credentials and connectivity.',
            fatal: true,
          );
          return;
        }

        // Exponential back-off before retrying.
        final backoff = Duration(seconds: math.min(2 * consecutiveFailures, 10));
        await Future<void>.delayed(backoff);
        continue;
      }

      // Refresh byte offsets with actual decoded sizes.
      _refreshByteOffsets();

      // Update buffering/progress state.
      bufferedCount = _decodedSegments.length;

      if (!_isReady) {
        // Emit buffering progress.
        final pct = initialBufferTarget > 0
            ? bufferedCount / initialBufferTarget
            : 1.0;
        _emitEvent(StreamPipelineBuffering(
          percent: pct.clamp(0.0, 1.0),
        ));

        if (bufferedCount >= initialBufferTarget) {
          _isReady = true;
          _readyCompleter?.complete();
          _emitEvent(StreamPipelineReady(
            totalBytes: totalBytes,
            mimeType: mimeType,
            filename: _targetFile?.filename ?? 'unknown',
          ));
        }
      }

      // Emit progress.
      _emitEvent(StreamPipelineProgress(
        bytesDownloaded: _decodedSegments.values
            .fold<int>(0, (sum, d) => sum + d.length),
        totalBytes: totalBytes,
        segmentsFetched: _decodedSegments.length,
        totalSegments: _segmentMap.length,
        downloadSpeed: _currentSpeed,
      ));
    }

    // All segments fetched.
    if (!_disposed && _decodedSegments.length >= _segmentMap.length) {
      _isComplete = true;
      _emitEvent(const StreamPipelineDone());
    }
  }

  /// Collects the next batch of segment indices to fetch.
  List<int> _collectBatch() {
    final batch = <int>[];
    final toRemove = <_FetchRequest>[];

    for (final req in _fetchQueue) {
      if (batch.length >= batchSize) break;
      // Skip already-fetched or in-flight segments.
      if (_decodedSegments.containsKey(req.segmentIndex) ||
          _inFlight.contains(req.segmentIndex)) {
        toRemove.add(req);
        continue;
      }
      batch.add(req.segmentIndex);
      toRemove.add(req);
    }

    for (final req in toRemove) {
      _fetchQueue.remove(req);
      _queuedRequests.remove(req.segmentIndex);
    }

    return batch;
  }

  // -----------------------------------------------------------------------
  // Byte assembly
  // -----------------------------------------------------------------------

  /// Assembles a contiguous byte range from decoded segments.
  ///
  /// Waits up to 30 seconds for each missing segment before timing out.
  Future<Uint8List> _assembleByteRange(int start, int end) async {
    final segIndices = _segmentIndicesForRange(start, end);
    if (segIndices.isEmpty) return Uint8List(0);

    // Ensure all needed segments are available.
    for (final idx in segIndices) {
      if (!_decodedSegments.containsKey(idx)) {
        // Boost priority for this segment.
        _enqueueSegment(idx, _FetchPriority.seek);
        _wakeScheduler();

        // Wait for it (with timeout).
        await _waitForSegment(idx).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            _emitError('Timeout waiting for segment $idx');
          },
        );
      }
    }

    // Calculate output size.
    final outputSize = end - start;
    final result = Uint8List(outputSize);
    var written = 0;

    for (final idx in segIndices) {
      final seg = _segmentMap[idx];
      final data = _decodedSegments[idx];
      if (data == null) continue;

      // Calculate the overlap between the requested range and this segment.
      final segStart = math.max(start, seg.byteStart);
      final segEnd = math.min(end, seg.byteEnd);
      final srcOffset = segStart - seg.byteStart;
      final length = segEnd - segStart;

      if (length <= 0 || srcOffset >= data.length) continue;

      final copyLen = math.min(length, data.length - srcOffset);
      result.setRange(written, written + copyLen, data, srcOffset);
      written += copyLen;
    }

    // Return exactly the bytes we assembled (may be less if segments
    // were unavailable).
    if (written < outputSize) {
      return Uint8List.sublistView(result, 0, written);
    }
    return result;
  }

  /// Returns a future that completes when segment [index] is decoded.
  Future<void> _waitForSegment(int index) {
    if (_decodedSegments.containsKey(index)) {
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _segmentWaiters.putIfAbsent(index, () => []).add(completer);
    return completer.future;
  }

  /// Notifies all waiters that segment [index] is now available.
  void _notifySegmentWaiters(int index) {
    final waiters = _segmentWaiters.remove(index);
    if (waiters == null) return;
    for (final c in waiters) {
      if (!c.isCompleted) c.complete();
    }
  }

  // -----------------------------------------------------------------------
  // RAR pipeline
  // -----------------------------------------------------------------------

  /// Runs the full fetch-decode-extract pipeline for RAR content.
  ///
  /// RAR archives require all volume parts to be complete before
  /// extraction can begin, so this fetches everything, then feeds
  /// segments through the [PostProcessor], and finally caches the
  /// extracted content.
  Future<void> _startRarPipeline(
    NzbDocument nzb,
    PostProcessor processor,
  ) async {
    _emitEvent(const StreamPipelineBuffering(percent: 0));

    // Collect all content file segments (RAR parts + PAR2).
    final allFiles = [...nzb.contentFiles, ...nzb.par2Files];
    final allSegments = <_RarSegmentTask>[];
    for (final file in allFiles) {
      final sorted = List<NzbSegment>.from(file.segments)..sort();
      for (final seg in sorted) {
        allSegments.add(_RarSegmentTask(
          filename: file.filename,
          segmentNumber: seg.number,
          messageId: seg.messageId,
        ));
      }
    }

    final totalSegs = allSegments.length;
    var fetchedCount = 0;

    // Stream controller that feeds DecodedSegments to PostProcessor.
    final segmentStream = StreamController<DecodedSegment>();

    // Start post-processing in the background.
    final postEvents = processor.process(nzb, segmentStream.stream);
    final extractedChunks = <Uint8List>[];
    String? extractedFilename;
    String? extractedMimeType;

    // Listen to post-process events.
    final postProcessDone = Completer<void>();
    var hadFatalError = false;
    final postSub = postEvents.listen(
      (event) {
        switch (event) {
          case PostProcessFileData(:final filename, :final data, :final mimeType):
            extractedChunks.add(data);
            extractedFilename ??= filename;
            extractedMimeType ??= mimeType;
          case PostProcessComplete():
            if (!postProcessDone.isCompleted) postProcessDone.complete();
          case PostProcessError(:final message, :final fatal):
            _emitError('Post-processing: $message', fatal: false);
            if (fatal) hadFatalError = true;
            // Don't abort — PAR2 verification failures shouldn't block
            // RAR extraction. Let the stream complete naturally.
          case PostProcessProgress(:final percent):
            _emitEvent(StreamPipelineBuffering(percent: percent * 0.5 + 0.5));
          case PostProcessAnalyzing() ||
               PostProcessFileComplete() ||
               PostProcessVerifying() ||
               PostProcessRepairing() ||
               PostProcessExtracting():
            break; // Informational — not forwarded.
        }
      },
      onError: (Object e) {
        if (!postProcessDone.isCompleted) {
          postProcessDone.completeError(e);
        }
      },
      onDone: () {
        if (!postProcessDone.isCompleted) postProcessDone.complete();
      },
    );

    // Fetch all segments in batches.
    for (var i = 0; i < totalSegs; i += batchSize) {
      if (_disposed) break;

      final batchEnd = math.min(i + batchSize, totalSegs);
      final batchTasks = allSegments.sublist(i, batchEnd);
      final messageIds = batchTasks.map((t) => t.messageId).toList();

      try {
        final results = await _pool.fetchBatch(messageIds);

        for (var j = 0; j < batchTasks.length; j++) {
          final task = batchTasks[j];
          final raw = results[j];
          if (raw.isEmpty) {
            _emitError('Failed to fetch segment ${task.messageId}');
            continue;
          }

          try {
            final decoded = _yenc.decodePart(raw);
            segmentStream.add(DecodedSegment(
              filename: task.filename,
              segmentNumber: task.segmentNumber,
              data: decoded.data,
              checksumValid: decoded.checksumValid,
            ));

            fetchedCount++;
            _speedBytes += decoded.data.length;
            _updateSpeed();
          } on FormatException catch (e) {
            _emitError('yEnc decode failed: ${e.message}');
          }
        }
      } catch (e) {
        _emitError('Batch fetch failed: $e');
      }

      // Emit buffering progress (first 50% is fetching).
      final pct = totalSegs > 0 ? fetchedCount / totalSegs : 1.0;
      _emitEvent(StreamPipelineBuffering(percent: pct * 0.5));

      _emitEvent(StreamPipelineProgress(
        bytesDownloaded: _speedBytes,
        totalBytes: nzb.totalBytes,
        segmentsFetched: fetchedCount,
        totalSegments: totalSegs,
        downloadSpeed: _currentSpeed,
      ));
    }

    // Close the segment stream to signal completion to PostProcessor.
    await segmentStream.close();

    // Wait for post-processing to finish.
    try {
      await postProcessDone.future.timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          _emitError('Post-processing timed out', fatal: true);
        },
      );
    } catch (e) {
      _emitError('Post-processing failed: $e', fatal: true);
      await postSub.cancel();
      return;
    }

    await postSub.cancel();

    // Assemble extracted content.
    if (extractedChunks.isNotEmpty) {
      var totalLen = 0;
      for (final chunk in extractedChunks) {
        totalLen += chunk.length;
      }
      final assembled = Uint8List(totalLen);
      var offset = 0;
      for (final chunk in extractedChunks) {
        assembled.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      _extractedContent = assembled;

      // Cache the extracted file.
      final sid = _cacheSessionId;
      if (sid != null && extractedFilename != null) {
        try {
          await _cache.putFile(sid, extractedFilename!, assembled);
        } catch (_) {
          // Best-effort cache.
        }
      }
    }

    _isReady = true;
    _isComplete = true;

    _emitEvent(StreamPipelineReady(
      totalBytes: totalBytes,
      mimeType: extractedMimeType ?? mimeType,
      filename: extractedFilename ?? _targetFile?.filename ?? 'unknown',
    ));
    _emitEvent(const StreamPipelineDone());
  }

  // -----------------------------------------------------------------------
  // Speed tracking
  // -----------------------------------------------------------------------

  /// Updates the rolling download speed estimate.
  void _updateSpeed() {
    final now = DateTime.now();
    final elapsed = now.difference(_speedWindowStart);
    if (elapsed.inMilliseconds >= 1000) {
      _currentSpeed = _speedBytes / (elapsed.inMilliseconds / 1000.0);
      _speedBytes = 0;
      _speedWindowStart = now;
    }
  }

  // -----------------------------------------------------------------------
  // Event helpers
  // -----------------------------------------------------------------------

  /// Emits an event on the public stream.
  void _emitEvent(StreamPipelineEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  /// Emits an error event.
  void _emitError(String message, {bool fatal = false}) {
    _emitEvent(StreamPipelineError(message: message, fatal: fatal));
  }

  // -----------------------------------------------------------------------
  // Stubs for PostProcessor dependencies
  // -----------------------------------------------------------------------

  /// Creates a minimal [Par2Engine] stub for analysis-only use.
  ///
  /// The actual PAR2 verification/repair is handled inside the RAR
  /// pipeline's [PostProcessor.process] call which owns its own
  /// engine instance.
  static Par2Engine _createStubPar2() => _StubPar2Engine();

  /// Creates a minimal [RarExtractor] stub for analysis-only use.
  static RarExtractor _createStubRar() => _StubRarExtractor();
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Lightweight task descriptor for RAR segment fetching.
@immutable
class _RarSegmentTask {
  const _RarSegmentTask({
    required this.filename,
    required this.segmentNumber,
    required this.messageId,
  });

  final String filename;
  final int segmentNumber;
  final String messageId;
}

/// Stub [Par2Engine] that satisfies the [PostProcessor] constructor
/// when only [PostProcessor.analyze] is needed.
class _StubPar2Engine implements Par2Engine {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'Par2Engine.${invocation.memberName} — stub only',
      );
}

/// Stub [RarExtractor] that satisfies the [PostProcessor] constructor
/// when only [PostProcessor.analyze] is needed.
class _StubRarExtractor implements RarExtractor {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'RarExtractor.${invocation.memberName} — stub only',
      );
}
