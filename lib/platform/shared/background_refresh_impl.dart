/// WorkManager-backed background refresh service.
///
/// Uses the `workmanager` Flutter plugin which wraps Android's WorkManager
/// and iOS's BGAppRefreshTask / BGProcessingTask behind a single Dart API.
///
/// The background task entry-point [callbackDispatcher] is a top-level
/// function (required by WorkManager's isolate model). It reconstructs
/// a minimal app context — database, feed service — and runs a refresh cycle
/// without starting the Flutter UI.
library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:kabuk/knowledge/drift_store.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/platform/shared/feed_service_impl.dart';
import 'package:kabuk/platform/shared/mesh_service_impl.dart';
import 'package:kabuk/platform/shared/nostr_service_impl.dart' show SharedNostrService;
import 'package:kabuk/services/background_refresh.dart';
import 'package:kabuk/services/exports.dart' show NostrService;
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/nostr.dart' show NostrService;
import 'package:workmanager/workmanager.dart';

/// Top-level WorkManager callback — runs in a separate isolate when the OS
/// wakes the app in the background.
///
/// IMPORTANT: this function must be a top-level (not instance) function and
/// must be annotated with `@pragma('vm:entry-point')`.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    dev.log('Background task started: $taskName', name: 'BackgroundRefresh');

    if (taskName == kFeedRefreshTaskName) {
      try {
        WidgetsFlutterBinding.ensureInitialized();
        await _runFeedRefresh();
      } on Object catch (e, st) {
        dev.log(
          'Background feed refresh failed: $e',
          name: 'BackgroundRefresh',
          error: e,
          stackTrace: st,
        );
      }
    } else if (taskName == kDmPollTaskName) {
      try {
        WidgetsFlutterBinding.ensureInitialized();
        await _runDmPoll();
      } on Object catch (e, st) {
        dev.log(
          'Background DM poll failed: $e',
          name: 'BackgroundRefresh',
          error: e,
          stackTrace: st,
        );
      }
    }

    dev.log('Background task complete: $taskName', name: 'BackgroundRefresh');
    return Future.value(true);
  });
}

// ---------------------------------------------------------------------------
// Background feed refresh implementation
// ---------------------------------------------------------------------------

/// Runs the full feed refresh cycle in the background isolate.
///
/// Opens the default profile's SQLite database directly (no Riverpod),
/// fetches all subscribed feeds, persists new articles, and fires a
/// local notification if new content was found.
Future<void> _runFeedRefresh() async {
  // Open the default-profile database directly by name.
  // drift_flutter resolves the same path path_provider would use.
  final db = KabukDatabase(driftDatabase(name: 'kabuk_default'));
  final store = DriftKnowledgeStore(db);
  final mesh = SharedMeshService();
  final feedService = SharedFeedService(mesh: mesh);

  int newArticleCount = 0;

  try {
    final subs = await store.listFeedSubscriptions();

    for (final sub in subs) {
      if (sub.feedUrl == null) continue;

      // Respect per-subscription refresh intervals.
      final last = sub.lastFetched;
      if (last != null) {
        final age = DateTime.now().difference(last);
        if (age < Duration(minutes: sub.refreshInterval)) continue;
      }

      try {
        final sourceType = FeedSourceType.values.firstWhere(
          (t) => t.name == sub.feedType,
          orElse: () => FeedSourceType.rss,
        );

        final items = await feedService.fetchItems(
          sub.feedUrl!,
          type: sourceType,
        );

        final existing = await store.listArticles(
          feedSource: sub.uri,
          limit: 300,
        );
        final existingByUrl = {for (final a in existing) a.url: a};

        for (final item in items) {
          final cached = existingByUrl[item.url];
          if (cached != null) {
            final isNostr = item.url.startsWith('nostr:');
            if (isNostr && cached.name != item.title && item.title.isNotEmpty) {
              await store.updateArticleTitleAndDescription(
                cached.uri,
                title: item.title,
                description: item.description,
              );
            }
            continue;
          }
          await store.createArticle(
            title: item.title,
            description: item.description,
            url: item.url,
            author: item.author,
            image: item.imageUrl,
            feedSource: sub.uri,
            datePublished: item.datePublished,
            tags: item.categories,
            galleryImages: item.galleryImages,
          );
          newArticleCount++;
        }

        await store.updateFeedLastFetched(sub.uri);
      } on Object catch (e) {
        dev.log(
          'Feed refresh failed for ${sub.uri}: $e',
          name: 'BackgroundRefresh',
          error: e,
        );
      }
    }
  } finally {
    unawaited(store.close());
    await db.close();
  }

  if (newArticleCount > 0) {
    await _showNewArticlesNotification(newArticleCount);
  }

  dev.log(
    'Background refresh complete — $newArticleCount new articles',
    name: 'BackgroundRefresh',
  );
}

// ---------------------------------------------------------------------------
// Background DM poll implementation
// ---------------------------------------------------------------------------

/// Stable notification ID for DM notifications.
const int _kDmNotificationId = 1002;

/// Polls for new Nostr DMs in the background isolate.
///
/// Opens the local database and reads the most-recent unread DM count.
/// Because the background isolate cannot reconstruct the full auth context
/// needed to decrypt NIP-17 sealed events, this task queries the locally
/// persisted [Messages] table for rows whose status is `received` and
/// whose timestamp is newer than 15 minutes ago. When any are found a local
/// notification is shown so the user can tap back into the app.
///
/// NOTE: To count *truly new* DMs that arrived since the last foreground
/// session the task reads conversations.unreadCount from the database.
/// The Nostr relay subscription in [SharedNostrService] persists incoming
/// DMs in real-time whenever the app is in the foreground; the background
/// task surfaces the count when the app is closed.
Future<void> _runDmPoll() async {
  dev.log('Background DM poll starting', name: 'BackgroundRefresh');

  final db = KabukDatabase(driftDatabase(name: 'kabuk_default'));

  try {
    // Sum unread counts across all nostr_dm conversations.
    final conversations = await db.listConversations();
    final unreadDms = conversations
        .where((c) => c.type == 'nostr_dm' || c.type == 'nostr_channel')
        .fold<int>(0, (sum, c) => sum + c.unreadCount);

    dev.log(
      'Background DM poll: $unreadDms unread messages across '
      '${conversations.length} conversations',
      name: 'BackgroundRefresh',
    );

    if (unreadDms > 0) {
      await _showNewDmsNotification(unreadDms);
    }
  } finally {
    await db.close();
  }
}

/// Shows a local notification for new background DMs.
Future<void> _showNewDmsNotification(int unreadCount) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await plugin.initialize(initSettings);

  const androidDetails = AndroidNotificationDetails(
    'kabuk_dm',
    'Direct Messages',
    channelDescription: 'Notifies when new Nostr DMs arrive',
    importance: Importance.high,
    priority: Priority.high,
    showWhen: true,
  );
  const details = NotificationDetails(android: androidDetails);

  final body = unreadCount == 1
      ? '1 unread message'
      : '$unreadCount unread messages';

  await plugin.show(_kDmNotificationId, 'New Messages — Kabuk', body, details);
}

// ---------------------------------------------------------------------------
// Background notification helper
// ---------------------------------------------------------------------------

/// Shows a local notification announcing newly-refreshed articles.
///
/// Calls `flutter_local_notifications` directly (no service layer) since
/// the background isolate runs outside of Riverpod.
Future<void> _showNewArticlesNotification(int count) async {
  final plugin = FlutterLocalNotificationsPlugin();

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);

  await plugin.initialize(initSettings);

  const androidDetails = AndroidNotificationDetails(
    'kabuk_feed_refresh',
    'Feed Refresh',
    channelDescription: 'Notifies when new feed articles are available',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    showWhen: false,
  );

  const details = NotificationDetails(android: androidDetails);

  final body = count == 1
      ? '1 new article is ready to read'
      : '$count new articles are ready to read';

  await plugin.show(_kFeedNotificationId, 'Kabuk Feed Updated', body, details);
}

/// Stable notification ID for feed refresh notifications.
const int _kFeedNotificationId = 1001;

// ---------------------------------------------------------------------------
// WorkManager-backed implementation
// ---------------------------------------------------------------------------

/// [BackgroundRefreshService] implementation using the `workmanager` plugin.
///
/// Registers a periodic WorkManager task on Android and a BGAppRefreshTask
/// on iOS to keep feed content fresh even when the app is closed.
class WorkmanagerRefreshService implements BackgroundRefreshService {
  bool _initialized = false;

  /// Initialises WorkManager and registers [callbackDispatcher].
  ///
  /// Must be called once before [registerPeriodicFeedRefresh].
  Future<void> initialize() async {
    if (_initialized) return;
    await Workmanager().initialize(callbackDispatcher);
    _initialized = true;
  }

  @override
  Future<void> registerPeriodicFeedRefresh({int intervalMinutes = 30}) async {
    await initialize();
    await Workmanager().registerPeriodicTask(
      kFeedRefreshTaskName,
      kFeedRefreshTaskName,
      frequency: Duration(minutes: intervalMinutes),
      // ExistingPeriodicWorkPolicy.replace updates the interval if it changed.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(
        // Only refresh when the device has network access.
        networkType: NetworkType.connected,
        // Don't wake from low-battery state for a feed refresh.
        requiresBatteryNotLow: true,
      ),
    );
    dev.log(
      'Periodic feed refresh registered: every $intervalMinutes minutes',
      name: 'BackgroundRefresh',
    );
  }

  @override
  Future<void> cancelFeedRefresh() async {
    await Workmanager().cancelByUniqueName(kFeedRefreshTaskName);
    dev.log('Periodic feed refresh cancelled', name: 'BackgroundRefresh');
  }

  /// Registers a periodic Nostr DM poll task with the OS scheduler.
  ///
  /// Minimum interval is 15 minutes (Android WorkManager floor). When the
  /// app is in the foreground the [NostrService] receives DMs in real-time
  /// via the persistent WebSocket connection; this task provides a safety net
  /// for background delivery and fires a local notification for each new sender.
  Future<void> registerPeriodicDmPoll({int intervalMinutes = 15}) async {
    await initialize();
    await Workmanager().registerPeriodicTask(
      kDmPollTaskName,
      kDmPollTaskName,
      frequency: Duration(minutes: intervalMinutes),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
    );
    dev.log(
      'Periodic DM poll registered: every $intervalMinutes minutes',
      name: 'BackgroundRefresh',
    );
  }

  /// Cancels any previously registered DM poll task.
  Future<void> cancelDmPoll() async {
    await Workmanager().cancelByUniqueName(kDmPollTaskName);
    dev.log('Periodic DM poll cancelled', name: 'BackgroundRefresh');
  }
}
