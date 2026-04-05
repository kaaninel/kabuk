/// Knowledge type helpers for schema:Organization entities.
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

/// Immutable data model for an Organization entity.
@immutable
class OrganizationData {
  /// Creates an [OrganizationData] with the given field values.
  const OrganizationData({
    required this.uri,
    this.name,
    this.description,
    this.url,
    this.logo,
    this.image,
    this.email,
    this.telephone,
    this.address,
    this.extractedFrom,
    this.confidence,
    this.sameAs = const [],
  });

  /// The entity URI (e.g. `kabuk:Organization/<uuid>`).
  final String uri;

  /// The organization name (`schema:name`).
  final String? name;

  /// A description of the organization (`schema:description`).
  final String? description;

  /// The canonical URL (`schema:url`).
  final String? url;

  /// Logo URL (`schema:logo`).
  final String? logo;

  /// Image URL (`schema:image`).
  final String? image;

  /// Email address (`schema:email`).
  final String? email;

  /// Telephone number (`schema:telephone`).
  final String? telephone;

  /// Street address (`schema:streetAddress`).
  final String? address;

  /// The source URL this entity was extracted from (`kabuk:extractedFrom`).
  final String? extractedFrom;

  /// Extraction confidence score (0.0–1.0) from semantic extraction.
  final double? confidence;

  /// Equivalent URIs for this organization (`schema:sameAs`).
  final List<String> sameAs;

  /// Constructs an [OrganizationData] from a subject [uri] and its [triples].
  factory OrganizationData.fromTriples(String uri, List<Triple> triples) {
    String? s(String pred) => triples
        .where((t) => t.predicate == pred)
        .map((t) => t.objectValue)
        .firstOrNull;
    List<String> multi(String pred) => triples
        .where((t) => t.predicate == pred)
        .map((t) => t.objectValue)
        .toList();

    return OrganizationData(
      uri: uri,
      name: s(NS.schemaName),
      description: s(NS.schemaDescription),
      url: s(NS.schemaUrl),
      logo: s(NS.schemaLogo),
      image: s(NS.schemaImage),
      email: s(NS.schemaEmail),
      telephone: s(NS.schemaTelephone),
      address: s(NS.schemaStreetAddress),
      extractedFrom: s(NS.kabukExtractedFrom),
      confidence: double.tryParse(s(NS.kabukConfidence) ?? ''),
      sameAs: multi(NS.schemaSameAs),
    );
  }
}

/// Convenience methods for working with Organization entities in the
/// knowledge store.
extension KnowledgeStoreOrganizationExtension on KnowledgeStore {
  /// Creates a new Organization entity and returns its URI.
  Future<String> createOrganization({
    required String name,
    String? description,
    String? url,
    String? logo,
    String? image,
    String? email,
    String? telephone,
    String? extractedFrom,
    double? confidence,
    List<String>? sameAs,
  }) async {
    return mutate((ctx) async {
      final uri = ctx.create('Organization');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.schemaOrganization,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      if (url != null) await ctx.set(uri, NS.schemaUrl, url);
      if (logo != null) await ctx.set(uri, NS.schemaLogo, logo);
      if (image != null) await ctx.set(uri, NS.schemaImage, image);
      if (email != null) await ctx.set(uri, NS.schemaEmail, email);
      if (telephone != null) {
        await ctx.set(uri, NS.schemaTelephone, telephone);
      }
      if (extractedFrom != null) {
        await ctx.set(uri, NS.kabukExtractedFrom, extractedFrom);
      }
      if (confidence != null) {
        await ctx.set(uri, NS.kabukConfidence, confidence.toString());
      }
      if (sameAs != null) {
        for (final sa in sameAs) {
          await ctx.add(uri, NS.schemaSameAs, sa);
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

  /// Retrieves a single Organization by [uri], or `null` if not found.
  Future<OrganizationData?> getOrganizationData(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return OrganizationData.fromTriples(uri, triples);
  }

  /// Updates mutable fields of an existing Organization entity.
  ///
  /// Only non-null parameters are written; others are left unchanged.
  Future<void> updateOrganization(
    String uri, {
    String? name,
    String? description,
    String? url,
    String? logo,
    List<String>? sameAs,
  }) {
    return mutate((ctx) async {
      if (name != null) await ctx.set(uri, NS.schemaName, name);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      if (url != null) await ctx.set(uri, NS.schemaUrl, url);
      if (logo != null) await ctx.set(uri, NS.schemaLogo, logo);
      if (sameAs != null) {
        // Remove existing sameAs triples, then add the new set.
        await ctx.remove(subject: uri, predicate: NS.schemaSameAs);
        for (final sa in sameAs) {
          await ctx.add(uri, NS.schemaSameAs, sa);
        }
      }
    });
  }

  /// Deletes an Organization entity and all its triples.
  Future<void> deleteOrganization(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }

  /// Lists Organization entities, with at most [limit] results.
  Future<List<OrganizationData>> listOrganizations({int limit = 50}) async {
    final subjects = await query()
        .whereType(NS.schemaOrganization)
        .limit(limit)
        .execute();
    final uris = subjects.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final entities = await getEntities(uris);
    return [
      for (final entry in entities.entries)
        OrganizationData.fromTriples(entry.key, entry.value),
    ];
  }

  /// Finds an Organization by [name] (case-insensitive).
  ///
  /// Returns the URI of the first matching Organization, or `null`.
  Future<String?> findOrganizationByName(String name) async {
    final candidates =
        await query()
            .whereType(NS.schemaOrganization)
            .where(NS.schemaName, contains: name)
            .execute();
    final lowerName = name.toLowerCase();
    // First pass: exact case-insensitive match.
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
    // Second pass: substring containment (e.g. "SpaceX" in
    // "Space Exploration Technologies Corp" after stripping suffixes).
    final strippedName = _stripCorpSuffixes(lowerName);
    if (strippedName.length >= 3) {
      final allOrgs =
          await query().whereType(NS.schemaOrganization).execute();
      for (final t in allOrgs) {
        final triples = await getEntity(t.subject);
        final entityName =
            triples
                .where((t) => t.predicate == NS.schemaName)
                .firstOrNull
                ?.objectValue;
        if (entityName == null) continue;
        final strippedEntity = _stripCorpSuffixes(entityName.toLowerCase());
        if (strippedEntity.isNotEmpty &&
            (strippedEntity.contains(strippedName) ||
             strippedName.contains(strippedEntity))) {
          return t.subject;
        }
        // Brand-abbreviation pattern: single-token name starting with the
        // first word of a multi-word name (e.g. "SpaceX" starts with "Space",
        // first word of "Space Exploration").
        final snWords = strippedName.split(' ')
            .where((w) => w.length >= 3).toList();
        final seWords = strippedEntity.split(' ')
            .where((w) => w.length >= 3).toList();
        final single = snWords.length == 1 && seWords.length > 1
            ? strippedName.replaceAll(' ', '')
            : seWords.length == 1 && snWords.length > 1
                ? strippedEntity.replaceAll(' ', '')
                : null;
        final multiFirst = snWords.length == 1 && seWords.length > 1
            ? seWords.first
            : seWords.length == 1 && snWords.length > 1
                ? snWords.first
                : null;
        if (single != null && multiFirst != null &&
            multiFirst.length >= 4 &&
            single.startsWith(multiFirst) &&
            multiFirst.length >= (single.length * 0.7).ceil()) {
          return t.subject;
        }
      }
    }
    return null;
  }

  /// Strips common corporate suffixes for fuzzy name comparison.
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

  /// Finds an Organization whose `schema:url` or `schema:sameAs` matches [url].
  ///
  /// Returns the URI of the first matching Organization, or `null`.
  Future<String?> findOrganizationByUrl(String url) async {
    // Check schema:url.
    final byUrl =
        await query()
            .whereType(NS.schemaOrganization)
            .where(NS.schemaUrl, equals: url)
            .execute();
    if (byUrl.isNotEmpty) return byUrl.first.subject;

    // Check schema:sameAs.
    final bySameAs =
        await query()
            .whereType(NS.schemaOrganization)
            .where(NS.schemaSameAs, equals: url)
            .execute();
    if (bySameAs.isNotEmpty) return bySameAs.first.subject;

    return null;
  }

  /// Creates a new Organization or merges into an existing one.
  ///
  /// Deduplication checks (in order):
  /// 1. URL / sameAs match
  /// 2. Name (case-insensitive)
  ///
  /// Merge strategy: existing non-null scalars are preserved; nulls are
  /// filled from new data. For description, the longer value wins. Multi-
  /// valued fields (sameAs) are unioned. The oldest dateCreated is kept.
  Future<String> createOrMergeOrganization({
    required String name,
    String? description,
    String? url,
    String? logo,
    String? image,
    String? email,
    String? telephone,
    String? extractedFrom,
    double? confidence,
    List<String>? sameAs,
  }) async {
    // Try to find an existing match.
    String? existingUri;
    if (url != null) existingUri = await findOrganizationByUrl(url);
    if (existingUri == null) {
      for (final sa in sameAs ?? <String>[]) {
        existingUri = await findOrganizationByUrl(sa);
        if (existingUri != null) break;
      }
    }
    existingUri ??= await findOrganizationByName(name);

    if (existingUri == null) {
      return createOrganization(
        name: name,
        description: description,
        url: url,
        logo: logo,
        image: image,
        email: email,
        telephone: telephone,
        extractedFrom: extractedFrom,
        confidence: confidence,
        sameAs: sameAs,
      );
    }

    // Merge into existing entity.
    final existing = await getOrganizationData(existingUri);
    if (existing == null) {
      return createOrganization(
        name: name,
        description: description,
        url: url,
        logo: logo,
        image: image,
        email: email,
        telephone: telephone,
        extractedFrom: extractedFrom,
        confidence: confidence,
        sameAs: sameAs,
      );
    }

    final uri = existingUri;
    await mutate((ctx) async {
      if (existing.url == null && url != null) {
        await ctx.set(uri, NS.schemaUrl, url);
      }
      if (existing.logo == null && logo != null) {
        await ctx.set(uri, NS.schemaLogo, logo);
      }
      if (existing.image == null && image != null) {
        await ctx.set(uri, NS.schemaImage, image);
      }
      if (existing.email == null && email != null) {
        await ctx.set(uri, NS.schemaEmail, email);
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
      // Union sameAs values.
      if (sameAs != null) {
        final existingSet = existing.sameAs.toSet();
        for (final sa in sameAs) {
          if (existingSet.add(sa)) {
            await ctx.add(uri, NS.schemaSameAs, sa);
          }
        }
      }
    });

    return uri;
  }
}
