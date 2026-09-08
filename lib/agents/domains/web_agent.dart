/// Web & channels agent — searches the web and other channels via the
/// channel registry.
///
/// Implements the standard agentic "search-then-read" loop:
/// `web_search(query)` finds pages → the agent picks promising URLs →
/// `web_fetch(url)` reads them → it synthesizes an answer. It also searches
/// Reddit, Nostr, Usenet, and RSS through the same MCP-style channel
/// registry. Search results are returned as a [ToolResult.channel] so the OS
/// draws them as a channel surface, not raw text.
///
/// All channel capability comes from [ChannelServer]s in the registry — the
/// same MCP-style interface the omnibar and feed engine use.
library;

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/plugins/channel.dart';
import 'package:kabuk/services/channels.dart';

/// Agent specialized in web search, page reading, and channel search
/// (Reddit, Nostr, Usenet, RSS).
class WebAgent extends BaseAgent {
  @override
  String get name => 'web';

  @override
  String get description =>
      'Search the web, read pages, and search Reddit / Nostr / Usenet / RSS '
      'channels. Uses web_search + web_fetch and channel search tools.';

  @override
  Set<AgentCapability> get requiredCapabilities => const {};

  @override
  String get systemPrompt => '''
You are the Web & Channels agent for Kabuk. You search the web and other
channels (Reddit, Nostr, Usenet, RSS) and read pages to answer the user's
questions about online content.

Capabilities:
• web_search(query, max_results) — search the web; returns titles, URLs, snippets
• web_fetch(url, max_length) — read a page's readable text content
• reddit_search(query, subreddit?) / reddit_list(subreddit, sort) — Reddit
• nostr_search(query) / nostr_hashtag(hashtag) — Nostr notes
• usenet_search(query, category?) — Usenet indexers
• rss_fetch(url) — any RSS/Atom feed

Usage Guidelines:
• For any web question, search first, then fetch the most promising URLs
• "search reddit for X" → reddit_search; "what's on r/flutter" → reddit_list
• For hashtag/community questions, consider nostr_hashtag
• Prefer official/source pages over aggregators when obvious
• Summarize concisely and cite the URLs you read (the user can open them)
• If search returns nothing useful, try rephrasing the query once
• Always respect that web content may be outdated; note the date if relevant
''';

  @override
  List<AgentTool> get tools => [
    AgentTool(
      name: 'web_search',
      description:
          'Search the web for a query. Returns ranked results with titles, '
          'URLs, and snippets. Use before web_fetch to find relevant pages.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'The search query.'},
          'max_results': {
            'type': 'integer',
            'description': 'Maximum results (default 8).',
          },
        },
        'required': ['query'],
      },
      execute: _webSearch,
    ),
    AgentTool(
      name: 'web_fetch',
      description:
          'Fetch a URL and return its readable text content. Bounded for '
          'context; pass start_index to page through long articles.',
      parameters: {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'description': 'The URL to read.'},
          'max_length': {
            'type': 'integer',
            'description': 'Max characters (default 8000).',
          },
          'start_index': {
            'type': 'integer',
            'description': 'Start offset into the text.',
          },
        },
        'required': ['url'],
      },
      execute: _webFetch,
    ),
    AgentTool(
      name: 'reddit_search',
      description:
          'Search Reddit for a query, optionally scoped to one subreddit. '
          'Returns posts with titles, authors, and URLs.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Search query.'},
          'subreddit': {
            'type': 'string',
            'description': 'Scope to one subreddit.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Max results (default 10).',
          },
        },
        'required': ['query'],
      },
      execute: (args, ctx) => _invokeChannel(
        ctx,
        'reddit',
        'reddit_search',
        args,
        title: 'Reddit search: ${args['query'] ?? ''}',
      ),
    ),
    AgentTool(
      name: 'reddit_list',
      description:
          'List posts from a subreddit (new/hot/top). Returns posts with '
          'titles, authors, and URLs.',
      parameters: {
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
      execute: (args, ctx) => _invokeChannel(
        ctx,
        'reddit',
        'reddit_list',
        args,
        title: 'r/${(args['subreddit'] ?? '').toString().replaceFirst('r/', '')}',
      ),
    ),
    AgentTool(
      name: 'nostr_search',
      description:
          'Search Nostr text notes by query (NIP-50). Returns posts with '
          'authors, timestamps, and text.',
      parameters: {
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
      execute: (args, ctx) => _invokeChannel(
        ctx,
        'nostr',
        'nostr_search',
        args,
        title: 'Nostr search: ${args['query'] ?? ''}',
      ),
    ),
    AgentTool(
      name: 'nostr_hashtag',
      description:
          'List recent Nostr notes tagged with a hashtag (e.g. bitcoin).',
      parameters: {
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
      execute: (args, ctx) => _invokeChannel(
        ctx,
        'nostr',
        'nostr_hashtag',
        args,
        title: '#${args['hashtag'] ?? ''}',
      ),
    ),
    AgentTool(
      name: 'usenet_search',
      description:
          'Search Usenet indexers for a query, optionally filtered by '
          'category (movies, tv, music, games, software, books, audio, other).',
      parameters: {
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
      execute: (args, ctx) => _invokeChannel(
        ctx,
        'usenet',
        'usenet_search',
        args,
        title: 'Usenet: ${args['query'] ?? ''}',
      ),
    ),
    AgentTool(
      name: 'rss_fetch',
      description:
          'Fetch an RSS or Atom feed URL and return its recent items.',
      parameters: {
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
      execute: (args, ctx) => _invokeChannel(
        ctx,
        'rss',
        'rss_fetch',
        args,
        title: 'RSS feed',
      ),
    ),
  ];

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
      return const AgentResponse.text('What would you like me to look up?');
    }

    final llmMessages = <LlmMessage>[
      if (message case UserMessage(:final history?)) ...history,
      LlmMessage.user(content),
    ];

    return processLlmRequest(
      context: context,
      messages: llmMessages,
      systemPrompt: systemPrompt,
      temperature: 0.4,
    );
  }

  Future<ToolResult> _webSearch(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final query = (args['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return const ToolResult.error('A search query is required.');
    }
    final registry = context.channelRegistry;
    if (registry == null) {
      return const ToolResult.error('Web channel registry is unavailable.');
    }

    final result = await registry.invoke('web', 'web_search', args);
    return switch (result) {
      ChannelContentResult(:final items) => ToolResult.channel(
        channel: Channel(
          entityUri: 'web:search:${Uri.encodeComponent(query)}',
          entityType: ChannelEntityType.custom,
          title: 'Web search: $query',
          sourcePluginId: 'web',
        ),
        items: items,
        summary: 'Top ${items.length} results for "$query"',
      ),
      ChannelTextResult(:final content) => ToolResult.text(content),
      ChannelJsonResult(:final data) => ToolResult.text(
        'Search returned structured data (${data.length} fields).',
      ),
      ChannelErrorResult(:final message) => ToolResult.error(message),
    };
  }

  Future<ToolResult> _webFetch(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final registry = context.channelRegistry;
    if (registry == null) {
      return const ToolResult.error('Web channel registry is unavailable.');
    }
    final result = await registry.invoke('web', 'web_fetch', args);
    return switch (result) {
      ChannelTextResult(:final content) => ToolResult.text(content),
      ChannelErrorResult(:final message) => ToolResult.error(message),
      _ => const ToolResult.text('Fetched the page.'),
    };
  }

  /// Invokes any channel server tool and presents the result as a channel
  /// (typed content) or text/error.
  Future<ToolResult> _invokeChannel(
    AgentContext context,
    String serverId,
    String tool,
    Map<String, dynamic> args, {
    required String title,
  }) async {
    final registry = context.channelRegistry;
    if (registry == null) {
      return ToolResult.error('Channel registry is unavailable.');
    }
    final result = await registry.invoke(serverId, tool, args);
    return switch (result) {
      ChannelContentResult(:final items) => ToolResult.channel(
        channel: Channel(
          entityUri: '$serverId:$tool',
          entityType: ChannelEntityType.custom,
          title: title,
          sourcePluginId: serverId,
        ),
        items: items,
        summary: items.isEmpty ? null : '${items.length} items',
      ),
      ChannelTextResult(:final content) => ToolResult.text(content),
      ChannelErrorResult(:final message) => ToolResult.error(message),
      _ => const ToolResult.text('Done.'),
    };
  }
}