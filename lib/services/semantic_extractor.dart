/// Semantic extraction service — transforms raw web content into structured
/// semantic entities using LLM analysis and structured data from the page.
///
/// Takes a [WebExtraction] with its JSON-LD, OpenGraph, and microdata,
/// analyzes it with an LLM, and produces a list of [SemanticEntity] objects
/// ready to be stored in the knowledge base.
library;

import 'dart:convert';
import 'dart:developer' as dev;

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

    // Step 2: Extract/enrich from OpenGraph
    final ogEntities =
        _extractFromOpenGraph(extraction.openGraph, extraction.url);
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

    // Step 3: Extract from microdata
    final microdataEntities = _extractFromMicrodata(extraction.microdata);
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
        for (final entity in llmEntities) {
          if (!_hasSimilarEntity(entities, entity)) {
            entities.add(entity);
          }
        }
      } catch (e, st) {
        dev.log(
          'LLM semantic extraction failed',
          name: 'SemanticExtractor',
          error: e,
          stackTrace: st,
        );
        // Continue with what we have from structured data
      }
    }

    // Step 5: Ensure we always have at least one entity (fallback)
    if (entities.isEmpty) {
      entities.add(_createFallbackEntity(extraction));
    }

    // Step 6: Add image entities for content images
    _addImageEntities(entities, extraction);

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
      // Handle @graph arrays (common in WordPress, news sites)
      final graph = ld['@graph'];
      if (graph is List) {
        for (final item in graph) {
          if (item is Map<String, dynamic>) {
            final entity = _jsonLdItemToEntity(item);
            if (entity != null) {
              _extractRelationships(item, entity, entities);
            }
          }
        }
      } else {
        final entity = _jsonLdItemToEntity(ld);
        if (entity != null) {
          _extractRelationships(ld, entity, entities);
        }
      }
    }

    return entities;
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
      default:
        schemaType = 'WebPage';
    }

    properties['url'] ??= url;

    // If article:author looks like a URL, create a Person entity
    final authorValue = og['article:author'];
    if (authorValue != null &&
        (authorValue.startsWith('http://') ||
            authorValue.startsWith('https://'))) {
      final authorUri = Uri.tryParse(authorValue);
      final pathName = authorUri?.pathSegments
          .where((s) => s.isNotEmpty)
          .lastOrNull
          ?.replaceAll('-', ' ')
          .replaceAll('_', ' ');

      final authorEntity = SemanticEntity(
        type: 'Person',
        properties: {
          'name': pathName ?? authorValue,
          'url': authorValue,
        },
        confidence: 0.7,
      );

      return [
        SemanticEntity(
          type: schemaType,
          properties: properties,
          confidence: 0.8,
        ),
        authorEntity,
      ];
    }

    return [
      SemanticEntity(
        type: schemaType,
        properties: properties,
        confidence: 0.8,
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Microdata extraction
  // ---------------------------------------------------------------------------

  List<SemanticEntity> _extractFromMicrodata(
    List<Map<String, dynamic>> microdata,
  ) {
    final entities = <SemanticEntity>[];

    for (final item in microdata) {
      final typeUrl = item['@type']?.toString() ?? '';
      final props = item['properties'] as Map<String, dynamic>? ?? {};

      if (props.isEmpty) continue;

      // Extract type name from full Schema.org URL
      String type = typeUrl.split('/').last;
      if (type.isEmpty) type = 'Thing';

      final properties = <String, dynamic>{};
      final relationships = <EntityRelationship>[];
      final nestedEntities = <SemanticEntity>[];

      for (final entry in props.entries) {
        final value = entry.value;

        // Check for nested itemscope objects (maps with @type).
        if (value is Map<String, dynamic> && value['@type'] != null) {
          final nestedType =
              (value['@type']?.toString() ?? '').split('/').last;
          if (nestedType.isNotEmpty) {
            final nestedProps = <String, dynamic>{};
            final innerProps =
                value['properties'] as Map<String, dynamic>? ?? {};
            for (final np in innerProps.entries) {
              final nv = np.value;
              if (nv is List) {
                nestedProps[np.key] = nv.length == 1 ? nv.first : nv;
              } else {
                nestedProps[np.key] = nv;
              }
            }
            if (nestedProps.isNotEmpty) {
              final predicate = _relationshipProperties[entry.key];
              if (predicate != null) {
                final targetIndex =
                    entities.length + 1 + nestedEntities.length;
                relationships.add(EntityRelationship(
                  predicate: predicate,
                  targetIndex: targetIndex,
                ));
              }
              nestedEntities.add(SemanticEntity(
                type: nestedType,
                properties: nestedProps,
                confidence: 0.85,
              ));
              continue; // Don't flatten the nested object into properties
            }
          }
        }

        if (value is List) {
          properties[entry.key] = value.length == 1 ? value.first : value;
        } else {
          properties[entry.key] = value;
        }
      }

      if (properties.isNotEmpty) {
        entities.add(SemanticEntity(
          type: type,
          properties: properties,
          relationships: relationships,
          confidence: 0.85,
        ));
        entities.addAll(nestedEntities);
      }
    }

    return entities;
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

    final prompt = '''Analyze this web page and extract ALL semantic entities. 
Return ONLY valid JSON — an array of objects.

URL: ${extraction.url}
Title: ${extraction.title}
Author: ${extraction.author ?? 'unknown'}
Site: ${extraction.siteName ?? 'unknown'}
Already found: $existingTypes

Page content:
$contentPreview

Extract entities that are NOT already found above. Look for:
- People (authors, mentioned people, profiles) with name, jobTitle, image, url
- Organizations with name, url, logo
- Places/Locations with name, address, latitude, longitude
- Products with name, price, brand, image, description
- Events with name, startDate, location
- Any other meaningful Schema.org typed entities

For each entity return: {"type": "SchemaType", "properties": {"name": "...", ...}, "confidence": 0.0-1.0}

IMPORTANT:
- Do NOT include navigation elements, ads, or boilerplate
- Do NOT include entities already listed in "Already found"
- Do NOT extract the main article/page itself (already handled)
- DO extract people mentioned or who authored the content
- DO extract organizations, brands, places referenced
- Keep property values concise (max 200 chars each)
- confidence should reflect how certain you are (0.5+ only)
- Return [] if no additional entities found

JSON array:''';

    final response = await _llm.complete(LlmRequest(
      messages: [LlmMessage.user(prompt)],
      temperature: 0.1,
      maxTokens: 2000,
      systemPrompt:
          'You are a semantic web extraction engine. You analyze web pages '
          'and extract structured Schema.org entities. Return ONLY valid JSON '
          'arrays. No markdown, no explanations.',
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

  List<SemanticEntity> _parseLlmResponse(String response) {
    final entities = <SemanticEntity>[];

    try {
      // Try to find JSON array in the response
      var jsonStr = response.trim();

      // Strip markdown code fences if present
      if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr
            .replaceFirst(RegExp(r'^```\w*\n?'), '')
            .replaceFirst(RegExp(r'\n?```$'), '');
      }

      // Find the JSON array
      final startIdx = jsonStr.indexOf('[');
      final endIdx = jsonStr.lastIndexOf(']');
      if (startIdx == -1 || endIdx == -1 || endIdx <= startIdx) return [];

      jsonStr = jsonStr.substring(startIdx, endIdx + 1);
      final parsed = jsonDecode(jsonStr) as List<dynamic>;

      for (final item in parsed) {
        if (item is! Map<String, dynamic>) continue;

        final type = item['type']?.toString();
        final props = item['properties'];
        final conf = item['confidence'];

        if (type == null || type.isEmpty) continue;
        if (props is! Map<String, dynamic>) continue;

        final confidence = conf is num ? conf.toDouble().clamp(0.0, 1.0) : 0.7;
        if (confidence < 0.5) continue; // Skip low confidence

        entities.add(SemanticEntity(
          type: type,
          properties: Map<String, dynamic>.from(props),
          confidence: confidence,
        ));
      }
    } catch (e) {
      dev.log(
        'Failed to parse LLM semantic response',
        name: 'SemanticExtractor',
        error: e,
      );
    }

    return entities;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Creates a fallback Article or WebPage entity when no structured data
  /// exists.
  SemanticEntity _createFallbackEntity(WebExtraction extraction) {
    return SemanticEntity(
      type: extraction.textContent.length > 200 ? 'Article' : 'WebPage',
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

  /// Checks if an entity with similar type and name already exists.
  bool _hasSimilarEntity(
    List<SemanticEntity> existing,
    SemanticEntity candidate,
  ) {
    return _findSimilarEntityIndex(existing, candidate) != null;
  }

  /// Returns the index of an existing entity with similar type and name,
  /// or `null` if no match is found.
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
        if (eName.isNotEmpty && candName.isNotEmpty && eName == candName) {
          return i;
        }
        final eUrl =
            (e.properties['url'] ?? '').toString().toLowerCase().trim();
        if (eUrl.isNotEmpty && candUrl.isNotEmpty && eUrl == candUrl) {
          return i;
        }
      }
    }
    return null;
  }
}
