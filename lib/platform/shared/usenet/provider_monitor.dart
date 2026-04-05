library;

import 'dart:async';

import 'package:kabuk/platform/shared/usenet/nntp_pool.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Overall health classification for a single provider.
enum HealthStatus {
  /// Connection, authentication, and article access all succeed within
  /// acceptable latency thresholds.
  healthy,

  /// The provider is reachable but exhibits degraded performance — for
  /// example, high latency (>5 s) or partial article availability.
  degraded,

  /// The provider cannot be reached or authentication fails.
  down,
}

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// Health snapshot for a single Usenet provider.
@immutable
class ProviderHealth {
  /// Unique identifier of the provider.
  final String providerId;

  /// Human-readable provider name.
  final String name;

  /// Whether a TCP/TLS connection could be established.
  final bool reachable;

  /// Whether AUTHINFO authentication succeeded.
  final bool authenticated;

  /// Round-trip time for connection + authentication, if measured.
  final Duration? latency;

  /// Number of test articles confirmed available via STAT, if checked.
  final int? articleCount;

  /// Human-readable error description when the provider is not healthy.
  final String? errorMessage;

  /// Aggregate health classification.
  final HealthStatus status;

  /// Creates a [ProviderHealth].
  const ProviderHealth({
    required this.providerId,
    required this.name,
    required this.reachable,
    required this.authenticated,
    this.latency,
    this.articleCount,
    this.errorMessage,
    required this.status,
  });

  @override
  String toString() =>
      'ProviderHealth($providerId, status=$status, '
      'latency=${latency?.inMilliseconds}ms)';
}

/// Aggregated health report covering every configured provider.
@immutable
class ProviderHealthReport {
  /// Timestamp when this check was performed.
  final DateTime checkedAt;

  /// Per-provider health results.
  final List<ProviderHealth> providers;

  /// Creates a [ProviderHealthReport].
  const ProviderHealthReport({
    required this.checkedAt,
    required this.providers,
  });

  /// Whether every provider is [HealthStatus.healthy].
  bool get allHealthy =>
      providers.every((p) => p.status == HealthStatus.healthy);

  /// Providers whose status is not [HealthStatus.healthy].
  List<ProviderHealth> get unhealthyProviders =>
      providers.where((p) => p.status != HealthStatus.healthy).toList();

  @override
  String toString() =>
      'ProviderHealthReport(${providers.length} providers, '
      'allHealthy=$allHealthy, at=$checkedAt)';
}

// ---------------------------------------------------------------------------
// ProviderMonitor
// ---------------------------------------------------------------------------

/// Latency threshold above which a provider is classified as *degraded*
/// rather than *healthy*.
const Duration _degradedLatencyThreshold = Duration(seconds: 5);

/// Periodically probes every configured Usenet provider in the
/// [NntpConnectionPool] and emits [ProviderHealthReport]s on a broadcast
/// stream.
///
/// Only reports whose overall status differs from the previous check are
/// emitted on [healthStream], preventing noisy repeated notifications.
///
/// ```dart
/// final monitor = ProviderMonitor(pool: pool);
/// monitor.start();
/// monitor.healthStream.listen((report) {
///   for (final p in report.unhealthyProviders) {
///     print('${p.name} is ${p.status}');
///   }
/// });
/// ```
class ProviderMonitor {
  /// Creates a [ProviderMonitor].
  ///
  /// [pool] is the connection pool whose providers will be checked.
  /// [checkInterval] controls how often periodic probes run (default: 5 min).
  ProviderMonitor({
    required NntpConnectionPool pool,
    Duration checkInterval = const Duration(minutes: 5),
  })  : _pool = pool,
        _checkInterval = checkInterval;

  final NntpConnectionPool _pool;
  final Duration _checkInterval;

  Timer? _timer;
  ProviderHealthReport? _lastReport;
  bool _disposed = false;

  final StreamController<ProviderHealthReport> _controller =
      StreamController<ProviderHealthReport>.broadcast();

  // -- public API -----------------------------------------------------------

  /// Broadcast stream of [ProviderHealthReport]s.
  ///
  /// A new event is emitted only when the set of per-provider
  /// [HealthStatus] values differs from the previous check.
  Stream<ProviderHealthReport> get healthStream => _controller.stream;

  /// The most recent [ProviderHealthReport], or `null` if no check has
  /// been performed yet.
  ProviderHealthReport? get lastReport => _lastReport;

  /// Starts periodic health checks at the configured [_checkInterval].
  ///
  /// The first check runs immediately. Calling [start] while already
  /// running is a no-op.
  void start() {
    _assertNotDisposed();
    if (_timer != null) return;

    // Fire the first check immediately, then schedule repeats.
    _runCheck();
    _timer = Timer.periodic(_checkInterval, (_) => _runCheck());
  }

  /// Stops periodic health checks.
  ///
  /// Does **not** dispose the monitor — [start] may be called again.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Runs an immediate, one-off health check and returns the report.
  ///
  /// The result is also stored in [lastReport] and, if the status changed,
  /// emitted on [healthStream].
  Future<ProviderHealthReport> checkNow() async {
    _assertNotDisposed();
    return _performCheck();
  }

  /// Releases all resources held by this monitor.
  ///
  /// After calling [dispose] the monitor must not be used.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    _controller.close();
  }

  // -- internal -------------------------------------------------------------

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('ProviderMonitor has been disposed');
    }
  }

  /// Schedules an async check without awaiting the result.
  void _runCheck() {
    // ignore: discarded_futures
    _performCheck();
  }

  /// Probes every provider and returns the aggregated report.
  Future<ProviderHealthReport> _performCheck() async {
    final statuses = _pool.providerStatuses;
    final healthFutures = statuses.map(_checkProvider);
    final results = await Future.wait(healthFutures);

    final report = ProviderHealthReport(
      checkedAt: DateTime.now(),
      providers: results,
    );

    final changed = _hasStatusChanged(report);
    _lastReport = report;

    if (changed && !_controller.isClosed) {
      _controller.add(report);
    }

    return report;
  }

  /// Checks a single provider by attempting a pool connection, measuring
  /// latency, and verifying article availability.
  Future<ProviderHealth> _checkProvider(ProviderStatus status) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Use the pool's existing `checkArticleExists` as a lightweight
      // end-to-end probe: it acquires (or creates) a connection,
      // authenticates, and issues a STAT command.
      //
      // We use a well-known placeholder Message-ID.  A 430 (not found)
      // response is fine — it proves the provider is alive and speaking
      // NNTP.
      final exists = await _pool.checkArticleExists(
        '<health-check@kabuk.local>',
      );
      stopwatch.stop();

      final latency = stopwatch.elapsed;
      final articleCount = exists ? 1 : 0;

      if (latency > _degradedLatencyThreshold) {
        return ProviderHealth(
          providerId: status.providerId,
          name: status.name,
          reachable: true,
          authenticated: true,
          latency: latency,
          articleCount: articleCount,
          errorMessage: 'High latency: ${latency.inMilliseconds} ms',
          status: HealthStatus.degraded,
        );
      }

      return ProviderHealth(
        providerId: status.providerId,
        name: status.name,
        reachable: true,
        authenticated: true,
        latency: latency,
        articleCount: articleCount,
        status: HealthStatus.healthy,
      );
    } catch (e) {
      stopwatch.stop();

      // Distinguish connection/auth failures from article-level issues by
      // inspecting the pool's up-to-date provider status.
      final currentStatuses = _pool.providerStatuses;
      final current = currentStatuses.where(
        (s) => s.providerId == status.providerId,
      );

      final reachable = current.isNotEmpty && current.first.isHealthy;

      return ProviderHealth(
        providerId: status.providerId,
        name: status.name,
        reachable: reachable,
        authenticated: false,
        latency: stopwatch.elapsed,
        errorMessage: e.toString(),
        status: HealthStatus.down,
      );
    }
  }

  /// Returns `true` when the per-provider status set in [report] differs
  /// from [_lastReport].
  bool _hasStatusChanged(ProviderHealthReport report) {
    if (_lastReport == null) return true;
    final previous = _lastReport!;

    if (previous.providers.length != report.providers.length) return true;

    final previousMap = {
      for (final p in previous.providers) p.providerId: p.status,
    };

    for (final p in report.providers) {
      final old = previousMap[p.providerId];
      if (old == null || old != p.status) return true;
    }

    return false;
  }
}
