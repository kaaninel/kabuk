/// Schema.org Note type helpers for the Kabuk knowledge store.
///
/// Provides [NoteData] for structured access to Note entities, plus
/// [KnowledgeStoreNoteExtension] convenience methods on [KnowledgeStore].
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

/// Immutable representation of a Schema.org Note entity.
///
/// All fields are extracted from the underlying RDF triples.
/// Use [NoteData.fromTriples] to construct from raw store data,
/// or the [KnowledgeStoreNoteExtension] helpers for high-level access.
@immutable
class NoteData {
  /// Creates a [NoteData] with the given field values.
  const NoteData({
    required this.uri,
    this.name,
    this.text,
    this.dateCreated,
    this.dateModified,
    this.tags = const [],
    this.parentCollection,
    this.coverImage,
    this.icon,
    this.pinned = false,
  });

  /// Constructs a [NoteData] from a subject [uri] and its [triples].
  ///
  /// Extracts Schema.org properties by matching predicate URIs.
  /// Unknown predicates are silently ignored.
  factory NoteData.fromTriples(String uri, List<Triple> triples) {
    return NoteData(
      uri: uri,
      name: triples
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue,
      text: triples
          .where((t) => t.predicate == NS.schemaText)
          .firstOrNull
          ?.objectValue,
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
      parentCollection: triples
          .where((t) => t.predicate == NS.kabukParentCollection)
          .firstOrNull
          ?.objectValue,
      coverImage: triples
          .where((t) => t.predicate == NS.kabukCoverImage)
          .firstOrNull
          ?.objectValue,
      icon: triples
          .where((t) => t.predicate == NS.kabukIcon)
          .firstOrNull
          ?.objectValue,
      pinned:
          triples
              .where((t) => t.predicate == NS.kabukPinned)
              .firstOrNull
              ?.objectValue ==
          'true',
    );
  }

  /// The entity URI (e.g. `kabuk:Note/<uuid>`).
  final String uri;

  /// The note title (`schema:name`).
  final String? name;

  /// The note body text (`schema:text`).
  final String? text;

  /// When the note was created (`schema:dateCreated`).
  final DateTime? dateCreated;

  /// When the note was last modified (`schema:dateModified`).
  final DateTime? dateModified;

  /// User-assigned tags (`kabuk:tag`). May be empty.
  final List<String> tags;

  /// URI of the parent collection, or null for uncategorized.
  final String? parentCollection;

  /// URI or path of a cover image for the document.
  final String? coverImage;

  /// An emoji or icon identifier.
  final String? icon;

  /// Whether this note is pinned/favorited.
  final bool pinned;

  static DateTime? _tryParseDateTime(String? value) =>
      value == null ? null : DateTime.tryParse(value);
}

/// Convenience methods for working with Note entities in the knowledge store.
extension KnowledgeStoreNoteExtension on KnowledgeStore {
  /// Creates a new Note entity and returns its URI.
  ///
  /// [title] becomes `schema:name`, [body] becomes `schema:text`.
  /// [tags] are stored as multiple `kabuk:tag` triples.
  /// `schema:dateCreated` and `schema:dateModified` are set to now.
  Future<String> createNote({
    required String title,
    String? body,
    List<String> tags = const [],
    String? parentCollection,
    String? icon,
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('Note');
      await ctx.set(uri, NS.rdfType, NS.schemaNote, objectType: ObjectType.uri);
      await ctx.set(uri, NS.schemaName, title);
      if (body != null) {
        await ctx.set(uri, NS.schemaText, body);
      }
      final now = DateTime.now().toIso8601String();
      await ctx.set(uri, NS.schemaDateCreated, now);
      await ctx.set(uri, NS.schemaDateModified, now);
      if (parentCollection != null) {
        await ctx.set(
          uri,
          NS.kabukParentCollection,
          parentCollection,
          objectType: ObjectType.uri,
        );
      }
      if (icon != null) {
        await ctx.set(uri, NS.kabukIcon, icon);
      }
      for (final tag in tags) {
        await ctx.add(uri, NS.kabukTag, tag);
      }
      return uri;
    });
  }

  /// Updates an existing note's metadata.
  Future<void> updateNote(
    String uri, {
    String? title,
    String? body,
    String? parentCollection,
    String? coverImage,
    String? icon,
    bool? pinned,
  }) {
    return mutate((ctx) async {
      if (title != null) await ctx.set(uri, NS.schemaName, title);
      if (body != null) await ctx.set(uri, NS.schemaText, body);
      if (parentCollection != null) {
        await ctx.set(
          uri,
          NS.kabukParentCollection,
          parentCollection,
          objectType: ObjectType.uri,
        );
      }
      if (coverImage != null) {
        await ctx.set(uri, NS.kabukCoverImage, coverImage);
      }
      if (icon != null) await ctx.set(uri, NS.kabukIcon, icon);
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

  /// Deletes a note and all its content blocks.
  Future<void> deleteNote(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }

  /// Lists notes in a specific collection.
  Future<List<NoteData>> listNotesInCollection(
    String collectionUri, {
    int limit = 50,
  }) async {
    final triples = await query()
        .where(NS.kabukParentCollection, equals: collectionUri)
        .limit(limit)
        .execute();

    final uris = triples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    final notes = <NoteData>[];
    for (final uri in uris) {
      final entityTriples = allTriples[uri];
      if (entityTriples == null || entityTriples.isEmpty) continue;
      final isNote = entityTriples.any(
        (t) => t.predicate == NS.rdfType && t.objectValue == NS.schemaNote,
      );
      if (isNote) {
        notes.add(NoteData.fromTriples(uri, entityTriples));
      }
    }
    notes.sort(
      (a, b) => (b.dateModified ?? DateTime(0)).compareTo(
        a.dateModified ?? DateTime(0),
      ),
    );
    return notes;
  }

  /// Retrieves a single Note by [uri], or `null` if not found.
  Future<NoteData?> getNoteData(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return NoteData.fromTriples(uri, triples);
  }

  /// Lists Notes ordered by most recently modified.
  ///
  /// Returns at most [limit] results.
  Future<List<NoteData>> listNotes({int limit = 20}) async {
    final typeTriples = await query()
        .where(NS.rdfType, equals: NS.schemaNote)
        .orderBy(NS.schemaDateModified, descending: true)
        .limit(limit)
        .execute();

    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    return [
      for (final uri in uris)
        if (allTriples[uri] case final triples? when triples.isNotEmpty)
          NoteData.fromTriples(uri, triples),
    ];
  }

  /// Full-text searches Notes and returns matching [NoteData] objects.
  ///
  /// Only entities whose `rdf:type` is `schema:Note` are included.
  Future<List<NoteData>> searchNotes(
    String searchQuery, {
    int limit = 20,
  }) async {
    final results = await search(searchQuery, limit: limit);
    final subjectUris = results.map((t) => t.subject).toSet();

    final uris = subjectUris.toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    final notes = <NoteData>[];
    for (final uri in uris) {
      final triples = allTriples[uri];
      if (triples == null || triples.isEmpty) continue;
      final isNote = triples.any(
        (t) => t.predicate == NS.rdfType && t.objectValue == NS.schemaNote,
      );
      if (isNote) {
        notes.add(NoteData.fromTriples(uri, triples));
      }
    }
    return notes;
  }
}
