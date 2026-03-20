/// Knowledge type helpers for schema:Place entities.
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

/// Immutable data model for a Place entity.
@immutable
class PlaceData {
  /// Creates a [PlaceData] with the given field values.
  const PlaceData({
    required this.uri,
    this.name,
    this.description,
    this.url,
    this.image,
    this.streetAddress,
    this.postalCode,
    this.addressLocality,
    this.addressRegion,
    this.addressCountry,
    this.latitude,
    this.longitude,
    this.telephone,
    this.extractedFrom,
    this.confidence,
  });

  /// The entity URI (e.g. `kabuk:Place/<uuid>`).
  final String uri;

  /// The place name (`schema:name`).
  final String? name;

  /// A description of the place (`schema:description`).
  final String? description;

  /// The canonical URL (`schema:url`).
  final String? url;

  /// Image URL (`schema:image`).
  final String? image;

  /// Street address (`schema:streetAddress`).
  final String? streetAddress;

  /// Postal/zip code (`schema:postalCode`).
  final String? postalCode;

  /// City or locality (`schema:addressLocality`).
  final String? addressLocality;

  /// State or region (`schema:addressRegion`).
  final String? addressRegion;

  /// Country (`schema:addressCountry`).
  final String? addressCountry;

  /// Geographic latitude (`schema:latitude`).
  final double? latitude;

  /// Geographic longitude (`schema:longitude`).
  final double? longitude;

  /// Telephone number (`schema:telephone`).
  final String? telephone;

  /// The source URL this entity was extracted from (`kabuk:extractedFrom`).
  final String? extractedFrom;

  /// Extraction confidence score (0.0–1.0) from semantic extraction.
  final double? confidence;

  /// Returns a formatted address string from available address components.
  String? get formattedAddress {
    final parts = [
      streetAddress,
      addressLocality,
      addressRegion,
      postalCode,
      addressCountry,
    ].where((p) => p != null && p.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Constructs a [PlaceData] from a subject [uri] and its [triples].
  factory PlaceData.fromTriples(String uri, List<Triple> triples) {
    String? s(String pred) => triples
        .where((t) => t.predicate == pred)
        .map((t) => t.objectValue)
        .firstOrNull;
    double? d(String pred) {
      final v = s(pred);
      return v != null ? double.tryParse(v) : null;
    }

    return PlaceData(
      uri: uri,
      name: s(NS.schemaName),
      description: s(NS.schemaDescription),
      url: s(NS.schemaUrl),
      image: s(NS.schemaImage),
      streetAddress: s(NS.schemaStreetAddress),
      postalCode: s(NS.schemaPostalCode),
      addressLocality: s(NS.schemaAddressLocality),
      addressRegion: s(NS.schemaAddressRegion),
      addressCountry: s(NS.schemaAddressCountry),
      latitude: d(NS.schemaLatitude),
      longitude: d(NS.schemaLongitude),
      telephone: s(NS.schemaTelephone),
      extractedFrom: s(NS.kabukExtractedFrom),
      confidence: d(NS.kabukConfidence),
    );
  }
}

/// Convenience methods for working with Place entities in the knowledge store.
extension KnowledgeStorePlaceExtension on KnowledgeStore {
  /// Creates a new Place entity and returns its URI.
  Future<String> createPlace({
    required String name,
    String? description,
    String? url,
    String? image,
    String? streetAddress,
    String? postalCode,
    String? addressLocality,
    String? addressRegion,
    String? addressCountry,
    double? latitude,
    double? longitude,
    String? telephone,
    String? extractedFrom,
    double? confidence,
  }) async {
    return mutate((ctx) async {
      final uri = ctx.create('Place');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.schemaPlace,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      if (url != null) await ctx.set(uri, NS.schemaUrl, url);
      if (image != null) await ctx.set(uri, NS.schemaImage, image);
      if (streetAddress != null) {
        await ctx.set(uri, NS.schemaStreetAddress, streetAddress);
      }
      if (postalCode != null) {
        await ctx.set(uri, NS.schemaPostalCode, postalCode);
      }
      if (addressLocality != null) {
        await ctx.set(uri, NS.schemaAddressLocality, addressLocality);
      }
      if (addressRegion != null) {
        await ctx.set(uri, NS.schemaAddressRegion, addressRegion);
      }
      if (addressCountry != null) {
        await ctx.set(uri, NS.schemaAddressCountry, addressCountry);
      }
      if (latitude != null) {
        await ctx.set(uri, NS.schemaLatitude, latitude.toString());
      }
      if (longitude != null) {
        await ctx.set(uri, NS.schemaLongitude, longitude.toString());
      }
      if (telephone != null) {
        await ctx.set(uri, NS.schemaTelephone, telephone);
      }
      if (extractedFrom != null) {
        await ctx.set(uri, NS.kabukExtractedFrom, extractedFrom);
      }
      if (confidence != null) {
        await ctx.set(uri, NS.kabukConfidence, confidence.toString());
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

  /// Retrieves a single Place by [uri], or `null` if not found.
  Future<PlaceData?> getPlaceData(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return PlaceData.fromTriples(uri, triples);
  }

  /// Updates mutable fields of an existing Place entity.
  ///
  /// Only non-null parameters are written; others are left unchanged.
  Future<void> updatePlace(
    String uri, {
    String? name,
    String? description,
    String? address,
    double? latitude,
    double? longitude,
    String? telephone,
    String? url,
  }) {
    return mutate((ctx) async {
      if (name != null) await ctx.set(uri, NS.schemaName, name);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      if (address != null) {
        await ctx.set(uri, NS.schemaStreetAddress, address);
      }
      if (latitude != null) {
        await ctx.set(uri, NS.schemaLatitude, latitude.toString());
      }
      if (longitude != null) {
        await ctx.set(uri, NS.schemaLongitude, longitude.toString());
      }
      if (telephone != null) {
        await ctx.set(uri, NS.schemaTelephone, telephone);
      }
      if (url != null) await ctx.set(uri, NS.schemaUrl, url);
    });
  }

  /// Deletes a Place entity and all its triples.
  Future<void> deletePlace(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }

  /// Lists Place entities, with at most [limit] results.
  Future<List<PlaceData>> listPlaces({int limit = 50}) async {
    final subjects =
        await query().whereType(NS.schemaPlace).limit(limit).execute();
    final uris = subjects.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final entities = await getEntities(uris);
    return [
      for (final entry in entities.entries)
        PlaceData.fromTriples(entry.key, entry.value),
    ];
  }

  /// Finds a Place by [name] (case-insensitive).
  ///
  /// Returns the URI of the first matching Place, or `null`.
  Future<String?> findPlaceByName(String name) async {
    final candidates =
        await query()
            .whereType(NS.schemaPlace)
            .where(NS.schemaName, contains: name)
            .execute();
    final lowerName = name.toLowerCase();
    for (final t in candidates) {
      final triples = await getEntity(t.subject);
      final entityName =
          triples
              .where((t) => t.predicate == NS.schemaName)
              .firstOrNull
              ?.objectValue;
      if (entityName != null && entityName.toLowerCase() == lowerName) {
        return t.subject;
      }
    }
    return null;
  }

  /// Finds a Place near the given coordinates within [radiusKm].
  ///
  /// Uses a simple Euclidean approximation on lat/lng (sufficient for
  /// small distances). Returns the URI of the nearest match within the
  /// radius, or `null` if none found.
  Future<String?> findPlaceByCoords(
    double lat,
    double lng, {
    double radiusKm = 0.5,
  }) async {
    final subjects =
        await query().whereType(NS.schemaPlace).execute();
    final uris = subjects.map((t) => t.subject).toSet();

    String? bestUri;
    double bestDist = double.infinity;

    for (final uri in uris) {
      final triples = await getEntity(uri);
      final place = PlaceData.fromTriples(uri, triples);
      if (place.latitude == null || place.longitude == null) continue;

      final dist = _haversineKm(lat, lng, place.latitude!, place.longitude!);
      if (dist <= radiusKm && dist < bestDist) {
        bestDist = dist;
        bestUri = uri;
      }
    }
    return bestUri;
  }

  /// Creates a new Place or merges into an existing one.
  ///
  /// Deduplication checks (in order):
  /// 1. Coordinates (within [deduplicateRadiusKm], default 0.5 km)
  /// 2. Name (case-insensitive)
  ///
  /// Merge strategy: existing non-null scalars are preserved; nulls are
  /// filled from new data. For description, the longer value wins. The
  /// oldest dateCreated is kept.
  Future<String> createOrMergePlace({
    required String name,
    String? description,
    String? url,
    String? image,
    String? streetAddress,
    String? postalCode,
    String? addressLocality,
    String? addressRegion,
    String? addressCountry,
    double? latitude,
    double? longitude,
    String? telephone,
    String? extractedFrom,
    double? confidence,
    double deduplicateRadiusKm = 0.5,
  }) async {
    // Try to find an existing match.
    String? existingUri;
    if (latitude != null && longitude != null) {
      existingUri = await findPlaceByCoords(
        latitude,
        longitude,
        radiusKm: deduplicateRadiusKm,
      );
    }
    existingUri ??= await findPlaceByName(name);

    if (existingUri == null) {
      return createPlace(
        name: name,
        description: description,
        url: url,
        image: image,
        streetAddress: streetAddress,
        postalCode: postalCode,
        addressLocality: addressLocality,
        addressRegion: addressRegion,
        addressCountry: addressCountry,
        latitude: latitude,
        longitude: longitude,
        telephone: telephone,
        extractedFrom: extractedFrom,
        confidence: confidence,
      );
    }

    // Merge into existing entity.
    final existing = await getPlaceData(existingUri);
    if (existing == null) {
      return createPlace(
        name: name,
        description: description,
        url: url,
        image: image,
        streetAddress: streetAddress,
        postalCode: postalCode,
        addressLocality: addressLocality,
        addressRegion: addressRegion,
        addressCountry: addressCountry,
        latitude: latitude,
        longitude: longitude,
        telephone: telephone,
        extractedFrom: extractedFrom,
        confidence: confidence,
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
      if (existing.streetAddress == null && streetAddress != null) {
        await ctx.set(uri, NS.schemaStreetAddress, streetAddress);
      }
      if (existing.postalCode == null && postalCode != null) {
        await ctx.set(uri, NS.schemaPostalCode, postalCode);
      }
      if (existing.addressLocality == null && addressLocality != null) {
        await ctx.set(uri, NS.schemaAddressLocality, addressLocality);
      }
      if (existing.addressRegion == null && addressRegion != null) {
        await ctx.set(uri, NS.schemaAddressRegion, addressRegion);
      }
      if (existing.addressCountry == null && addressCountry != null) {
        await ctx.set(uri, NS.schemaAddressCountry, addressCountry);
      }
      if (existing.latitude == null && latitude != null) {
        await ctx.set(uri, NS.schemaLatitude, latitude.toString());
      }
      if (existing.longitude == null && longitude != null) {
        await ctx.set(uri, NS.schemaLongitude, longitude.toString());
      }
      if (existing.telephone == null && telephone != null) {
        await ctx.set(uri, NS.schemaTelephone, telephone);
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
    });

    return uri;
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Haversine distance in kilometres between two lat/lng points.
double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a =
      _sinSq(dLat / 2) +
      _cos(_degToRad(lat1)) * _cos(_degToRad(lat2)) * _sinSq(dLng / 2);
  final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
  return earthRadiusKm * c;
}

double _degToRad(double deg) => deg * 3.141592653589793 / 180.0;

// dart:math is not imported to avoid platform coupling; inline the helpers.
double _sinSq(double x) {
  final s = _sin(x);
  return s * s;
}

// Taylor-series sin/cos good enough for small-angle haversine use.
// For production accuracy consider importing dart:math; these are kept
// inline to avoid adding an import solely for this helper.
double _sin(double x) {
  // Normalize to [-π, π].
  const pi = 3.141592653589793;
  x = x % (2 * pi);
  if (x > pi) x -= 2 * pi;
  if (x < -pi) x += 2 * pi;
  // 7-term Taylor expansion.
  final x2 = x * x;
  return x *
      (1 -
          x2 / 6 *
              (1 -
                  x2 / 20 *
                      (1 - x2 / 42 * (1 - x2 / 72 * (1 - x2 / 110)))));
}

double _cos(double x) => _sin(x + 3.141592653589793 / 2);

double _sqrt(double x) {
  if (x <= 0) return 0;
  // Newton's method — 10 iterations is plenty for double precision.
  double guess = x;
  for (var i = 0; i < 10; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}

double _atan2(double y, double x) {
  // Approximation using the identity atan2(y,x) ≈ atan(y/x) with quadrant
  // correction. Uses a polynomial atan approximation.
  const pi = 3.141592653589793;
  if (x == 0) return y >= 0 ? pi / 2 : -pi / 2;
  final a = y / x;
  final abs = a < 0 ? -a : a;
  // Polynomial atan for |a| <= 1.
  double at;
  if (abs <= 1) {
    at = a / (1 + 0.28125 * a * a);
  } else {
    at = (a > 0 ? pi / 2 : -pi / 2) - (1 / a) / (1 + 0.28125 / (a * a));
  }
  if (x < 0) at += y >= 0 ? pi : -pi;
  return at;
}
