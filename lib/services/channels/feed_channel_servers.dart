/// Channel servers for Reddit, Nostr, RSS, and Usenet.
///
/// Each source is exposed as an MCP-style [ChannelServer] so any agent (or
/// the omnibar) can invoke it through the shared [ChannelRegistry] — exactly
/// like the `web` server, but for Reddit/Nostr/RSS/Usenet.
///
/// All four are thin adapters over the existing [FeedService], so they reuse
/// the same parsing, dedup, and error behaviour as the feed pipeline.
library;

import 'package:kabuk/services/channels.dart';
import 'package:kabuk/services/feed.dart';

/// Reddit channel — `reddit_list` (subreddit listings) + `reddit_search`.
class RedditChannelServer implements ChannelServer {
  /// Creates a [RedditChannelServer] backed by the given [feedService].
  RedditChannelServer({required FeedService feedService})
      : _feed = feedService;

  final FeedService _feed;

  @override
  String get id => 'reddit';

  @override
  String get name => 'Reddit';

  @override
  String get description =>
      'List subreddit posts and search Reddit. Returns posts with titles, '
      'authors, scores, and links.';

  @override
  List<ChannelTool> listTools() => const [
    ChannelTool(
      name: 'reddit_list',
      description:
          'List posts from a subreddit, sorted by new/hot/top. Returns the '
          'post titles, authors, scores, and URLs.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'subreddit': {'type': 'string', 'description': 'Subreddit name.'},
          'sort': {
            'type': 'string',
            'enum': ['new', 'hot', 'top'],
            'description': 'Sort order (default hot).',
          },
          'limit': {
            'type': 'integer',
            'description': 'Max results (default 10).',
          },
        },
        'required': ['subreddit'],
      },
    ),
    ChannelTool(
      name: 'reddit_search',
      description:
          'Search Reddit for a query. Optionally scoped to one subreddit.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Search query.'},
          'subreddit': {
            'type': 'string',
            'description': 'Scope the search to one subreddit.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Max results (default 10).',
          },
        },
        'required': ['query'],
      },
    ),
  ];

  @override
  List<ChannelResource> listResources() => const [];

  @override
  Future<ChannelResource> readResource(String uri) async =>
      throw ArgumentError('Reddit channel has no resources: $uri');

  @override
  Future<ChannelCallResult> callTool(
    String tool,
    Map<String, dynamic> args,
  ) async {
    return switch (tool) {
      'reddit_list' => _redditList(args),
      'reddit_search' => _redditSearch(args),
      _ => ChannelCallResult.error('Unknown reddit tool "$tool"'),
    };
  }

  Future<ChannelCallResult> _redditList(Map<String, dynamic> args) async {
    final sub = (args['subreddit'] as String? ?? '')
        .replaceFirst(RegExp(r'^r/'), '')
        .trim();
    if (sub.isEmpty) {
      return const ChannelCallResult.error('A subreddit is required.');
    }
    final sort = (args['sort'] as String? ?? 'hot');
    final limit = (args['limit'] as int?) ?? 10;
    final url =
        'https://www.reddit.com/r/$sub/$sort.json'
        '?limit=${limit.clamp(1, 50)}&raw_json=1';
    return _fetchItems(url);
  }

  Future<ChannelCallResult> _redditSearch(Map<String, dynamic> args) async {
    final query = (args['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return const ChannelCallResult.error('A search query is required.');
    }
    final sub = (args['subreddit'] as String? ?? '').trim();
    final limit = (args['limit'] as int?) ?? 10;

    final encoded = Uri.encodeQueryComponent(query);
    final subParam = sub.isNotEmpty
        ? '&restrict_sr=1&sr_name=${Uri.encodeComponent(sub)}'
        : '';
    final url =
        'https://www.reddit.com/search.json'
        '?q=$encoded$subParam&limit=${limit.clamp(1, 50)}&raw_json=1';
    return _fetchItems(url);
  }

  Future<ChannelCallResult> _fetchItems(String url) async {
    try {
      final items = await _feed.fetchItems(url, type: FeedSourceType.reddit);
      if (items.isEmpty) {
        return ChannelCallResult.text('No Reddit posts found.');
      }
      return ChannelCallResult.content(
        items.map(feedItemToContentItem).toList(),
      );
    } on Object catch (e) {
      return ChannelCallResult.error('Reddit fetch failed: $e');
    }
  }
}

/// Nostr channel — `nostr_search` (NIP-50) + `nostr_hashtag`.
class NostrChannelServer implements ChannelServer {
  /// Creates a [NostrChannelServer] backed by the given [feedService].
  NostrChannelServer({required FeedService feedService})
      : _feed = feedService;

  final FeedService _feed;

  @override
  String get id => 'nostr';

  @override
  String get name => 'Nostr';

  @override
  String get description =>
      'Search Nostr notes by query or hashtag. Returns posts with authors, '
      'timestamps, and text.';

  @override
  List<ChannelTool> listTools() => const [
    ChannelTool(
      name: 'nostr_search',
      description:
          'Search Nostr text notes by free-text query (NIP-50). Note: not '
          'all relays support full-text search.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Search query.'},
          'limit': {
            'type': 'integer',
            'description': 'Max results (default 10).',
          },
        },
        'required': ['query'],
      },
    ),
    ChannelTool(
      name: 'nostr_hashtag',
      description:
          'List recent Nostr notes tagged with a hashtag (e.g. bitcoin).',
      inputSchema: {
        'type': 'object',
        'properties': {
          'hashtag': {'type': 'string', 'description': 'Hashtag name.'},
          'limit': {
            'type': 'integer',
            'description': 'Max results (default 10).',
          },
        },
        'required': ['hashtag'],
      },
    ),
  ];

  @override
  List<ChannelResource> listResources() => const [];

  @override
  Future<ChannelResource> readResource(String uri) async =>
      throw ArgumentError('Nostr channel has no resources: $uri');

  @override
  Future<ChannelCallResult> callTool(
    String tool,
    Map<String, dynamic> args,
  ) async {
    return switch (tool) {
      'nostr_search' => _nostrSearch(args),
      'nostr_hashtag' => _nostrHashtag(args),
      _ => ChannelCallResult.error('Unknown nostr tool "$tool"'),
    };
  }

  Future<ChannelCallResult> _nostrSearch(Map<String, dynamic> args) async {
    final query = (args['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return const ChannelCallResult.error('A search query is required.');
    }
    final limit = (args['limit'] as int?) ?? 10;
    return _fetchItems(
      'nostr:search/$query',
      limit: limit,
      empty: 'No Nostr results for "$query".',
    );
  }

  Future<ChannelCallResult> _nostrHashtag(Map<String, dynamic> args) async {
    final hashtag = (args['hashtag'] as String? ?? '')
        .replaceFirst('#', '')
        .trim()
        .toLowerCase();
    if (hashtag.isEmpty) {
      return const ChannelCallResult.error('A hashtag is required.');
    }
    final limit = (args['limit'] as int?) ?? 10;
    return _fetchItems(
      'nostr:t/$hashtag',
      limit: limit,
      empty: 'No Nostr posts for #$hashtag.',
    );
  }

  Future<ChannelCallResult> _fetchItems(
    String url, {
    required int limit,
    required String empty,
  }) async {
    try {
      final items = await _feed.fetchItems(url, type: FeedSourceType.nostr);
      if (items.isEmpty) return ChannelCallResult.text(empty);
      return ChannelCallResult.content(
        items.take(limit).map(feedItemToContentItem).toList(),
      );
    } on Object catch (e) {
      return ChannelCallResult.error('Nostr fetch failed: $e');
    }
  }
}

/// RSS channel — `rss_fetch` (fetch any RSS/Atom feed).
class RssChannelServer implements ChannelServer {
  /// Creates a [RssChannelServer] backed by the given [feedService].
  RssChannelServer({required FeedService feedService}) : _feed = feedService;

  final FeedService _feed;

  @override
  String get id => 'rss';

  @override
  String get name => 'RSS';

  @override
  String get description => 'Fetch and read any RSS/Atom feed.';

  @override
  List<ChannelTool> listTools() => const [
    ChannelTool(
      name: 'rss_fetch',
      description:
          'Fetch an RSS or Atom feed URL and return its recent items.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'description': 'Feed URL.'},
          'limit': {
            'type': 'integer',
            'description': 'Max items (default 10).',
          },
        },
        'required': ['url'],
      },
    ),
  ];

  @override
  List<ChannelResource> listResources() => const [];

  @override
  Future<ChannelResource> readResource(String uri) async =>
      throw ArgumentError('RSS channel has no resources: $uri');

  @override
  Future<ChannelCallResult> callTool(
    String tool,
    Map<String, dynamic> args,
  ) async {
    if (tool != 'rss_fetch') {
      return ChannelCallResult.error('Unknown rss tool "$tool"');
    }
    final url = (args['url'] as String? ?? '').trim();
    if (!url.startsWith('http')) {
      return const ChannelCallResult.error('A feed URL is required.');
    }
    final limit = (args['limit'] as int?) ?? 10;
    try {
      final items = await _feed.fetchItems(url, type: FeedSourceType.rss);
      if (items.isEmpty) return const ChannelCallResult.text('Feed is empty.');
      return ChannelCallResult.content(
        items.take(limit).map(feedItemToContentItem).toList(),
      );
    } on Object catch (e) {
      return ChannelCallResult.error('RSS fetch failed: $e');
    }
  }
}

/// Usenet channel — `usenet_search` via Newznab indexers.
class UsenetChannelServer implements ChannelServer {
  /// Creates a [UsenetChannelServer] backed by the given [feedService].
  UsenetChannelServer({required FeedService feedService})
      : _feed = feedService;

  final FeedService _feed;

  @override
  String get id => 'usenet';

  @override
  String get name => 'Usenet';

  @override
  String get description =>
      'Search Usenet indexers for releases (movies, TV, music, software).';

  @override
  List<ChannelTool> listTools() => const [
    ChannelTool(
      name: 'usenet_search',
      description:
          'Search configured Usenet indexers for a query, optionally '
          'filtered by category (movies, tv, music, games, software, books, '
          'audio, other).',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Search query.'},
          'category': {
            'type': 'string',
            'description': 'Optional category filter.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Max results (default 10).',
          },
        },
        'required': ['query'],
      },
    ),
  ];

  @override
  List<ChannelResource> listResources() => const [];

  @override
  Future<ChannelResource> readResource(String uri) async =>
      throw ArgumentError('Usenet channel has no resources: $uri');

  @override
  Future<ChannelCallResult> callTool(
    String tool,
    Map<String, dynamic> args,
  ) async {
    if (tool != 'usenet_search') {
      return ChannelCallResult.error('Unknown usenet tool "$tool"');
    }
    final query = (args['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return const ChannelCallResult.error('A search query is required.');
    }
    final category = (args['category'] as String? ?? '').trim();
    final limit = (args['limit'] as int?) ?? 10;

    final encoded = Uri.encodeQueryComponent(query);
    final catParam = category.isNotEmpty ? '&cat=${Uri.encodeComponent(category)}' : '';
    final url = 'usenet://search?q=$encoded$catParam';
    try {
      final items = await _feed.fetchItems(url, type: FeedSourceType.usenet);
      if (items.isEmpty) {
        return ChannelCallResult.text('No Usenet releases found for "$query".');
      }
      return ChannelCallResult.content(
        items.take(limit).map(feedItemToContentItem).toList(),
      );
    } on Object catch (e) {
      return ChannelCallResult.error('Usenet search failed: $e');
    }
  }
}