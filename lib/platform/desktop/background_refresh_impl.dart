/// No-op background refresh for desktop platforms.
///
/// Desktop platforms don't support WorkManager or BGTaskScheduler.
/// The in-app 30-minute [Timer.periodic] in [ExploreView] is sufficient
/// for desktop — the app is rarely used in a "closed" background state.
library;

import 'package:kabuk/services/background_refresh.dart';

/// Desktop no-op implementation of [BackgroundRefreshService].
class DesktopBackgroundRefreshService implements BackgroundRefreshService {
  @override
  Future<void> registerPeriodicFeedRefresh({int intervalMinutes = 30}) async {
    // No-op: desktop relies on the in-app periodic timer.
  }

  @override
  Future<void> cancelFeedRefresh() async {
    // No-op.
  }
}
