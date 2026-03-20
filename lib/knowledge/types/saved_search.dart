/// Saved search type helpers for the Kabuk knowledge store.
///
/// Provides [SavedSearchData] for structured access to SavedSearch entities
/// (persistent search queries that auto-refresh and appear in discovery),
/// plus [KnowledgeStoreSavedSearchExtension] convenience methods on
/// [KnowledgeStore].
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

/// Immutable representation of a SavedSearch entity.
///
/// Represents a persistent search query that the user has saved for
/// recurring use. Saved searches appear as filter options in the Explore
/// view and can be refreshed on demand.
@immutable
class SavedSearchData {
  /// Creates a [SavedSearchData] with the given field values.
  const SavedSearchData({
    required this.uri,
    this.name,
    this.query,
    this.source,
    this.dateCreated,
  });

  /// Constructs a [SavedSearchData] from a subject [uri] and its [triples].
  factory SavedSearchData.fromTriples(String uri, List<Triple> triples) {
    return SavedSearchData(
      uri: uri,
      name: triples
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue,
      query: triples
          .where((t) => t.predicate == NS.kabukSearchQuery)
          .firstOrNull
          ?.objectValue,
      source: triples
          .where((t) => t.predicate == NS.kabukSearchSource)
          .firstOrNull
          ?.objectValue,
      dateCreated: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaDateCreated)
            .firstOrNull
            ?.objectValue,
      ),
    );
  }

  /// The entity URI in the knowledge store.
  final String uri;

  /// Display name of the saved search (`schema:name`).
  final String? name;

  /// The search query string (`kabuk:searchQuery`).
  final String? query;

  /// Where the search runs: `nostr_hashtag`, `nostr_search`, or `local`
  /// (`kabuk:searchSource`).
  final String? source;

  /// When this saved search was created (`schema:dateCreated`).
  final DateTime? dateCreated;

  static DateTime? _tryParseDateTime(String? value) =>
      value == null ? null : DateTime.tryParse(value);
}

/// Convenience methods for working with SavedSearch entities in the
/// knowledge store.
extension KnowledgeStoreSavedSearchExtension on KnowledgeStore {
  /// Creates a new SavedSearch entity and returns its URI.
  Future<String> createSavedSearch({
    required String name,
    required String queryText,
    required String source,
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('SavedSearch');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.kabukSavedSearch,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      await ctx.set(uri, NS.kabukSearchQuery, queryText);
      await ctx.set(uri, NS.kabukSearchSource, source);
      await ctx.set(
        uri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );
      return uri;
    });
  }

  /// Retrieves a single SavedSearch by [uri], or `null` if not found.
  Future<SavedSearchData?> getSavedSearch(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return SavedSearchData.fromTriples(uri, triples);
  }

  /// Lists all saved searches ordered by most recently created.
  Future<List<SavedSearchData>> listSavedSearches({int limit = 100}) async {
    final typeTriples = await query()
        .where(NS.rdfType, equals: NS.kabukSavedSearch)
        .orderBy(NS.schemaDateCreated, descending: true)
        .limit(limit)
        .execute();

    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    return [
      for (final uri in uris)
        if (allTriples[uri] case final triples? when triples.isNotEmpty)
          SavedSearchData.fromTriples(uri, triples),
    ];
  }

  /// Deletes a saved search by [uri].
  Future<void> deleteSavedSearch(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }
}
