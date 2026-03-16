/// Concrete implementation of [KnowledgeStore] backed by Drift/SQLite.
///
/// This is the single concrete knowledge store used in the real app.
/// It translates the abstract [KnowledgeStore] / [MutationContext] /
/// [QueryBuilder] interfaces into Drift database operations.
library;

import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide QueryExecutor;
import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/knowledge/changes.dart';
import 'package:kabuk/knowledge/database.dart' as db;
import 'package:kabuk/knowledge/mutation.dart';
import 'package:kabuk/knowledge/query.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart' as model;
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Drift-backed implementation of [KnowledgeStore].
///
/// All data is persisted in a single SQLite database. Mutations are
/// transactional and emit [ChangeSet] events on the [changes] stream,
/// enabling reactive UI updates through Riverpod providers.
class DriftKnowledgeStore implements KnowledgeStore {
  /// Creates a [DriftKnowledgeStore] backed by the given database.
  DriftKnowledgeStore(this._db);

  final db.KabukDatabase _db;
  final StreamController<ChangeSet> _changesController =
      StreamController<ChangeSet>.broadcast();

  @override
  Stream<ChangeSet> get changes => _changesController.stream;

  @override
  QueryBuilder query() => QueryBuilder(DriftQueryExecutor(_db));

  @override
  Future<T> mutate<T>(Future<T> Function(MutationContext ctx) action) async {
    final mutationCtx = _DriftMutationContext(_db);
    final result = await _db.transaction(() async {
      return action(mutationCtx);
    });

    // Emit changes after transaction commits.
    final changeList = mutationCtx._changes;
    if (changeList.isNotEmpty) {
      _changesController.add(
        ChangeSet(changes: changeList, timestamp: DateTime.now()),
      );
    }

    return result;
  }

  @override
  Stream<List<model.Triple>> watch({
    String? subject,
    String? predicate,
    String? object,
  }) {
    return _db
        .watchTriples(subject: subject, predicate: predicate, objectUri: object)
        .map((rows) => rows.map(_tripleFromRow).toList());
  }

  @override
  Future<List<model.Triple>> search(String query, {int limit = 20}) async {
    final rows = await _db.searchTriples(query, limit: limit);
    return rows.map(_tripleFromRow).toList();
  }

  /// Rebuild the FTS5 full-text search index from scratch.
  ///
  /// Re-indexes every row in the triples table. Useful after bulk
  /// imports or if the index becomes out of sync.
  Future<void> rebuildFtsIndex() async {
    await _db.rebuildFtsIndex();
  }

  @override
  Future<List<model.Triple>> getEntity(String subjectUri) async {
    final rows = await _db.findTriples(subject: subjectUri);
    return rows.map(_tripleFromRow).toList();
  }

  @override
  Future<Map<String, List<model.Triple>>> getEntities(
    List<String> subjects,
  ) async {
    if (subjects.isEmpty) return const {};
    final rows = await _db.findTriplesBySubjects(subjects);
    final result = <String, List<model.Triple>>{};
    for (final row in rows) {
      final triple = _tripleFromRow(row);
      result.putIfAbsent(triple.subject, () => []).add(triple);
    }
    return result;
  }

  @override
  Future<void> close() async {
    await _changesController.close();
    await _db.close();
  }
}

// ---------------------------------------------------------------------------
// DriftQueryExecutor — implements QueryExecutor against a Drift database.
// ---------------------------------------------------------------------------

/// A [QueryExecutor] that translates [QueryBuilder] state into
/// Drift/SQLite queries against a [db.KabukDatabase].
class DriftQueryExecutor implements QueryExecutor {
  /// Creates a [DriftQueryExecutor] backed by the given [db].
  DriftQueryExecutor(this._db);

  final db.KabukDatabase _db;

  @override
  Future<List<model.Triple>> execute(QueryBuilder builder) async {
    final q = _db.select(_db.triples);
    _applyFilters(q, builder);
    _applyOrdering(q, builder);
    if (builder.limitValue != null) {
      q.limit(builder.limitValue!, offset: builder.offsetValue);
    }
    final rows = await q.get();
    final results = rows.map(_tripleFromRow).toList();

    // Follow graph traversal: for each follow predicate, collect URI objects
    // from matching triples and fetch their triples as well.
    if (builder.follows.isNotEmpty) {
      final visitedUris = <String>{};
      for (final followPredicate in builder.follows) {
        final urisToFollow = results
            .where(
              (t) =>
                  t.predicate == followPredicate &&
                  t.objectType == model.ObjectType.uri,
            )
            .map((t) => t.objectValue)
            .where((uri) => uri.isNotEmpty && visitedUris.add(uri))
            .toList();
        for (final uri in urisToFollow) {
          final followQ = _db.select(_db.triples)
            ..where((t) => t.subject.equals(uri));
          final followRows = await followQ.get();
          results.addAll(followRows.map(_tripleFromRow));
        }
      }
    }

    return results;
  }

  @override
  Future<model.Triple?> first(QueryBuilder builder) async {
    final q = _db.select(_db.triples);
    _applyFilters(q, builder);
    _applyOrdering(q, builder);
    q.limit(1);
    final rows = await q.get();
    if (rows.isEmpty) return null;
    return _tripleFromRow(rows.first);
  }

  @override
  Future<int> count(QueryBuilder builder) async {
    final countExpr = _db.triples.id.count();
    final q = _db.selectOnly(_db.triples)..addColumns([countExpr]);
    _applyFiltersJoinable(q, builder);
    final row = await q.getSingle();
    return row.read(countExpr) ?? 0;
  }

  @override
  Stream<List<model.Triple>> stream(QueryBuilder builder) {
    final q = _db.select(_db.triples);
    _applyFilters(q, builder);
    _applyOrdering(q, builder);
    if (builder.limitValue != null) {
      q.limit(builder.limitValue!, offset: builder.offsetValue);
    }

    if (builder.follows.isEmpty) {
      return q.watch().map((rows) => rows.map(_tripleFromRow).toList());
    }

    // With follow directives, perform graph traversal on each emission.
    return q.watch().asyncMap((rows) async {
      final results = rows.map(_tripleFromRow).toList();
      final visitedUris = <String>{};
      for (final followPredicate in builder.follows) {
        final urisToFollow = results
            .where(
              (t) =>
                  t.predicate == followPredicate &&
                  t.objectType == model.ObjectType.uri,
            )
            .map((t) => t.objectValue)
            .where((uri) => uri.isNotEmpty && visitedUris.add(uri))
            .toList();
        for (final uri in urisToFollow) {
          final followQ = _db.select(_db.triples)
            ..where((t) => t.subject.equals(uri));
          final followRows = await followQ.get();
          results.addAll(followRows.map(_tripleFromRow));
        }
      }
      return results;
    });
  }

  void _applyFilters(
    SimpleSelectStatement<db.$TriplesTable, db.Triple> q,
    QueryBuilder builder,
  ) {
    q.where((t) {
      Expression<bool> expr = const Constant(true);
      if (builder.subjectFilter != null) {
        expr = expr & t.subject.equals(builder.subjectFilter!);
      }
      if (builder.predicateFilter != null) {
        expr = expr & t.predicate.equals(builder.predicateFilter!);
      }
      if (builder.objectFilter != null) {
        expr =
            expr &
            (t.objectUri.equals(builder.objectFilter!) |
                t.objectString.equals(builder.objectFilter!));
      }
      if (builder.graphFilter != null) {
        expr = expr & t.graph.equals(builder.graphFilter!);
      }
      if (builder.objectTypeFilter != null) {
        expr = expr & t.objectType.equals(builder.objectTypeFilter!.name);
      }
      for (final clause in builder.clauses) {
        if (clause.equals != null) {
          expr =
              expr &
              t.predicate.equals(clause.predicate) &
              (t.objectString.equals(clause.equals!) |
                  t.objectUri.equals(clause.equals!));
        }
        if (clause.contains != null) {
          expr =
              expr &
              t.predicate.equals(clause.predicate) &
              (t.objectString.like('%${clause.contains!}%') |
                  t.objectUri.like('%${clause.contains!}%'));
        }
        if (clause.greaterThan != null) {
          final gt = clause.greaterThan!;
          final gtInt = int.tryParse(gt);
          final gtReal = double.tryParse(gt);
          Expression<bool> gtExpr = t.objectString.isBiggerThanValue(gt);
          if (gtInt != null) {
            gtExpr = gtExpr | t.objectInt.isBiggerThanValue(gtInt);
          }
          if (gtReal != null) {
            gtExpr = gtExpr | t.objectReal.isBiggerThanValue(gtReal);
          }
          expr = expr & t.predicate.equals(clause.predicate) & gtExpr;
        }
        if (clause.lessThan != null) {
          final lt = clause.lessThan!;
          final ltInt = int.tryParse(lt);
          final ltReal = double.tryParse(lt);
          Expression<bool> ltExpr = t.objectString.isSmallerThanValue(lt);
          if (ltInt != null) {
            ltExpr = ltExpr | t.objectInt.isSmallerThanValue(ltInt);
          }
          if (ltReal != null) {
            ltExpr = ltExpr | t.objectReal.isSmallerThanValue(ltReal);
          }
          expr = expr & t.predicate.equals(clause.predicate) & ltExpr;
        }
      }
      return expr;
    });
  }

  void _applyFiltersJoinable(
    JoinedSelectStatement<db.$TriplesTable, db.Triple> q,
    QueryBuilder builder,
  ) {
    final t = _db.triples;
    if (builder.subjectFilter != null) {
      q.where(t.subject.equals(builder.subjectFilter!));
    }
    if (builder.predicateFilter != null) {
      q.where(t.predicate.equals(builder.predicateFilter!));
    }
    if (builder.objectFilter != null) {
      q.where(
        t.objectUri.equals(builder.objectFilter!) |
            t.objectString.equals(builder.objectFilter!),
      );
    }
    if (builder.graphFilter != null) {
      q.where(t.graph.equals(builder.graphFilter!));
    }
    if (builder.objectTypeFilter != null) {
      q.where(t.objectType.equals(builder.objectTypeFilter!.name));
    }
    for (final clause in builder.clauses) {
      if (clause.equals != null) {
        q.where(
          t.predicate.equals(clause.predicate) &
              (t.objectString.equals(clause.equals!) |
                  t.objectUri.equals(clause.equals!)),
        );
      }
      if (clause.contains != null) {
        q.where(
          t.predicate.equals(clause.predicate) &
              (t.objectString.like('%${clause.contains!}%') |
                  t.objectUri.like('%${clause.contains!}%')),
        );
      }
      if (clause.greaterThan != null) {
        final gt = clause.greaterThan!;
        final gtInt = int.tryParse(gt);
        final gtReal = double.tryParse(gt);
        Expression<bool> gtExpr = t.objectString.isBiggerThanValue(gt);
        if (gtInt != null) {
          gtExpr = gtExpr | t.objectInt.isBiggerThanValue(gtInt);
        }
        if (gtReal != null) {
          gtExpr = gtExpr | t.objectReal.isBiggerThanValue(gtReal);
        }
        q.where(t.predicate.equals(clause.predicate) & gtExpr);
      }
      if (clause.lessThan != null) {
        final lt = clause.lessThan!;
        final ltInt = int.tryParse(lt);
        final ltReal = double.tryParse(lt);
        Expression<bool> ltExpr = t.objectString.isSmallerThanValue(lt);
        if (ltInt != null) {
          ltExpr = ltExpr | t.objectInt.isSmallerThanValue(ltInt);
        }
        if (ltReal != null) {
          ltExpr = ltExpr | t.objectReal.isSmallerThanValue(ltReal);
        }
        q.where(t.predicate.equals(clause.predicate) & ltExpr);
      }
    }
  }

  void _applyOrdering(
    SimpleSelectStatement<db.$TriplesTable, db.Triple> q,
    QueryBuilder builder,
  ) {
    if (builder.orderings.isNotEmpty) {
      q.orderBy(
        builder.orderings.map((o) {
          return (db.Triples t) {
            final column = switch (o.predicate) {
              'subject' => t.subject,
              'predicate' => t.predicate,
              'createdAt' => t.createdAt,
              'updatedAt' => t.updatedAt,
              _ => t.createdAt,
            };
            return o.descending
                ? OrderingTerm.desc(column)
                : OrderingTerm.asc(column);
          };
        }).toList(),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Drift MutationContext — collects changes for the ChangeSet.
// ---------------------------------------------------------------------------

/// Concrete [MutationContext] that writes to a [db.KabukDatabase] and
/// accumulates [KnowledgeChange] events for emission after commit.
class _DriftMutationContext implements MutationContext {
  _DriftMutationContext(this._db);

  final db.KabukDatabase _db;
  final List<KnowledgeChange> _changes = [];

  @override
  String create(String type) {
    return 'kabuk:$type/${_uuid.v4()}';
  }

  @override
  Future<void> add(
    String subject,
    String predicate,
    dynamic object, {
    model.ObjectType? objectType,
    String? graph,
  }) async {
    final resolved = _resolveObject(object, objectType);
    final companion = db.TriplesCompanion.insert(
      subject: subject,
      predicate: predicate,
      objectType: resolved.type.name,
      objectUri: Value(resolved.uriValue),
      objectString: Value(resolved.stringValue),
      objectInt: Value(resolved.intValue),
      objectReal: Value(resolved.realValue),
      graph: Value(graph ?? 'default'),
    );
    await _db.insertTriple(companion);

    _changes.add(
      KnowledgeChange.added(
        model.Triple(
          subject: subject,
          predicate: predicate,
          objectValue: _toObjectString(resolved),
          objectType: resolved.type,
        ),
      ),
    );
  }

  @override
  Future<void> set(
    String subject,
    String predicate,
    dynamic object, {
    model.ObjectType? objectType,
    String? graph,
  }) async {
    // Remove existing triples with this subject + predicate first.
    final existing = await _db.findTriples(
      subject: subject,
      predicate: predicate,
    );
    if (existing.isNotEmpty) {
      // Delete old rows without emitting removed events — we'll emit
      // a single "updated" event instead to avoid UI flickering.
      await _db.deleteTriple(subject: subject, predicate: predicate);

      // Insert the new value directly (bypass add() to avoid TripleAdded).
      final resolved = _resolveObject(object, objectType);
      final companion = db.TriplesCompanion.insert(
        subject: subject,
        predicate: predicate,
        objectType: resolved.type.name,
        objectUri: Value(resolved.uriValue),
        objectString: Value(resolved.stringValue),
        objectInt: Value(resolved.intValue),
        objectReal: Value(resolved.realValue),
        graph: Value(graph ?? 'default'),
      );
      await _db.insertTriple(companion);

      final newTriple = model.Triple(
        subject: subject,
        predicate: predicate,
        objectValue: _toObjectString(resolved),
        objectType: resolved.type,
      );

      // Emit an updated event for each replaced triple.
      for (final row in existing) {
        _changes.add(
          KnowledgeChange.updated(
            oldTriple: model.Triple(
              subject: row.subject,
              predicate: row.predicate,
              objectValue: _objectValueFromRow(row),
              objectType: _objectTypeFromName(row.objectType),
            ),
            newTriple: newTriple,
          ),
        );
      }
    } else {
      // No existing value — plain add.
      await add(
        subject,
        predicate,
        object,
        objectType: objectType,
        graph: graph,
      );
    }
  }

  @override
  Future<void> remove({
    String? subject,
    String? predicate,
    String? object,
  }) async {
    assert(
      subject != null || predicate != null || object != null,
      'At least one filter must be specified for remove',
    );
    // Fetch matching rows, but do NOT rely on objectUri-only for the object
    // filter since string-typed triples are stored in objectString, not
    // objectUri. We fetch by subject/predicate first, then filter in Dart.
    final allRows = await _db.findTriples(
      subject: subject,
      predicate: predicate,
    );
    final rows = object == null
        ? allRows
        : allRows.where((row) => _objectValueFromRow(row) == object).toList();
    for (final row in rows) {
      // Delete by the specific object column so we don't inadvertently remove
      // other multi-valued triples sharing the same (subject, predicate).
      final objectType = row.objectType;
      await _db.deleteTriple(
        subject: row.subject,
        predicate: row.predicate,
        objectType: objectType,
        objectUri: (objectType == 'uri' || objectType == 'blobRef')
            ? row.objectUri
            : null,
        objectString: objectType == 'string' ? row.objectString : null,
        objectInt:
            (objectType == 'integer' ||
                objectType == 'boolean' ||
                objectType == 'datetime')
            ? row.objectInt
            : null,
        objectReal: (objectType == 'float' || objectType == 'real')
            ? row.objectReal
            : null,
      );
      _changes.add(
        KnowledgeChange.removed(
          model.Triple(
            subject: row.subject,
            predicate: row.predicate,
            objectValue: _objectValueFromRow(row),
            objectType: _objectTypeFromName(row.objectType),
          ),
        ),
      );
    }
  }

  @override
  Future<String> storeBlob(List<int> data, {String? mimeType}) async {
    final hashAlg = Sha256();
    final hash = await hashAlg.hash(data);
    final hashHex = hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    await _db.storeBlob(
      db.BlobsCompanion.insert(
        hash: hashHex,
        data: Uint8List.fromList(data),
        mimeType: Value(mimeType),
        size: data.length,
      ),
    );
    return hashHex;
  }

  @override
  Future<Result<List<int>>> retrieveBlob(String hash) async {
    final blob = await _db.getBlob(hash);
    if (blob == null) {
      return Result.failure(ServiceError.notFound('Blob not found: $hash'));
    }
    return Result.success(blob.data);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Resolved object value with type information.
class _ResolvedObject {
  const _ResolvedObject({
    required this.type,
    this.uriValue,
    this.stringValue,
    this.intValue,
    this.realValue,
  });

  final model.ObjectType type;
  final String? uriValue;
  final String? stringValue;
  final int? intValue;
  final double? realValue;
}

/// Map a stored type name back to [model.ObjectType].
///
/// Handles both the enum name (`float`) and the DB column type name (`real`).
model.ObjectType _objectTypeFromName(String name) {
  return switch (name) {
    'uri' => model.ObjectType.uri,
    'string' => model.ObjectType.string,
    'integer' => model.ObjectType.integer,
    'float' || 'real' => model.ObjectType.float,
    'datetime' => model.ObjectType.datetime,
    'boolean' => model.ObjectType.boolean,
    'blobRef' => model.ObjectType.blobRef,
    _ => model.ObjectType.string,
  };
}

/// Infer or apply the object type and extract storage values.
_ResolvedObject _resolveObject(dynamic value, model.ObjectType? explicitType) {
  if (explicitType != null) {
    return switch (explicitType) {
      model.ObjectType.uri => _ResolvedObject(
        type: model.ObjectType.uri,
        uriValue: value.toString(),
      ),
      model.ObjectType.string => _ResolvedObject(
        type: model.ObjectType.string,
        stringValue: value.toString(),
      ),
      model.ObjectType.integer => _ResolvedObject(
        type: model.ObjectType.integer,
        intValue: value is int ? value : int.parse(value.toString()),
      ),
      model.ObjectType.float => _ResolvedObject(
        type: model.ObjectType.float,
        realValue: value is double ? value : double.parse(value.toString()),
      ),
      model.ObjectType.datetime => _ResolvedObject(
        type: model.ObjectType.datetime,
        intValue: value is DateTime
            ? value.millisecondsSinceEpoch
            : value is int
            ? value
            : DateTime.parse(value.toString()).millisecondsSinceEpoch,
      ),
      model.ObjectType.boolean => _ResolvedObject(
        type: model.ObjectType.boolean,
        intValue: (value == true || value == 1 || value == 'true') ? 1 : 0,
      ),
      model.ObjectType.blobRef => _ResolvedObject(
        type: model.ObjectType.blobRef,
        uriValue: value.toString(),
      ),
    };
  }

  // Infer type from Dart runtime type.
  return switch (value) {
    final Uri v => _ResolvedObject(
      type: model.ObjectType.uri,
      uriValue: v.toString(),
    ),
    final String v
        when v.startsWith('http://') ||
            v.startsWith('https://') ||
            v.startsWith('kabuk:') ||
            v.startsWith('schema:') =>
      _ResolvedObject(type: model.ObjectType.uri, uriValue: v),
    final String v => _ResolvedObject(
      type: model.ObjectType.string,
      stringValue: v,
    ),
    final int v => _ResolvedObject(type: model.ObjectType.integer, intValue: v),
    final double v => _ResolvedObject(
      type: model.ObjectType.float,
      realValue: v,
    ),
    final bool v => _ResolvedObject(
      type: model.ObjectType.boolean,
      intValue: v ? 1 : 0,
    ),
    final DateTime v => _ResolvedObject(
      type: model.ObjectType.datetime,
      intValue: v.millisecondsSinceEpoch,
    ),
    _ => _ResolvedObject(
      type: model.ObjectType.string,
      stringValue: value.toString(),
    ),
  };
}

/// Extract the display string for an object value from a Drift row.
String _objectValueFromRow(db.Triple row) {
  return switch (row.objectType) {
    'uri' || 'blobRef' => row.objectUri ?? '',
    'string' => row.objectString ?? '',
    'integer' => (row.objectInt ?? 0).toString(),
    'float' || 'real' => (row.objectReal ?? 0.0).toString(),
    'datetime' => DateTime.fromMillisecondsSinceEpoch(
      row.objectInt ?? 0,
    ).toIso8601String(),
    'boolean' => (row.objectInt == 1).toString(),
    _ => row.objectString ?? row.objectUri ?? '',
  };
}

/// Convert the resolved object to a display string.
String _toObjectString(_ResolvedObject obj) {
  return switch (obj.type) {
    model.ObjectType.uri || model.ObjectType.blobRef => obj.uriValue ?? '',
    model.ObjectType.string => obj.stringValue ?? '',
    model.ObjectType.integer => (obj.intValue ?? 0).toString(),
    model.ObjectType.float => (obj.realValue ?? 0.0).toString(),
    model.ObjectType.datetime => DateTime.fromMillisecondsSinceEpoch(
      obj.intValue ?? 0,
    ).toIso8601String(),
    model.ObjectType.boolean => (obj.intValue == 1).toString(),
  };
}

/// Convert a Drift [db.Triple] row to a domain [model.Triple].
model.Triple _tripleFromRow(db.Triple row) {
  return model.Triple(
    subject: row.subject,
    predicate: row.predicate,
    objectValue: _objectValueFromRow(row),
    objectType: _objectTypeFromName(row.objectType),
    graph: row.graph,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
