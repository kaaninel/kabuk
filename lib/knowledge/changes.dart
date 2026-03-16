/// Change event types for the Kabuk knowledge store.
library;

import 'package:kabuk/knowledge/triple.dart';

/// A single change to the knowledge store.
///
/// Use pattern matching to handle each change type exhaustively:
/// ```dart
/// switch (change) {
///   case TripleAdded(:final triple): // ...
///   case TripleRemoved(:final triple): // ...
///   case TripleUpdated(:final oldTriple, :final newTriple): // ...
/// }
/// ```
sealed class KnowledgeChange {
  /// Base constructor for knowledge changes.
  const KnowledgeChange();

  /// A triple was added to the store.
  const factory KnowledgeChange.added(Triple triple) = TripleAdded;

  /// A triple was removed from the store.
  const factory KnowledgeChange.removed(Triple triple) = TripleRemoved;

  /// A triple was updated (replaced) in the store.
  const factory KnowledgeChange.updated({
    required Triple oldTriple,
    required Triple newTriple,
  }) = TripleUpdated;
}

/// A triple was added to the knowledge store.
final class TripleAdded extends KnowledgeChange {
  /// Creates a [TripleAdded] change event.
  const TripleAdded(this.triple);

  /// The triple that was added.
  final Triple triple;

  @override
  String toString() => 'TripleAdded($triple)';
}

/// A triple was removed from the knowledge store.
final class TripleRemoved extends KnowledgeChange {
  /// Creates a [TripleRemoved] change event.
  const TripleRemoved(this.triple);

  /// The triple that was removed.
  final Triple triple;

  @override
  String toString() => 'TripleRemoved($triple)';
}

/// A triple was updated (old value replaced with new) in the knowledge store.
final class TripleUpdated extends KnowledgeChange {
  /// Creates a [TripleUpdated] change event.
  const TripleUpdated({required this.oldTriple, required this.newTriple});

  /// The previous version of the triple.
  final Triple oldTriple;

  /// The new version of the triple.
  final Triple newTriple;

  @override
  String toString() => 'TripleUpdated(old: $oldTriple, new: $newTriple)';
}

/// A batch of changes from a single mutation transaction.
///
/// Each call to `KnowledgeStore.mutate` produces exactly one [ChangeSet]
/// that is emitted on the `KnowledgeStore.changes` stream after the
/// transaction commits.
class ChangeSet {
  /// Creates a change set with the given changes and timestamp.
  const ChangeSet({required this.changes, required this.timestamp});

  /// The individual changes in this batch.
  final List<KnowledgeChange> changes;

  /// When this transaction committed.
  final DateTime timestamp;

  /// Whether this change set contains no changes.
  bool get isEmpty => changes.isEmpty;

  /// Whether this change set contains at least one change.
  bool get isNotEmpty => changes.isNotEmpty;

  @override
  String toString() => 'ChangeSet(${changes.length} changes at $timestamp)';
}
