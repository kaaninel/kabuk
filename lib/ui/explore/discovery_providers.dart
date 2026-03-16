/// Discovery providers — reactive state for content discovery in the Explore view.
///
/// Provides Riverpod providers for trending Nostr hashtags, saved searches,
/// and topic-based discovery. These power the enhanced Explore view's
/// discovery section.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/saved_search.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/services/nostr_utils.dart';

// =============================================================================
// Trending Topics
// =============================================================================

/// A single trending topic with its hashtag and post count.
typedef TrendingTopic = ({String hashtag, int count});

/// Fetches trending hashtags from Nostr — auto-refreshes every 15 minutes.
final trendingTopicsProvider = FutureProvider<List<TrendingTopic>>((ref) async {
  final nostr = ref.watch(nostrServiceProvider);

  // Auto-invalidate every 15 minutes for fresh trending data.
  final timer = Timer(const Duration(minutes: 15), () {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);

  final trending = await nostr.trendingHashtags(
    window: const Duration(hours: 24),
  );

  return trending.take(15).toList();
});

// =============================================================================
// Saved Searches
// =============================================================================

/// Watches all SavedSearch entities reactively.
final savedSearchesProvider = FutureProvider<List<SavedSearchData>>((
  ref,
) async {
  final store = ref.watch(knowledgeStoreProvider);
  return store.listSavedSearches();
});

// =============================================================================
// Nostr Hashtag Search (on-demand)
// =============================================================================

/// A search request for Nostr hashtag content.
typedef HashtagSearchParams = ({List<String> hashtags, int limit});

/// On-demand Nostr hashtag search — keyed by hashtag list.
final nostrHashtagSearchProvider =
    FutureProvider.family<List<NostrEvent>, HashtagSearchParams>((
      ref,
      params,
    ) async {
      final nostr = ref.watch(nostrServiceProvider);

      final events = await collectNostrEvents(
        nostr.searchByHashtag(params.hashtags, limit: params.limit),
        where: (e) => e.kind == NostrKind.textNote,
      );

      // Deduplicate and sort newest first.
      final seen = <String>{};
      events.removeWhere((e) => !seen.add(e.id));
      events.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return events;
    });
