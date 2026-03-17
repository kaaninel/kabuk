/// Discovery agent — searches, discovers, and subscribes to content across
/// Nostr, RSS, Reddit, and the local knowledge store.
///
/// Provides a unified interface for exploring content: hashtag search on
/// Nostr, NIP-50 full-text search, trending topics, feed suggestions,
/// and saved search subscriptions (persistent queries that auto-refresh).
library;

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/memory.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/knowledge/types/bookmark.dart';
import 'package:kabuk/knowledge/types/saved_search.dart';
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/services/nostr_utils.dart';

/// Agent specialized in content discovery across all connected sources.
///
/// Handles topic-based Nostr search, keyword search (NIP-50), trending
/// topics, content suggestions, and saved search management. Works with
/// the FeedAgent for subscribing to discovered content.
class DiscoveryAgent extends BaseAgent with AgentMemoryMixin {
  @override
  String get name => 'discover';

  @override
  String get description =>
      'Discovers and searches for content across Nostr, RSS, and the web — '
      'find topics, trends, and new sources to subscribe to.';

  @override
  String get systemPrompt => '''
You are the Discovery agent for Kabuk. You help users find, explore, and
subscribe to content across multiple networks and protocols.

Capabilities:
• Search Nostr by hashtag/topic — find posts about any subject
• Full-text search on Nostr (NIP-50) — keyword search across relay content
• Discover trending topics — see what's popular on the Nostr network
• Search local knowledge store — find content the user already has
• Save searches as subscriptions — persistent queries that auto-refresh
• Suggest content sources — recommend feeds based on interests
• Bookmark content — save interesting articles/notes for later

Content Sources:
• **Nostr** — decentralized social posts (kind 1 text notes) searchable by
hashtag (#t tags), keyword (NIP-50), or author
• **RSS/Atom** — traditional web feeds from blogs, news sites, podcasts
• **Reddit** — subreddit content via JSON API
• All sources are unified in the Explore view

Search Types:
• **Hashtag search**: "search #flutter" or "find posts about dart"
→ use search_nostr_hashtag
• **Keyword search**: "search for machine learning on nostr"
→ use search_nostr_content
• **Local search**: "find my articles about cooking"
→ use search_local
• **Trending**: "what's trending?" or "popular topics"
→ use trending_topics

Subscription Types:
• **Feed subscription**: subscribe to an RSS feed or subreddit
→ delegate to the feeds agent
• **Nostr topic subscription**: subscribe to a hashtag (e.g., #flutter)
→ use subscribe_topic which creates a Nostr feed subscription
• **Saved search**: save a search query that refreshes periodically
→ use save_search

Usage Guidelines:
• When the user asks to "find" or "search" content, determine whether they
want Nostr content, local content, or both
• For topic exploration, start with trending_topics and suggest relevant hashtags
• When showing results, include the content preview, author, and timestamp
• Offer to subscribe to interesting topics or save searches for later
• If the user mentions a specific hashtag (prefixed with #), use search_nostr_hashtag
• For general content discovery, combine trending + hashtag search
''';

  @override
  List<AgentTool> get tools => [
    AgentTool(
      name: 'search_nostr_hashtag',
      description:
          'Search Nostr for posts tagged with specific hashtags/topics.',
      parameters: {
        'type': 'object',
        'properties': {
          'hashtags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Hashtags to search for (without #). '
                'e.g. ["flutter", "dart"]',
          },
          'limit': {
            'type': 'integer',
            'description': 'Max results to return (default 20).',
          },
        },
        'required': ['hashtags'],
      },
      execute: _searchNostrHashtag,
    ),
    AgentTool(
      name: 'search_nostr_content',
      description:
          'Full-text keyword search on Nostr (NIP-50). '
          'Searches event content across supporting relays.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The search query string.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Max results to return (default 20).',
          },
        },
        'required': ['query'],
      },
      execute: _searchNostrContent,
    ),
    AgentTool(
      name: 'trending_topics',
      description: 'Discover trending hashtags/topics on the Nostr network.',
      parameters: {
        'type': 'object',
        'properties': {
          'hours': {
            'type': 'integer',
            'description':
                'Time window in hours to scan for trends (default 24).',
          },
        },
      },
      execute: _trendingTopics,
    ),
    AgentTool(
      name: 'search_local',
      description:
          'Search the local knowledge store for articles, notes, '
          'and other content matching a query.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The search query string.',
          },
          'type': {
            'type': 'string',
            'enum': [
              'all',
              'article',
              'note',
              'nostr_note',
              'contact',
              'event',
            ],
            'description': 'Filter to a specific entity type (default: all).',
          },
          'limit': {
            'type': 'integer',
            'description': 'Max results to return (default 15).',
          },
        },
        'required': ['query'],
      },
      execute: _searchLocal,
    ),
    AgentTool(
      name: 'subscribe_topic',
      description:
          'Subscribe to a Nostr hashtag/topic as a feed. '
          'Creates a persistent subscription that auto-refreshes.',
      parameters: {
        'type': 'object',
        'properties': {
          'hashtags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Hashtags to subscribe to (without #). '
                'e.g. ["flutter", "dart"]',
          },
          'name': {
            'type': 'string',
            'description':
                'A display name for the subscription. '
                'Defaults to "#<hashtag>".',
          },
        },
        'required': ['hashtags'],
      },
      execute: _subscribeTopic,
    ),
    AgentTool(
      name: 'save_search',
      description:
          'Save a search query as a named subscription for recurring use. '
          'Saved searches appear in the Explore view filters.',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description':
                'Display name for the saved search '
                '(e.g. "AI News", "Flutter Tips").',
          },
          'query': {
            'type': 'string',
            'description': 'The search query or hashtag(s) to save.',
          },
          'source': {
            'type': 'string',
            'enum': ['nostr_hashtag', 'nostr_search', 'local'],
            'description':
                'Where to search: nostr_hashtag (t-tag), '
                'nostr_search (NIP-50), or local (knowledge store).',
          },
        },
        'required': ['name', 'query', 'source'],
      },
      execute: _saveSearch,
    ),
    AgentTool(
      name: 'list_saved_searches',
      description: 'List all saved search subscriptions.',
      parameters: {'type': 'object', 'properties': <String, dynamic>{}},
      execute: _listSavedSearches,
    ),
    AgentTool(
      name: 'delete_saved_search',
      description: 'Remove a saved search subscription.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {
            'type': 'string',
            'description': 'The URI of the saved search to remove.',
          },
        },
        'required': ['uri'],
      },
      execute: _deleteSavedSearch,
    ),
    AgentTool(
      name: 'bookmark_content',
      description: 'Bookmark an article or Nostr note for later reading.',
      parameters: {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': 'The URL or Nostr event URI to bookmark.',
          },
          'name': {
            'type': 'string',
            'description':
                'A display name for the bookmark (auto-detected if omitted).',
          },
          'description': {
            'type': 'string',
            'description': 'Optional description or note about the bookmark.',
          },
        },
        'required': ['url'],
      },
      execute: _bookmarkContent,
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
        'What would you like to discover? I can search Nostr by topic, '
        'find trending hashtags, or search your local content.',
      );
    }

    // ---- Fast path: common discovery patterns ----
    final directResult = await _tryDirectDispatch(content, context);
    if (directResult != null) return directResult;

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
      temperature: 0.4,
    );
  }

  // ---------------------------------------------------------------------------
  // Direct dispatch patterns
  // ---------------------------------------------------------------------------

  static final _hashtagPattern = RegExp(
    r'(?:search|find|explore|discover|show)\b.*?#(\w+)',
    caseSensitive: false,
  );
  static final _bareHashtagPattern = RegExp(
    r'^#(\w+(?:\s*,?\s*#?\w+)*)\s*$',
    caseSensitive: false,
  );
  static final _trendingPattern = RegExp(
    r'(trending|popular|hot|what.s\s*new|topics)',
    caseSensitive: false,
  );
  static final _subscribeTopicPattern = RegExp(
    r'(subscribe|follow)\b.*?#(\w+)',
    caseSensitive: false,
  );

  Future<AgentResponse?> _tryDirectDispatch(
    String content,
    AgentContext context,
  ) async {
    // "subscribe to #flutter"
    final subscribeMatch = _subscribeTopicPattern.firstMatch(content);
    if (subscribeMatch != null) {
      final hashtag = subscribeMatch.group(2)!;
      final result = await _subscribeTopic({
        'hashtags': [hashtag],
      }, context);
      return _toolResultToResponse(result);
    }

    // "search #flutter" or "find posts about #dart"
    final hashtagMatch = _hashtagPattern.firstMatch(content);
    if (hashtagMatch != null) {
      final hashtag = hashtagMatch.group(1)!;
      final result = await _searchNostrHashtag({
        'hashtags': [hashtag],
      }, context);
      return _toolResultToResponse(result);
    }

    // Bare "#flutter #dart"
    final bareMatch = _bareHashtagPattern.firstMatch(content);
    if (bareMatch != null) {
      final raw = bareMatch.group(1)!;
      final hashtags = raw
          .split(RegExp(r'[,\s]+'))
          .map((h) => h.replaceFirst('#', '').trim())
          .where((h) => h.isNotEmpty)
          .toList();
      if (hashtags.isNotEmpty) {
        final result = await _searchNostrHashtag({
          'hashtags': hashtags,
        }, context);
        return _toolResultToResponse(result);
      }
    }

    // "trending" / "popular topics"
    if (_trendingPattern.hasMatch(content)) {
      final result = await _trendingTopics({}, context);
      return _toolResultToResponse(result);
    }

    return null;
  }

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

  Future<ToolResult> _searchNostrHashtag(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error(
        'Nostr service not available. Please configure relays in settings.',
      );
    }

    final hashtags =
        (args['hashtags'] as List?)
            ?.map((h) => h.toString().toLowerCase().replaceFirst('#', ''))
            .where((h) => h.isNotEmpty)
            .toList() ??
        [];
    if (hashtags.isEmpty) {
      return const ToolResult.error('At least one hashtag is required.');
    }
    final limit = (args['limit'] as int?) ?? 20;

    final events = await collectNostrEvents(
      nostr.searchByHashtag(hashtags, limit: limit),
      where: (e) => e.kind == NostrKind.textNote,
    );

    if (events.isEmpty) {
      return ToolResult.text(
        'No posts found for #${hashtags.join(", #")}. '
        'Try different hashtags or check relay connections.',
      );
    }

    // Sort newest first and deduplicate.
    final seen = <String>{};
    events.removeWhere((e) => !seen.add(e.id));
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final lines = events.take(limit).map((event) {
      final date = DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000);
      final preview = event.content.length > 150
          ? '${event.content.substring(0, 150)}…'
          : event.content;
      final author = event.pubkey.substring(0, 8);
      return '- **$author…** (${_formatDate(date)})\n  $preview';
    });

    return ToolResult.text(
      'Found ${events.length} post(s) for **#${hashtags.join(', #')}**:\n\n'
      '${lines.join('\n\n')}\n\n'
      '💡 You can subscribe to ${hashtags.length > 1 ? "these topics" : "this topic"} '
      'with: "subscribe to #${hashtags.first}"',
    );
  }

  Future<ToolResult> _searchNostrContent(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error(
        'Nostr service not available. Please configure relays in settings.',
      );
    }

    final query = args['query'] as String? ?? '';
    if (query.isEmpty) {
      return const ToolResult.error('Search query cannot be empty.');
    }
    final limit = (args['limit'] as int?) ?? 20;

    final events = await collectNostrEvents(
      nostr.searchContent(query, limit: limit),
      where: (e) => e.kind == NostrKind.textNote,
    );

    if (events.isEmpty) {
      return ToolResult.text(
        'No results for "$query" via NIP-50 search. '
        'Not all relays support full-text search. '
        'Try searching by hashtag instead.',
      );
    }

    final seen = <String>{};
    events.removeWhere((e) => !seen.add(e.id));
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final lines = events.take(limit).map((event) {
      final date = DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000);
      final preview = event.content.length > 150
          ? '${event.content.substring(0, 150)}…'
          : event.content;
      final author = event.pubkey.substring(0, 8);
      return '- **$author…** (${_formatDate(date)})\n  $preview';
    });

    return ToolResult.text(
      'Found ${events.length} Nostr post(s) matching "$query":\n\n'
      '${lines.join('\n\n')}',
    );
  }

  Future<ToolResult> _trendingTopics(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error(
        'Nostr service not available. Please configure relays in settings.',
      );
    }

    final hours = (args['hours'] as int?) ?? 24;
    final window = Duration(hours: hours);

    final trending = await nostr.trendingHashtags(window: window);

    if (trending.isEmpty) {
      return const ToolResult.text(
        'No trending topics found. Try connecting to more relays or '
        'expanding the time window.',
      );
    }

    final lines = trending.take(20).map((t) {
      final bar = '█' * (t.count.clamp(1, 20));
      return '- **#${t.hashtag}** — ${t.count} posts $bar';
    });

    return ToolResult.text(
      'Trending topics on Nostr (last ${hours}h):\n\n'
      '${lines.join('\n')}\n\n'
      '💡 Search any topic with: "search #topic"\n'
      '📌 Subscribe with: "subscribe to #topic"',
    );
  }

  Future<ToolResult> _searchLocal(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final query = args['query'] as String? ?? '';
    if (query.isEmpty) {
      return const ToolResult.error('Search query cannot be empty.');
    }
    final typeFilter = args['type'] as String? ?? 'all';
    final limit = (args['limit'] as int?) ?? 15;

    // Map type filter to RDF type URI.
    final rdfType = switch (typeFilter) {
      'article' => NS.schemaArticle,
      'note' => NS.schemaNote,
      'nostr_note' => NS.kabukNostrNote,
      'contact' => NS.schemaPerson,
      'event' => NS.schemaEvent,
      _ => null,
    };

    final results = await context.knowledge.search(query, limit: limit * 3);

    if (results.isEmpty) {
      return ToolResult.text('No local results found for "$query".');
    }

    // Deduplicate by subject.
    final seen = <String>{};
    final subjects = <String>[];
    for (final triple in results) {
      if (seen.add(triple.subject)) subjects.add(triple.subject);
    }

    final entities = await context.knowledge.getEntities(subjects);
    final lines = <String>[];

    for (final subject in subjects) {
      if (lines.length >= limit) break;

      final entity = entities[subject] ?? [];
      if (entity.isEmpty) continue;

      // Filter by type if specified.
      if (rdfType != null) {
        final isMatch = entity.any(
          (t) => t.predicate == NS.rdfType && t.objectValue == rdfType,
        );
        if (!isMatch) continue;
      }

      final type = entity
          .where((t) => t.predicate == NS.rdfType)
          .firstOrNull
          ?.objectValue
          .split('/')
          .last;
      final name = entity
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue;
      final text = entity
          .where((t) => t.predicate == NS.schemaText)
          .firstOrNull
          ?.objectValue;
      final desc = entity
          .where((t) => t.predicate == NS.schemaDescription)
          .firstOrNull
          ?.objectValue;

      final displayName = name ?? 'Untitled';
      final typeName = type ?? 'Unknown';
      final preview = text ?? desc ?? '';
      final previewLine = preview.isNotEmpty
          ? '\n  ${preview.length > 100 ? '${preview.substring(0, 100)}…' : preview}'
          : '';

      lines.add('- **$displayName** [$typeName]$previewLine');
    }

    if (lines.isEmpty) {
      return ToolResult.text('No local results found for "$query".');
    }

    return ToolResult.text(
      'Found ${lines.length} local result(s) for "$query":\n\n'
      '${lines.join('\n')}',
    );
  }

  Future<ToolResult> _subscribeTopic(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final hashtags =
        (args['hashtags'] as List?)
            ?.map((h) => h.toString().toLowerCase().replaceFirst('#', ''))
            .where((h) => h.isNotEmpty)
            .toList() ??
        [];
    if (hashtags.isEmpty) {
      return const ToolResult.error('At least one hashtag is required.');
    }

    final displayName = args['name'] as String? ?? '#${hashtags.join(', #')}';
    final feedUrl = 'nostr:t/${hashtags.join(',')}';

    // Check for duplicate subscription.
    final existing = await context.knowledge.listFeedSubscriptions();
    final alreadySubscribed = existing.any((f) => f.feedUrl == feedUrl);
    if (alreadySubscribed) {
      return ToolResult.text(
        'Already subscribed to **$displayName**. '
        'Use "refresh feeds" to get latest content.',
      );
    }

    final uri = await context.knowledge.createFeedSubscription(
      name: displayName,
      feedUrl: feedUrl,
      feedType: 'nostr',
      category: 'nostr',
    );

    // Immediately fetch initial content if feed service is available.
    var fetchCount = 0;
    final feed = context.feed;
    if (feed != null) {
      try {
        final items = await feed.fetchItems(
          feedUrl,
          type: FeedSourceType.nostr,
        );
        final existingArticles = await context.knowledge.listArticles(
          feedSource: uri,
          limit: 500,
        );
        final existingUrls = existingArticles.map((a) => a.url).toSet();

        for (final item in items) {
          if (existingUrls.contains(item.url)) continue;
          await context.knowledge.createArticle(
            title: item.title,
            description: item.description,
            url: item.url,
            videoUrl: item.videoUrl,
            author: item.author,
            image: item.imageUrl,
            feedSource: uri,
            datePublished: item.datePublished,
            tags: item.categories,
          );
          fetchCount++;
        }
        await context.knowledge.updateFeedLastFetched(uri);
      } on Object {
        // Fetch failed — subscription is still created.
      }
    }

    return ToolResult.text(
      'Subscribed to Nostr topic **$displayName**\n'
      'Feed URL: $feedUrl\n'
      'URI: $uri\n'
      '${fetchCount > 0 ? 'Fetched $fetchCount initial posts.' : ''}\n\n'
      'New posts will appear in your Explore feed.',
    );
  }

  Future<ToolResult> _saveSearch(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final name = args['name'] as String? ?? '';
    final query = args['query'] as String? ?? '';
    final source = args['source'] as String? ?? 'nostr_hashtag';

    if (name.isEmpty || query.isEmpty) {
      return const ToolResult.error('Both name and query are required.');
    }

    // Store as a SavedSearch entity.
    final uri = await context.knowledge.mutate((ctx) async {
      final uri = ctx.create('SavedSearch');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.kabukSavedSearch,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      await ctx.set(uri, NS.kabukSearchQuery, query);
      await ctx.set(uri, NS.kabukSearchSource, source);
      await ctx.set(
        uri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );
      return uri;
    });

    return ToolResult.text(
      'Saved search **$name** ($source: "$query")\n'
      'URI: $uri\n\n'
      'This search will appear in your Explore view filters.',
    );
  }

  Future<ToolResult> _listSavedSearches(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final searches = await context.knowledge.listSavedSearches();

    if (searches.isEmpty) {
      return const ToolResult.text(
        'No saved searches yet. Use save_search to create one.',
      );
    }

    final lines = searches.map((s) {
      return '- **${s.name ?? 'Unnamed'}** (${s.source ?? 'unknown'})\n'
          '  Query: ${s.query ?? ''}\n'
          '  URI: `${s.uri}`';
    });

    return ToolResult.text(
      'Saved searches (${searches.length}):\n${lines.join('\n')}',
    );
  }

  Future<ToolResult> _deleteSavedSearch(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final uri = args['uri'] as String? ?? '';
    if (uri.isEmpty) {
      return const ToolResult.error('Saved search URI is required.');
    }

    await context.knowledge.mutate((ctx) async {
      await ctx.remove(subject: uri);
    });

    return ToolResult.text('Deleted saved search: $uri');
  }

  Future<ToolResult> _bookmarkContent(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final url = args['url'] as String? ?? '';
    if (url.isEmpty) {
      return const ToolResult.error('URL is required.');
    }

    final name = args['name'] as String? ?? url;
    final description = args['description'] as String?;

    // Import the bookmark using the knowledge store extension.
    final uri = await context.knowledge.createBookmark(
      name: name,
      url: url,
      description: description,
    );

    return ToolResult.text(
      'Bookmarked **$name**\n'
      'URL: $url\n'
      'URI: $uri',
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

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
