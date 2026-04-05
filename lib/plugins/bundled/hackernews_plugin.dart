/// Hacker News content plugin.
///
/// Adapts the Hacker News API (Firebase + Algolia) into [ContentItem]
/// objects. Supports searching via the Algolia HN Search API and
/// fetching trending stories via the official Firebase endpoint.
/// No API key is required.
library;

import 'dart:convert';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show IconData;
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/plugins/context.dart';
import 'package:kabuk/plugins/plugin.dart';
import 'package:meta/meta.dart';

/// Content plugin for Hacker News.
///
/// Capabilities:
/// - **search** — full-text story search via the Algolia HN Search API.
/// - **trending** — top stories from the official HN Firebase endpoint.
///
/// Stories are mapped to [ContentType.article] items with
/// [ArticleMeta] metadata. Self-posts include the story text in the
/// article body; link posts leave it null.
@immutable
class HackerNewsPlugin implements ContentPlugin {
  /// Creates a [HackerNewsPlugin].
  const HackerNewsPlugin();

  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------

  @override
  String get id => 'hackernews';

  @override
  String get name => 'Hacker News';

  @override
  String get description =>
      'Tech news and discussion from news.ycombinator.com.';

  @override
  String get version => '1.0.0';

  @override
  IconData get iconData => Icons.newspaper_outlined;

  @override
  PluginCategory get category => PluginCategory.news;

  @override
  Set<ContentCapability> get capabilities => const {
        ContentCapability.search,
        ContentCapability.trending,
      };

  @override
  List<PluginConfigField> get configFields => const [];

  @override
  bool hasCapability(ContentCapability capability) =>
      capabilities.contains(capability);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Cached context set during [initialize].
  static PluginContext? _context;

  PluginContext get _ctx {
    final ctx = _context;
    if (ctx == null) {
      throw StateError('HackerNewsPlugin has not been initialized.');
    }
    return ctx;
  }

  @override
  Future<void> initialize(PluginContext context) async {
    _context = context;
    context.log('HackerNewsPlugin initialized');
  }

  @override
  Future<void> dispose() async {
    _context = null;
  }

  // ---------------------------------------------------------------------------
  // URL handling
  // ---------------------------------------------------------------------------

  static final _hnUrlPattern = RegExp(
    r'^https?://(www\.)?news\.ycombinator\.com',
  );

  static final _itemIdPattern = RegExp(r'[?&]id=(\d+)');

  @override
  bool canHandleUrl(String url) => _hnUrlPattern.hasMatch(url);

  @override
  Future<ResolvedContent> resolveUrl(String url) async {
    final idMatch = _itemIdPattern.firstMatch(url);
    if (idMatch == null) return const ResolvedNotHandled();

    final storyId = idMatch.group(1)!;
    final story = await _fetchStory(int.parse(storyId));
    if (story == null) return const ResolvedNotHandled();

    return ResolvedContentItem(_storyToContentItem(story));
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  @override
  Future<List<ContentItem>> search(
    String query, {
    int page = 0,
    int perPage = 20,
  }) async {
    final uri = Uri.parse(
      'https://hn.algolia.com/api/v1/search'
      '?query=${Uri.encodeQueryComponent(query)}'
      '&tags=story'
      '&hitsPerPage=$perPage'
      '&page=$page',
    );

    final response = await _ctx.httpClient.get(uri);
    if (response.statusCode != 200) {
      _ctx.log(
        'Algolia search failed',
        error: 'HTTP ${response.statusCode}: ${response.body}',
      );
      return const [];
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final hits = json['hits'] as List<dynamic>? ?? const [];

    return hits.map((hit) {
      final h = hit as Map<String, dynamic>;
      return _algoliaHitToContentItem(h);
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Channel (not supported)
  // ---------------------------------------------------------------------------

  @override
  Future<List<ContentItem>> fetchChannel(
    String entityId, {
    int page = 0,
    int perPage = 20,
  }) {
    throw UnsupportedError('HackerNewsPlugin does not support channels.');
  }

  // ---------------------------------------------------------------------------
  // Trending
  // ---------------------------------------------------------------------------

  @override
  Future<List<ContentItem>> fetchTrending({
    int page = 0,
    int perPage = 20,
  }) async {
    final topUri = Uri.parse(
      'https://hacker-news.firebaseio.com/v0/topstories.json',
    );
    final topResponse = await _ctx.httpClient.get(topUri);
    if (topResponse.statusCode != 200) {
      _ctx.log(
        'Top stories fetch failed',
        error: 'HTTP ${topResponse.statusCode}',
      );
      return const [];
    }

    final allIds = (jsonDecode(topResponse.body) as List<dynamic>)
        .cast<int>();

    // Paginate by slicing the ID list.
    final start = page * perPage;
    if (start >= allIds.length) return const [];
    final end = (start + perPage).clamp(0, allIds.length);
    final pageIds = allIds.sublist(start, end);

    // Fetch story details in parallel.
    final futures = pageIds.map(_fetchStory);
    final stories = await Future.wait(futures);

    return stories
        .where((s) => s != null)
        .map((s) => _storyToContentItem(s!))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Fetch a single story by its HN ID from the Firebase API.
  Future<Map<String, dynamic>?> _fetchStory(int storyId) async {
    final uri = Uri.parse(
      'https://hacker-news.firebaseio.com/v0/item/$storyId.json',
    );
    final response = await _ctx.httpClient.get(uri);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    if (data == null || data is! Map<String, dynamic>) return null;
    return data;
  }

  /// Convert an Algolia search hit to a [ContentItem].
  ContentItem _algoliaHitToContentItem(Map<String, dynamic> hit) {
    final objectId = hit['objectID'] as String? ?? '';
    final title = hit['title'] as String? ?? '';
    final storyUrl = hit['url'] as String?;
    final author = hit['author'] as String? ?? '';
    final createdAt = hit['created_at'] as String?;
    final points = hit['points'] as int? ?? 0;
    final numComments = hit['num_comments'] as int? ?? 0;
    final storyText = hit['story_text'] as String?;

    return ContentItem(
      sourcePluginId: id,
      externalId: objectId,
      contentType: ContentType.article,
      title: title,
      description: '$points points by $author | $numComments comments',
      url: storyUrl ?? 'https://news.ycombinator.com/item?id=$objectId',
      author: ContentAuthor(
        name: author,
        url: 'https://news.ycombinator.com/user?id=$author',
      ),
      publishedAt: createdAt != null ? DateTime.tryParse(createdAt) : null,
      metadata: ArticleMeta(
        body: storyText,
      ),
      extra: {
        'points': points.toString(),
        'commentCount': numComments.toString(),
        'hnId': objectId,
      },
    );
  }

  /// Convert a Firebase story item to a [ContentItem].
  ContentItem _storyToContentItem(Map<String, dynamic> story) {
    final storyId = story['id'] as int? ?? 0;
    final title = story['title'] as String? ?? '';
    final storyUrl = story['url'] as String?;
    final author = story['by'] as String? ?? '';
    final time = story['time'] as int?;
    final score = story['score'] as int? ?? 0;
    final descendants = story['descendants'] as int? ?? 0;
    final text = story['text'] as String?;

    final publishedAt = time != null
        ? DateTime.fromMillisecondsSinceEpoch(time * 1000, isUtc: true)
        : null;

    return ContentItem(
      sourcePluginId: id,
      externalId: storyId.toString(),
      contentType: ContentType.article,
      title: title,
      description: '$score points by $author | $descendants comments',
      url: storyUrl ?? 'https://news.ycombinator.com/item?id=$storyId',
      author: ContentAuthor(
        name: author,
        url: 'https://news.ycombinator.com/user?id=$author',
      ),
      publishedAt: publishedAt,
      metadata: ArticleMeta(
        body: text,
      ),
      extra: {
        'points': score.toString(),
        'commentCount': descendants.toString(),
        'hnId': storyId.toString(),
      },
    );
  }
}
