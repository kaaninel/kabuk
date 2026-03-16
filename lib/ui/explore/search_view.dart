/// Enhanced search view — full-screen unified search across local store and Nostr.
///
/// Combines [KnowledgeStore.search] for local data with Nostr relay
/// search ([searchContent] for NIP-50, [searchByHashtag] for hashtags).
/// Supports search history via SavedSearch, inline result display,
/// and profile search.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/saved_search.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/services/nostr_utils.dart';
import 'package:kabuk/ui/explore/nostr_providers.dart';
import 'package:kabuk/ui/explore/profile_view.dart';
import 'package:kabuk/ui/explore/thread_view.dart';
import 'package:kabuk/ui/shared/error_retry.dart';
import 'package:kabuk/ui/shared/feed_image.dart';
import 'package:kabuk/ui/shared/nostr_author_row.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// Search result model
// =============================================================================

/// Unified search result from either local or Nostr sources.
sealed class SearchResult {
  const SearchResult();
}

/// A local knowledge store result.
final class LocalSearchResult extends SearchResult {
  /// Creates a [LocalSearchResult].
  const LocalSearchResult({
    required this.uri,
    required this.predicate,
    required this.value,
  });

  /// The entity URI.
  final String uri;

  /// The matching predicate.
  final String predicate;

  /// The matching value text.
  final String value;
}

/// A Nostr note result.
final class NostrNoteResult extends SearchResult {
  /// Creates a [NostrNoteResult].
  const NostrNoteResult({required this.event});

  /// The matching event.
  final NostrEvent event;
}

/// A Nostr profile result.
final class NostrProfileResult extends SearchResult {
  /// Creates a [NostrProfileResult].
  const NostrProfileResult({required this.profile});

  /// The matching profile.
  final NostrProfile profile;
}

// =============================================================================
// Providers
// =============================================================================

/// Search query state — triggers search.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Combined search results from both local and Nostr.
final searchResultsProvider = FutureProvider<List<SearchResult>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return [];

  final store = ref.watch(knowledgeStoreProvider);
  final nostr = ref.watch(nostrServiceProvider);

  final results = <SearchResult>[];

  // 1. Local knowledge store search.
  try {
    final localTriples = await store.search(query, limit: 20);
    final seen = <String>{};
    for (final triple in localTriples) {
      if (seen.add(triple.subject)) {
        results.add(
          LocalSearchResult(
            uri: triple.subject,
            predicate: triple.predicate,
            value: triple.objectValue,
          ),
        );
      }
    }
  } on Object {
    // Local search failed — continue with remote.
  }

  // 2. Nostr relay search — hashtag or NIP-50 depending on query.
  try {
    final isHashtag =
        query.startsWith('#') || (!query.contains(' ') && query.length < 30);

    final List<NostrEvent> nostrEvents;
    if (isHashtag) {
      final tag = query.replaceAll('#', '').toLowerCase();
      nostrEvents = await collectNostrEvents(
        nostr.searchByHashtag([tag], limit: 30),
        timeout: const Duration(seconds: 6),
      );
    } else {
      nostrEvents = await collectNostrEvents(
        nostr.searchContent(query, limit: 30),
        timeout: const Duration(seconds: 6),
      );
    }

    // Deduplicate.
    final seenEvents = <String>{};
    for (final e in nostrEvents) {
      if (seenEvents.add(e.id)) {
        results.add(NostrNoteResult(event: e));
      }
    }
  } on Object {
    // Nostr search failed — show local results only.
  }

  return results;
});

/// Recent search queries (saved searches with source 'nostr_search' or 'local').
final recentSearchesProvider = FutureProvider<List<SavedSearchData>>((
  ref,
) async {
  final store = ref.watch(knowledgeStoreProvider);
  final all = await store.listSavedSearches(limit: 10);
  return all
      .where((s) => s.source == 'nostr_search' || s.source == 'local')
      .toList();
});

// =============================================================================
// Search View
// =============================================================================

/// Full-screen search view with combined local + Nostr results.
class SearchView extends ConsumerStatefulWidget {
  /// Creates a [SearchView].
  const SearchView({super.key});

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _isDebouncing = false;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() => _isDebouncing = value.trim().isNotEmpty);
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(searchQueryProvider.notifier).state = value.trim();
      if (mounted) setState(() => _isDebouncing = false);
    });
  }

  Future<void> _saveSearch(String query) async {
    if (query.trim().isEmpty) return;
    final store = ref.read(knowledgeStoreProvider);
    final isHashtag = query.startsWith('#') || !query.contains(' ');
    await store.createSavedSearch(
      name: query,
      queryText: query,
      source: isHashtag ? 'nostr_hashtag' : 'nostr_search',
    );
    ref.invalidate(recentSearchesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final resultsAsync = ref.watch(searchResultsProvider);
    final recentAsync = ref.watch(recentSearchesProvider);

    return Scaffold(
      backgroundColor: KabukTheme.background,
      appBar: AppBar(
        backgroundColor: KabukTheme.surface,
        foregroundColor: KabukTheme.textPrimary,
        elevation: 0,
        titleSpacing: 0,
        title: _buildSearchField(),
        actions: [
          if (query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined, size: 20),
              onPressed: () => _saveSearch(query),
              tooltip: 'Save search',
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isDebouncing)
            const LinearProgressIndicator(
              minHeight: 2,
              color: KabukTheme.primaryGreen,
              backgroundColor: Colors.transparent,
            ),
          Expanded(
            child: query.isEmpty
                ? _buildRecentSearches(recentAsync)
                : _buildResults(resultsAsync),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _controller,
      autofocus: true,
      onChanged: _onQueryChanged,
      style: const TextStyle(color: KabukTheme.textPrimary, fontSize: 16),
      decoration: InputDecoration(
        hintText: 'Search notes, topics, profiles...',
        hintStyle: const TextStyle(color: KabukTheme.textTertiary),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingMd,
          vertical: KabukTheme.spacingSm,
        ),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                color: KabukTheme.textTertiary,
                onPressed: () {
                  _controller.clear();
                  _debounce?.cancel();
                  ref.read(searchQueryProvider.notifier).state = '';
                  setState(() => _isDebouncing = false);
                },
              )
            : null,
      ),
    );
  }

  Widget _buildRecentSearches(AsyncValue<List<SavedSearchData>> recentAsync) {
    return recentAsync.when(
      data: (recent) {
        if (recent.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 48,
                  color: KabukTheme.textTertiary,
                ),
                SizedBox(height: KabukTheme.spacingMd),
                Text(
                  'Search across your local data\nand the Nostr network',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: KabukTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(KabukTheme.spacingMd),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: KabukTheme.spacingSm),
              child: Text(
                'Recent Searches',
                style: TextStyle(
                  color: KabukTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...recent.map(
              (s) => ListTile(
                leading: Icon(
                  s.source == 'nostr_hashtag'
                      ? Icons.tag_rounded
                      : Icons.history_rounded,
                  color: KabukTheme.textTertiary,
                  size: 20,
                ),
                title: Text(
                  s.name ?? s.query ?? 'Unknown',
                  style: const TextStyle(
                    color: KabukTheme.textPrimary,
                    fontSize: 14,
                  ),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
                onTap: () {
                  _controller.text = s.query ?? '';
                  ref.read(searchQueryProvider.notifier).state = s.query ?? '';
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildResults(AsyncValue<List<SearchResult>> resultsAsync) {
    return resultsAsync.when(
      data: (results) {
        if (results.isEmpty) {
          return const Center(
            child: Text(
              'No results found',
              style: TextStyle(color: KabukTheme.textSecondary),
            ),
          );
        }

        // Group results by type.
        final local = results.whereType<LocalSearchResult>().toList();
        final notes = results.whereType<NostrNoteResult>().toList();
        final profiles = results.whereType<NostrProfileResult>().toList();

        return ListView(
          padding: const EdgeInsets.all(KabukTheme.spacingMd),
          children: [
            if (local.isNotEmpty) ...[
              _sectionHeader('Local', Icons.storage_rounded),
              ...local.map((r) => _LocalResultTile(result: r)),
              const SizedBox(height: KabukTheme.spacingMd),
            ],
            if (profiles.isNotEmpty) ...[
              _sectionHeader('Profiles', Icons.person_rounded),
              ...profiles.map((r) => _ProfileResultTile(profile: r.profile)),
              const SizedBox(height: KabukTheme.spacingMd),
            ],
            if (notes.isNotEmpty) ...[
              _sectionHeader('Nostr Notes', Icons.chat_bubble_outline),
              ...notes.map((r) => _NoteResultTile(event: r.event)),
            ],
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: KabukTheme.primaryGreen),
      ),
      error: (e, _) => ErrorRetryWidget.fromError(
        e,
        onRetry: () => ref.invalidate(searchResultsProvider),
      ),
    );
  }

  Widget _sectionHeader(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
      child: Row(
        children: [
          Icon(icon, size: 16, color: KabukTheme.textSecondary),
          const SizedBox(width: KabukTheme.spacingSm),
          Text(
            label,
            style: const TextStyle(
              color: KabukTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Result tiles
// =============================================================================

/// Tile for a local knowledge store result.
class _LocalResultTile extends StatelessWidget {
  const _LocalResultTile({required this.result});

  final LocalSearchResult result;

  @override
  Widget build(BuildContext context) {
    // Extract a readable label from the predicate.
    final predicate = result.predicate.split('/').last.split('#').last;
    return Container(
      margin: const EdgeInsets.only(bottom: KabukTheme.spacingXs),
      padding: const EdgeInsets.all(KabukTheme.spacingSm),
      decoration: BoxDecoration(
        color: KabukTheme.cardColor,
        borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            predicate,
            style: const TextStyle(
              color: KabukTheme.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            result.value,
            style: const TextStyle(color: KabukTheme.textPrimary, fontSize: 13),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Tile for a Nostr note result.
class _NoteResultTile extends ConsumerWidget {
  const _NoteResultTile({required this.event});

  final NostrEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileForPubkeyProvider(event.pubkey));

    return InkWell(
      borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ThreadView(eventId: event.id, rootEvent: event),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        decoration: BoxDecoration(
          color: KabukTheme.cardColor,
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author
            profileAsync.when(
              data: (p) => NostrAuthorRow(
                name: p?.displayName ?? '${event.pubkey.substring(0, 8)}...',
                picture: p?.picture,
                createdAt: event.createdAt,
                size: AuthorRowSize.compact,
                nameColor: KabukTheme.textSecondary,
                nameWeight: FontWeight.w500,
              ),
              loading: () => NostrAuthorRow(
                name: '${event.pubkey.substring(0, 8)}...',
                createdAt: event.createdAt,
                size: AuthorRowSize.compact,
                nameColor: KabukTheme.textSecondary,
                nameWeight: FontWeight.w500,
              ),
              error: (_, _) => NostrAuthorRow(
                name: '${event.pubkey.substring(0, 8)}...',
                createdAt: event.createdAt,
                size: AuthorRowSize.compact,
                nameColor: KabukTheme.textSecondary,
                nameWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: KabukTheme.spacingXs),
            Text(
              event.content,
              style: const TextStyle(
                color: KabukTheme.textPrimary,
                fontSize: 13,
                height: 1.4,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tile for a Nostr profile result.
class _ProfileResultTile extends StatelessWidget {
  const _ProfileResultTile({required this.profile});

  final NostrProfile profile;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProfileView(pubkey: profile.pubkey),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        decoration: BoxDecoration(
          color: KabukTheme.cardColor,
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
        child: Row(
          children: [
            if (profile.picture != null)
              ClipOval(
                child: FeedImage(
                  imageUrl: profile.picture!,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              )
            else
              CircleAvatar(
                radius: 20,
                backgroundColor: KabukTheme.surfaceVariant,
                child: Text(
                  profile.displayName.isNotEmpty
                      ? profile.displayName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: KabukTheme.textSecondary,
                    fontSize: 16,
                  ),
                ),
              ),
            const SizedBox(width: KabukTheme.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.displayName,
                    style: const TextStyle(
                      color: KabukTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (profile.nip05 != null)
                    Text(
                      profile.nip05!,
                      style: const TextStyle(
                        color: KabukTheme.purpleAccent,
                        fontSize: 12,
                      ),
                    ),
                  if (profile.about != null && profile.about!.isNotEmpty)
                    Text(
                      profile.about!,
                      style: const TextStyle(
                        color: KabukTheme.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: KabukTheme.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
