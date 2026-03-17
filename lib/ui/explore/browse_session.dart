/// Browse session — a temporary, un-subscribed feed view.
///
/// Holds the state for content that the user is browsing inline in the
/// Explore view (e.g. `r/nostr`, an RSS URL, a 4chan board, or a Nostr
/// profile) without adding it to their subscribed feeds.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/services/nostr_utils.dart';
import 'package:kabuk/ui/explore/explore_view.dart' show ExploreView, friendlyError;

// =============================================================================
// Data classes
// =============================================================================

/// An active browse session for a content source.
class BrowseSession {
  /// Creates a [BrowseSession].
  const BrowseSession({
    required this.url,
    required this.displayName,
    required this.sourceType,
    this.articles = const [],
    this.loading = false,
    this.error = '',
    this.nextCursor,
    this.loadingMore = false,
  });

  /// Canonical URL / identifier for the browsed source.
  ///
  /// For Reddit this is the `r/name` string; for RSS the full URL;
  /// for 4chan `4chan://board`; for Nostr profiles the hex pubkey.
  final String url;

  /// Human-readable display name shown in the UI (e.g. `r/nostr`, `/g/`).
  final String displayName;

  /// Source type string matching FeedSourceType.name, or `'nostr_profile'`.
  final String sourceType;

  /// Articles fetched from the source (in-memory, not persisted to the store).
  final List<ArticleData> articles;

  /// True while the initial fetch is in progress.
  final bool loading;

  /// Non-empty when the last fetch failed — contains the error message.
  final String error;

  /// Pagination cursor (Reddit `after` token, etc.).
  final String? nextCursor;

  /// True while an additional page is loading.
  final bool loadingMore;

  /// Returns a copy of this session with the given fields overridden.
  BrowseSession copyWith({
    String? url,
    String? displayName,
    String? sourceType,
    List<ArticleData>? articles,
    bool? loading,
    String? error,
    String? nextCursor,
    bool? loadingMore,
  }) => BrowseSession(
    url: url ?? this.url,
    displayName: displayName ?? this.displayName,
    sourceType: sourceType ?? this.sourceType,
    articles: articles ?? this.articles,
    loading: loading ?? this.loading,
    error: error ?? this.error,
    nextCursor: nextCursor ?? this.nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

// =============================================================================
// Helpers
// =============================================================================

/// Converts a [FeedItem] to an [ArticleData] for in-memory browse display.
///
/// The resulting [ArticleData] is NOT persisted to the knowledge store —
/// its URI uses the `browse://` scheme as a stable in-memory identifier.
ArticleData browseItemToArticle(FeedItem item, String feedSource) =>
    ArticleData(
      uri: 'browse://${Uri.encodeComponent(item.url)}',
      name: item.title,
      description: item.description,
      url: item.url,
      author: item.author,
      image: item.imageUrl,
      feedSource: feedSource,
      datePublished: item.datePublished,
      tags: item.categories,
      galleryImages: item.galleryImages,
    );

// =============================================================================
// Notifier
// =============================================================================

/// Manages the active [BrowseSession].
class BrowseNotifier extends StateNotifier<BrowseSession?> {
  /// Creates a [BrowseNotifier].
  BrowseNotifier(this._ref) : super(null);

  final Ref _ref;

  /// Starts browsing [url].
  ///
  /// If the same URL is already loaded, re-uses the cached articles.
  /// [sourceType] must match FeedSourceType.name or be `'nostr_profile'`.
  Future<void> browse(String url, String displayName, String sourceType) async {
    // Cache hit — same URL already loaded successfully.
    final s = state;
    if (s != null &&
        s.url == url &&
        s.articles.isNotEmpty &&
        !s.loading &&
        s.error.isEmpty) {
      return;
    }

    state = BrowseSession(
      url: url,
      displayName: displayName,
      sourceType: sourceType,
      loading: true,
    );

    try {
      if (sourceType == 'nostr_profile') {
        await _browseNostrProfile(url, displayName);
        return;
      }

      final feedService = _ref.read(feedServiceProvider);
      final type = FeedSourceType.values.firstWhere(
        (t) => t.name == sourceType,
        orElse: () => FeedSourceType.rss,
      );
      final result = await feedService.fetchItemsPage(url, type: type);
      final articles = result.items
          .map((i) => browseItemToArticle(i, 'browse:$url'))
          .toList();

      state = BrowseSession(
        url: url,
        displayName: displayName,
        sourceType: sourceType,
        articles: articles,
        nextCursor: result.nextCursor,
      );
    } on Object catch (e) {
      state = BrowseSession(
        url: url,
        displayName: displayName,
        sourceType: sourceType,
        error: friendlyError(e),
      );
    }
  }

  /// Fetches a Nostr user profile and their recent notes.
  Future<void> _browseNostrProfile(String pubkeyHex, String displayName) async {
    try {
      final nostr = _ref.read(nostrServiceProvider);
      final profile = await nostr.fetchProfileCached(pubkeyHex);

      final events = await collectNostrEvents(
        nostr.subscribe([
          NostrFilter(
            authors: [pubkeyHex],
            kinds: [NostrKind.textNote],
            limit: 50,
          ),
        ]),
        timeout: const Duration(seconds: 6),
      );
      events.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final profileName = (profile?.displayName.isNotEmpty == true)
          ? profile!.displayName
          : displayName;
      final avatarUrl = profile?.picture;

      final articles = events.map((e) {
        final preview = e.content.length > 300
            ? '${e.content.substring(0, 300)}...'
            : e.content;
        return ArticleData(
          uri: 'browse://nostr/${e.id}',
          name: preview,
          description: profile?.about,
          url: 'https://njump.me/${e.id}',
          author: profileName,
          image: avatarUrl,
          feedSource: 'browse:nostr:$pubkeyHex',
          datePublished: DateTime.fromMillisecondsSinceEpoch(
            e.createdAt * 1000,
            isUtc: true,
          ),
          tags: const [],
          galleryImages: const [],
        );
      }).toList();

      state = BrowseSession(
        url: pubkeyHex,
        displayName: profileName,
        sourceType: 'nostr_profile',
        articles: articles,
      );
    } on Object catch (e) {
      if (state?.url == pubkeyHex) {
        state = state!.copyWith(loading: false, error: friendlyError(e));
      }
    }
  }

  /// Loads the next page of results for the current session.
  Future<void> loadMore() async {
    final s = state;
    if (s == null ||
        s.loadingMore ||
        s.nextCursor == null ||
        s.sourceType == 'nostr_profile') {
      return;
    }

    state = s.copyWith(loadingMore: true, error: '');

    try {
      final feedService = _ref.read(feedServiceProvider);
      final type = FeedSourceType.values.firstWhere(
        (t) => t.name == s.sourceType,
        orElse: () => FeedSourceType.rss,
      );
      final result = await feedService.fetchItemsPage(
        s.url,
        type: type,
        cursor: s.nextCursor,
      );
      final seen = s.articles.map((a) => a.url).toSet();
      final newArticles = result.items
          .map((i) => browseItemToArticle(i, 'browse:${s.url}'))
          .where((a) => !seen.contains(a.url))
          .toList();

      state = s.copyWith(
        articles: [...s.articles, ...newArticles],
        nextCursor: result.nextCursor,
        loadingMore: false,
      );
    } on Object catch (e) {
      state = s.copyWith(loadingMore: false, error: friendlyError(e));
    }
  }

  /// Clears the current browse session.
  void clear() => state = null;
}

// =============================================================================
// Provider
// =============================================================================

/// Singleton provider for the active [BrowseSession].
///
/// Watch this in [ExploreView] to switch the feed into browse mode.
final browseSessionProvider =
    StateNotifierProvider<BrowseNotifier, BrowseSession?>(
      BrowseNotifier.new,
    );
