/// Collection type helpers for the Kabuk knowledge store.
///
/// A Collection is a nestable folder for organizing documents and media.
/// Collections form a tree structure with optional parent collections,
/// similar to folders in a file system or notebooks in Obsidian.
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

/// Immutable representation of a Collection entity.
///
/// Collections organize documents and other collections into a tree.
/// Each collection has a name, optional icon/color, and an optional
/// parent collection URI for nesting.
@immutable
class CollectionData {
  /// Creates a [CollectionData] with explicit values.
  const CollectionData({
    required this.uri,
    this.name,
    this.description,
    this.icon,
    this.color,
    this.parentCollection,
    this.pinned = false,
    this.dateCreated,
    this.dateModified,
    this.tags = const [],
  });

  /// Constructs a [CollectionData] from a subject [uri] and its [triples].
  factory CollectionData.fromTriples(String uri, List<Triple> triples) {
    return CollectionData(
      uri: uri,
      name: triples
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue,
      description: triples
          .where((t) => t.predicate == NS.schemaDescription)
          .firstOrNull
          ?.objectValue,
      icon: triples
          .where((t) => t.predicate == NS.kabukIcon)
          .firstOrNull
          ?.objectValue,
      color: triples
          .where((t) => t.predicate == NS.kabukColor)
          .firstOrNull
          ?.objectValue,
      parentCollection: triples
          .where((t) => t.predicate == NS.kabukParentCollection)
          .firstOrNull
          ?.objectValue,
      pinned:
          triples
              .where((t) => t.predicate == NS.kabukPinned)
              .firstOrNull
              ?.objectValue ==
          'true',
      dateCreated: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaDateCreated)
            .firstOrNull
            ?.objectValue,
      ),
      dateModified: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaDateModified)
            .firstOrNull
            ?.objectValue,
      ),
      tags: triples
          .where((t) => t.predicate == NS.kabukTag)
          .map((t) => t.objectValue)
          .toList(),
    );
  }

  /// The entity URI (e.g. `kabuk:Collection/<uuid>`).
  final String uri;

  /// The collection name (`schema:name`).
  final String? name;

  /// Optional description (`schema:description`).
  final String? description;

  /// An emoji or icon identifier.
  final String? icon;

  /// Hex color string for the collection.
  final String? color;

  /// URI of the parent collection, or null for root collections.
  final String? parentCollection;

  /// Whether this collection is pinned/favorited.
  final bool pinned;

  /// When the collection was created.
  final DateTime? dateCreated;

  /// When the collection was last modified.
  final DateTime? dateModified;

  /// User-assigned tags.
  final List<String> tags;

  static DateTime? _tryParseDateTime(String? value) =>
      value == null ? null : DateTime.tryParse(value);
}

/// Convenience methods for working with Collection entities.
extension KnowledgeStoreCollectionExtension on KnowledgeStore {
  /// Creates a new collection and returns its URI.
  Future<String> createCollection({
    required String name,
    String? description,
    String? icon,
    String? color,
    String? parentCollection,
    List<String> tags = const [],
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('Collection');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.kabukCollection,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      if (icon != null) {
        await ctx.set(uri, NS.kabukIcon, icon);
      }
      if (color != null) {
        await ctx.set(uri, NS.kabukColor, color);
      }
      if (parentCollection != null) {
        await ctx.set(
          uri,
          NS.kabukParentCollection,
          parentCollection,
          objectType: ObjectType.uri,
        );
      }

      final now = DateTime.now().toIso8601String();
      await ctx.set(uri, NS.schemaDateCreated, now);
      await ctx.set(uri, NS.schemaDateModified, now);

      for (final tag in tags) {
        await ctx.add(uri, NS.kabukTag, tag);
      }
      return uri;
    });
  }

  /// Updates a collection's metadata.
  Future<void> updateCollection(
    String uri, {
    String? name,
    String? description,
    String? icon,
    String? color,
    bool? pinned,
  }) {
    return mutate((ctx) async {
      if (name != null) await ctx.set(uri, NS.schemaName, name);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      if (icon != null) await ctx.set(uri, NS.kabukIcon, icon);
      if (color != null) await ctx.set(uri, NS.kabukColor, color);
      if (pinned != null) {
        await ctx.set(
          uri,
          NS.kabukPinned,
          pinned,
          objectType: ObjectType.boolean,
        );
      }
      await ctx.set(
        uri,
        NS.schemaDateModified,
        DateTime.now().toIso8601String(),
      );
    });
  }

  /// Deletes a collection and optionally its contents.
  Future<void> deleteCollection(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }

  /// Lists root collections (those without a parent).
  Future<List<CollectionData>> listRootCollections({int limit = 50}) async {
    final typeTriples = await query()
        .where(NS.rdfType, equals: NS.kabukCollection)
        .orderBy(NS.schemaName)
        .limit(limit)
        .execute();

    final uris = typeTriples.map((t) => t.subject).toSet();
    final collections = <CollectionData>[];

    for (final uri in uris) {
      final triples = await getEntity(uri);
      final data = CollectionData.fromTriples(uri, triples);
      if (data.parentCollection == null) {
        collections.add(data);
      }
    }
    return collections;
  }

  /// Lists child collections of a parent collection.
  Future<List<CollectionData>> listChildCollections(
    String parentUri, {
    int limit = 50,
  }) async {
    final triples = await query()
        .where(NS.kabukParentCollection, equals: parentUri)
        .limit(limit)
        .execute();

    final uris = triples.map((t) => t.subject).toSet();
    final collections = <CollectionData>[];

    for (final uri in uris) {
      final entityTriples = await getEntity(uri);
      // Only include actual Collection entities.
      final isCollection = entityTriples.any(
        (t) => t.predicate == NS.rdfType && t.objectValue == NS.kabukCollection,
      );
      if (isCollection) {
        collections.add(CollectionData.fromTriples(uri, entityTriples));
      }
    }
    return collections;
  }

  /// Retrieves a single collection by [uri], or null if not found.
  Future<CollectionData?> getCollectionData(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return CollectionData.fromTriples(uri, triples);
  }

  /// Lists all documents (Notes) within a collection.
  Future<List<String>> listDocumentsInCollection(
    String collectionUri, {
    int limit = 50,
  }) async {
    final triples = await query()
        .where(NS.kabukParentCollection, equals: collectionUri)
        .limit(limit)
        .execute();

    final uris = <String>{};
    for (final t in triples) {
      final entityTriples = await getEntity(t.subject);
      final isNote = entityTriples.any(
        (e) => e.predicate == NS.rdfType && e.objectValue == NS.schemaNote,
      );
      if (isNote) uris.add(t.subject);
    }
    return uris.toList();
  }
}
