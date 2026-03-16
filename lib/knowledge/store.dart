/// RDF triple store interface for the Kabuk knowledge layer.
library;

import 'package:kabuk/knowledge/changes.dart';
import 'package:kabuk/knowledge/mutation.dart';
import 'package:kabuk/knowledge/query.dart';
import 'package:kabuk/knowledge/triple.dart';

/// RDF triple store interface.
///
/// All data in Kabuk is stored as RDF triples (subject, predicate, object).
/// The store uses SQLite via Drift as the backend. Mutations emit change
/// events that Riverpod providers can watch for reactive UI updates.
///
/// ```dart
/// // Query example
/// final people = await store.query()
///     .whereType('schema:Person')
///     .where('schema:name', contains: 'Alice')
///     .execute();
///
/// // Mutation example
/// await store.mutate((ctx) async {
///   final uri = ctx.create('Person');
///   await ctx.set(uri, 'schema:name', 'Alice');
/// });
///
/// // Watch example
/// store.watch(predicate: 'schema:name').listen((triples) {
///   print('Names changed: $triples');
/// });
/// ```
abstract interface class KnowledgeStore {
  /// Create a [QueryBuilder] for constructing triple queries.
  ///
  /// The returned builder is connected to this store, so terminal
  /// operations like [QueryBuilder.execute] will work.
  QueryBuilder query();

  /// Perform mutations inside a transaction.
  ///
  /// All operations within the [action] callback are executed atomically.
  /// Change events are emitted on the [changes] stream only after the
  /// transaction commits successfully.
  ///
  /// Returns the value returned by [action].
  Future<T> mutate<T>(Future<T> Function(MutationContext ctx) action);

  /// Watch for changes to triples matching a pattern.
  ///
  /// All parameters are optional filters. When omitted, that position
  /// is treated as a wildcard. The stream emits the full current set
  /// of matching triples whenever any matching triple changes.
  Stream<List<Triple>> watch({
    String? subject,
    String? predicate,
    String? object,
  });

  /// Full-text search across all triples.
  ///
  /// Searches object values for matches against [query].
  /// Returns at most [limit] results.
  Future<List<Triple>> search(String query, {int limit = 20});

  /// Get all triples for a given subject URI.
  ///
  /// This is a convenience method equivalent to
  /// `query().subject(subjectUri).execute()`.
  Future<List<Triple>> getEntity(String subjectUri);

  /// Fetch multiple entities by their subject URIs in a single query.
  ///
  /// Returns a map from subject URI to the list of triples for that entity.
  /// Subjects not found in the store are omitted from the result.
  Future<Map<String, List<Triple>>> getEntities(List<String> subjects);

  /// A stream of all change sets from mutation transactions.
  ///
  /// Each [ChangeSet] contains the individual triple changes from one
  /// call to [mutate]. This is the primary mechanism for reactive UI
  /// updates through Riverpod providers.
  Stream<ChangeSet> get changes;

  /// Close the underlying database connection.
  ///
  /// After calling this, all other methods will throw.
  Future<void> close();
}
