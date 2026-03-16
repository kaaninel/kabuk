import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/knowledge/triple.dart';

void main() {
  group('Triple', () {
    // -----------------------------------------------------------------------
    // Primary constructor
    // -----------------------------------------------------------------------

    group('primary constructor', () {
      test('stores all required fields', () {
        const triple = Triple(
          subject: 'kabuk:Note/1',
          predicate: 'schema:name',
          objectValue: 'My Note',
          objectType: ObjectType.string,
        );
        expect(triple.subject, 'kabuk:Note/1');
        expect(triple.predicate, 'schema:name');
        expect(triple.objectValue, 'My Note');
        expect(triple.objectType, ObjectType.string);
      });

      test('defaults graph to "default"', () {
        const triple = Triple(
          subject: 's',
          predicate: 'p',
          objectValue: 'o',
          objectType: ObjectType.string,
        );
        expect(triple.graph, 'default');
      });

      test('defaults encrypted to false', () {
        const triple = Triple(
          subject: 's',
          predicate: 'p',
          objectValue: 'o',
          objectType: ObjectType.string,
        );
        expect(triple.encrypted, isFalse);
      });

      test('optional fields are null by default', () {
        const triple = Triple(
          subject: 's',
          predicate: 'p',
          objectValue: 'o',
          objectType: ObjectType.string,
        );
        expect(triple.id, isNull);
        expect(triple.objectLang, isNull);
        expect(triple.objectDatatype, isNull);
        expect(triple.createdAt, isNull);
        expect(triple.updatedAt, isNull);
      });
    });

    // -----------------------------------------------------------------------
    // Named constructors
    // -----------------------------------------------------------------------

    group('Triple.uri', () {
      test('sets objectType to uri', () {
        const triple = Triple.uri(
          subject: 'kabuk:Note/1',
          predicate: 'schema:author',
          object: 'kabuk:Person/2',
        );
        expect(triple.objectType, ObjectType.uri);
        expect(triple.objectValue, 'kabuk:Person/2');
        expect(triple.objectLang, isNull);
        expect(triple.objectDatatype, isNull);
      });
    });

    group('Triple.string', () {
      test('sets objectType to string', () {
        const triple = Triple.string(
          subject: 'kabuk:Note/1',
          predicate: 'schema:name',
          object: 'Hello World',
        );
        expect(triple.objectType, ObjectType.string);
        expect(triple.objectValue, 'Hello World');
      });

      test('supports objectLang', () {
        const triple = Triple.string(
          subject: 'kabuk:Note/1',
          predicate: 'schema:name',
          object: 'Merhaba',
          objectLang: 'tr',
        );
        expect(triple.objectLang, 'tr');
      });
    });

    group('Triple.integer', () {
      test('converts int to string objectValue', () {
        final triple = Triple.integer(
          subject: 's',
          predicate: 'schema:wordCount',
          object: 42,
        );
        expect(triple.objectType, ObjectType.integer);
        expect(triple.objectValue, '42');
      });
    });

    group('Triple.float', () {
      test('converts double to string objectValue', () {
        final triple = Triple.float(
          subject: 's',
          predicate: 'schema:price',
          object: 3.14,
        );
        expect(triple.objectType, ObjectType.float);
        expect(triple.objectValue, '3.14');
      });
    });

    group('Triple.datetime', () {
      test('converts DateTime to ISO 8601 string', () {
        final dt = DateTime.utc(2026, 2, 25, 12, 0, 0);
        final triple = Triple.datetime(
          subject: 's',
          predicate: 'schema:dateCreated',
          object: dt,
        );
        expect(triple.objectType, ObjectType.datetime);
        expect(triple.objectValue, dt.toIso8601String());
      });
    });

    group('Triple.boolean', () {
      test('converts true to "true"', () {
        final triple = Triple.boolean(
          subject: 's',
          predicate: 'kabuk:pinned',
          object: true,
        );
        expect(triple.objectType, ObjectType.boolean);
        expect(triple.objectValue, 'true');
      });

      test('converts false to "false"', () {
        final triple = Triple.boolean(
          subject: 's',
          predicate: 'kabuk:pinned',
          object: false,
        );
        expect(triple.objectValue, 'false');
      });
    });

    group('Triple.blobRef', () {
      test('stores hash as objectValue', () {
        const triple = Triple.blobRef(
          subject: 's',
          predicate: 'kabuk:attachment',
          hash: 'sha256:abcdef1234567890',
        );
        expect(triple.objectType, ObjectType.blobRef);
        expect(triple.objectValue, 'sha256:abcdef1234567890');
      });
    });

    // -----------------------------------------------------------------------
    // copyWith
    // -----------------------------------------------------------------------

    group('copyWith', () {
      const original = Triple(
        id: 1,
        subject: 'kabuk:Note/1',
        predicate: 'schema:name',
        objectValue: 'Original',
        objectType: ObjectType.string,
        graph: 'default',
        encrypted: false,
      );

      test('returns identical copy when no args provided', () {
        final copy = original.copyWith();
        expect(copy, equals(original));
      });

      test('overrides subject', () {
        final copy = original.copyWith(subject: 'kabuk:Note/2');
        expect(copy.subject, 'kabuk:Note/2');
        expect(copy.predicate, original.predicate);
      });

      test('overrides objectValue', () {
        final copy = original.copyWith(objectValue: 'New Value');
        expect(copy.objectValue, 'New Value');
      });

      test('overrides encrypted', () {
        final copy = original.copyWith(encrypted: true);
        expect(copy.encrypted, isTrue);
      });

      test('overrides id', () {
        final copy = original.copyWith(id: 99);
        expect(copy.id, 99);
      });

      test('overrides graph', () {
        final copy = original.copyWith(graph: 'private');
        expect(copy.graph, 'private');
      });

      test('overrides createdAt and updatedAt', () {
        final now = DateTime.now();
        final copy = original.copyWith(createdAt: now, updatedAt: now);
        expect(copy.createdAt, now);
        expect(copy.updatedAt, now);
      });
    });

    // -----------------------------------------------------------------------
    // Equality
    // -----------------------------------------------------------------------

    group('equality', () {
      test('two triples with same fields are equal', () {
        const a = Triple(
          id: 1,
          subject: 's',
          predicate: 'p',
          objectValue: 'o',
          objectType: ObjectType.string,
        );
        const b = Triple(
          id: 1,
          subject: 's',
          predicate: 'p',
          objectValue: 'o',
          objectType: ObjectType.string,
        );
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      });

      test('triples with different ids are not equal', () {
        const a = Triple(
          id: 1,
          subject: 's',
          predicate: 'p',
          objectValue: 'o',
          objectType: ObjectType.string,
        );
        const b = Triple(
          id: 2,
          subject: 's',
          predicate: 'p',
          objectValue: 'o',
          objectType: ObjectType.string,
        );
        expect(a, isNot(equals(b)));
      });

      test('triples with different objectType are not equal', () {
        const a = Triple(
          subject: 's',
          predicate: 'p',
          objectValue: 'o',
          objectType: ObjectType.string,
        );
        const b = Triple(
          subject: 's',
          predicate: 'p',
          objectValue: 'o',
          objectType: ObjectType.uri,
        );
        expect(a, isNot(equals(b)));
      });

      test('triples with different encrypted flag are not equal', () {
        const a = Triple(
          subject: 's',
          predicate: 'p',
          objectValue: 'o',
          objectType: ObjectType.string,
          encrypted: false,
        );
        const b = Triple(
          subject: 's',
          predicate: 'p',
          objectValue: 'o',
          objectType: ObjectType.string,
          encrypted: true,
        );
        expect(a, isNot(equals(b)));
      });
    });

    // -----------------------------------------------------------------------
    // toString
    // -----------------------------------------------------------------------

    group('toString', () {
      test('includes subject, predicate, objectValue and objectType', () {
        const triple = Triple.string(
          subject: 'kabuk:Note/1',
          predicate: 'schema:name',
          object: 'Test',
        );
        final str = triple.toString();
        expect(str, contains('kabuk:Note/1'));
        expect(str, contains('schema:name'));
        expect(str, contains('Test'));
        expect(str, contains('string'));
      });

      test('includes graph when not default', () {
        const triple = Triple.string(
          subject: 's',
          predicate: 'p',
          object: 'o',
          graph: 'private',
        );
        expect(triple.toString(), contains('graph=private'));
      });

      test('omits graph when default', () {
        const triple = Triple.string(subject: 's', predicate: 'p', object: 'o');
        expect(triple.toString(), isNot(contains('graph=')));
      });

      test('includes encrypted flag when true', () {
        const triple = Triple.string(
          subject: 's',
          predicate: 'p',
          object: 'o',
          encrypted: true,
        );
        expect(triple.toString(), contains('encrypted'));
      });

      test('omits encrypted flag when false', () {
        const triple = Triple.string(subject: 's', predicate: 'p', object: 'o');
        // Should not contain ', encrypted' (the flag suffix)
        expect(triple.toString(), isNot(contains(', encrypted')));
      });
    });
  });

  // -------------------------------------------------------------------------
  // ObjectType enum
  // -------------------------------------------------------------------------

  group('ObjectType', () {
    test('has all expected values', () {
      expect(
        ObjectType.values,
        containsAll([
          ObjectType.uri,
          ObjectType.string,
          ObjectType.integer,
          ObjectType.float,
          ObjectType.datetime,
          ObjectType.boolean,
          ObjectType.blobRef,
        ]),
      );
    });
  });
}
