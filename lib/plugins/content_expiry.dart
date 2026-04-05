/// Automatic content expiry service.
///
/// Periodically removes browsed content that has exceeded its time-to-live.
/// Content explicitly saved by the user (marked with `kabuk:saved`) is never
/// removed.
library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';

/// Service that periodically prunes stale content from the knowledge store.
///
/// Content is considered stale when its `kabuk:browsedAt` timestamp is older
/// than [defaultTtl] **and** it has not been explicitly saved by the user
/// (`kabuk:saved != 'true'`).
///
/// Entities with an explicit `kabuk:expiresAt` timestamp use that value
/// instead of the default TTL.
///
/// ```dart
/// final expiry = ContentExpiryService(store: knowledgeStore);
/// expiry.start();
/// // …later…
/// expiry.dispose();
/// ```
class ContentExpiryService {
  /// Creates a [ContentExpiryService].
  ///
  /// [store] is the knowledge store to clean up.
  /// [defaultTtl] controls how long un-saved content lives (default 7 days).
  /// [checkInterval] controls how often the cleanup runs (default 6 hours).
  ContentExpiryService({
    required KnowledgeStore store,
    this.defaultTtl = const Duration(days: 7),
    this.checkInterval = const Duration(hours: 6),
  }) : _store = store;

  final KnowledgeStore _store;

  /// How long un-saved content is kept before it becomes eligible for removal.
  final Duration defaultTtl;

  /// How often the periodic cleanup timer fires.
  final Duration checkInterval;

  Timer? _timer;

  /// Start the periodic cleanup timer.
  ///
  /// A cleanup pass runs immediately, then repeats every [checkInterval].
  /// Calling [start] when already running cancels the previous timer.
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(checkInterval, (_) => cleanup());
    // Also run immediately on start.
    unawaited(cleanup());
  }

  /// Stop the periodic cleanup timer.
  ///
  /// Does not cancel an in-flight [cleanup] call — it only prevents future
  /// scheduled runs.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Run a single cleanup pass.
  ///
  /// Removes content where:
  /// - `kabuk:browsedAt` timestamp is older than [defaultTtl], or
  /// - `kabuk:expiresAt` timestamp is in the past
  /// **and** `kabuk:saved` is NOT `'true'`.
  ///
  /// Returns the number of entities removed.
  Future<int> cleanup() async {
    try {
      final now = DateTime.now();
      final cutoff = now.subtract(defaultTtl);

      // 1. Find all entities that have a kabuk:browsedAt predicate.
      final browsedTriples =
          await _store
              .query()
              .predicate(NS.kabukBrowsedAt)
              .execute();

      // Collect unique subjects.
      final subjects = browsedTriples.map((t) => t.subject).toSet();
      if (subjects.isEmpty) return 0;

      // 2. Fetch full entity data for all candidates in one batch.
      final entities = await _store.getEntities(subjects.toList());

      // 3. Determine which entities should be pruned.
      final toRemove = <String>[];

      for (final entry in entities.entries) {
        final triples = entry.value;

        // Skip entities the user has explicitly saved.
        final saved = triples
            .where((t) => t.predicate == NS.kabukSaved)
            .firstOrNull
            ?.objectValue;
        if (saved == 'true') continue;

        // Check explicit expiresAt first — it takes priority.
        final expiresAtRaw = triples
            .where((t) => t.predicate == NS.kabukExpiresAt)
            .firstOrNull
            ?.objectValue;
        if (expiresAtRaw != null) {
          final expiresAt = DateTime.tryParse(expiresAtRaw);
          if (expiresAt != null && now.isAfter(expiresAt)) {
            toRemove.add(entry.key);
            continue;
          }
          // Has a future expiresAt — not expired yet.
          if (expiresAt != null) continue;
        }

        // Fall back to browsedAt + defaultTtl.
        final browsedAtRaw = triples
            .where((t) => t.predicate == NS.kabukBrowsedAt)
            .firstOrNull
            ?.objectValue;
        if (browsedAtRaw == null) continue;
        final browsedAt = DateTime.tryParse(browsedAtRaw);
        if (browsedAt != null && browsedAt.isBefore(cutoff)) {
          toRemove.add(entry.key);
        }
      }

      if (toRemove.isEmpty) return 0;

      // 4. Delete all triples for each expired entity.
      await _store.mutate((ctx) async {
        for (final subject in toRemove) {
          await ctx.remove(subject: subject);
        }
      });

      dev.log(
        'ContentExpiryService: pruned ${toRemove.length} expired entities',
        name: 'content_expiry',
      );

      return toRemove.length;
    } catch (e, st) {
      dev.log(
        'ContentExpiryService: cleanup failed: $e',
        name: 'content_expiry',
        error: e,
        stackTrace: st,
      );
      return 0;
    }
  }

  /// Stop the timer and release resources.
  void dispose() {
    stop();
  }
}
