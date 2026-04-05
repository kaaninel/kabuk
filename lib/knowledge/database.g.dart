// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $TriplesTable extends Triples with TableInfo<$TriplesTable, Triple> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TriplesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _predicateMeta = const VerificationMeta(
    'predicate',
  );
  @override
  late final GeneratedColumn<String> predicate = GeneratedColumn<String>(
    'predicate',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _objectTypeMeta = const VerificationMeta(
    'objectType',
  );
  @override
  late final GeneratedColumn<String> objectType = GeneratedColumn<String>(
    'object_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _objectUriMeta = const VerificationMeta(
    'objectUri',
  );
  @override
  late final GeneratedColumn<String> objectUri = GeneratedColumn<String>(
    'object_uri',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _objectStringMeta = const VerificationMeta(
    'objectString',
  );
  @override
  late final GeneratedColumn<String> objectString = GeneratedColumn<String>(
    'object_string',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _objectIntMeta = const VerificationMeta(
    'objectInt',
  );
  @override
  late final GeneratedColumn<int> objectInt = GeneratedColumn<int>(
    'object_int',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _objectRealMeta = const VerificationMeta(
    'objectReal',
  );
  @override
  late final GeneratedColumn<double> objectReal = GeneratedColumn<double>(
    'object_real',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _graphMeta = const VerificationMeta('graph');
  @override
  late final GeneratedColumn<String> graph = GeneratedColumn<String>(
    'graph',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('default'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _syncVersionMeta = const VerificationMeta(
    'syncVersion',
  );
  @override
  late final GeneratedColumn<int> syncVersion = GeneratedColumn<int>(
    'sync_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    subject,
    predicate,
    objectType,
    objectUri,
    objectString,
    objectInt,
    objectReal,
    graph,
    createdAt,
    updatedAt,
    syncVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'triples';
  @override
  VerificationContext validateIntegrity(
    Insertable<Triple> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('predicate')) {
      context.handle(
        _predicateMeta,
        predicate.isAcceptableOrUnknown(data['predicate']!, _predicateMeta),
      );
    } else if (isInserting) {
      context.missing(_predicateMeta);
    }
    if (data.containsKey('object_type')) {
      context.handle(
        _objectTypeMeta,
        objectType.isAcceptableOrUnknown(data['object_type']!, _objectTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_objectTypeMeta);
    }
    if (data.containsKey('object_uri')) {
      context.handle(
        _objectUriMeta,
        objectUri.isAcceptableOrUnknown(data['object_uri']!, _objectUriMeta),
      );
    }
    if (data.containsKey('object_string')) {
      context.handle(
        _objectStringMeta,
        objectString.isAcceptableOrUnknown(
          data['object_string']!,
          _objectStringMeta,
        ),
      );
    }
    if (data.containsKey('object_int')) {
      context.handle(
        _objectIntMeta,
        objectInt.isAcceptableOrUnknown(data['object_int']!, _objectIntMeta),
      );
    }
    if (data.containsKey('object_real')) {
      context.handle(
        _objectRealMeta,
        objectReal.isAcceptableOrUnknown(data['object_real']!, _objectRealMeta),
      );
    }
    if (data.containsKey('graph')) {
      context.handle(
        _graphMeta,
        graph.isAcceptableOrUnknown(data['graph']!, _graphMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('sync_version')) {
      context.handle(
        _syncVersionMeta,
        syncVersion.isAcceptableOrUnknown(
          data['sync_version']!,
          _syncVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {
      subject,
      predicate,
      objectType,
      objectUri,
      objectString,
      objectInt,
      objectReal,
      graph,
    },
  ];
  @override
  Triple map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Triple(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      )!,
      predicate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}predicate'],
      )!,
      objectType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}object_type'],
      )!,
      objectUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}object_uri'],
      ),
      objectString: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}object_string'],
      ),
      objectInt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}object_int'],
      ),
      objectReal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}object_real'],
      ),
      graph: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}graph'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      syncVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_version'],
      )!,
    );
  }

  @override
  $TriplesTable createAlias(String alias) {
    return $TriplesTable(attachedDatabase, alias);
  }
}

class Triple extends DataClass implements Insertable<Triple> {
  /// Auto-incrementing primary key.
  final int id;

  /// The subject URI of the triple.
  final String subject;

  /// The predicate URI of the triple.
  final String predicate;

  /// The type of the object value.
  ///
  /// One of: `uri`, `string`, `integer`, `real`, `datetime`, `boolean`,
  /// `blobRef`.
  final String objectType;

  /// Object value when [objectType] is `uri` or `blobRef`.
  final String? objectUri;

  /// Object value when [objectType] is `string`.
  final String? objectString;

  /// Object value when [objectType] is `integer`, `boolean`, or `datetime`.
  ///
  /// Booleans are stored as 0/1. DateTimes are stored as milliseconds
  /// since epoch.
  final int? objectInt;

  /// Object value when [objectType] is `real`.
  final double? objectReal;

  /// The named graph this triple belongs to (optional).
  final String graph;

  /// Timestamp when this triple was created.
  final DateTime createdAt;

  /// Timestamp when this triple was last updated.
  final DateTime updatedAt;

  /// Monotonically increasing version counter for sync.
  ///
  /// Incremented on each mutation. Remote peers request changes
  /// `WHERE sync_version > lastKnownVersion` to get deltas.
  final int syncVersion;
  const Triple({
    required this.id,
    required this.subject,
    required this.predicate,
    required this.objectType,
    this.objectUri,
    this.objectString,
    this.objectInt,
    this.objectReal,
    required this.graph,
    required this.createdAt,
    required this.updatedAt,
    required this.syncVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['subject'] = Variable<String>(subject);
    map['predicate'] = Variable<String>(predicate);
    map['object_type'] = Variable<String>(objectType);
    if (!nullToAbsent || objectUri != null) {
      map['object_uri'] = Variable<String>(objectUri);
    }
    if (!nullToAbsent || objectString != null) {
      map['object_string'] = Variable<String>(objectString);
    }
    if (!nullToAbsent || objectInt != null) {
      map['object_int'] = Variable<int>(objectInt);
    }
    if (!nullToAbsent || objectReal != null) {
      map['object_real'] = Variable<double>(objectReal);
    }
    map['graph'] = Variable<String>(graph);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['sync_version'] = Variable<int>(syncVersion);
    return map;
  }

  TriplesCompanion toCompanion(bool nullToAbsent) {
    return TriplesCompanion(
      id: Value(id),
      subject: Value(subject),
      predicate: Value(predicate),
      objectType: Value(objectType),
      objectUri: objectUri == null && nullToAbsent
          ? const Value.absent()
          : Value(objectUri),
      objectString: objectString == null && nullToAbsent
          ? const Value.absent()
          : Value(objectString),
      objectInt: objectInt == null && nullToAbsent
          ? const Value.absent()
          : Value(objectInt),
      objectReal: objectReal == null && nullToAbsent
          ? const Value.absent()
          : Value(objectReal),
      graph: Value(graph),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      syncVersion: Value(syncVersion),
    );
  }

  factory Triple.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Triple(
      id: serializer.fromJson<int>(json['id']),
      subject: serializer.fromJson<String>(json['subject']),
      predicate: serializer.fromJson<String>(json['predicate']),
      objectType: serializer.fromJson<String>(json['objectType']),
      objectUri: serializer.fromJson<String?>(json['objectUri']),
      objectString: serializer.fromJson<String?>(json['objectString']),
      objectInt: serializer.fromJson<int?>(json['objectInt']),
      objectReal: serializer.fromJson<double?>(json['objectReal']),
      graph: serializer.fromJson<String>(json['graph']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      syncVersion: serializer.fromJson<int>(json['syncVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'subject': serializer.toJson<String>(subject),
      'predicate': serializer.toJson<String>(predicate),
      'objectType': serializer.toJson<String>(objectType),
      'objectUri': serializer.toJson<String?>(objectUri),
      'objectString': serializer.toJson<String?>(objectString),
      'objectInt': serializer.toJson<int?>(objectInt),
      'objectReal': serializer.toJson<double?>(objectReal),
      'graph': serializer.toJson<String>(graph),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'syncVersion': serializer.toJson<int>(syncVersion),
    };
  }

  Triple copyWith({
    int? id,
    String? subject,
    String? predicate,
    String? objectType,
    Value<String?> objectUri = const Value.absent(),
    Value<String?> objectString = const Value.absent(),
    Value<int?> objectInt = const Value.absent(),
    Value<double?> objectReal = const Value.absent(),
    String? graph,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? syncVersion,
  }) => Triple(
    id: id ?? this.id,
    subject: subject ?? this.subject,
    predicate: predicate ?? this.predicate,
    objectType: objectType ?? this.objectType,
    objectUri: objectUri.present ? objectUri.value : this.objectUri,
    objectString: objectString.present ? objectString.value : this.objectString,
    objectInt: objectInt.present ? objectInt.value : this.objectInt,
    objectReal: objectReal.present ? objectReal.value : this.objectReal,
    graph: graph ?? this.graph,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncVersion: syncVersion ?? this.syncVersion,
  );
  Triple copyWithCompanion(TriplesCompanion data) {
    return Triple(
      id: data.id.present ? data.id.value : this.id,
      subject: data.subject.present ? data.subject.value : this.subject,
      predicate: data.predicate.present ? data.predicate.value : this.predicate,
      objectType: data.objectType.present
          ? data.objectType.value
          : this.objectType,
      objectUri: data.objectUri.present ? data.objectUri.value : this.objectUri,
      objectString: data.objectString.present
          ? data.objectString.value
          : this.objectString,
      objectInt: data.objectInt.present ? data.objectInt.value : this.objectInt,
      objectReal: data.objectReal.present
          ? data.objectReal.value
          : this.objectReal,
      graph: data.graph.present ? data.graph.value : this.graph,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      syncVersion: data.syncVersion.present
          ? data.syncVersion.value
          : this.syncVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Triple(')
          ..write('id: $id, ')
          ..write('subject: $subject, ')
          ..write('predicate: $predicate, ')
          ..write('objectType: $objectType, ')
          ..write('objectUri: $objectUri, ')
          ..write('objectString: $objectString, ')
          ..write('objectInt: $objectInt, ')
          ..write('objectReal: $objectReal, ')
          ..write('graph: $graph, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('syncVersion: $syncVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    subject,
    predicate,
    objectType,
    objectUri,
    objectString,
    objectInt,
    objectReal,
    graph,
    createdAt,
    updatedAt,
    syncVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Triple &&
          other.id == this.id &&
          other.subject == this.subject &&
          other.predicate == this.predicate &&
          other.objectType == this.objectType &&
          other.objectUri == this.objectUri &&
          other.objectString == this.objectString &&
          other.objectInt == this.objectInt &&
          other.objectReal == this.objectReal &&
          other.graph == this.graph &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.syncVersion == this.syncVersion);
}

class TriplesCompanion extends UpdateCompanion<Triple> {
  final Value<int> id;
  final Value<String> subject;
  final Value<String> predicate;
  final Value<String> objectType;
  final Value<String?> objectUri;
  final Value<String?> objectString;
  final Value<int?> objectInt;
  final Value<double?> objectReal;
  final Value<String> graph;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> syncVersion;
  const TriplesCompanion({
    this.id = const Value.absent(),
    this.subject = const Value.absent(),
    this.predicate = const Value.absent(),
    this.objectType = const Value.absent(),
    this.objectUri = const Value.absent(),
    this.objectString = const Value.absent(),
    this.objectInt = const Value.absent(),
    this.objectReal = const Value.absent(),
    this.graph = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.syncVersion = const Value.absent(),
  });
  TriplesCompanion.insert({
    this.id = const Value.absent(),
    required String subject,
    required String predicate,
    required String objectType,
    this.objectUri = const Value.absent(),
    this.objectString = const Value.absent(),
    this.objectInt = const Value.absent(),
    this.objectReal = const Value.absent(),
    this.graph = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.syncVersion = const Value.absent(),
  }) : subject = Value(subject),
       predicate = Value(predicate),
       objectType = Value(objectType);
  static Insertable<Triple> custom({
    Expression<int>? id,
    Expression<String>? subject,
    Expression<String>? predicate,
    Expression<String>? objectType,
    Expression<String>? objectUri,
    Expression<String>? objectString,
    Expression<int>? objectInt,
    Expression<double>? objectReal,
    Expression<String>? graph,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? syncVersion,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (subject != null) 'subject': subject,
      if (predicate != null) 'predicate': predicate,
      if (objectType != null) 'object_type': objectType,
      if (objectUri != null) 'object_uri': objectUri,
      if (objectString != null) 'object_string': objectString,
      if (objectInt != null) 'object_int': objectInt,
      if (objectReal != null) 'object_real': objectReal,
      if (graph != null) 'graph': graph,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (syncVersion != null) 'sync_version': syncVersion,
    });
  }

  TriplesCompanion copyWith({
    Value<int>? id,
    Value<String>? subject,
    Value<String>? predicate,
    Value<String>? objectType,
    Value<String?>? objectUri,
    Value<String?>? objectString,
    Value<int?>? objectInt,
    Value<double?>? objectReal,
    Value<String>? graph,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? syncVersion,
  }) {
    return TriplesCompanion(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      predicate: predicate ?? this.predicate,
      objectType: objectType ?? this.objectType,
      objectUri: objectUri ?? this.objectUri,
      objectString: objectString ?? this.objectString,
      objectInt: objectInt ?? this.objectInt,
      objectReal: objectReal ?? this.objectReal,
      graph: graph ?? this.graph,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncVersion: syncVersion ?? this.syncVersion,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (predicate.present) {
      map['predicate'] = Variable<String>(predicate.value);
    }
    if (objectType.present) {
      map['object_type'] = Variable<String>(objectType.value);
    }
    if (objectUri.present) {
      map['object_uri'] = Variable<String>(objectUri.value);
    }
    if (objectString.present) {
      map['object_string'] = Variable<String>(objectString.value);
    }
    if (objectInt.present) {
      map['object_int'] = Variable<int>(objectInt.value);
    }
    if (objectReal.present) {
      map['object_real'] = Variable<double>(objectReal.value);
    }
    if (graph.present) {
      map['graph'] = Variable<String>(graph.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (syncVersion.present) {
      map['sync_version'] = Variable<int>(syncVersion.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TriplesCompanion(')
          ..write('id: $id, ')
          ..write('subject: $subject, ')
          ..write('predicate: $predicate, ')
          ..write('objectType: $objectType, ')
          ..write('objectUri: $objectUri, ')
          ..write('objectString: $objectString, ')
          ..write('objectInt: $objectInt, ')
          ..write('objectReal: $objectReal, ')
          ..write('graph: $graph, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('syncVersion: $syncVersion')
          ..write(')'))
        .toString();
  }
}

class $BlobsTable extends Blobs with TableInfo<$BlobsTable, Blob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BlobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _hashMeta = const VerificationMeta('hash');
  @override
  late final GeneratedColumn<String> hash = GeneratedColumn<String>(
    'hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<Uint8List> data = GeneratedColumn<Uint8List>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [hash, data, mimeType, size, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'blobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Blob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('hash')) {
      context.handle(
        _hashMeta,
        hash.isAcceptableOrUnknown(data['hash']!, _hashMeta),
      );
    } else if (isInserting) {
      context.missing(_hashMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {hash};
  @override
  Blob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Blob(
      hash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hash'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}data'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $BlobsTable createAlias(String alias) {
    return $BlobsTable(attachedDatabase, alias);
  }
}

class Blob extends DataClass implements Insertable<Blob> {
  /// SHA-256 content hash — the primary key.
  final String hash;

  /// The binary data.
  final Uint8List data;

  /// MIME type of the blob (e.g. `image/png`).
  final String? mimeType;

  /// Size in bytes.
  final int size;

  /// Timestamp when the blob was stored.
  final DateTime createdAt;
  const Blob({
    required this.hash,
    required this.data,
    this.mimeType,
    required this.size,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['hash'] = Variable<String>(hash);
    map['data'] = Variable<Uint8List>(data);
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    map['size'] = Variable<int>(size);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  BlobsCompanion toCompanion(bool nullToAbsent) {
    return BlobsCompanion(
      hash: Value(hash),
      data: Value(data),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      size: Value(size),
      createdAt: Value(createdAt),
    );
  }

  factory Blob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Blob(
      hash: serializer.fromJson<String>(json['hash']),
      data: serializer.fromJson<Uint8List>(json['data']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      size: serializer.fromJson<int>(json['size']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'hash': serializer.toJson<String>(hash),
      'data': serializer.toJson<Uint8List>(data),
      'mimeType': serializer.toJson<String?>(mimeType),
      'size': serializer.toJson<int>(size),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Blob copyWith({
    String? hash,
    Uint8List? data,
    Value<String?> mimeType = const Value.absent(),
    int? size,
    DateTime? createdAt,
  }) => Blob(
    hash: hash ?? this.hash,
    data: data ?? this.data,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    size: size ?? this.size,
    createdAt: createdAt ?? this.createdAt,
  );
  Blob copyWithCompanion(BlobsCompanion data) {
    return Blob(
      hash: data.hash.present ? data.hash.value : this.hash,
      data: data.data.present ? data.data.value : this.data,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      size: data.size.present ? data.size.value : this.size,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Blob(')
          ..write('hash: $hash, ')
          ..write('data: $data, ')
          ..write('mimeType: $mimeType, ')
          ..write('size: $size, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    hash,
    $driftBlobEquality.hash(data),
    mimeType,
    size,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Blob &&
          other.hash == this.hash &&
          $driftBlobEquality.equals(other.data, this.data) &&
          other.mimeType == this.mimeType &&
          other.size == this.size &&
          other.createdAt == this.createdAt);
}

class BlobsCompanion extends UpdateCompanion<Blob> {
  final Value<String> hash;
  final Value<Uint8List> data;
  final Value<String?> mimeType;
  final Value<int> size;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const BlobsCompanion({
    this.hash = const Value.absent(),
    this.data = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.size = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BlobsCompanion.insert({
    required String hash,
    required Uint8List data,
    this.mimeType = const Value.absent(),
    required int size,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : hash = Value(hash),
       data = Value(data),
       size = Value(size);
  static Insertable<Blob> custom({
    Expression<String>? hash,
    Expression<Uint8List>? data,
    Expression<String>? mimeType,
    Expression<int>? size,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (hash != null) 'hash': hash,
      if (data != null) 'data': data,
      if (mimeType != null) 'mime_type': mimeType,
      if (size != null) 'size': size,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BlobsCompanion copyWith({
    Value<String>? hash,
    Value<Uint8List>? data,
    Value<String?>? mimeType,
    Value<int>? size,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return BlobsCompanion(
      hash: hash ?? this.hash,
      data: data ?? this.data,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (hash.present) {
      map['hash'] = Variable<String>(hash.value);
    }
    if (data.present) {
      map['data'] = Variable<Uint8List>(data.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BlobsCompanion(')
          ..write('hash: $hash, ')
          ..write('data: $data, ')
          ..write('mimeType: $mimeType, ')
          ..write('size: $size, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _agentNameMeta = const VerificationMeta(
    'agentName',
  );
  @override
  late final GeneratedColumn<String> agentName = GeneratedColumn<String>(
    'agent_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metadataMeta = const VerificationMeta(
    'metadata',
  );
  @override
  late final GeneratedColumn<String> metadata = GeneratedColumn<String>(
    'metadata',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nostrEventIdMeta = const VerificationMeta(
    'nostrEventId',
  );
  @override
  late final GeneratedColumn<String> nostrEventId = GeneratedColumn<String>(
    'nostr_event_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('sent'),
  );
  static const VerificationMeta _replyToIdMeta = const VerificationMeta(
    'replyToId',
  );
  @override
  late final GeneratedColumn<String> replyToId = GeneratedColumn<String>(
    'reply_to_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    role,
    agentName,
    content,
    metadata,
    timestamp,
    nostrEventId,
    status,
    replyToId,
    isPinned,
    expiresAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('agent_name')) {
      context.handle(
        _agentNameMeta,
        agentName.isAcceptableOrUnknown(data['agent_name']!, _agentNameMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('metadata')) {
      context.handle(
        _metadataMeta,
        metadata.isAcceptableOrUnknown(data['metadata']!, _metadataMeta),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('nostr_event_id')) {
      context.handle(
        _nostrEventIdMeta,
        nostrEventId.isAcceptableOrUnknown(
          data['nostr_event_id']!,
          _nostrEventIdMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('reply_to_id')) {
      context.handle(
        _replyToIdMeta,
        replyToId.isAcceptableOrUnknown(data['reply_to_id']!, _replyToIdMeta),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      agentName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_name'],
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      metadata: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata'],
      ),
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      nostrEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nostr_event_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      replyToId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_id'],
      ),
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  /// Unique message identifier (UUID).
  final String id;

  /// The conversation this message belongs to.
  final String conversationId;

  /// Message role: `user`, `agent`, `system`, `tool_call`, `tool_result`.
  final String role;

  /// The agent that produced this message (null for user messages).
  final String? agentName;

  /// Text content of the message.
  final String content;

  /// JSON-encoded metadata (tool arguments, widget results, etc.).
  final String? metadata;

  /// When the message was created.
  final DateTime timestamp;

  /// Nostr event ID for messages sent/received via Nostr DMs.
  final String? nostrEventId;

  /// Delivery status: `sending`, `sent`, `delivered`, `failed`.
  final String status;

  /// The message ID this is replying to (for threaded replies).
  final String? replyToId;

  /// Whether this message is pinned/starred in the conversation.
  final bool isPinned;

  /// When the message expires and should be auto-deleted (disappearing messages).
  ///
  /// Stored as a UTC DateTime. `null` means the message never expires.
  final DateTime? expiresAt;
  const Message({
    required this.id,
    required this.conversationId,
    required this.role,
    this.agentName,
    required this.content,
    this.metadata,
    required this.timestamp,
    this.nostrEventId,
    required this.status,
    this.replyToId,
    required this.isPinned,
    this.expiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['role'] = Variable<String>(role);
    if (!nullToAbsent || agentName != null) {
      map['agent_name'] = Variable<String>(agentName);
    }
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || metadata != null) {
      map['metadata'] = Variable<String>(metadata);
    }
    map['timestamp'] = Variable<DateTime>(timestamp);
    if (!nullToAbsent || nostrEventId != null) {
      map['nostr_event_id'] = Variable<String>(nostrEventId);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || replyToId != null) {
      map['reply_to_id'] = Variable<String>(replyToId);
    }
    map['is_pinned'] = Variable<bool>(isPinned);
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      role: Value(role),
      agentName: agentName == null && nullToAbsent
          ? const Value.absent()
          : Value(agentName),
      content: Value(content),
      metadata: metadata == null && nullToAbsent
          ? const Value.absent()
          : Value(metadata),
      timestamp: Value(timestamp),
      nostrEventId: nostrEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(nostrEventId),
      status: Value(status),
      replyToId: replyToId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToId),
      isPinned: Value(isPinned),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      role: serializer.fromJson<String>(json['role']),
      agentName: serializer.fromJson<String?>(json['agentName']),
      content: serializer.fromJson<String>(json['content']),
      metadata: serializer.fromJson<String?>(json['metadata']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      nostrEventId: serializer.fromJson<String?>(json['nostrEventId']),
      status: serializer.fromJson<String>(json['status']),
      replyToId: serializer.fromJson<String?>(json['replyToId']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'role': serializer.toJson<String>(role),
      'agentName': serializer.toJson<String?>(agentName),
      'content': serializer.toJson<String>(content),
      'metadata': serializer.toJson<String?>(metadata),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'nostrEventId': serializer.toJson<String?>(nostrEventId),
      'status': serializer.toJson<String>(status),
      'replyToId': serializer.toJson<String?>(replyToId),
      'isPinned': serializer.toJson<bool>(isPinned),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
    };
  }

  Message copyWith({
    String? id,
    String? conversationId,
    String? role,
    Value<String?> agentName = const Value.absent(),
    String? content,
    Value<String?> metadata = const Value.absent(),
    DateTime? timestamp,
    Value<String?> nostrEventId = const Value.absent(),
    String? status,
    Value<String?> replyToId = const Value.absent(),
    bool? isPinned,
    Value<DateTime?> expiresAt = const Value.absent(),
  }) => Message(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    role: role ?? this.role,
    agentName: agentName.present ? agentName.value : this.agentName,
    content: content ?? this.content,
    metadata: metadata.present ? metadata.value : this.metadata,
    timestamp: timestamp ?? this.timestamp,
    nostrEventId: nostrEventId.present ? nostrEventId.value : this.nostrEventId,
    status: status ?? this.status,
    replyToId: replyToId.present ? replyToId.value : this.replyToId,
    isPinned: isPinned ?? this.isPinned,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      role: data.role.present ? data.role.value : this.role,
      agentName: data.agentName.present ? data.agentName.value : this.agentName,
      content: data.content.present ? data.content.value : this.content,
      metadata: data.metadata.present ? data.metadata.value : this.metadata,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      nostrEventId: data.nostrEventId.present
          ? data.nostrEventId.value
          : this.nostrEventId,
      status: data.status.present ? data.status.value : this.status,
      replyToId: data.replyToId.present ? data.replyToId.value : this.replyToId,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('agentName: $agentName, ')
          ..write('content: $content, ')
          ..write('metadata: $metadata, ')
          ..write('timestamp: $timestamp, ')
          ..write('nostrEventId: $nostrEventId, ')
          ..write('status: $status, ')
          ..write('replyToId: $replyToId, ')
          ..write('isPinned: $isPinned, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    role,
    agentName,
    content,
    metadata,
    timestamp,
    nostrEventId,
    status,
    replyToId,
    isPinned,
    expiresAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.role == this.role &&
          other.agentName == this.agentName &&
          other.content == this.content &&
          other.metadata == this.metadata &&
          other.timestamp == this.timestamp &&
          other.nostrEventId == this.nostrEventId &&
          other.status == this.status &&
          other.replyToId == this.replyToId &&
          other.isPinned == this.isPinned &&
          other.expiresAt == this.expiresAt);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String> role;
  final Value<String?> agentName;
  final Value<String> content;
  final Value<String?> metadata;
  final Value<DateTime> timestamp;
  final Value<String?> nostrEventId;
  final Value<String> status;
  final Value<String?> replyToId;
  final Value<bool> isPinned;
  final Value<DateTime?> expiresAt;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.role = const Value.absent(),
    this.agentName = const Value.absent(),
    this.content = const Value.absent(),
    this.metadata = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.nostrEventId = const Value.absent(),
    this.status = const Value.absent(),
    this.replyToId = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String conversationId,
    required String role,
    this.agentName = const Value.absent(),
    required String content,
    this.metadata = const Value.absent(),
    required DateTime timestamp,
    this.nostrEventId = const Value.absent(),
    this.status = const Value.absent(),
    this.replyToId = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       conversationId = Value(conversationId),
       role = Value(role),
       content = Value(content),
       timestamp = Value(timestamp);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? role,
    Expression<String>? agentName,
    Expression<String>? content,
    Expression<String>? metadata,
    Expression<DateTime>? timestamp,
    Expression<String>? nostrEventId,
    Expression<String>? status,
    Expression<String>? replyToId,
    Expression<bool>? isPinned,
    Expression<DateTime>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (role != null) 'role': role,
      if (agentName != null) 'agent_name': agentName,
      if (content != null) 'content': content,
      if (metadata != null) 'metadata': metadata,
      if (timestamp != null) 'timestamp': timestamp,
      if (nostrEventId != null) 'nostr_event_id': nostrEventId,
      if (status != null) 'status': status,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (isPinned != null) 'is_pinned': isPinned,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? conversationId,
    Value<String>? role,
    Value<String?>? agentName,
    Value<String>? content,
    Value<String?>? metadata,
    Value<DateTime>? timestamp,
    Value<String?>? nostrEventId,
    Value<String>? status,
    Value<String?>? replyToId,
    Value<bool>? isPinned,
    Value<DateTime?>? expiresAt,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      agentName: agentName ?? this.agentName,
      content: content ?? this.content,
      metadata: metadata ?? this.metadata,
      timestamp: timestamp ?? this.timestamp,
      nostrEventId: nostrEventId ?? this.nostrEventId,
      status: status ?? this.status,
      replyToId: replyToId ?? this.replyToId,
      isPinned: isPinned ?? this.isPinned,
      expiresAt: expiresAt ?? this.expiresAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (agentName.present) {
      map['agent_name'] = Variable<String>(agentName.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (metadata.present) {
      map['metadata'] = Variable<String>(metadata.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (nostrEventId.present) {
      map['nostr_event_id'] = Variable<String>(nostrEventId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (replyToId.present) {
      map['reply_to_id'] = Variable<String>(replyToId.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('agentName: $agentName, ')
          ..write('content: $content, ')
          ..write('metadata: $metadata, ')
          ..write('timestamp: $timestamp, ')
          ..write('nostrEventId: $nostrEventId, ')
          ..write('status: $status, ')
          ..write('replyToId: $replyToId, ')
          ..write('isPinned: $isPinned, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('New Chat'),
  );
  static const VerificationMeta _agentNameMeta = const VerificationMeta(
    'agentName',
  );
  @override
  late final GeneratedColumn<String> agentName = GeneratedColumn<String>(
    'agent_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('agent'),
  );
  static const VerificationMeta _nostrPubkeyMeta = const VerificationMeta(
    'nostrPubkey',
  );
  @override
  late final GeneratedColumn<String> nostrPubkey = GeneratedColumn<String>(
    'nostr_pubkey',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isMutedMeta = const VerificationMeta(
    'isMuted',
  );
  @override
  late final GeneratedColumn<bool> isMuted = GeneratedColumn<bool>(
    'is_muted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_muted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastMessageMeta = const VerificationMeta(
    'lastMessage',
  );
  @override
  late final GeneratedColumn<String> lastMessage = GeneratedColumn<String>(
    'last_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastMessageAtMeta = const VerificationMeta(
    'lastMessageAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastMessageAt =
      GeneratedColumn<DateTime>(
        'last_message_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    agentName,
    type,
    nostrPubkey,
    isPinned,
    isArchived,
    isMuted,
    unreadCount,
    lastMessage,
    lastMessageAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Conversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('agent_name')) {
      context.handle(
        _agentNameMeta,
        agentName.isAcceptableOrUnknown(data['agent_name']!, _agentNameMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('nostr_pubkey')) {
      context.handle(
        _nostrPubkeyMeta,
        nostrPubkey.isAcceptableOrUnknown(
          data['nostr_pubkey']!,
          _nostrPubkeyMeta,
        ),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    }
    if (data.containsKey('is_muted')) {
      context.handle(
        _isMutedMeta,
        isMuted.isAcceptableOrUnknown(data['is_muted']!, _isMutedMeta),
      );
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('last_message')) {
      context.handle(
        _lastMessageMeta,
        lastMessage.isAcceptableOrUnknown(
          data['last_message']!,
          _lastMessageMeta,
        ),
      );
    }
    if (data.containsKey('last_message_at')) {
      context.handle(
        _lastMessageAtMeta,
        lastMessageAt.isAcceptableOrUnknown(
          data['last_message_at']!,
          _lastMessageAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      agentName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_name'],
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      nostrPubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nostr_pubkey'],
      ),
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      isMuted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_muted'],
      )!,
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      lastMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message'],
      ),
      lastMessageAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_message_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class Conversation extends DataClass implements Insertable<Conversation> {
  /// Unique conversation identifier (UUID).
  final String id;

  /// Human-readable title for the conversation.
  final String title;

  /// The primary agent handling this conversation.
  final String? agentName;

  /// Conversation type: `agent`, `nostr_dm`, `nostr_group`.
  final String type;

  /// Nostr public key of the other party (for `nostr_dm` conversations).
  final String? nostrPubkey;

  /// Whether this conversation is pinned to the top.
  final bool isPinned;

  /// Whether this conversation is archived (hidden from main list).
  final bool isArchived;

  /// Whether notifications are muted for this conversation.
  final bool isMuted;

  /// Number of unread messages.
  final int unreadCount;

  /// Preview text of the last message.
  final String? lastMessage;

  /// Timestamp of the last message (for sort ordering).
  final DateTime? lastMessageAt;

  /// When the conversation was created.
  final DateTime createdAt;

  /// When the conversation was last updated.
  final DateTime updatedAt;
  const Conversation({
    required this.id,
    required this.title,
    this.agentName,
    required this.type,
    this.nostrPubkey,
    required this.isPinned,
    required this.isArchived,
    required this.isMuted,
    required this.unreadCount,
    this.lastMessage,
    this.lastMessageAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || agentName != null) {
      map['agent_name'] = Variable<String>(agentName);
    }
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || nostrPubkey != null) {
      map['nostr_pubkey'] = Variable<String>(nostrPubkey);
    }
    map['is_pinned'] = Variable<bool>(isPinned);
    map['is_archived'] = Variable<bool>(isArchived);
    map['is_muted'] = Variable<bool>(isMuted);
    map['unread_count'] = Variable<int>(unreadCount);
    if (!nullToAbsent || lastMessage != null) {
      map['last_message'] = Variable<String>(lastMessage);
    }
    if (!nullToAbsent || lastMessageAt != null) {
      map['last_message_at'] = Variable<DateTime>(lastMessageAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      id: Value(id),
      title: Value(title),
      agentName: agentName == null && nullToAbsent
          ? const Value.absent()
          : Value(agentName),
      type: Value(type),
      nostrPubkey: nostrPubkey == null && nullToAbsent
          ? const Value.absent()
          : Value(nostrPubkey),
      isPinned: Value(isPinned),
      isArchived: Value(isArchived),
      isMuted: Value(isMuted),
      unreadCount: Value(unreadCount),
      lastMessage: lastMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessage),
      lastMessageAt: lastMessageAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Conversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      agentName: serializer.fromJson<String?>(json['agentName']),
      type: serializer.fromJson<String>(json['type']),
      nostrPubkey: serializer.fromJson<String?>(json['nostrPubkey']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      isMuted: serializer.fromJson<bool>(json['isMuted']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      lastMessage: serializer.fromJson<String?>(json['lastMessage']),
      lastMessageAt: serializer.fromJson<DateTime?>(json['lastMessageAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'agentName': serializer.toJson<String?>(agentName),
      'type': serializer.toJson<String>(type),
      'nostrPubkey': serializer.toJson<String?>(nostrPubkey),
      'isPinned': serializer.toJson<bool>(isPinned),
      'isArchived': serializer.toJson<bool>(isArchived),
      'isMuted': serializer.toJson<bool>(isMuted),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'lastMessage': serializer.toJson<String?>(lastMessage),
      'lastMessageAt': serializer.toJson<DateTime?>(lastMessageAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Conversation copyWith({
    String? id,
    String? title,
    Value<String?> agentName = const Value.absent(),
    String? type,
    Value<String?> nostrPubkey = const Value.absent(),
    bool? isPinned,
    bool? isArchived,
    bool? isMuted,
    int? unreadCount,
    Value<String?> lastMessage = const Value.absent(),
    Value<DateTime?> lastMessageAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Conversation(
    id: id ?? this.id,
    title: title ?? this.title,
    agentName: agentName.present ? agentName.value : this.agentName,
    type: type ?? this.type,
    nostrPubkey: nostrPubkey.present ? nostrPubkey.value : this.nostrPubkey,
    isPinned: isPinned ?? this.isPinned,
    isArchived: isArchived ?? this.isArchived,
    isMuted: isMuted ?? this.isMuted,
    unreadCount: unreadCount ?? this.unreadCount,
    lastMessage: lastMessage.present ? lastMessage.value : this.lastMessage,
    lastMessageAt: lastMessageAt.present
        ? lastMessageAt.value
        : this.lastMessageAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Conversation copyWithCompanion(ConversationsCompanion data) {
    return Conversation(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      agentName: data.agentName.present ? data.agentName.value : this.agentName,
      type: data.type.present ? data.type.value : this.type,
      nostrPubkey: data.nostrPubkey.present
          ? data.nostrPubkey.value
          : this.nostrPubkey,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
      isMuted: data.isMuted.present ? data.isMuted.value : this.isMuted,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      lastMessage: data.lastMessage.present
          ? data.lastMessage.value
          : this.lastMessage,
      lastMessageAt: data.lastMessageAt.present
          ? data.lastMessageAt.value
          : this.lastMessageAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('agentName: $agentName, ')
          ..write('type: $type, ')
          ..write('nostrPubkey: $nostrPubkey, ')
          ..write('isPinned: $isPinned, ')
          ..write('isArchived: $isArchived, ')
          ..write('isMuted: $isMuted, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    agentName,
    type,
    nostrPubkey,
    isPinned,
    isArchived,
    isMuted,
    unreadCount,
    lastMessage,
    lastMessageAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.id == this.id &&
          other.title == this.title &&
          other.agentName == this.agentName &&
          other.type == this.type &&
          other.nostrPubkey == this.nostrPubkey &&
          other.isPinned == this.isPinned &&
          other.isArchived == this.isArchived &&
          other.isMuted == this.isMuted &&
          other.unreadCount == this.unreadCount &&
          other.lastMessage == this.lastMessage &&
          other.lastMessageAt == this.lastMessageAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> agentName;
  final Value<String> type;
  final Value<String?> nostrPubkey;
  final Value<bool> isPinned;
  final Value<bool> isArchived;
  final Value<bool> isMuted;
  final Value<int> unreadCount;
  final Value<String?> lastMessage;
  final Value<DateTime?> lastMessageAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ConversationsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.agentName = const Value.absent(),
    this.type = const Value.absent(),
    this.nostrPubkey = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.isMuted = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.lastMessage = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.agentName = const Value.absent(),
    this.type = const Value.absent(),
    this.nostrPubkey = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.isMuted = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.lastMessage = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<Conversation> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? agentName,
    Expression<String>? type,
    Expression<String>? nostrPubkey,
    Expression<bool>? isPinned,
    Expression<bool>? isArchived,
    Expression<bool>? isMuted,
    Expression<int>? unreadCount,
    Expression<String>? lastMessage,
    Expression<DateTime>? lastMessageAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (agentName != null) 'agent_name': agentName,
      if (type != null) 'type': type,
      if (nostrPubkey != null) 'nostr_pubkey': nostrPubkey,
      if (isPinned != null) 'is_pinned': isPinned,
      if (isArchived != null) 'is_archived': isArchived,
      if (isMuted != null) 'is_muted': isMuted,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (lastMessage != null) 'last_message': lastMessage,
      if (lastMessageAt != null) 'last_message_at': lastMessageAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? agentName,
    Value<String>? type,
    Value<String?>? nostrPubkey,
    Value<bool>? isPinned,
    Value<bool>? isArchived,
    Value<bool>? isMuted,
    Value<int>? unreadCount,
    Value<String?>? lastMessage,
    Value<DateTime?>? lastMessageAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ConversationsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      agentName: agentName ?? this.agentName,
      type: type ?? this.type,
      nostrPubkey: nostrPubkey ?? this.nostrPubkey,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isMuted: isMuted ?? this.isMuted,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (agentName.present) {
      map['agent_name'] = Variable<String>(agentName.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (nostrPubkey.present) {
      map['nostr_pubkey'] = Variable<String>(nostrPubkey.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (isMuted.present) {
      map['is_muted'] = Variable<bool>(isMuted.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (lastMessage.present) {
      map['last_message'] = Variable<String>(lastMessage.value);
    }
    if (lastMessageAt.present) {
      map['last_message_at'] = Variable<DateTime>(lastMessageAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('agentName: $agentName, ')
          ..write('type: $type, ')
          ..write('nostrPubkey: $nostrPubkey, ')
          ..write('isPinned: $isPinned, ')
          ..write('isArchived: $isArchived, ')
          ..write('isMuted: $isMuted, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessageReactionsTable extends MessageReactions
    with TableInfo<$MessageReactionsTable, MessageReaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageReactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pubkeyMeta = const VerificationMeta('pubkey');
  @override
  late final GeneratedColumn<String> pubkey = GeneratedColumn<String>(
    'pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reactionMeta = const VerificationMeta(
    'reaction',
  );
  @override
  late final GeneratedColumn<String> reaction = GeneratedColumn<String>(
    'reaction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('+'),
  );
  static const VerificationMeta _nostrEventIdMeta = const VerificationMeta(
    'nostrEventId',
  );
  @override
  late final GeneratedColumn<String> nostrEventId = GeneratedColumn<String>(
    'nostr_event_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    messageId,
    conversationId,
    pubkey,
    reaction,
    nostrEventId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_reactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageReaction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('pubkey')) {
      context.handle(
        _pubkeyMeta,
        pubkey.isAcceptableOrUnknown(data['pubkey']!, _pubkeyMeta),
      );
    } else if (isInserting) {
      context.missing(_pubkeyMeta);
    }
    if (data.containsKey('reaction')) {
      context.handle(
        _reactionMeta,
        reaction.isAcceptableOrUnknown(data['reaction']!, _reactionMeta),
      );
    }
    if (data.containsKey('nostr_event_id')) {
      context.handle(
        _nostrEventIdMeta,
        nostrEventId.isAcceptableOrUnknown(
          data['nostr_event_id']!,
          _nostrEventIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {messageId, pubkey},
  ];
  @override
  MessageReaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageReaction(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      pubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pubkey'],
      )!,
      reaction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reaction'],
      )!,
      nostrEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nostr_event_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $MessageReactionsTable createAlias(String alias) {
    return $MessageReactionsTable(attachedDatabase, alias);
  }
}

class MessageReaction extends DataClass implements Insertable<MessageReaction> {
  /// Auto-incrementing primary key.
  final int id;

  /// The local database message ID being reacted to.
  final String messageId;

  /// The conversation this reaction belongs to.
  final String conversationId;

  /// The reactor's Nostr public key (hex).
  final String pubkey;

  /// The reaction emoji (NIP-25, default '+' for like, '-' for dislike).
  final String reaction;

  /// The Nostr event ID of the published kind-7 reaction event.
  final String? nostrEventId;

  /// When the reaction was created.
  final DateTime createdAt;
  const MessageReaction({
    required this.id,
    required this.messageId,
    required this.conversationId,
    required this.pubkey,
    required this.reaction,
    this.nostrEventId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['message_id'] = Variable<String>(messageId);
    map['conversation_id'] = Variable<String>(conversationId);
    map['pubkey'] = Variable<String>(pubkey);
    map['reaction'] = Variable<String>(reaction);
    if (!nullToAbsent || nostrEventId != null) {
      map['nostr_event_id'] = Variable<String>(nostrEventId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MessageReactionsCompanion toCompanion(bool nullToAbsent) {
    return MessageReactionsCompanion(
      id: Value(id),
      messageId: Value(messageId),
      conversationId: Value(conversationId),
      pubkey: Value(pubkey),
      reaction: Value(reaction),
      nostrEventId: nostrEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(nostrEventId),
      createdAt: Value(createdAt),
    );
  }

  factory MessageReaction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageReaction(
      id: serializer.fromJson<int>(json['id']),
      messageId: serializer.fromJson<String>(json['messageId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      pubkey: serializer.fromJson<String>(json['pubkey']),
      reaction: serializer.fromJson<String>(json['reaction']),
      nostrEventId: serializer.fromJson<String?>(json['nostrEventId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'messageId': serializer.toJson<String>(messageId),
      'conversationId': serializer.toJson<String>(conversationId),
      'pubkey': serializer.toJson<String>(pubkey),
      'reaction': serializer.toJson<String>(reaction),
      'nostrEventId': serializer.toJson<String?>(nostrEventId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  MessageReaction copyWith({
    int? id,
    String? messageId,
    String? conversationId,
    String? pubkey,
    String? reaction,
    Value<String?> nostrEventId = const Value.absent(),
    DateTime? createdAt,
  }) => MessageReaction(
    id: id ?? this.id,
    messageId: messageId ?? this.messageId,
    conversationId: conversationId ?? this.conversationId,
    pubkey: pubkey ?? this.pubkey,
    reaction: reaction ?? this.reaction,
    nostrEventId: nostrEventId.present ? nostrEventId.value : this.nostrEventId,
    createdAt: createdAt ?? this.createdAt,
  );
  MessageReaction copyWithCompanion(MessageReactionsCompanion data) {
    return MessageReaction(
      id: data.id.present ? data.id.value : this.id,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      pubkey: data.pubkey.present ? data.pubkey.value : this.pubkey,
      reaction: data.reaction.present ? data.reaction.value : this.reaction,
      nostrEventId: data.nostrEventId.present
          ? data.nostrEventId.value
          : this.nostrEventId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageReaction(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('conversationId: $conversationId, ')
          ..write('pubkey: $pubkey, ')
          ..write('reaction: $reaction, ')
          ..write('nostrEventId: $nostrEventId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    messageId,
    conversationId,
    pubkey,
    reaction,
    nostrEventId,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageReaction &&
          other.id == this.id &&
          other.messageId == this.messageId &&
          other.conversationId == this.conversationId &&
          other.pubkey == this.pubkey &&
          other.reaction == this.reaction &&
          other.nostrEventId == this.nostrEventId &&
          other.createdAt == this.createdAt);
}

class MessageReactionsCompanion extends UpdateCompanion<MessageReaction> {
  final Value<int> id;
  final Value<String> messageId;
  final Value<String> conversationId;
  final Value<String> pubkey;
  final Value<String> reaction;
  final Value<String?> nostrEventId;
  final Value<DateTime> createdAt;
  const MessageReactionsCompanion({
    this.id = const Value.absent(),
    this.messageId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.pubkey = const Value.absent(),
    this.reaction = const Value.absent(),
    this.nostrEventId = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  MessageReactionsCompanion.insert({
    this.id = const Value.absent(),
    required String messageId,
    required String conversationId,
    required String pubkey,
    this.reaction = const Value.absent(),
    this.nostrEventId = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : messageId = Value(messageId),
       conversationId = Value(conversationId),
       pubkey = Value(pubkey);
  static Insertable<MessageReaction> custom({
    Expression<int>? id,
    Expression<String>? messageId,
    Expression<String>? conversationId,
    Expression<String>? pubkey,
    Expression<String>? reaction,
    Expression<String>? nostrEventId,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageId != null) 'message_id': messageId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (pubkey != null) 'pubkey': pubkey,
      if (reaction != null) 'reaction': reaction,
      if (nostrEventId != null) 'nostr_event_id': nostrEventId,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  MessageReactionsCompanion copyWith({
    Value<int>? id,
    Value<String>? messageId,
    Value<String>? conversationId,
    Value<String>? pubkey,
    Value<String>? reaction,
    Value<String?>? nostrEventId,
    Value<DateTime>? createdAt,
  }) {
    return MessageReactionsCompanion(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      conversationId: conversationId ?? this.conversationId,
      pubkey: pubkey ?? this.pubkey,
      reaction: reaction ?? this.reaction,
      nostrEventId: nostrEventId ?? this.nostrEventId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (pubkey.present) {
      map['pubkey'] = Variable<String>(pubkey.value);
    }
    if (reaction.present) {
      map['reaction'] = Variable<String>(reaction.value);
    }
    if (nostrEventId.present) {
      map['nostr_event_id'] = Variable<String>(nostrEventId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageReactionsCompanion(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('conversationId: $conversationId, ')
          ..write('pubkey: $pubkey, ')
          ..write('reaction: $reaction, ')
          ..write('nostrEventId: $nostrEventId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $DevicePairsTable extends DevicePairs
    with TableInfo<$DevicePairsTable, DevicePair> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DevicePairsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localDeviceIdMeta = const VerificationMeta(
    'localDeviceId',
  );
  @override
  late final GeneratedColumn<String> localDeviceId = GeneratedColumn<String>(
    'local_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteDeviceIdMeta = const VerificationMeta(
    'remoteDeviceId',
  );
  @override
  late final GeneratedColumn<String> remoteDeviceId = GeneratedColumn<String>(
    'remote_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteNameMeta = const VerificationMeta(
    'remoteName',
  );
  @override
  late final GeneratedColumn<String> remoteName = GeneratedColumn<String>(
    'remote_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteAddressMeta = const VerificationMeta(
    'remoteAddress',
  );
  @override
  late final GeneratedColumn<String> remoteAddress = GeneratedColumn<String>(
    'remote_address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sharedPublicKeyHexMeta =
      const VerificationMeta('sharedPublicKeyHex');
  @override
  late final GeneratedColumn<String> sharedPublicKeyHex =
      GeneratedColumn<String>(
        'shared_public_key_hex',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _pairingTokenMeta = const VerificationMeta(
    'pairingToken',
  );
  @override
  late final GeneratedColumn<String> pairingToken = GeneratedColumn<String>(
    'pairing_token',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _lastSyncAtMeta = const VerificationMeta(
    'lastSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncAt = GeneratedColumn<DateTime>(
    'last_sync_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isVerifiedMeta = const VerificationMeta(
    'isVerified',
  );
  @override
  late final GeneratedColumn<bool> isVerified = GeneratedColumn<bool>(
    'is_verified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_verified" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    localDeviceId,
    remoteDeviceId,
    remoteName,
    remoteAddress,
    sharedPublicKeyHex,
    pairingToken,
    createdAt,
    lastSeenAt,
    lastSyncAt,
    isVerified,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'device_pairs';
  @override
  VerificationContext validateIntegrity(
    Insertable<DevicePair> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_device_id')) {
      context.handle(
        _localDeviceIdMeta,
        localDeviceId.isAcceptableOrUnknown(
          data['local_device_id']!,
          _localDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localDeviceIdMeta);
    }
    if (data.containsKey('remote_device_id')) {
      context.handle(
        _remoteDeviceIdMeta,
        remoteDeviceId.isAcceptableOrUnknown(
          data['remote_device_id']!,
          _remoteDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_remoteDeviceIdMeta);
    }
    if (data.containsKey('remote_name')) {
      context.handle(
        _remoteNameMeta,
        remoteName.isAcceptableOrUnknown(data['remote_name']!, _remoteNameMeta),
      );
    } else if (isInserting) {
      context.missing(_remoteNameMeta);
    }
    if (data.containsKey('remote_address')) {
      context.handle(
        _remoteAddressMeta,
        remoteAddress.isAcceptableOrUnknown(
          data['remote_address']!,
          _remoteAddressMeta,
        ),
      );
    }
    if (data.containsKey('shared_public_key_hex')) {
      context.handle(
        _sharedPublicKeyHexMeta,
        sharedPublicKeyHex.isAcceptableOrUnknown(
          data['shared_public_key_hex']!,
          _sharedPublicKeyHexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sharedPublicKeyHexMeta);
    }
    if (data.containsKey('pairing_token')) {
      context.handle(
        _pairingTokenMeta,
        pairingToken.isAcceptableOrUnknown(
          data['pairing_token']!,
          _pairingTokenMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_pairingTokenMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('last_sync_at')) {
      context.handle(
        _lastSyncAtMeta,
        lastSyncAt.isAcceptableOrUnknown(
          data['last_sync_at']!,
          _lastSyncAtMeta,
        ),
      );
    }
    if (data.containsKey('is_verified')) {
      context.handle(
        _isVerifiedMeta,
        isVerified.isAcceptableOrUnknown(data['is_verified']!, _isVerifiedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localDeviceId, remoteDeviceId};
  @override
  DevicePair map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DevicePair(
      localDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_device_id'],
      )!,
      remoteDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_device_id'],
      )!,
      remoteName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_name'],
      )!,
      remoteAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_address'],
      ),
      sharedPublicKeyHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shared_public_key_hex'],
      )!,
      pairingToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pairing_token'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      )!,
      lastSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_at'],
      ),
      isVerified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_verified'],
      )!,
    );
  }

  @override
  $DevicePairsTable createAlias(String alias) {
    return $DevicePairsTable(attachedDatabase, alias);
  }
}

class DevicePair extends DataClass implements Insertable<DevicePair> {
  /// Unique identifier for the local device in this pairing.
  final String localDeviceId;

  /// Unique identifier for the remote device.
  final String remoteDeviceId;

  /// Human-readable name of the remote device.
  final String remoteName;

  /// Last-known network address of the remote device (e.g. `http://ip:port`).
  final String? remoteAddress;

  /// Hex-encoded public key of the identity shared in this pairing.
  final String sharedPublicKeyHex;

  /// HMAC-based pairing token for mutual authentication.
  final String pairingToken;

  /// When this pairing was established.
  final DateTime createdAt;

  /// When the remote device was last seen (via beacon or sync).
  final DateTime lastSeenAt;

  /// Timestamp of the last successful sync with this device.
  final DateTime? lastSyncAt;

  /// Whether this pairing has been verified on both sides.
  final bool isVerified;
  const DevicePair({
    required this.localDeviceId,
    required this.remoteDeviceId,
    required this.remoteName,
    this.remoteAddress,
    required this.sharedPublicKeyHex,
    required this.pairingToken,
    required this.createdAt,
    required this.lastSeenAt,
    this.lastSyncAt,
    required this.isVerified,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_device_id'] = Variable<String>(localDeviceId);
    map['remote_device_id'] = Variable<String>(remoteDeviceId);
    map['remote_name'] = Variable<String>(remoteName);
    if (!nullToAbsent || remoteAddress != null) {
      map['remote_address'] = Variable<String>(remoteAddress);
    }
    map['shared_public_key_hex'] = Variable<String>(sharedPublicKeyHex);
    map['pairing_token'] = Variable<String>(pairingToken);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    if (!nullToAbsent || lastSyncAt != null) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt);
    }
    map['is_verified'] = Variable<bool>(isVerified);
    return map;
  }

  DevicePairsCompanion toCompanion(bool nullToAbsent) {
    return DevicePairsCompanion(
      localDeviceId: Value(localDeviceId),
      remoteDeviceId: Value(remoteDeviceId),
      remoteName: Value(remoteName),
      remoteAddress: remoteAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteAddress),
      sharedPublicKeyHex: Value(sharedPublicKeyHex),
      pairingToken: Value(pairingToken),
      createdAt: Value(createdAt),
      lastSeenAt: Value(lastSeenAt),
      lastSyncAt: lastSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAt),
      isVerified: Value(isVerified),
    );
  }

  factory DevicePair.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DevicePair(
      localDeviceId: serializer.fromJson<String>(json['localDeviceId']),
      remoteDeviceId: serializer.fromJson<String>(json['remoteDeviceId']),
      remoteName: serializer.fromJson<String>(json['remoteName']),
      remoteAddress: serializer.fromJson<String?>(json['remoteAddress']),
      sharedPublicKeyHex: serializer.fromJson<String>(
        json['sharedPublicKeyHex'],
      ),
      pairingToken: serializer.fromJson<String>(json['pairingToken']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastSeenAt: serializer.fromJson<DateTime>(json['lastSeenAt']),
      lastSyncAt: serializer.fromJson<DateTime?>(json['lastSyncAt']),
      isVerified: serializer.fromJson<bool>(json['isVerified']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localDeviceId': serializer.toJson<String>(localDeviceId),
      'remoteDeviceId': serializer.toJson<String>(remoteDeviceId),
      'remoteName': serializer.toJson<String>(remoteName),
      'remoteAddress': serializer.toJson<String?>(remoteAddress),
      'sharedPublicKeyHex': serializer.toJson<String>(sharedPublicKeyHex),
      'pairingToken': serializer.toJson<String>(pairingToken),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastSeenAt': serializer.toJson<DateTime>(lastSeenAt),
      'lastSyncAt': serializer.toJson<DateTime?>(lastSyncAt),
      'isVerified': serializer.toJson<bool>(isVerified),
    };
  }

  DevicePair copyWith({
    String? localDeviceId,
    String? remoteDeviceId,
    String? remoteName,
    Value<String?> remoteAddress = const Value.absent(),
    String? sharedPublicKeyHex,
    String? pairingToken,
    DateTime? createdAt,
    DateTime? lastSeenAt,
    Value<DateTime?> lastSyncAt = const Value.absent(),
    bool? isVerified,
  }) => DevicePair(
    localDeviceId: localDeviceId ?? this.localDeviceId,
    remoteDeviceId: remoteDeviceId ?? this.remoteDeviceId,
    remoteName: remoteName ?? this.remoteName,
    remoteAddress: remoteAddress.present
        ? remoteAddress.value
        : this.remoteAddress,
    sharedPublicKeyHex: sharedPublicKeyHex ?? this.sharedPublicKeyHex,
    pairingToken: pairingToken ?? this.pairingToken,
    createdAt: createdAt ?? this.createdAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    lastSyncAt: lastSyncAt.present ? lastSyncAt.value : this.lastSyncAt,
    isVerified: isVerified ?? this.isVerified,
  );
  DevicePair copyWithCompanion(DevicePairsCompanion data) {
    return DevicePair(
      localDeviceId: data.localDeviceId.present
          ? data.localDeviceId.value
          : this.localDeviceId,
      remoteDeviceId: data.remoteDeviceId.present
          ? data.remoteDeviceId.value
          : this.remoteDeviceId,
      remoteName: data.remoteName.present
          ? data.remoteName.value
          : this.remoteName,
      remoteAddress: data.remoteAddress.present
          ? data.remoteAddress.value
          : this.remoteAddress,
      sharedPublicKeyHex: data.sharedPublicKeyHex.present
          ? data.sharedPublicKeyHex.value
          : this.sharedPublicKeyHex,
      pairingToken: data.pairingToken.present
          ? data.pairingToken.value
          : this.pairingToken,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      lastSyncAt: data.lastSyncAt.present
          ? data.lastSyncAt.value
          : this.lastSyncAt,
      isVerified: data.isVerified.present
          ? data.isVerified.value
          : this.isVerified,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DevicePair(')
          ..write('localDeviceId: $localDeviceId, ')
          ..write('remoteDeviceId: $remoteDeviceId, ')
          ..write('remoteName: $remoteName, ')
          ..write('remoteAddress: $remoteAddress, ')
          ..write('sharedPublicKeyHex: $sharedPublicKeyHex, ')
          ..write('pairingToken: $pairingToken, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('isVerified: $isVerified')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localDeviceId,
    remoteDeviceId,
    remoteName,
    remoteAddress,
    sharedPublicKeyHex,
    pairingToken,
    createdAt,
    lastSeenAt,
    lastSyncAt,
    isVerified,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DevicePair &&
          other.localDeviceId == this.localDeviceId &&
          other.remoteDeviceId == this.remoteDeviceId &&
          other.remoteName == this.remoteName &&
          other.remoteAddress == this.remoteAddress &&
          other.sharedPublicKeyHex == this.sharedPublicKeyHex &&
          other.pairingToken == this.pairingToken &&
          other.createdAt == this.createdAt &&
          other.lastSeenAt == this.lastSeenAt &&
          other.lastSyncAt == this.lastSyncAt &&
          other.isVerified == this.isVerified);
}

class DevicePairsCompanion extends UpdateCompanion<DevicePair> {
  final Value<String> localDeviceId;
  final Value<String> remoteDeviceId;
  final Value<String> remoteName;
  final Value<String?> remoteAddress;
  final Value<String> sharedPublicKeyHex;
  final Value<String> pairingToken;
  final Value<DateTime> createdAt;
  final Value<DateTime> lastSeenAt;
  final Value<DateTime?> lastSyncAt;
  final Value<bool> isVerified;
  final Value<int> rowid;
  const DevicePairsCompanion({
    this.localDeviceId = const Value.absent(),
    this.remoteDeviceId = const Value.absent(),
    this.remoteName = const Value.absent(),
    this.remoteAddress = const Value.absent(),
    this.sharedPublicKeyHex = const Value.absent(),
    this.pairingToken = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.isVerified = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DevicePairsCompanion.insert({
    required String localDeviceId,
    required String remoteDeviceId,
    required String remoteName,
    this.remoteAddress = const Value.absent(),
    required String sharedPublicKeyHex,
    required String pairingToken,
    this.createdAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.isVerified = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : localDeviceId = Value(localDeviceId),
       remoteDeviceId = Value(remoteDeviceId),
       remoteName = Value(remoteName),
       sharedPublicKeyHex = Value(sharedPublicKeyHex),
       pairingToken = Value(pairingToken);
  static Insertable<DevicePair> custom({
    Expression<String>? localDeviceId,
    Expression<String>? remoteDeviceId,
    Expression<String>? remoteName,
    Expression<String>? remoteAddress,
    Expression<String>? sharedPublicKeyHex,
    Expression<String>? pairingToken,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastSeenAt,
    Expression<DateTime>? lastSyncAt,
    Expression<bool>? isVerified,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localDeviceId != null) 'local_device_id': localDeviceId,
      if (remoteDeviceId != null) 'remote_device_id': remoteDeviceId,
      if (remoteName != null) 'remote_name': remoteName,
      if (remoteAddress != null) 'remote_address': remoteAddress,
      if (sharedPublicKeyHex != null)
        'shared_public_key_hex': sharedPublicKeyHex,
      if (pairingToken != null) 'pairing_token': pairingToken,
      if (createdAt != null) 'created_at': createdAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt,
      if (isVerified != null) 'is_verified': isVerified,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DevicePairsCompanion copyWith({
    Value<String>? localDeviceId,
    Value<String>? remoteDeviceId,
    Value<String>? remoteName,
    Value<String?>? remoteAddress,
    Value<String>? sharedPublicKeyHex,
    Value<String>? pairingToken,
    Value<DateTime>? createdAt,
    Value<DateTime>? lastSeenAt,
    Value<DateTime?>? lastSyncAt,
    Value<bool>? isVerified,
    Value<int>? rowid,
  }) {
    return DevicePairsCompanion(
      localDeviceId: localDeviceId ?? this.localDeviceId,
      remoteDeviceId: remoteDeviceId ?? this.remoteDeviceId,
      remoteName: remoteName ?? this.remoteName,
      remoteAddress: remoteAddress ?? this.remoteAddress,
      sharedPublicKeyHex: sharedPublicKeyHex ?? this.sharedPublicKeyHex,
      pairingToken: pairingToken ?? this.pairingToken,
      createdAt: createdAt ?? this.createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      isVerified: isVerified ?? this.isVerified,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localDeviceId.present) {
      map['local_device_id'] = Variable<String>(localDeviceId.value);
    }
    if (remoteDeviceId.present) {
      map['remote_device_id'] = Variable<String>(remoteDeviceId.value);
    }
    if (remoteName.present) {
      map['remote_name'] = Variable<String>(remoteName.value);
    }
    if (remoteAddress.present) {
      map['remote_address'] = Variable<String>(remoteAddress.value);
    }
    if (sharedPublicKeyHex.present) {
      map['shared_public_key_hex'] = Variable<String>(sharedPublicKeyHex.value);
    }
    if (pairingToken.present) {
      map['pairing_token'] = Variable<String>(pairingToken.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (lastSyncAt.present) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt.value);
    }
    if (isVerified.present) {
      map['is_verified'] = Variable<bool>(isVerified.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DevicePairsCompanion(')
          ..write('localDeviceId: $localDeviceId, ')
          ..write('remoteDeviceId: $remoteDeviceId, ')
          ..write('remoteName: $remoteName, ')
          ..write('remoteAddress: $remoteAddress, ')
          ..write('sharedPublicKeyHex: $sharedPublicKeyHex, ')
          ..write('pairingToken: $pairingToken, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('isVerified: $isVerified, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$KabukDatabase extends GeneratedDatabase {
  _$KabukDatabase(QueryExecutor e) : super(e);
  $KabukDatabaseManager get managers => $KabukDatabaseManager(this);
  late final $TriplesTable triples = $TriplesTable(this);
  late final $BlobsTable blobs = $BlobsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $MessageReactionsTable messageReactions = $MessageReactionsTable(
    this,
  );
  late final $DevicePairsTable devicePairs = $DevicePairsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    triples,
    blobs,
    messages,
    conversations,
    messageReactions,
    devicePairs,
  ];
}

typedef $$TriplesTableCreateCompanionBuilder =
    TriplesCompanion Function({
      Value<int> id,
      required String subject,
      required String predicate,
      required String objectType,
      Value<String?> objectUri,
      Value<String?> objectString,
      Value<int?> objectInt,
      Value<double?> objectReal,
      Value<String> graph,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> syncVersion,
    });
typedef $$TriplesTableUpdateCompanionBuilder =
    TriplesCompanion Function({
      Value<int> id,
      Value<String> subject,
      Value<String> predicate,
      Value<String> objectType,
      Value<String?> objectUri,
      Value<String?> objectString,
      Value<int?> objectInt,
      Value<double?> objectReal,
      Value<String> graph,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> syncVersion,
    });

class $$TriplesTableFilterComposer
    extends Composer<_$KabukDatabase, $TriplesTable> {
  $$TriplesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get predicate => $composableBuilder(
    column: $table.predicate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get objectType => $composableBuilder(
    column: $table.objectType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get objectUri => $composableBuilder(
    column: $table.objectUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get objectString => $composableBuilder(
    column: $table.objectString,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get objectInt => $composableBuilder(
    column: $table.objectInt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get objectReal => $composableBuilder(
    column: $table.objectReal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get graph => $composableBuilder(
    column: $table.graph,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncVersion => $composableBuilder(
    column: $table.syncVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TriplesTableOrderingComposer
    extends Composer<_$KabukDatabase, $TriplesTable> {
  $$TriplesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get predicate => $composableBuilder(
    column: $table.predicate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get objectType => $composableBuilder(
    column: $table.objectType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get objectUri => $composableBuilder(
    column: $table.objectUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get objectString => $composableBuilder(
    column: $table.objectString,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get objectInt => $composableBuilder(
    column: $table.objectInt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get objectReal => $composableBuilder(
    column: $table.objectReal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get graph => $composableBuilder(
    column: $table.graph,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncVersion => $composableBuilder(
    column: $table.syncVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TriplesTableAnnotationComposer
    extends Composer<_$KabukDatabase, $TriplesTable> {
  $$TriplesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get predicate =>
      $composableBuilder(column: $table.predicate, builder: (column) => column);

  GeneratedColumn<String> get objectType => $composableBuilder(
    column: $table.objectType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get objectUri =>
      $composableBuilder(column: $table.objectUri, builder: (column) => column);

  GeneratedColumn<String> get objectString => $composableBuilder(
    column: $table.objectString,
    builder: (column) => column,
  );

  GeneratedColumn<int> get objectInt =>
      $composableBuilder(column: $table.objectInt, builder: (column) => column);

  GeneratedColumn<double> get objectReal => $composableBuilder(
    column: $table.objectReal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get graph =>
      $composableBuilder(column: $table.graph, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get syncVersion => $composableBuilder(
    column: $table.syncVersion,
    builder: (column) => column,
  );
}

class $$TriplesTableTableManager
    extends
        RootTableManager<
          _$KabukDatabase,
          $TriplesTable,
          Triple,
          $$TriplesTableFilterComposer,
          $$TriplesTableOrderingComposer,
          $$TriplesTableAnnotationComposer,
          $$TriplesTableCreateCompanionBuilder,
          $$TriplesTableUpdateCompanionBuilder,
          (Triple, BaseReferences<_$KabukDatabase, $TriplesTable, Triple>),
          Triple,
          PrefetchHooks Function()
        > {
  $$TriplesTableTableManager(_$KabukDatabase db, $TriplesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TriplesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TriplesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TriplesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> subject = const Value.absent(),
                Value<String> predicate = const Value.absent(),
                Value<String> objectType = const Value.absent(),
                Value<String?> objectUri = const Value.absent(),
                Value<String?> objectString = const Value.absent(),
                Value<int?> objectInt = const Value.absent(),
                Value<double?> objectReal = const Value.absent(),
                Value<String> graph = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> syncVersion = const Value.absent(),
              }) => TriplesCompanion(
                id: id,
                subject: subject,
                predicate: predicate,
                objectType: objectType,
                objectUri: objectUri,
                objectString: objectString,
                objectInt: objectInt,
                objectReal: objectReal,
                graph: graph,
                createdAt: createdAt,
                updatedAt: updatedAt,
                syncVersion: syncVersion,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String subject,
                required String predicate,
                required String objectType,
                Value<String?> objectUri = const Value.absent(),
                Value<String?> objectString = const Value.absent(),
                Value<int?> objectInt = const Value.absent(),
                Value<double?> objectReal = const Value.absent(),
                Value<String> graph = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> syncVersion = const Value.absent(),
              }) => TriplesCompanion.insert(
                id: id,
                subject: subject,
                predicate: predicate,
                objectType: objectType,
                objectUri: objectUri,
                objectString: objectString,
                objectInt: objectInt,
                objectReal: objectReal,
                graph: graph,
                createdAt: createdAt,
                updatedAt: updatedAt,
                syncVersion: syncVersion,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TriplesTableProcessedTableManager =
    ProcessedTableManager<
      _$KabukDatabase,
      $TriplesTable,
      Triple,
      $$TriplesTableFilterComposer,
      $$TriplesTableOrderingComposer,
      $$TriplesTableAnnotationComposer,
      $$TriplesTableCreateCompanionBuilder,
      $$TriplesTableUpdateCompanionBuilder,
      (Triple, BaseReferences<_$KabukDatabase, $TriplesTable, Triple>),
      Triple,
      PrefetchHooks Function()
    >;
typedef $$BlobsTableCreateCompanionBuilder =
    BlobsCompanion Function({
      required String hash,
      required Uint8List data,
      Value<String?> mimeType,
      required int size,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$BlobsTableUpdateCompanionBuilder =
    BlobsCompanion Function({
      Value<String> hash,
      Value<Uint8List> data,
      Value<String?> mimeType,
      Value<int> size,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$BlobsTableFilterComposer
    extends Composer<_$KabukDatabase, $BlobsTable> {
  $$BlobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get hash => $composableBuilder(
    column: $table.hash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BlobsTableOrderingComposer
    extends Composer<_$KabukDatabase, $BlobsTable> {
  $$BlobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get hash => $composableBuilder(
    column: $table.hash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BlobsTableAnnotationComposer
    extends Composer<_$KabukDatabase, $BlobsTable> {
  $$BlobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get hash =>
      $composableBuilder(column: $table.hash, builder: (column) => column);

  GeneratedColumn<Uint8List> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$BlobsTableTableManager
    extends
        RootTableManager<
          _$KabukDatabase,
          $BlobsTable,
          Blob,
          $$BlobsTableFilterComposer,
          $$BlobsTableOrderingComposer,
          $$BlobsTableAnnotationComposer,
          $$BlobsTableCreateCompanionBuilder,
          $$BlobsTableUpdateCompanionBuilder,
          (Blob, BaseReferences<_$KabukDatabase, $BlobsTable, Blob>),
          Blob,
          PrefetchHooks Function()
        > {
  $$BlobsTableTableManager(_$KabukDatabase db, $BlobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BlobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BlobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BlobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> hash = const Value.absent(),
                Value<Uint8List> data = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BlobsCompanion(
                hash: hash,
                data: data,
                mimeType: mimeType,
                size: size,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String hash,
                required Uint8List data,
                Value<String?> mimeType = const Value.absent(),
                required int size,
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BlobsCompanion.insert(
                hash: hash,
                data: data,
                mimeType: mimeType,
                size: size,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BlobsTableProcessedTableManager =
    ProcessedTableManager<
      _$KabukDatabase,
      $BlobsTable,
      Blob,
      $$BlobsTableFilterComposer,
      $$BlobsTableOrderingComposer,
      $$BlobsTableAnnotationComposer,
      $$BlobsTableCreateCompanionBuilder,
      $$BlobsTableUpdateCompanionBuilder,
      (Blob, BaseReferences<_$KabukDatabase, $BlobsTable, Blob>),
      Blob,
      PrefetchHooks Function()
    >;
typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      required String id,
      required String conversationId,
      required String role,
      Value<String?> agentName,
      required String content,
      Value<String?> metadata,
      required DateTime timestamp,
      Value<String?> nostrEventId,
      Value<String> status,
      Value<String?> replyToId,
      Value<bool> isPinned,
      Value<DateTime?> expiresAt,
      Value<int> rowid,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<String> id,
      Value<String> conversationId,
      Value<String> role,
      Value<String?> agentName,
      Value<String> content,
      Value<String?> metadata,
      Value<DateTime> timestamp,
      Value<String?> nostrEventId,
      Value<String> status,
      Value<String?> replyToId,
      Value<bool> isPinned,
      Value<DateTime?> expiresAt,
      Value<int> rowid,
    });

class $$MessagesTableFilterComposer
    extends Composer<_$KabukDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nostrEventId => $composableBuilder(
    column: $table.nostrEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToId => $composableBuilder(
    column: $table.replyToId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessagesTableOrderingComposer
    extends Composer<_$KabukDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nostrEventId => $composableBuilder(
    column: $table.nostrEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToId => $composableBuilder(
    column: $table.replyToId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$KabukDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get agentName =>
      $composableBuilder(column: $table.agentName, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get metadata =>
      $composableBuilder(column: $table.metadata, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get nostrEventId => $composableBuilder(
    column: $table.nostrEventId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get replyToId =>
      $composableBuilder(column: $table.replyToId, builder: (column) => column);

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$KabukDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, BaseReferences<_$KabukDatabase, $MessagesTable, Message>),
          Message,
          PrefetchHooks Function()
        > {
  $$MessagesTableTableManager(_$KabukDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String?> agentName = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> metadata = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<String?> nostrEventId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> replyToId = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                conversationId: conversationId,
                role: role,
                agentName: agentName,
                content: content,
                metadata: metadata,
                timestamp: timestamp,
                nostrEventId: nostrEventId,
                status: status,
                replyToId: replyToId,
                isPinned: isPinned,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String conversationId,
                required String role,
                Value<String?> agentName = const Value.absent(),
                required String content,
                Value<String?> metadata = const Value.absent(),
                required DateTime timestamp,
                Value<String?> nostrEventId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> replyToId = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                id: id,
                conversationId: conversationId,
                role: role,
                agentName: agentName,
                content: content,
                metadata: metadata,
                timestamp: timestamp,
                nostrEventId: nostrEventId,
                status: status,
                replyToId: replyToId,
                isPinned: isPinned,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$KabukDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, BaseReferences<_$KabukDatabase, $MessagesTable, Message>),
      Message,
      PrefetchHooks Function()
    >;
typedef $$ConversationsTableCreateCompanionBuilder =
    ConversationsCompanion Function({
      required String id,
      Value<String> title,
      Value<String?> agentName,
      Value<String> type,
      Value<String?> nostrPubkey,
      Value<bool> isPinned,
      Value<bool> isArchived,
      Value<bool> isMuted,
      Value<int> unreadCount,
      Value<String?> lastMessage,
      Value<DateTime?> lastMessageAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ConversationsTableUpdateCompanionBuilder =
    ConversationsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> agentName,
      Value<String> type,
      Value<String?> nostrPubkey,
      Value<bool> isPinned,
      Value<bool> isArchived,
      Value<bool> isMuted,
      Value<int> unreadCount,
      Value<String?> lastMessage,
      Value<DateTime?> lastMessageAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ConversationsTableFilterComposer
    extends Composer<_$KabukDatabase, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nostrPubkey => $composableBuilder(
    column: $table.nostrPubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isMuted => $composableBuilder(
    column: $table.isMuted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessage => $composableBuilder(
    column: $table.lastMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$KabukDatabase, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nostrPubkey => $composableBuilder(
    column: $table.nostrPubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isMuted => $composableBuilder(
    column: $table.isMuted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessage => $composableBuilder(
    column: $table.lastMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$KabukDatabase, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get agentName =>
      $composableBuilder(column: $table.agentName, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get nostrPubkey => $composableBuilder(
    column: $table.nostrPubkey,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isMuted =>
      $composableBuilder(column: $table.isMuted, builder: (column) => column);

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastMessage => $composableBuilder(
    column: $table.lastMessage,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ConversationsTableTableManager
    extends
        RootTableManager<
          _$KabukDatabase,
          $ConversationsTable,
          Conversation,
          $$ConversationsTableFilterComposer,
          $$ConversationsTableOrderingComposer,
          $$ConversationsTableAnnotationComposer,
          $$ConversationsTableCreateCompanionBuilder,
          $$ConversationsTableUpdateCompanionBuilder,
          (
            Conversation,
            BaseReferences<_$KabukDatabase, $ConversationsTable, Conversation>,
          ),
          Conversation,
          PrefetchHooks Function()
        > {
  $$ConversationsTableTableManager(
    _$KabukDatabase db,
    $ConversationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> agentName = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> nostrPubkey = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<bool> isMuted = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<String?> lastMessage = const Value.absent(),
                Value<DateTime?> lastMessageAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion(
                id: id,
                title: title,
                agentName: agentName,
                type: type,
                nostrPubkey: nostrPubkey,
                isPinned: isPinned,
                isArchived: isArchived,
                isMuted: isMuted,
                unreadCount: unreadCount,
                lastMessage: lastMessage,
                lastMessageAt: lastMessageAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> title = const Value.absent(),
                Value<String?> agentName = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> nostrPubkey = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<bool> isMuted = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<String?> lastMessage = const Value.absent(),
                Value<DateTime?> lastMessageAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion.insert(
                id: id,
                title: title,
                agentName: agentName,
                type: type,
                nostrPubkey: nostrPubkey,
                isPinned: isPinned,
                isArchived: isArchived,
                isMuted: isMuted,
                unreadCount: unreadCount,
                lastMessage: lastMessage,
                lastMessageAt: lastMessageAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$KabukDatabase,
      $ConversationsTable,
      Conversation,
      $$ConversationsTableFilterComposer,
      $$ConversationsTableOrderingComposer,
      $$ConversationsTableAnnotationComposer,
      $$ConversationsTableCreateCompanionBuilder,
      $$ConversationsTableUpdateCompanionBuilder,
      (
        Conversation,
        BaseReferences<_$KabukDatabase, $ConversationsTable, Conversation>,
      ),
      Conversation,
      PrefetchHooks Function()
    >;
typedef $$MessageReactionsTableCreateCompanionBuilder =
    MessageReactionsCompanion Function({
      Value<int> id,
      required String messageId,
      required String conversationId,
      required String pubkey,
      Value<String> reaction,
      Value<String?> nostrEventId,
      Value<DateTime> createdAt,
    });
typedef $$MessageReactionsTableUpdateCompanionBuilder =
    MessageReactionsCompanion Function({
      Value<int> id,
      Value<String> messageId,
      Value<String> conversationId,
      Value<String> pubkey,
      Value<String> reaction,
      Value<String?> nostrEventId,
      Value<DateTime> createdAt,
    });

class $$MessageReactionsTableFilterComposer
    extends Composer<_$KabukDatabase, $MessageReactionsTable> {
  $$MessageReactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reaction => $composableBuilder(
    column: $table.reaction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nostrEventId => $composableBuilder(
    column: $table.nostrEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessageReactionsTableOrderingComposer
    extends Composer<_$KabukDatabase, $MessageReactionsTable> {
  $$MessageReactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reaction => $composableBuilder(
    column: $table.reaction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nostrEventId => $composableBuilder(
    column: $table.nostrEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessageReactionsTableAnnotationComposer
    extends Composer<_$KabukDatabase, $MessageReactionsTable> {
  $$MessageReactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pubkey =>
      $composableBuilder(column: $table.pubkey, builder: (column) => column);

  GeneratedColumn<String> get reaction =>
      $composableBuilder(column: $table.reaction, builder: (column) => column);

  GeneratedColumn<String> get nostrEventId => $composableBuilder(
    column: $table.nostrEventId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$MessageReactionsTableTableManager
    extends
        RootTableManager<
          _$KabukDatabase,
          $MessageReactionsTable,
          MessageReaction,
          $$MessageReactionsTableFilterComposer,
          $$MessageReactionsTableOrderingComposer,
          $$MessageReactionsTableAnnotationComposer,
          $$MessageReactionsTableCreateCompanionBuilder,
          $$MessageReactionsTableUpdateCompanionBuilder,
          (
            MessageReaction,
            BaseReferences<
              _$KabukDatabase,
              $MessageReactionsTable,
              MessageReaction
            >,
          ),
          MessageReaction,
          PrefetchHooks Function()
        > {
  $$MessageReactionsTableTableManager(
    _$KabukDatabase db,
    $MessageReactionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageReactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessageReactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessageReactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> pubkey = const Value.absent(),
                Value<String> reaction = const Value.absent(),
                Value<String?> nostrEventId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => MessageReactionsCompanion(
                id: id,
                messageId: messageId,
                conversationId: conversationId,
                pubkey: pubkey,
                reaction: reaction,
                nostrEventId: nostrEventId,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String messageId,
                required String conversationId,
                required String pubkey,
                Value<String> reaction = const Value.absent(),
                Value<String?> nostrEventId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => MessageReactionsCompanion.insert(
                id: id,
                messageId: messageId,
                conversationId: conversationId,
                pubkey: pubkey,
                reaction: reaction,
                nostrEventId: nostrEventId,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessageReactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$KabukDatabase,
      $MessageReactionsTable,
      MessageReaction,
      $$MessageReactionsTableFilterComposer,
      $$MessageReactionsTableOrderingComposer,
      $$MessageReactionsTableAnnotationComposer,
      $$MessageReactionsTableCreateCompanionBuilder,
      $$MessageReactionsTableUpdateCompanionBuilder,
      (
        MessageReaction,
        BaseReferences<
          _$KabukDatabase,
          $MessageReactionsTable,
          MessageReaction
        >,
      ),
      MessageReaction,
      PrefetchHooks Function()
    >;
typedef $$DevicePairsTableCreateCompanionBuilder =
    DevicePairsCompanion Function({
      required String localDeviceId,
      required String remoteDeviceId,
      required String remoteName,
      Value<String?> remoteAddress,
      required String sharedPublicKeyHex,
      required String pairingToken,
      Value<DateTime> createdAt,
      Value<DateTime> lastSeenAt,
      Value<DateTime?> lastSyncAt,
      Value<bool> isVerified,
      Value<int> rowid,
    });
typedef $$DevicePairsTableUpdateCompanionBuilder =
    DevicePairsCompanion Function({
      Value<String> localDeviceId,
      Value<String> remoteDeviceId,
      Value<String> remoteName,
      Value<String?> remoteAddress,
      Value<String> sharedPublicKeyHex,
      Value<String> pairingToken,
      Value<DateTime> createdAt,
      Value<DateTime> lastSeenAt,
      Value<DateTime?> lastSyncAt,
      Value<bool> isVerified,
      Value<int> rowid,
    });

class $$DevicePairsTableFilterComposer
    extends Composer<_$KabukDatabase, $DevicePairsTable> {
  $$DevicePairsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localDeviceId => $composableBuilder(
    column: $table.localDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteDeviceId => $composableBuilder(
    column: $table.remoteDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteName => $composableBuilder(
    column: $table.remoteName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteAddress => $composableBuilder(
    column: $table.remoteAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sharedPublicKeyHex => $composableBuilder(
    column: $table.sharedPublicKeyHex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pairingToken => $composableBuilder(
    column: $table.pairingToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isVerified => $composableBuilder(
    column: $table.isVerified,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DevicePairsTableOrderingComposer
    extends Composer<_$KabukDatabase, $DevicePairsTable> {
  $$DevicePairsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localDeviceId => $composableBuilder(
    column: $table.localDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteDeviceId => $composableBuilder(
    column: $table.remoteDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteName => $composableBuilder(
    column: $table.remoteName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteAddress => $composableBuilder(
    column: $table.remoteAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sharedPublicKeyHex => $composableBuilder(
    column: $table.sharedPublicKeyHex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pairingToken => $composableBuilder(
    column: $table.pairingToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isVerified => $composableBuilder(
    column: $table.isVerified,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DevicePairsTableAnnotationComposer
    extends Composer<_$KabukDatabase, $DevicePairsTable> {
  $$DevicePairsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localDeviceId => $composableBuilder(
    column: $table.localDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remoteDeviceId => $composableBuilder(
    column: $table.remoteDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remoteName => $composableBuilder(
    column: $table.remoteName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remoteAddress => $composableBuilder(
    column: $table.remoteAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sharedPublicKeyHex => $composableBuilder(
    column: $table.sharedPublicKeyHex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pairingToken => $composableBuilder(
    column: $table.pairingToken,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isVerified => $composableBuilder(
    column: $table.isVerified,
    builder: (column) => column,
  );
}

class $$DevicePairsTableTableManager
    extends
        RootTableManager<
          _$KabukDatabase,
          $DevicePairsTable,
          DevicePair,
          $$DevicePairsTableFilterComposer,
          $$DevicePairsTableOrderingComposer,
          $$DevicePairsTableAnnotationComposer,
          $$DevicePairsTableCreateCompanionBuilder,
          $$DevicePairsTableUpdateCompanionBuilder,
          (
            DevicePair,
            BaseReferences<_$KabukDatabase, $DevicePairsTable, DevicePair>,
          ),
          DevicePair,
          PrefetchHooks Function()
        > {
  $$DevicePairsTableTableManager(_$KabukDatabase db, $DevicePairsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DevicePairsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DevicePairsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DevicePairsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> localDeviceId = const Value.absent(),
                Value<String> remoteDeviceId = const Value.absent(),
                Value<String> remoteName = const Value.absent(),
                Value<String?> remoteAddress = const Value.absent(),
                Value<String> sharedPublicKeyHex = const Value.absent(),
                Value<String> pairingToken = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> lastSeenAt = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<bool> isVerified = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicePairsCompanion(
                localDeviceId: localDeviceId,
                remoteDeviceId: remoteDeviceId,
                remoteName: remoteName,
                remoteAddress: remoteAddress,
                sharedPublicKeyHex: sharedPublicKeyHex,
                pairingToken: pairingToken,
                createdAt: createdAt,
                lastSeenAt: lastSeenAt,
                lastSyncAt: lastSyncAt,
                isVerified: isVerified,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localDeviceId,
                required String remoteDeviceId,
                required String remoteName,
                Value<String?> remoteAddress = const Value.absent(),
                required String sharedPublicKeyHex,
                required String pairingToken,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> lastSeenAt = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<bool> isVerified = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicePairsCompanion.insert(
                localDeviceId: localDeviceId,
                remoteDeviceId: remoteDeviceId,
                remoteName: remoteName,
                remoteAddress: remoteAddress,
                sharedPublicKeyHex: sharedPublicKeyHex,
                pairingToken: pairingToken,
                createdAt: createdAt,
                lastSeenAt: lastSeenAt,
                lastSyncAt: lastSyncAt,
                isVerified: isVerified,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DevicePairsTableProcessedTableManager =
    ProcessedTableManager<
      _$KabukDatabase,
      $DevicePairsTable,
      DevicePair,
      $$DevicePairsTableFilterComposer,
      $$DevicePairsTableOrderingComposer,
      $$DevicePairsTableAnnotationComposer,
      $$DevicePairsTableCreateCompanionBuilder,
      $$DevicePairsTableUpdateCompanionBuilder,
      (
        DevicePair,
        BaseReferences<_$KabukDatabase, $DevicePairsTable, DevicePair>,
      ),
      DevicePair,
      PrefetchHooks Function()
    >;

class $KabukDatabaseManager {
  final _$KabukDatabase _db;
  $KabukDatabaseManager(this._db);
  $$TriplesTableTableManager get triples =>
      $$TriplesTableTableManager(_db, _db.triples);
  $$BlobsTableTableManager get blobs =>
      $$BlobsTableTableManager(_db, _db.blobs);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$MessageReactionsTableTableManager get messageReactions =>
      $$MessageReactionsTableTableManager(_db, _db.messageReactions);
  $$DevicePairsTableTableManager get devicePairs =>
      $$DevicePairsTableTableManager(_db, _db.devicePairs);
}
