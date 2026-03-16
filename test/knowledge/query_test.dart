import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/knowledge/query.dart';
import 'package:kabuk/knowledge/triple.dart';

void main() {
  group('QueryBuilder', () {
    late QueryBuilder builder;

    setUp(() {
      builder = QueryBuilder();
    });

    // -----------------------------------------------------------------------
    // Initial state
    // -----------------------------------------------------------------------

    group('initial state', () {
      test('all filters are null by default', () {
        expect(builder.subjectFilter, isNull);
        expect(builder.predicateFilter, isNull);
        expect(builder.objectFilter, isNull);
        expect(builder.objectTypeFilter, isNull);
        expect(builder.graphFilter, isNull);
        expect(builder.limitValue, isNull);
        expect(builder.offsetValue, isNull);
      });

      test('clauses, orderings, and follows are empty', () {
        expect(builder.clauses, isEmpty);
        expect(builder.orderings, isEmpty);
        expect(builder.follows, isEmpty);
      });
    });

    // -----------------------------------------------------------------------
    // subject / predicate / object filters
    // -----------------------------------------------------------------------

    group('subject()', () {
      test('sets the subject filter', () {
        final result = builder.subject('kabuk:Note/abc');
        expect(builder.subjectFilter, 'kabuk:Note/abc');
        expect(
          result,
          same(builder),
          reason: 'should return this for chaining',
        );
      });
    });

    group('predicate()', () {
      test('sets the predicate filter', () {
        builder.predicate('schema:name');
        expect(builder.predicateFilter, 'schema:name');
      });
    });

    group('object()', () {
      test('sets the object filter', () {
        builder.object('Alice');
        expect(builder.objectFilter, 'Alice');
      });
    });

    group('objectType()', () {
      test('sets the object type filter', () {
        builder.objectType(ObjectType.uri);
        expect(builder.objectTypeFilter, ObjectType.uri);
      });
    });

    group('graph()', () {
      test('sets the graph filter', () {
        builder.graph('private');
        expect(builder.graphFilter, 'private');
      });
    });

    // -----------------------------------------------------------------------
    // where / whereType
    // -----------------------------------------------------------------------

    group('where()', () {
      test('adds an equals clause', () {
        builder.where('schema:name', equals: 'Alice');
        expect(builder.clauses, hasLength(1));
        expect(builder.clauses.first.predicate, 'schema:name');
        expect(builder.clauses.first.equals, 'Alice');
        expect(builder.clauses.first.contains, isNull);
      });

      test('adds a contains clause', () {
        builder.where('schema:text', contains: 'hello');
        expect(builder.clauses.first.contains, 'hello');
      });

      test('adds greaterThan and lessThan', () {
        builder.where('schema:price', greaterThan: '10', lessThan: '100');
        final clause = builder.clauses.first;
        expect(clause.greaterThan, '10');
        expect(clause.lessThan, '100');
      });

      test('accumulates multiple clauses', () {
        builder
            .where('schema:name', equals: 'Alice')
            .where('schema:email', contains: '@');
        expect(builder.clauses, hasLength(2));
      });
    });

    group('whereType()', () {
      test('adds an rdf:type equals clause', () {
        builder.whereType('schema:Person');
        expect(builder.clauses, hasLength(1));
        expect(builder.clauses.first.predicate, 'rdf:type');
        expect(builder.clauses.first.equals, 'schema:Person');
      });
    });

    // -----------------------------------------------------------------------
    // orderBy
    // -----------------------------------------------------------------------

    group('orderBy()', () {
      test('adds an ascending ordering', () {
        builder.orderBy('schema:name');
        expect(builder.orderings, hasLength(1));
        expect(builder.orderings.first.predicate, 'schema:name');
        expect(builder.orderings.first.descending, isFalse);
      });

      test('adds a descending ordering', () {
        builder.orderBy('schema:dateCreated', descending: true);
        expect(builder.orderings.first.descending, isTrue);
      });

      test('accumulates multiple orderings', () {
        builder.orderBy('schema:name').orderBy('schema:dateCreated');
        expect(builder.orderings, hasLength(2));
      });
    });

    // -----------------------------------------------------------------------
    // limit / offset
    // -----------------------------------------------------------------------

    group('limit()', () {
      test('sets the limit', () {
        builder.limit(25);
        expect(builder.limitValue, 25);
      });
    });

    group('offset()', () {
      test('sets the offset', () {
        builder.offset(50);
        expect(builder.offsetValue, 50);
      });
    });

    // -----------------------------------------------------------------------
    // follow
    // -----------------------------------------------------------------------

    group('follow()', () {
      test('adds a follow predicate', () {
        builder.follow('schema:knows');
        expect(builder.follows, ['schema:knows']);
      });

      test('accumulates multiple follows', () {
        builder.follow('schema:knows').follow('schema:worksFor');
        expect(builder.follows, hasLength(2));
      });
    });

    // -----------------------------------------------------------------------
    // Chaining
    // -----------------------------------------------------------------------

    group('chaining', () {
      test('full query chain sets all accumulated state correctly', () {
        builder
            .subject('kabuk:Note/1')
            .predicate('schema:name')
            .whereType('schema:NoteDigitalDocument')
            .where('schema:text', contains: 'hello')
            .orderBy('schema:dateCreated', descending: true)
            .limit(10)
            .offset(5)
            .follow('schema:author');

        expect(builder.subjectFilter, 'kabuk:Note/1');
        expect(builder.predicateFilter, 'schema:name');
        expect(builder.clauses, hasLength(2)); // whereType + where
        expect(builder.orderings, hasLength(1));
        expect(builder.limitValue, 10);
        expect(builder.offsetValue, 5);
        expect(builder.follows, ['schema:author']);
      });
    });

    // -----------------------------------------------------------------------
    // Unmodifiable accessors
    // -----------------------------------------------------------------------

    group('immutability of accessors', () {
      test('clauses list is unmodifiable', () {
        builder.where('schema:name', equals: 'Alice');
        expect(
          () => builder.clauses.add(const QueryClause(predicate: 'x')),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('orderings list is unmodifiable', () {
        builder.orderBy('schema:name');
        expect(
          () => builder.orderings.add(const QueryOrdering(predicate: 'x')),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('follows list is unmodifiable', () {
        builder.follow('schema:knows');
        expect(
          () => builder.follows.add('schema:worksFor'),
          throwsA(isA<UnsupportedError>()),
        );
      });
    });

    // -----------------------------------------------------------------------
    // Terminal operations (should throw without store)
    // -----------------------------------------------------------------------

    group('terminal operations throw without store', () {
      test('execute() throws UnimplementedError', () {
        expect(() => builder.execute(), throwsUnimplementedError);
      });

      test('first() throws UnimplementedError', () {
        expect(() => builder.first(), throwsUnimplementedError);
      });

      test('count() throws UnimplementedError', () {
        expect(() => builder.count(), throwsUnimplementedError);
      });

      test('stream() throws UnimplementedError', () {
        expect(() => builder.stream(), throwsUnimplementedError);
      });
    });
  });

  // -------------------------------------------------------------------------
  // QueryClause
  // -------------------------------------------------------------------------

  group('QueryClause', () {
    test('stores all filter fields', () {
      const clause = QueryClause(
        predicate: 'schema:price',
        equals: '42',
        contains: '4',
        greaterThan: '10',
        lessThan: '100',
      );
      expect(clause.predicate, 'schema:price');
      expect(clause.equals, '42');
      expect(clause.contains, '4');
      expect(clause.greaterThan, '10');
      expect(clause.lessThan, '100');
    });

    test('optional fields default to null', () {
      const clause = QueryClause(predicate: 'schema:name');
      expect(clause.equals, isNull);
      expect(clause.contains, isNull);
      expect(clause.greaterThan, isNull);
      expect(clause.lessThan, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // QueryOrdering
  // -------------------------------------------------------------------------

  group('QueryOrdering', () {
    test('ascending by default', () {
      const ordering = QueryOrdering(predicate: 'schema:name');
      expect(ordering.descending, isFalse);
    });

    test('can be descending', () {
      const ordering = QueryOrdering(
        predicate: 'schema:date',
        descending: true,
      );
      expect(ordering.descending, isTrue);
    });
  });
}
