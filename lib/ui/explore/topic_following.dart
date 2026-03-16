/// Topic following — providers and UI for following Nostr hashtags.
///
/// Leverages the existing [SavedSearch] knowledge type with
/// `source: 'nostr_hashtag'` to persist followed topics. Provides
/// Riverpod providers for listing/toggling followed topics and
/// a feed filtered by followed hashtags.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/saved_search.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/services/nostr_utils.dart';
import 'package:kabuk/ui/explore/nostr_providers.dart';
import 'package:kabuk/ui/shared/nostr_author_row.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// Providers
// =============================================================================

/// All followed topics (saved searches with `source == 'nostr_hashtag'`).
final followedTopicsProvider = FutureProvider<List<SavedSearchData>>((
  ref,
) async {
  final store = ref.watch(knowledgeStoreProvider);
  final all = await store.listSavedSearches();
  return all.where((s) => s.source == 'nostr_hashtag').toList();
});

/// Whether a specific hashtag is followed.
final isTopicFollowedProvider = FutureProvider.family<bool, String>((
  ref,
  hashtag,
) async {
  final topics = await ref.watch(followedTopicsProvider.future);
  return topics.any((s) => s.query?.toLowerCase() == hashtag.toLowerCase());
});

/// Nostr notes matching any followed topic.
final topicFeedProvider = FutureProvider<List<NostrEvent>>((ref) async {
  final topics = await ref.watch(followedTopicsProvider.future);
  if (topics.isEmpty) return [];

  final nostr = ref.watch(nostrServiceProvider);
  final hashtags = topics
      .map((t) => t.query)
      .whereType<String>()
      .map((q) => q.toLowerCase())
      .toList();

  if (hashtags.isEmpty) return [];

  final events = await collectNostrEvents(
    nostr.subscribe([
      NostrFilter(kinds: [NostrKind.textNote], tTags: hashtags, limit: 100),
    ]),
    timeout: const Duration(seconds: 8),
  );

  // Newest first.
  events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return events;
});

// =============================================================================
// Helper functions
// =============================================================================

/// Follows a hashtag topic.
///
/// Creates a SavedSearch with `source: 'nostr_hashtag'` in the
/// knowledge store.
Future<void> followTopic(WidgetRef ref, String hashtag) async {
  final store = ref.read(knowledgeStoreProvider);
  final normalized = hashtag.toLowerCase().replaceAll('#', '');
  await store.createSavedSearch(
    name: '#$normalized',
    queryText: normalized,
    source: 'nostr_hashtag',
  );
  ref.invalidate(followedTopicsProvider);
}

/// Unfollows a hashtag topic.
///
/// Deletes the matching SavedSearch from the knowledge store.
/// Returns silently if the topic is not found (already unfollowed).
Future<void> unfollowTopic(WidgetRef ref, String hashtag) async {
  final store = ref.read(knowledgeStoreProvider);
  final normalized = hashtag.toLowerCase().replaceAll('#', '');
  final topics = await store.listSavedSearches();
  final match = topics
      .where(
        (s) =>
            s.source == 'nostr_hashtag' && s.query?.toLowerCase() == normalized,
      )
      .firstOrNull;
  if (match == null) return; // Already unfollowed or never followed.
  await store.deleteSavedSearch(match.uri);
  ref.invalidate(followedTopicsProvider);
}

/// Toggles following/unfollowing of a hashtag topic.
Future<void> toggleTopic(WidgetRef ref, String hashtag) async {
  final normalized = hashtag.toLowerCase().replaceAll('#', '');
  final isFollowed = await ref.read(isTopicFollowedProvider(normalized).future);
  if (isFollowed) {
    await unfollowTopic(ref, normalized);
  } else {
    await followTopic(ref, normalized);
  }
}

// =============================================================================
// Widgets
// =============================================================================

/// A chip that toggles following a hashtag topic.
class TopicChip extends ConsumerWidget {
  /// Creates a [TopicChip] for the given [hashtag].
  const TopicChip({required this.hashtag, super.key});

  /// The hashtag (without `#` prefix).
  final String hashtag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followedAsync = ref.watch(isTopicFollowedProvider(hashtag));

    final isFollowed = followedAsync.valueOrNull ?? false;
    return ActionChip(
      label: Text(
        '#$hashtag',
        style: TextStyle(
          color: isFollowed
              ? KabukTheme.primaryGreen
              : KabukTheme.textSecondary,
          fontSize: 13,
        ),
      ),
      backgroundColor: isFollowed
          ? KabukTheme.primaryGreen.withValues(alpha: 0.15)
          : KabukTheme.surfaceVariant,
      side: BorderSide(
        color: isFollowed
            ? KabukTheme.primaryGreen.withValues(alpha: 0.4)
            : KabukTheme.divider,
      ),
      onPressed: () => toggleTopic(ref, hashtag),
    );
  }
}

/// A full-screen view showing followed topics and their feed.
class TopicFeedView extends ConsumerWidget {
  /// Creates a [TopicFeedView].
  const TopicFeedView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topicsAsync = ref.watch(followedTopicsProvider);
    final feedAsync = ref.watch(topicFeedProvider);

    return Scaffold(
      backgroundColor: KabukTheme.background,
      appBar: AppBar(
        title: const Text('Topics'),
        backgroundColor: KabukTheme.surface,
        foregroundColor: KabukTheme.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAddTopicDialog(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          // Followed topic chips
          topicsAsync.when(
            data: (topics) {
              if (topics.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(KabukTheme.spacingMd),
                  child: Text(
                    'No followed topics yet. Tap + to add one.',
                    style: TextStyle(color: KabukTheme.textSecondary),
                  ),
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: KabukTheme.spacingMd,
                  vertical: KabukTheme.spacingSm,
                ),
                child: Row(
                  children: topics
                      .map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(
                            right: KabukTheme.spacingXs,
                          ),
                          child: TopicChip(
                            hashtag: t.query ?? t.name ?? 'unknown',
                          ),
                        ),
                      )
                      .toList(),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),

          const Divider(color: KabukTheme.divider, height: 1),

          // Feed
          Expanded(
            child: feedAsync.when(
              data: (events) {
                if (events.isEmpty) {
                  return const Center(
                    child: Text(
                      'No posts in followed topics',
                      style: TextStyle(color: KabukTheme.textSecondary),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(KabukTheme.spacingMd),
                  itemCount: events.length,
                  itemBuilder: (context, index) =>
                      _TopicNoteCard(event: events[index]),
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(
                  color: KabukTheme.primaryGreen,
                ),
              ),
              error: (e, _) => Center(
                child: Text(
                  'Error: $e',
                  style: const TextStyle(color: KabukTheme.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddTopicDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        title: const Text(
          'Follow Topic',
          style: TextStyle(color: KabukTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: KabukTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter hashtag (e.g. bitcoin)',
            hintStyle: const TextStyle(color: KabukTheme.textTertiary),
            prefixText: '# ',
            prefixStyle: const TextStyle(color: KabukTheme.purpleAccent),
            filled: true,
            fillColor: KabukTheme.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: KabukTheme.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                followTopic(ref, text);
                Navigator.of(ctx).pop();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: KabukTheme.primaryGreen,
            ),
            child: const Text('Follow'),
          ),
        ],
      ),
    );
  }
}

/// A compact note card for the topic feed.
class _TopicNoteCard extends ConsumerWidget {
  const _TopicNoteCard({required this.event});

  final NostrEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileForPubkeyProvider(event.pubkey));

    return Container(
      margin: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: BoxDecoration(
        color: KabukTheme.cardColor,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author header
          profileAsync.when(
            data: (profile) => NostrAuthorRow(
              name:
                  profile?.displayName ?? '${event.pubkey.substring(0, 8)}...',
              picture: profile?.picture,
              createdAt: event.createdAt,
            ),
            loading: () => NostrAuthorRow(
              name: '${event.pubkey.substring(0, 8)}...',
              createdAt: event.createdAt,
            ),
            error: (_, _) => NostrAuthorRow(
              name: '${event.pubkey.substring(0, 8)}...',
              createdAt: event.createdAt,
            ),
          ),
          const SizedBox(height: KabukTheme.spacingSm),

          // Content
          Text(
            event.content,
            style: const TextStyle(
              color: KabukTheme.textPrimary,
              fontSize: 14,
              height: 1.5,
            ),
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
          ),

          // Hashtags
          if (event.tags.any((t) => t.isNotEmpty && t[0] == 't')) ...[
            const SizedBox(height: KabukTheme.spacingSm),
            Wrap(
              spacing: KabukTheme.spacingXs,
              runSpacing: KabukTheme.spacingXs,
              children: event.tags
                  .where((t) => t.length >= 2 && t[0] == 't')
                  .map((t) => TopicChip(hashtag: t[1]))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
