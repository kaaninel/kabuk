mixin Ref {
  Uri get value;

  Uri toUri() => value;
  dynamic toSQL() => toString();

  @override
  String toString() {
    return value.toString();
  }
}

class Subject with Ref {
  @override
  final Uri value;
  const Subject(this.value);
  factory Subject.fromSQL(String sql) => Subject(Uri.parse(sql));
  factory Subject.ref(String uri) => Subject(Uri.parse(uri));

  RefObject toRefObject() => RefObject(value);
}

sealed class Object {
  const Object();
  factory Object.ref(String uri) => RefObject(Uri.parse(uri));
  factory Object.fromSQL(dynamic data, bool isRef) {
    if (isRef) {
      return RefObject(Uri.parse(data));
    } else if (data is String) {
      return StringObject.fromSQL(data);
    } else if (data is num) {
      return NumberObject.fromSQL(data);
    } else if (data is bool) {
      return BooleanObject.fromSQL(data);
    } else if (data is DateTime) {
      return DateTimeObject.fromSQL(data.toIso8601String());
    } else {
      throw ArgumentError('Invalid data type');
    }
  }
  dynamic toSQL();
}

final class RefObject extends Object with Ref {
  @override
  final Uri value;

  const RefObject(this.value);

  Subject toSubject() => Subject(value);
}

sealed class LiteralObject extends Object {
  const LiteralObject();
}

final class StringObject extends LiteralObject {
  final String value;
  const StringObject(this.value);
  factory StringObject.fromSQL(String sql) => StringObject(sql);

  @override
  dynamic toSQL() => value;
}

final class NumberObject extends LiteralObject {
  final num value;
  const NumberObject(this.value);
  factory NumberObject.fromSQL(num sql) => NumberObject(sql);

  @override
  dynamic toSQL() => value is int ? value : value.toDouble();
}

final class BooleanObject extends LiteralObject {
  final bool value;
  const BooleanObject(this.value);
  factory BooleanObject.fromSQL(bool sql) => BooleanObject(sql);

  @override
  dynamic toSQL() => value;
}

final class DateTimeObject extends LiteralObject {
  final DateTime value;
  const DateTimeObject(this.value);
  factory DateTimeObject.fromSQL(String sql) =>
      DateTimeObject(DateTime.parse(sql));

  @override
  dynamic toSQL() => value.toIso8601String();
}

class Predicate with Ref {
  @override
  final Uri value;

  const Predicate(this.value);
  factory Predicate.fromSQL(String sql) => Predicate(Uri.parse(sql));
  factory Predicate.ref(String uri) => Predicate(Uri.parse(uri));
  factory Predicate.schema(String schema) =>
      Predicate(Uri.https('schema.org', schema));
}

class Data {
  final int? id;
  final Subject? subject;
  final Object object;
  final Predicate predicate;
  final Object? context;

  const Data(this.id, this.subject, this.object, this.predicate, this.context);

  factory Data.fromSQL(List<dynamic> sql) {
    return Data(
      sql[0] as int?,
      sql[1] == null ? null : Subject.fromSQL(sql[1]),
      Object.fromSQL(sql[2], sql[5]),
      Predicate.fromSQL(sql[3]),
      sql[4] == null ? null : Object.fromSQL(sql[4], sql[6]),
    );
  }

  List<dynamic> toSQL() {
    return [
      id,
      subject?.toSQL(),
      object.toSQL(),
      predicate.toSQL(),
      context?.toSQL(),
      object is Ref,
      context is Ref,
    ];
  }
}
