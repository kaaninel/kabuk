/// Reader Mode orchestration service — AI-enhanced article extraction pipeline.
///
/// Orchestrates the full "AI Reader Mode" flow:
/// 1. **Extract** — Pull structured content from a URL or WebView via
///    [WebExtractor].
/// 2. **Store** — Persist the article and its content blocks in the
///    knowledge store immediately so the UI can render basic content fast.
/// 3. **Enhance** — Optionally send the extracted text through the local LLM
///    to clean up navigation remnants, fix formatting, and improve readability.
///
/// The two-phase approach (store basic → enhance async) gives a responsive UX:
/// the user sees content immediately while the LLM polishes it in the
/// background.
library;

import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/knowledge/types/content_block.dart';
import 'package:kabuk/services/web_extractor.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Orchestrates the AI Reader Mode pipeline.
///
/// Flow: URL → extract → LLM enhance → store as Article + ContentBlocks.
/// Provides both immediate (basic extraction) and enhanced (LLM-processed)
/// modes for responsive UX — show basic content fast, enhance in background.
///
/// ```dart
/// final service = ref.read(readerModeServiceProvider);
/// final articleUri = await service.processUrl('https://example.com/article');
/// ```
class ReaderModeService {
  /// Creates a [ReaderModeService] backed by the given [store] and [llm].
  ReaderModeService({
    required KnowledgeStore store,
    required LlmService llm,
  })  : _store = store,
        _llm = llm;

  final KnowledgeStore _store;
  final LlmService _llm;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Process a URL into a reader-mode article.
  ///
  /// If [preExtracted] is supplied the extraction step is skipped and the
  /// provided [WebExtraction] is used directly. Otherwise [WebExtractor.fromUrl]
  /// fetches and parses the page via HTTP.
  ///
  /// Returns a [ReaderModeResult] describing the articles created. When the
  /// page is an index/listing page with discoverable article links, multiple
  /// articles are created (one per link) and the main page itself is skipped.
  Future<ReaderModeResult> processUrl(
    String url, {
    WebExtraction? preExtracted,
    String? feedSource,
  }) async {
    final extraction =
        preExtracted ??
        await WebExtractor.fromUrl(url).timeout(
          const Duration(seconds: 15),
          onTimeout: () => WebExtraction(url: url, title: '', textContent: ''),
        );
    return _pipeline(extraction, feedSource: feedSource);
  }

  /// Process a URL with a pre-loaded WebView (extracts via JS).
  ///
  /// Uses [WebExtractor.fromWebView] to run JavaScript against the live DOM,
  /// which typically yields higher-quality extraction than the HTTP fallback.
  ///
  /// Returns a [ReaderModeResult] describing the articles created.
  Future<ReaderModeResult> processFromWebView(
    WebViewController controller, {
    required String url,
    String? feedSource,
  }) async {
    final extraction = await WebExtractor.fromWebView(
      controller,
      url: url,
    );
    return _pipeline(extraction, feedSource: feedSource);
  }

  // -------------------------------------------------------------------------
  // Pipeline
  // -------------------------------------------------------------------------

  /// Runs the full extract → store → enhance pipeline.
  ///
  /// When the extracted page contains article links (index/listing page),
  /// creates multiple articles from those links instead of storing the
  /// index page itself as content.
  Future<ReaderModeResult> _pipeline(
    WebExtraction extraction, {
    String? feedSource,
  }) async {
    final articleLinks = extraction.articleLinks;

    // --- Multi-article path: index/listing page ---
    if (articleLinks.isNotEmpty) {
      final domain = _extractDomain(extraction.url);
      final siteName = extraction.siteName ?? domain;
      final createdUris = <String>[];

      // Check which URLs already exist to avoid duplicates.
      final existingArticles = await _store.listArticles(
        feedSource: feedSource,
        limit: 500,
      );
      final existingUrls = <String>{
        for (final a in existingArticles)
          if (a.url != null) a.url!,
      };

      // For links missing images, fetch og:image in parallel (max 10 at a time).
      final linksToProcess = articleLinks
          .where((l) => !existingUrls.contains(l.url))
          .toList();
      final enriched = await _enrichLinksWithImages(linksToProcess);

      for (final link in enriched) {
        try {
          final uri = await _store.createArticle(
            title: link.title,
            url: link.url,
            image: link.image,
            description: link.description,
            feedSource: feedSource ?? 'web:$domain',
            author: siteName,
            tags: ['web', if (domain.isNotEmpty) domain],
          );
          createdUris.add(uri);
        } on Object catch (e, st) {
          dev.log(
            'Failed to create article for ${link.url}',
            name: 'ReaderModeService',
            error: e,
            stackTrace: st,
          );
        }
      }

      // If we created multiple articles, return multi-article result.
      if (createdUris.isNotEmpty) {
        return ReaderModeResult(
          articleUris: createdUris,
          isMultiArticle: true,
        );
      }
      // Fall through to single-article path if no links were stored.
    }

    // --- Single-article path: regular content page ---

    // Step 1 — Store basic article immediately.
    final articleUri = await _storeArticle(extraction, feedSource: feedSource);

    // Step 2 — Create content blocks from the extracted markdown.
    final blockUris = await _createContentBlocks(
      articleUri,
      extraction.textContent,
      extraction.images,
      extraction.videos,
    );

    // Step 3 — LLM enhancement (best-effort, graceful degradation).
    await _enhanceWithLlm(articleUri, extraction.textContent, blockUris);

    return ReaderModeResult(
      articleUris: [articleUri],
      isMultiArticle: false,
    );
  }

  // -------------------------------------------------------------------------
  // Step 1 — Store Article
  // -------------------------------------------------------------------------

  /// Creates an Article entity in the knowledge store from [extraction].
  Future<String> _storeArticle(
    WebExtraction extraction, {
    String? feedSource,
  }) {
    final domain = _extractDomain(extraction.url);
    final summary = extraction.textContent.length > 500
        ? extraction.textContent.substring(0, 500)
        : extraction.textContent;

    return _store.createArticle(
      title: extraction.title,
      description: summary,
      url: extraction.url,
      author: extraction.author,
      image: extraction.images.firstOrNull,
      feedSource: feedSource ?? 'web:$domain',
      datePublished: extraction.datePublished,
      tags: ['web', if (domain.isNotEmpty) domain],
      galleryImages: extraction.images,
    );
  }

  // -------------------------------------------------------------------------
  // Step 2 — Content Blocks
  // -------------------------------------------------------------------------

  /// Parses [markdown] into content blocks and stores them under
  /// [parentDocument].
  ///
  /// Returns the list of created block URIs (in order).
  Future<List<String>> _createContentBlocks(
    String parentDocument,
    String markdown,
    List<String> images,
    List<String> videos,
  ) async {
    final blocks = _parseMarkdownBlocks(markdown, images, videos);
    final uris = <String>[];

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final uri = await _store.createContentBlock(
        parentDocument: parentDocument,
        type: block.type,
        order: i,
        content: block.content,
        mediaUri: block.mediaUri,
        language: block.language,
        level: block.level,
      );
      uris.add(uri);
    }

    return uris;
  }

  // -------------------------------------------------------------------------
  // Step 3 — LLM Enhancement
  // -------------------------------------------------------------------------

  /// System prompt for the content-enhancement LLM call.
  static const _enhanceSystemPrompt =
      'You are a content processor. Clean up and improve the following web '
      'page content. Fix formatting, remove navigation/ad remnants, improve '
      'readability. Return the cleaned content as markdown.';

  /// Attempts to enhance article content using the LLM.
  ///
  /// On success, replaces the existing content blocks with blocks derived
  /// from the LLM-enhanced text. On failure the basic extraction is kept
  /// (graceful degradation).
  Future<void> _enhanceWithLlm(
    String articleUri,
    String rawText,
    List<String> existingBlockUris,
  ) async {
    if (rawText.trim().isEmpty) return;

    try {
      final response = await _llm.complete(
        LlmRequest(
          systemPrompt: _enhanceSystemPrompt,
          messages: [LlmMessage.user(rawText)],
          temperature: 0.3,
          maxTokens: 4096,
        ),
      );

      final enhanced = switch (response) {
        TextLlmResponse(:final content) => content,
        ToolCallsLlmResponse(:final content) => content,
        ErrorLlmResponse(:final message) => throw Exception(message),
      };

      if (enhanced == null || enhanced.trim().isEmpty) return;

      // Delete old blocks.
      for (final uri in existingBlockUris) {
        await _store.deleteContentBlock(uri);
      }

      // Re-create blocks from enhanced content (reuse original media lists).
      // We don't have a separate images/videos list from the LLM output so
      // we pass empty lists — the LLM output is purely textual.
      await _createContentBlocks(articleUri, enhanced, const [], const []);
    } on Object catch (e, st) {
      // Graceful degradation — keep the basic extraction.
      dev.log(
        'LLM enhancement failed, keeping basic extraction',
        name: 'ReaderModeService',
        error: e,
        stackTrace: st,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Markdown Parsing
  // -------------------------------------------------------------------------

  /// Lightweight regex-based markdown-to-block parser.
  ///
  /// Splits [markdown] into a list of [_ParsedBlock]s by detecting headings,
  /// blockquotes, fenced code blocks, image references, and plain text
  /// paragraphs. This is intentionally simple — a full markdown AST is not
  /// needed for block-level splitting.
  List<_ParsedBlock> _parseMarkdownBlocks(
    String markdown,
    List<String> images,
    List<String> videos,
  ) {
    final blocks = <_ParsedBlock>[];
    final lines = markdown.split('\n');

    final usedImages = <String>{};
    final usedVideos = <String>{};

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];

      // -- Fenced code block ---------------------------------------------------
      final codeMatch = _codeBlockStart.firstMatch(line);
      if (codeMatch != null) {
        final language = codeMatch.group(1);
        final buffer = StringBuffer();
        i++; // skip opening fence
        while (i < lines.length && !_codeBlockEnd.hasMatch(lines[i])) {
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.write(lines[i]);
          i++;
        }
        if (i < lines.length) i++; // skip closing fence
        blocks.add(_ParsedBlock(
          type: BlockType.code,
          content: buffer.toString(),
          language: language?.isNotEmpty == true ? language : null,
        ));
        continue;
      }

      // -- Heading -------------------------------------------------------------
      final headingMatch = _headingPattern.firstMatch(line);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        final text = headingMatch.group(2)!.trim();
        if (text.isNotEmpty) {
          blocks.add(_ParsedBlock(
            type: BlockType.heading,
            content: text,
            level: level.clamp(1, 3),
          ));
        }
        i++;
        continue;
      }

      // -- Blockquote ----------------------------------------------------------
      if (_quotePattern.hasMatch(line)) {
        final buffer = StringBuffer();
        while (i < lines.length && _quotePattern.hasMatch(lines[i])) {
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.write(lines[i].replaceFirst(_quotePattern, ''));
          i++;
        }
        blocks.add(_ParsedBlock(
          type: BlockType.quote,
          content: buffer.toString(),
        ));
        continue;
      }

      // -- Inline image reference (![alt](url)) --------------------------------
      final imgMatch = _imagePattern.firstMatch(line);
      if (imgMatch != null) {
        final imgUrl = imgMatch.group(2)!;
        final caption = imgMatch.group(1);
        blocks.add(_ParsedBlock(
          type: BlockType.image,
          mediaUri: imgUrl,
          content: caption?.isNotEmpty == true ? caption : null,
        ));
        usedImages.add(imgUrl);
        i++;
        continue;
      }

      // -- Horizontal rule (---, ***, ___) -------------------------------------
      if (_dividerPattern.hasMatch(line)) {
        blocks.add(const _ParsedBlock(type: BlockType.divider));
        i++;
        continue;
      }

      // -- Blank line — skip ---------------------------------------------------
      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // -- Default: text paragraph (accumulate consecutive non-empty lines) ----
      final buffer = StringBuffer();
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !_headingPattern.hasMatch(lines[i]) &&
          !_quotePattern.hasMatch(lines[i]) &&
          !_codeBlockStart.hasMatch(lines[i]) &&
          !_imagePattern.hasMatch(lines[i]) &&
          !_dividerPattern.hasMatch(lines[i])) {
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(lines[i]);
        i++;
      }
      if (buffer.isNotEmpty) {
        blocks.add(_ParsedBlock(
          type: BlockType.text,
          content: buffer.toString(),
        ));
      }
    }

    // -- Append remaining images/videos not referenced in the text ------------
    for (final url in images) {
      if (!usedImages.contains(url)) {
        blocks.add(_ParsedBlock(type: BlockType.image, mediaUri: url));
      }
    }
    for (final url in videos) {
      if (!usedVideos.contains(url)) {
        blocks.add(_ParsedBlock(type: BlockType.video, mediaUri: url));
      }
    }

    return blocks;
  }

  // -------------------------------------------------------------------------
  // Regex patterns
  // -------------------------------------------------------------------------

  /// Matches `# `, `## `, or `### ` heading lines.
  static final _headingPattern = RegExp(r'^(#{1,3})\s+(.+)$');

  /// Matches `> ` blockquote lines.
  static final _quotePattern = RegExp(r'^>\s?');

  /// Opening of a fenced code block: ``` or ```language.
  static final _codeBlockStart = RegExp(r'^```(\w*)$');

  /// Closing of a fenced code block: ```.
  static final _codeBlockEnd = RegExp(r'^```$');

  /// Markdown image syntax: `![alt](url)`.
  static final _imagePattern = RegExp(r'^!\[([^\]]*)\]\(([^)]+)\)$');

  /// Horizontal rule: `---`, `***`, or `___` (with optional spaces).
  static final _dividerPattern = RegExp(r'^\s*([-*_])\s*\1\s*\1\s*$');

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Extracts the domain (host) from a URL string.
  ///
  /// Returns an empty string if parsing fails.
  static String _extractDomain(String url) {
    try {
      return Uri.parse(url).host;
    } on Object {
      return '';
    }
  }

  /// Enriches [ExtractedLink] entries that lack images by fetching each
  /// article URL and extracting `og:image` from the HTML `<meta>` tags.
  ///
  /// Processes up to 10 links in parallel with a 5-second timeout per fetch.
  /// Links that already have images are returned unchanged.
  Future<List<ExtractedLink>> _enrichLinksWithImages(
    List<ExtractedLink> links,
  ) async {
    if (links.isEmpty) return links;

    final results = <ExtractedLink>[];
    // Process in batches of 10 for bounded concurrency.
    for (var i = 0; i < links.length; i += 10) {
      final batch = links.skip(i).take(10).toList();
      final futures = batch.map((link) async {
        if (link.image != null) return link;
        try {
          final response = await http
              .get(
                Uri.parse(link.url),
                headers: {
                  'User-Agent': 'Mozilla/5.0 (compatible; Kabuk/1.0)',
                },
              )
              .timeout(const Duration(seconds: 5));
          if (response.statusCode != 200) return link;

          final html = response.body;
          // Extract og:image and og:title for better quality.
          final ogImage = _extractMetaImage(html);
          final ogTitle = _extractMetaTitle(html);
          final ogDesc = _extractMetaDescription(html);

          // Use og:title if available (much cleaner than link text).
          final bestTitle = ogTitle ?? link.title;
          final bestDesc = link.description ?? ogDesc;
          final bestImage = ogImage != null
              ? WebExtractor.resolveUrl(link.url, ogImage)
              : link.image;

          if (ogImage != null || ogTitle != null || ogDesc != null) {
            return ExtractedLink(
              url: link.url,
              title: bestTitle,
              image: bestImage,
              description: bestDesc,
            );
          }
          return link;
        } on Object {
          return link;
        }
      });
      results.addAll(await Future.wait(futures));
    }
    return results;
  }

  /// Extracts `og:title` from HTML meta tags.
  static String? _extractMetaTitle(String html) {
    for (final prop in ['og:title', 'twitter:title']) {
      final m1 = RegExp(
        '(?:property|name)="$prop"[^>]+content="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(html);
      if (m1 != null) return _decodeEntities(m1.group(1)!);
      final m2 = RegExp(
        'content="([^"]+)"[^>]+(?:property|name)="$prop"',
        caseSensitive: false,
      ).firstMatch(html);
      if (m2 != null) return _decodeEntities(m2.group(1)!);
    }
    return null;
  }

  /// Extracts `og:image` or `twitter:image` from HTML meta tags.
  static String? _extractMetaImage(String html) {
    for (final prop in ['og:image', 'twitter:image', 'twitter:image:src']) {
      // property="og:image" content="..."
      final m1 = RegExp(
        'property="$prop"[^>]+content="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(html);
      if (m1 != null) return _decodeEntities(m1.group(1)!);

      // content="..." property="og:image"
      final m2 = RegExp(
        'content="([^"]+)"[^>]+property="$prop"',
        caseSensitive: false,
      ).firstMatch(html);
      if (m2 != null) return _decodeEntities(m2.group(1)!);

      // name= variant (twitter uses name instead of property)
      final m3 = RegExp(
        'name="$prop"[^>]+content="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(html);
      if (m3 != null) return _decodeEntities(m3.group(1)!);
    }
    return null;
  }

  /// Extracts meta description from HTML.
  static String? _extractMetaDescription(String html) {
    for (final prop in ['og:description', 'description']) {
      final m1 = RegExp(
        '(?:property|name)="$prop"[^>]+content="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(html);
      if (m1 != null) {
        final desc = _decodeEntities(m1.group(1)!);
        return desc.length > 500 ? desc.substring(0, 500) : desc;
      }
      final m2 = RegExp(
        'content="([^"]+)"[^>]+(?:property|name)="$prop"',
        caseSensitive: false,
      ).firstMatch(html);
      if (m2 != null) {
        final desc = _decodeEntities(m2.group(1)!);
        return desc.length > 500 ? desc.substring(0, 500) : desc;
      }
    }
    return null;
  }

  /// Decodes common HTML entities in a string.
  static String _decodeEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'");
  }
}

// ---------------------------------------------------------------------------
// Result model
// ---------------------------------------------------------------------------

/// Result of the reader mode processing pipeline.
///
/// When [isMultiArticle] is `true`, the source page was an index/listing
/// page and [articleUris] contains URIs for each discovered article.
/// When `false`, the page was a single content page and [articleUris]
/// contains exactly one URI.
class ReaderModeResult {
  /// Creates a [ReaderModeResult].
  const ReaderModeResult({
    required this.articleUris,
    required this.isMultiArticle,
  });

  /// URIs of the articles created in the knowledge store.
  final List<String> articleUris;

  /// Whether multiple articles were discovered from an index/listing page.
  final bool isMultiArticle;

  /// Convenience getter for the first (or only) article URI.
  String get primaryArticleUri => articleUris.first;
}

// ---------------------------------------------------------------------------
// Internal model for parsed blocks
// ---------------------------------------------------------------------------

/// A lightweight intermediate representation of a content block produced by
/// the markdown parser before it is persisted to the knowledge store.
class _ParsedBlock {
  const _ParsedBlock({
    required this.type,
    this.content,
    this.mediaUri,
    this.language,
    this.level,
  });

  /// The kind of block.
  final BlockType type;

  /// Text/markdown content (headings, paragraphs, quotes, code).
  final String? content;

  /// Media URI for image/video/audio blocks.
  final String? mediaUri;

  /// Programming language hint for code blocks.
  final String? language;

  /// Heading level (1–3) for heading blocks.
  final int? level;
}

// ---------------------------------------------------------------------------
// Riverpod Providers
// ---------------------------------------------------------------------------

/// Provider for the [ReaderModeService] instance.
///
/// Depends on [knowledgeStoreProvider] and [llmServiceProvider].
final readerModeServiceProvider = Provider<ReaderModeService>((ref) {
  return ReaderModeService(
    store: ref.read(knowledgeStoreProvider),
    llm: ref.read(llmServiceProvider),
  );
});

/// Process a URL through reader mode. Returns a [ReaderModeResult].
///
/// Usage:
/// ```dart
/// final result = await ref.read(processReaderModeProvider('https://...').future);
/// ```
final processReaderModeProvider =
    FutureProvider.family<ReaderModeResult, String>((ref, url) async {
  final service = ref.read(readerModeServiceProvider);
  return service.processUrl(url);
});
