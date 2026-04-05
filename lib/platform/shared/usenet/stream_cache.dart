/// Smart cache manager for Usenet streaming.
///
/// Stores decoded segments during streaming and auto-purges when done.
/// Supports LRU eviction, per-session isolation, and a configurable size
/// limit (default 2 GB). On app startup, [StreamCache.initialize] cleans orphaned
/// sessions older than 24 hours that were never explicitly saved.
///
/// Cache layout on disk:
/// ```
/// {basePath}/usenet_cache/
///   sessions/
///     {sessionId}/
///       meta.json
///       segments/
///         {messageId_hash}
///       files/
///         {filename}
///   index.json
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// Aggregate statistics for the entire cache.
@immutable
class CacheStats {
  /// Creates cache statistics.
  const CacheStats({
    required this.totalBytes,
    required this.maxBytes,
    required this.sessionCount,
  });

  /// Total bytes currently occupied on disk.
  final int totalBytes;

  /// Configured upper limit in bytes.
  final int maxBytes;

  /// Number of active (non-purged) sessions.
  final int sessionCount;

  /// Percentage of the limit currently in use (0.0–100.0+).
  double get usagePercent =>
      maxBytes > 0 ? (totalBytes / maxBytes) * 100.0 : 0.0;

  @override
  String toString() =>
      'CacheStats(total: $totalBytes, max: $maxBytes, '
      'sessions: $sessionCount, usage: ${usagePercent.toStringAsFixed(1)}%)';
}

/// Metadata snapshot for a single cache session.
@immutable
class CacheSessionInfo {
  /// Creates session info.
  const CacheSessionInfo({
    required this.sessionId,
    required this.title,
    required this.totalBytes,
    required this.segmentCount,
    required this.createdAt,
    required this.lastAccessedAt,
  });

  /// Unique identifier for this session.
  final String sessionId;

  /// Human-readable title (usually the NZB title).
  final String title;

  /// Approximate bytes this session occupies on disk.
  final int totalBytes;

  /// Number of cached segments.
  final int segmentCount;

  /// When the session was created.
  final DateTime createdAt;

  /// When the session was last read or written to.
  final DateTime lastAccessedAt;

  @override
  String toString() =>
      'CacheSessionInfo(id: $sessionId, title: $title, '
      'bytes: $totalBytes, segments: $segmentCount)';
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// In-memory representation of a session stored in the global index.
class _SessionEntry {
  _SessionEntry({
    required this.sessionId,
    required this.title,
    required this.createdAt,
    required this.lastAccessedAt,
    this.totalBytes = 0,
    this.segmentCount = 0,
    this.saved = false,
  });

  factory _SessionEntry.fromJson(Map<String, dynamic> json) => _SessionEntry(
        sessionId: json['sessionId'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastAccessedAt: DateTime.parse(json['lastAccessedAt'] as String),
        totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
        segmentCount: (json['segmentCount'] as num?)?.toInt() ?? 0,
        saved: json['saved'] as bool? ?? false,
      );

  final String sessionId;
  final String title;
  DateTime createdAt;
  DateTime lastAccessedAt;
  int totalBytes;
  int segmentCount;
  bool saved;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'lastAccessedAt': lastAccessedAt.toIso8601String(),
        'totalBytes': totalBytes,
        'segmentCount': segmentCount,
        'saved': saved,
      };
}

/// Hashes a Usenet message ID to a 16-character hex string safe for use as
/// a filename.
String _hashMessageId(String messageId) {
  final bytes = utf8.encode(messageId);
  final digest = sha256.convert(bytes);
  return digest.toString().substring(0, 16);
}

// ---------------------------------------------------------------------------
// StreamCache
// ---------------------------------------------------------------------------

/// Manages an on-disk cache of decoded Usenet segments and reassembled files.
///
/// Each download gets its own *session* — an isolated directory containing
/// raw segments and post-processed files. Sessions are tracked in a global
/// index (`index.json`) and evicted on an LRU basis when the total cache
/// size exceeds [maxCacheBytes].
///
/// Usage:
/// ```dart
/// final cache = StreamCache(basePath: appTempDir);
/// await cache.initialize();
///
/// final sid = await cache.createSession('My.NZB.File');
/// await cache.putSegment(sid, '<msg@id>', decodedBytes);
/// final data = await cache.getSegment(sid, '<msg@id>');
///
/// await cache.closeSession(sid); // purge
/// ```
class StreamCache {
  /// Creates a [StreamCache] rooted at [basePath] with an optional size limit.
  ///
  /// [maxCacheBytes] defaults to 2 GiB.
  StreamCache({
    required this.basePath,
    this.maxCacheBytes = 2 * 1024 * 1024 * 1024,
  });

  /// Root directory under which the cache tree is created.
  final String basePath;

  /// Maximum bytes the cache may occupy before LRU eviction kicks in.
  int maxCacheBytes;

  /// Sessions that are actively streaming (protected from eviction).
  final Set<String> _activeSessions = {};

  /// In-memory index: sessionId → set of hashed message IDs.
  final Map<String, Set<String>> _segmentIndex = {};

  /// In-memory session metadata mirror.
  final Map<String, _SessionEntry> _sessions = {};

  /// Simple async lock for serialising index writes.
  Completer<void>? _indexLock;

  // -- Path helpers ---------------------------------------------------------

  /// Root of the entire cache tree.
  String get _cacheRoot => '$basePath/usenet_cache';

  /// Directory containing all session directories.
  String get _sessionsRoot => '$_cacheRoot/sessions';

  /// Path to the global index file.
  String get _indexPath => '$_cacheRoot/index.json';

  String _sessionDir(String id) => '$_sessionsRoot/$id';
  String _segmentsDir(String id) => '${_sessionDir(id)}/segments';
  String _filesDir(String id) => '${_sessionDir(id)}/files';
  String _metaPath(String id) => '${_sessionDir(id)}/meta.json';

  // -- Initialisation -------------------------------------------------------

  /// Creates the cache directory structure, loads the index, and removes
  /// orphaned sessions older than 24 hours.
  Future<void> initialize() async {
    try {
      await Directory(_sessionsRoot).create(recursive: true);
    } on FileSystemException catch (_) {
      // If we can't create the directory the cache is non-functional — callers
      // should handle the error.
      rethrow;
    }

    await _loadIndex();
    await _cleanOrphans();
  }

  // -- Session lifecycle ----------------------------------------------------

  /// Allocates a new cache session for [nzbTitle] and returns its unique id.
  Future<String> createSession(String nzbTitle) async {
    final sessionId =
        '${DateTime.now().millisecondsSinceEpoch}_${_hashMessageId(nzbTitle).substring(0, 8)}';

    final entry = _SessionEntry(
      sessionId: sessionId,
      title: nzbTitle,
      createdAt: DateTime.now(),
      lastAccessedAt: DateTime.now(),
    );

    try {
      await Directory(_segmentsDir(sessionId)).create(recursive: true);
      await Directory(_filesDir(sessionId)).create(recursive: true);
      await _writeMeta(sessionId, entry);
    } on FileSystemException catch (_) {
      rethrow;
    }

    _sessions[sessionId] = entry;
    _segmentIndex[sessionId] = {};
    _activeSessions.add(sessionId);

    await _persistIndex();
    return sessionId;
  }

  /// Closes a session.
  ///
  /// When [save] is `false` (the default), the entire session directory is
  /// deleted. When `true`, the session is marked as *saved* in the index and
  /// its files are retained.
  Future<void> closeSession(String sessionId, {bool save = false}) async {
    _activeSessions.remove(sessionId);

    if (save) {
      final entry = _sessions[sessionId];
      if (entry != null) {
        entry.saved = true;
        await _persistIndex();
      }
      return;
    }

    // Purge from disk.
    try {
      final dir = Directory(_sessionDir(sessionId));
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    } on FileSystemException catch (_) {
      // Best-effort deletion — log or ignore.
    }

    _sessions.remove(sessionId);
    _segmentIndex.remove(sessionId);
    await _persistIndex();
  }

  /// Moves all cached *files* (not raw segments) from [sessionId] to
  /// [destinationPath].
  ///
  /// Returns the destination path on success, or `null` if the session has no
  /// cached files.
  Future<String?> saveSessionTo(
    String sessionId,
    String destinationPath,
  ) async {
    final srcDir = Directory(_filesDir(sessionId));
    if (!srcDir.existsSync()) return null;

    final destDir = Directory(destinationPath);
    if (!destDir.existsSync()) {
      await destDir.create(recursive: true);
    }

    final files = await srcDir.list().toList();
    if (files.isEmpty) return null;

    for (final entity in files) {
      if (entity is File) {
        final name = entity.uri.pathSegments.last;
        await entity.copy('$destinationPath/$name');
      }
    }

    return destinationPath;
  }

  /// Lists all sessions currently tracked in the index.
  Future<List<CacheSessionInfo>> getSessions() async {
    return _sessions.values.map(_toInfo).toList()
      ..sort((a, b) => b.lastAccessedAt.compareTo(a.lastAccessedAt));
  }

  // -- Segment I/O ----------------------------------------------------------

  /// Caches a decoded segment [data] under [sessionId] keyed by [messageId].
  ///
  /// Automatically triggers LRU eviction if the cache is over limit.
  Future<void> putSegment(
    String sessionId,
    String messageId,
    Uint8List data,
  ) async {
    _assertSession(sessionId);

    final hash = _hashMessageId(messageId);
    final file = File('${_segmentsDir(sessionId)}/$hash');

    try {
      await file.writeAsBytes(data, flush: true);
    } on FileSystemException catch (_) {
      rethrow;
    }

    // Update in-memory bookkeeping.
    (_segmentIndex[sessionId] ??= {}).add(hash);
    final entry = _sessions[sessionId];
    if (entry != null) {
      entry.totalBytes += data.length;
      entry.segmentCount += 1;
      entry.lastAccessedAt = DateTime.now();
    }

    await _evictIfNeeded();
  }

  /// Retrieves a previously cached segment, or `null` on a cache miss.
  Future<Uint8List?> getSegment(String sessionId, String messageId) async {
    final hash = _hashMessageId(messageId);
    final file = File('${_segmentsDir(sessionId)}/$hash');

    try {
      if (!file.existsSync()) return null;
      final data = await file.readAsBytes();
      _touch(sessionId);
      return data;
    } on FileSystemException catch (_) {
      return null;
    }
  }

  /// Synchronous check against the in-memory segment index.
  bool hasSegment(String sessionId, String messageId) {
    final hash = _hashMessageId(messageId);
    return _segmentIndex[sessionId]?.contains(hash) ?? false;
  }

  // -- File I/O -------------------------------------------------------------

  /// Caches a post-processed (reassembled) file.
  ///
  /// Automatically triggers LRU eviction if the cache is over limit.
  Future<void> putFile(
    String sessionId,
    String filename,
    Uint8List data,
  ) async {
    _assertSession(sessionId);

    final file = File('${_filesDir(sessionId)}/$filename');

    try {
      await file.writeAsBytes(data, flush: true);
    } on FileSystemException catch (_) {
      rethrow;
    }

    final entry = _sessions[sessionId];
    if (entry != null) {
      entry.totalBytes += data.length;
      entry.lastAccessedAt = DateTime.now();
    }

    await _evictIfNeeded();
  }

  /// Retrieves a cached post-processed file, or `null` on a cache miss.
  Future<Uint8List?> getFile(String sessionId, String filename) async {
    final file = File('${_filesDir(sessionId)}/$filename');

    try {
      if (!file.existsSync()) return null;
      final data = await file.readAsBytes();
      _touch(sessionId);
      return data;
    } on FileSystemException catch (_) {
      return null;
    }
  }

  // -- Stats & maintenance --------------------------------------------------

  /// Returns aggregate cache statistics.
  Future<CacheStats> getStats() async {
    var totalBytes = 0;
    for (final entry in _sessions.values) {
      totalBytes += entry.totalBytes;
    }

    return CacheStats(
      totalBytes: totalBytes,
      maxBytes: maxCacheBytes,
      sessionCount: _sessions.length,
    );
  }

  /// Updates the maximum cache size and evicts if now over limit.
  Future<void> setMaxSize(int maxBytes) async {
    maxCacheBytes = maxBytes;
    await _evictIfNeeded();
  }

  /// Deletes **all** cache data and resets internal state.
  Future<void> clear() async {
    try {
      final dir = Directory(_cacheRoot);
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    } on FileSystemException catch (_) {
      // Best-effort.
    }

    _sessions.clear();
    _segmentIndex.clear();
    _activeSessions.clear();

    // Re-create the directory structure so the cache remains usable.
    await Directory(_sessionsRoot).create(recursive: true);
    await _persistIndex();
  }

  /// Evicts least-recently-used sessions until the cache is within
  /// [maxCacheBytes]. Active (currently streaming) sessions are never evicted.
  Future<void> evictLru() async {
    await _evictIfNeeded();
  }

  // -- Private helpers ------------------------------------------------------

  void _assertSession(String sessionId) {
    if (!_sessions.containsKey(sessionId)) {
      throw StateError('Unknown cache session: $sessionId');
    }
  }

  void _touch(String sessionId) {
    _sessions[sessionId]?.lastAccessedAt = DateTime.now();
  }

  int get _totalBytes {
    var total = 0;
    for (final e in _sessions.values) {
      total += e.totalBytes;
    }
    return total;
  }

  Future<void> _evictIfNeeded() async {
    while (_totalBytes > maxCacheBytes) {
      // Sort non-active sessions by lastAccessedAt ascending.
      final candidates = _sessions.values
          .where((e) => !_activeSessions.contains(e.sessionId))
          .toList()
        ..sort((a, b) => a.lastAccessedAt.compareTo(b.lastAccessedAt));

      if (candidates.isEmpty) break; // Nothing left to evict.

      final victim = candidates.first;
      await _deleteSessionFromDisk(victim.sessionId);
      _sessions.remove(victim.sessionId);
      _segmentIndex.remove(victim.sessionId);
    }

    await _persistIndex();
  }

  Future<void> _deleteSessionFromDisk(String sessionId) async {
    try {
      final dir = Directory(_sessionDir(sessionId));
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    } on FileSystemException catch (_) {
      // Best-effort.
    }
  }

  /// Removes sessions older than 24 hours that were not explicitly saved.
  Future<void> _cleanOrphans() async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    final toRemove = <String>[];

    for (final entry in _sessions.values) {
      if (!entry.saved && entry.lastAccessedAt.isBefore(cutoff)) {
        toRemove.add(entry.sessionId);
      }
    }

    for (final id in toRemove) {
      await _deleteSessionFromDisk(id);
      _sessions.remove(id);
      _segmentIndex.remove(id);
    }

    if (toRemove.isNotEmpty) {
      await _persistIndex();
    }
  }

  // -- Index persistence ----------------------------------------------------

  Future<void> _loadIndex() async {
    final file = File(_indexPath);
    try {
      if (!file.existsSync()) return;
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final list = json['sessions'] as List<dynamic>? ?? [];

      _sessions.clear();
      _segmentIndex.clear();

      for (final item in list) {
        final entry =
            _SessionEntry.fromJson(item as Map<String, dynamic>);
        _sessions[entry.sessionId] = entry;
        // Rebuild the in-memory segment index from disk.
        _segmentIndex[entry.sessionId] = await _loadSegmentHashes(entry.sessionId);
      }
    } on FormatException catch (_) {
      // Corrupt index — start fresh.
      _sessions.clear();
      _segmentIndex.clear();
    } on FileSystemException catch (_) {
      // Missing or unreadable — start fresh.
    }
  }

  Future<Set<String>> _loadSegmentHashes(String sessionId) async {
    final dir = Directory(_segmentsDir(sessionId));
    final hashes = <String>{};

    try {
      if (!dir.existsSync()) return hashes;
      await for (final entity in dir.list()) {
        if (entity is File) {
          hashes.add(entity.uri.pathSegments.last);
        }
      }
    } on FileSystemException catch (_) {
      // Ignore unreadable directories.
    }

    return hashes;
  }

  /// Serialises the current session map to `index.json`.
  ///
  /// Uses a simple [Completer]-based lock so concurrent writes are serialised.
  Future<void> _persistIndex() async {
    // Acquire lock.
    while (_indexLock != null) {
      await _indexLock!.future;
    }
    _indexLock = Completer<void>();

    try {
      final data = {
        'sessions': _sessions.values.map((e) => e.toJson()).toList(),
      };
      final file = File(_indexPath);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
        flush: true,
      );
    } on FileSystemException catch (_) {
      // Best-effort persistence.
    } finally {
      final lock = _indexLock;
      _indexLock = null;
      lock?.complete();
    }
  }

  Future<void> _writeMeta(String sessionId, _SessionEntry entry) async {
    final file = File(_metaPath(sessionId));
    try {
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(entry.toJson()),
        flush: true,
      );
    } on FileSystemException catch (_) {
      // Best-effort.
    }
  }

  CacheSessionInfo _toInfo(_SessionEntry e) => CacheSessionInfo(
        sessionId: e.sessionId,
        title: e.title,
        totalBytes: e.totalBytes,
        segmentCount: e.segmentCount,
        createdAt: e.createdAt,
        lastAccessedAt: e.lastAccessedAt,
      );
}
