/// Web channel server — `web_search` and `web_fetch` tools.
///
/// This is Kabuk's built-in version of the standard `fetch` + web-search MCP
/// servers: an agent can search the web, then read a page, then reason about
/// the content — the "search-then-read" loop — without any external server.
///
/// - `web_search(query, max_results)` → [ChannelContentResult] of results
///   (DuckDuckGo Instant Answer + HTML results).
/// - `web_fetch(url, max_length, start_index)` → [ChannelTextResult] of the
///   page's readable text (bounded so it fits the LLM context).
library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:kabuk/platform/shared/duckduckgo_source.dart';
import 'package:kabuk/services/channels.dart';
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/web_extractor.dart';

/// A [ChannelServer] for web search and page fetching.
class WebChannelServer implements ChannelServer {
  /// Creates a [WebChannelServer] backed by the given [feedService].
  WebChannelServer({required FeedService feedService})
      : _feedService = feedService;

  final FeedService _feedService;

  @override
  String get id => 'web';

  @override
  String get name => 'Web';

  @override
  String get description =>
      'Search the web (DuckDuckGo) and fetch readable page content.';

  @override
  List<ChannelTool> listTools() => const [
    ChannelTool(
      name: 'web_search',
      description:
          'Search the web for a query. Returns ranked results with titles, '
          'URLs, and snippets. Use this before web_fetch to find pages.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'The search query.'},
          'max_results': {
            'type': 'integer',
            'description': 'Maximum results to return (default 8).',
          },
        },
        'required': ['query'],
      },
    ),
    ChannelTool(
      name: 'web_fetch',
      description:
          'Fetch a URL and return its readable text content (strips '
          'navigation/ads). Bounded by max_length for LLM context.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'description': 'The URL to read.'},
          'max_length': {
            'type': 'integer',
            'description': 'Max characters to return (default 8000).',
          },
          'start_index': {
            'type': 'integer',
            'description': 'Start offset into the text (for pagination).',
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
      throw ArgumentError('Web channel has no resources: $uri');

  @override
  Future<ChannelCallResult> callTool(
    String tool,
    Map<String, dynamic> args,
  ) async {
    return switch (tool) {
      'web_search' => _webSearch(args),
      'web_fetch' => _webFetch(args),
      _ => ChannelCallResult.error('Unknown web tool "$tool"'),
    };
  }

  Future<ChannelCallResult> _webSearch(Map<String, dynamic> args) async {
    final query = (args['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return const ChannelCallResult.error('A search query is required.');
    }
    final maxResults = (args['max_results'] as int?) ?? 8;

    try {
      final items = await _feedService.fetchItems(
        buildDuckDuckGoUrl(query),
        type: FeedSourceType.duckduckgo,
      );
      return ChannelCallResult.content(
        items.take(maxResults.clamp(1, 20)).map(feedItemToContentItem).toList(),
      );
    } on Object catch (e) {
      dev.log('web_search failed: $e', name: 'WebChannel', error: e);
      return ChannelCallResult.error('Web search failed: $e');
    }
  }

  Future<ChannelCallResult> _webFetch(Map<String, dynamic> args) async {
    final url = (args['url'] as String? ?? '').trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return const ChannelCallResult.error('A valid http(s) URL is required.');
    }
    final maxLength = (args['max_length'] as int?) ?? 8000;
    final startIndex = (args['start_index'] as int?) ?? 0;

    try {
      final extraction = await WebExtractor.fromUrl(url).timeout(
        const Duration(seconds: 20),
        onTimeout: () => WebExtraction(
          url: url,
          title: '',
          textContent: '',
        ),
      );
      var text = extraction.textContent;
      final title = extraction.title;

      // Bound the content for LLM context (with pagination).
      if (startIndex > 0 && startIndex < text.length) {
        text = text.substring(startIndex);
      }
      if (maxLength > 0 && text.length > maxLength) {
        text = '${text.substring(0, maxLength)}…';
      }

      final buffer = StringBuffer();
      if (title.trim().isNotEmpty) buffer.writeln('# $title');
      buffer.write(text);
      final body = buffer.toString().trim();
      if (body.isEmpty) {
        return ChannelCallResult.text(
          'Could not extract readable content from $url (empty page).',
        );
      }
      return ChannelCallResult.text(body);
    } on Object catch (e) {
      dev.log('web_fetch failed: $e', name: 'WebChannel', error: e);
      return ChannelCallResult.error('Web fetch failed: $e');
    }
  }
}