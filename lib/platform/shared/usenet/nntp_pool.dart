library;

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:kabuk/platform/shared/usenet/nntp_client.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// Configuration for a single Usenet provider.
@immutable
class ProviderConfig {
  /// Unique identifier for this provider.
  final String id;

  /// Human-readable name.
  final String name;

  /// Server hostname.
  final String host;

  /// Server port (typically 563 for NNTPS).
  final int port;

  /// Username for AUTHINFO.
  final String username;

  /// Password for AUTHINFO.
  final String password;

  /// Maximum concurrent connections to this provider.
  final int connections;

  /// Priority order — 0 = primary, higher values = backup.
  final int priority;

  /// Whether to connect over TLS.
  final bool ssl;

  /// Retention period in days.
  final int retentionDays;

  /// Creates a [ProviderConfig].
  const ProviderConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.connections = 10,
    this.priority = 0,
    this.ssl = true,
    this.retentionDays = 0,
  });

  @override
  String toString() => 'ProviderConfig($id, $host:$port, pri=$priority)';
}

/// Aggregate statistics for the entire connection pool.
@immutable
class PoolStats {
  /// Total number of managed connections across all providers.
  final int totalConnections;

  /// Connections currently processing a request.
  final int activeConnections;

  /// Connections sitting idle and ready for work.
  final int idleConnections;

  /// Number of configured providers.
  final int totalProviders;

  /// Cumulative articles fetched since pool creation.
  final int totalArticlesFetched;

  /// Cumulative bytes fetched since pool creation.
  final int totalBytesFetched;

  /// Cumulative failed requests since pool creation.
  final int failedRequests;

  /// Creates a [PoolStats].
  const PoolStats({
    required this.totalConnections,
    required this.activeConnections,
    required this.idleConnections,
    required this.totalProviders,
    required this.totalArticlesFetched,
    required this.totalBytesFetched,
    required this.failedRequests,
  });

  @override
  String toString() =>
      'PoolStats(conns=$totalConnections, active=$activeConnections, '
      'idle=$idleConnections, providers=$totalProviders, '
      'fetched=$totalArticlesFetched, bytes=$totalBytesFetched, '
      'failed=$failedRequests)';
}

/// Health and performance status for a single provider.
@immutable
class ProviderStatus {
  /// The provider's unique identifier.
  final String providerId;

  /// Human-readable name.
  final String name;

  /// Total managed connections for this provider.
  final int connections;

  /// Connections currently processing a request.
  final int activeConnections;

  /// Cumulative articles fetched from this provider.
  final int articlesFetched;

  /// Cumulative failed requests against this provider.
  final int failedRequests;

  /// Rolling average latency in milliseconds.
  final double avgLatencyMs;

  /// Whether the provider is considered healthy.
  final bool isHealthy;

  /// Creates a [ProviderStatus].
  const ProviderStatus({
    required this.providerId,
    required this.name,
    required this.connections,
    required this.activeConnections,
    required this.articlesFetched,
    required this.failedRequests,
    required this.avgLatencyMs,
    required this.isHealthy,
  });

  @override
  String toString() =>
      'ProviderStatus($providerId, conns=$connections, '
      'active=$activeConnections, healthy=$isHealthy)';
}

// ---------------------------------------------------------------------------
// Internal connection wrapper
// ---------------------------------------------------------------------------

/// Connection lifecycle states.
enum _ConnectionState { idle, busy, connecting, failed }

/// Internal wrapper that pairs an [NntpClient] with pool bookkeeping.
class _PooledConnection {
  _PooledConnection({required this.config});

  /// The provider configuration this connection belongs to.
  final ProviderConfig config;

  /// The underlying NNTP client (null until first connect).
  NntpClient? client;

  /// Current lifecycle state.
  _ConnectionState state = _ConnectionState.idle;

  /// Number of consecutive connection failures (for backoff).
  int consecutiveFailures = 0;

  /// Earliest time a reconnect may be attempted after failure.
  DateTime? backoffUntil;
}

/// Internal per-provider bookkeeping.
class _ProviderEntry {
  _ProviderEntry({required this.config});

  /// The provider configuration.
  final ProviderConfig config;

  /// Live pooled connections.
  final List<_PooledConnection> connections = [];

  /// Queue of callers waiting for an idle connection.
  final List<Completer<_PooledConnection>> waitQueue = [];

  // -- health metrics -------------------------------------------------------

  /// Total articles successfully fetched from this provider.
  int articlesFetched = 0;

  /// Total failed requests against this provider.
  int failedRequests = 0;

  /// Running count of consecutive failures (reset on success).
  int consecutiveFailures = 0;

  /// Latency samples for rolling average (milliseconds).
  final List<double> _latencySamples = [];

  /// Whether the provider is considered healthy.
  bool isHealthy = true;

  /// Timestamp of the last health-check retry for an unhealthy provider.
  DateTime? lastHealthRetry;

  /// Maximum latency samples retained for the rolling average.
  static const int _maxLatencySamples = 100;

  /// Number of consecutive failures before a provider is marked unhealthy.
  static const int unhealthyThreshold = 5;

  /// Interval before retrying an unhealthy provider.
  static const Duration healthRetryInterval = Duration(seconds: 60);

  /// Records a successful request with the given [latencyMs].
  void recordSuccess(double latencyMs) {
    articlesFetched++;
    consecutiveFailures = 0;
    isHealthy = true;
    _latencySamples.add(latencyMs);
    if (_latencySamples.length > _maxLatencySamples) {
      _latencySamples.removeAt(0);
    }
  }

  /// Records a failed request.
  void recordFailure() {
    failedRequests++;
    consecutiveFailures++;
    if (consecutiveFailures >= unhealthyThreshold) {
      isHealthy = false;
    }
  }

  /// Rolling average latency in milliseconds.
  double get avgLatencyMs {
    if (_latencySamples.isEmpty) return 0;
    return _latencySamples.reduce((a, b) => a + b) / _latencySamples.length;
  }
}

// ---------------------------------------------------------------------------
// NntpConnectionPool
// ---------------------------------------------------------------------------

/// Manages a pool of [NntpClient] connections across multiple Usenet
/// providers, with priority-based fallback, health monitoring, request
/// queuing, and batch-parallel fetching.
class NntpConnectionPool {
  /// Creates an empty [NntpConnectionPool] with no providers.
  NntpConnectionPool();

  /// Providers keyed by [ProviderConfig.id], maintained in priority order.
  final Map<String, _ProviderEntry> _providers = {};

  // -- global counters ------------------------------------------------------

  int _totalArticlesFetched = 0;
  int _totalBytesFetched = 0;
  int _failedRequests = 0;
  bool _disposed = false;

  // -- public API -----------------------------------------------------------

  /// Registers a new provider.
  ///
  /// Connections are created lazily on the first request — this method only
  /// stores the configuration.
  Future<void> addProvider(ProviderConfig config) async {
    _assertNotDisposed();
    if (_providers.containsKey(config.id)) {
      throw StateError('Provider "${config.id}" already registered');
    }
    _providers[config.id] = _ProviderEntry(config: config);
  }

  /// Disconnects and removes all connections for [providerId].
  Future<void> removeProvider(String providerId) async {
    _assertNotDisposed();
    final entry = _providers.remove(providerId);
    if (entry == null) return;
    await _disposeProviderConnections(entry);
  }

  /// Fetches the body of an article identified by [messageId].
  ///
  /// Providers are tried in priority order. If the primary provider returns
  /// a 430 (article not found) or a connection error, the next provider is
  /// attempted.
  Future<Uint8List> fetchArticleBody(String messageId) async {
    _assertNotDisposed();
    final providers = _providersByPriority();
    if (providers.isEmpty) {
      throw StateError('No providers registered');
    }

    Object? lastError;
    for (final entry in providers) {
      if (!_isProviderAvailable(entry)) continue;
      try {
        final result = await _fetchFromProvider(entry, messageId);
        return result;
      } on NntpException catch (e) {
        lastError = e;
        entry.recordFailure();
        _failedRequests++;
        // Article not found — try next provider.
        if (e.code == 430) continue;
        // Connection-level error — try next provider.
        continue;
      } catch (e) {
        lastError = e;
        entry.recordFailure();
        _failedRequests++;
        continue;
      }
    }

    throw NntpException(
      message: 'All providers exhausted for <$messageId>: $lastError',
    );
  }

  /// Checks whether an article exists on any registered provider via STAT.
  ///
  /// Returns `true` as soon as any provider confirms the article.
  Future<bool> checkArticleExists(String messageId) async {
    _assertNotDisposed();
    for (final entry in _providersByPriority()) {
      if (!_isProviderAvailable(entry)) continue;
      try {
        final conn = await _acquireConnection(entry);
        try {
          final sw = Stopwatch()..start();
          final resp = await conn.client!.stat(messageId);
          sw.stop();
          _releaseConnection(entry, conn);
          entry.recordSuccess(sw.elapsedMilliseconds.toDouble());
          if (resp.isSuccess) return true;
          if (resp.isArticleNotFound) continue;
        } catch (e) {
          _handleConnectionError(entry, conn, e);
          continue;
        }
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  /// Fetches multiple articles in parallel, distributing work across all
  /// available connections.
  ///
  /// Returns results in the same order as [messageIds]. Individual failures
  /// are retried on backup providers; if all providers fail for a given ID
  /// the corresponding entry is an empty [Uint8List].
  Future<List<Uint8List>> fetchBatch(
    List<String> messageIds, {
    int maxRetries = 3,
  }) async {
    _assertNotDisposed();
    if (messageIds.isEmpty) return const [];

    final results = List<Uint8List?>.filled(messageIds.length, null);

    // First pass: fetch all in parallel.
    final futures = <Future<void>>[];
    for (var idx = 0; idx < messageIds.length; idx++) {
      final i = idx;
      futures.add(_fetchWithFallback(messageIds[i]).then((data) {
        results[i] = data;
      }).catchError((Object e) {
        results[i] = Uint8List(0);
      }));
    }
    await Future.wait(futures);

    // Retry failed segments individually with back-off.
    for (var retry = 0; retry < maxRetries; retry++) {
      final failedIndices = <int>[];
      for (var i = 0; i < results.length; i++) {
        if (results[i] == null || results[i]!.isEmpty) {
          failedIndices.add(i);
        }
      }
      if (failedIndices.isEmpty) break;

      // Wait before retrying (exponential back-off: 500ms, 1s, 2s).
      await Future<void>.delayed(
        Duration(milliseconds: 500 * (1 << retry)),
      );

      final retryFutures = <Future<void>>[];
      for (final idx in failedIndices) {
        retryFutures.add(_fetchWithFallback(messageIds[idx]).then((data) {
          if (data.isNotEmpty) {
            results[idx] = data;
          }
        }).catchError((Object _) {
          // Still failed — leave as empty.
        }));
      }
      await Future.wait(retryFutures);
    }

    return results.map((r) => r ?? Uint8List(0)).toList();
  }

  /// Aggregate pool statistics.
  PoolStats get stats {
    var total = 0;
    var active = 0;
    var idle = 0;
    for (final entry in _providers.values) {
      for (final conn in entry.connections) {
        total++;
        switch (conn.state) {
          case _ConnectionState.busy:
          case _ConnectionState.connecting:
            active++;
          case _ConnectionState.idle:
            idle++;
          case _ConnectionState.failed:
            break;
        }
      }
    }
    return PoolStats(
      totalConnections: total,
      activeConnections: active,
      idleConnections: idle,
      totalProviders: _providers.length,
      totalArticlesFetched: _totalArticlesFetched,
      totalBytesFetched: _totalBytesFetched,
      failedRequests: _failedRequests,
    );
  }

  /// Per-provider health information.
  List<ProviderStatus> get providerStatuses {
    return _providers.values.map((entry) {
      var conns = 0;
      var active = 0;
      for (final c in entry.connections) {
        conns++;
        if (c.state == _ConnectionState.busy ||
            c.state == _ConnectionState.connecting) {
          active++;
        }
      }
      return ProviderStatus(
        providerId: entry.config.id,
        name: entry.config.name,
        connections: conns,
        activeConnections: active,
        articlesFetched: entry.articlesFetched,
        failedRequests: entry.failedRequests,
        avgLatencyMs: entry.avgLatencyMs,
        isHealthy: entry.isHealthy,
      );
    }).toList();
  }

  /// Gracefully shuts down all connections and releases resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final entry in _providers.values) {
      await _disposeProviderConnections(entry);
    }
    _providers.clear();
  }

  // -- internal helpers -----------------------------------------------------

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('NntpConnectionPool has been disposed');
    }
  }

  /// Returns providers sorted by ascending priority, filtering out entries
  /// that are not currently available.
  List<_ProviderEntry> _providersByPriority() {
    final sorted = _providers.values.toList()
      ..sort((a, b) => a.config.priority.compareTo(b.config.priority));
    return sorted;
  }

  /// Whether a provider can accept new requests right now.
  ///
  /// An unhealthy provider is retried after [_ProviderEntry.healthRetryInterval].
  bool _isProviderAvailable(_ProviderEntry entry) {
    if (entry.isHealthy) return true;
    final now = DateTime.now();
    if (entry.lastHealthRetry == null ||
        now.difference(entry.lastHealthRetry!) >=
            _ProviderEntry.healthRetryInterval) {
      entry.lastHealthRetry = now;
      return true; // allow a single retry
    }
    return false;
  }

  /// Fetches an article body from a specific provider.
  Future<Uint8List> _fetchFromProvider(
    _ProviderEntry entry,
    String messageId,
  ) async {
    final conn = await _acquireConnection(entry);
    try {
      final sw = Stopwatch()..start();
      final data = await conn.client!.body(messageId);
      sw.stop();
      _releaseConnection(entry, conn);
      entry.recordSuccess(sw.elapsedMilliseconds.toDouble());
      _totalArticlesFetched++;
      _totalBytesFetched += data.length;
      return data;
    } catch (e) {
      dev.log('[NNTP Pool] _fetchFromProvider error for $messageId: $e');
      _handleConnectionError(entry, conn, e);
      rethrow;
    }
  }

  /// Attempts to fetch an article with full provider fallback.
  Future<Uint8List> _fetchWithFallback(String messageId) =>
      fetchArticleBody(messageId);

  // -- connection lifecycle -------------------------------------------------

  /// Acquires an idle connection from [entry], creating or queuing as needed.
  Future<_PooledConnection> _acquireConnection(_ProviderEntry entry) async {
    // 1. Try to find an idle, connected connection.
    for (final conn in entry.connections) {
      if (conn.state == _ConnectionState.idle &&
          conn.client != null &&
          conn.client!.isConnected) {
        conn.state = _ConnectionState.busy;
        return conn;
      }
    }

    // 2. If under the connection limit, create a new one.
    if (entry.connections.length < entry.config.connections) {
      final conn = _PooledConnection(config: entry.config);
      entry.connections.add(conn);
      await _connectPooled(conn);
      conn.state = _ConnectionState.busy;
      return conn;
    }

    // 3. Try to replace a failed connection.
    for (var i = 0; i < entry.connections.length; i++) {
      final conn = entry.connections[i];
      if (conn.state == _ConnectionState.failed) {
        if (_isBackoffExpired(conn)) {
          await _connectPooled(conn);
          conn.state = _ConnectionState.busy;
          return conn;
        }
      }
    }

    // 4. All connections busy — queue the caller.
    final completer = Completer<_PooledConnection>();
    entry.waitQueue.add(completer);
    return completer.future;
  }

  /// Releases a connection back to the pool and drains the wait queue.
  void _releaseConnection(_ProviderEntry entry, _PooledConnection conn) {
    if (entry.waitQueue.isNotEmpty) {
      // Hand directly to the next waiting caller.
      final waiter = entry.waitQueue.removeAt(0);
      conn.state = _ConnectionState.busy;
      waiter.complete(conn);
    } else {
      conn.state = _ConnectionState.idle;
    }
  }

  /// Establishes (or re-establishes) the underlying [NntpClient] for [conn].
  Future<void> _connectPooled(_PooledConnection conn) async {
    conn.state = _ConnectionState.connecting;
    conn.client?.dispose();
    final client = NntpClient(
      host: conn.config.host,
      port: conn.config.port,
      ssl: conn.config.ssl,
    );
    try {
      await client.connect();
      await client.authenticate(conn.config.username, conn.config.password);
      conn.client = client;
      conn.consecutiveFailures = 0;
      conn.backoffUntil = null;
    } catch (e) {
      client.dispose();
      conn.client = null;
      _applyBackoff(conn);
      conn.state = _ConnectionState.failed;
      throw NntpException(message: 'Connection failed: $e');
    }
  }

  /// Handles a connection error by marking the connection failed and
  /// notifying the provider entry.
  void _handleConnectionError(
    _ProviderEntry entry,
    _PooledConnection conn,
    Object error,
  ) {
    conn.client?.dispose();
    conn.client = null;
    _applyBackoff(conn);
    conn.state = _ConnectionState.failed;
    entry.recordFailure();
    _failedRequests++;

    // Keep connection in pool with failed state — _acquireConnection
    // will reconnect it after backoff expires (step 3).

    // Drain the wait queue with errors if all connections are dead.
    if (entry.connections.every((c) => c.state == _ConnectionState.failed) &&
        entry.waitQueue.isNotEmpty) {
      final waiters = List<Completer<_PooledConnection>>.from(entry.waitQueue);
      entry.waitQueue.clear();
      for (final w in waiters) {
        w.completeError(
          NntpException(message: 'All connections to ${entry.config.id} failed'),
        );
      }
    }
  }

  // -- backoff --------------------------------------------------------------

  /// Maximum backoff duration.
  static const Duration _maxBackoff = Duration(seconds: 30);

  /// Applies exponential backoff to a failed connection.
  void _applyBackoff(_PooledConnection conn) {
    conn.consecutiveFailures++;
    final delaySeconds =
        (1 << (conn.consecutiveFailures - 1)).clamp(1, _maxBackoff.inSeconds);
    conn.backoffUntil =
        DateTime.now().add(Duration(seconds: delaySeconds));
  }

  /// Whether the backoff period for [conn] has elapsed.
  bool _isBackoffExpired(_PooledConnection conn) {
    if (conn.backoffUntil == null) return true;
    return DateTime.now().isAfter(conn.backoffUntil!);
  }

  // -- cleanup --------------------------------------------------------------

  /// Gracefully disconnects all connections belonging to [entry].
  Future<void> _disposeProviderConnections(_ProviderEntry entry) async {
    // Fail any waiting callers.
    for (final w in entry.waitQueue) {
      w.completeError(
        StateError('Provider "${entry.config.id}" is being removed'),
      );
    }
    entry.waitQueue.clear();

    for (final conn in entry.connections) {
      try {
        if (conn.client != null && conn.client!.isConnected) {
          await conn.client!.quit();
        }
      } catch (_) {
        // Best-effort.
      }
      conn.client?.dispose();
      conn.client = null;
      conn.state = _ConnectionState.failed;
    }
    entry.connections.clear();
  }
}
