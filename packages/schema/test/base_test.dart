import 'package:test/test.dart';
import 'package:schema/src/base.dart';

void main() {
  group('Subject', () {
    test('toUri returns the correct value', () {
      final subject = Subject(Uri.parse('http://example.com'));
      expect(subject.toUri(), Uri.parse('http://example.com'));
    });

    test('fromSQL creates correct Subject', () {
      final subject = Subject.fromSQL('http://example.com');
      expect(subject.value.toString(), 'http://example.com');
    });
  });

  group('Object', () {
    test('fromSQL creates RefObject if isRef true', () {
      final obj = Object.fromSQL('http://example.com', true);
      expect(obj, isA<RefObject>());
      expect((obj as RefObject).value.toString(), 'http://example.com');
    });

    test('fromSQL creates StringObject if data is String', () {
      final obj = Object.fromSQL('hello', false);
      expect(obj, isA<StringObject>());
      expect((obj as StringObject).value, 'hello');
    });

    test('fromSQL creates NumberObject if data is num', () {
      final obj = Object.fromSQL(42, false);
      expect(obj, isA<NumberObject>());
      expect((obj as NumberObject).value, 42);
    });

    test('fromSQL creates BooleanObject if data is bool', () {
      final obj = Object.fromSQL(true, false);
      expect(obj, isA<BooleanObject>());
      expect((obj as BooleanObject).value, true);
    });

    test('fromSQL creates DateTimeObject if data is DateTime', () {
      final obj = Object.fromSQL(DateTime.now(), false);
      expect(obj, isA<DateTimeObject>());
    });

    test('fromSQL throws ArgumentError for invalid data type', () {
      expect(() => Object.fromSQL({}, false), throwsArgumentError);
    });
  });

  group('Data', () {
    test('fromSQL with valid data creates correct Data instance', () {
      final data = Data.fromSQL([
        1,
        'http://subject.com',
        'http://object.com',
        'http://predicate.com',
        null,
        true,
        false
      ]);
      expect(data.id, 1);
      expect(data.subject, isNotNull);
      expect(data.object, isA<RefObject>());
      expect(data.predicate.value, Uri.parse('http://predicate.com'));
      expect(data.context, isNull);
    });

    test('toSQL returns correct list', () {
      final subject = Subject(Uri.parse('http://subject.com'));
      final predicate = Predicate(Uri.parse('http://predicate.com'));
      final object = RefObject(Uri.parse('http://object.com'));
      final data = Data(1, subject, object, predicate, null);
      final sql = data.toSQL();
      expect(sql[0], 1);
      expect(sql[1], 'http://subject.com');
      expect(sql[2], 'http://object.com');
      expect(sql[3], 'http://predicate.com');
      expect(sql[4], null);
      expect(sql[5], true);
      expect(sql[6], false);
    });
  });
}
