/// Nostr social providers — URL-based social interactions for Explore.
///
/// Every article in the feed gets inline Nostr social features
/// (likes, comments, reshares) anchored by its canonical URL.
/// No manual "share to Nostr" step is needed — the article URL
/// is the universal social identifier via Nostr `r` tags.
///
/// Uses **optimistic UI** — social actions update the local state
/// immediately and reconcile with relay responses in the background.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/knowledge/types/nostr_social.dart';
import 'package:kabuk/platform/shared/nostr_feed_source.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/services/nostr_utils.dart';

// =============================================================================
// Optimistic state overlay
// =============================================================================

/// Local optimistic overrides for social stats, keyed by URL.
///
/// When a user taps like/repost, we immediately update this map
/// so the UI reflects the change without waiting for relay round-trips.
/// The relay publish happens in the background and on failure we
/// roll back the optimistic state.
final _optimisticStatsProvider =
    StateProvider<Map<String, _OptimisticOverride>>((ref) => {});

/// Optimistic comments that have been posted but not yet confirmed
/// from the relay. Shown immediately in the comments list.
final _optimisticCommentsProvider =
    StateProvider<Map<String, List<NostrComment>>>((ref) => {});

/// Types of social actions that can be pending.
enum _SocialAction { react, comment, repost }

/// Tracks which actions are currently in-flight per URL.
final _pendingActionsProvider = StateProvider<Map<String, Set<_SocialAction>>>(
  (ref) => {},
);

/// An optimistic override for social stats on a specific URL.
@immutable
class _OptimisticOverride {
  const _OptimisticOverride({
    this.reactionDelta = 0,
    this.commentDelta = 0,
    this.repostDelta = 0,
    this.userReacted,
    this.userReposted,
  });

  final int reactionDelta;
  final int commentDelta;
  final int repostDelta;
  final bool? userReacted;
  final bool? userReposted;

  /// Merges this override on top of real stats from the relay.
  NostrSocialStats applyTo(NostrSocialStats base) {
    return NostrSocialStats(
      reactionCount: (base.reactionCount + reactionDelta).clamp(0, 999999),
      replyCount: (base.replyCount + commentDelta).clamp(0, 999999),
      repostCount: (base.repostCount + repostDelta).clamp(0, 999999),
      userReacted: userReacted ?? base.userReacted,
      userReposted: userReposted ?? base.userReposted,
    );
  }
}

// =============================================================================
// URL-based social stats
// =============================================================================

/// Raw stats fetched from relays (no optimistic overlay).
final _rawNostrStatsForUrlProvider =
    FutureProvider.family<NostrSocialStats, String>((ref, url) async {
      if (url.isEmpty) return const NostrSocialStats();

      final nostr = ref.watch(nostrServiceProvider);
      final userPubkey = await ref.read(authServiceProvider).getPublicKeyHex();

      var reactionCount = 0;
      var commentCount = 0;
      var repostCount = 0;
      var userReacted = false;
      var userReposted = false;

      // Fetch reactions for this URL.
      try {
        await for (final event
            in nostr
                .fetchReactionsForUrl(url)
                .timeout(
                  const Duration(seconds: 4),
                  onTimeout: (sink) => sink.close(),
                )) {
          reactionCount++;
          if (userPubkey != null && event.pubkey == userPubkey) {
            userReacted = true;
          }
        }
      } on TimeoutException {
        // Expected — relay subscriptions don't always close.
      }

      // Fetch comments for this URL.
      try {
        await for (final _
            in nostr
                .fetchCommentsForUrl(url)
                .timeout(
                  const Duration(seconds: 4),
                  onTimeout: (sink) => sink.close(),
                )) {
          commentCount++;
        }
      } on TimeoutException {
        // Expected.
      }

      // Fetch reposts for this URL.
      try {
        await for (final event
            in nostr
                .fetchRepostsForUrl(url)
                .timeout(
                  const Duration(seconds: 4),
                  onTimeout: (sink) => sink.close(),
                )) {
          repostCount++;
          if (userPubkey != null && event.pubkey == userPubkey) {
            userReposted = true;
          }
        }
      } on TimeoutException {
        // Expected.
      }

      return NostrSocialStats(
        reactionCount: reactionCount,
        replyCount: commentCount,
        repostCount: repostCount,
        userReacted: userReacted,
        userReposted: userReposted,
      );
    });

/// Fetches and caches Nostr social stats for a given article URL.
///
/// Combines relay data with optimistic local overrides so the UI
/// responds instantly to user actions.
final nostrSocialStatsForUrlProvider =
    Provider.family<AsyncValue<NostrSocialStats>, String>((ref, url) {
      if (url.isEmpty) return const AsyncData(NostrSocialStats());

      final rawAsync = ref.watch(_rawNostrStatsForUrlProvider(url));
      final overrides = ref.watch(_optimisticStatsProvider);
      final override = overrides[url];

      if (override == null) return rawAsync;

      return rawAsync.when(
        data: (stats) => AsyncData(override.applyTo(stats)),
        // Show optimistic state even while loading from relays.
        loading: () => AsyncData(override.applyTo(const NostrSocialStats())),
        error: (e, st) => AsyncData(override.applyTo(const NostrSocialStats())),
      );
    });

// =============================================================================
// Comments for a URL
// =============================================================================

/// A single Nostr comment about a URL.
class NostrComment {
  /// Creates a [NostrComment].
  const NostrComment({
    required this.eventId,
    required this.pubkey,
    required this.content,
    required this.createdAt,
    this.authorName,
    this.authorPicture,
    this.isPending = false,
  });

  /// Nostr event ID.
  final String eventId;

  /// Author's public key (hex).
  final String pubkey;

  /// The comment text.
  final String content;

  /// When the comment was posted.
  final DateTime createdAt;

  /// Resolved author display name (if available).
  final String? authorName;

  /// Resolved author profile picture URL (if available).
  final String? authorPicture;

  /// Whether this comment is optimistically displayed (not yet confirmed).
  final bool isPending;
}

/// Fetches Nostr comments for a given article URL.
///
/// Returns a list of [NostrComment] sorted newest-first, with
/// any optimistic (pending) comments prepended at the top.
final nostrCommentsForUrlProvider =
    Provider.family<AsyncValue<List<NostrComment>>, String>((ref, url) {
      if (url.isEmpty) return const AsyncData([]);

      final rawAsync = ref.watch(_rawNostrCommentsProvider(url));
      final optimistic = ref.watch(_optimisticCommentsProvider);
      final pending = optimistic[url] ?? [];

      if (pending.isEmpty) return rawAsync;

      return rawAsync.when(
        data: (comments) => AsyncData([...pending, ...comments]),
        loading: () => AsyncData(pending),
        error: (_, _) => AsyncData(pending),
      );
    });

/// Raw comments from relays (no optimistic overlay).
final _rawNostrCommentsProvider =
    FutureProvider.family<List<NostrComment>, String>((ref, url) async {
      if (url.isEmpty) return [];

      final nostr = ref.watch(nostrServiceProvider);
      final events = <NostrEvent>[];

      try {
        await for (final event
            in nostr
                .fetchCommentsForUrl(url, limit: 50)
                .timeout(
                  const Duration(seconds: 5),
                  onTimeout: (sink) => sink.close(),
                )) {
          events.add(event);
        }
      } on TimeoutException {
        // Expected.
      }

      if (events.isEmpty) return [];

      // Sort newest first.
      events.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Resolve profiles (best effort, batch unique pubkeys).
      final uniquePubkeys = events.map((e) => e.pubkey).toSet();
      final profiles = <String, Map<String, dynamic>>{};

      for (final pubkey in uniquePubkeys) {
        try {
          final profile = await nostr
              .fetchProfile(pubkey)
              .timeout(const Duration(seconds: 2));
          if (profile != null) {
            profiles[pubkey] =
                jsonDecode(profile.content) as Map<String, dynamic>;
          }
        } on Object {
          // Skip — profile fetch failed.
        }
      }

      return events.map((event) {
        final profile = profiles[event.pubkey];
        return NostrComment(
          eventId: event.id,
          pubkey: event.pubkey,
          content: event.content,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            event.createdAt * 1000,
          ),
          authorName: profile?['name'] as String?,
          authorPicture: profile?['picture'] as String?,
        );
      }).toList();
    });

// =============================================================================
// Identity check helper
// =============================================================================

/// Checks whether the user has a Nostr identity configured.
///
/// Returns the hex public key if available, null otherwise.
Future<String?> _ensureIdentity(WidgetRef ref) async {
  final auth = ref.read(authServiceProvider);
  return auth.getPublicKeyHex();
}

// =============================================================================
// Social actions (URL-based) — optimistic UI
// =============================================================================

/// Applies an optimistic override for a URL.
void _applyOptimistic(WidgetRef ref, String url, _OptimisticOverride ov) {
  final map = Map<String, _OptimisticOverride>.from(
    ref.read(_optimisticStatsProvider),
  );
  map[url] = ov;
  ref.read(_optimisticStatsProvider.notifier).state = map;
}

/// Clears optimistic override for a URL (after relay confirms or on rollback).
void _clearOptimistic(WidgetRef ref, String url) {
  final map = Map<String, _OptimisticOverride>.from(
    ref.read(_optimisticStatsProvider),
  );
  map.remove(url);
  ref.read(_optimisticStatsProvider.notifier).state = map;
}

/// Marks an action as pending.
void _markPending(WidgetRef ref, String url, _SocialAction action) {
  final map = Map<String, Set<_SocialAction>>.from(
    ref.read(_pendingActionsProvider),
  );
  map[url] = {...(map[url] ?? {}), action};
  ref.read(_pendingActionsProvider.notifier).state = map;
}

/// Clears a pending action.
void _clearPending(WidgetRef ref, String url, _SocialAction action) {
  final map = Map<String, Set<_SocialAction>>.from(
    ref.read(_pendingActionsProvider),
  );
  final set = map[url];
  if (set != null) {
    set.remove(action);
    if (set.isEmpty) map.remove(url);
  }
  ref.read(_pendingActionsProvider.notifier).state = map;
}

/// Reacts to content via its URL on Nostr (kind 7 with `r` tag).
///
/// **Optimistic:** Immediately shows the like state. Publishes to relays
/// in the background and rolls back on failure.
///
/// Returns `true` if the identity is configured (action was attempted),
/// `false` if no identity exists (user needs to set up in Settings).
Future<bool> reactToUrl(
  WidgetRef ref, {
  required String url,
  String reaction = '+',
}) async {
  if (url.isEmpty) return false;

  // Check identity upfront.
  final pubkey = await _ensureIdentity(ref);
  if (pubkey == null) return false;

  // Optimistic update — show liked state immediately.
  _applyOptimistic(
    ref,
    url,
    const _OptimisticOverride(reactionDelta: 1, userReacted: true),
  );
  _markPending(ref, url, _SocialAction.react);

  // Publish in background.
  try {
    final nostr = ref.read(nostrServiceProvider);
    await nostr.publishReactionForUrl(url, reaction: reaction);
  } on Object {
    // Roll back optimistic state on failure.
    _clearOptimistic(ref, url);
  } finally {
    _clearPending(ref, url, _SocialAction.react);
    // Reconcile with relays in background.
    ref.invalidate(_rawNostrStatsForUrlProvider(url));
  }
  return true;
}

/// Posts a comment about content via its URL on Nostr (kind 1 with `r` tag).
///
/// **Optimistic:** Shows the comment immediately in a pending state.
/// On success, refreshes from relays; on failure, removes the pending comment.
///
/// Returns `true` if the identity is configured, `false` otherwise.
Future<bool> commentOnUrl(
  WidgetRef ref, {
  required String url,
  required String content,
}) async {
  if (url.isEmpty || content.trim().isEmpty) return false;

  final pubkey = await _ensureIdentity(ref);
  if (pubkey == null) return false;

  final trimmed = content.trim();

  // Resolve the user's display info for the optimistic comment.
  String? userName;
  String? userPicture;
  try {
    final nostr = ref.read(nostrServiceProvider);
    final profile = await nostr
        .fetchProfile(pubkey)
        .timeout(const Duration(seconds: 2));
    if (profile != null) {
      final meta = jsonDecode(profile.content) as Map<String, dynamic>;
      userName = meta['name'] as String?;
      userPicture = meta['picture'] as String?;
    }
  } on Object {
    // No profile — fine.
  }

  // Create optimistic comment.
  final pendingComment = NostrComment(
    eventId: 'pending_${DateTime.now().microsecondsSinceEpoch}',
    pubkey: pubkey,
    content: trimmed,
    createdAt: DateTime.now(),
    authorName: userName ?? pubkey.substring(0, 8),
    authorPicture: userPicture,
    isPending: true,
  );

  // Apply optimistic updates.
  _addOptimisticComment(ref, url, pendingComment);
  _applyOptimistic(ref, url, const _OptimisticOverride(commentDelta: 1));
  _markPending(ref, url, _SocialAction.comment);

  // Publish in background.
  try {
    final nostr = ref.read(nostrServiceProvider);
    await nostr.publishCommentForUrl(url, trimmed);
  } on Object {
    // Roll back.
    _removeOptimisticComment(ref, url, pendingComment.eventId);
    _clearOptimistic(ref, url);
  } finally {
    _clearPending(ref, url, _SocialAction.comment);
    // Refresh real data from relays.
    ref.invalidate(_rawNostrStatsForUrlProvider(url));
    ref.invalidate(_rawNostrCommentsProvider(url));
  }
  return true;
}

/// Reposts content via its URL on Nostr (kind 6 with `r` tag).
///
/// **Optimistic:** Immediately shows repost state.
///
/// Returns `true` if identity is configured, `false` otherwise.
Future<bool> repostUrl(
  WidgetRef ref, {
  required String url,
  String? comment,
}) async {
  if (url.isEmpty) return false;

  final pubkey = await _ensureIdentity(ref);
  if (pubkey == null) return false;

  // Optimistic update.
  _applyOptimistic(
    ref,
    url,
    const _OptimisticOverride(repostDelta: 1, userReposted: true),
  );
  _markPending(ref, url, _SocialAction.repost);

  try {
    final nostr = ref.read(nostrServiceProvider);
    await nostr.publishRepostForUrl(url, comment: comment);
  } on Object {
    _clearOptimistic(ref, url);
  } finally {
    _clearPending(ref, url, _SocialAction.repost);
    ref.invalidate(_rawNostrStatsForUrlProvider(url));
  }
  return true;
}

// =============================================================================
// Optimistic comment helpers
// =============================================================================

void _addOptimisticComment(WidgetRef ref, String url, NostrComment comment) {
  final map = Map<String, List<NostrComment>>.from(
    ref.read(_optimisticCommentsProvider),
  );
  map[url] = [comment, ...(map[url] ?? [])];
  ref.read(_optimisticCommentsProvider.notifier).state = map;
}

void _removeOptimisticComment(WidgetRef ref, String url, String eventId) {
  final map = Map<String, List<NostrComment>>.from(
    ref.read(_optimisticCommentsProvider),
  );
  final list = map[url];
  if (list != null) {
    map[url] = list.where((c) => c.eventId != eventId).toList();
    if (map[url]!.isEmpty) map.remove(url);
  }
  ref.read(_optimisticCommentsProvider.notifier).state = map;
}

// =============================================================================
// Public refresh helper
// =============================================================================

/// Forces a re-fetch of social stats and comments for a URL from relays.
///
/// Call this from the UI refresh button to get fresh data.
void refreshNostrSocial(WidgetRef ref, String url) {
  ref.invalidate(_rawNostrStatsForUrlProvider(url));
  ref.invalidate(_rawNostrCommentsProvider(url));
  // Also clear any stale optimistic overrides.
  _clearOptimistic(ref, url);
  final map = Map<String, List<NostrComment>>.from(
    ref.read(_optimisticCommentsProvider),
  );
  map.remove(url);
  ref.read(_optimisticCommentsProvider.notifier).state = map;
}

// =============================================================================
// Nostr feed providers
// =============================================================================

/// Watches Nostr notes from the knowledge store.
final nostrNotesProvider = FutureProvider<List<NostrNoteData>>((ref) async {
  final store = ref.watch(knowledgeStoreProvider);
  return store.listNostrNotes(limit: 100);
});

/// The contact list (followed pubkeys) of the current user.
final nostrContactsProvider = FutureProvider<List<String>>((ref) async {
  final nostr = ref.watch(nostrServiceProvider);
  return nostr.fetchContactList();
});

/// Fetches a cached Nostr profile by pubkey.
///
/// Shared provider used across thread view, profile view, search,
/// and topic feeds to avoid duplicate network requests.
final profileForPubkeyProvider =
    FutureProvider.family<NostrProfile?, String>((ref, pubkey) async {
  final nostr = ref.watch(nostrServiceProvider);
  return nostr.fetchProfileCached(pubkey);
});

/// Fetches Nostr global feed and stores notes in the knowledge store.
///
/// Each note is persisted both as a `kabuk:NostrNote` (for the social layer:
/// reactions, replies, reposts) and as a `schema:Article` tagged with the
/// `nostr:global` feed source so it appears in the Explore feed's "Nostr" chip.
///
/// Returns the number of new notes ingested. Bounded by [limit] and a short
/// timeout so it never stalls the surrounding refresh pass.
Future<int> refreshNostrFeed(WidgetRef ref, {int limit = 50}) async {
  final nostr = ref.read(nostrServiceProvider);
  final store = ref.read(knowledgeStoreProvider);

  final existingUrlIndex = await store.listArticleUrlIndex();

  return processNostrEvents(
    nostr.fetchGlobalFeed(limit: limit),
    where: (e) => e.kind == NostrKind.textNote,
    limit: limit,
    timeout: const Duration(seconds: 4),
    onEvent: (event) async {
      // Deduplicate.
      final existing = await store.findNostrNoteByEventId(event.id);
      if (existing != null) return;

      // Resolve author profile (best effort).
      String? authorName;
      String? authorPicture;
      try {
        final profile = await nostr.fetchProfile(event.pubkey);
        if (profile != null) {
          final meta = jsonDecode(profile.content) as Map<String, dynamic>;
          authorName = meta['name'] as String?;
          authorPicture = meta['picture'] as String?;
        }
      } on Object {
        // Profile fetch failed — proceed without.
      }

      await store.createNostrNote(
        event: event,
        authorName: authorName,
        authorPicture: authorPicture,
      );

      // Persist as a schema:Article so the global Nostr feed shows up in the
      // Explore feed. Dedup by 'nostr:<eventId>' URL.
      final items = nostrEventsToFeedItems([event]);
      for (final item in items) {
        if (existingUrlIndex.containsKey(item.url)) continue;
        await store.createArticle(
          title: item.title,
          description: item.description,
          url: item.url,
          image: item.imageUrl,
          author: item.author,
          feedSource: 'nostr:global',
          datePublished: item.datePublished,
          tags: item.categories,
        );
        existingUrlIndex[item.url] = '';
      }
    },
  );
}
