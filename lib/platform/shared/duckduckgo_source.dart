/// DuckDuckGo feed source implementation.
///
/// Turns a DuckDuckGo search into a [FeedSource], so a search query can be
/// subscribed to like any other feed (`ddg://search?q=flutter`).
///
/// Uses two endpoints:
/// - the official **Instant Answer API** (`api.duckduckgo.com`) for the
///   structured answer box, and
/// - the **HTML search results** page (`html.duckduckgo.com/html`) for full
///   web results (DuckDuckGo has no free full-results JSON API, so the HTML
///   results page is parsed into [FeedItem]s).
library;

import 'dart:convert';
import 'dart:developer' as dev;

import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/mesh.dart';

/// [FeedSource] implementation for DuckDuckGo searches.
///
/// Supports URL formats:
/// - `ddg://search?q=<query>` — canonical Kabuk format
/// - `ddg:<query>` — shorthand
/// - `duckduckgo://search?q=<query>` — alias
class DuckDuckGoFeedSource implements FeedSource {
  /// Creates a [DuckDuckGoFeedSource] with the given [mesh] service.
  DuckDuckGoFeedSource({required MeshService mesh}) : _mesh = mesh;

  final MeshService _mesh;

  /// Browser-like User-Agent — the HTML results page expects a real browser.
  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const _headers = {
    'User-Agent': _userAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// Max web results returned per fetch.
  static const _maxResults = 20;

  @override
  FeedSourceType get type => FeedSourceType.duckduckgo;

  @override
  Future<List<FeedItem>> fetch(String url) async {
    final query = parseDuckDuckGoQuery(url);
    if (query.isEmpty) return const [];

    final items = <FeedItem>[];
    final instant = await _fetchInstantAnswer(query);
    if (instant != null) items.add(instant);
    items.addAll(await _fetchWebResults(query));
    return items;
  }

  @override
  Future<bool> validate(String url) async =>
      parseDuckDuckGoQuery(url).isNotEmpty;

  // ---------------------------------------------------------------------------
  // Instant Answer API
  // ---------------------------------------------------------------------------

  /// Fetches the structured Instant Answer box, if one exists.
  Future<FeedItem?> _fetchInstantAnswer(String query) async {
    try {
      final uri = Uri.parse(
        'https://api.duckduckgo.com/'
        '?q=${Uri.encodeQueryComponent(query)}'
        '&format=json&no_html=1&skip_disambig=1',
      );
      final res = await _mesh.get(uri, headers: _headers);
      if (res.statusCode != 200) return null;

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final answer = json['Answer'] as String?;
      final abstractText = json['AbstractText'] as String?;
      final text = (answer?.isNotEmpty == true)
          ? answer
          : (abstractText?.isNotEmpty == true ? abstractText : null);
      if (text == null || text.isEmpty) return null;

      final heading = json['Heading'] as String?;
      final abstractUrl = json['AbstractURL'] as String?;
      final title = (heading?.isNotEmpty == true) ? heading! : query;
      final url = (abstractUrl?.isNotEmpty == true)
          ? abstractUrl!
          : 'https://duckduckgo.com/?q=${Uri.encodeQueryComponent(query)}';

      return FeedItem(title: title, url: url, description: text);
    } on Object catch (e) {
      dev.log('DDG instant answer failed: $e', name: 'DuckDuckGo', error: e);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // HTML web results
  // ---------------------------------------------------------------------------

  /// Fetches and parses full web results from the HTML results page.
  Future<List<FeedItem>> _fetchWebResults(String query) async {
    try {
      final uri = Uri.parse(
        'https://html.duckduckgo.com/html/'
        '?q=${Uri.encodeQueryComponent(query)}',
      );
      final res = await _mesh.get(uri, headers: _headers);
      if (res.statusCode != 200) return const [];

      final results = _parseHtmlResults(res.body);
      return results.take(_maxResults).toList();
    } on Object catch (e) {
      dev.log('DDG html results failed: $e', name: 'DuckDuckGo', error: e);
      return const [];
    }
  }

  /// Extracts result links + snippets from DuckDuckGo's HTML.
  static List<FeedItem> _parseHtmlResults(String html) {
    // Results: <a class="result__a" href="...">Title</a>
    final linkPattern = RegExp(
      r'<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>',
      dotAll: true,
    );
    // Snippets: <a class="result__snippet" ...>…</a>
    final snippetPattern = RegExp(
      r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
      dotAll: true,
    );

    final linkMatches = linkPattern.allMatches(html).toList();
    final snippetMatches = snippetPattern.allMatches(html).toList();

    final items = <FeedItem>[];
    for (var i = 0; i < linkMatches.length; i++) {
      final match = linkMatches[i];
      final href = _decodeResultUrl(match.group(1) ?? '');
      final title = _stripHtml(match.group(2) ?? '').trim();
      if (title.isEmpty || !href.startsWith('http')) continue;

      final snippet = i < snippetMatches.length
          ? _stripHtml(snippetMatches[i].group(1) ?? '').trim()
          : null;

      items.add(
        FeedItem(
          title: title,
          url: href,
          description: (snippet?.isNotEmpty == true) ? snippet : null,
        ),
      );
    }
    return items;
  }

  /// Decodes DuckDuckGo's redirect URL (`//duckduckgo.com/l/?uddg=…`).
  static String _decodeResultUrl(String href) {
    var h = href.trim();
    if (h.startsWith('//')) h = 'https:$h';
    final uri = Uri.tryParse(h);
    if (uri == null) return h;
    final uddg = uri.queryParameters['uddg'];
    if (uddg != null && uddg.isNotEmpty) {
      try {
        return Uri.decodeComponent(uddg);
      } on Object {
        return uddg;
      }
    }
    return uri.toString();
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }
}

/// Parses a DuckDuckGo feed URL into a search query string.
///
/// Supported formats:
/// - `ddg://search?q=<query>` / `duckduckgo://search?q=<query>`
/// - `ddg:<query>` / `ddg:search <query>`
String parseDuckDuckGoQuery(String input) {
  final trimmed = input.trim();
  if (trimmed.startsWith('ddg://') ||
      trimmed.startsWith('duckduckgo://')) {
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return '';
    final q = uri.queryParameters['q'];
    if (q != null && q.isNotEmpty) return q;
    // Fall back to the path segment after /search.
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length > 1) {
      return segments.sublist(1).join(' ');
    }
    return '';
  }
  if (trimmed.startsWith('duckduckgo:')) {
    return trimmed.substring('duckduckgo:'.length).trim();
  }
  if (trimmed.startsWith('ddg:')) {
    var rest = trimmed.substring(4).trim();
    rest = rest.replaceFirst(RegExp(r'^search\b'), '').trim();
    rest = rest.replaceFirst(RegExp(r'^[/?]+'), '').trim();
    return rest;
  }
  return '';
}

/// Builds a canonical DuckDuckGo feed URL for a [query].
String buildDuckDuckGoUrl(String query) =>
    'ddg://search?q=${Uri.encodeQueryComponent(query)}';