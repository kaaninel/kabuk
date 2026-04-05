/// Semantic extraction service — transforms raw web content into structured
/// semantic entities using LLM analysis and structured data from the page.
///
/// Takes a [WebExtraction] with its JSON-LD, OpenGraph, and microdata,
/// analyzes it with an LLM, and produces a list of [SemanticEntity] objects
/// ready to be stored in the knowledge base.
library;

import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/services/web_extractor.dart';

// =============================================================================
// Models
// =============================================================================

/// A semantic entity extracted from a web page.
///
/// Represents a typed object (Person, Product, Article, Place, Organization,
/// ImageObject, etc.) with its properties and relationships to other entities.
class SemanticEntity {
  /// Creates a [SemanticEntity] with the given [type], [properties],
  /// optional [relationships], and [confidence] score.
  const SemanticEntity({
    required this.type,
    required this.properties,
    this.relationships = const [],
    this.confidence = 1.0,
  });

  /// Schema.org type (e.g., 'Article', 'Person', 'Product', 'Place').
  final String type;

  /// Key-value properties of the entity.
  /// Keys are Schema.org property names (e.g., 'name', 'description', 'price').
  /// Values can be `String`, `num`, `bool`, `List<String>`, or `null`.
  final Map<String, dynamic> properties;

  /// Relationships to other entities in the same extraction result.
  /// Each relationship is (predicate, targetIndex) where targetIndex
  /// refers to another entity in the [SemanticExtractionResult.entities] list.
  final List<EntityRelationship> relationships;

  /// Confidence score (0.0 to 1.0) of this extraction.
  final double confidence;
}

/// A relationship between two semantic entities.
class EntityRelationship {
  /// Creates an [EntityRelationship] from [predicate] to a target entity
  /// at [targetIndex] in the parent result's entity list.
  const EntityRelationship({
    required this.predicate,
    required this.targetIndex,
  });

  /// The relationship predicate (e.g., 'author', 'publisher', 'offers').
  final String predicate;

  /// Index of the target entity in the [SemanticExtractionResult.entities] list.
  final int targetIndex;
}

/// Result of semantic extraction from a web page.
class SemanticExtractionResult {
  /// Creates a [SemanticExtractionResult] with all extracted data.
  const SemanticExtractionResult({
    required this.entities,
    required this.markdownContent,
    required this.sourceUrl,
    this.pageTitle,
    this.siteName,
    this.favicon,
    this.primaryEntityIndex,
  });

  /// All semantic entities extracted from the page.
  final List<SemanticEntity> entities;

  /// Clean markdown content of the page (body text).
  final String markdownContent;

  /// The source URL.
  final String sourceUrl;

  /// Page title.
  final String? pageTitle;

  /// Site name.
  final String? siteName;

  /// Favicon URL.
  final String? favicon;

  /// Index of the "main" entity (e.g., the primary Article or Product).
  /// Null if no primary entity was identified.
  final int? primaryEntityIndex;
}

// =============================================================================
// Service
// =============================================================================

/// Extracts semantic entities from web pages using structured data and LLM.
///
/// The extraction pipeline:
/// 1. Parse JSON-LD structured data (highest quality source)
/// 2. Parse OpenGraph metadata
/// 3. Parse microdata
/// 4. Use LLM to analyze content and identify additional entities
/// 5. Merge and deduplicate entities
/// 6. Establish relationships between entities
class SemanticExtractorService {
  /// Creates a [SemanticExtractorService] backed by the given [LlmService].
  SemanticExtractorService({required LlmService llm}) : _llm = llm;

  final LlmService _llm;

  /// Extract semantic entities from a [WebExtraction].
  Future<SemanticExtractionResult> extract(WebExtraction extraction) async {
    final entities = <SemanticEntity>[];

    // Step 1: Extract entities from JSON-LD (most structured source)
    final jsonLdEntities = _extractFromJsonLd(extraction.jsonLd);
    entities.addAll(jsonLdEntities);
    debugPrint('[SemanticExtractor] JSON-LD entities: ${jsonLdEntities.length} '
        '(${jsonLdEntities.map((e) => e.type).join(', ')})');

    // Step 2: Extract/enrich from OpenGraph
    final ogEntities =
        _extractFromOpenGraph(extraction.openGraph, extraction.url);
    debugPrint('[SemanticExtractor] OG entities: ${ogEntities.length} '
        '(${ogEntities.map((e) => e.type).join(', ')})');
    if (ogEntities.isNotEmpty) {
      final mainOg = ogEntities.first;
      // Add the main OG entity first.
      if (!_hasSimilarEntity(entities, mainOg)) {
        final mainIndex = entities.length;
        // If there's an author entity, resolve the relationship index.
        if (ogEntities.length > 1) {
          final authorEntity = ogEntities[1];
          if (!_hasSimilarEntity(entities, authorEntity)) {
            final authorIndex = mainIndex + 1;
            entities.add(SemanticEntity(
              type: mainOg.type,
              properties: mainOg.properties,
              relationships: [
                EntityRelationship(
                  predicate: 'schema:author',
                  targetIndex: authorIndex,
                ),
              ],
              confidence: mainOg.confidence,
            ));
            entities.add(authorEntity);
          } else {
            // Author already exists — find its index.
            final existingIdx = _findSimilarEntityIndex(entities, authorEntity);
            if (existingIdx != null) {
              entities.add(SemanticEntity(
                type: mainOg.type,
                properties: mainOg.properties,
                relationships: [
                  EntityRelationship(
                    predicate: 'schema:author',
                    targetIndex: existingIdx,
                  ),
                ],
                confidence: mainOg.confidence,
              ));
            } else {
              entities.add(mainOg);
            }
          }
        } else {
          entities.add(mainOg);
        }
      }
    }

    // Add remaining OG entities (e.g. Organization from og:site_name) that
    // were not already handled as the main entity or author.
    for (var i = 2; i < ogEntities.length; i++) {
      if (!_hasSimilarEntity(entities, ogEntities[i])) {
        entities.add(ogEntities[i]);
      }
    }

    // Step 3: Extract from microdata
    final microdataEntities = _extractFromMicrodata(extraction.microdata);
    debugPrint('[SemanticExtractor] Microdata entities: '
        '${microdataEntities.length}');
    for (final entity in microdataEntities) {
      if (!_hasSimilarEntity(entities, entity)) {
        entities.add(entity);
      }
    }

    // Step 4: Use LLM to analyze content and find additional entities
    // Only if we have meaningful content and the structured data was thin
    if (extraction.textContent.length > 100) {
      try {
        final llmEntities = await _extractWithLlm(extraction, entities);
        debugPrint('[SemanticExtractor] LLM entities: ${llmEntities.length} '
            '(${llmEntities.map((e) => e.type).join(', ')})');
        for (final entity in llmEntities) {
          if (!_hasSimilarEntity(entities, entity)) {
            entities.add(entity);
          }
        }
      } catch (e, st) {
        debugPrint('[SemanticExtractor] LLM extraction failed: $e');
        dev.log(
          'LLM semantic extraction failed',
          name: 'SemanticExtractor',
          error: e,
          stackTrace: st,
        );
        // Continue with what we have from structured data
      }
    }

    // Step 4b: Ensure Person/Organization entities exist from metadata.
    // When LLM is unavailable or the structured data only recorded author/
    // publisher as properties (not as standalone entities), create them now.
    _ensureMetadataEntities(entities, extraction);

    debugPrint('[SemanticExtractor] Total entities after all steps: '
        '${entities.length} '
        '(${entities.map((e) => '${e.type}:${e.properties['name']}').join(', ')})');

    // Step 5: Create a fallback entity only when the extraction had
    // meaningful content – otherwise leave entities empty so the caller
    // falls through to the simpler article-only path.
    if (entities.isEmpty && extraction.textContent.length > 200) {
      entities.add(_createFallbackEntity(extraction));
    }

    // Step 6: Add image entities for content images
    _addImageEntities(entities, extraction);

    // Step 7: Add link entities for discovered articles/pages
    _addLinkEntities(entities, extraction);

    // Find primary entity
    int? primaryIndex;
    for (var i = 0; i < entities.length; i++) {
      final e = entities[i];
      if (e.type == 'Article' ||
          e.type == 'Product' ||
          e.type == 'WebPage' ||
          e.type == 'Recipe' ||
          e.type == 'HowTo' ||
          e.type == 'NewsArticle' ||
          e.type == 'BlogPosting') {
        primaryIndex = i;
        break;
      }
    }

    return SemanticExtractionResult(
      entities: entities,
      markdownContent: extraction.textContent,
      sourceUrl: extraction.url,
      pageTitle: extraction.title,
      siteName: extraction.siteName,
      favicon: extraction.favicon,
      primaryEntityIndex: primaryIndex ?? 0,
    );
  }

  // ---------------------------------------------------------------------------
  // JSON-LD extraction
  // ---------------------------------------------------------------------------

  /// Relationship-bearing JSON-LD properties and their Schema.org predicates.
  static const _relationshipProperties = <String, String>{
    'author': 'schema:author',
    'publisher': 'schema:publisher',
    'brand': 'schema:brand',
    'offers': 'schema:offers',
    'location': 'schema:location',
    'worksFor': 'schema:worksFor',
    'memberOf': 'schema:memberOf',
    'organizer': 'schema:organizer',
  };

  List<SemanticEntity> _extractFromJsonLd(
    List<Map<String, dynamic>> jsonLdList,
  ) {
    final entities = <SemanticEntity>[];

    for (final ld in jsonLdList) {
      _extractJsonLdRecursive(ld, entities);
    }

    return entities;
  }

  /// Recursively extracts entities from a JSON-LD node.
  ///
  /// Handles `@graph` arrays, container types (`WebSite`, `WebPage`,
  /// `BreadcrumbList` → `ListItem`), and deeply nested typed objects.
  void _extractJsonLdRecursive(
    Map<String, dynamic> node,
    List<SemanticEntity> entities, {
    int depth = 0,
  }) {
    // Guard against excessively deep nesting
    if (depth > 10) return;

    // Handle @graph arrays — iterate ALL items
    final graph = node['@graph'];
    if (graph is List) {
      for (final item in graph) {
        if (item is Map<String, dynamic>) {
          _extractJsonLdRecursive(item, entities, depth: depth + 1);
        }
      }
      // If the node itself has a @type beyond the graph, also process it
      if (node['@type'] == null) return;
    }

    final rawType = node['@type'];
    String? type;
    if (rawType is List) {
      type = rawType.firstOrNull?.toString();
    } else if (rawType is String) {
      type = rawType;
    }

    // Handle container types that hold sub-entities
    if (type == 'BreadcrumbList') {
      _extractBreadcrumbEntities(node, entities, depth);
      return;
    }

    if (type == 'WebSite' || type == 'WebPage' || type == 'CollectionPage' ||
        type == 'SearchResultsPage' || type == 'ItemPage') {
      // Extract the container itself, then recurse into sub-entities
      final entity = _jsonLdItemToEntity(node);
      if (entity != null) {
        _extractRelationships(node, entity, entities);
      }
      // Recurse into nested objects that may hold additional entities
      _extractNestedTypedObjects(node, entities, depth);
      return;
    }

    // Standard entity extraction
    final entity = _jsonLdItemToEntity(node);
    if (entity != null) {
      _extractRelationships(node, entity, entities);
    }

    // Still recurse into any nested typed objects not covered by
    // _extractRelationships (which only handles _relationshipProperties)
    _extractNestedTypedObjects(node, entities, depth);
  }

  /// Extracts entities from `BreadcrumbList` → `ListItem` chains.
  ///
  /// Each `ListItem` with an `item` property that has a `@type` is extracted
  /// as a separate entity.
  void _extractBreadcrumbEntities(
    Map<String, dynamic> node,
    List<SemanticEntity> entities,
    int depth,
  ) {
    final itemListElement = node['itemListElement'];
    if (itemListElement is! List) return;

    for (final listItem in itemListElement) {
      if (listItem is! Map<String, dynamic>) continue;

      // ListItem's "item" can be a typed entity
      final item = listItem['item'];
      if (item is Map<String, dynamic> && item['@type'] != null) {
        _extractJsonLdRecursive(item, entities, depth: depth + 1);
      } else if (item is Map<String, dynamic> && item['name'] != null) {
        // Some breadcrumbs have name/url but no @type — create a WebPage
        final name = item['name']?.toString();
        final url = item['@id']?.toString() ?? item['url']?.toString();
        if (name != null && name.isNotEmpty) {
          final candidate = SemanticEntity(
            type: 'WebPage',
            properties: {
              'name': name,
              if (url != null) 'url': url,
            },
            confidence: 0.6,
          );
          if (!_hasSimilarEntity(entities, candidate)) {
            entities.add(candidate);
          }
        }
      }

      // Also check for nested "name" in the ListItem itself
      if (listItem['name'] != null && item == null) {
        final name = listItem['name'].toString();
        final url = listItem['url']?.toString() ??
            listItem['@id']?.toString();
        if (name.isNotEmpty) {
          final candidate = SemanticEntity(
            type: 'WebPage',
            properties: {
              'name': name,
              if (url != null) 'url': url,
            },
            confidence: 0.6,
          );
          if (!_hasSimilarEntity(entities, candidate)) {
            entities.add(candidate);
          }
        }
      }
    }
  }

  /// Recursively scans all values of [node] for nested objects with `@type`
  /// that aren't already handled by [_extractRelationships].
  void _extractNestedTypedObjects(
    Map<String, dynamic> node,
    List<SemanticEntity> entities,
    int depth,
  ) {
    for (final entry in node.entries) {
      // Skip keys already handled by _extractRelationships
      if (_relationshipProperties.containsKey(entry.key)) continue;
      // Skip JSON-LD structural keys
      if (entry.key.startsWith('@')) continue;

      final value = entry.value;
      if (value is Map<String, dynamic> && value['@type'] != null) {
        _extractJsonLdRecursive(value, entities, depth: depth + 1);
      } else if (value is List) {
        for (final elem in value) {
          if (elem is Map<String, dynamic> && elem['@type'] != null) {
            _extractJsonLdRecursive(elem, entities, depth: depth + 1);
          }
        }
      }
    }
  }

  /// Extracts nested objects from [item] as separate entities, adds
  /// [EntityRelationship]s to [parentEntity], and appends everything to
  /// [entities]. The parent entity is always added to the list first.
  void _extractRelationships(
    Map<String, dynamic> item,
    SemanticEntity parentEntity,
    List<SemanticEntity> entities,
  ) {
    // Collect nested entities and their predicates in one pass.
    final nestedEntities = <SemanticEntity>[];
    final relationships = <EntityRelationship>[];

    void tryExtractNested(dynamic value, String predicate) {
      if (value is Map<String, dynamic> && value['@type'] != null) {
        final nested = _jsonLdItemToEntity(value);
        if (nested != null && !_hasSimilarEntity(entities, nested)) {
          // targetIndex = parentIndex + 1 + count of nested entities so far
          final targetIndex = entities.length + 1 + nestedEntities.length;
          relationships.add(EntityRelationship(
            predicate: predicate,
            targetIndex: targetIndex,
          ));
          nestedEntities.add(nested);
        }
      } else if (value is List) {
        for (final elem in value) {
          if (elem is Map<String, dynamic> && elem['@type'] != null) {
            final nested = _jsonLdItemToEntity(elem);
            if (nested != null && !_hasSimilarEntity(entities, nested)) {
              final targetIndex = entities.length + 1 + nestedEntities.length;
              relationships.add(EntityRelationship(
                predicate: predicate,
                targetIndex: targetIndex,
              ));
              nestedEntities.add(nested);
            }
          }
        }
      }
    }

    for (final entry in _relationshipProperties.entries) {
      tryExtractNested(item[entry.key], entry.value);
    }

    // Add the parent entity (with relationships if any were found).
    if (relationships.isNotEmpty) {
      entities.add(SemanticEntity(
        type: parentEntity.type,
        properties: parentEntity.properties,
        relationships: relationships,
        confidence: parentEntity.confidence,
      ));
    } else {
      entities.add(parentEntity);
    }

    // Append nested entities in order — their indices match targetIndex.
    entities.addAll(nestedEntities);
  }

  SemanticEntity? _jsonLdItemToEntity(Map<String, dynamic> item) {
    final rawType = item['@type'];
    if (rawType == null) return null;

    // Normalize type — can be a string or list
    String? type;
    if (rawType is List) {
      type = rawType.firstOrNull?.toString();
    } else if (rawType is String) {
      type = rawType;
    }
    if (type == null || type.isEmpty) return null;

    // Skip generic types that don't carry useful info
    if (type == 'BreadcrumbList' ||
        type == 'SiteNavigationElement' ||
        type == 'WPHeader' ||
        type == 'WPFooter' ||
        type == 'WPSideBar') {
      return null;
    }

    final properties = <String, dynamic>{};

    // Map common JSON-LD properties
    _mapJsonLdProp(item, 'name', properties);
    _mapJsonLdProp(item, 'headline', properties, targetKey: 'name');
    _mapJsonLdProp(item, 'description', properties);
    _mapJsonLdProp(item, 'url', properties);
    _mapJsonLdProp(item, 'datePublished', properties);
    _mapJsonLdProp(item, 'dateModified', properties);
    _mapJsonLdProp(item, 'dateCreated', properties);
    _mapJsonLdProp(item, 'inLanguage', properties);

    // Image — can be string, object, or array
    final image = item['image'];
    if (image is String) {
      properties['image'] = image;
    } else if (image is Map) {
      properties['image'] =
          image['url']?.toString() ?? image['@id']?.toString();
    } else if (image is List && image.isNotEmpty) {
      final first = image.first;
      if (first is String) {
        properties['image'] = first;
        if (image.length > 1) {
          properties['images'] = image.whereType<String>().toList();
        }
      } else if (first is Map) {
        properties['image'] = first['url']?.toString();
        properties['images'] = image
            .whereType<Map<dynamic, dynamic>>()
            .map((i) => i['url']?.toString())
            .where((u) => u != null)
            .toList();
      }
    }

    // Author — can be string, object, or array
    final author = item['author'];
    if (author is String) {
      properties['author'] = author;
    } else if (author is Map) {
      properties['author'] =
          author['name']?.toString() ?? author['@id']?.toString();
      if (author['url'] != null) {
        properties['authorUrl'] = author['url'].toString();
      }
      if (author['image'] != null) {
        final authorImg = author['image'];
        properties['authorImage'] =
            authorImg is Map ? authorImg['url']?.toString() : authorImg.toString();
      }
    } else if (author is List && author.isNotEmpty) {
      final first = author.first;
      properties['author'] =
          first is Map ? first['name']?.toString() : first.toString();
    }

    // Publisher
    final publisher = item['publisher'];
    if (publisher is String) {
      properties['publisher'] = publisher;
    } else if (publisher is Map) {
      properties['publisher'] = publisher['name']?.toString();
      if (publisher['logo'] != null) {
        final logo = publisher['logo'];
        properties['publisherLogo'] =
            logo is Map ? logo['url']?.toString() : logo.toString();
      }
    }

    // Product-specific
    _mapJsonLdProp(item, 'sku', properties);
    _mapJsonLdProp(item, 'brand', properties);
    _mapJsonLdProp(item, 'gtin', properties);
    _mapJsonLdProp(item, 'category', properties);
    _mapJsonLdProp(item, 'color', properties);
    _mapJsonLdProp(item, 'material', properties);

    // Handle brand as object
    final brand = item['brand'];
    if (brand is Map) {
      properties['brand'] = brand['name']?.toString();
    }

    // Offers (price info)
    final offers = item['offers'];
    if (offers is Map) {
      _mapJsonLdProp(offers, 'price', properties);
      _mapJsonLdProp(offers, 'priceCurrency', properties);
      _mapJsonLdProp(offers, 'availability', properties);
      _mapJsonLdProp(offers, 'itemCondition', properties);
    } else if (offers is List && offers.isNotEmpty && offers.first is Map) {
      final firstOffer = offers.first as Map<dynamic, dynamic>;
      _mapJsonLdProp(firstOffer, 'price', properties);
      _mapJsonLdProp(firstOffer, 'priceCurrency', properties);
      _mapJsonLdProp(firstOffer, 'availability', properties);
    }

    // Ratings
    final rating = item['aggregateRating'];
    if (rating is Map) {
      _mapJsonLdProp(rating, 'ratingValue', properties);
      _mapJsonLdProp(rating, 'reviewCount', properties);
      _mapJsonLdProp(rating, 'bestRating', properties);
    }

    // Place-specific
    final address = item['address'];
    if (address is Map) {
      _mapJsonLdProp(address, 'streetAddress', properties);
      _mapJsonLdProp(address, 'postalCode', properties);
      _mapJsonLdProp(address, 'addressLocality', properties);
      _mapJsonLdProp(address, 'addressRegion', properties);
      _mapJsonLdProp(address, 'addressCountry', properties);
    } else if (address is String) {
      properties['streetAddress'] = address;
    }

    final geo = item['geo'];
    if (geo is Map) {
      _mapJsonLdProp(geo, 'latitude', properties);
      _mapJsonLdProp(geo, 'longitude', properties);
    }

    // Person-specific
    _mapJsonLdProp(item, 'jobTitle', properties);
    _mapJsonLdProp(item, 'email', properties);
    _mapJsonLdProp(item, 'telephone', properties);
    _mapJsonLdProp(item, 'givenName', properties);
    _mapJsonLdProp(item, 'familyName', properties);

    // sameAs (social links)
    final sameAs = item['sameAs'];
    if (sameAs is List) {
      properties['sameAs'] = sameAs.whereType<String>().toList();
    } else if (sameAs is String) {
      properties['sameAs'] = [sameAs];
    }

    // Keywords
    final keywords = item['keywords'];
    if (keywords is List) {
      properties['keywords'] = keywords.whereType<String>().toList();
    } else if (keywords is String) {
      properties['keywords'] = keywords
          .split(',')
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .toList();
    }

    // Only return if we have at least a name or description
    if (properties['name'] == null &&
        properties['description'] == null &&
        properties['headline'] == null) {
      return null;
    }

    return SemanticEntity(
      type: type,
      properties: properties,
      confidence: 0.95, // JSON-LD is high confidence
    );
  }

  void _mapJsonLdProp(
    Map<dynamic, dynamic> source,
    String key,
    Map<String, dynamic> target, {
    String? targetKey,
  }) {
    final value = source[key];
    if (value != null && value.toString().isNotEmpty) {
      target[targetKey ?? key] =
          value is num || value is bool ? value : value.toString();
    }
  }

  // ---------------------------------------------------------------------------
  // OpenGraph extraction
  // ---------------------------------------------------------------------------

  List<SemanticEntity> _extractFromOpenGraph(Map<String, String> og, String url) {
    if (og.isEmpty) return const [];

    final results = <SemanticEntity>[];
    final properties = <String, dynamic>{};
    final ogType = og['og:type'] ?? 'website';

    if (og['og:title'] != null) properties['name'] = og['og:title'];
    if (og['og:description'] != null) {
      properties['description'] = og['og:description'];
    }
    if (og['og:image'] != null) properties['image'] = og['og:image'];
    if (og['og:url'] != null) properties['url'] = og['og:url'];
    if (og['og:site_name'] != null) {
      properties['publisher'] = og['og:site_name'];
    }
    if (og['article:published_time'] != null) {
      properties['datePublished'] = og['article:published_time'];
    }
    if (og['article:author'] != null) {
      properties['author'] = og['article:author'];
    }
    if (og['product:price:amount'] != null) {
      properties['price'] = og['product:price:amount'];
    }
    if (og['product:price:currency'] != null) {
      properties['priceCurrency'] = og['product:price:currency'];
    }

    // article:section → category
    if (og['article:section'] != null) {
      properties['articleSection'] = og['article:section'];
    }

    // article:tag → keywords
    final tags = <String>[];
    if (og['article:tag'] != null) {
      tags.add(og['article:tag']!);
    }
    // Handle multiple article:tag values (some pages use indexed keys)
    for (var i = 0; i < 20; i++) {
      final tagKey = 'article:tag:$i';
      if (og[tagKey] != null) {
        tags.add(og[tagKey]!);
      }
    }
    if (tags.isNotEmpty) {
      properties['keywords'] = tags;
    }

    // og:locale → language
    if (og['og:locale'] != null) {
      properties['inLanguage'] = og['og:locale'];
    }

    if (properties.isEmpty) return const [];

    // Map og:type to Schema.org type
    final String schemaType;
    switch (ogType) {
      case 'article':
        schemaType = 'Article';
      case 'product':
        schemaType = 'Product';
      case 'profile':
        schemaType = 'Person';
      case 'music.song' || 'music.album':
        schemaType = 'MusicRecording';
      case 'video.movie' || 'video.episode':
        schemaType = 'VideoObject';
      case 'book':
        schemaType = 'Book';
      case 'place':
        schemaType = 'Place';
      default:
        schemaType = 'WebPage';
    }

    properties['url'] ??= url;

    // Extract place coordinates from OG place tags
    final placeLat = og['place:location:latitude'];
    final placeLng = og['place:location:longitude'];
    if (placeLat != null && placeLng != null) {
      final lat = double.tryParse(placeLat);
      final lng = double.tryParse(placeLng);
      if (lat != null && lng != null) {
        if (schemaType == 'Place') {
          // Add coords directly to the main entity
          properties['latitude'] = lat;
          properties['longitude'] = lng;
        } else {
          // Create a separate Place entity
          final placeProps = <String, dynamic>{
            'latitude': lat,
            'longitude': lng,
          };
          if (og['og:title'] != null) {
            placeProps['name'] = og['og:title'];
          }
          results.add(SemanticEntity(
            type: 'Place',
            properties: placeProps,
            confidence: 0.75,
          ));
        }
      }
    }

    // Create a Person entity from article:author (URL or plain-text name).
    final authorValue = og['article:author'];
    if (authorValue != null && authorValue.trim().isNotEmpty) {
      SemanticEntity? authorEntity;

      if (authorValue.startsWith('http://') ||
          authorValue.startsWith('https://')) {
        // Author is a URL — extract name from the path.
        final authorUri = Uri.tryParse(authorValue);
        final pathName = authorUri?.pathSegments
            .where((s) => s.isNotEmpty)
            .lastOrNull
            ?.replaceAll('-', ' ')
            .replaceAll('_', ' ');

        authorEntity = SemanticEntity(
          type: 'Person',
          properties: {
            'name': pathName ?? authorValue,
            'url': authorValue,
          },
          confidence: 0.7,
        );
      } else {
        // Author is a plain-text name.
        authorEntity = SemanticEntity(
          type: 'Person',
          properties: {'name': authorValue.trim()},
          confidence: 0.7,
        );
      }

      results.insert(
        0,
        SemanticEntity(
          type: schemaType,
          properties: properties,
          confidence: 0.8,
        ),
      );
      results.add(authorEntity);
    } else {
      results.insert(
        0,
        SemanticEntity(
          type: schemaType,
          properties: properties,
          confidence: 0.8,
        ),
      );
    }

    // Create an Organization entity from og:site_name if present.
    final siteName = og['og:site_name'];
    if (siteName != null && siteName.trim().isNotEmpty) {
      final orgProps = <String, dynamic>{'name': siteName.trim()};
      if (og['og:url'] != null) {
        final siteUri = Uri.tryParse(og['og:url']!);
        if (siteUri != null) {
          orgProps['url'] = '${siteUri.scheme}://${siteUri.host}';
        }
      }
      results.add(SemanticEntity(
        type: 'Organization',
        properties: orgProps,
        confidence: 0.65,
      ));
    }

    return results;
  }

  // ---------------------------------------------------------------------------
  // Microdata extraction
  // ---------------------------------------------------------------------------

  List<SemanticEntity> _extractFromMicrodata(
    List<Map<String, dynamic>> microdata,
  ) {
    final entities = <SemanticEntity>[];

    for (final item in microdata) {
      _extractMicrodataRecursive(item, entities);
    }

    return entities;
  }

  /// Recursively extracts entities from a microdata item and its nested
  /// `itemscope` children.
  void _extractMicrodataRecursive(
    Map<String, dynamic> item,
    List<SemanticEntity> entities, {
    int depth = 0,
  }) {
    if (depth > 10) return;

    final typeUrl = item['@type']?.toString() ?? '';
    final props = item['properties'] as Map<String, dynamic>? ?? {};

    if (props.isEmpty) return;

    // Extract type name from full Schema.org URL
    String type = typeUrl.split('/').last;
    if (type.isEmpty) type = 'Thing';

    final properties = <String, dynamic>{};
    final relationships = <EntityRelationship>[];
    final nestedEntities = <SemanticEntity>[];

    for (final entry in props.entries) {
      final value = entry.value;

      // Check for nested itemscope objects (maps with @type)
      if (value is Map<String, dynamic> && value['@type'] != null) {
        final nested = _extractMicrodataItem(value);
        if (nested != null && !_hasSimilarEntity(entities, nested)) {
          final predicate = _relationshipProperties[entry.key];
          if (predicate != null) {
            final targetIndex =
                entities.length + 1 + nestedEntities.length;
            relationships.add(EntityRelationship(
              predicate: predicate,
              targetIndex: targetIndex,
            ));
          }
          nestedEntities.add(nested);

          // Recurse into the nested item for deeper nesting
          final nestedProps =
              value['properties'] as Map<String, dynamic>? ?? {};
          for (final np in nestedProps.entries) {
            if (np.value is Map<String, dynamic> &&
                (np.value as Map)['@type'] != null) {
              _extractMicrodataRecursive(
                np.value as Map<String, dynamic>,
                entities,
                depth: depth + 1,
              );
            } else if (np.value is List) {
              for (final listItem in np.value as List) {
                if (listItem is Map<String, dynamic> &&
                    listItem['@type'] != null) {
                  _extractMicrodataRecursive(
                    listItem,
                    entities,
                    depth: depth + 1,
                  );
                }
              }
            }
          }
          continue;
        }
      }

      // Handle lists that may contain nested itemscope objects
      if (value is List) {
        var hasNested = false;
        for (final elem in value) {
          if (elem is Map<String, dynamic> && elem['@type'] != null) {
            final nested = _extractMicrodataItem(elem);
            if (nested != null && !_hasSimilarEntity(entities, nested)) {
              final predicate = _relationshipProperties[entry.key];
              if (predicate != null) {
                final targetIndex =
                    entities.length + 1 + nestedEntities.length;
                relationships.add(EntityRelationship(
                  predicate: predicate,
                  targetIndex: targetIndex,
                ));
              }
              nestedEntities.add(nested);
              hasNested = true;

              // Recurse deeper
              _extractMicrodataRecursive(
                elem,
                entities,
                depth: depth + 1,
              );
            }
          }
        }
        if (hasNested) continue;

        properties[entry.key] = value.length == 1 ? value.first : value;
      } else {
        properties[entry.key] = value;
      }
    }

    if (properties.isNotEmpty) {
      final candidate = SemanticEntity(
        type: type,
        properties: properties,
        relationships: relationships,
        confidence: 0.85,
      );
      if (!_hasSimilarEntity(entities, candidate)) {
        entities.add(candidate);
        entities.addAll(nestedEntities);
      }
    }
  }

  /// Converts a single microdata item to a [SemanticEntity] without recursion.
  SemanticEntity? _extractMicrodataItem(Map<String, dynamic> item) {
    final typeUrl = item['@type']?.toString() ?? '';
    final props = item['properties'] as Map<String, dynamic>? ?? {};

    String type = typeUrl.split('/').last;
    if (type.isEmpty) type = 'Thing';

    final properties = <String, dynamic>{};
    for (final entry in props.entries) {
      final value = entry.value;
      // Flatten nested typed objects to just their name
      if (value is Map<String, dynamic> && value['@type'] != null) {
        final innerProps =
            value['properties'] as Map<String, dynamic>? ?? {};
        final name = innerProps['name'];
        if (name is List && name.isNotEmpty) {
          properties[entry.key] = name.first;
        } else if (name != null) {
          properties[entry.key] = name;
        }
        continue;
      }
      if (value is List) {
        properties[entry.key] = value.length == 1 ? value.first : value;
      } else {
        properties[entry.key] = value;
      }
    }

    if (properties.isEmpty) return null;

    return SemanticEntity(
      type: type,
      properties: properties,
      confidence: 0.85,
    );
  }

  // ---------------------------------------------------------------------------
  // LLM extraction
  // ---------------------------------------------------------------------------

  Future<List<SemanticEntity>> _extractWithLlm(
    WebExtraction extraction,
    List<SemanticEntity> existingEntities,
  ) async {
    // Truncate content to avoid token limits
    final contentPreview = extraction.textContent.length > 3000
        ? extraction.textContent.substring(0, 3000)
        : extraction.textContent;

    // Build context about what we already found
    final existingTypes = existingEntities
        .map((e) => '${e.type}: ${e.properties['name'] ?? 'unnamed'}')
        .join(', ');

    final prompt =
        '''Analyze this web page content and extract a comprehensive semantic graph.
Your goal is to represent the page as a `WebPage` entity containing a rich collection of its parts.
Do NOT just extract a single Article unless the page is strictly a text article.

Page Metadata:
URL: ${extraction.url}
Title: ${extraction.title}
Author: ${extraction.author ?? 'unknown'}
Site: ${extraction.siteName ?? 'unknown'}

Already found entities: $existingTypes

Content Preview (Markdown-ish):
$contentPreview

Instructions:
1.  **Root Entity**: The root of your extraction MUST be a `WebPage` entity.
2.  **Main Entity**: Identify the primary subject of the page (e.g., an `Article`, a `Product`, a `Person` profile, a `VideoObject`, or an `ImageGallery`) and link it via `mainEntity`.
3.  **Parts**: Extract all significant sections as `hasPart`. This includes:
    *   `ImageGallery`: If there are multiple related images.
    *   `VideoObject`: For embedded videos.
    *   `SiteNavigationElement`: For major navigation menus (group them).
    *   `relatedLink`: For "See Also" or "Related Articles" links.
4.  **Content**: For the `mainEntity` (e.g. Article), put the *cleaned* markdown content into a custom property `markdownContent` (if it's text-heavy).
5.  **Entities**: Extract mentioned People, Places, Organizations as separate entities and link them (e.g. `mentions`, `about`).

JSON Output Format:
{
  "entities": [
    {
      "type": "WebPage",
      "properties": {
        "name": "Page Title",
        "url": "${extraction.url}",
        "description": "..."
      },
      "relationships": [
        {"predicate": "mainEntity", "targetIndex": 1},
        {"predicate": "hasPart", "targetIndex": 2}
      ]
    },
    {
      "type": "Article", // or Product, Person, etc.
      "properties": {
        "name": "Title",
        "markdownContent": "Full markdown text...",
        "image": "url...",
        "datePublished": "..."
      }
    }
  ]
}
''';


    final response = await _llm.complete(LlmRequest(
      messages: [LlmMessage.user(prompt)],
      temperature: 0.1,
      maxTokens: 2000,
      systemPrompt:
          'You are a semantic web extraction engine. You analyze web pages '
          'and extract structured Schema.org entities. Return ONLY valid JSON. '
          'No markdown, no explanations.',
    ));

    // Extract content from the sealed LlmResponse
    final content = switch (response) {
      TextLlmResponse(:final content) => content,
      ToolCallsLlmResponse(:final content) => content ?? '',
      ErrorLlmResponse(:final message) =>
        throw Exception('LLM extraction error: $message'),
    };

    return _parseLlmResponse(content);
  }

  /// Relationship mapping from LLM "relationshipToArticle" values to Schema.org
  /// predicates.
  static const _llmRelationshipMap = <String, String>{
    'author': 'schema:author',
    'publisher': 'schema:publisher',
    'subject': 'schema:about',
    'source': 'schema:mentions',
    'mentioned': 'schema:mentions',
  };

  List<SemanticEntity> _parseLlmResponse(String response) {
    final entities = <SemanticEntity>[];

    try {
      var jsonStr = response.trim();

      // Strip markdown code fences if present (handle ```json and ```)
      jsonStr = jsonStr
          .replaceFirst(RegExp(r'^```\w*\n?'), '')
          .replaceFirst(RegExp(r'\n?```\s*$'), '');

      // Try to find a JSON object with "entities" array first, then bare array
      List<dynamic> parsed;
      final objStart = jsonStr.indexOf('{');
      final arrStart = jsonStr.indexOf('[');

      if (objStart != -1 &&
          (arrStart == -1 || objStart < arrStart)) {
        // Looks like {"entities": [...]} wrapper
        final objEnd = jsonStr.lastIndexOf('}');
        if (objEnd > objStart) {
          var objStr = jsonStr.substring(objStart, objEnd + 1);
          objStr = _tryRecoverJson(objStr);
          final obj = jsonDecode(objStr) as Map<String, dynamic>;
          final entitiesArr = obj['entities'];
          if (entitiesArr is List) {
            parsed = entitiesArr;
          } else {
            // Fall back to trying as array
            return _tryParseAsArray(jsonStr);
          }
        } else {
          return _tryParseAsArray(jsonStr);
        }
      } else if (arrStart != -1) {
        return _tryParseAsArray(jsonStr);
      } else {
        return [];
      }

      _addEntitiesFromParsed(parsed, entities);
    } catch (e) {
      dev.log(
        'Failed to parse LLM semantic response',
        name: 'SemanticExtractor',
        error: e,
      );
      // Try one more time with aggressive JSON recovery
      try {
        final recovered = _tryParseAsArray(response);
        if (recovered.isNotEmpty) return recovered;
      } catch (_) {
        // Give up
      }
    }

    return entities;
  }

  /// Attempts to parse [jsonStr] as a JSON array of entities.
  List<SemanticEntity> _tryParseAsArray(String jsonStr) {
    final entities = <SemanticEntity>[];
    final startIdx = jsonStr.indexOf('[');
    final endIdx = jsonStr.lastIndexOf(']');
    if (startIdx == -1 || endIdx == -1 || endIdx <= startIdx) return [];

    var arrStr = jsonStr.substring(startIdx, endIdx + 1);
    arrStr = _tryRecoverJson(arrStr);
    final parsed = jsonDecode(arrStr) as List<dynamic>;
    _addEntitiesFromParsed(parsed, entities);
    return entities;
  }

  /// Attempts basic JSON recovery: remove trailing commas before ] or }.
  String _tryRecoverJson(String jsonStr) {
    return jsonStr
        .replaceAll(RegExp(r',\s*}'), '}')
        .replaceAll(RegExp(r',\s*]'), ']');
  }

  /// Converts parsed JSON items into [SemanticEntity] objects, handling
  /// the "relationshipToArticle" field and building relationships between
  /// entities.
  void _addEntitiesFromParsed(
    List<dynamic> parsed,
    List<SemanticEntity> entities,
  ) {
    final startOffset = entities.length;

    for (final item in parsed) {
      if (item is! Map<String, dynamic>) continue;

      final type = item['type']?.toString();
      final props = item['properties'];
      final conf = item['confidence'];

      if (type == null || type.isEmpty) continue;
      if (props is! Map<String, dynamic>) continue;

      final confidence = conf is num ? conf.toDouble().clamp(0.0, 1.0) : 0.7;
      if (confidence < 0.5) continue;

      final relationships = <EntityRelationship>[];
      
      // Parse explicit relationships from the LLM
      final rels = item['relationships'];
      if (rels is List) {
        for (final rel in rels) {
          if (rel is Map &&
              rel['predicate'] != null &&
              rel['targetIndex'] != null) {
            final targetRelative = rel['targetIndex'];
            if (targetRelative is int &&
                targetRelative >= 0 &&
                targetRelative < parsed.length) {
              relationships.add(EntityRelationship(
                predicate: rel['predicate'].toString(),
                targetIndex: startOffset + targetRelative,
              ));
            }
          }
        }
      }

      // Backward compatibility: handle "relationshipToArticle" by assuming
      // the first entity in the batch is the root/article if not specified.
      final relToArticle = item['relationshipToArticle']?.toString();
      if (relToArticle != null && parsed.isNotEmpty) {
        // Assume index 0 is the root if this is not index 0
        final myIndex = parsed.indexOf(item);
        if (myIndex > 0) {
           final predicate = _llmRelationshipMap[relToArticle];
           if (predicate != null) {
             // Add relationship to the FIRST entity in this batch (assumed root)
             relationships.add(EntityRelationship(
               predicate: predicate,
               targetIndex: startOffset, // 0th element of this batch
             ));
           }
        }
      }

      entities.add(SemanticEntity(
        type: type,
        properties: Map<String, dynamic>.from(props),
        relationships: relationships,
        confidence: confidence,
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Creates a fallback Article or WebPage entity when no structured data
  /// exists.
  SemanticEntity _createFallbackEntity(WebExtraction extraction) {
    // Check structured data and URL patterns for specific entity types
    // before defaulting to Article.
    String type;
    if (_looksLikeProduct(extraction)) {
      type = 'Product';
    } else if (extraction.textContent.length > 200) {
      type = 'Article';
    } else {
      type = 'WebPage';
    }

    return SemanticEntity(
      type: type,
      properties: {
        'name': extraction.title,
        if (extraction.description != null)
          'description': extraction.description,
        'url': extraction.url,
        if (extraction.author != null) 'author': extraction.author,
        if (extraction.images.isNotEmpty) 'image': extraction.images.first,
        if (extraction.datePublished != null)
          'datePublished': extraction.datePublished!.toIso8601String(),
        if (extraction.siteName != null) 'publisher': extraction.siteName,
      },
      confidence: 0.6,
    );
  }

  /// Heuristically detects whether a page is a product page based on
  /// OG type, URL patterns, and text content indicators.
  static bool _looksLikeProduct(WebExtraction extraction) {
    // OG type check
    final ogType = extraction.openGraph['og:type']?.toLowerCase();
    if (ogType == 'product' || ogType == 'og:product') return true;

    // URL patterns common for product pages
    final url = extraction.url.toLowerCase();
    if (url.contains('/dp/') || // Amazon
        url.contains('/product/') ||
        url.contains('/item/') ||
        url.contains('/p/') && url.contains('shop')) {
      return true;
    }

    // Text content indicators
    final lower = extraction.textContent.toLowerCase();
    final indicators = [
      'add to cart', 'buy now', 'add to bag', 'add to basket',
      'in stock', 'out of stock', 'free shipping', 'free delivery',
    ];
    var matches = 0;
    for (final ind in indicators) {
      if (lower.contains(ind)) matches++;
    }
    return matches >= 2;
  }

  /// Adds `ImageObject` entities for significant content images.
  void _addImageEntities(
    List<SemanticEntity> entities,
    WebExtraction extraction,
  ) {
    // Collect images already referenced by other entities
    final usedImages = <String>{};
    for (final e in entities) {
      final img = e.properties['image'];
      if (img is String) usedImages.add(img);
      final imgs = e.properties['images'];
      if (imgs is List) {
        for (final i in imgs) {
          if (i is String) usedImages.add(i);
        }
      }
      final authorImg = e.properties['authorImage'];
      if (authorImg is String) usedImages.add(authorImg);
      final publisherLogo = e.properties['publisherLogo'];
      if (publisherLogo is String) usedImages.add(publisherLogo);
    }

    // Add remaining content images as ImageObject entities
    var imageCount = 0;
    for (final imgUrl in extraction.images) {
      if (usedImages.contains(imgUrl)) continue;
      if (WebExtractor.isLikelyLogoUrl(imgUrl)) continue;
      if (imageCount >= 20) break; // Cap at 20 image entities

      entities.add(SemanticEntity(
        type: 'ImageObject',
        properties: {
          'contentUrl': imgUrl,
          'url': imgUrl,
          'name': 'Image from ${extraction.title}',
        },
        confidence: 0.7,
      ));
      imageCount++;
    }
  }

  /// Adds entity entries for discovered links, classifying them by type.
  ///
  /// Links pointing to product pages become `Product` entities; other
  /// links with images or headline-length titles become `Article`; the
  /// rest become `WebPage`.
  void _addLinkEntities(
    List<SemanticEntity> entities,
    WebExtraction extraction,
  ) {
    if (extraction.articleLinks.isEmpty) return;

    // De-dupe against existing entities
    final existingUrls = entities
        .map((e) => e.properties['url'] as String?)
        .where((u) => u != null)
        .toSet();
    // Also ignore self-link
    existingUrls.add(extraction.url);

    for (final link in extraction.articleLinks) {
      if (existingUrls.contains(link.url)) continue;
      // Skip very short titles or empty URLs
      if (link.title.length < 3 || link.url.isEmpty) continue;

      // Detect product links by URL patterns
      final linkUrl = link.url.toLowerCase();
      final isProduct = linkUrl.contains('/dp/') ||
          linkUrl.contains('/product/') ||
          linkUrl.contains('/item/') ||
          linkUrl.contains('/gp/product/') ||
          (linkUrl.contains('/p/') && linkUrl.contains('shop'));

      // Treat as Article if it has an image or title looks like a headline.
      // Otherwise WebPage.
      final String type;
      if (isProduct) {
        type = 'Product';
      } else if (link.image != null || link.title.length > 20) {
        type = 'Article';
      } else {
        type = 'WebPage';
      }

      entities.add(SemanticEntity(
        type: type,
        properties: {
          'name': link.title,
          'url': link.url,
          if (link.image != null && link.image!.isNotEmpty) 'image': link.image,
          if (link.description != null) 'description': link.description,
        },
        confidence: 0.8,
      ));
      existingUrls.add(link.url);
    }
  }

  /// Creates Person and Organization entities from [WebExtraction] metadata
  /// (author, siteName) when no such entities were found by structured-data
  /// extractors. This guarantees basic entity coverage even without an LLM.
  void _ensureMetadataEntities(
    List<SemanticEntity> entities,
    WebExtraction extraction,
  ) {
    // Create a Person entity for the article author if one doesn't exist yet.
    final author = extraction.author;
    if (author != null && author.trim().isNotEmpty) {
      final authorCandidate = SemanticEntity(
        type: 'Person',
        properties: {'name': author.trim()},
        confidence: 0.6,
      );
      if (!_hasSimilarEntity(entities, authorCandidate)) {
        entities.add(authorCandidate);
      }
    }

    // Create an Organization entity for the site/publisher if missing.
    final site = extraction.siteName;
    if (site != null && site.trim().isNotEmpty) {
      final orgProps = <String, dynamic>{'name': site.trim()};
      final parsedUrl = Uri.tryParse(extraction.url);
      if (parsedUrl != null) {
        orgProps['url'] = '${parsedUrl.scheme}://${parsedUrl.host}';
      }
      final orgCandidate = SemanticEntity(
        type: 'Organization',
        properties: orgProps,
        confidence: 0.55,
      );
      if (!_hasSimilarEntity(entities, orgCandidate)) {
        entities.add(orgCandidate);
      }
    }
  }

  /// Checks if an entity with similar type and name already exists.
  bool _hasSimilarEntity(
    List<SemanticEntity> existing,
    SemanticEntity candidate,
  ) {
    return _findSimilarEntityIndex(existing, candidate) != null;
  }

  /// Returns the index of an existing entity with similar type and name,
  /// or `null` if no match is found.
  ///
  /// Uses fuzzy matching: exact name, URL match, substring containment,
  /// and word overlap to catch variants like "SpaceX" vs
  /// "Space Exploration Technologies Corporation".
  int? _findSimilarEntityIndex(
    List<SemanticEntity> existing,
    SemanticEntity candidate,
  ) {
    final candName =
        (candidate.properties['name'] ?? '').toString().toLowerCase().trim();
    final candUrl =
        (candidate.properties['url'] ?? '').toString().toLowerCase().trim();

    for (var i = 0; i < existing.length; i++) {
      final e = existing[i];
      if (e.type == candidate.type) {
        final eName =
            (e.properties['name'] ?? '').toString().toLowerCase().trim();
        // Exact name match.
        if (eName.isNotEmpty && candName.isNotEmpty && eName == candName) {
          return i;
        }
        // URL match.
        final eUrl =
            (e.properties['url'] ?? '').toString().toLowerCase().trim();
        if (eUrl.isNotEmpty && candUrl.isNotEmpty && eUrl == candUrl) {
          return i;
        }
        // Fuzzy name match: substring containment.
        if (eName.isNotEmpty && candName.isNotEmpty) {
          if (eName.contains(candName) || candName.contains(eName)) {
            return i;
          }
          // Strip common corporate suffixes and compare.
          final stripped = _stripCorpSuffixes(eName);
          final candStripped = _stripCorpSuffixes(candName);
          if (stripped.isNotEmpty && candStripped.isNotEmpty &&
              (stripped == candStripped ||
               stripped.contains(candStripped) ||
               candStripped.contains(stripped))) {
            return i;
          }
          // Cross-reference: if one entity's name appears in the other's
          // description, they're likely aliases (e.g. "SpaceX" in desc of
          // "Space Exploration Technologies Corporation").
          final eDesc = (e.properties['description'] ?? '')
              .toString().toLowerCase().trim();
          final candDesc = (candidate.properties['description'] ?? '')
              .toString().toLowerCase().trim();
          if (candName.length >= 4 && eDesc.contains(candName)) return i;
          if (eName.length >= 4 && candDesc.contains(eName)) return i;

          // Brand-abbreviation pattern: single-token name starting with the
          // first word of a multi-word name (after suffix stripping).
          // E.g. "SpaceX" starts with "Space" (first word of
          // "Space Exploration") → 5/6 = 83% coverage → same entity.
          final sWords = stripped.split(' ')
              .where((w) => w.length >= 3).toList();
          final cWords = candStripped.split(' ')
              .where((w) => w.length >= 3).toList();
          final single = sWords.length == 1 && cWords.length > 1
              ? stripped.replaceAll(' ', '')
              : cWords.length == 1 && sWords.length > 1
                  ? candStripped.replaceAll(' ', '')
                  : null;
          final multiFirst = sWords.length == 1 && cWords.length > 1
              ? cWords.first
              : cWords.length == 1 && sWords.length > 1
                  ? sWords.first
                  : null;
          if (single != null && multiFirst != null &&
              multiFirst.length >= 4 &&
              single.startsWith(multiFirst) &&
              multiFirst.length >= (single.length * 0.7).ceil()) {
            return i;
          }
        }
      }
    }
    return null;
  }

  /// Strips common corporate/organization suffixes for fuzzy comparison.
  static String _stripCorpSuffixes(String name) {
    var s = name;
    for (final suffix in const [
      'inc', 'inc.', 'llc', 'ltd', 'corp', 'corp.', 'corporation',
      'company', 'co', 'co.', 'group', 'holdings', 'technologies',
      'technology', 'the',
    ]) {
      s = s.replaceAll(RegExp('\\b${RegExp.escape(suffix)}\\b'), '');
    }
    return s.replaceAll(RegExp(r'[,.\s]+'), ' ').trim();
  }
}
