/// Kabuk SavedView type helpers for the knowledge store.
///
/// Provides [SavedViewData] for structured access to AI-generated RFW views
/// saved by the user, plus [KnowledgeStoreSavedViewExtension] convenience
/// methods on [KnowledgeStore].
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

/// Immutable representation of a saved AI-generated view.
///
/// These are RFW templates generated during chat interactions that the user
/// chose to save for later access from the Apps view.
@immutable
class SavedViewData {
  /// Creates a [SavedViewData] with the given field values.
  const SavedViewData({
    required this.uri,
    this.name,
    this.description,
    this.rfwSource,
    this.dateCreated,
    this.pinOrder,
  });

  /// Constructs a [SavedViewData] from a subject [uri] and its [triples].
  factory SavedViewData.fromTriples(String uri, List<Triple> triples) {
    return SavedViewData(
      uri: uri,
      name: triples
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue,
      description: triples
          .where((t) => t.predicate == NS.schemaDescription)
          .firstOrNull
          ?.objectValue,
      rfwSource: triples
          .where((t) => t.predicate == NS.kabukRfwSource)
          .firstOrNull
          ?.objectValue,
      dateCreated: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaDateCreated)
            .firstOrNull
            ?.objectValue,
      ),
      pinOrder: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.kabukPinOrder)
            .firstOrNull
            ?.objectValue,
      ),
    );
  }

  /// The entity URI (e.g. `kabuk:SavedView/<uuid>`).
  final String uri;

  /// Display name (`schema:name`).
  final String? name;

  /// Short description (`schema:description`).
  final String? description;

  /// The RFW template source text (`kabuk:rfwSource`).
  final String? rfwSource;

  /// When the view was saved (`schema:dateCreated`).
  final DateTime? dateCreated;

  /// Sort order for pinned display (`kabuk:pinOrder`).
  final int? pinOrder;

  static DateTime? _tryParseDateTime(String? value) =>
      value == null ? null : DateTime.tryParse(value);

  static int? _tryParseInt(String? value) =>
      value == null ? null : int.tryParse(value);
}

/// Convenience methods for working with SavedView entities in the knowledge
/// store.
extension KnowledgeStoreSavedViewExtension on KnowledgeStore {
  /// Creates a new SavedView entity and returns its URI.
  Future<String> createSavedView({
    required String name,
    required String rfwSource,
    String? description,
    int? pinOrder,
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('SavedView');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.kabukSavedView,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      await ctx.set(uri, NS.kabukRfwSource, rfwSource);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
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

  /// Retrieves a single SavedView by [uri], or `null` if not found.
  Future<SavedViewData?> getSavedViewData(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return SavedViewData.fromTriples(uri, triples);
  }

  /// Lists all SavedViews ordered by creation date (newest first).
  Future<List<SavedViewData>> listSavedViews({int limit = 100}) async {
    final typeTriples = await query()
        .where(NS.rdfType, equals: NS.kabukSavedView)
        .orderBy(NS.schemaDateCreated, descending: true)
        .limit(limit)
        .execute();

    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    return [
      for (final uri in uris)
        if (allTriples[uri] case final triples? when triples.isNotEmpty)
          SavedViewData.fromTriples(uri, triples),
    ];
  }

  /// Deletes a SavedView by [uri].
  Future<void> deleteSavedView(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }
}
