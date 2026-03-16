/// Mutation context for transactional writes to the knowledge store.
library;

import 'package:kabuk/config/result.dart';
import 'package:kabuk/knowledge/triple.dart';

/// Context for performing mutations inside a knowledge store transaction.
///
/// Instances of [MutationContext] are provided to the callback passed to
/// `KnowledgeStore.mutate`. All operations are executed within a single
/// database transaction and changes are emitted only after the transaction
/// commits successfully.
///
/// ```dart
/// await store.mutate((ctx) async {
///   final uri = ctx.create('Person');
///   await ctx.set(uri, 'schema:name', 'Alice');
///   await ctx.set(uri, 'schema:email', 'alice@example.com');
/// });
/// ```
abstract interface class MutationContext {
  /// Generate a new entity URI with the format `kabuk:{type}/{uuid}`.
  ///
  /// The returned URI can be used as a subject for subsequent [add] or
  /// [set] calls within the same transaction.
  String create(String type);

  /// Add a triple to the store.
  ///
  /// Unlike [set], this does not replace existing triples with the same
  /// subject and predicate — it allows multiple values per predicate.
  ///
  /// The [object] value is automatically converted to a string
  /// representation. If [objectType] is not specified, it is inferred
  /// from the Dart runtime type of [object].
  Future<void> add(
    String subject,
    String predicate,
    dynamic object, {
    ObjectType? objectType,
    String? graph,
  });

  /// Set a triple (upsert).
  ///
  /// Replaces any existing triple with the same subject, predicate, and
  /// graph. Use this for single-valued properties.
  ///
  /// The [object] value is automatically converted to a string
  /// representation. If [objectType] is not specified, it is inferred
  /// from the Dart runtime type of [object].
  Future<void> set(
    String subject,
    String predicate,
    dynamic object, {
    ObjectType? objectType,
    String? graph,
  });

  /// Remove all triples matching the given pattern.
  ///
  /// At least one of [subject], [predicate], or [object] must be
  /// specified. Pass multiple parameters to narrow the match.
  Future<void> remove({String? subject, String? predicate, String? object});

  /// Store a blob and return its content-addressable hash.
  ///
  /// The [data] is stored securely and can be referenced from triples
  /// using [ObjectType.blobRef] with the returned hash.
  Future<String> storeBlob(List<int> data, {String? mimeType});

  /// Retrieve a blob by its content hash.
  ///
  /// Returns [Failure] with [NotFoundError] if the blob is not found.
  Future<Result<List<int>>> retrieveBlob(String hash);
}
