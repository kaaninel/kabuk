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

import 'package:flutter/foundation.dart';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
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
    this.navigationLinks = const [],
    this.author,
    this.datePublished,
    this.siteName,
    this.favicon,
    this.description,
    this.nextPageUrl,
    this.jsonLd = const [],
    this.openGraph = const {},
    this.microdata = const [],
    this.schemaTypes = const [],
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

  /// Navigation links found on the page (categories, sections, related).
  ///
  /// These are links that aren't articles but may be useful for the user
  /// to navigate to other sections of the site.
  final List<ExtractedLink> navigationLinks;

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

  /// URL of the next page for paginated content.
  ///
  /// Detected from `<link rel="next">`, pagination controls, or common
  /// URL patterns (e.g. `/page/2`, `?page=2`).
  final String? nextPageUrl;

  /// JSON-LD structured data found in `<script type="application/ld+json">` tags.
  final List<Map<String, dynamic>> jsonLd;

  /// OpenGraph metadata as a structured map.
  final Map<String, String> openGraph;

  /// Microdata/RDFa structured data extracted from itemscope/itemprop attributes.
  final List<Map<String, dynamic>> microdata;

  /// Schema.org types detected on the page (from JSON-LD or microdata).
  final List<String> schemaTypes;
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
  /// Realistic browser User-Agent for HTTP extraction.
  static const _browserUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 '
      'Mobile/15E148 Safari/604.1';

  static Future<WebExtraction> fromUrl(String url) async {
    debugPrint('[WebExtractor] fromUrl: fetching $url');
    try {
      final uri = Uri.parse(url);
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': _browserUserAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'Accept-Charset': 'utf-8',
        },
      );

      debugPrint('[WebExtractor] HTTP ${response.statusCode} for $url '
          '(${response.body.length} bytes)');

      if (response.body.length < 500) {
        debugPrint('[WebExtractor] ⚠ Very small response — likely a block page '
            'or redirect wall. Body: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
      }

      if (response.statusCode != 200) {
        debugPrint('[WebExtractor] Non-200 status: ${response.statusCode}');
        return WebExtraction(url: url, title: url, textContent: '');
      }

      // Decode with proper charset from Content-Type header
      final html = _decodeResponseBody(response);
      final result = _parseHtml(html, url);
      debugPrint('[WebExtractor] Extracted: title="${result.title}", '
          'text=${result.textContent.length} chars, '
          'links=${result.articleLinks.length}, '
          'images=${result.images.length}');
      return result;
    } catch (e, st) {
      debugPrint('[WebExtractor] HTTP extraction failed for $url: $e');
      dev.log('HTTP extraction failed for $url', error: e, stackTrace: st);
      return WebExtraction(url: url, title: url, textContent: '');
    }
  }

  /// Decodes the HTTP response body using the charset from Content-Type header.
  ///
  /// Falls back to UTF-8 if no charset is specified. Handles common charsets
  /// like ISO-8859-1 and Windows-1252 that cause mojibake when decoded as UTF-8.
  static String _decodeResponseBody(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    final charsetMatch =
        RegExp(r'charset=([^\s;]+)', caseSensitive: false).firstMatch(contentType);
    final charset = charsetMatch?.group(1)?.toLowerCase().replaceAll('-', '');

    if (charset != null && charset != 'utf8') {
      // For Latin-1/Windows-1252, decode bytes with latin1 then let Dart handle it
      if (charset == 'iso88591' || charset == 'latin1' || charset == 'windows1252') {
        return latin1.decode(response.bodyBytes);
      }
    }

    // Default: try UTF-8 with allowMalformed to prevent crashes
    try {
      return utf8.decode(response.bodyBytes);
    } catch (_) {
      return latin1.decode(response.bodyBytes);
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

  function resolveUrl(url) {
    if (!url) return '';
    try { return new URL(url, document.baseURI).href; } catch(e) { return url; }
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
  if (fl) favicon = resolveUrl(fl.getAttribute('href'));

  // --- Next Page (Pagination) ---
  var nextPageUrl = '';
  var nextLink = document.querySelector('link[rel="next"]');
  if (nextLink) nextPageUrl = resolveUrl(nextLink.getAttribute('href'));
  if (!nextPageUrl) {
    var anchors = document.querySelectorAll('a');
    for (var i = 0; i < anchors.length; i++) {
      var a = anchors[i];
      var rel = a.getAttribute('rel');
      var txt = a.innerText.trim().toLowerCase();
      if (rel === 'next' || txt === 'next' || txt === 'next page' || txt === 'next >' || txt === '>>' || txt === 'more') {
        nextPageUrl = resolveUrl(a.getAttribute('href'));
        break;
      }
    }
  }

  // --- Main content element ---
  var selectors = [
    'article', '[role="article"]', 'main', '[role="main"]',
    '.post-content', '.article-body', '.entry-content', '.article-content',
    '.post-body', '.story-body', '.content-body', '#article-body',
    '.td-post-content', '.post_content', '.article__body',
    // Gallery/Grid selectors
    '.gallery', '.photos', '.grid', '.listing', '.posts', '.items',
    '.product-list', '.video-list', '.thumbs', '.thumbnails'
  ];
  var main = null;
  for (var i = 0; i < selectors.length; i++) {
    var el = document.querySelector(selectors[i]);
    if (el && el.innerText.trim().length > 50) { main = el.cloneNode(true); break; }
  }
  if (!main) {
    main = document.body.cloneNode(true);
  }

  // --- Article/Content Links ---
  // Identify links to other content (articles, galleries, products)
  var articleLinks = [];
  var seenLinks = {};
  
  // Strategy 1: Links inside Heading tags (h1-h4)
  var headings = document.querySelectorAll('h1 a, h2 a, h3 a, h4 a, a h1, a h2, a h3, a h4');
  headings.forEach(function(el) {
    var a = el.tagName === 'A' ? el : el.querySelector('a');
    var h = el.tagName === 'A' ? el.parentElement : el;
    if (a) {
      var href = resolveUrl(a.getAttribute('href'));
      var txt = a.innerText.trim();
      if (href && txt.length > 5 && !seenLinks[href]) {
        seenLinks[href] = true;
        // Try to find an image nearby
        var img = '';
        var container = h.parentElement;
        if (container) {
          var i = container.querySelector('img');
          if (i) img = resolveUrl(i.getAttribute('src') || i.getAttribute('data-src'));
        }
        articleLinks.push({ url: href, title: txt, image: img });
      }
    }
  });

  // Strategy 2: Card/Grid items
  // Look for repeated structures containing Link + Image + Title
  var candidates = document.querySelectorAll('article, .card, .post, .item, .entry, .thumb, .product');
  candidates.forEach(function(el) {
    var a = el.querySelector('a');
    var img = el.querySelector('img');
    var titleEl = el.querySelector('h1, h2, h3, h4, .title, .name');
    
    if (a && (img || titleEl)) {
      var href = resolveUrl(a.getAttribute('href'));
      var txt = titleEl ? titleEl.innerText.trim() : (img ? (img.getAttribute('alt') || '') : a.innerText.trim());
      
      if (href && !seenLinks[href] && href !== window.location.href) {
        seenLinks[href] = true;
        var imgSrc = img ? resolveUrl(img.getAttribute('src') || img.getAttribute('data-src')) : '';
        articleLinks.push({ url: href, title: txt, image: imgSrc });
      }
    }
  });

  // Strip boilerplate from main content
  var removeSelectors = [
    'nav', 'header', 'footer', 'aside', 'script', 'style', 'noscript', 'svg',
    '.sidebar', '.nav', '.menu', '.footer', '.header',
    '.ad', '.ads', '.advertisement', '.social-share', '.comments', '.comment',
    '[role="navigation"]', '[role="banner"]', '[role="contentinfo"]',
    '[aria-hidden="true"]',
    // Related/recommended article sections (we extracted links, now remove UI)
    '.related', '.related-articles', '.related-stories', '.related-content',
    '.recommended', '.more-stories', '.trending', '.popular',
    '.recirculation', '.recirc', '.promo', '.newsletter',
    '[data-component="related-list"]', '[data-component="trending"]',
    '.article-footer', '.story-footer', '.duet--article--article-body-component-container:last-child',
    // Paywall / subscription / settings UI
    '.paywall', '.paywall-overlay', '.subscription-prompt', '.gate',
    '.article-settings', '.font-settings', '.display-settings',
    '.story-tools', '.article-tools', '.tools-bar',
    '[data-paywall]', '.metered-content-wall', '.pw-widget',
    // Author bio sections
    '.author-bio', '.author-info', '.byline-bio', '.contributor-bio',
    '.article-author-bio', '.writer-bio',
    // BBC-specific promotional sections
    '[data-component="links-block"]', '[data-component="topic-list"]',
    '[data-component="see-alsos"]', '[data-component="tag-list"]',
    '.ssrcss-1mrs5ns-PromoLink', '.ssrcss-1h3bnil-StyledLink',
    '[data-testid="promo"]', '[data-testid="related-content"]',
    // Generic promo containers
    '.promo-group', '.content-promo', '.story-promo',
    '.module--promo', '.block-link', '.faux-block-link'
  ];
  var remove = main.querySelectorAll(removeSelectors.join(', '));
  for (var r = 0; r < remove.length; r++) remove[r].remove();

  // --- Convert to markdown ---
  function toMarkdown(node) {
    if (!node) return '';
    
    // Helper to process children recursively
    function processChildren(n) {
      var res = '';
      var children = n.childNodes;
      for (var i = 0; i < children.length; i++) {
        res += toMarkdown(children[i]);
      }
      return res;
    }

    if (node.nodeType === 3) { // Text node
      var txt = node.textContent;
      // Collapse whitespace but preserve single spaces
      return txt.replace(/\s+/g, ' ');
    } 
    
    if (node.nodeType === 1) { // Element node
      var tag = node.tagName.toLowerCase();
      
      // Skip hidden/irrelevant
      if (tag === 'script' || tag === 'style' || tag === 'noscript' || tag === 'svg' ||
          tag === 'nav' || tag === 'aside' || tag === 'footer' || tag === 'header' ||
          tag === 'form' || tag === 'button') return '';
          
      if (node.getAttribute('aria-hidden') === 'true') return '';
      
      if (tag === 'br') return '\n';
      if (tag === 'hr') return '\n---\n';
      
      // Images
      if (tag === 'img') {
        var src = bestSrc(node);
        var alt = node.getAttribute('alt') || '';
        // Skip tiny icons or data URIs
        if (!src || src.startsWith('data:') || src.length < 10) return '';
        // Also skip tracking pixels
        if (src.indexOf('pixel') !== -1 || src.indexOf('spacer') !== -1 || src.indexOf('tracking') !== -1) return '';
        return '![' + alt + '](' + src + ')';
      }

      var inner = processChildren(node);
      
      // Block elements
      if (tag === 'h1') return '\n\n# ' + inner.trim() + '\n\n';
      if (tag === 'h2') return '\n\n## ' + inner.trim() + '\n\n';
      if (tag === 'h3') return '\n\n### ' + inner.trim() + '\n\n';
      if (tag === 'h4') return '\n\n#### ' + inner.trim() + '\n\n';
      if (tag === 'h5' || tag === 'h6') return '\n\n##### ' + inner.trim() + '\n\n';
      
      if (tag === 'p' || tag === 'div' || tag === 'section' || tag === 'article') {
        var trimmed = inner.trim();
        if (!trimmed) return '';
        return '\n\n' + trimmed + '\n\n';
      }
      
      if (tag === 'blockquote') {
        return '\n\n> ' + inner.trim().replace(/\n/g, '\n> ') + '\n\n';
      }
      
      if (tag === 'ul' || tag === 'ol') {
        return '\n\n' + inner.trim() + '\n\n';
      }
      
      if (tag === 'li') {
        var trimmed = inner.trim();
        if (!trimmed) return '';
        var parent = node.parentNode;
        var prefix = (parent && parent.tagName.toLowerCase() === 'ol') ? '1. ' : '- ';
        return '\n' + prefix + trimmed;
      }
      
      if (tag === 'figure') {
        return '\n\n' + inner.trim() + '\n\n';
      }

      // Inline elements
      if (tag === 'a') {
        var href = node.getAttribute('href');
        var text = inner.trim();
        if (href && text) return '[' + text + '](' + href + ')';
        return text;
      }
      
      if (tag === 'strong' || tag === 'b') return '**' + inner + '**';
      if (tag === 'em' || tag === 'i') return '*' + inner + '*';
      if (tag === 'code') return '`' + inner + '`';
      if (tag === 'pre') return '\n```\n' + inner + '\n```\n';
      
      return inner;
    }
    return '';
  }

  var textContent = toMarkdown(main).replace(/\n{3,}/g, '\n\n').trim();

  // --- Image filtering helper ---
  function isContentImage(src) {
    if (!src) return false;
    var lower = src.toLowerCase();
    // Skip tracking pixels, spacer gifs, data URIs, tiny icons
    if (lower.indexOf('data:') === 0) return false;
    if (lower.indexOf('pixel') !== -1 || lower.indexOf('spacer') !== -1) return false;
    if (lower.indexOf('tracking') !== -1 || lower.indexOf('beacon') !== -1) return false;
    if (lower.indexOf('.svg') !== -1 && (lower.indexOf('icon') !== -1 || lower.indexOf('logo') !== -1)) return false;
    if (/\b1x1\b|\b1\.gif\b|\b1\.png\b/.test(lower)) return false;
    // Skip common ad/tracker patterns
    if (/doubleclick|googlesyndication|facebook\.com\/tr|analytics/.test(lower)) return false;
    return true;
  }

  function bestSrc(img) {
    // Try srcset for highest-resolution image first
    var srcset = img.getAttribute('srcset');
    if (srcset) {
      var parts = srcset.split(',').map(function(s) { return s.trim().split(/\s+/); });
      var best = null, bestW = 0;
      for (var p = 0; p < parts.length; p++) {
        var u = parts[p][0];
        var desc = parts[p][1] || '';
        var w = parseInt(desc) || 0;
        if (w > bestW || !best) { best = u; bestW = w; }
      }
      if (best && isContentImage(best)) return best;
    }
    // Standard src, then lazy-load attributes
    return img.getAttribute('src')
      || img.getAttribute('data-src')
      || img.getAttribute('data-lazy-src')
      || img.getAttribute('data-original')
      || img.getAttribute('data-full')
      || '';
  }

  // --- Images ---
  // Build a set of author/byline image URLs to exclude from the gallery
  var authorImageUrls = {};
  var _authorSels = [
    '.author img', '.byline img', '.contributor img', '.writer img',
    '[class*="author"] img', '[class*="byline"] img', '[class*="writer"] img',
    '[rel="author"] img', '.post-author img', '.article-author img',
    '.author-info img', '.author-bio img', '.author-card img',
    '.c-entry-author img', '.c-byline img',
    'figure[class*="author"] img', 'div[class*="avatar"] img',
    'a[href*="/authors/"] img', 'a[href*="/staff/"] img',
  ];
  _authorSels.forEach(function(sel) {
    try {
      document.querySelectorAll(sel).forEach(function(img) {
        var s = img.src || img.getAttribute('data-src') || '';
        if (s) authorImageUrls[s] = true;
      });
    } catch(e) { /* selector not supported */ }
  });

  var ogImage = meta('property', 'og:image');
  var images = [];
  if (ogImage && isContentImage(ogImage) && !authorImageUrls[ogImage]) images.push(ogImage);

  // Collect from main content area
  var imgs = main.querySelectorAll('img');
  for (var i = 0; i < imgs.length; i++) {
    var src = bestSrc(imgs[i]);
    if (!src || !isContentImage(src)) continue;
    // Skip images identified as author/byline photos
    if (authorImageUrls[src]) continue;
    var w = imgs[i].naturalWidth || parseInt(imgs[i].getAttribute('width') || '0', 10);
    var h = imgs[i].naturalHeight || parseInt(imgs[i].getAttribute('height') || '0', 10);
    if ((w > 0 && w < 80) || (h > 0 && h < 80)) continue;
    // Skip avatar/author images by class/alt attributes
    var cls = (imgs[i].getAttribute('class') || '').toLowerCase();
    var alt = (imgs[i].getAttribute('alt') || '').toLowerCase();
    if (cls.indexOf('avatar') !== -1 || cls.indexOf('author') !== -1 || cls.indexOf('byline') !== -1) continue;
    if (alt.indexOf('avatar') !== -1 || alt.indexOf('headshot') !== -1 || alt.indexOf('author') !== -1) continue;
    // Skip if a parent element is an author/byline container
    var parent = imgs[i].parentElement;
    var isAuthorChild = false;
    for (var d = 0; d < 4 && parent; d++) {
      var pc = (parent.getAttribute('class') || '').toLowerCase();
      if (pc.indexOf('author') !== -1 || pc.indexOf('byline') !== -1 || pc.indexOf('avatar') !== -1 || pc.indexOf('contributor') !== -1) {
        isAuthorChild = true; break;
      }
      parent = parent.parentElement;
    }
    if (isAuthorChild) continue;
    if (images.indexOf(src) === -1) images.push(src);
  }

  // Also check <a> tags linking directly to images (common gallery pattern)
  var galleryLinks = main.querySelectorAll('a[href]');
  for (var gl = 0; gl < galleryLinks.length; gl++) {
    var href = galleryLinks[gl].getAttribute('href') || '';
    if (/\.(jpe?g|png|gif|webp|avif|bmp)(\?|$)/i.test(href)) {
      if (isContentImage(href) && images.indexOf(href) === -1) {
        images.push(href);
      }
    }
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

  // --- JSON-LD Structured Data ---
  var jsonLd = [];
  var ldScripts = document.querySelectorAll('script[type="application/ld+json"]');
  for (var ld = 0; ld < ldScripts.length; ld++) {
    try {
      var parsed = JSON.parse(ldScripts[ld].textContent);
      if (Array.isArray(parsed)) {
        for (var p = 0; p < parsed.length; p++) jsonLd.push(parsed[p]);
      } else {
        jsonLd.push(parsed);
      }
    } catch(e) { /* ignore malformed JSON-LD */ }
  }

  // --- OpenGraph as structured map ---
  var openGraph = {};
  var ogMetas = document.querySelectorAll('meta[property^="og:"]');
  for (var og = 0; og < ogMetas.length; og++) {
    var prop = ogMetas[og].getAttribute('property');
    var cont = ogMetas[og].getAttribute('content') || '';
    if (prop && cont) openGraph[prop] = cont;
  }
  // Also capture article: and product: meta tags
  var extraMetas = document.querySelectorAll('meta[property^="article:"], meta[property^="product:"], meta[property^="music:"], meta[property^="video:"], meta[property^="book:"], meta[property^="profile:"]');
  for (var em = 0; em < extraMetas.length; em++) {
    var prop = extraMetas[em].getAttribute('property');
    var cont = extraMetas[em].getAttribute('content') || '';
    if (prop && cont) openGraph[prop] = cont;
  }

  // --- Microdata (itemscope/itemprop) ---
  var microdata = [];
  var itemScopes = document.querySelectorAll('[itemscope]');
  for (var is_ = 0; is_ < Math.min(itemScopes.length, 20); is_++) {
    var item = itemScopes[is_];
    var itemType = item.getAttribute('itemtype') || '';
    var props = {};
    var itemProps = item.querySelectorAll('[itemprop]');
    for (var ip = 0; ip < itemProps.length; ip++) {
      var propName = itemProps[ip].getAttribute('itemprop');
      var propValue = itemProps[ip].getAttribute('content')
        || itemProps[ip].getAttribute('href')
        || itemProps[ip].getAttribute('src')
        || itemProps[ip].innerText.trim().substring(0, 500);
      if (propName && propValue) {
        if (props[propName]) {
          if (Array.isArray(props[propName])) props[propName].push(propValue);
          else props[propName] = [props[propName], propValue];
        } else {
          props[propName] = propValue;
        }
      }
    }
    if (itemType || Object.keys(props).length > 0) {
      microdata.push({ '@type': itemType, properties: props });
    }
  }

  // --- Collect all Schema.org types found ---
  var schemaTypes = [];
  for (var j = 0; j < jsonLd.length; j++) {
    if (jsonLd[j]['@type']) {
      var t = jsonLd[j]['@type'];
      if (Array.isArray(t)) { for (var tt = 0; tt < t.length; tt++) schemaTypes.push(t[tt]); }
      else schemaTypes.push(t);
    }
    // Check @graph items too
    if (jsonLd[j]['@graph']) {
      var graph = jsonLd[j]['@graph'];
      for (var g = 0; g < graph.length; g++) {
        if (graph[g]['@type']) {
          var gt = graph[g]['@type'];
          if (Array.isArray(gt)) { for (var gtt = 0; gtt < gt.length; gtt++) schemaTypes.push(gt[gtt]); }
          else schemaTypes.push(gt);
        }
      }
    }
  }
  for (var m = 0; m < microdata.length; m++) {
    if (microdata[m]['@type']) {
      var mt = microdata[m]['@type'];
      // Extract type name from full URL
      var typeName = mt.split('/').pop();
      if (typeName && schemaTypes.indexOf(typeName) === -1) schemaTypes.push(typeName);
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
    nextPageUrl: nextPageUrl,
    articleLinks: articleLinks,
    jsonLd: jsonLd,
    openGraph: openGraph,
    microdata: microdata,
    schemaTypes: schemaTypes,
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
      nextPageUrl: _resolveUrl(url, _nonEmpty(data['nextPageUrl'] as String?)),
      articleLinks: (data['articleLinks'] as List<dynamic>? ?? [])
          .map((e) {
            final map = e as Map<String, dynamic>;
            return ExtractedLink(
              url: (map['url'] as String? ?? '').trim(),
              title: (map['title'] as String? ?? '').trim(),
              image: _resolveUrl(url, map['image'] as String?),
            );
          })
          .where((e) => e.url.isNotEmpty)
          .toList(),
      jsonLd: (data['jsonLd'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList(),
      openGraph: (data['openGraph'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
      microdata: (data['microdata'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList(),
      schemaTypes: _stringList(data['schemaTypes']),
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
    if (ogImage != null &&
        ogImage.isNotEmpty &&
        !_isTrackingOrAdUrl(ogImage)) {
      final resolved = _resolveUrl(url, ogImage);
      if (resolved != null) images.add(resolved);
    }

    // Match <img> tags with src, data-src, data-lazy-src, data-original
    final imgTagRegex = RegExp(
      r'<img\b([^>]*)>',
      caseSensitive: false,
    );
    final attrRegex = RegExp(
      r'''(?:src|data-src|data-lazy-src|data-original|data-full)=["']([^"']+)["']''',
      caseSensitive: false,
    );
    final srcsetRegex = RegExp(
      r'''srcset=["']([^"']+)["']''',
      caseSensitive: false,
    );

    // Regex to detect images nested inside header, nav, or logo/brand
    // containers by examining the ~300 chars preceding the <img>.
    final logoContainerPattern = RegExp(
      r'<(?:header|nav)\b[^>]*>[^<]*$|'
      r'class="[^"]*(?:logo|brand|site-identity|masthead|site-header)[^"]*"[^>]*>[^<]*$',
      caseSensitive: false,
    );

    for (final m in imgTagRegex.allMatches(html)) {
      final attrs = m.group(1) ?? '';

      // Skip images inside header/nav/logo containers.
      final preceding = html.substring(
        (m.start - 300).clamp(0, html.length),
        m.start,
      );
      if (logoContainerPattern.hasMatch(preceding)) continue;

      // Try srcset first for highest resolution
      String? bestUrl;
      final srcsetMatch = srcsetRegex.firstMatch(attrs);
      if (srcsetMatch != null) {
        final srcsetVal = srcsetMatch.group(1) ?? '';
        bestUrl = _bestFromSrcset(srcsetVal);
      }

      // Fall back to src/data-src/etc.
      bestUrl ??= attrRegex.firstMatch(attrs)?.group(1);
      if (bestUrl == null || bestUrl.isEmpty) continue;
      if (_isTrackingOrAdUrl(bestUrl)) continue;
      if (_isLikelyLogo(bestUrl)) continue;

      final resolved = _resolveUrl(url, bestUrl);
      if (resolved != null && !images.contains(resolved)) {
        images.add(resolved);
      }
    }

    // <a> tags linking directly to images (gallery lightbox pattern)
    final linkToImageRegex = RegExp(
      r'''<a\b[^>]+href=["']([^"']+\.(?:jpe?g|png|gif|webp|avif|bmp))(?:\?[^"']*)?"[^>]*>''',
      caseSensitive: false,
    );
    for (final m in linkToImageRegex.allMatches(html)) {
      final href = m.group(1) ?? '';
      if (href.isNotEmpty && !_isTrackingOrAdUrl(href)) {
        final resolved = _resolveUrl(url, href);
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
    // Pass page-level og:image as fallback for articles without images.
    final resolvedOgImage = ogImage != null && ogImage.isNotEmpty
        ? _resolveUrl(url, ogImage)
        : null;
    final articleLinks = _extractArticleLinks(html, url, resolvedOgImage);

    // --- Pagination (next page) ---
    final nextPageUrl = _extractNextPageUrl(html, url);

    // --- Navigation links (categories, sections) ---
    final navigationLinks = _extractNavigationLinks(html, url);

    // --- JSON-LD from HTML ---
    final jsonLd = <Map<String, dynamic>>[];
    final ldPattern = RegExp(
      r'<script[^>]+type=["\x27]application/ld\+json["\x27][^>]*>(.*?)</script>',
      dotAll: true,
      caseSensitive: false,
    );
    for (final match in ldPattern.allMatches(html)) {
      try {
        final content = match.group(1)?.trim() ?? '';
        if (content.isEmpty) continue;
        final parsed = jsonDecode(content);
        if (parsed is List) {
          for (final item in parsed) {
            if (item is Map<String, dynamic>) jsonLd.add(item);
          }
        } else if (parsed is Map<String, dynamic>) {
          jsonLd.add(parsed);
        }
      } catch (_) { /* ignore malformed JSON-LD */ }
    }

    // --- OpenGraph from HTML ---
    final openGraphData = <String, String>{};
    final ogPattern = RegExp(
      r'<meta[^>]+property=["\x27]([^"\x27]+)["\x27][^>]+content=["\x27]([^"\x27]*)["\x27]',
      caseSensitive: false,
    );
    final ogPatternAlt = RegExp(
      r'<meta[^>]+content=["\x27]([^"\x27]*)["\x27][^>]+property=["\x27]([^"\x27]+)["\x27]',
      caseSensitive: false,
    );
    for (final match in ogPattern.allMatches(html)) {
      final prop = match.group(1) ?? '';
      final content = match.group(2) ?? '';
      if (prop.startsWith('og:') || prop.startsWith('article:') || prop.startsWith('product:')) {
        openGraphData[prop] = content;
      }
    }
    for (final match in ogPatternAlt.allMatches(html)) {
      final content = match.group(1) ?? '';
      final prop = match.group(2) ?? '';
      if (prop.startsWith('og:') || prop.startsWith('article:') || prop.startsWith('product:')) {
        openGraphData.putIfAbsent(prop, () => content);
      }
    }

    // --- Schema types from JSON-LD ---
    final schemaTypes = <String>[];
    for (final ld in jsonLd) {
      _collectSchemaTypes(ld, schemaTypes);
    }

    return WebExtraction(
      url: url,
      title: _decodeEntities(title).trim(),
      textContent: textContent,
      images: images,
      videos: videos,
      articleLinks: articleLinks,
      navigationLinks: navigationLinks,
      author: _nonEmpty(author),
      datePublished: published,
      siteName: _nonEmpty(ogSiteName),
      favicon: _resolveUrl(url, faviconMatch ?? faviconAlt),
      description: ogDesc != null ? _decodeEntities(ogDesc) : null,
      nextPageUrl: nextPageUrl,
      jsonLd: jsonLd,
      openGraph: openGraphData,
      microdata: const [],
      schemaTypes: schemaTypes,
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
    r'^create\s+(an?\s+)?account\b|^start\s+your\b|^try\s+it\b|'
    r'benefits\s+of\s+a(n?\s+)?\w+\s+sub|^discover\s+all\s+the\b|'
    r'^become\s+a\s+(member|subscriber)\b|^why\s+subscribe\b|'
    r'^unlock\s+(full|premium|exclusive)\b|^go\s+ad[\s-]?free\b)',
    caseSensitive: false,
  );

  /// Extracts article-like links from raw HTML.
  ///
  /// Scans for `<a>` tags inside article containers, cards, and common
  /// listing patterns. Deduplicates by URL and limits to 50 results.
  static List<ExtractedLink> _extractArticleLinks(
    String html,
    String baseUrl,
    String? pageOgImage,
  ) {
    // First pass: same-domain only (standard news/article sites).
    final links = _doExtractArticleLinks(
      html, baseUrl, pageOgImage,
      sameDomainOnly: true,
    );
    if (links.length >= 5) return links;

    // Few same-domain links — likely an aggregator (HN, Reddit, etc.).
    // Second pass: allow cross-domain article links.
    return _doExtractArticleLinks(
      html, baseUrl, pageOgImage,
      sameDomainOnly: false,
    );
  }

  /// Domains to skip when extracting cross-domain article links.
  static const _socialDomains = {
    'twitter.com', 'x.com', 'facebook.com', 'instagram.com',
    'linkedin.com', 'tiktok.com', 'pinterest.com', 'snapchat.com',
    'whatsapp.com', 't.me', 'discord.com', 'discord.gg',
    'accounts.google.com', 'play.google.com', 'apps.apple.com',
  };

  static List<ExtractedLink> _doExtractArticleLinks(
    String html,
    String baseUrl,
    String? pageOgImage, {
    required bool sameDomainOnly,
  }) {
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

      // Domain filtering.
      if (sameDomainOnly) {
        // Only keep links on the same domain (or closely related sub-domains).
        if (!linkUri.host.endsWith(baseHost) &&
            !baseHost.endsWith(linkUri.host)) {
          continue;
        }
      } else {
        // Cross-domain pass: skip social/platform domains.
        final host = linkUri.host;
        if (_socialDomains.any((d) => host == d || host.endsWith('.$d'))) {
          continue;
        }
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

      // Deduplicate by URL (strip tracking params) and title.
      final cleanUri = linkUri.replace(
        fragment: '',
        queryParameters:
            linkUri.queryParameters.isEmpty ? null : _stripTrackingParams(linkUri),
      );
      final canonical = cleanUri.toString();
      final titleKey = title.toLowerCase();
      if (seen.contains(canonical) || seen.contains(titleKey)) continue;
      seen.add(canonical);
      seen.add(titleKey);

      // Try to find an associated image. Modern sites use lazy loading
      // (data-src, srcset, data-original) so we check multiple attributes.
      // Only trust images found INSIDE the link element — context-based
      // searches (before/after the link) often pick up site logos, nav icons,
      // or unrelated images. Let _enrichLinksWithImages() fetch each article's
      // own og:image for better quality.
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

      // Don't fall back to page-level og:image or context-based search —
      // _enrichLinksWithImages() will fetch each article's own og:image.

      links.add(ExtractedLink(
        url: canonical,
        title: _decodeEntities(title),
        image: image,
      ));
    }

    return links;
  }

  /// Common tracking/analytics query parameters to strip during dedup.
  static const _trackingParams = {
    'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
    'ref', 'source', 'fbclid', 'gclid', 'ocid', 'ns_mchannel',
    'ns_source', 'ns_campaign', 'ns_linkname', 'ns_fee',
  };

  /// Strips tracking query parameters from a URI for deduplication.
  static Map<String, String>? _stripTrackingParams(Uri uri) {
    final cleaned = Map<String, String>.from(uri.queryParameters)
      ..removeWhere((k, _) => _trackingParams.contains(k.toLowerCase()));
    return cleaned.isEmpty ? null : cleaned;
  }

  // ---------------------------------------------------------------------------
  // HTML regex helpers
  // ---------------------------------------------------------------------------

  /// Detects if a URL likely points to a site logo, icon, or branding image
  /// rather than article-specific content.
  static bool _isLikelyLogo(String url) {
    final lower = url.toLowerCase();
    // Check path segments for common logo/icon patterns.
    final uri = Uri.tryParse(lower);
    final pathPart = uri?.path ?? lower;
    // Check the filename (last segment) for logo/icon keywords.
    final filename = pathPart.split('/').last;
    const logoKeywords = [
      'logo',
      'icon',
      'brand',
      'favicon',
      'badge',
      'site-image',
      'default-image',
      'default_image',
      'fallback',
      'avatar',
      'masthead',
      'site-identity',
    ];
    if (logoKeywords.any(filename.contains)) return true;
    // Also check full path for explicit logo/icon directories.
    const pathPatterns = [
      '/logo/',
      '/logos/',
      '/icons/',
      '/brand/',
      '/favicon/',
      '/branding/',
    ];
    if (pathPatterns.any(pathPart.contains)) return true;
    // SVG images are often logos/icons.
    if (pathPart.endsWith('.svg')) return true;
    // Domain + /logo or /brand pattern (e.g. cdn.example.com/logo-dark.png).
    if (uri != null && uri.host.isNotEmpty) {
      final domainBase = uri.host.split('.').first;
      if (pathPart.contains('/$domainBase/logo') ||
          pathPart.contains('/$domainBase/brand')) {
        return true;
      }
    }
    // Tiny dimension hints in URL (e.g. 16x16, 24x24, 32x32, 48x48, 64x64).
    if (RegExp(r'[\-_/](?:16|24|32|48|64)x(?:16|24|32|48|64)[\-_./]')
        .hasMatch(pathPart)) {
      return true;
    }
    return false;
  }

  /// Public API for checking if a URL is likely a site logo.
  static bool isLikelyLogoUrl(String url) => _isLikelyLogo(url);

  /// Returns `true` when [url] looks like a tracking pixel, ad beacon, or
  /// other non-content image.
  static bool _isTrackingOrAdUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.startsWith('data:')) return true;
    const patterns = [
      'pixel',
      'spacer',
      'tracking',
      'beacon',
      '1x1',
      '1.gif',
      '1.png',
      'doubleclick',
      'googlesyndication',
      'facebook.com/tr',
      'analytics',
      'ad-banner',
      'ad_banner',
      'advertisement',
    ];
    for (final p in patterns) {
      if (lower.contains(p)) return true;
    }
    return false;
  }

  /// Picks the highest-resolution URL from an HTML `srcset` attribute value.
  static String? _bestFromSrcset(String srcset) {
    if (srcset.isEmpty) return null;
    String? best;
    var bestW = 0;
    for (final entry in srcset.split(',')) {
      final parts = entry.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty) continue;
      final u = parts[0];
      final desc = parts.length > 1 ? parts[1] : '';
      final w = int.tryParse(desc.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (w > bestW || best == null) {
        best = u;
        bestW = w;
      }
    }
    return (best != null && !best.startsWith('data:')) ? best : null;
  }

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
            !val.contains('blank.') &&
            !val.contains('placeholder') &&
            !val.contains('loading.') &&
            !val.contains('grey-placeholder') &&
            !val.contains('lazy-load') &&
            !_isLikelyLogo(val)) {
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

  /// Extracts the main article text from raw HTML using DOM parsing.
  ///
  /// Uses [package:html] for proper DOM traversal instead of regex, which
  /// eliminates CSS/script content leaking into the extracted text.
  static String _extractMainText(String html) {
    final document = html_parser.parse(html);

    // Tags whose entire subtree should be removed (not just the tag itself).
    const stripTags = {
      'script', 'style', 'noscript', 'nav', 'header', 'footer', 'aside',
      'svg', 'form', 'iframe', 'button', 'select', 'fieldset', 'input',
      'label', 'template', 'dialog', 'menu', 'menuitem',
    };

    // ARIA roles whose subtree should be removed.
    const stripRoles = {
      'navigation', 'complementary', 'banner', 'contentinfo', 'search',
    };

    // Class/ID fragments indicating boilerplate.
    const boilerplatePatterns = [
      'toolbar', 'settings', 'menu', 'sidebar', 'share', 'social',
      'comment-form', 'login', 'signup', 'subscribe', 'paywall', 'ad-',
      'promo', 'cookie', 'consent', 'popup', 'modal', 'overlay', 'dropdown',
      'toggle', 'newsletter', 'sign-up', 'popular', 'trending', 'related',
      'widget', 'advertisement', 'social-share', 'share-bar', 'recirculation',
      'recommended', 'follow-topics', 'author-follow', 'article-footer',
      'story-footer', 'cta', 'callout', 'mw-editsection', 'mw-navigation',
      'mw-head', 'mw-panel', 'noprint', 'mw-jump-link', 'mw-indicators',
    ];

    bool isBoilerplate(dom.Element el) {
      final cls = el.className.toLowerCase();
      final id = (el.attributes['id'] ?? '').toLowerCase();
      final combined = '$cls $id';
      return boilerplatePatterns.any((p) => combined.contains(p));
    }

    // Remove unwanted elements from the DOM.
    void stripFromDom(dom.Element root) {
      // Collect elements to remove (can't modify while iterating).
      final toRemove = <dom.Element>[];
      for (final el in root.querySelectorAll('*')) {
        final tag = el.localName?.toLowerCase() ?? '';
        if (stripTags.contains(tag)) {
          toRemove.add(el);
          continue;
        }
        final role = el.attributes['role']?.toLowerCase() ?? '';
        if (stripRoles.contains(role)) {
          toRemove.add(el);
          continue;
        }
        if (el.attributes['aria-hidden'] == 'true') {
          toRemove.add(el);
          continue;
        }
        if (isBoilerplate(el)) {
          toRemove.add(el);
          continue;
        }
      }
      for (final el in toRemove) {
        el.remove();
      }
    }

    // Find the main content container.
    dom.Element? content;
    for (final selector in [
      'article',
      'main',
      '[role="main"]',
      '.post-content',
      '.article-body',
      '.entry-content',
      '.article-content',
    ]) {
      final candidates = document.querySelectorAll(selector);
      for (final c in candidates) {
        if ((c.text.trim()).length > 200) {
          content = c;
          break;
        }
      }
      if (content != null) break;
    }
    content ??= document.body ?? document.documentElement!;

    // Clean the content subtree.
    stripFromDom(content);

    // Convert DOM to markdown.
    final buffer = StringBuffer();
    _domToMarkdown(content, buffer);

    final text = buffer
        .toString()
        .replaceAll(RegExp(r'[^\S\n]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    return _cleanMarkdownContent(text);
  }

  /// Recursively converts a DOM subtree to markdown.
  static void _domToMarkdown(dom.Node node, StringBuffer buffer) {
    if (node is dom.Text) {
      buffer.write(node.text);
      return;
    }

    if (node is! dom.Element) {
      for (final child in node.nodes) {
        _domToMarkdown(child, buffer);
      }
      return;
    }

    final tag = node.localName?.toLowerCase() ?? '';

    switch (tag) {
      case 'br':
        buffer.write('\n');
      case 'hr':
        buffer.write('\n---\n');
      case 'p' || 'div' || 'section' || 'blockquote':
        buffer.write('\n\n');
        if (tag == 'blockquote') buffer.write('> ');
        for (final child in node.nodes) {
          _domToMarkdown(child, buffer);
        }
        buffer.write('\n\n');
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(tag.substring(1));
        buffer.write('\n\n${'#' * level} ');
        // Write heading text without child tags.
        buffer.write(node.text.trim());
        buffer.write('\n\n');
      case 'a':
        final href = node.attributes['href'] ?? '';
        final text = node.text.trim();
        if (text.isNotEmpty && href.isNotEmpty) {
          buffer.write('[$text]($href)');
        } else if (text.isNotEmpty) {
          buffer.write(text);
        }
      case 'img':
        final src = node.attributes['src'] ??
            node.attributes['data-src'] ??
            node.attributes['data-lazy-src'] ??
            '';
        final alt = node.attributes['alt'] ?? '';
        if (src.isNotEmpty) {
          buffer.write('\n![${alt.replaceAll('\n', ' ')}]($src)\n');
        }
      case 'li':
        buffer.write('\n- ');
        for (final child in node.nodes) {
          _domToMarkdown(child, buffer);
        }
      case 'ul' || 'ol':
        buffer.write('\n');
        for (final child in node.nodes) {
          _domToMarkdown(child, buffer);
        }
        buffer.write('\n');
      case 'pre' || 'code':
        if (tag == 'pre') {
          buffer.write('\n```\n');
          buffer.write(node.text);
          buffer.write('\n```\n');
        } else {
          buffer.write('`${node.text}`');
        }
      case 'strong' || 'b':
        buffer.write('**');
        for (final child in node.nodes) {
          _domToMarkdown(child, buffer);
        }
        buffer.write('**');
      case 'em' || 'i':
        buffer.write('_');
        for (final child in node.nodes) {
          _domToMarkdown(child, buffer);
        }
        buffer.write('_');
      case 'figure':
        // Process children (usually <img> + <figcaption>).
        for (final child in node.nodes) {
          _domToMarkdown(child, buffer);
        }
      case 'figcaption':
        buffer.write('\n_');
        buffer.write(node.text.trim());
        buffer.write('_\n');
      case 'table':
        // Simple table → plain text extraction.
        for (final row in node.querySelectorAll('tr')) {
          final cells = row
              .querySelectorAll('td, th')
              .map((c) => c.text.trim())
              .where((t) => t.isNotEmpty)
              .join(' | ');
          if (cells.isNotEmpty) buffer.write('\n$cells');
        }
        buffer.write('\n');
      default:
        // Inline or unknown — just recurse into children.
        for (final child in node.nodes) {
          _domToMarkdown(child, buffer);
        }
    }
  }

  /// Post-processes converted markdown to remove residual page-chrome text
  /// that slips through HTML stripping (font-size controls, theme selectors,
  /// paywall markers, etc.).
  static String _cleanMarkdownContent(String markdown) {
    final lines = markdown.split('\n');
    final cleaned = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();

      // Single-word UI control labels (font size, layout width, etc.)
      if (_uiControlWord.hasMatch(trimmed)) continue;

      // "Width *", "Size *", "Font *", etc.
      if (_uiSettingLine.hasMatch(trimmed)) continue;

      // Standalone colour names (theme selectors).
      if (_colourName.hasMatch(trimmed)) continue;

      // "Subscribe …", "Sign in …", "Log in …", "Create account …"
      if (_authActionLine.hasMatch(trimmed)) continue;

      // "Subscribers only", "Members only", "Premium content"
      if (_accessGateLine.hasMatch(trimmed)) continue;

      // Wikipedia / wiki CMS edit links and navigation tabs.
      if (_wikiEditLink.hasMatch(trimmed)) continue;
      if (_wikiNavTab.hasMatch(trimmed)) continue;
      if (trimmed.contains('Birthday mode') ||
          trimmed.contains('Baby Globe')) {
        continue;
      }

      cleaned.add(line);
    }

    return cleaned
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Single-word lines matching common UI controls.
  static final _uiControlWord = RegExp(
    r'^(Small|Standard|Large|Medium|Wide|Narrow|Compact|Default|Normal|'
    r'Expanded|Collapsed|On|Off|Enabled|Disabled|Auto)\s*\*?\s*$',
  );

  /// Lines like "Width *", "Size *", "Font *", etc.
  static final _uiSettingLine = RegExp(
    r'^(Width|Height|Size|Color|Theme|Font|Layout|View|Display|Spacing|'
    r'Appearance|Mode|Style|Contrast)\s*\*?\s*$',
  );

  /// Standalone colour names often used as theme selectors.
  static final _colourName = RegExp(
    r'^(Orange|Blue|Green|Red|Dark|Light|White|Black|Gray|Grey|Purple|'
    r'Yellow|Cyan|Teal|Amber|Indigo)\s*$',
  );

  /// Auth / subscription action lines.
  static final _authActionLine = RegExp(
    r'^(Subscribe|Sign\s*in|Log\s*in|Create\s+account|Register|Join)',
    caseSensitive: false,
  );

  /// Paywall / access gate lines (with optional bullet prefix).
  static final _accessGateLine = RegExp(
    r'^[\s\u00B7\u2022•·\-*]*\s*'
    r'(Subscribers?\s+only|Members?\s+only|Premium\s+content|'
    r'Exclusive\s+content|Paid\s+content)\s*$',
    caseSensitive: false,
  );

  /// Wikipedia / wiki CMS edit links (e.g. `"edit"`, `"[edit]"`).
  static final _wikiEditLink = RegExp(
    r'^\[?\s*edit\s*\]?\s*$',
    caseSensitive: false,
  );

  /// Wikipedia navigation tabs (Article, Talk, Read, View source, etc.).
  static final _wikiNavTab = RegExp(
    r'^(Article|Talk|Read|View\s+source|View\s+history)\s*$',
    caseSensitive: false,
  );

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

  // ---------------------------------------------------------------------------
  // Pagination detection
  // ---------------------------------------------------------------------------

  /// Detects the URL of the next page for paginated content.
  ///
  /// Checks (in order of priority):
  /// 1. `<link rel="next">` — standards-based pagination hint
  /// 2. `<a rel="next">` — explicit next-page links
  /// 3. Common "Next" link patterns in pagination controls
  static String? _extractNextPageUrl(String html, String baseUrl) {
    // 1. <link rel="next" href="...">
    final linkRelNext = RegExp(
      r'''<link[^>]+rel=["']next["'][^>]+href=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    // Also try reversed attribute order: href before rel
    final linkRelNextAlt = linkRelNext ?? RegExp(
      r'''<link[^>]+href=["']([^"']+)["'][^>]+rel=["']next["']''',
      caseSensitive: false,
    ).firstMatch(html);
    if (linkRelNextAlt != null) {
      final href = linkRelNextAlt.group(1);
      if (href != null && href.isNotEmpty) {
        return _resolveUrl(baseUrl, href);
      }
    }

    // 2. <a rel="next" href="...">
    final aRelNext = RegExp(
      r'''<a[^>]+rel=["']next["'][^>]+href=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    final aRelNextAlt = aRelNext ?? RegExp(
      r'''<a[^>]+href=["']([^"']+)["'][^>]+rel=["']next["']''',
      caseSensitive: false,
    ).firstMatch(html);
    if (aRelNextAlt != null) {
      final href = aRelNextAlt.group(1);
      if (href != null && href.isNotEmpty) {
        return _resolveUrl(baseUrl, href);
      }
    }

    // 3. Common pagination link patterns: links with text like
    //    "Next", "Next Page", "Older", "→", "»"
    final nextPatterns = RegExp(
      r'''<a[^>]+href=["']([^"']+)["'][^>]*>\s*'''
      r'(?:Next(?:\s+Page)?|Older(?:\s+Posts?)?|›|→|»|&raquo;|&#8250;|&gt;)'
      r'\s*</a>',
      caseSensitive: false,
    );
    final nextMatch = nextPatterns.firstMatch(html);
    if (nextMatch != null) {
      final href = nextMatch.group(1);
      if (href != null && href.isNotEmpty) {
        return _resolveUrl(baseUrl, href);
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Navigation link extraction
  // ---------------------------------------------------------------------------

  /// Extracts navigation links from the page.
  ///
  /// These are category, section, and related links from nav elements
  /// that might help the user discover more content on the same site.
  /// Limited to same-domain links.
  static List<ExtractedLink> _extractNavigationLinks(
    String html,
    String baseUrl,
  ) {
    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null) return const [];
    final baseHost = baseUri.host;

    // Extract links from <nav> elements and common nav containers.
    final navRegex = RegExp(
      r'<(?:nav|ul[^>]+class=["\x27][^"\x27]*(?:nav|menu|categories|sections)[^"\x27]*["\x27])[^>]*>(.*?)</(?:nav|ul)>',
      caseSensitive: false,
      dotAll: true,
    );

    final linkRegex = RegExp(
      r'<a\s[^>]*href=["' "'" r']([^"' "'" r']+)["' "'" r'][^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    );

    final seen = <String>{};
    final links = <ExtractedLink>[];

    for (final navMatch in navRegex.allMatches(html)) {
      if (links.length >= 20) break;

      final navContent = navMatch.group(1) ?? '';
      for (final linkMatch in linkRegex.allMatches(navContent)) {
        if (links.length >= 20) break;

        final rawHref = linkMatch.group(1) ?? '';
        final innerHtml = linkMatch.group(2) ?? '';
        if (rawHref.isEmpty) continue;

        final resolved = _resolveUrl(baseUrl, rawHref);
        if (resolved == null || resolved.isEmpty) continue;

        final linkUri = Uri.tryParse(resolved);
        if (linkUri == null) continue;

        // Same domain only.
        if (!linkUri.host.endsWith(baseHost) &&
            !baseHost.endsWith(linkUri.host)) {
          continue;
        }

        // Skip root/empty links and anchors.
        if (linkUri.path == '/' || linkUri.path.isEmpty) continue;
        if (rawHref.startsWith('#')) continue;

        final title = _decodeEntities(_stripTags(innerHtml)).trim();
        if (title.isEmpty || title.length < 2) continue;
        if (title.length > 100) continue;

        final canonical = linkUri.replace(fragment: '').toString();
        if (seen.contains(canonical) || canonical == baseUrl) continue;
        seen.add(canonical);

        links.add(ExtractedLink(url: canonical, title: title));
      }
    }

    return links;
  }

  // ---------------------------------------------------------------------------
  // Structured data helpers
  // ---------------------------------------------------------------------------

  /// Recursively collects Schema.org `@type` values from JSON-LD data.
  static void _collectSchemaTypes(
    Map<String, dynamic> data,
    List<String> types,
  ) {
    final type = data['@type'];
    if (type is String && !types.contains(type)) {
      types.add(type);
    } else if (type is List) {
      for (final t in type) {
        if (t is String && !types.contains(t)) types.add(t);
      }
    }
    // Check @graph
    final graph = data['@graph'];
    if (graph is List) {
      for (final item in graph) {
        if (item is Map<String, dynamic>) _collectSchemaTypes(item, types);
      }
    }
  }
}
