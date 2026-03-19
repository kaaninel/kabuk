/// Web content extraction service — "AI Reader Mode" extraction pipeline.
///
/// Provides two extraction modes:
/// 1. **JavaScript extraction** — runs in an already-loaded WebView to extract
///    structured content from the live DOM (used by QuickPeekSheet).
/// 2. **HTTP fetch extraction** — fetches HTML from a URL and parses it with
///    regex-based heuristics (fallback when no WebView is available).
///
/// Both modes produce a [WebExtraction] containing cleaned text content in
/// markdown format, metadata, images, and video URLs.
library;

import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

/// A link to an article discovered on an index/listing page.
///
/// Used when a page contains links to multiple articles (e.g., a news
/// homepage or blog index). Each [ExtractedLink] captures the metadata
/// visible on the index page without fetching the linked page.
class ExtractedLink {
  /// Creates an [ExtractedLink].
  const ExtractedLink({
    required this.url,
    required this.title,
    this.image,
    this.description,
  });

  /// Absolute URL of the linked article.
  final String url;

  /// Title text extracted from the link or its container.
  final String title;

  /// Thumbnail/hero image URL associated with this link, if any.
  final String? image;

  /// Short description or snippet, if available.
  final String? description;
}

/// Result of extracting content from a web page.
///
/// Contains the cleaned article text in markdown format along with
/// structured metadata (author, date, site name) and media URLs.
/// When the page is an index/listing page, [articleLinks] contains
/// links to individual articles discovered on the page.
class WebExtraction {
  /// Creates a [WebExtraction] with the given fields.
  const WebExtraction({
    required this.url,
    required this.title,
    required this.textContent,
    this.images = const [],
    this.videos = const [],
    this.articleLinks = const [],
    this.author,
    this.datePublished,
    this.siteName,
    this.favicon,
    this.description,
  });

  /// The source URL of the extracted page.
  final String url;

  /// Page title extracted from `<title>`, `og:title`, or `<h1>`.
  final String title;

  /// Cleaned text content in markdown format.
  final String textContent;

  /// Image URLs found in the article content.
  final List<String> images;

  /// Video URLs found in the article (including YouTube/Vimeo embeds).
  final List<String> videos;

  /// Article links discovered on the page (for index/listing pages).
  final List<ExtractedLink> articleLinks;

  /// Author name from `<meta name="author">` or `article:author`.
  final String? author;

  /// Publication date from `article:published_time` or similar.
  final DateTime? datePublished;

  /// Site name from `og:site_name`.
  final String? siteName;

  /// Favicon URL.
  final String? favicon;

  /// Page description from `og:description` or `<meta name="description">`.
  final String? description;
}

/// Extracts structured content from web pages.
///
/// Use [fromWebView] when a page is already loaded in a WebView (e.g.,
/// QuickPeekSheet). Use [fromUrl] as a fallback to fetch and parse HTML
/// directly via HTTP.
class WebExtractor {
  WebExtractor._();

  // ---------------------------------------------------------------------------
  // JavaScript extraction (primary mode)
  // ---------------------------------------------------------------------------

  /// Extracts content from an already-loaded WebView page.
  ///
  /// Injects a JavaScript snippet that reads the live DOM, finds the main
  /// content area using heuristics, and returns structured JSON. The [url]
  /// parameter should be the current page URL for the extraction result.
  static Future<WebExtraction> fromWebView(
    WebViewController controller, {
    required String url,
  }) async {
    try {
      final result = await controller.runJavaScriptReturningResult(
        _extractionJs,
      );

      final jsonStr = result is String ? result : result.toString();
      // WebView may wrap the result in quotes; strip them.
      final decoded =
          jsonStr.startsWith('"') && jsonStr.endsWith('"')
              ? jsonDecode(jsonStr) as String
              : jsonStr;

      final data = jsonDecode(decoded) as Map<String, dynamic>;
      return _parseExtractionJson(data, url);
    } catch (e, st) {
      dev.log('WebView extraction failed', error: e, stackTrace: st);
      // On any failure, return a minimal extraction so callers always
      // get something useful.
      return WebExtraction(url: url, title: '', textContent: '');
    }
  }

  // ---------------------------------------------------------------------------
  // HTTP fetch extraction (fallback mode)
  // ---------------------------------------------------------------------------

  /// Extracts content from a URL by fetching and parsing HTML.
  ///
  /// Uses [http.get] to download the page, then applies regex-based
  /// heuristics to pull out metadata, text, images, and videos. No
  /// external HTML parsing library is required.
  static Future<WebExtraction> fromUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (compatible; Kabuk/1.0; +https://kabuk.app)',
          'Accept': 'text/html,application/xhtml+xml',
        },
      );

      if (response.statusCode != 200) {
        return WebExtraction(url: url, title: url, textContent: '');
      }

      final html = response.body;
      return _parseHtml(html, url);
    } catch (e, st) {
      dev.log('HTTP extraction failed for $url', error: e, stackTrace: st);
      return WebExtraction(url: url, title: url, textContent: '');
    }
  }

  // ---------------------------------------------------------------------------
  // JavaScript snippet
  // ---------------------------------------------------------------------------

  static const _extractionJs = r'''
(function() {
  function meta(attr, value) {
    var el = document.querySelector('meta[' + attr + '="' + value + '"]');
    return el ? (el.getAttribute('content') || '') : '';
  }

  // --- Title ---
  var title = meta('property', 'og:title')
    || document.title
    || (document.querySelector('h1') ? document.querySelector('h1').innerText : '');

  // --- Metadata ---
  var siteName = meta('property', 'og:site_name');
  var description = meta('property', 'og:description') || meta('name', 'description');
  var author = meta('name', 'author') || meta('property', 'article:author');
  var datePublished = meta('property', 'article:published_time')
    || meta('name', 'date')
    || meta('property', 'og:article:published_time');
  var favicon = '';
  var fl = document.querySelector('link[rel="icon"]')
    || document.querySelector('link[rel="shortcut icon"]')
    || document.querySelector('link[rel="apple-touch-icon"]');
  if (fl) favicon = fl.getAttribute('href') || '';

  // --- Main content element ---
  var selectors = [
    'article', '[role="article"]', 'main', '[role="main"]',
    '.post-content', '.article-body', '.entry-content', '.article-content',
    '.post-body', '.story-body', '.content-body', '#article-body',
    '.td-post-content', '.post_content', '.article__body',
  ];
  var main = null;
  for (var i = 0; i < selectors.length; i++) {
    var el = document.querySelector(selectors[i]);
    if (el && el.innerText.trim().length > 100) { main = el; break; }
  }
  if (!main) {
    main = document.body.cloneNode(true);
    var remove = main.querySelectorAll(
      'nav, header, footer, aside, .sidebar, .nav, .menu, .footer, .header, ' +
      '.ad, .ads, .advertisement, .social-share, .comments, .comment, ' +
      'script, style, noscript, svg, [role="navigation"], [role="banner"], ' +
      '[role="contentinfo"], [aria-hidden="true"]'
    );
    for (var r = 0; r < remove.length; r++) remove[r].remove();
  }

  // --- Convert to markdown ---
  function toMarkdown(node) {
    if (!node) return '';
    var md = '';
    var children = node.childNodes;
    for (var i = 0; i < children.length; i++) {
      var c = children[i];
      if (c.nodeType === 3) {
        md += c.textContent;
      } else if (c.nodeType === 1) {
        var tag = c.tagName.toLowerCase();
        if (tag === 'script' || tag === 'style' || tag === 'noscript' || tag === 'svg') continue;
        if (tag === 'br') { md += '\n'; continue; }
        if (tag === 'h1') md += '\n\n# ' + c.innerText.trim() + '\n\n';
        else if (tag === 'h2') md += '\n\n## ' + c.innerText.trim() + '\n\n';
        else if (tag === 'h3') md += '\n\n### ' + c.innerText.trim() + '\n\n';
        else if (tag === 'h4') md += '\n\n#### ' + c.innerText.trim() + '\n\n';
        else if (tag === 'h5' || tag === 'h6') md += '\n\n##### ' + c.innerText.trim() + '\n\n';
        else if (tag === 'p' || tag === 'div') md += '\n\n' + toMarkdown(c) + '\n\n';
        else if (tag === 'blockquote') md += '\n\n> ' + c.innerText.trim().replace(/\n/g, '\n> ') + '\n\n';
        else if (tag === 'ul' || tag === 'ol') {
          var items = c.querySelectorAll(':scope > li');
          for (var li = 0; li < items.length; li++) {
            var prefix = tag === 'ol' ? ((li + 1) + '. ') : '- ';
            md += '\n' + prefix + items[li].innerText.trim();
          }
          md += '\n\n';
        }
        else if (tag === 'a') {
          var href = c.getAttribute('href') || '';
          var text = c.innerText.trim();
          if (text && href) md += '[' + text + '](' + href + ')';
          else if (text) md += text;
        }
        else if (tag === 'strong' || tag === 'b') md += '**' + c.innerText.trim() + '**';
        else if (tag === 'em' || tag === 'i') md += '*' + c.innerText.trim() + '*';
        else if (tag === 'code') md += '`' + c.innerText.trim() + '`';
        else if (tag === 'pre') md += '\n\n```\n' + c.innerText.trim() + '\n```\n\n';
        else if (tag === 'img') { /* handled separately */ }
        else md += toMarkdown(c);
      }
    }
    return md;
  }

  var textContent = toMarkdown(main).replace(/\n{3,}/g, '\n\n').trim();

  // --- Images ---
  var ogImage = meta('property', 'og:image');
  var images = [];
  if (ogImage) images.push(ogImage);
  var imgs = main.querySelectorAll('img');
  for (var i = 0; i < imgs.length; i++) {
    var src = imgs[i].getAttribute('src') || imgs[i].getAttribute('data-src') || '';
    if (!src) continue;
    var w = imgs[i].naturalWidth || parseInt(imgs[i].getAttribute('width') || '0', 10);
    var h = imgs[i].naturalHeight || parseInt(imgs[i].getAttribute('height') || '0', 10);
    if ((w > 0 && w < 200) || (h > 0 && h < 200)) continue;
    if (images.indexOf(src) === -1) images.push(src);
  }

  // --- Videos ---
  var videos = [];
  var ogVideo = meta('property', 'og:video');
  if (ogVideo) videos.push(ogVideo);
  var vidEls = document.querySelectorAll('video source, video[src]');
  for (var v = 0; v < vidEls.length; v++) {
    var vs = vidEls[v].getAttribute('src') || '';
    if (vs && videos.indexOf(vs) === -1) videos.push(vs);
  }
  var iframes = document.querySelectorAll('iframe');
  for (var f = 0; f < iframes.length; f++) {
    var fs = iframes[f].getAttribute('src') || '';
    if (fs && (fs.indexOf('youtube.com') !== -1 || fs.indexOf('youtu.be') !== -1
      || fs.indexOf('vimeo.com') !== -1 || fs.indexOf('player.vimeo.com') !== -1)) {
      if (videos.indexOf(fs) === -1) videos.push(fs);
    }
  }

  return JSON.stringify({
    title: title,
    textContent: textContent,
    images: images,
    videos: videos,
    author: author,
    datePublished: datePublished,
    siteName: siteName,
    favicon: favicon,
    description: description,
  });
})();
''';

  // ---------------------------------------------------------------------------
  // Shared parsing helpers
  // ---------------------------------------------------------------------------

  /// Builds a [WebExtraction] from the JSON map returned by the JS snippet.
  static WebExtraction _parseExtractionJson(
    Map<String, dynamic> data,
    String url,
  ) {
    DateTime? published;
    final dateStr = data['datePublished'] as String? ?? '';
    if (dateStr.isNotEmpty) {
      published = DateTime.tryParse(dateStr);
    }

    return WebExtraction(
      url: url,
      title: (data['title'] as String? ?? '').trim(),
      textContent: (data['textContent'] as String? ?? '').trim(),
      images: _stringList(data['images']),
      videos: _stringList(data['videos']),
      author: _nonEmpty(data['author'] as String?),
      datePublished: published,
      siteName: _nonEmpty(data['siteName'] as String?),
      favicon: _resolveUrl(url, _nonEmpty(data['favicon'] as String?)),
      description: _nonEmpty(data['description'] as String?),
    );
  }

  /// Parses raw HTML into a [WebExtraction] using regex heuristics.
  static WebExtraction _parseHtml(String html, String url) {
    // --- Meta tags ---
    final ogTitle = _metaContent(html, property: 'og:title');
    final ogDesc = _metaContent(html, property: 'og:description') ??
        _metaContent(html, name: 'description');
    final ogImage = _metaContent(html, property: 'og:image');
    final ogVideo = _metaContent(html, property: 'og:video');
    final ogSiteName = _metaContent(html, property: 'og:site_name');
    final author = _metaContent(html, name: 'author') ??
        _metaContent(html, property: 'article:author');
    final dateStr =
        _metaContent(html, property: 'article:published_time') ??
        _metaContent(html, name: 'date');

    // --- Title ---
    final titleTag = _firstMatch(html, r'<title[^>]*>(.*?)</title>');
    final title = ogTitle ?? titleTag ?? '';

    // --- Favicon ---
    final faviconMatch = _firstMatch(
      html,
      r'''<link[^>]+rel=["'](?:icon|shortcut icon|apple-touch-icon)["'][^>]+href=["']([^"']+)["']''',
    );
    final faviconAlt = _firstMatch(
      html,
      r'''<link[^>]+href=["']([^"']+)["'][^>]+rel=["'](?:icon|shortcut icon)["']''',
    );

    // --- Main content ---
    final textContent = _extractMainText(html);

    // --- Images (resolve all to absolute URLs) ---
    final images = <String>[];
    if (ogImage != null && ogImage.isNotEmpty) {
      final resolved = _resolveUrl(url, ogImage);
      if (resolved != null) images.add(resolved);
    }
    final imgRegex = RegExp(
      r'<img[^>]+src=["' "'" r']([^"' "'" r']+)["' "'" r']',
      caseSensitive: false,
    );
    for (final m in imgRegex.allMatches(html)) {
      final src = m.group(1) ?? '';
      if (src.isNotEmpty) {
        final resolved = _resolveUrl(url, src);
        if (resolved != null && !images.contains(resolved)) {
          images.add(resolved);
        }
      }
    }

    // --- Videos ---
    final videos = <String>[];
    if (ogVideo != null && ogVideo.isNotEmpty) videos.add(ogVideo);
    final videoSrcRegex = RegExp(
      r'<(?:video|source)[^>]+src=["' "'" r']([^"' "'" r']+)["' "'" r']',
      caseSensitive: false,
    );
    for (final m in videoSrcRegex.allMatches(html)) {
      final src = m.group(1) ?? '';
      if (src.isNotEmpty && !videos.contains(src)) videos.add(src);
    }
    final iframeRegex = RegExp(
      r'<iframe[^>]+src=["' "'" r']([^"' "'" r']+)["' "'" r']',
      caseSensitive: false,
    );
    for (final m in iframeRegex.allMatches(html)) {
      final src = m.group(1) ?? '';
      if (_isVideoEmbed(src) && !videos.contains(src)) videos.add(src);
    }

    DateTime? published;
    if (dateStr != null && dateStr.isNotEmpty) {
      published = DateTime.tryParse(dateStr);
    }

    // --- Article links (for index/listing pages) ---
    final articleLinks = _extractArticleLinks(html, url);

    return WebExtraction(
      url: url,
      title: _decodeEntities(title).trim(),
      textContent: textContent,
      images: images,
      videos: videos,
      articleLinks: articleLinks,
      author: _nonEmpty(author),
      datePublished: published,
      siteName: _nonEmpty(ogSiteName),
      favicon: _resolveUrl(url, faviconMatch ?? faviconAlt),
      description: ogDesc != null ? _decodeEntities(ogDesc) : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Article link extraction
  // ---------------------------------------------------------------------------

  /// Non-article path segments that should be filtered out.
  static final _nonArticlePaths = RegExp(
    r'^/(about|contact|login|signup|register|privacy|terms|faq|help|search'
    r'|categories|tags|authors?|archive|page|#|javascript:|newsletter'
    r'|subscribe|account|profile|settings|cart|checkout|sitemap)',
    caseSensitive: false,
  );

  /// Heuristic: titles that look like a person name (2-3 capitalized words,
  /// no lowercase-starting words, no punctuation/numbers).
  static final _personNamePattern = RegExp(
    r'^[A-Z][a-z]+(\s+[A-Z][a-z]+){1,2}$',
  );

  /// Matches promotional/CTA titles that aren't real articles.
  static final _promoTitlePattern = RegExp(
    r'(?:^subscribe\s+to\b|^sign\s+up\b|^join\s+(our|the)\b|'
    r'^follow\s+us\b|^download\s+(our|the)\b|^get\s+the\s+app\b|'
    r'^create\s+(an?\s+)?account\b|^start\s+your\b|^try\s+it\b)',
    caseSensitive: false,
  );

  /// Extracts article-like links from raw HTML.
  ///
  /// Scans for `<a>` tags inside article containers, cards, and common
  /// listing patterns. Deduplicates by URL and limits to 50 results.
  static List<ExtractedLink> _extractArticleLinks(String html, String baseUrl) {
    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null) return const [];
    final baseHost = baseUri.host;

    // Strip nav, header, footer, sidebar, and ad regions to reduce noise.
    final cleanedHtml = html.replaceAll(
      RegExp(
        r'<(nav|header|footer|aside)[^>]*>.*?</\1>',
        caseSensitive: false,
        dotAll: true,
      ),
      '',
    );

    // Match <a> tags with href attributes.
    final linkRegex = RegExp(
      r'<a\s[^>]*href=["' "'" r']([^"' "'" r']+)["' "'" r'][^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    );

    final seen = <String>{};
    final links = <ExtractedLink>[];

    for (final match in linkRegex.allMatches(cleanedHtml)) {
      if (links.length >= 50) break;

      final rawHref = match.group(1) ?? '';
      final innerHtml = match.group(2) ?? '';
      if (rawHref.isEmpty) continue;

      // Resolve to absolute URL.
      final resolved = _resolveUrl(baseUrl, rawHref);
      if (resolved == null || resolved.isEmpty) continue;

      final linkUri = Uri.tryParse(resolved);
      if (linkUri == null) continue;

      // Only keep links on the same domain (or closely related sub-domains).
      if (!linkUri.host.endsWith(baseHost) &&
          !baseHost.endsWith(linkUri.host)) {
        continue;
      }

      // Filter out non-article paths.
      if (_nonArticlePaths.hasMatch(linkUri.path)) continue;

      // Must have a meaningful path (at least /segment/something or slug).
      if (linkUri.pathSegments.where((s) => s.isNotEmpty).length < 2 &&
          !linkUri.path.contains('-')) {
        continue;
      }

      // Skip root/homepage links.
      if (linkUri.path == '/' || linkUri.path.isEmpty) continue;

      // Extract title from link text. Prefer heading elements (h1-h6) to
      // avoid concatenating headline + description when both are inside <a>.
      var title = '';
      final headingMatch = RegExp(
        r'<h[1-6][^>]*>(.*?)</h[1-6]>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(innerHtml);
      if (headingMatch != null) {
        title = _decodeEntities(_stripTags(headingMatch.group(1) ?? '')).trim();
      }
      if (title.isEmpty) {
        title = _decodeEntities(_stripTags(innerHtml)).trim();
      }
      // Collapse whitespace.
      title = title.replaceAll(RegExp(r'\s+'), ' ');
      if (title.length < 10) continue;
      // Skip titles that look like a person name (e.g. "Aisha Malik").
      if (_personNamePattern.hasMatch(title)) continue;
      // Skip titles with too few words (likely nav items, not headlines).
      if (title.split(' ').length < 4 && title.length < 30) continue;
      // Skip promotional/CTA titles (e.g. "Subscribe to Ars Technica").
      if (_promoTitlePattern.hasMatch(title)) continue;
      // Truncate very long titles.
      if (title.length > 200) title = title.substring(0, 200);

      // Deduplicate.
      final canonical = linkUri.replace(fragment: '').toString();
      if (seen.contains(canonical)) continue;
      seen.add(canonical);

      // Try to find an associated image. Modern sites use lazy loading
      // (data-src, srcset, data-original) so we check multiple attributes.
      String? image;
      final imgTagRegex = RegExp(r'<img\s[^>]+>', caseSensitive: false);

      // Check inner HTML first (image inside the link).
      final innerImgTag = imgTagRegex.firstMatch(innerHtml);
      if (innerImgTag != null) {
        image = _bestImgUrl(innerImgTag.group(0)!, baseUrl);
      }

      // Also check <picture><source> inside the link.
      if (image == null) {
        final sourceMatch = RegExp(
          r'<source[^>]+srcset=["\x27]([^"\x27,]+)',
          caseSensitive: false,
        ).firstMatch(innerHtml);
        if (sourceMatch != null) {
          final url = sourceMatch.group(1)?.trim();
          if (url != null && url.isNotEmpty && !url.startsWith('data:')) {
            image = _resolveUrl(baseUrl, url);
          }
        }
      }

      // Then check backward context (~800 chars).
      if (image == null) {
        final linkStart = match.start;
        final searchStart = (linkStart - 800).clamp(0, linkStart);
        final beforeHtml = cleanedHtml.substring(searchStart, linkStart);
        final beforeImgTags = imgTagRegex.allMatches(beforeHtml);
        if (beforeImgTags.isNotEmpty) {
          image = _bestImgUrl(beforeImgTags.last.group(0)!, baseUrl);
        }
      }

      // Finally check forward context (~800 chars).
      if (image == null) {
        final linkEnd = match.end;
        final searchEnd = (linkEnd + 800).clamp(linkEnd, cleanedHtml.length);
        final afterHtml = cleanedHtml.substring(linkEnd, searchEnd);
        final afterImgTag = imgTagRegex.firstMatch(afterHtml);
        if (afterImgTag != null) {
          image = _bestImgUrl(afterImgTag.group(0)!, baseUrl);
        }
      }

      links.add(ExtractedLink(
        url: canonical,
        title: _decodeEntities(title),
        image: image,
      ));
    }

    return links;
  }

  // ---------------------------------------------------------------------------
  // HTML regex helpers
  // ---------------------------------------------------------------------------

  /// Extracts the best image URL from an `<img>` tag string, handling
  /// lazy-loading attributes (`data-src`, `data-original`, `srcset`, etc.).
  static String? _bestImgUrl(String imgTag, String baseUrl) {
    for (final attr in [
      'data-src',
      'data-original',
      'data-lazy-src',
      'data-full-src',
      'src',
    ]) {
      final m = RegExp(
        '$attr="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(imgTag);
      if (m != null) {
        final val = m.group(1) ?? '';
        if (val.isNotEmpty &&
            !val.startsWith('data:') &&
            !val.contains('1x1') &&
            !val.contains('pixel') &&
            !val.contains('spacer') &&
            !val.contains('blank.')) {
          return _resolveUrl(baseUrl, val);
        }
      }
    }
    // Fallback: first URL from srcset.
    final srcsetMatch = RegExp(
      r'srcset="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(imgTag);
    if (srcsetMatch != null) {
      final srcset = srcsetMatch.group(1) ?? '';
      final firstUrl = srcset.split(',').first.trim().split(' ').first;
      if (firstUrl.isNotEmpty && !firstUrl.startsWith('data:')) {
        return _resolveUrl(baseUrl, firstUrl);
      }
    }
    return null;
  }

  /// Extracts a `<meta>` tag content value by property or name attribute.
  static String? _metaContent(
    String html, {
    String? property,
    String? name,
  }) {
    final attr = property != null
        ? 'property=["\'"]$property["\'"]'
        : 'name=["\'"]$name["\'"]';
    final regex = RegExp(
      '<meta[^>]+$attr[^>]+content=["\'"]([^"\'"]*)["\'"]',
      caseSensitive: false,
    );
    final alt = RegExp(
      '<meta[^>]+content=["\'"]([^"\'"]*)["\'"][^>]+$attr',
      caseSensitive: false,
    );
    final match = regex.firstMatch(html) ?? alt.firstMatch(html);
    final value = match?.group(1);
    return (value != null && value.isNotEmpty) ? _decodeEntities(value) : null;
  }

  /// Returns the first capture group from [pattern] in [html], or `null`.
  static String? _firstMatch(String html, String pattern) {
    final m = RegExp(pattern, caseSensitive: false, dotAll: true)
        .firstMatch(html);
    final value = m?.group(1);
    return (value != null && value.isNotEmpty) ? _decodeEntities(value) : null;
  }

  /// Attempts to isolate the main article text from raw HTML.
  ///
  /// Looks for `<article>`, `<main>`, or common content class containers.
  /// Falls back to `<body>` with boilerplate sections stripped.
  static String _extractMainText(String html) {
    // Try to find a main content block.
    final blockPatterns = [
      r'<article[^>]*>(.*?)</article>',
      r'<main[^>]*>(.*?)</main>',
      r'<div[^>]+class="[^"]*(?:post-content|article-body|entry-content|article-content)[^"]*"[^>]*>(.*?)</div>',
      r'<div[^>]+role="main"[^>]*>(.*?)</div>',
    ];

    String? contentHtml;
    for (final p in blockPatterns) {
      final m = RegExp(p, caseSensitive: false, dotAll: true).firstMatch(html);
      if (m != null && (m.group(1) ?? '').length > 200) {
        contentHtml = m.group(1);
        break;
      }
    }

    contentHtml ??= _firstMatch(html, r'<body[^>]*>(.*)</body>') ?? html;

    // Strip boilerplate tags.
    contentHtml = contentHtml.replaceAll(
      RegExp(
        r'<(script|style|noscript|nav|header|footer|aside|svg|form|iframe|button)[^>]*>.*?</\1>',
        caseSensitive: false,
        dotAll: true,
      ),
      '',
    );

    // Strip common boilerplate sections (newsletter signups, related/popular
    // content, ad containers, sidebar widgets).
    contentHtml = contentHtml.replaceAll(
      RegExp(
        r'<div[^>]+(?:class|id)="[^"]*(?:newsletter|signup|sign-up|subscribe|'
        r'popular|trending|related|sidebar|widget|ad-|advertisement|'
        r'social-share|share-bar|recirculation|promo|cookie|consent|'
        r'most-popular|recommended|follow-topics|author-follow|'
        r'article-footer|story-footer|cta|callout)[^"]*"[^>]*>.*?</div>',
        caseSensitive: false,
        dotAll: true,
      ),
      '',
    );

    // Strip <section> boilerplate (e.g. "Most Popular" or "Related" sections).
    contentHtml = contentHtml.replaceAll(
      RegExp(
        r'<section[^>]+(?:class|id)="[^"]*(?:popular|trending|related|'
        r'newsletter|sidebar|widget|promo|recommended|'
        r'follow-topics|article-footer|story-footer|cta)[^"]*"[^>]*>.*?</section>',
        caseSensitive: false,
        dotAll: true,
      ),
      '',
    );

    // Convert headings to markdown.
    for (var h = 1; h <= 6; h++) {
      final prefix = '#' * h;
      contentHtml = contentHtml!.replaceAllMapped(
        RegExp('<h$h[^>]*>(.*?)</h$h>', caseSensitive: false, dotAll: true),
        (m) => '\n\n$prefix ${_stripTags(m.group(1) ?? '')}\n\n',
      );
    }

    // Convert <p>, <br>, <li> to newlines.
    contentHtml = contentHtml!
        .replaceAll(RegExp(r'<br\s*/?>',  caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</?p[^>]*>', caseSensitive: false), '\n\n')
        .replaceAllMapped(
          RegExp(r'<li[^>]*>(.*?)</li>', caseSensitive: false, dotAll: true),
          (m) => '\n- ${_stripTags(m.group(1) ?? '')}',
        );

    // Add spaces after closing inline tags to prevent word concatenation
    // (e.g. "<a>Middle East</a><a>Israel</a>" → "Middle East Israel").
    contentHtml = contentHtml.replaceAll(
      RegExp(r'</(?:a|span|div|td|th|dt|dd|label|em|strong|b|i|u|time)\s*>',
          caseSensitive: false),
      ' ',
    );

    // Strip remaining tags, decode entities, and clean whitespace.
    final text = _decodeEntities(_stripTags(contentHtml))
        .replaceAll(RegExp(r'[^\S\n]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    return text;
  }

  /// Removes all HTML tags from [html].
  static String _stripTags(String html) =>
      html.replaceAll(RegExp(r'<[^>]+>'), '');

  /// Decodes common HTML entities.
  static String _decodeEntities(String text) => text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
        final code = int.tryParse(m.group(1) ?? '');
        return code != null ? String.fromCharCode(code) : m.group(0)!;
      })
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
        final code = int.tryParse(m.group(1) ?? '', radix: 16);
        return code != null ? String.fromCharCode(code) : m.group(0)!;
      });

  /// Returns `true` if [src] looks like a YouTube or Vimeo embed URL.
  static bool _isVideoEmbed(String src) =>
      src.contains('youtube.com') ||
      src.contains('youtu.be') ||
      src.contains('vimeo.com') ||
      src.contains('player.vimeo.com');

  /// Converts a list of dynamic values to a `List<String>`.
  static List<String> _stringList(dynamic value) {
    if (value is List) return value.whereType<String>().toList();
    return const [];
  }

  /// Returns [value] if it's non-null and non-empty, otherwise `null`.
  static String? _nonEmpty(String? value) =>
      (value != null && value.trim().isNotEmpty) ? value.trim() : null;

  /// Resolves a potentially relative [path] against the page [baseUrl].
  static String? _resolveUrl(String baseUrl, String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    try {
      return Uri.parse(baseUrl).resolve(path).toString();
    } catch (_) {
      return path;
    }
  }

  /// Resolves a relative [path] against [baseUrl] to an absolute URL.
  ///
  /// Public wrapper for use by other services (e.g., ReaderModeService).
  static String? resolveUrl(String baseUrl, String path) =>
      _resolveUrl(baseUrl, path);
}
