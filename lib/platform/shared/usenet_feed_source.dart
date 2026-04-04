/// Usenet feed source implementation.
///
/// Maps Newznab indexer search results to [FeedItem]s, enabling Usenet
/// releases to appear in the unified feed alongside RSS, Reddit, and
/// other sources.
///
/// Uses [UsenetService] for indexer management and [NewznabClient] for
/// querying. All credentials are vault-managed — the feed source never
/// handles raw API keys.
library;

import 'dart:developer' as dev;

import 'package:kabuk/platform/shared/usenet/newznab_client.dart';
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/usenet.dart';

/// [FeedSource] implementation for Usenet indexer search results.
///
/// Supports URLs in the forms:
/// - `usenet://search?q=query` — general search across all indexers
/// - `usenet://category/movies` — browse by category
/// - `usenet://category/tvShows` — browse by category
/// - `usenet://indexer/{indexerId}/search?q=query` — search specific indexer
class UsenetFeedSource implements FeedSource {
  /// Creates a [UsenetFeedSource].
  ///
  /// The [usenetService] provides access to configured indexers.
  /// The [clientFactory] builds a [NewznabClient] for a given base URL
  /// and API key — injectable for testing.
  UsenetFeedSource({
    required UsenetService usenetService,
    required NewznabClient Function({
      required String baseUrl,
      required String apiKey,
    }) clientFactory,
  })  : _usenetService = usenetService,
        _clientFactory = clientFactory;

  final UsenetService _usenetService;
  final NewznabClient Function({
    required String baseUrl,
    required String apiKey,
  }) _clientFactory;

  @override
  FeedSourceType get type => FeedSourceType.usenet;

  @override
  Future<List<FeedItem>> fetch(String url) async {
    final parsed = _parseUsenetUrl(url);
    if (parsed == null) {
      throw UsenetFeedException('Invalid Usenet feed URL: $url');
    }

    final indexers = await _usenetService.getIndexers();
    final enabled = indexers.where((i) => i.enabled).toList();
    if (enabled.isEmpty) return const [];

    switch (parsed) {
      case _UsenetSearch(:final query, :final indexerId, :final category):
        final categoryIds = category != null
            ? _categoryToNewznabIds(category)
            : null;
        return _search(query, enabled,
            indexerId: indexerId, categories: categoryIds);
      case _UsenetCategory(:final category):
        return _browseCategory(category, enabled);
    }
  }

  @override
  Future<bool> validate(String url) async {
    return _parseUsenetUrl(url) != null;
  }

  // ---------------------------------------------------------------------------
  // Search / browse
  // ---------------------------------------------------------------------------

  /// Searches indexers for [query], optionally filtering to a single indexer
  /// and/or specific Newznab [categories].
  Future<List<FeedItem>> _search(
    String query,
    List<UsenetIndexer> indexers, {
    String? indexerId,
    List<int>? categories,
  }) async {
    final targets = indexerId != null
        ? indexers.where((i) => i.id == indexerId).toList()
        : indexers;

    if (targets.isEmpty) return const [];

    final items = <FeedItem>[];
    for (final indexer in targets) {
      try {
        final client = _clientFactory(
          baseUrl: indexer.baseUrl,
          apiKey: indexer.apiKeyRef,
        );
        final result = await client.search(query, categories: categories);
        items.addAll(result.items.map(_toFeedItem));
      } on Object catch (e) {
        dev.log(
          'UsenetFeedSource: search failed on ${indexer.name}: $e',
          name: 'UsenetFeedSource',
        );
      }
    }

    // Sort newest first.
    items.sort((a, b) => (b.datePublished ?? DateTime(0))
        .compareTo(a.datePublished ?? DateTime(0)));
    return items;
  }

  /// Browses a category across all enabled indexers.
  Future<List<FeedItem>> _browseCategory(
    UsenetCategory category,
    List<UsenetIndexer> indexers,
  ) async {
    final categoryIds = _categoryToNewznabIds(category);
    if (categoryIds.isEmpty) return const [];

    final items = <FeedItem>[];
    for (final indexer in indexers) {
      try {
        final client = _clientFactory(
          baseUrl: indexer.baseUrl,
          apiKey: indexer.apiKeyRef,
        );
        // Browse by category uses an empty query with a category filter.
        final result = await client.search('', categories: categoryIds);
        items.addAll(result.items.map(_toFeedItem));
      } on Object catch (e) {
        dev.log(
          'UsenetFeedSource: category browse failed on ${indexer.name}: $e',
          name: 'UsenetFeedSource',
        );
      }
    }

    items.sort((a, b) => (b.datePublished ?? DateTime(0))
        .compareTo(a.datePublished ?? DateTime(0)));
    return items;
  }

  // ---------------------------------------------------------------------------
  // Mapping
  // ---------------------------------------------------------------------------

  /// Converts a [NewznabItem] to a [FeedItem].
  static FeedItem _toFeedItem(NewznabItem release) {
    return FeedItem(
      title: release.title,
      url: release.nzbUrl,
      description: _buildDescription(release),
      author: release.poster,
      imageUrl: null, // Poster fetching can be added later.
      datePublished: release.publishedAt,
      identifier: release.guid,
      categories: [
        if (release.category != null) release.category!,
        ...release.attributes.values,
      ],
    );
  }

  /// Builds a human-readable description from a Newznab item.
  ///
  /// Format: `"{humanSize} • {category} • {attributes joined by ', '}"`.
  static String _buildDescription(NewznabItem release) {
    final parts = <String>[
      _humanizeBytes(release.sizeBytes),
      if (release.category != null) release.category!,
      if (release.attributes.isNotEmpty)
        release.attributes.values.join(', '),
    ];
    return parts.join(' • ');
  }

  /// Converts a byte count to a human-readable size string.
  static String _humanizeBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const suffixes = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var i = 0;
    while (value >= 1024 && i < suffixes.length - 1) {
      value /= 1024;
      i++;
    }
    return '${value.toStringAsFixed(1)} ${suffixes[i]}';
  }

  // ---------------------------------------------------------------------------
  // URL parsing
  // ---------------------------------------------------------------------------

  /// Parses a `usenet://` URL into a typed command.
  static _UsenetUrlParsed? _parseUsenetUrl(String url) {
    final trimmed = url.trim();
    if (!trimmed.startsWith('usenet://')) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    final host = uri.host;
    final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    // usenet://search?q=query[&cat=categoryName]
    if (host == 'search') {
      final query = uri.queryParameters['q'] ?? '';
      final catParam = uri.queryParameters['cat'];
      final category = catParam != null ? _parseCategory(catParam) : null;
      return _UsenetSearch(query: query, category: category);
    }

    // usenet://category/{categoryName}
    if (host == 'category' && pathSegments.isNotEmpty) {
      final category = _parseCategory(pathSegments.first);
      if (category != null) return _UsenetCategory(category: category);
    }

    // usenet://indexer/{indexerId}/search?q=query
    if (host == 'indexer' && pathSegments.length >= 2) {
      final indexerId = pathSegments[0];
      if (pathSegments[1] == 'search') {
        final query = uri.queryParameters['q'] ?? '';
        return _UsenetSearch(query: query, indexerId: indexerId);
      }
    }

    return null;
  }

  /// Maps a category name from the URL to a [UsenetCategory].
  static UsenetCategory? _parseCategory(String name) {
    return switch (name) {
      'movies' => UsenetCategory.movies,
      'tvShows' || 'tv' => UsenetCategory.tvShows,
      'music' => UsenetCategory.music,
      'games' => UsenetCategory.games,
      'software' => UsenetCategory.software,
      'books' => UsenetCategory.books,
      'audio' => UsenetCategory.audio,
      'other' => UsenetCategory.other,
      _ => null,
    };
  }

  /// Maps a [UsenetCategory] to Newznab numeric category IDs.
  static List<int> _categoryToNewznabIds(UsenetCategory category) {
    return switch (category) {
      UsenetCategory.movies => [NewznabCategoryId.movies],
      UsenetCategory.tvShows => [NewznabCategoryId.tv],
      UsenetCategory.music => [NewznabCategoryId.audio],
      UsenetCategory.games => [NewznabCategoryId.console],
      UsenetCategory.software => [NewznabCategoryId.pc],
      UsenetCategory.books => [NewznabCategoryId.books],
      UsenetCategory.audio => [NewznabCategoryId.audio],
      UsenetCategory.other => [NewznabCategoryId.other],
    };
  }
}

// ---------------------------------------------------------------------------
// Internal URL parse types
// ---------------------------------------------------------------------------

sealed class _UsenetUrlParsed {}

class _UsenetSearch extends _UsenetUrlParsed {
  _UsenetSearch({required this.query, this.indexerId, this.category});
  final String query;
  final String? indexerId;
  final UsenetCategory? category;
}

class _UsenetCategory extends _UsenetUrlParsed {
  _UsenetCategory({required this.category});
  final UsenetCategory category;
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Exception thrown by [UsenetFeedSource].
class UsenetFeedException implements Exception {
  /// Creates a [UsenetFeedException] with a descriptive [message].
  const UsenetFeedException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'UsenetFeedException: $message';
}
