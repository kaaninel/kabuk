/// Wikipedia content plugin.
///
/// Adapts the MediaWiki Action API and REST API into [ContentItem]
/// objects. Supports searching articles and resolving Wikipedia URLs
/// to structured content. Configurable language via the `language`
/// config field (defaults to `'en'`). No API key is required.
library;

import 'dart:convert';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show IconData;
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/plugins/context.dart';
import 'package:kabuk/plugins/plugin.dart';
import 'package:meta/meta.dart';

/// Content plugin for Wikipedia.
///
/// Capabilities:
/// - **search** — article search via the MediaWiki Action API.
/// - **urlResolve** — resolve `*.wikipedia.org` URLs to article
///   summaries via the REST API.
///
/// Articles are mapped to [ContentType.article] items with
/// [ArticleMeta] metadata containing the article extract.
@immutable
class WikipediaPlugin implements ContentPlugin {
  /// Creates a [WikipediaPlugin].
  const WikipediaPlugin();

  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------

  @override
  String get id => 'wikipedia';

  @override
  String get name => 'Wikipedia';

  @override
  String get description => 'The free encyclopedia — articles in 300+ languages.';

  @override
  String get version => '1.0.0';

  @override
  IconData get iconData => Icons.menu_book_outlined;

  @override
  PluginCategory get category => PluginCategory.reference;

  @override
  Set<ContentCapability> get capabilities => const {
        ContentCapability.search,
        ContentCapability.urlResolve,
      };

  @override
  List<PluginConfigField> get configFields => const [
        PluginConfigField(
          key: 'language',
          label: 'Language',
          description: 'Wikipedia language edition to use.',
          type: PluginConfigFieldType.choice,
          choices: ['en', 'es', 'fr', 'de', 'ja', 'zh', 'ru', 'pt', 'it'],
          defaultValue: 'en',
        ),
      ];

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
      throw StateError('WikipediaPlugin has not been initialized.');
    }
    return ctx;
  }

  /// Returns the configured language code, falling back to `'en'`.
  String get _lang => _ctx.getConfig('language') ?? 'en';

  @override
  Future<void> initialize(PluginContext context) async {
    _context = context;
    context.log('WikipediaPlugin initialized (lang: ${context.getConfig('language') ?? 'en'})');
  }

  @override
  Future<void> dispose() async {
    _context = null;
  }

  // ---------------------------------------------------------------------------
  // URL handling
  // ---------------------------------------------------------------------------

  static final _wikiUrlPattern = RegExp(
    r'^https?://([a-z]{2,3})\.wikipedia\.org',
  );

  /// Extracts the article title from a Wikipedia URL path.
  ///
  /// Handles both `/wiki/Title` and `/w/index.php?title=Title` forms.
  static String? _extractTitle(Uri uri) {
    // /wiki/Article_Title
    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments[0] == 'wiki') {
      return Uri.decodeComponent(segments.sublist(1).join('/'));
    }

    // /w/index.php?title=Article_Title
    final titleParam = uri.queryParameters['title'];
    if (titleParam != null) return titleParam;

    return null;
  }

  /// Extracts the language subdomain from a Wikipedia URL.
  static String? _extractLang(String url) {
    final match = _wikiUrlPattern.firstMatch(url);
    return match?.group(1);
  }

  @override
  bool canHandleUrl(String url) => _wikiUrlPattern.hasMatch(url);

  @override
  Future<ResolvedContent> resolveUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return const ResolvedNotHandled();

    final title = _extractTitle(uri);
    if (title == null) return const ResolvedNotHandled();

    final lang = _extractLang(url) ?? _lang;
    final summary = await _fetchSummary(title, lang: lang);
    if (summary == null) return const ResolvedNotHandled();

    return ResolvedContentItem(_summaryToContentItem(summary, lang: lang));
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
    final lang = _lang;
    final offset = page * perPage;

    // Use the MediaWiki Action API for richer search results.
    final uri = Uri.parse(
      'https://$lang.wikipedia.org/w/api.php'
      '?action=query'
      '&list=search'
      '&srsearch=${Uri.encodeQueryComponent(query)}'
      '&srlimit=$perPage'
      '&sroffset=$offset'
      '&srprop=snippet|titlesnippet'
      '&format=json',
    );

    final response = await _ctx.httpClient.get(uri);
    if (response.statusCode != 200) {
      _ctx.log(
        'Wikipedia search failed',
        error: 'HTTP ${response.statusCode}: ${response.body}',
      );
      return const [];
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final results =
        (json['query'] as Map<String, dynamic>?)?['search'] as List<dynamic>? ??
            const [];

    // For each result, fetch the summary to get thumbnail and extract.
    final futures = results.map((r) async {
      final result = r as Map<String, dynamic>;
      final title = result['title'] as String? ?? '';
      final pageId = result['pageid'] as int? ?? 0;
      final snippet = result['snippet'] as String? ?? '';

      // Attempt to enrich with REST summary.
      final summary = await _fetchSummary(title, lang: lang);
      if (summary != null) {
        return _summaryToContentItem(summary, lang: lang);
      }

      // Fallback to basic search result data.
      return ContentItem(
        sourcePluginId: id,
        externalId: pageId.toString(),
        contentType: ContentType.article,
        title: title,
        description: _stripHtml(snippet),
        url: 'https://$lang.wikipedia.org/wiki/${Uri.encodeComponent(title)}',
        metadata: ArticleMeta(
          body: _stripHtml(snippet),
        ),
        extra: {
          'wikiLang': lang,
          'pageId': pageId.toString(),
        },
      );
    });

    return Future.wait(futures);
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
    throw UnsupportedError('WikipediaPlugin does not support channels.');
  }

  // ---------------------------------------------------------------------------
  // Trending (not supported)
  // ---------------------------------------------------------------------------

  @override
  Future<List<ContentItem>> fetchTrending({
    int page = 0,
    int perPage = 20,
  }) {
    throw UnsupportedError('WikipediaPlugin does not support trending.');
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Fetch the REST API summary for an article [title].
  Future<Map<String, dynamic>?> _fetchSummary(
    String title, {
    required String lang,
  }) async {
    final encoded = Uri.encodeComponent(title.replaceAll(' ', '_'));
    final uri = Uri.parse(
      'https://$lang.wikipedia.org/api/rest_v1/page/summary/$encoded',
    );

    final response = await _ctx.httpClient.get(uri);
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body);
    if (data == null || data is! Map<String, dynamic>) return null;
    return data;
  }

  /// Convert a REST API summary response to a [ContentItem].
  ContentItem _summaryToContentItem(
    Map<String, dynamic> summary, {
    required String lang,
  }) {
    final title = summary['title'] as String? ?? '';
    final extract = summary['extract'] as String?;
    final extractHtml = summary['extract_html'] as String?;
    final pageId = summary['pageid'] as int? ?? 0;
    final summaryDescription = summary['description'] as String?;

    // Thumbnail
    final thumbnail = summary['thumbnail'] as Map<String, dynamic>?;
    final thumbnailUrl = thumbnail?['source'] as String?;

    // Content URLs
    final contentUrls = summary['content_urls'] as Map<String, dynamic>?;
    final desktopUrls = contentUrls?['desktop'] as Map<String, dynamic>?;
    final articleUrl = desktopUrls?['page'] as String?;

    return ContentItem(
      sourcePluginId: id,
      externalId: pageId.toString(),
      contentType: ContentType.article,
      title: title,
      description: summaryDescription ?? extract,
      url: articleUrl ??
          'https://$lang.wikipedia.org/wiki/${Uri.encodeComponent(title)}',
      thumbnailUrl: thumbnailUrl,
      metadata: ArticleMeta(
        body: extract,
        bodyHtml: extractHtml,
        wordCount: extract?.split(RegExp(r'\s+')).length,
      ),
      extra: {
        'wikiLang': lang,
        'pageId': pageId.toString(),
      },
    );
  }

  /// Strips basic HTML tags from a [text] string.
  static String _stripHtml(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '');
  }
}
