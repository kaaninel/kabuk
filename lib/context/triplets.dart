import 'dart:async';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class RDFTerminal {
  final String prefix;
  final String name;

  const RDFTerminal(this.prefix, this.name);
  factory RDFTerminal.from(String s) {
    final [prefix, name] = s.split(':');
    return RDFTerminal(prefix, name);
  }

  @override
  String toString() {
    return '$prefix$name';
  }
}

class Subject extends RDFTerminal {
  const Subject(super.prefix, super.name);

  factory Subject.from(String s) {
    final [prefix, name] = s.split(':');
    return Subject(prefix, name);
  }
}

class Verb extends RDFTerminal {
  const Verb(super.prefix, super.name);

  factory Verb.from(String s) {
    final [prefix, name] = s.split(':');
    return Verb(prefix, name);
  }
}

enum ValueType { string, integer, float, date, time, dateTime, boolean, uri }

class Value {
  final ValueType type;
  final String value;
  const Value(this.value, this.type);
}

class Triplet {
  final Subject subject;
  final Verb verb;
  final Value value;

  Triplet(this.subject, this.verb, this.value);

  factory Triplet.fromMap(Map<String, dynamic> map) {
    return Triplet(
      Subject.from(map['subject']),
      Verb.from(map['verb']),
      Value(map['value'], map['valueType']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'subject': subject.toString(),
      'verb': verb.toString(),
      'value': value.toString(),
      'valueType': value.type.toString(),
    };
  }

  @override
  String toString() {
    return 'Triplet{subject: $subject, verb: $verb, value: $value, valueType: ${value.type}}';
  }
}

class TripletRow {
  final String name;
  final int id;
  Triplet? triplet;

  TripletRow(this.name, this.id, this.triplet);

  Future<Triplet> value() async {
    triplet ??= await DB(name).read(id).then((value) => value.triplet!);
    return triplet!;
  }
}

class DB {
  static final Map<String, DB> _instance = {};

  factory DB(String name) =>
      _instance.putIfAbsent(name, () => DB._internal(name));

  final String name;
  Database? _database;

  DB._internal(this.name) {
    _initDatabase();
  }

  Future<void> _initDatabase() async {
    _database = await openDatabase(
      join(await getDatabasesPath(), "kabuk_$name.db"),
      onCreate: _onCreate,
      version: 1,
    );
  }

  FutureOr<void> _onCreate(Database db, int version) async {
    await db.execute(await rootBundle.loadString('assets/sql/graph.sql'));
  }

  Future<void> insert(Triplet triplet) async {
    final db = _database;
    if (db == null) {
      throw Exception("Database not initialized");
    }
    await db.insert('graph', triplet.toMap());
  }

  Future<TripletRow> read(int i) async {
    final db = _database;
    if (db == null) {
      throw Exception("Database not initialized");
    }
    final List<Map<String, dynamic>> maps =
        await db.query('graph', where: 'id = ?', whereArgs: [i], limit: 1);
    if (maps.isEmpty) {
      throw Exception("No such row");
    }
    return TripletRow(name, i, Triplet.fromMap(maps.first));
  }
}
