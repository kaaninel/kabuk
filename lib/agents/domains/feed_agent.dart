/// Feed agent — manages RSS, Reddit, and other content feed subscriptions.
///
/// Provides tools for subscribing to feeds, refreshing content,
/// listing articles, and managing feed subscriptions. All articles
/// are stored as `schema:Article` entities in the knowledge store.
library;

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/memory.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/services/feed.dart';

/// Agent specialized in content feed management.
///
/// Handles subscribing to RSS feeds and subreddits, fetching new content,
/// listing and searching articles, and managing subscriptions.
class FeedAgent extends BaseAgent with AgentMemoryMixin {
  @override
  String get name => 'feeds';

  @override
  String get description =>
      'Manages RSS feeds, subreddits, and other content sources — '
      'subscribe, refresh, read articles.';

  @override
  String get systemPrompt => '''
You are the Feed agent for Kabuk. You manage the user's content feed
subscriptions and articles, stored as schema:DataFeed and schema:Article
entities in the knowledge store.

Capabilities:
• Subscribe to RSS/Atom feeds by URL
• Subscribe to Reddit subreddits (just the name like "flutter" or "r/flutter")
• Subscribe to Nostr hashtag/topic feeds (e.g. "nostr:t/flutter")
• Refresh feeds to fetch new articles (one feed or all at once)
• List recent articles across all feeds or from a specific subscription
• List all active feed subscriptions
• Remove/unsubscribe from feeds
• Mark articles as read
• Search articles by keyword

Feed Type Detection:
• If the user mentions "r/something" or a subreddit name → feed_type: "reddit"
• If the user provides a standard URL → feed_type: "rss" (handles both RSS2 and Atom)
• If the user mentions a Nostr topic or hashtag (e.g. "#flutter", "nostr:t/dart")
→ feed_type: "nostr"
• If the user wants to discover or search Nostr content, delegate to the "discover"
agent instead
• If unclear, ask whether it's an RSS feed, a subreddit, or a Nostr topic

Nostr Feed URL Formats:
• nostr:t/flutter — subscribe to the #flutter hashtag
• nostr:t/flutter,dart — subscribe to multiple hashtags
• nostr:feed/global — subscribe to the global feed
• nostr:feed/following — subscribe to the user's following feed

Usage Guidelines:
• When subscribing, confirm the feed name and type
• When listing articles, show title, source, and date — keep it scannable
• "Add", "follow", "subscribe to" all mean subscribe_feed
• "What's new?", "any updates?" mean list recent (unread) articles
• After subscribing to a new feed, offer to refresh it immediately
• When showing articles, indicate which are unread
• If a feed URL fails, suggest checking the URL or trying an alternative
• For Nostr topic subscriptions with discover/search intent, suggest using the
discover agent instead
''';

  @override
  List<AgentTool> get tools => [
    AgentTool(
      name: 'subscribe_feed',
      description:
          'Subscribe to a new content feed (RSS, Atom, or Reddit subreddit).',
      parameters: {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description':
                'The feed URL, subreddit name (e.g. "flutter"), '
                'or subreddit path (e.g. "r/flutter").',
          },
          'name': {
            'type': 'string',
            'description':
                'A display name for the feed. If omitted, will be '
                'inferred from the URL.',
          },
          'feed_type': {
            'type': 'string',
            'enum': ['rss', 'reddit', 'nostr'],
            'description':
                'The type of feed source. Use "rss" for RSS/Atom feeds, '
                '"reddit" for subreddits, "nostr" for Nostr hashtag feeds.',
          },
          'category': {
            'type': 'string',
            'description': 'Optional category for organizing feeds.',
          },
        },
        'required': ['url'],
      },
      execute: _subscribeFeed,
    ),
    AgentTool(
      name: 'list_feeds',
      description: 'List all feed subscriptions.',
      parameters: {'type': 'object', 'properties': <String, dynamic>{}},
      execute: _listFeeds,
    ),
    AgentTool(
      name: 'unsubscribe_feed',
      description: 'Remove a feed subscription and all its articles.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {
            'type': 'string',
            'description': 'The entity URI of the feed subscription to remove.',
          },
        },
        'required': ['uri'],
      },
      execute: _unsubscribeFeed,
    ),
    AgentTool(
      name: 'refresh_feed',
      description: 'Fetch new articles from a specific feed or all feeds.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {
            'type': 'string',
            'description':
                'The entity URI of a specific feed to refresh. '
                'Omit to refresh all feeds.',
          },
        },
      },
      execute: _refreshFeed,
    ),
    AgentTool(
      name: 'list_articles',
      description:
          'List recent articles, optionally filtered by feed or unread status.',
      parameters: {
        'type': 'object',
        'properties': {
          'feed_uri': {
            'type': 'string',
            'description':
                'Filter to a specific feed subscription URI. Omit for all.',
          },
          'unread_only': {
            'type': 'boolean',
            'description':
                'If true, only show unread articles (default: false).',
          },
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of articles to return (default 20).',
          },
        },
      },
      execute: _listArticles,
    ),
    AgentTool(
      name: 'search_articles',
      description: 'Search articles by keyword.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'The search keyword.'},
        },
        'required': ['query'],
      },
      execute: _searchArticles,
    ),
    AgentTool(
      name: 'mark_read',
      description: 'Mark an article as read.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {
            'type': 'string',
            'description': 'The entity URI of the article to mark as read.',
          },
        },
        'required': ['uri'],
      },
      execute: _markRead,
    ),
  ];

  @override
  Set<AgentCapability> get requiredCapabilities => {
    AgentCapability.llmCall,
    AgentCapability.knowledgeRead,
    AgentCapability.knowledgeWrite,
    AgentCapability.meshConnect,
  };

  @override
  Future<AgentResponse> process(
    AgentMessage message,
    AgentContext context,
  ) async {
    final content = switch (message) {
      UserMessage(:final content) => content,
      SystemMessage(:final content) => content,
      _ => '',
    };

    if (content.isEmpty) {
      return const AgentResponse.text(
        'What would you like to do with your feeds?',
      );
    }

    // ---- Fast path: keyword-based tool dispatch ----
    // Handle common feed commands without requiring an LLM.
    final directResult = await _tryDirectDispatch(content, context);
    if (directResult != null) {
      return directResult;
    }

    // ---- LLM path ----
    final llmMessages = <LlmMessage>[
      if (message case UserMessage(:final history?)) ...history,
      LlmMessage.user(content),
    ];

    final prompt = await buildSystemPromptWithMemory(context);
    return processLlmRequest(
      context: context,
      messages: llmMessages,
      systemPrompt: prompt,
      temperature: 0.3,
    );
  }

  // ---------------------------------------------------------------------------
  // Direct dispatch (no LLM needed)
  // ---------------------------------------------------------------------------

  /// Regex patterns for common feed intents.
  static final _subscribeRedditPattern = RegExp(
    r'(subscribe|follow|add)\b.*?\b(?:r/(\w+)|reddit\b.*?(\w+))',
    caseSensitive: false,
  );
  static final _subscribeRssPattern = RegExp(
    r'(subscribe|follow|add)\b.*?(https?://\S+)',
    caseSensitive: false,
  );
  static final _bareSubredditPattern = RegExp(
    r'^\s*r/(\w+)\s*$',
    caseSensitive: false,
  );
  static final _refreshPattern = RegExp(
    r'(refresh|fetch|update)\b.*\bfeed',
    caseSensitive: false,
  );
  static final _listFeedsPattern = RegExp(
    r'(list|show|my)\b.*\b(feed|subscription)',
    caseSensitive: false,
  );
  static final _listArticlesPattern = RegExp(
    r'(list|show|my|latest|recent|new)\b.*\barticle',
    caseSensitive: false,
  );

  /// Tries to handle the user's intent directly without an LLM call.
  ///
  /// Returns an [AgentResponse] if the intent was matched and handled,
  /// or `null` if the request should fall through to the LLM.
  Future<AgentResponse?> _tryDirectDispatch(
    String content,
    AgentContext context,
  ) async {
    // 1. "subscribe to r/all" or "add r/technology"
    final redditMatch = _subscribeRedditPattern.firstMatch(content);
    if (redditMatch != null) {
      final subreddit = redditMatch.group(2) ?? redditMatch.group(3) ?? '';
      if (subreddit.isNotEmpty) {
        final result = await _subscribeFeed({
          'url': 'r/$subreddit',
          'feed_type': 'reddit',
        }, context);
        return _toolResultToResponse(result);
      }
    }

    // 2. Bare "r/all" style input
    final bareMatch = _bareSubredditPattern.firstMatch(content);
    if (bareMatch != null) {
      final subreddit = bareMatch.group(1) ?? '';
      if (subreddit.isNotEmpty) {
        final result = await _subscribeFeed({
          'url': 'r/$subreddit',
          'feed_type': 'reddit',
        }, context);
        return _toolResultToResponse(result);
      }
    }

    // 3. "subscribe to https://..."
    final rssMatch = _subscribeRssPattern.firstMatch(content);
    if (rssMatch != null) {
      final url = rssMatch.group(2) ?? '';
      if (url.isNotEmpty) {
        final result = await _subscribeFeed({'url': url}, context);
        return _toolResultToResponse(result);
      }
    }

    // 4. "refresh feeds"
    if (_refreshPattern.hasMatch(content)) {
      final result = await _refreshFeed({}, context);
      return _toolResultToResponse(result);
    }

    // 5. "list my feeds" / "show subscriptions"
    if (_listFeedsPattern.hasMatch(content)) {
      final result = await _listFeeds({}, context);
      return _toolResultToResponse(result);
    }

    // 6. "show my articles" / "latest articles"
    if (_listArticlesPattern.hasMatch(content)) {
      final result = await _listArticles({}, context);
      return _toolResultToResponse(result);
    }

    return null; // Fall through to LLM.
  }

  /// Converts a [ToolResult] to an [AgentResponse].
  AgentResponse _toolResultToResponse(ToolResult result) {
    return switch (result) {
      TextToolResult(:final content) => AgentResponse.text(content),
      ErrorToolResult(:final message) => AgentResponse.error(message),
      _ => const AgentResponse.text('Done.'),
    };
  }

  // ---------------------------------------------------------------------------
  // Tool implementations
  // ---------------------------------------------------------------------------

  Future<ToolResult> _subscribeFeed(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final feed = context.feed;
    if (feed == null) {
      return const ToolResult.error('Feed service not available.');
    }

    final url = args['url'] as String? ?? '';
    if (url.isEmpty) {
      return const ToolResult.error('URL is required.');
    }

    final explicitType = args['feed_type'] as String?;
    final category = args['category'] as String?;

    // Determine feed type.
    FeedSourceType sourceType;
    if (explicitType == 'reddit') {
      sourceType = FeedSourceType.reddit;
    } else if (explicitType == 'rss') {
      sourceType = FeedSourceType.rss;
    } else if (explicitType == 'nostr') {
      sourceType = FeedSourceType.nostr;
    } else {
      final detected = await feed.detectType(url);
      if (detected == null) {
        return ToolResult.error(
          'Could not detect the type of "$url". '
          'Please specify feed_type as "rss", "reddit", or "nostr".',
        );
      }
      sourceType = detected;
    }

    // Infer name if not provided.
    var name = args['name'] as String?;
    if (name == null || name.isEmpty) {
      name = _inferName(url, sourceType);
    }

    // Validate the feed works before subscribing.
    final source = feed.getSource(sourceType);
    final valid = await source.validate(url);
    if (!valid) {
      return ToolResult.error(
        'Could not validate the feed at "$url". '
        'Please check the URL and try again.',
      );
    }

    // Store the subscription.
    final feedUri = await context.knowledge.createFeedSubscription(
      name: name,
      feedUrl: url,
      feedType: sourceType.name,
      category: category,
    );

    // Immediately fetch articles.
    final newCount = await _fetchAndStoreArticles(
      context: context,
      feedService: feed,
      feedUri: feedUri,
      feedUrl: url,
      sourceType: sourceType,
    );

    return ToolResult.text(
      'Subscribed to **$name** (${sourceType.name})\n'
      'URI: $feedUri\n'
      'Fetched $newCount articles.',
    );
  }

  Future<ToolResult> _listFeeds(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final feeds = await context.knowledge.listFeedSubscriptions();

    if (feeds.isEmpty) {
      return const ToolResult.text(
        'No feed subscriptions yet. Use subscribe_feed to add one.',
      );
    }

    final lines = feeds.map((f) {
      final lastFetched = f.lastFetched != null
          ? f.lastFetched!.toIso8601String()
          : 'never';
      return '- **${f.name ?? 'Unnamed'}** (${f.feedType ?? 'unknown'})\n'
          '  URL: ${f.feedUrl}\n'
          '  Last fetched: $lastFetched\n'
          '  URI: `${f.uri}`';
    });

    return ToolResult.text(
      'Found ${feeds.length} feed(s):\n${lines.join('\n')}',
    );
  }

  Future<ToolResult> _unsubscribeFeed(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final uri = args['uri'] as String? ?? '';
    if (uri.isEmpty) {
      return const ToolResult.error('Feed URI is required.');
    }

    final existing = await context.knowledge.getFeedSubscription(uri);
    if (existing == null) {
      return ToolResult.error('Feed subscription not found: $uri');
    }

    await context.knowledge.deleteFeedSubscription(uri);
    return ToolResult.text(
      'Unsubscribed from **${existing.name ?? uri}** and removed its articles.',
    );
  }

  Future<ToolResult> _refreshFeed(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final feed = context.feed;
    if (feed == null) {
      return const ToolResult.error('Feed service not available.');
    }

    final uri = args['uri'] as String?;
    final feeds = <FeedSubscriptionData>[];

    if (uri != null && uri.isNotEmpty) {
      final sub = await context.knowledge.getFeedSubscription(uri);
      if (sub == null) {
        return ToolResult.error('Feed subscription not found: $uri');
      }
      feeds.add(sub);
    } else {
      feeds.addAll(await context.knowledge.listFeedSubscriptions());
    }

    if (feeds.isEmpty) {
      return const ToolResult.text('No feeds to refresh.');
    }

    var totalNew = 0;
    final results = <String>[];

    for (final sub in feeds) {
      if (sub.feedUrl == null) continue;
      try {
        final sourceType = FeedSourceType.values.firstWhere(
          (t) => t.name == sub.feedType,
          orElse: () => FeedSourceType.rss,
        );
        final count = await _fetchAndStoreArticles(
          context: context,
          feedService: feed,
          feedUri: sub.uri,
          feedUrl: sub.feedUrl!,
          sourceType: sourceType,
        );
        totalNew += count;
        results.add('- **${sub.name}**: $count new articles');
      } on Object catch (e) {
        results.add('- **${sub.name}**: error — $e');
      }
    }

    return ToolResult.text(
      'Refreshed ${feeds.length} feed(s), $totalNew new article(s):\n'
      '${results.join('\n')}',
    );
  }

  Future<ToolResult> _listArticles(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final feedUri = args['feed_uri'] as String?;
    final unreadOnly = args['unread_only'] as bool? ?? false;
    final limit = (args['limit'] as int?) ?? 20;

    final articles = await context.knowledge.listArticles(
      limit: limit,
      feedSource: feedUri,
      unreadOnly: unreadOnly ? true : null,
    );

    if (articles.isEmpty) {
      return const ToolResult.text('No articles found.');
    }

    final lines = articles.map((a) {
      final readMark = a.read ? '✓' : '•';
      final date = a.datePublished != null
          ? _formatDate(a.datePublished!)
          : 'undated';
      final author = a.author != null ? ' by ${a.author}' : '';
      return '$readMark **${a.name ?? 'Untitled'}**$author ($date)\n'
          '  ${a.url ?? ''}\n'
          '  URI: `${a.uri}`';
    });

    return ToolResult.text(
      'Found ${articles.length} article(s):\n${lines.join('\n')}',
    );
  }

  Future<ToolResult> _searchArticles(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final query = args['query'] as String? ?? '';
    if (query.isEmpty) {
      return const ToolResult.error('Search query cannot be empty.');
    }

    final results = await context.knowledge.search(query);
    final articleSubjects = <String>{};
    for (final triple in results) {
      articleSubjects.add(triple.subject);
    }

    if (articleSubjects.isEmpty) {
      return ToolResult.text('No articles matching "$query".');
    }

    final uris = articleSubjects.take(20).toList();
    final entities = await context.knowledge.getEntities(uris);

    final lines = <String>[];
    for (final uri in uris) {
      final triples = entities[uri] ?? [];
      final isArticle = triples.any(
        (t) => t.predicate == NS.rdfType && t.objectValue == NS.schemaArticle,
      );
      if (!isArticle) continue;

      final article = ArticleData.fromTriples(uri, triples);
      lines.add(
        '- **${article.name ?? 'Untitled'}** (${article.url ?? ''})\n'
        '  URI: `$uri`',
      );
    }

    if (lines.isEmpty) {
      return ToolResult.text('No articles matching "$query".');
    }

    return ToolResult.text(
      'Found ${lines.length} article(s) matching "$query":\n${lines.join('\n')}',
    );
  }

  Future<ToolResult> _markRead(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final uri = args['uri'] as String? ?? '';
    if (uri.isEmpty) {
      return const ToolResult.error('Article URI is required.');
    }

    final article = await context.knowledge.getArticleData(uri);
    if (article == null) {
      return ToolResult.error('Article not found: $uri');
    }

    await context.knowledge.markArticleRead(uri);
    return ToolResult.text('Marked **${article.name ?? uri}** as read.');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Fetches items from a feed source and stores new articles.
  ///
  /// Returns the number of newly created articles (skips duplicates).
  Future<int> _fetchAndStoreArticles({
    required AgentContext context,
    required FeedService feedService,
    required String feedUri,
    required String feedUrl,
    required FeedSourceType sourceType,
  }) async {
    final items = await feedService.fetchItems(feedUrl, type: sourceType);

    // Load existing article identifiers for this feed to skip duplicates.
    final existing = await context.knowledge.listArticles(
      feedSource: feedUri,
      limit: 500,
    );
    final existingUrls = existing.map((a) => a.url).toSet();
    final existingIds = existing
        .where((a) => a.uri.isNotEmpty)
        .map((a) => a.url)
        .toSet();

    var newCount = 0;
    for (final item in items) {
      // Skip if we already have this article.
      if (existingUrls.contains(item.url) ||
          existingIds.contains(item.identifier)) {
        continue;
      }

      await context.knowledge.createArticle(
        title: item.title,
        description: item.description,
        url: item.url,
        videoUrl: item.videoUrl,
        author: item.author,
        image: item.imageUrl,
        feedSource: feedUri,
        datePublished: item.datePublished,
        tags: item.categories,
      );
      newCount++;
    }

    // Update last-fetched timestamp.
    await context.knowledge.updateFeedLastFetched(feedUri);

    return newCount;
  }

  /// Infers a display name from a feed URL.
  static String _inferName(String url, FeedSourceType type) {
    if (type == FeedSourceType.reddit) {
      // Extract subreddit name.
      final match = RegExp(r'r/(\w+)').firstMatch(url);
      if (match != null) return 'r/${match.group(1)}';
      // Bare subreddit name.
      final cleaned = url.replaceAll(RegExp(r'[/\s]'), '');
      return 'r/$cleaned';
    }
    if (type == FeedSourceType.nostr) {
      // Parse Nostr feed URL formats.
      if (url.startsWith('nostr:t/')) {
        final hashtags = url.substring('nostr:t/'.length);
        return '#${hashtags.replaceAll(',', ', #')}';
      }
      if (url.startsWith('nostr:feed/')) {
        return 'Nostr ${url.substring('nostr:feed/'.length)}';
      }
      if (url.startsWith('nostr:search/')) {
        return 'Nostr search: ${url.substring('nostr:search/'.length)}';
      }
      if (url.startsWith('#')) return url;
      return 'Nostr feed';
    }
    // Use domain name for RSS.
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } on Object {
      return url.length > 40 ? '${url.substring(0, 40)}...' : url;
    }
  }

  static String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
