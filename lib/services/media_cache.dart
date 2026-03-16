/// Media cache service — custom [CacheManager] for Kabuk.
///
/// Provides a project-scoped image / media cache with a 7-day TTL and a
/// 500-object ceiling.  All [CachedNetworkImage] and [FeedImage] calls pass
/// this manager so that every in-app image is stored once, in one place, with
/// consistent eviction rules.
///
/// Also exposes a [connectivityProvider] that streams the current
/// [ConnectivityResult] list so the rest of the UI can react to network
/// changes (WiFi → allow pre-fetch; none → show offline banner).
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Custom cache manager
// ---------------------------------------------------------------------------

/// Kabuk-wide image + media cache manager.
///
/// Configuration:
/// - **Key:** `kabuk_media_v1` (increment to bust existing cache on schema change)
/// - **Max age:** 7 days — balances offline usability with storage hygiene
/// - **Max objects:** 500 — enough for a large scroll session without eating too
///   much disk space; oldest entries are evicted automatically by the LRU logic
///   inside [flutter_cache_manager].
class KabukCacheManager extends CacheManager with ImageCacheManager {
  /// The singleton instance shared across the whole app.
  static final KabukCacheManager instance = KabukCacheManager._();

  static const _key = 'kabuk_media_v1';

  KabukCacheManager._()
    : super(
        Config(
          _key,
          maxNrOfCacheObjects: 500,
          stalePeriod: const Duration(days: 7),
          fileService: HttpFileService(),
        ),
      );
}

// ---------------------------------------------------------------------------
// Connectivity provider
// ---------------------------------------------------------------------------

/// Streams the live [ConnectivityResult] list from the OS.
///
/// Updated whenever the network state changes (network up/down, WiFi ↔ mobile).
/// Starts with a `[]` initial value; the first real result arrives quickly.
///
/// ```dart
/// final conn = ref.watch(connectivityProvider).valueOrNull ?? [];
/// final isOnline  = hasNetwork(conn);
/// final isWifi    = onWifi(conn);
/// ```
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// Returns `true` when [results] contains at least one usable network type.
bool hasNetwork(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);

/// Returns `true` when [results] include a WiFi connection.
bool onWifi(List<ConnectivityResult> results) =>
    results.contains(ConnectivityResult.wifi);
