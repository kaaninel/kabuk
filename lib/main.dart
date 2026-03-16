import 'dart:developer' as dev;

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
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
import 'package:kabuk/platform/shared/background_refresh_impl.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // We intentionally create multiple KabukDatabase instances backed by
  // different SQLite files (per-profile DBs + a global settings DB).
  // Drift warns about this but it's safe because each instance uses a
  // distinct file.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final container = ProviderContainer();

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
  container
      .read(knowledgeStoreProvider)
      .pruneStaleArticles()
      .then(
        (_) {},
        onError: (Object e) {
          dev.log('Failed to prune stale articles: $e', name: 'Main', error: e);
        },
      );

  runApp(
    UncontrolledProviderScope(container: container, child: const KabukApp()),
  );
}
