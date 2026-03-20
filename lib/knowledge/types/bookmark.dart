/// Kabuk Bookmark type helpers for the knowledge store.
///
/// Provides [BookmarkData] for structured access to pinned web bookmarks,
/// plus [KnowledgeStoreBookmarkExtension] convenience methods on
/// [KnowledgeStore].
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

/// Immutable representation of a pinned web bookmark.
///
/// All fields are extracted from the underlying RDF triples.
/// Use [BookmarkData.fromTriples] to construct from raw store data,
/// or the [KnowledgeStoreBookmarkExtension] helpers for high-level access.
@immutable
class BookmarkData {
  /// Creates a [BookmarkData] with the given field values.
  const BookmarkData({
    required this.uri,
    this.name,
    this.url,
    this.description,
    this.iconName,
    this.color,
    this.pinOrder,
    this.dateCreated,
  });

  /// Constructs a [BookmarkData] from a subject [uri] and its [triples].
  factory BookmarkData.fromTriples(String uri, List<Triple> triples) {
    return BookmarkData(
      uri: uri,
      name: triples
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue,
      url: triples
          .where((t) => t.predicate == NS.schemaUrl)
          .firstOrNull
          ?.objectValue,
      description: triples
          .where((t) => t.predicate == NS.schemaDescription)
          .firstOrNull
          ?.objectValue,
      iconName: triples
          .where((t) => t.predicate == NS.kabukIconName)
          .firstOrNull
          ?.objectValue,
      color: triples
          .where((t) => t.predicate == NS.kabukColor)
          .firstOrNull
          ?.objectValue,
      pinOrder: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.kabukPinOrder)
            .firstOrNull
            ?.objectValue,
      ),
      dateCreated: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaDateCreated)
            .firstOrNull
            ?.objectValue,
      ),
    );
  }

  /// The entity URI (e.g. `kabuk:Bookmark/<uuid>`).
  final String uri;

  /// Display name (`schema:name`).
  final String? name;

  /// The URL to open (`schema:url`).
  final String? url;

  /// Optional description (`schema:description`).
  final String? description;

  /// Material icon name identifier (`kabuk:iconName`).
  final String? iconName;

  /// Hex color string e.g. `'FF4500'` (`kabuk:color`).
  final String? color;

  /// Sort order for pinned display (`kabuk:pinOrder`).
  final int? pinOrder;

  /// When the bookmark was created (`schema:dateCreated`).
  final DateTime? dateCreated;

  static DateTime? _tryParseDateTime(String? value) =>
      value == null ? null : DateTime.tryParse(value);

  static int? _tryParseInt(String? value) =>
      value == null ? null : int.tryParse(value);
}

/// Convenience methods for working with Bookmark entities in the knowledge
/// store.
extension KnowledgeStoreBookmarkExtension on KnowledgeStore {
  /// Creates a new Bookmark entity and returns its URI.
  Future<String> createBookmark({
    required String name,
    required String url,
    String? description,
    String? iconName,
    String? color,
    int? pinOrder,
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('Bookmark');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.kabukBookmark,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      await ctx.set(uri, NS.schemaUrl, url);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      if (iconName != null) {
        await ctx.set(uri, NS.kabukIconName, iconName);
      }
      if (color != null) {
        await ctx.set(uri, NS.kabukColor, color);
      }
      if (pinOrder != null) {
        await ctx.set(uri, NS.kabukPinOrder, pinOrder.toString());
      }
      await ctx.set(
        uri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );
      return uri;
    });
  }

  /// Retrieves a single Bookmark by [uri], or `null` if not found.
  Future<BookmarkData?> getBookmarkData(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return BookmarkData.fromTriples(uri, triples);
  }

  /// Lists all Bookmarks ordered by pin order then creation date.
  Future<List<BookmarkData>> listBookmarks({int limit = 100}) async {
    final typeTriples = await query()
        .where(NS.rdfType, equals: NS.kabukBookmark)
        .limit(limit)
        .execute();

    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    final bookmarks = <BookmarkData>[];
    for (final uri in uris) {
      final triples = allTriples[uri];
      if (triples != null && triples.isNotEmpty) {
        bookmarks.add(BookmarkData.fromTriples(uri, triples));
      }
    }

    // Sort by pinOrder (nulls last), then dateCreated descending.
    bookmarks.sort((a, b) {
      final ao = a.pinOrder ?? 999999;
      final bo = b.pinOrder ?? 999999;
      if (ao != bo) return ao.compareTo(bo);
      final ad = a.dateCreated ?? DateTime(2000);
      final bd = b.dateCreated ?? DateTime(2000);
      return bd.compareTo(ad);
    });

    return bookmarks;
  }

  /// Deletes a Bookmark by [uri].
  Future<void> deleteBookmark(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }
}
