/// Knowledge type helpers for schema:WebPage entities.
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

/// Immutable data model for a WebPage entity in the knowledge store.
///
/// Represents a parsed web page as a semantic object. Links to all
/// entities extracted from the page (articles, people, products, etc.)
/// via [memberEntities].
@immutable
class WebPageData {
  /// Creates a [WebPageData] with the given field values.
  const WebPageData({
    required this.uri,
    this.name,
    this.description,
    this.url,
    this.image,
    this.siteName,
    this.favicon,
    this.inLanguage,
    this.publisher,
    this.datePublished,
    this.dateModified,
    this.extractedFrom,
    this.confidence,
    this.memberEntities = const [],
    this.keywords = const [],
    this.breadcrumbs = const [],
  });

  /// The entity URI (e.g. `kabuk:WebPage/<uuid>`).
  final String uri;

  /// The page title (`schema:name`).
  final String? name;

  /// A description/summary of the page (`schema:description`).
  final String? description;

  /// The canonical URL of the page (`schema:url`).
  final String? url;

  /// Primary image/thumbnail URL (`schema:image`).
  final String? image;

  /// The name of the parent website (`schema:isPartOf`).
  final String? siteName;

  /// Favicon URL for the website (`kabuk:channelFavicon`).
  final String? favicon;

  /// The language of the page content (`schema:inLanguage`).
  final String? inLanguage;

  /// The publisher name or URI (`schema:publisher`).
  final String? publisher;

  /// The date the page was published (`schema:datePublished`).
  final DateTime? datePublished;

  /// The date the page was last modified (`schema:dateModified`).
  final DateTime? dateModified;

  /// The source URL this entity was extracted from (`kabuk:extractedFrom`).
  final String? extractedFrom;

  /// Extraction confidence score (0.0–1.0) from semantic extraction.
  final double? confidence;

  /// URIs of entities extracted from this page (`kabuk:memberEntity`).
  final List<String> memberEntities;

  /// Keywords/tags associated with the page (`schema:keywords`).
  final List<String> keywords;

  /// Breadcrumb parts (`schema:hasPart`).
  final List<String> breadcrumbs;

  /// Constructs a [WebPageData] from a subject [uri] and its [triples].
  factory WebPageData.fromTriples(String uri, List<Triple> triples) {
    String? s(String pred) => triples
        .where((t) => t.predicate == pred)
        .map((t) => t.objectValue)
        .firstOrNull;
    DateTime? dt(String pred) {
      final v = s(pred);
      return v != null ? DateTime.tryParse(v) : null;
    }

    List<String> multi(String pred) => triples
        .where((t) => t.predicate == pred)
        .map((t) => t.objectValue)
        .toList();

    return WebPageData(
      uri: uri,
      name: s(NS.schemaName),
      description: s(NS.schemaDescription),
      url: s(NS.schemaUrl),
      image: s(NS.schemaImage),
      siteName: s(NS.schemaIsPartOf),
      favicon: s(NS.kabukChannelFavicon),
      inLanguage: s(NS.schemaInLanguage),
      publisher: s(NS.schemaPublisher),
      datePublished: dt(NS.schemaDatePublished),
      dateModified: dt(NS.schemaDateModified),
      extractedFrom: s(NS.kabukExtractedFrom),
      confidence: double.tryParse(s(NS.kabukConfidence) ?? ''),
      memberEntities: multi(NS.kabukMemberEntity),
      keywords: multi(NS.schemaKeywords),
      breadcrumbs: multi(NS.schemaHasPart),
    );
  }
}

/// Convenience methods for working with WebPage entities in the knowledge store.
extension KnowledgeStoreWebPageExtension on KnowledgeStore {
  /// Creates a WebPage entity representing a parsed web page.
  Future<String> createWebPage({
    required String name,
    required String url,
    String? description,
    String? image,
    String? siteName,
    String? favicon,
    String? inLanguage,
    String? publisher,
    DateTime? datePublished,
    double? confidence,
    List<String>? keywords,
  }) async {
    return mutate((ctx) async {
      final uri = ctx.create('WebPage');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.schemaWebPage,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      await ctx.set(uri, NS.schemaUrl, url);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      if (image != null) await ctx.set(uri, NS.schemaImage, image);
      if (siteName != null) {
        await ctx.set(uri, NS.schemaIsPartOf, siteName);
      }
      if (favicon != null) {
        await ctx.set(uri, NS.kabukChannelFavicon, favicon);
      }
      if (inLanguage != null) {
        await ctx.set(uri, NS.schemaInLanguage, inLanguage);
      }
      if (publisher != null) {
        await ctx.set(uri, NS.schemaPublisher, publisher);
      }
      if (datePublished != null) {
        await ctx.set(
          uri,
          NS.schemaDatePublished,
          datePublished.toIso8601String(),
          objectType: ObjectType.datetime,
        );
      }
      if (keywords != null) {
        for (final kw in keywords) {
          await ctx.add(uri, NS.schemaKeywords, kw);
        }
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

  /// Adds a member entity URI to a WebPage.
  Future<void> addWebPageMember(String webPageUri, String entityUri) async {
    await mutate((ctx) async {
      await ctx.add(
        webPageUri,
        NS.kabukMemberEntity,
        entityUri,
        objectType: ObjectType.uri,
      );
    });
  }

  /// Retrieves a single WebPage by [uri], or `null` if not found.
  Future<WebPageData?> getWebPageData(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return WebPageData.fromTriples(uri, triples);
  }

  /// Finds a WebPage by its canonical URL.
  Future<WebPageData?> findWebPageByUrl(String url) async {
    final results = await query()
        .whereType(NS.schemaWebPage)
        .where(NS.schemaUrl, equals: url)
        .limit(1)
        .execute();
    if (results.isEmpty) return null;
    final uri = results.first.subject;
    return getWebPageData(uri);
  }

  /// Updates mutable fields of an existing WebPage entity.
  ///
  /// Only non-null parameters are written; others are left unchanged.
  /// Automatically sets `schema:dateModified` to the current time.
  Future<void> updateWebPage(
    String uri, {
    String? name,
    String? description,
  }) {
    return mutate((ctx) async {
      if (name != null) await ctx.set(uri, NS.schemaName, name);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      await ctx.set(
        uri,
        NS.schemaDateModified,
        DateTime.now().toIso8601String(),
        objectType: ObjectType.datetime,
      );
    });
  }

  /// Deletes a WebPage entity and all its triples.
  ///
  /// When [cascadeMembers] is `true`, also deletes every entity referenced
  /// via `kabuk:memberEntity` (e.g. extracted articles, products, people).
  Future<void> deleteWebPage(String uri, {bool cascadeMembers = false}) async {
    if (cascadeMembers) {
      final triples = await getEntity(uri);
      final memberUris = triples
          .where((t) => t.predicate == NS.kabukMemberEntity)
          .map((t) => t.objectValue)
          .toList();
      await mutate((ctx) async {
        for (final memberUri in memberUris) {
          await ctx.remove(subject: memberUri);
        }
        await ctx.remove(subject: uri);
      });
    } else {
      await mutate((ctx) async {
        await ctx.remove(subject: uri);
      });
    }
  }

  /// Lists WebPage entities, with at most [limit] results.
  ///
  /// Optionally filter by [domain] (matched against the page URL host).
  Future<List<WebPageData>> listWebPages({
    int limit = 50,
    String? domain,
  }) async {
    final q = query().whereType(NS.schemaWebPage).limit(limit);
    final subjects = await q.execute();
    final uris = subjects.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final entities = await getEntities(uris);
    var pages = [
      for (final entry in entities.entries)
        WebPageData.fromTriples(entry.key, entry.value),
    ];
    if (domain != null) {
      pages = pages
          .where(
            (p) =>
                p.url != null &&
                Uri.tryParse(p.url!)?.host.contains(domain) == true,
          )
          .toList();
    }
    return pages;
  }

  /// Remove WebPages older than [maxAge] and their orphaned member entities.
  ///
  /// For each stale WebPage, member entities are checked for references
  /// from other WebPages. Only truly orphaned members are deleted.
  /// Returns the total count of deleted entities (WebPages + orphaned members).
  Future<int> pruneStaleWebPages(Duration maxAge) async {
    final cutoff = DateTime.now().subtract(maxAge);

    // 1. Find all WebPage entities.
    final typeTriples = await query()
        .where(NS.rdfType, equals: NS.schemaWebPage)
        .execute();
    final allUris = typeTriples.map((t) => t.subject).toSet();
    if (allUris.isEmpty) return 0;

    // 2. Load all WebPage data and determine which are stale.
    final allTriples = await getEntities(allUris.toList());
    final staleUris = <String>[];
    final staleMemberUris = <String, List<String>>{}; // webPageUri → members

    for (final uri in allUris) {
      final triples = allTriples[uri];
      if (triples == null || triples.isEmpty) continue;
      final page = WebPageData.fromTriples(uri, triples);

      // Use dateCreated for age check; skip pages without a date.
      final dateStr = triples
          .where((t) => t.predicate == NS.schemaDateCreated)
          .map((t) => t.objectValue)
          .firstOrNull;
      if (dateStr == null) continue;
      final dateCreated = DateTime.tryParse(dateStr);
      if (dateCreated == null || dateCreated.isAfter(cutoff)) continue;

      staleUris.add(uri);
      staleMemberUris[uri] = page.memberEntities;
    }
    if (staleUris.isEmpty) return 0;

    // 3. For member entities of stale pages, check if referenced elsewhere.
    // Collect all memberEntity triples from non-stale WebPages.
    final staleSet = staleUris.toSet();
    final memberTriples = await query()
        .predicate(NS.kabukMemberEntity)
        .execute();
    final liveReferences = <String>{};
    for (final t in memberTriples) {
      if (!staleSet.contains(t.subject)) {
        liveReferences.add(t.objectValue);
      }
    }

    // 4. Delete stale WebPages and orphaned members.
    var deletedCount = 0;
    await mutate((ctx) async {
      for (final uri in staleUris) {
        // Delete orphaned member entities.
        final members = staleMemberUris[uri] ?? [];
        for (final memberUri in members) {
          if (!liveReferences.contains(memberUri)) {
            await ctx.remove(subject: memberUri);
            deletedCount++;
          }
        }
        // Delete the WebPage itself.
        await ctx.remove(subject: uri);
        deletedCount++;
      }
    });

    return deletedCount;
  }
}
