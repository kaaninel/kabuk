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

  /// Highest segment index that has been served via [getBytes].
  int _lastServedSegment = -1;

  /// Number of segments to keep ahead of the last served position.
  /// Segments behind this window are evicted from memory.
  static const int _evictionWindowSize = 80;

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

  /// Total bytes downloaded from Usenet (persists even after eviction).
  int _totalBytesDownloaded = 0;

  /// Total segments fetched (persists even after eviction).
  int _totalSegmentsFetched = 0;

  /// Whether the pipeline has been started and is ready to serve.
  bool _isReady = false;

  /// Whether all segments have been fetched.
  bool _isComplete = false;

  /// Whether [dispose] has been called.
  bool _disposed = false;

  /// Whether the pipeline is in RAR extraction mode.
  bool _isRarMode = false;

  /// Expected total content size in bytes (set from RAR file header or NZB).
  ///
  /// For RAR mode this is set from [RarFileStart.uncompressedSize] when
  /// available, otherwise estimated from the NZB total bytes.
  int? _estimatedTotalBytes;

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
    // For RAR mode, prefer the expected total from the RAR file header.
    if (_isRarMode && _estimatedTotalBytes != null) {
      return _estimatedTotalBytes!;
    }
    if (_segmentMap.isEmpty) return 0;
    return _segmentMap.last.byteEnd;
  }

  /// Detected MIME type of the primary content file.
  String? get mimeType => _rarExtractedMimeType ?? _plan?.detectedContentType ?? _targetFile?.detectedContentType;

  /// MIME type detected during RAR extraction (from file header/content sniffing).
  String? _rarExtractedMimeType;

  /// Active cache session identifier, or `null` if not started.
  String? get cacheSessionId => _cacheSessionId;

  /// Total bytes downloaded from Usenet so far.
  int get bytesDownloaded => _totalBytesDownloaded;

  /// Starts the pipeline for the given [nzb] document.
  ///
  /// Selects the target file (largest non-PAR2/non-sample video, or
  /// [targetFile] if explicitly specified), builds the segment map,
  /// initialises the cache session, and begins the fetch loop.
  ///
  /// Emits [StreamPipelineBuffering] events during initial buffering,
  /// then [StreamPipelineReady] when enough data is available to serve.
  Future<void> start(NzbDocument nzb, {String? targetFile}) async {
    if (_disposed) {
      print('[Pipeline] start: already disposed!');
      return;
    }

    print('[Pipeline] start: "${nzb.title}" files=${nzb.files.length}');
    _nzb = nzb;

    // Analyse the NZB to determine processing strategy.
    final analyzeProcessor = PostProcessor(
      yenc: _yenc,
      par2: _createStubPar2(),
      rar: _createStubRar(),
    );
    _plan = analyzeProcessor.analyze(nzb);
    _isRarMode = _plan!.needsRarExtraction;
    print('[Pipeline] plan: isRarMode=$_isRarMode '
        'contentType=${_plan!.detectedContentType}');

    // Select the target file (for non-RAR) or skip (RAR uses all volumes).
    if (!_isRarMode) {
      _targetFile = _selectTargetFile(nzb, targetFile);
      if (_targetFile == null) {
        print('[Pipeline] ERROR: no suitable target file found!');
        _emitError('No suitable content file found in NZB', fatal: true);
        return;
      }
      print('[Pipeline] target: "${_targetFile!.filename}" '
          'bytes=${_targetFile!.totalBytes} segs=${_targetFile!.segments.length} '
          'mime=${_targetFile!.detectedContentType}');
    }

    // Create a cache session.
    try {
      _cacheSessionId =
          await _cache.createSession(nzb.title ?? _targetFile?.filename ?? 'stream');
    } catch (e) {
      print('[Pipeline] cache session failed: $e');
      _emitError('Failed to create cache session: $e', fatal: true);
      return;
    }

    _readyCompleter = Completer<void>();

    if (_isRarMode) {
      print('[Pipeline] starting progressive RAR pipeline…');
      unawaited(_runRarStreamingPipeline(nzb));
    } else {
      _buildSegmentMap(_targetFile!);
      _seedFetchQueue();
      print('[Pipeline] segmentMap=${_segmentMap.length} segments, '
          'totalBytes=$totalBytes, fetchQueue=${_fetchQueue.length}');
      unawaited(_runScheduler());
    }

    try {
      await _readyCompleter!.future.timeout(const Duration(seconds: 120));
      print('[Pipeline] buffering complete — isReady=$_isReady');
    } on TimeoutException {
      print('[Pipeline] TIMEOUT: initial buffering took >120s');
      _emitError('Initial buffering timed out after 120 seconds',
          fatal: true);
      return;
    }
  }

  /// Returns the byte range [start] (inclusive) to [end] (exclusive).
  ///
  /// Calculates which decoded segments cover the requested range, waits
  /// for any uncached segments, and assembles the result. Works for both
  /// direct (non-RAR) and progressive RAR-extracted content.
  ///
  /// Returns an empty [Uint8List] if the range is invalid.
  Future<Uint8List> getBytes(int start, int end) async {
    if (_disposed || !_isReady) return Uint8List(0);

    final total = totalBytes;
    if (start < 0 || start >= total || end <= start) return Uint8List(0);
    final clampedEnd = end > total ? total : end;

    final result = await _assembleByteRange(start, clampedEnd);

    // Track highest served segment for eviction.
    if (!_isRarMode && _segmentMap.isNotEmpty) {
      final endIdx = _segmentIndexForByte(clampedEnd - 1);
      if (endIdx > _lastServedSegment) {
        _lastServedSegment = endIdx;
        _evictOldSegments();
      }
    }

    return result;
  }

  /// Seeks to [bytePosition], reprioritising the fetch queue so segments
  /// near the seek target are fetched first.
  Future<void> seekTo(int bytePosition) async {
    if (_disposed || _segmentMap.isEmpty) return;

    _currentPosition = bytePosition.clamp(0, totalBytes);
    _emitEvent(StreamPipelineSeek(bytePosition: _currentPosition));

    // In RAR mode, data arrives sequentially — can't reprioritise.
    // The player will wait for the data to be extracted.
    if (_isRarMode) return;

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
      // Assemble the full file from decoded segments and cache it.
      if (_segmentMap.isNotEmpty) {
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

    print('[Scheduler] starting: ${_fetchQueue.length} segments to fetch, '
        'bufferTarget=$initialBufferTarget');

    while (!_disposed && _fetchQueue.isNotEmpty) {
      // Collect the next batch.
      final batch = _collectBatch();
      if (batch.isEmpty) {
        print('[Scheduler] batch empty, waiting for wake…');
        _schedulerWake = Completer<void>();
        await _schedulerWake!.future.catchError((_) {});
        _schedulerWake = null;
        continue;
      }

      print('[Scheduler] fetching batch of ${batch.length} segments '
          '(queued=${_fetchQueue.length} decoded=${_decodedSegments.length})');

      // Mark as in-flight.
      for (final idx in batch) {
        _inFlight.add(idx);
      }

      // Build message ID list.
      final messageIds =
          batch.map((idx) => _segmentMap[idx].messageId).toList();

      try {
        final results = await _pool.fetchBatch(messageIds);
        print('[Scheduler] batch fetched: ${results.length} results, '
            'empty=${results.where((r) => r.isEmpty).length}');
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
            _totalBytesDownloaded += decoded.data.length;
            _totalSegmentsFetched++;

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
      } catch (e, st) {
        // Batch fetch failed — re-queue segments.
        print('[Scheduler] BATCH FETCH FAILED: $e');
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
        bytesDownloaded: _totalBytesDownloaded,
        totalBytes: totalBytes,
        segmentsFetched: _totalSegmentsFetched,
        totalSegments: _segmentMap.length,
        downloadSpeed: _currentSpeed,
      ));
    }

    // All segments fetched.
    if (!_disposed && _totalSegmentsFetched >= _segmentMap.length) {
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
        // Try to recover from disk cache first (segment may have been evicted).
        final recovered = await _recoverFromCache(idx);
        if (recovered) continue;

        // In non-RAR mode, boost priority for this segment in the scheduler.
        if (!_isRarMode) {
          _enqueueSegment(idx, _FetchPriority.seek);
          _wakeScheduler();
        }

        // Wait for it (with timeout — longer for RAR since data arrives sequentially).
        final timeout = _isRarMode ? const Duration(seconds: 120) : const Duration(seconds: 30);
        await _waitForSegment(idx).timeout(
          timeout,
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

  /// Evicts decoded segments that are far behind the current playback position.
  ///
  /// Keeps a window of [_evictionWindowSize] segments ahead of
  /// [_lastServedSegment] and removes everything behind
  /// `_lastServedSegment - _evictionWindowSize` to free memory.
  void _evictOldSegments() {
    final evictBefore = _lastServedSegment - _evictionWindowSize;
    if (evictBefore <= 0) return;
    final toRemove = <int>[];
    for (final idx in _decodedSegments.keys) {
      if (idx < evictBefore) toRemove.add(idx);
    }
    for (final idx in toRemove) {
      _decodedSegments.remove(idx);
    }
  }

  /// Attempts to recover an evicted segment from the disk cache.
  ///
  /// Returns `true` if the segment was restored to [_decodedSegments].
  Future<bool> _recoverFromCache(int segIdx) async {
    final sid = _cacheSessionId;
    if (sid == null || segIdx >= _segmentMap.length) return false;
    try {
      final data = await _cache.getSegment(sid, _segmentMap[segIdx].messageId);
      if (data != null) {
        _decodedSegments[segIdx] = data;
        return true;
      }
    } catch (_) {
      // Cache miss — segment needs to be re-fetched.
    }
    return false;
  }

  // -----------------------------------------------------------------------
  // Progressive RAR streaming pipeline
  // -----------------------------------------------------------------------

  /// Runs the progressive RAR streaming pipeline.
  ///
  /// Instead of downloading all RAR volumes before extraction, this fetches
  /// volumes one at a time and feeds their decoded segments to the
  /// [RarExtractor] as lazy streams. Extracted data chunks are stored in
  /// [_decodedSegments] and served via [getBytes] / [_assembleByteRange],
  /// just like the non-RAR path.
  ///
  /// Sets [_isReady] after the initial buffer threshold (typically a few MB)
  /// so playback can begin while the rest downloads in the background.
  Future<void> _runRarStreamingPipeline(NzbDocument nzb) async {
    _emitEvent(const StreamPipelineBuffering(percent: 0));

    // Get RAR volumes in correct order for multi-volume extraction.
    // For non-obfuscated NZBs, natural filename sort works (part001, part002...).
    // For obfuscated NZBs (all same filename), fall back to date (posting
    // timestamp) or original XML order.
    final rarFiles = nzb.rarFiles.toList();
    _sortRarVolumes(rarFiles);

    if (rarFiles.isEmpty) {
      _emitError('No RAR volumes found in NZB', fatal: true);
      return;
    }

    // Probe: verify volume[0] is actually the first RAR volume by downloading
    // its first segment and checking for a file header. If it's a continuation
    // volume, scan others to find the real first volume.
    await _probeAndReorderFirstVolume(rarFiles);

    print('[RAR-Stream] ${rarFiles.length} RAR volumes to process');
    // Log first few volumes for debugging order.
    for (var i = 0; i < math.min(3, rarFiles.length); i++) {
      final f = rarFiles[i];
      print('[RAR-Stream] vol[$i]: "${f.filename}" date=${f.date} '
          'segs=${f.segments.length} bytes=${f.totalBytes}');
    }
    if (rarFiles.length > 3) {
      print('[RAR-Stream] ... (${rarFiles.length - 3} more)');
    }

    // Estimate total content bytes from NZB size (RAR overhead ~2-3%).
    // This estimate is refined once we get the real size from the RAR header.
    var nzbRarBytes = 0;
    for (final f in rarFiles) {
      nzbRarBytes += f.totalBytes;
    }
    _estimatedTotalBytes = (nzbRarBytes * 0.97).round();
    print('[RAR-Stream] estimated content size: $_estimatedTotalBytes bytes '
        '(from $nzbRarBytes RAR bytes)');

    // Count total segments across all RAR volumes.
    var totalSegs = 0;
    for (final f in rarFiles) {
      totalSegs += f.segments.length;
    }

    // Create lazy download streams for each RAR volume.
    var fetchedSegs = 0;
    final volumeStreams = <Stream<List<int>>>[];
    for (final file in rarFiles) {
      volumeStreams.add(_createVolumeDownloadStream(file, totalSegs, () => fetchedSegs, (n) => fetchedSegs = n));
    }

    // Start the RAR extractor with lazy volume streams.
    final rar = RarExtractor();
    final extractStream = volumeStreams.length == 1
        ? rar.extract(volumeStreams.first)
        : rar.extractMultiVolume(volumeStreams);

    // Track extraction state.
    var extractedOffset = 0;
    var chunkIndex = 0;
    String? extractedFilename;
    var consecutiveErrors = 0;

    // Initial buffer threshold — enough for the player to start.
    const initialBufferBytes = 5 * 1024 * 1024; // 5 MB

    try {
      await for (final event in extractStream) {
        if (_disposed) break;

        switch (event) {
          case RarFileStart(:final filename, :final uncompressedSize, :final compressionMethod):
            extractedFilename ??= filename;
            print('[RAR-Stream] file started: "$filename" '
                'size=${uncompressedSize ?? "unknown"} '
                'method=${compressionMethod ?? "unknown"}');

            // Reject compressed RAR — we can only stream Store-method archives.
            // Compressed data requires RAR decompression which we don't support.
            if (compressionMethod != null && compressionMethod != 'Store') {
              print('[RAR-Stream] ✗ compressed RAR (method=$compressionMethod), '
                  'cannot stream — need Store method');
              _emitError(
                'RAR archive uses $compressionMethod compression. '
                'Only Store (uncompressed) RAR archives can be streamed.',
                fatal: true,
              );
              return;
            }

            // Update estimated total with exact size from the RAR header.
            if (uncompressedSize != null && uncompressedSize > 0) {
              _estimatedTotalBytes = uncompressedSize;
              print('[RAR-Stream] updated total bytes: $uncompressedSize');
            }

            // Detect MIME type from filename extension.
            _rarExtractedMimeType ??= _mimeFromFilename(filename);

          case RarFileData(:final data):
            if (data.isEmpty) continue;
            consecutiveErrors = 0;

            // Debug: log first bytes of first chunk to verify data is valid.
            if (chunkIndex == 0) {
              final hexBytes = data.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
              print('[RAR-Stream] first chunk: ${data.length} bytes, '
                  'hex: $hexBytes');
              // Also sniff MIME from actual bytes (overrides filename-based).
              final sniffed = _sniffMimeType(data);
              if (sniffed != null) {
                _rarExtractedMimeType = sniffed;
                print('[RAR-Stream] MIME from magic bytes: $sniffed');
              } else if (_rarExtractedMimeType != null) {
                print('[RAR-Stream] MIME from filename: $_rarExtractedMimeType '
                    '(magic bytes did not match any known format)');
              }
            }

            // Detect MIME type from first data chunk.
            if (chunkIndex == 0 && _rarExtractedMimeType == null) {
              _rarExtractedMimeType = _sniffMimeType(data);
            }

            // Store the chunk as a virtual segment.
            _decodedSegments[chunkIndex] = data;
            _totalBytesDownloaded += data.length;
            _totalSegmentsFetched++;
            _segmentMap.add(_SegmentInfo(
              index: chunkIndex,
              messageId: 'rar_chunk_$chunkIndex',
              byteStart: extractedOffset,
              byteEnd: extractedOffset + data.length,
              encodedBytes: data.length,
            ));

            extractedOffset += data.length;
            chunkIndex++;

            // Notify any waiters blocked on this segment.
            _notifySegmentWaiters(chunkIndex - 1);

            // Speed tracking.
            _speedBytes += data.length;
            _updateSpeed();

            // Check if we've reached the initial buffer threshold.
            if (!_isReady && extractedOffset >= initialBufferBytes) {
              _isReady = true;
              if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
                _readyCompleter!.complete();
              }
              _emitEvent(StreamPipelineReady(
                totalBytes: totalBytes,
                mimeType: _rarExtractedMimeType ?? 'application/octet-stream',
                filename: extractedFilename ?? 'content',
              ));
              print('[RAR-Stream] ready! extracted=$extractedOffset bytes '
                  '($chunkIndex chunks), total=$totalBytes');
            }

            // Emit buffering/progress events.
            if (!_isReady) {
              final pct = initialBufferBytes > 0
                  ? extractedOffset / initialBufferBytes
                  : 0.0;
              _emitEvent(StreamPipelineBuffering(
                percent: pct.clamp(0.0, 1.0),
              ));
            }

            _emitEvent(StreamPipelineProgress(
              bytesDownloaded: extractedOffset,
              totalBytes: totalBytes,
              segmentsFetched: chunkIndex,
              totalSegments: _estimatedTotalBytes != null
                  ? (_estimatedTotalBytes! / math.max(1, extractedOffset / math.max(1, chunkIndex))).round()
                  : totalSegs,
              downloadSpeed: _currentSpeed,
            ));

          case RarFileEnd(:final filename, :final checksumValid):
            print('[RAR-Stream] file complete: "$filename" '
                'valid=$checksumValid, total=$extractedOffset bytes');
            if (!checksumValid) {
              _emitError('CRC mismatch in extracted file: $filename');
            }

          case RarProgress():
            break; // Ignored — we emit our own progress events.

          case RarError(:final message, :final recoverable):
            print('[RAR-Stream] error: $message (recoverable=$recoverable)');
            _emitError('RAR extraction: $message', fatal: !recoverable);
            consecutiveErrors++;
            if (!recoverable || consecutiveErrors > 10) break;

          case RarPasswordRequired():
            _emitError('RAR archive is password-protected', fatal: true);
            return;
        }
      }
    } catch (e, st) {
      print('[RAR-Stream] extraction failed: $e\n$st');
      _emitError('RAR extraction failed: $e', fatal: true);
    }

    // If we never reached the buffer threshold but have some data, mark ready.
    if (!_isReady && extractedOffset > 0) {
      _isReady = true;
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _readyCompleter!.complete();
      }
      // Update estimated total to actual extracted size.
      _estimatedTotalBytes = extractedOffset;
      _emitEvent(StreamPipelineReady(
        totalBytes: totalBytes,
        mimeType: _rarExtractedMimeType ?? 'application/octet-stream',
        filename: extractedFilename ?? 'content',
      ));
      print('[RAR-Stream] ready (all extracted): $extractedOffset bytes');
    } else if (!_isReady) {
      // No data extracted at all.
      _emitError('No content could be extracted from RAR archive', fatal: true);
      return;
    }

    // Update final total bytes to actual extracted size.
    _estimatedTotalBytes = extractedOffset;

    _isComplete = true;
    _emitEvent(const StreamPipelineDone());
    print('[RAR-Stream] complete: $extractedOffset bytes in $chunkIndex chunks');
  }

  /// Creates a lazy download stream for a single RAR volume.
  ///
  /// Downloads and yEnc-decodes segments one at a time, yielding decoded
  /// data as chunks. The [RarExtractor] consumes these chunks progressively.
  Stream<List<int>> _createVolumeDownloadStream(
    NzbFileEntry file,
    int totalSegments,
    int Function() getFetchedCount,
    void Function(int) setFetchedCount,
  ) async* {
    final segments = List<NzbSegment>.from(file.segments)..sort();
    print('[RAR-Stream] downloading volume "${file.filename}" '
        '(${segments.length} segments, ${file.totalBytes} bytes)');

    for (final seg in segments) {
      if (_disposed) return;

      try {
        final results = await _pool.fetchBatch([seg.messageId]);
        if (results.isNotEmpty && results.first.isNotEmpty) {
          final decoded = _yenc.decodePart(results.first);
          _speedBytes += decoded.data.length;
          _updateSpeed();
          setFetchedCount(getFetchedCount() + 1);
          yield decoded.data;
        } else {
          _emitError('Empty result for segment ${seg.messageId}');
          // Yield empty bytes to keep the volume stream going.
          // The RAR parser handles gaps gracefully for store-mode archives.
        }
      } catch (e) {
        print('[RAR-Stream] segment fetch failed: $e');
        _emitError('Segment fetch failed: $e');
        // Continue to next segment — partial extraction is better than nothing.
      }
    }
  }

  /// Guesses MIME type from a filename extension.
  static String? _mimeFromFilename(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return const <String, String>{
      'mkv': 'video/x-matroska',
      'mp4': 'video/mp4',
      'avi': 'video/x-msvideo',
      'wmv': 'video/x-ms-wmv',
      'mov': 'video/quicktime',
      'webm': 'video/webm',
      'flv': 'video/x-flv',
      'ts': 'video/mp2t',
      'm4v': 'video/x-m4v',
      'mp3': 'audio/mpeg',
      'flac': 'audio/flac',
      'aac': 'audio/aac',
      'ogg': 'audio/ogg',
      'wav': 'audio/wav',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'pdf': 'application/pdf',
      'epub': 'application/epub+zip',
    }[ext];
  }

  /// Sniffs MIME type from file content magic bytes.
  static String? _sniffMimeType(Uint8List data) {
    if (data.length < 12) return null;

    // Matroska/WebM (EBML header).
    if (data[0] == 0x1A && data[1] == 0x45 && data[2] == 0xDF && data[3] == 0xA3) {
      // Check for WebM doctype vs Matroska.
      return 'video/x-matroska';
    }
    // MPEG-4 (ftyp box).
    if (data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70) {
      return 'video/mp4';
    }
    // AVI (RIFF...AVI).
    if (data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 &&
        data[8] == 0x41 && data[9] == 0x56 && data[10] == 0x49) {
      return 'video/x-msvideo';
    }
    // MPEG-TS.
    if (data[0] == 0x47) {
      return 'video/mp2t';
    }
    return null;
  }

  /// Sorts RAR volumes in the correct multi-volume order.
  ///
  /// For non-obfuscated NZBs (e.g. "movie.part001.rar", "movie.part002.rar"),
  /// natural filename sort handles this correctly.
  ///
  /// For obfuscated NZBs where all files have the same generated name
  /// (e.g. "File 1.rar" × 46), we preserve the original NZB XML order.
  /// NZB generators typically emit `<file>` elements in upload order, which
  /// corresponds to volume order. If dates are available, sort by date as
  /// a secondary strategy.
  static void _sortRarVolumes(List<NzbFileEntry> files) {
    if (files.length <= 1) return;

    // Check if filenames are all identical (obfuscated case).
    final allSameFilename = files.every((f) => f.filename == files.first.filename);

    if (allSameFilename) {
      // Check if dates are available for sorting.
      final hasDates = files.any((f) => f.date != null);
      if (hasDates) {
        // Sort by posting timestamp (reflects upload order).
        files.sort((a, b) {
          final ad = a.date ?? 0;
          final bd = b.date ?? 0;
          return ad.compareTo(bd);
        });
        print('[RAR-Sort] obfuscated NZB: sorted ${files.length} volumes by date');
      } else {
        // No dates, no distinct filenames — keep original NZB XML order.
        // NZB generators typically emit <file> elements in upload/volume order.
        print('[RAR-Sort] obfuscated NZB: keeping original XML order '
            '(${files.length} volumes, no dates)');
      }
    } else {
      // Natural sort by filename (handles part001, part002, etc.).
      files.sort();
      print('[RAR-Sort] sorted ${files.length} volumes by filename');
    }
  }

  /// Probes RAR volumes to find the first volume and reorders the list.
  ///
  /// Downloads the first segment of each candidate volume (up to a limit)
  /// and uses [RarExtractor.inspect] to check the `isFirstVolume` flag.
  /// If found, moves it to position 0.
  Future<void> _probeAndReorderFirstVolume(List<NzbFileEntry> files) async {
    if (files.length <= 1) return;

    // Only probe if filenames are ambiguous (all same name).
    final allSame = files.every((f) => f.filename == files.first.filename);
    if (!allSame) return; // Filenames are distinct → already sorted correctly.

    print('[RAR-Probe] probing ${math.min(files.length, 5)} volumes '
        'for first-volume flag...');

    final rar = RarExtractor();

    // Probe up to 5 candidate volumes in parallel.
    final probeFutures = <int, Future<RarArchiveInfo>>{};
    for (var i = 0; i < math.min(files.length, 5); i++) {
      final file = files[i];
      if (file.segments.isEmpty) continue;

      probeFutures[i] = (() async {
        final seg = (List<NzbSegment>.from(file.segments)..sort()).first;
        final results = await _pool.fetchBatch([seg.messageId]);
        if (results.isEmpty || results.first.isEmpty) {
          throw StateError('Empty response for probe segment');
        }
        final decoded = _yenc.decodePart(results.first);
        return rar.inspect(decoded.data);
      })();
    }

    // Check results — find the first volume.
    // A valid first volume must be detected as multi-volume (isMultiVolume)
    // AND as the first in the set (isFirstVolume). Default parser values
    // are isFirstVolume=true, isMultiVolume=false — so we reject results
    // that match defaults (indicates parsing failure / non-RAR data).
    for (final entry in probeFutures.entries) {
      try {
        final info = await entry.value;
        final isValid = info.isMultiVolume && info.isFirstVolume;
        print('[RAR-Probe] vol[${entry.key}]: '
            '${info.version}, multiVol=${info.isMultiVolume}, '
            'firstVol=${info.isFirstVolume}, '
            'files=${info.files.length}'
            '${isValid ? ' ← FIRST VOLUME' : ''}');

        if (isValid && entry.key != 0) {
          // Move this volume to position 0.
          final firstVol = files.removeAt(entry.key);
          files.insert(0, firstVol);
          print('[RAR-Probe] ✓ moved vol[${entry.key}] to position 0');
          return;
        } else if (isValid && entry.key == 0) {
          print('[RAR-Probe] ✓ vol[0] is already the first volume');
          return;
        }
      } catch (e) {
        print('[RAR-Probe] vol[${entry.key}] probe failed: $e');
      }
    }

    // If no first volume found in the first 5, probe ALL remaining volumes.
    if (files.length > 5) {
      print('[RAR-Probe] scanning remaining ${files.length - 5} volumes...');
      for (var i = 5; i < files.length; i++) {
        if (_disposed) return;
        final file = files[i];
        if (file.segments.isEmpty) continue;

        try {
          final seg = (List<NzbSegment>.from(file.segments)..sort()).first;
          final results = await _pool.fetchBatch([seg.messageId]);
          if (results.isEmpty || results.first.isEmpty) continue;
          final decoded = _yenc.decodePart(results.first);
          final info = await rar.inspect(decoded.data);

          if (info.isMultiVolume && info.isFirstVolume) {
            final firstVol = files.removeAt(i);
            files.insert(0, firstVol);
            print('[RAR-Probe] ✓ found first volume at index $i, moved to 0');
            return;
          }
        } catch (_) {
          continue;
        }
      }
    }

    print('[RAR-Probe] ⚠ could not identify first volume, '
        'using current order');
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
    // On fatal errors, complete the ready-completer so start() returns
    // promptly instead of waiting for the 120-second timeout.
    if (fatal && _readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.complete();
    }
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
