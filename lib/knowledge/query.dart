/// Query builder for the Kabuk knowledge store.
library;

import 'package:kabuk/knowledge/triple.dart';

/// Executes terminal query operations against a backing store.
///
/// Implementations translate the accumulated [QueryBuilder] state into
/// concrete database operations. The default implementation in the
/// Kabuk stack is `DriftQueryExecutor` which uses Drift/SQLite.
abstract interface class QueryExecutor {
  /// Execute the query and return all matching triples.
  Future<List<Triple>> execute(QueryBuilder builder);

  /// Execute the query and return the first matching triple, or null.
  Future<Triple?> first(QueryBuilder builder);

  /// Execute the query and return the count of matching triples.
  Future<int> count(QueryBuilder builder);

  /// Execute the query and return a reactive stream of matching triples.
  ///
  /// The stream emits a new list whenever the matching set changes.
  Stream<List<Triple>> stream(QueryBuilder builder);
}

/// A single filter clause accumulated by [QueryBuilder].
class QueryClause {
  /// Creates a query clause.
  const QueryClause({
    required this.predicate,
    this.equals,
    this.contains,
    this.greaterThan,
    this.lessThan,
  });

  /// The predicate URI to filter on.
  final String predicate;

  /// Exact match on the object value.
  final String? equals;

  /// Substring match on the object value.
  final String? contains;

  /// Greater-than comparison on the object value.
  final String? greaterThan;

  /// Less-than comparison on the object value.
  final String? lessThan;
}

/// An ordering directive for query results.
class QueryOrdering {
  /// Creates an ordering directive.
  const QueryOrdering({required this.predicate, this.descending = false});

  /// The predicate to sort by.
  final String predicate;

  /// Whether to sort in descending order.
  final bool descending;
}

/// Fluent interface for building knowledge store queries.
///
/// Construct queries by chaining filter methods, then execute with
/// a terminal operation. The builder accumulates clauses without
/// touching the database until a terminal method is called.
///
/// ```dart
/// final people = await store.query()
///     .whereType('schema:Person')
///     .where('schema:name', contains: 'Alice')
///     .orderBy('schema:name')
///     .limit(10)
///     .execute();
/// ```
class QueryBuilder {
  /// Creates a new empty query builder.
  ///
  /// When executor is provided, terminal operations (execute,
  /// [first], [count], [stream]) delegate to it. Without an executor,
  /// those methods throw [UnimplementedError].
  QueryBuilder([this._executor]);

  final QueryExecutor? _executor;

  String? _subject;
  String? _predicate;
  String? _object;
  ObjectType? _objectType;
  String? _graph;
  final List<QueryClause> _clauses = [];
  final List<QueryOrdering> _orderings = [];
  final List<String> _follows = [];
  int? _limit;
  int? _offset;

  /// Filter by subject URI.
  QueryBuilder subject(String uri) {
    _subject = uri;
    return this;
  }

  /// Filter by predicate URI.
  QueryBuilder predicate(String uri) {
    _predicate = uri;
    return this;
  }

  /// Filter by object value.
  QueryBuilder object(String value) {
    _object = value;
    return this;
  }

  /// Filter by object type.
  QueryBuilder objectType(ObjectType type) {
    _objectType = type;
    return this;
  }

  /// Filter by named graph.
  QueryBuilder graph(String graph) {
    _graph = graph;
    return this;
  }

  /// Add a filter clause on a predicate's object value.
  ///
  /// At least one of [equals], [contains], [greaterThan], or [lessThan]
  /// should be specified.
  QueryBuilder where(
    String predicate, {
    String? equals,
    String? contains,
    String? greaterThan,
    String? lessThan,
  }) {
    _clauses.add(
      QueryClause(
        predicate: predicate,
        equals: equals,
        contains: contains,
        greaterThan: greaterThan,
        lessThan: lessThan,
      ),
    );
    return this;
  }

  /// Shorthand for filtering by `rdf:type`.
  ///
  /// Equivalent to `where('rdf:type', equals: rdfType)`.
  QueryBuilder whereType(String rdfType) {
    return where('rdf:type', equals: rdfType);
  }

  /// Add an ordering directive.
  QueryBuilder orderBy(String predicate, {bool descending = false}) {
    _orderings.add(QueryOrdering(predicate: predicate, descending: descending));
    return this;
  }

  /// Limit the number of results.
  QueryBuilder limit(int count) {
    _limit = count;
    return this;
  }

  /// Offset into the result set (for pagination).
  QueryBuilder offset(int count) {
    _offset = count;
    return this;
  }

  /// Follow a predicate for graph traversal.
  ///
  /// This causes the query to also return triples reachable by
  /// following the given predicate from matched subjects.
  QueryBuilder follow(String predicate) {
    _follows.add(predicate);
    return this;
  }

  // ---------------------------------------------------------------------------
  // Accumulated state accessors (for use by store implementations)
  // ---------------------------------------------------------------------------

  /// The subject filter, if set.
  String? get subjectFilter => _subject;

  /// The predicate filter, if set.
  String? get predicateFilter => _predicate;

  /// The object filter, if set.
  String? get objectFilter => _object;

  /// The object type filter, if set.
  ObjectType? get objectTypeFilter => _objectType;

  /// The graph filter, if set.
  String? get graphFilter => _graph;

  /// All accumulated where-clauses.
  List<QueryClause> get clauses => List.unmodifiable(_clauses);

  /// All accumulated ordering directives.
  List<QueryOrdering> get orderings => List.unmodifiable(_orderings);

  /// All accumulated follow directives.
  List<String> get follows => List.unmodifiable(_follows);

  /// The result limit, if set.
  int? get limitValue => _limit;

  /// The result offset, if set.
  int? get offsetValue => _offset;

  // ---------------------------------------------------------------------------
  // Terminal operations
  // ---------------------------------------------------------------------------

  /// Execute the query and return all matching triples.
  Future<List<Triple>> execute() {
    final executor = _executor;
    if (executor == null) {
      throw UnimplementedError(
        'QueryBuilder.execute() requires a store implementation. '
        'Use KnowledgeStore.query() to get a connected QueryBuilder.',
      );
    }
    return executor.execute(this);
  }

  /// Execute the query and return the first matching triple, or null.
  Future<Triple?> first() {
    final executor = _executor;
    if (executor == null) {
      throw UnimplementedError(
        'QueryBuilder.first() requires a store implementation. '
        'Use KnowledgeStore.query() to get a connected QueryBuilder.',
      );
    }
    return executor.first(this);
  }

  /// Execute the query and return the count of matching triples.
  Future<int> count() {
    final executor = _executor;
    if (executor == null) {
      throw UnimplementedError(
        'QueryBuilder.count() requires a store implementation. '
        'Use KnowledgeStore.query() to get a connected QueryBuilder.',
      );
    }
    return executor.count(this);
  }

  /// Execute the query and return a reactive stream of matching triples.
  ///
  /// The stream emits a new list whenever the matching set changes.
  Stream<List<Triple>> stream() {
    final executor = _executor;
    if (executor == null) {
      throw UnimplementedError(
        'QueryBuilder.stream() requires a store implementation. '
        'Use KnowledgeStore.query() to get a connected QueryBuilder.',
      );
    }
    return executor.stream(this);
  }
}
