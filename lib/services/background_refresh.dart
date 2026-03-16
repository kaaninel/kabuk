/// Background refresh service — abstract interface for OS-level periodic tasks.
///
/// On Android this is backed by WorkManager (via the `workmanager` plugin),
/// which survives app restarts and device reboots. On iOS it is backed by
/// BGAppRefreshTask. On desktop the in-app 30-minute timer in [ExploreView]
/// is sufficient; the OS-level scheduler is a no-op.
///
/// The only job registered here is [BackgroundRefreshService.feedRefreshTask]:
/// it fetches all subscribed feed URLs and persists new articles to the
/// knowledge store so the user always sees fresh content when they open the app.
library;

/// Unique task name sent to the OS scheduler.
const String kFeedRefreshTaskName = 'kabuk.feed_refresh';

/// Task name for the background Nostr DM poll.
const String kDmPollTaskName = 'kabuk.dm_poll';

/// Abstract interface for the OS-level background refresh scheduler.
abstract interface class BackgroundRefreshService {
  /// Registers the periodic feed refresh task with the OS scheduler.
  ///
  /// [intervalMinutes] controls how often the OS is *asked* to run the task.
  /// On iOS the OS may delay or coalesce tasks; the minimum is ~15 minutes.
  Future<void> registerPeriodicFeedRefresh({int intervalMinutes = 30});

  /// Cancels any previously registered periodic refresh task.
  Future<void> cancelFeedRefresh();
}
