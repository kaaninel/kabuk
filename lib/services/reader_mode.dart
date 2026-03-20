/// Reader Mode orchestration service — article extraction pipeline.
///
/// Orchestrates the full "Reader Mode" flow:
/// 1. **Extract** — Pull structured content from a URL or WebView via
///    [WebExtractor].
/// 2. **Store** — Persist the article and its content blocks in the
///    knowledge store so the UI can render the content.
///
/// Content is served as raw markdown extracted from the page — no LLM
/// modifications are applied to preserve the original content faithfully.
library;

import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/knowledge/types/content_block.dart';
import 'package:kabuk/knowledge/types/organization.dart';
import 'package:kabuk/knowledge/types/person.dart';
import 'package:kabuk/knowledge/types/place.dart';
import 'package:kabuk/knowledge/types/product.dart';
import 'package:kabuk/knowledge/types/webpage.dart';
import 'package:kabuk/services/semantic_extractor.dart';
import 'package:kabuk/services/web_extractor.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Orchestrates the Reader Mode pipeline.
///
/// Flow: URL → extract → store as Article + ContentBlocks.
/// Content is served as-is from the page without LLM modifications.
///
/// ```dart
/// final service = ref.read(readerModeServiceProvider);
/// final articleUri = await service.processUrl('https://example.com/article');
/// ```
class ReaderModeService {
  /// Creates a [ReaderModeService] backed by the given [store], [llm], and
  /// optional [semanticExtractor].
  ReaderModeService({
    required KnowledgeStore store,
    required LlmService llm,
    SemanticExtractorService? semanticExtractor,
  })  : _store = store,
        _llm = llm,
        _semanticExtractor =
            semanticExtractor ?? SemanticExtractorService(llm: llm);

  final KnowledgeStore _store;
  // ignore: unused_field
  final LlmService _llm; // Kept for API compat; future knowledge distillation.
  final SemanticExtractorService _semanticExtractor;

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
          const Duration(seconds: 30),
          onTimeout: () {
            debugPrint('[ReaderMode] ⏱ Timeout (30s) fetching $url');
            return WebExtraction(
              url: url,
              title: _titleFromUrlPath(url),
              textContent: '',
            );
          },
        );
    debugPrint('[ReaderMode] processUrl extraction done: '
        'title="${extraction.title}" '
        'textLen=${extraction.textContent.length} '
        'articleLinks=${extraction.articleLinks.length}');
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

  /// Fetch full content for an existing article and store content blocks
  /// under its URI.
  ///
  /// Used for lazy-loading article body when only title/description are
  /// available (e.g. stub articles parsed from index pages).
  /// Also extracts and stores gallery images found on the article page.
  Future<void> fetchContentForArticle(String articleUri, String url) async {
    final extraction = await WebExtractor.fromUrl(url).timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        debugPrint('[ReaderMode] ⏱ Timeout (30s) fetching article $url');
        return WebExtraction(
          url: url,
          title: _titleFromUrlPath(url),
          textContent: '',
        );
      },
    );

    if (extraction.textContent.isEmpty) return;

    // Create content blocks from the raw extracted markdown.
    await _createContentBlocks(
      articleUri,
      extraction.textContent,
      extraction.images,
      extraction.videos,
    );

    // Store gallery images if the article page had multiple images.
    final contentImages = _filterContentImages(extraction.images);
    if (contentImages.length > 1) {
      await _store.updateArticleGalleryImages(articleUri, contentImages);
    }
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
    // Generate a title from the URL path when the extractor returns empty.
    final effectiveTitle = extraction.title.isNotEmpty
        ? extraction.title
        : _titleFromUrlPath(extraction.url);
    if (effectiveTitle != extraction.title) {
      extraction = WebExtraction(
        url: extraction.url,
        title: effectiveTitle,
        textContent: extraction.textContent,
        images: extraction.images,
        videos: extraction.videos,
        articleLinks: extraction.articleLinks,
        navigationLinks: extraction.navigationLinks,
        author: extraction.author,
        datePublished: extraction.datePublished,
        siteName: extraction.siteName,
        favicon: extraction.favicon,
        description: extraction.description,
        nextPageUrl: extraction.nextPageUrl,
        jsonLd: extraction.jsonLd,
        openGraph: extraction.openGraph,
        microdata: extraction.microdata,
        schemaTypes: extraction.schemaTypes,
      );
    }

    dev.log(
      '[ReaderMode] Processing: ${extraction.url}, '
      'title="${extraction.title}", '
      'textLen=${extraction.textContent.length}',
      name: 'ReaderModeService',
    );
    debugPrint('[ReaderMode] _pipeline start: url=${extraction.url}, '
        'title="${extraction.title}", '
        'textLen=${extraction.textContent.length}, '
        'articleLinks=${extraction.articleLinks.length}, '
        'images=${extraction.images.length}');

    // Detect empty or error pages (e.g. 404) early.
    final title = extraction.title.trim();
    final isErrorPage =
        title.contains('404') ||
        title.contains('Not Found') ||
        title.contains('Page Not Found') ||
        title.contains('Error');
    if (isErrorPage && extraction.articleLinks.isEmpty) {
      debugPrint('[ReaderMode] Detected error page: title="$title"');
      // Still create a minimal article so the UI can show something.
      final domain = _extractDomain(extraction.url);
      final articleUri = await _store.createArticle(
        title: title.isNotEmpty ? title : 'Page not found',
        description: 'This page could not be loaded.',
        url: extraction.url,
        feedSource: feedSource ?? 'web:$domain',
        tags: ['web', if (domain.isNotEmpty) domain],
      );
      return ReaderModeResult(
        articleUris: [articleUri],
        isMultiArticle: false,
      );
    }

    final articleLinks = extraction.articleLinks;

    // Determine if this is an index/listing page or a single article.
    // An index page has many links but little body text. A single article
    // page has substantial text even if it links to related articles.
    final isLikelyIndex = articleLinks.isNotEmpty &&
        (extraction.textContent.length < 500 ||
            (articleLinks.length >= 8 &&
                extraction.textContent.length <
                    articleLinks.length * 200));

    debugPrint('[ReaderMode] articleLinks=${articleLinks.length}, '
        'textLen=${extraction.textContent.length}, '
        'isLikelyIndex=$isLikelyIndex');

    // --- Multi-article path: index/listing page ---
    if (isLikelyIndex) {
      debugPrint('[ReaderMode] Entering MULTI-ARTICLE path '
          '(${articleLinks.length} links)');
      final domain = _extractDomain(extraction.url);
      final siteName = extraction.siteName ?? domain;
      final createdUris = <String>[];

      // Check which URLs already exist to avoid duplicates.
      final existingArticles = await _store.listArticles(
        feedSource: feedSource,
        limit: 500,
      );
      final existingUrlToUri = <String, String>{
        for (final a in existingArticles)
          if (a.url != null) a.url!: a.uri,
      };

      // Collect URIs of already-cached articles that match extracted links.
      final existingMatchUris = <String>[];
      final linksToProcess = <ExtractedLink>[];
      final cachedNeedingImages = <_CachedImageFix>[];
      for (final link in articleLinks) {
        final cachedUri = existingUrlToUri[link.url];
        if (cachedUri != null) {
          existingMatchUris.add(cachedUri);
          // Check if the cached article has a logo-like image that needs fixing.
          final cached = existingArticles.firstWhere(
            (a) => a.url == link.url,
            orElse: () => existingArticles.first,
          );
          if (cached.url == link.url &&
              (cached.image == null ||
                  WebExtractor.isLikelyLogoUrl(cached.image!) ||
                  _isGenericOgImage(cached.image!, link.url))) {
            cachedNeedingImages.add(
              _CachedImageFix(uri: cachedUri, pageUrl: link.url),
            );
          }
        } else {
          linksToProcess.add(link);
        }
      }

      // For links missing images, fetch og:image in parallel (max 10 at a time).
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

      // Re-enrich cached articles that have logo-like or missing images.
      if (cachedNeedingImages.isNotEmpty) {
        _fixCachedImages(cachedNeedingImages);
      }

      // Return multi-article result with both new and cached article URIs.
      final allUris = [...createdUris, ...existingMatchUris];

      // Create or reuse a WebPage as container for the multi-article channel
      try {
        final existing = await _store.findWebPageByUrl(extraction.url);
        if (existing != null) {
          await _store.updateWebPage(
            existing.uri,
            name: extraction.siteName ?? domain,
            description: extraction.description,
          );
          for (final uri in allUris) {
            if (!existing.memberEntities.contains(uri)) {
              await _store.addWebPageMember(existing.uri, uri);
            }
          }
        } else {
          final webPageUri = await _store.createWebPage(
            name: extraction.siteName ?? domain,
            url: extraction.url,
            description: extraction.description,
            favicon: extraction.favicon,
          );
          await _store.mutate((ctx) async {
            await ctx.set(
              webPageUri,
              NS.kabukFeedSource,
              feedSource ?? 'web:$domain',
            );
          });
          for (final uri in allUris) {
            await _store.addWebPageMember(webPageUri, uri);
          }
        }
      } catch (e, st) {
        dev.log(
          'Failed to create WebPage for multi-article',
          name: 'ReaderModeService',
          error: e,
          stackTrace: st,
        );
      }

      if (allUris.isNotEmpty) {
        return ReaderModeResult(
          articleUris: allUris,
          isMultiArticle: true,
          nextPageUrl: extraction.nextPageUrl,
          navigationLinks: extraction.navigationLinks,
        );
      }
      // Fall through to single-article path if no links were stored.
    }

    // --- Single-article path: semantic extraction ---

    debugPrint('[ReaderMode] Single-article path: running semantic extraction '
        'on ${extraction.textContent.length} chars');

    // Step 1 — Run semantic extraction
    SemanticExtractionResult? semanticResult;
    try {
      semanticResult = await _semanticExtractor.extract(extraction);
    } catch (e, st) {
      debugPrint('[ReaderMode] Semantic extraction failed: $e');
      dev.log(
        'Semantic extraction failed, falling back',
        name: 'ReaderModeService',
        error: e,
        stackTrace: st,
      );
    }

    debugPrint('[ReaderMode] Semantic entities: '
        '${semanticResult?.entities.length ?? 0}');

    if (semanticResult != null && semanticResult.entities.isNotEmpty) {
      debugPrint('[ReaderMode] Storing semantic result '
          '(${semanticResult.entities.length} entities)');
      return _storeSemanticResult(
        semanticResult,
        feedSource: feedSource,
        extraction: extraction,
      );
    }

    // Fallback: original article-only path
    debugPrint('[ReaderMode] Fallback: storing as plain article');
    final articleUri = await _storeArticle(extraction, feedSource: feedSource);
    await _createContentBlocks(
      articleUri,
      extraction.textContent,
      extraction.images,
      extraction.videos,
    );

    // Always create WebPage container for web content
    final domain = _extractDomain(extraction.url);
    if (domain.isNotEmpty) {
      try {
        final existingWp = await _store.findWebPageByUrl(extraction.url);
        if (existingWp == null) {
          final wpUri = await _store.createWebPage(
            url: extraction.url,
            name: extraction.title.isNotEmpty ? extraction.title : domain,
            description: extraction.description,
          );
          await _store.mutate((ctx) async {
            await ctx.set(
              wpUri,
              NS.kabukFeedSource,
              feedSource ?? 'web:$domain',
            );
          });
          await _store.addWebPageMember(wpUri, articleUri);
        } else {
          await _store.addWebPageMember(existingWp.uri, articleUri);
        }
      } catch (e, st) {
        dev.log(
          'Failed to create WebPage for fallback article',
          name: 'ReaderModeService',
          error: e,
          stackTrace: st,
        );
      }
    }

    return ReaderModeResult(
      articleUris: [articleUri],
      isMultiArticle: false,
      nextPageUrl: extraction.nextPageUrl,
      navigationLinks: extraction.navigationLinks,
    );
  }

  // -------------------------------------------------------------------------
  // Semantic Entity Storage
  // -------------------------------------------------------------------------

  /// Stores all semantic entities from a [SemanticExtractionResult] in the
  /// knowledge store. Creates proper entity types and links them together.
  Future<ReaderModeResult> _storeSemanticResult(
    SemanticExtractionResult result, {
    String? feedSource,
    required WebExtraction extraction,
  }) async {
    final allUris = <String>[];
    final entityUriMap = <int, String>{}; // index → URI for relationship linking
    final domain = _extractDomain(result.sourceUrl);

    // Collect image URLs from Person entities so they can be excluded from
    // article galleries (prevents author headshots in image galleries).
    final personImageUrls = <String>{};
    for (final entity in result.entities) {
      if (entity.type == 'Person') {
        final p = entity.properties;
        final image = _str(p['image']) ?? _str(p['schema:image']);
        if (image != null) personImageUrls.add(image);
        final thumbnail =
            _str(p['thumbnailUrl']) ?? _str(p['schema:thumbnailUrl']);
        if (thumbnail != null) personImageUrls.add(thumbnail);
      }
    }

    // First pass: create all entities
    for (var i = 0; i < result.entities.length; i++) {
      final entity = result.entities[i];
      try {
        final uri = await _storeEntity(
          entity,
          result.sourceUrl,
          feedSource,
          domain,
          personImageUrls: personImageUrls,
        );
        debugPrint('[ReaderMode] Stored entity[$i] ${entity.type} '
            '"${entity.properties['name']}" → $uri');
        if (uri != null) {
          entityUriMap[i] = uri;
          allUris.add(uri);
        }
      } catch (e, st) {
        debugPrint('[ReaderMode] Failed to store ${entity.type}: $e');
        dev.log(
          'Failed to store ${entity.type} entity',
          name: 'ReaderModeService',
          error: e,
          stackTrace: st,
        );
      }
    }

    // Second pass: store entity relationships as RDF triples
    await _storeEntityRelationships(result.entities, entityUriMap);

    // Create content blocks for the primary entity (usually an Article)
    if (result.primaryEntityIndex != null) {
      final primaryUri = entityUriMap[result.primaryEntityIndex!];
      if (primaryUri != null) {
        if (result.markdownContent.isNotEmpty) {
          await _createContentBlocks(
            primaryUri,
            result.markdownContent,
            extraction.images,
            extraction.videos,
          );
        } else if (extraction.description?.isNotEmpty == true) {
          await _createContentBlocks(
            primaryUri,
            extraction.description!,
            [],
            [],
          );
        }
      }
    }

    // Create or reuse a WebPage entity as container, linking to all members
    debugPrint('[ReaderMode] Linking ${allUris.length} entities to WebPage '
        'for ${result.sourceUrl}');
    try {
      final existing = await _store.findWebPageByUrl(result.sourceUrl);
      if (existing != null) {
        await _store.updateWebPage(
          existing.uri,
          name: result.pageTitle ?? domain,
          description: extraction.description,
        );
        for (final uri in allUris) {
          if (!existing.memberEntities.contains(uri)) {
            await _store.addWebPageMember(existing.uri, uri);
          }
        }
        allUris.insert(0, existing.uri);
      } else {
        final webPageUri = await _store.createWebPage(
          name: result.pageTitle ?? domain,
          url: result.sourceUrl,
          description: extraction.description,
          image: extraction.images.firstOrNull,
          siteName: result.siteName,
          favicon: result.favicon,
        );
        await _store.mutate((ctx) async {
          await ctx.set(
            webPageUri,
            NS.kabukFeedSource,
            feedSource ?? 'web:$domain',
          );
        });
        for (final uri in allUris) {
          await _store.addWebPageMember(webPageUri, uri);
        }
        allUris.insert(0, webPageUri);
      }
    } catch (e, st) {
      dev.log(
        'Failed to create WebPage entity',
        name: 'ReaderModeService',
        error: e,
        stackTrace: st,
      );
    }

    // Ensure we have at least one article URI for backward compat
    final articleUris = allUris
        .where((u) => u.contains('Article/'))
        .toList();
    if (articleUris.isEmpty && allUris.isNotEmpty) {
      articleUris.add(allUris.first);
    }

    return ReaderModeResult(
      articleUris: articleUris.isEmpty ? allUris.take(1).toList() : articleUris,
      isMultiArticle: allUris.length > 1,
      nextPageUrl: extraction.nextPageUrl,
      navigationLinks: extraction.navigationLinks,
      allEntityUris: allUris,
    );
  }

  /// Maps `schema:*` predicate strings from [EntityRelationship] to full
  /// namespace URIs defined in [NS].
  static const _predicateToNs = <String, String>{
    'schema:author': NS.schemaAuthor,
    'schema:publisher': NS.schemaPublisher,
    'schema:brand': NS.schemaBrand,
    'schema:offers': NS.schemaOffers,
    'schema:location': NS.schemaLocation,
    'schema:worksFor': NS.schemaWorksFor,
    'schema:memberOf': NS.schemaMemberOf,
    'schema:organizer': NS.schemaOrganizer,
  };

  /// Stores cross-entity relationships as RDF triples.
  ///
  /// Iterates over every entity's [SemanticEntity.relationships] and writes a
  /// `(sourceUri, predicate, targetUri)` triple for each one where both source
  /// and target have been successfully stored.
  Future<void> _storeEntityRelationships(
    List<SemanticEntity> entities,
    Map<int, String> entityUriMap,
  ) async {
    for (var i = 0; i < entities.length; i++) {
      final entity = entities[i];
      final sourceUri = entityUriMap[i];
      if (sourceUri == null) continue;

      for (final rel in entity.relationships) {
        final targetUri = entityUriMap[rel.targetIndex];
        if (targetUri == null) continue;

        final predicateUri = _predicateToNs[rel.predicate];
        if (predicateUri == null) {
          dev.log(
            'Unknown relationship predicate: ${rel.predicate}',
            name: 'ReaderModeService',
          );
          continue;
        }

        try {
          await _store.mutate((ctx) async {
            await ctx.set(
              sourceUri,
              predicateUri,
              targetUri,
              objectType: ObjectType.uri,
            );
          });
        } catch (e, st) {
          dev.log(
            'Failed to store relationship '
            '${rel.predicate} from $sourceUri to $targetUri',
            name: 'ReaderModeService',
            error: e,
            stackTrace: st,
          );
        }
      }
    }
  }

  /// Stores a single [SemanticEntity] in the knowledge store.
  /// Returns the created entity URI, or null if the entity type is unsupported.
  Future<String?> _storeEntity(
    SemanticEntity entity,
    String sourceUrl,
    String? feedSource,
    String domain, {
    Set<String> personImageUrls = const {},
  }) async {
    final p = entity.properties;
    final name = (p['name'] ?? p['headline'] ?? '').toString();
    if (name.isEmpty && entity.type != 'ImageObject') return null;

    final String? uri;
    switch (entity.type) {
      case 'Article' ||
          'NewsArticle' ||
          'BlogPosting' ||
          'Report' ||
          'TechArticle':
        // Exclude person/author images from the article gallery.
        final gallery = personImageUrls.isEmpty
            ? _strList(p['images'])
            : _strList(p['images'])
                .where((url) => !personImageUrls.contains(url))
                .toList();
        uri = await _store.createArticle(
          title: name,
          description: _str(p['description']),
          url: _str(p['url']) ?? sourceUrl,
          author: _str(p['author']),
          image: _str(p['image']),
          feedSource: feedSource ?? 'web:$domain',
          datePublished: _tryParseDate(_str(p['datePublished'])),
          tags: ['web', if (domain.isNotEmpty) domain],
          galleryImages: gallery,
        );

      case 'Person':
        uri = await _store.createOrMergePerson(
          name: name,
          description: _str(p['description']),
          email: _str(p['email']),
          telephone: _str(p['telephone']),
          givenName: _str(p['givenName']),
          familyName: _str(p['familyName']),
          confidence: entity.confidence,
        );

      case 'Product':
        uri = await _store.createOrMergeProduct(
          name: name,
          description: _str(p['description']),
          url: _str(p['url']) ?? sourceUrl,
          image: _str(p['image']),
          price: _str(p['price']),
          priceCurrency: _str(p['priceCurrency']),
          brand: _str(p['brand']),
          sku: _str(p['sku']),
          category: _str(p['category']),
          ratingValue: _tryDouble(p['ratingValue']),
          reviewCount: _tryInt(p['reviewCount']),
          availability: _str(p['availability']),
          extractedFrom: sourceUrl,
          confidence: entity.confidence,
          images: _strList(p['images']),
        );

      case 'Place' || 'LocalBusiness' || 'Restaurant' || 'Hotel':
        uri = await _store.createOrMergePlace(
          name: name,
          description: _str(p['description']),
          url: _str(p['url']),
          image: _str(p['image']),
          streetAddress: _str(p['streetAddress']),
          postalCode: _str(p['postalCode']),
          addressLocality: _str(p['addressLocality']),
          addressRegion: _str(p['addressRegion']),
          addressCountry: _str(p['addressCountry']),
          latitude: _tryDouble(p['latitude']),
          longitude: _tryDouble(p['longitude']),
          telephone: _str(p['telephone']),
          extractedFrom: sourceUrl,
          confidence: entity.confidence,
        );

      case 'Organization' || 'Corporation' || 'EducationalOrganization':
        uri = await _store.createOrMergeOrganization(
          name: name,
          description: _str(p['description']),
          url: _str(p['url']),
          logo: _str(p['logo']) ?? _str(p['publisherLogo']),
          image: _str(p['image']),
          email: _str(p['email']),
          telephone: _str(p['telephone']),
          extractedFrom: sourceUrl,
          confidence: entity.confidence,
          sameAs: _strList(p['sameAs']),
        );

      case 'ImageObject':
        // Images are stored as gallery on the article, not as separate entities
        uri = null;

      case 'WebPage' || 'CollectionPage' || 'WebSite':
        uri = await _store.createWebPage(
          name: name,
          url: _str(p['url']) ?? sourceUrl,
          description: _str(p['description']),
          image: _str(p['image']),
          siteName: _str(p['publisher']),
          inLanguage: _str(p['inLanguage']),
          confidence: entity.confidence,
        );
        await _store.mutate((ctx) async {
          await ctx.set(uri!, NS.kabukFeedSource, feedSource ?? 'web:$domain');
        });

      default:
        // For unknown types, create as Article (best generic representation)
        if (name.isNotEmpty) {
          uri = await _store.createArticle(
            title: name,
            description: _str(p['description']),
            url: _str(p['url']) ?? sourceUrl,
            feedSource: feedSource ?? 'web:$domain',
            image: _str(p['image']),
            tags: ['web', domain, entity.type.toLowerCase()],
          );
        } else {
          uri = null;
        }
    }

    // Store provenance metadata on the entity.
    if (uri != null) {
      final entityUri = uri;
      await _store.mutate((ctx) async {
        await ctx.set(entityUri, NS.kabukSemanticType, entity.type);
        await ctx.set(entityUri, NS.kabukExtractedFrom, sourceUrl);
      });
    }

    return uri;
  }

  static String? _str(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  static List<String> _strList(dynamic value) {
    if (value is List) return value.whereType<String>().toList();
    return const [];
  }

  static double? _tryDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _tryInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _tryParseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
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
    final effectiveFeedSource = feedSource ?? 'web:$domain';
    final summary = extraction.textContent.length > 500
        ? extraction.textContent.substring(0, 500)
        : extraction.textContent;

    dev.log(
      '[ReaderMode] Storing article: title="${extraction.title}", '
      'feedSource=$effectiveFeedSource',
      name: 'ReaderModeService',
    );

    return _store.createArticle(
      title: extraction.title,
      description: summary,
      url: extraction.url,
      author: extraction.author,
      image: extraction.images.firstOrNull,
      feedSource: effectiveFeedSource,
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
    // Filter out logo/icon images before distributing inline.
    final contentImages = images
        .where((url) => !WebExtractor.isLikelyLogoUrl(url))
        .toList();

    debugPrint(
      '[ReaderMode] _createContentBlocks: '
      '${contentImages.length} images (${images.length} raw), '
      '${videos.length} videos, '
      'markdown=${markdown.length} chars',
    );

    final blocks = _parseMarkdownBlocks(markdown, contentImages, videos);
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
  // Image Filtering
  // -------------------------------------------------------------------------

  /// Filters a list of image URLs to keep only content-relevant images.
  ///
  /// Removes logos, tracking pixels, avatars, thumbnails, and other
  /// non-content images. Also deduplicates by normalized URL.
  static List<String> _filterContentImages(List<String> images) {
    final seen = <String>{};
    return images.where((url) {
      if (WebExtractor.isLikelyLogoUrl(url)) return false;
      final lower = url.toLowerCase();
      if (lower.contains('pixel') || lower.contains('spacer')) return false;
      if (lower.contains('tracking') || lower.contains('beacon')) return false;
      if (lower.contains('1x1') || lower.contains('1.gif')) return false;
      if (lower.startsWith('data:')) return false;
      // Filter out avatar/author images (expanded patterns)
      if (lower.contains('avatar') || lower.contains('headshot')) return false;
      if (lower.contains('profile-photo') ||
          lower.contains('profile_photo') ||
          lower.contains('profilephoto')) {
        return false;
      }
      if (lower.contains('author') &&
          (lower.contains('photo') ||
              lower.contains('image') ||
              lower.contains('pic') ||
              lower.contains('img'))) {
        return false;
      }
      if ((lower.contains('writer') || lower.contains('contributor') || lower.contains('byline')) &&
          (lower.contains('photo') || lower.contains('image'))) {
        return false;
      }
      if (RegExp(r'/(staff|authors?|contributors?|writers?|people|team)/[^/]+\.(jpe?g|png|webp|avif)')
          .hasMatch(lower)) {
        return false;
      }
      if (RegExp(r'/(staff|authors?|contributors?|writers?)/[^/]+/(photo|image|avatar|headshot)')
          .hasMatch(lower)) {
        return false;
      }
      // Heuristic: very small square images (≤200px) indicated by URL dims
      if (_smallSquareImagePattern.hasMatch(lower)) return false;
      // Filter out social/share icons
      if (lower.contains('social') && lower.contains('icon')) return false;
      if (lower.contains('share-') || lower.contains('share_')) return false;
      // Filter out ad images
      if (lower.contains('/ad/') || lower.contains('/ads/')) return false;
      if (lower.contains('doubleclick') || lower.contains('googlesyndication')) {
        return false;
      }
      // Filter out promotional/banner/show images
      if (_promoPathPattern.hasMatch(lower)) return false;
      // Filter out tiny images (likely icons/buttons, dimension in URL)
      if (_tinyImagePattern.hasMatch(lower)) return false;
      // Dedup by normalized URL (strip query params for comparison)
      final normalized =
          Uri.tryParse(url)?.replace(query: '').toString() ?? url;
      if (seen.contains(normalized)) return false;
      seen.add(normalized);
      return true;
    }).toList();
  }

  /// Matches promotional, banner, sidebar, and non-article image paths.
  static final _promoPathPattern = RegExp(
    r'[/\-_](promo|banner|promoted|shows?|podcasts?|highlight|'
    r'featured|sidebar|widget|related|recommend|trending|popular|'
    r'footer|header-bg|masthead|hero-banner|placeholder|thumbnail-default|'
    r'newsletter|sponsor|partner|campaign)[/\-_.]',
    caseSensitive: false,
  );

  /// Matches tiny images likely to be icons (e.g. 16x16, 24x24, 32x32 in URL).
  static final _tinyImagePattern = RegExp(
    r'[/\-_](1[0-6]|2[0-4]|32)x\1[/\-_.]',
    caseSensitive: false,
  );

  /// Matches small square images (≤200px) that are likely profile
  /// photos / avatars based on dimension hints in the URL.
  static final _smallSquareImagePattern = RegExp(
    r'[/\-_=](([1-9]\d?|1\d{2}|200)x\2)[/\-_.]',
    caseSensitive: false,
  );

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

    // -- Distribute remaining images inline instead of appending at end -------
    // Collect unreferenced images (limit to 4 to avoid sidebar/promo junk).
    final unreferenced = <String>[];
    for (final url in images) {
      if (!usedImages.contains(url) && unreferenced.length < 4) {
        unreferenced.add(url);
      }
    }

    final textBlockCount =
        blocks.where((b) => b.type == BlockType.text).length;
    debugPrint(
      '[ReaderMode] _parseMarkdownBlocks: '
      '${blocks.length} blocks ($textBlockCount text), '
      '${usedImages.length} inline images, '
      '${unreferenced.length} unreferenced images to distribute',
    );

    // Insert after text/heading blocks at even intervals so images appear
    // inline with their surrounding content rather than pinned at the bottom.
    if (unreferenced.isNotEmpty) {
      final textBlockIndices = <int>[];
      for (var j = 0; j < blocks.length; j++) {
        if (blocks[j].type == BlockType.text ||
            blocks[j].type == BlockType.heading) {
          textBlockIndices.add(j);
        }
      }
      if (textBlockIndices.isNotEmpty) {
        final spacing = textBlockIndices.length > 1
            ? (textBlockIndices.length / unreferenced.length)
                .ceil()
                .clamp(1, textBlockIndices.length)
            : 1;
        var insertOffset = 0;
        for (var imgIdx = 0; imgIdx < unreferenced.length; imgIdx++) {
          final targetTextIdx =
              (imgIdx * spacing).clamp(0, textBlockIndices.length - 1);
          final insertAt =
              (textBlockIndices[targetTextIdx] + 1 + insertOffset)
                  .clamp(0, blocks.length);
          blocks.insert(
            insertAt,
            _ParsedBlock(type: BlockType.image, mediaUri: unreferenced[imgIdx]),
          );
          insertOffset++;
        }
      } else {
        // Fallback: no text blocks found, append at the end.
        for (final url in unreferenced) {
          blocks.add(_ParsedBlock(type: BlockType.image, mediaUri: url));
        }
      }
    }
    for (final url in videos) {
      if (!usedVideos.contains(url)) {
        blocks.add(_ParsedBlock(type: BlockType.video, mediaUri: url));
      }
    }

    // -- Strip trailing boilerplate blocks (CTAs, follow prompts, etc.) ------
    _stripTrailingBoilerplate(blocks);

    // -- Remove separator-only, whitespace-only, and boilerplate text blocks --
    blocks.removeWhere((b) {
      if (b.type != BlockType.text) return false;
      final trimmed = b.content?.trim() ?? '';
      if (trimmed.isEmpty) return true;
      // Remove blocks that are only punctuation/separator characters
      // (includes middle dot ·, bullet •, em-dash —, en-dash –, etc.)
      if (RegExp(r'^[\s\u00B7\u2022\u2013\u2014\u2027\-|/\\,;:.*]+$')
          .hasMatch(trimmed)) {
        return true;
      }
      // Remove very short single-word blocks that look like UI labels
      // (e.g. "Size", "Small", "Standard", "Large", "Wide", "Links")
      if (trimmed.length <= 15 && !trimmed.contains(' ') &&
          RegExp(r'^[A-Z][a-z]+\s*\*?$').hasMatch(trimmed)) {
        return true;
      }
      // Remove very short blocks that look like metadata fragments
      if (trimmed.length < 4 &&
          !RegExp(r'[a-zA-Z0-9]').hasMatch(trimmed)) {
        return true;
      }
      // Remove image credit / author bio lines
      if (_isImageCreditOrBio(trimmed)) return true;
      // Remove paywall/subscription prompts
      if (_isPaywallPrompt(trimmed)) return true;
      return false;
    });

    // -- Remove consecutive duplicate text blocks -----------------------------
    _removeDuplicateBlocks(blocks);

    return blocks;
  }

  /// Common CTA / boilerplate patterns found at the end of articles.
  static final _boilerplatePatterns = [
    RegExp(r'follow\s+topics?\s+and\s+authors?', caseSensitive: false),
    RegExp(r'receive\s+email\s+updates?', caseSensitive: false),
    RegExp(r'sign\s+up\s+for\s+(our|the)\s+newsletter', caseSensitive: false),
    RegExp(r'subscribe\s+to\s+(our|the)', caseSensitive: false),
    RegExp(r'more\s+like\s+this\s+in\s+your', caseSensitive: false),
    RegExp(r'personalized\s+homepage\s+feed', caseSensitive: false),
    RegExp(r'was\s+originally\s+published\s+on', caseSensitive: false),
    RegExp(r'correction.*this\s+(article|story)', caseSensitive: false),
    RegExp(r'read\s+more\s+at\s+', caseSensitive: false),
    RegExp(r'most\s+popular$', caseSensitive: false),
    RegExp(r'^related\s+(stories|articles|posts)$', caseSensitive: false),
    RegExp(r'discover\s+all\s+the\s+benefits', caseSensitive: false),
    RegExp(r'benefits\s+of\s+a(n)?\s+\w+\s+subscription',
        caseSensitive: false),
    RegExp(r'^become\s+a\s+(member|subscriber)', caseSensitive: false),
    RegExp(r'^(already\s+a\s+(subscriber|member))', caseSensitive: false),
  ];

  /// Removes trailing boilerplate blocks (from the end backwards) and any
  /// isolated short text blocks that match known CTA patterns.
  void _stripTrailingBoilerplate(List<_ParsedBlock> blocks) {
    // Remove from the end: once we hit real content, stop.
    while (blocks.isNotEmpty) {
      final last = blocks.last;
      if (last.type == BlockType.divider) {
        blocks.removeLast();
        continue;
      }
      if (last.type == BlockType.text &&
          last.content != null &&
          _isBoilerplate(last.content!)) {
        blocks.removeLast();
        continue;
      }
      break;
    }
    // Also remove any matching blocks earlier in the list.
    blocks.removeWhere(
      (b) =>
          b.type == BlockType.text &&
          b.content != null &&
          _isBoilerplate(b.content!),
    );
  }

  /// Returns true if the text matches known boilerplate patterns.
  bool _isBoilerplate(String text) {
    final trimmed = text.trim();
    // Very short bullet-point style items after a CTA heading aren't
    // boilerplate by themselves, but paragraphs matching CTA phrases are.
    return _boilerplatePatterns.any((p) => p.hasMatch(trimmed));
  }

  /// Returns true if a text block is an image credit or author bio line.
  ///
  /// Common patterns: "Image: Reuters", "Photo by John Doe",
  /// "Andrew J. Hawkins is a transportation editor with 10+ years..."
  static bool _isImageCreditOrBio(String text) {
    final trimmed = text.trim();
    // "Image: ..." or "Photo: ..." or "Photo by ..."
    if (RegExp(r'^(Image|Photo|Illustration|Credit|Source)\s*[:by]',
            caseSensitive: false)
        .hasMatch(trimmed)) {
      return true;
    }
    // Author bio: "X is a/an Y editor/reporter/writer/journalist..."
    if (RegExp(
            r'\b(is\s+(a|an|the)\s+\w+\s+(editor|reporter|writer|journalist|correspondent))',
            caseSensitive: false)
        .hasMatch(trimmed)) {
      return true;
    }
    // "Reporting by ..." or "Written by ..."
    if (RegExp(r'^(Reporting|Written|Edited|Photography)\s+by\b',
            caseSensitive: false)
        .hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  /// Returns true if a text block is a paywall or subscription prompt,
  /// or common site-specific noise (media caption placeholders, share
  /// buttons, standalone timestamps, etc.).
  static bool _isPaywallPrompt(String text) {
    final lower = text.trim().toLowerCase();
    if (lower == 'subscribers only' || lower == 'premium content') return true;
    if (lower == 'learn more' || lower == 'sign in') return true;
    if (lower == 'story text') return true;
    if (lower == 'share' || lower == 'copy link' || lower == 'save' ||
        lower == 'bookmark' || lower == 'print') {
      return true;
    }
    // BBC "Media caption," placeholder
    if (RegExp(r'^media\s+caption\s*[,.]?\s*$').hasMatch(lower)) return true;
    // "PublishedX hours ago" with missing space
    if (RegExp(r'^published\d').hasMatch(lower)) return true;
    // Standalone time: "6 hours ago"
    if (RegExp(r'^\d+\s+(hours?|minutes?|days?|mins?)\s+ago\s*$')
        .hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'(subscribe|sign\s+up|log\s*in)\s+(to|for)\s+(read|access|view|continue)',
            caseSensitive: false)
        .hasMatch(text)) {
      return true;
    }
    if (RegExp(r'(already\s+a\s+(subscriber|member)|create\s+an?\s+account)',
            caseSensitive: false)
        .hasMatch(text)) {
      return true;
    }
    return false;
  }

  /// Removes consecutive duplicate text blocks (same normalized content).
  static void _removeDuplicateBlocks(List<_ParsedBlock> blocks) {
    if (blocks.length < 2) return;
    final seen = <String>{};
    blocks.removeWhere((b) {
      if (b.type != BlockType.text || b.content == null) return false;
      final norm = b.content!.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (norm.length < 10) return false; // don't dedup very short blocks
      if (seen.contains(norm)) return true;
      seen.add(norm);
      return false;
    });
  }

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

  /// Generates a human-readable title from the URL path when the extractor
  /// returns an empty title.
  ///
  /// Picks the last meaningful path segment, replaces dashes/underscores with
  /// spaces, strips file extensions, and capitalises each word.
  static String _titleFromUrlPath(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final segments = uri.pathSegments
        .where((s) => s.isNotEmpty && !RegExp(r'^\d+$').hasMatch(s))
        .toList();
    if (segments.isEmpty) return uri.host.replaceFirst('www.', '');
    final last = segments.last
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\.\w+$'), ''); // remove file extensions
    // Capitalize first letter of each word
    return last
        .split(' ')
        .map(
          (w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}',
        )
        .join(' ');
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
        if (link.image != null && !WebExtractor.isLikelyLogoUrl(link.image!)) {
          return link;
        }
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
          final ogImage = extractMetaImage(html);
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
  ///
  /// Public so feed enrichment can reuse this without duplicating logic.
  static String? extractMetaImage(String html) {
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
        .replaceAll('&#x27;', "'")
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
  }

  /// Checks if an image URL is a generic site-wide og:image rather than
  /// an article-specific hero image.
  static bool _isGenericOgImage(String imageUrl, String articleUrl) {
    final imageUri = Uri.tryParse(imageUrl);
    final articleUri = Uri.tryParse(articleUrl);
    if (imageUri == null || articleUri == null) return false;

    // If the image path is very short (e.g. /logo.png, /og.png), it's generic.
    final segments = imageUri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.length <= 2) return true;

    // Check for common generic image filenames.
    final filename = segments.last.toLowerCase();
    const genericNames = [
      'og-image',
      'og_image',
      'social-share',
      'social_share',
      'default-og',
      'default_og',
      'share-image',
      'share_image',
      'site-image',
      'featured-default',
    ];
    return genericNames.any(filename.contains);
  }

  /// Fixes images for cached articles that have logo/generic images.
  ///
  /// Runs in the background (fire-and-forget) so it doesn't block UI.
  void _fixCachedImages(List<_CachedImageFix> items) {
    Future<void> run() async {
      for (var i = 0; i < items.length; i += 5) {
        final batch = items.skip(i).take(5).toList();
        final futures = batch.map((item) async {
          try {
            final response = await http
                .get(
                  Uri.parse(item.pageUrl),
                  headers: {
                    'User-Agent': 'Mozilla/5.0 (compatible; Kabuk/1.0)',
                  },
                )
                .timeout(const Duration(seconds: 5));
            if (response.statusCode != 200) return;

            final ogImage = extractMetaImage(response.body);
            if (ogImage != null && ogImage.isNotEmpty) {
              final resolved = WebExtractor.resolveUrl(item.pageUrl, ogImage);
              if (resolved != null &&
                  !WebExtractor.isLikelyLogoUrl(resolved)) {
                await _store.updateArticleImage(item.uri, resolved);
              }
            }
          } on Object {
            // Best-effort — failures are silently ignored.
          }
        });
        await Future.wait(futures);
      }
    }

    // Fire and forget.
    run();
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
    this.nextPageUrl,
    this.navigationLinks = const [],
    this.allEntityUris = const [],
  });

  /// URIs of the articles created in the knowledge store.
  final List<String> articleUris;

  /// Whether multiple articles were discovered from an index/listing page.
  final bool isMultiArticle;

  /// URL of the next page, if pagination was detected.
  final String? nextPageUrl;

  /// Navigation links for site navigation (categories, sections).
  final List<ExtractedLink> navigationLinks;

  /// All entity URIs created (articles, people, products, places, etc.).
  /// This is a superset of [articleUris] — includes all semantic entities.
  final List<String> allEntityUris;

  /// Convenience getter for the first (or only) article URI.
  String get primaryArticleUri => articleUris.first;
}

// ---------------------------------------------------------------------------
// Helper for cached image fixes
// ---------------------------------------------------------------------------

/// A cached article whose image needs to be re-fetched.
class _CachedImageFix {
  const _CachedImageFix({required this.uri, required this.pageUrl});

  /// URI of the article in the knowledge store.
  final String uri;

  /// URL of the article's web page to fetch og:image from.
  final String pageUrl;
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
  final llm = ref.read(llmServiceProvider);
  return ReaderModeService(
    store: ref.read(knowledgeStoreProvider),
    llm: llm,
    semanticExtractor: SemanticExtractorService(llm: llm),
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
