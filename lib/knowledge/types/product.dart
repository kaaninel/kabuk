/// Knowledge type helpers for schema:Product entities.
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

/// Immutable data model for a Product entity.
@immutable
class ProductData {
  /// Creates a [ProductData] with the given field values.
  const ProductData({
    required this.uri,
    this.name,
    this.description,
    this.url,
    this.image,
    this.price,
    this.priceCurrency,
    this.brand,
    this.sku,
    this.category,
    this.ratingValue,
    this.reviewCount,
    this.availability,
    this.condition,
    this.color,
    this.material,
    this.extractedFrom,
    this.confidence,
    this.offers = const [],
    this.images = const [],
  });

  /// The entity URI (e.g. `kabuk:Product/<uuid>`).
  final String uri;

  /// The product name (`schema:name`).
  final String? name;

  /// A description of the product (`schema:description`).
  final String? description;

  /// The canonical URL (`schema:url`).
  final String? url;

  /// Primary image URL (`schema:image`).
  final String? image;

  /// The price (`schema:price`).
  final String? price;

  /// The currency of the price (`schema:priceCurrency`).
  final String? priceCurrency;

  /// The brand name (`schema:brand`).
  final String? brand;

  /// The stock keeping unit (`schema:sku`).
  final String? sku;

  /// The product category (`schema:category`).
  final String? category;

  /// The aggregate rating value (`schema:ratingValue`).
  final double? ratingValue;

  /// The number of reviews (`schema:reviewCount`).
  final int? reviewCount;

  /// Product availability (`schema:availability`).
  final String? availability;

  /// Product condition (`schema:itemCondition`).
  final String? condition;

  /// Product color (`schema:color`).
  final String? color;

  /// Product material (`schema:material`).
  final String? material;

  /// The source URL this entity was extracted from (`kabuk:extractedFrom`).
  final String? extractedFrom;

  /// Extraction confidence score (0.0–1.0) from semantic extraction.
  final double? confidence;

  /// URIs of associated offer entities (`schema:offers`).
  final List<String> offers;

  /// All image URLs (`schema:image`).
  final List<String> images;

  /// Constructs a [ProductData] from a subject [uri] and its [triples].
  factory ProductData.fromTriples(String uri, List<Triple> triples) {
    String? s(String pred) => triples
        .where((t) => t.predicate == pred)
        .map((t) => t.objectValue)
        .firstOrNull;
    double? d(String pred) {
      final v = s(pred);
      return v != null ? double.tryParse(v) : null;
    }

    int? i(String pred) {
      final v = s(pred);
      return v != null ? int.tryParse(v) : null;
    }

    List<String> multi(String pred) => triples
        .where((t) => t.predicate == pred)
        .map((t) => t.objectValue)
        .toList();

    return ProductData(
      uri: uri,
      name: s(NS.schemaName),
      description: s(NS.schemaDescription),
      url: s(NS.schemaUrl),
      image: s(NS.schemaImage),
      price: s(NS.schemaPrice),
      priceCurrency: s(NS.schemaPriceCurrency),
      brand: s(NS.schemaBrand),
      sku: s(NS.schemaSku),
      category: s(NS.schemaCategory),
      ratingValue: d(NS.schemaRatingValue),
      reviewCount: i(NS.schemaReviewCount),
      availability: s(NS.schemaAvailability),
      condition: s(NS.schemaItemCondition),
      color: s(NS.schemaColor),
      material: s(NS.schemaMaterial),
      extractedFrom: s(NS.kabukExtractedFrom),
      confidence: d(NS.kabukConfidence),
      offers: multi(NS.schemaOffers),
      images: multi(NS.schemaImage),
    );
  }
}

/// Convenience methods for working with Product entities in the knowledge store.
extension KnowledgeStoreProductExtension on KnowledgeStore {
  /// Creates a new Product entity and returns its URI.
  Future<String> createProduct({
    required String name,
    String? description,
    String? url,
    String? image,
    String? price,
    String? priceCurrency,
    String? brand,
    String? sku,
    String? category,
    double? ratingValue,
    int? reviewCount,
    String? availability,
    String? extractedFrom,
    double? confidence,
    List<String>? images,
  }) async {
    return mutate((ctx) async {
      final uri = ctx.create('Product');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.schemaProduct,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      if (url != null) await ctx.set(uri, NS.schemaUrl, url);
      if (image != null) await ctx.set(uri, NS.schemaImage, image);
      if (price != null) await ctx.set(uri, NS.schemaPrice, price);
      if (priceCurrency != null) {
        await ctx.set(uri, NS.schemaPriceCurrency, priceCurrency);
      }
      if (brand != null) await ctx.set(uri, NS.schemaBrand, brand);
      if (sku != null) await ctx.set(uri, NS.schemaSku, sku);
      if (category != null) await ctx.set(uri, NS.schemaCategory, category);
      if (ratingValue != null) {
        await ctx.set(uri, NS.schemaRatingValue, ratingValue.toString());
      }
      if (reviewCount != null) {
        await ctx.set(uri, NS.schemaReviewCount, reviewCount.toString());
      }
      if (availability != null) {
        await ctx.set(uri, NS.schemaAvailability, availability);
      }
      if (extractedFrom != null) {
        await ctx.set(uri, NS.kabukExtractedFrom, extractedFrom);
      }
      if (confidence != null) {
        await ctx.set(uri, NS.kabukConfidence, confidence.toString());
      }
      if (images != null) {
        for (final img in images) {
          await ctx.add(uri, NS.schemaImage, img);
        }
      }
      await ctx.set(
        uri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
        objectType: ObjectType.datetime,
      );
      return uri;
    });
  }

  /// Retrieves a single Product by [uri], or `null` if not found.
  Future<ProductData?> getProductData(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return ProductData.fromTriples(uri, triples);
  }

  /// Updates mutable fields of an existing Product entity.
  ///
  /// Only non-null parameters are written; others are left unchanged.
  Future<void> updateProduct(
    String uri, {
    String? name,
    String? description,
    String? price,
    String? currency,
    String? brand,
    List<String>? images,
    String? ratingValue,
    String? url,
  }) {
    return mutate((ctx) async {
      if (name != null) await ctx.set(uri, NS.schemaName, name);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      if (price != null) await ctx.set(uri, NS.schemaPrice, price);
      if (currency != null) {
        await ctx.set(uri, NS.schemaPriceCurrency, currency);
      }
      if (brand != null) await ctx.set(uri, NS.schemaBrand, brand);
      if (images != null) {
        // Remove existing image triples, then add the new set.
        await ctx.remove(subject: uri, predicate: NS.schemaImage);
        for (final img in images) {
          await ctx.add(uri, NS.schemaImage, img);
        }
      }
      if (ratingValue != null) {
        await ctx.set(uri, NS.schemaRatingValue, ratingValue);
      }
      if (url != null) await ctx.set(uri, NS.schemaUrl, url);
    });
  }

  /// Deletes a Product entity and all its triples.
  Future<void> deleteProduct(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }

  /// Lists Product entities, with at most [limit] results.
  ///
  /// Optionally filter by [extractedFrom] source URL.
  Future<List<ProductData>> listProducts({
    int limit = 50,
    String? extractedFrom,
  }) async {
    var q = query().whereType(NS.schemaProduct).limit(limit);
    if (extractedFrom != null) {
      q = q.where(NS.kabukExtractedFrom, equals: extractedFrom);
    }
    final subjects = await q.execute();
    final uris = subjects.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final entities = await getEntities(uris);
    return [
      for (final entry in entities.entries)
        ProductData.fromTriples(entry.key, entry.value),
    ];
  }

  /// Finds a Product by its canonical [url].
  ///
  /// Returns the URI of the first matching Product, or `null`.
  Future<String?> findProductByUrl(String url) async {
    final results =
        await query()
            .whereType(NS.schemaProduct)
            .where(NS.schemaUrl, equals: url)
            .execute();
    return results.isNotEmpty ? results.first.subject : null;
  }

  /// Finds a Product by its stock keeping unit ([sku]).
  ///
  /// Returns the URI of the first matching Product, or `null`.
  Future<String?> findProductBySku(String sku) async {
    final results =
        await query()
            .whereType(NS.schemaProduct)
            .where(NS.schemaSku, equals: sku)
            .execute();
    return results.isNotEmpty ? results.first.subject : null;
  }

  /// Creates a new Product or merges into an existing one.
  ///
  /// Deduplication checks (in order):
  /// 1. URL match
  /// 2. SKU match
  ///
  /// Merge strategy: existing non-null scalars are preserved; nulls are
  /// filled from new data. For description, the longer value wins. Multi-
  /// valued fields (images) are unioned. The oldest dateCreated is kept.
  Future<String> createOrMergeProduct({
    required String name,
    String? description,
    String? url,
    String? image,
    String? price,
    String? priceCurrency,
    String? brand,
    String? sku,
    String? category,
    double? ratingValue,
    int? reviewCount,
    String? availability,
    String? extractedFrom,
    double? confidence,
    List<String>? images,
  }) async {
    // Try to find an existing match.
    String? existingUri;
    if (url != null) existingUri = await findProductByUrl(url);
    if (existingUri == null && sku != null) {
      existingUri = await findProductBySku(sku);
    }

    if (existingUri == null) {
      return createProduct(
        name: name,
        description: description,
        url: url,
        image: image,
        price: price,
        priceCurrency: priceCurrency,
        brand: brand,
        sku: sku,
        category: category,
        ratingValue: ratingValue,
        reviewCount: reviewCount,
        availability: availability,
        extractedFrom: extractedFrom,
        confidence: confidence,
        images: images,
      );
    }

    // Merge into existing entity.
    final existing = await getProductData(existingUri);
    if (existing == null) {
      return createProduct(
        name: name,
        description: description,
        url: url,
        image: image,
        price: price,
        priceCurrency: priceCurrency,
        brand: brand,
        sku: sku,
        category: category,
        ratingValue: ratingValue,
        reviewCount: reviewCount,
        availability: availability,
        extractedFrom: extractedFrom,
        confidence: confidence,
        images: images,
      );
    }

    final uri = existingUri;
    await mutate((ctx) async {
      if (existing.url == null && url != null) {
        await ctx.set(uri, NS.schemaUrl, url);
      }
      if (existing.image == null && image != null) {
        await ctx.set(uri, NS.schemaImage, image);
      }
      if (existing.price == null && price != null) {
        await ctx.set(uri, NS.schemaPrice, price);
      }
      if (existing.priceCurrency == null && priceCurrency != null) {
        await ctx.set(uri, NS.schemaPriceCurrency, priceCurrency);
      }
      if (existing.brand == null && brand != null) {
        await ctx.set(uri, NS.schemaBrand, brand);
      }
      if (existing.sku == null && sku != null) {
        await ctx.set(uri, NS.schemaSku, sku);
      }
      if (existing.category == null && category != null) {
        await ctx.set(uri, NS.schemaCategory, category);
      }
      if (existing.ratingValue == null && ratingValue != null) {
        await ctx.set(uri, NS.schemaRatingValue, ratingValue.toString());
      }
      if (existing.reviewCount == null && reviewCount != null) {
        await ctx.set(uri, NS.schemaReviewCount, reviewCount.toString());
      }
      if (existing.availability == null && availability != null) {
        await ctx.set(uri, NS.schemaAvailability, availability);
      }
      // Keep the longer description.
      if (description != null &&
          (existing.description == null ||
              description.length > existing.description!.length)) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      // Keep the higher confidence value.
      if (confidence != null &&
          (existing.confidence == null || confidence > existing.confidence!)) {
        await ctx.set(uri, NS.kabukConfidence, confidence.toString());
      }
      // Union image lists.
      if (images != null) {
        final existingSet = existing.images.toSet();
        for (final img in images) {
          if (existingSet.add(img)) {
            await ctx.add(uri, NS.schemaImage, img);
          }
        }
      }
    });

    return uri;
  }
}
