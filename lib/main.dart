import 'dart:developer' as dev;

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/agents/domains/calendar_agent.dart';
import 'package:kabuk/agents/domains/contact_agent.dart';
import 'package:kabuk/agents/domains/discovery_agent.dart';
import 'package:kabuk/agents/domains/feed_agent.dart';
import 'package:kabuk/agents/domains/file_agent.dart';
import 'package:kabuk/agents/domains/identity_agent.dart';
import 'package:kabuk/agents/domains/messaging_agent.dart';
import 'package:kabuk/agents/domains/note_agent.dart';
import 'package:kabuk/agents/domains/router.dart';
import 'package:kabuk/agents/domains/search_agent.dart';
import 'package:kabuk/agents/domains/system_agent.dart';
import 'package:kabuk/app.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/knowledge/types/webpage.dart';
import 'package:kabuk/platform/shared/background_refresh_impl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Enable fullscreen kiosk mode — hide system navigation bar.
  // On iOS, KabukViewController handles home-indicator auto-hide and
  // bottom-edge gesture deferral natively.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  // We intentionally create multiple KabukDatabase instances backed by
  // different SQLite files (per-profile DBs + a global settings DB).
  // Drift warns about this but it's safe because each instance uses a
  // distinct file.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final container = ProviderContainer();

  // Resolve the platform cache directory so services that write ephemeral data
  // (e.g. UsenetService stream cache) use an absolute, writable path.
  try {
    final tempDir = await getTemporaryDirectory();
    container.read(cacheDirectoryProvider.notifier).state = tempDir.path;
  } on Object catch (e) {
    dev.log(
      'Failed to resolve temporary directory: $e',
      name: 'Main',
      error: e,
    );
  }

  // Register all agents on startup.
  final runtime = container.read(agentRuntimeProvider);
  runtime.register(SystemAgent());
  runtime.register(NoteAgent());
  runtime.register(ContactAgent());
  runtime.register(CalendarAgent());
  runtime.register(FileAgent());
  runtime.register(SearchAgent());
  runtime.register(IdentityAgent());
  runtime.register(MessagingAgent());
  runtime.register(FeedAgent());
  runtime.register(DiscoveryAgent());
  runtime.register(RouterAgent());

  // Initialize Usenet service (lazy — the provider handles creation).
  // Reading the provider ensures it's created and available for agents.
  container.read(usenetServiceProvider);

  // Register OS-level periodic feed refresh (Android: WorkManager, iOS: BGTask).
  // This ensures content stays fresh even when the app is fully closed.
  final bgRefresh = WorkmanagerRefreshService();
  bgRefresh.registerPeriodicFeedRefresh().then(
    (_) {},
    onError: (Object e) {
      dev.log(
        'Failed to register periodic feed refresh: $e',
        name: 'Main',
        error: e,
      );
    },
  );
  // M1: Register periodic background DM poll for notification delivery.
  bgRefresh.registerPeriodicDmPoll().then(
    (_) {},
    onError: (Object e) {
      dev.log(
        'Failed to register periodic DM poll: $e',
        name: 'Main',
        error: e,
      );
    },
  );

  // Prune expired articles from the knowledge store on startup.
  // Image cache eviction is handled automatically by KabukCacheManager's
  // stalePeriod + maxNrOfCacheObjects config — no explicit flush needed.
  final store = container.read(knowledgeStoreProvider);
  store.pruneStaleArticles().then(
    (_) {},
    onError: (Object e) {
      dev.log('Failed to prune stale articles: $e', name: 'Main', error: e);
    },
  );

  // Prune stale web pages (30 days) and orphaned semantic entities.
  store.pruneStaleWebPages(const Duration(days: 30)).then(
    (_) => store.pruneOrphanedEntities(),
    onError: (Object e) {
      dev.log('Failed to prune stale web pages: $e', name: 'Main', error: e);
    },
  ).then(
    (_) {},
    onError: (Object e) {
      dev.log(
        'Failed to prune orphaned entities: $e',
        name: 'Main',
        error: e,
      );
    },
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const KabukApp()),
  );
}
