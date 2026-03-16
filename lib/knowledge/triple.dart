/// RDF triple data types for the Kabuk knowledge store.
library;

import 'package:meta/meta.dart';

/// The type of an RDF object value.
enum ObjectType {
  /// A URI reference to another entity.
  uri,

  /// A string literal.
  string,

  /// An integer literal.
  integer,

  /// A floating-point literal.
  float,

  /// A datetime literal (ISO 8601).
  datetime,

  /// A boolean literal.
  boolean,

  /// A reference to a stored blob (content hash).
  blobRef,
}

/// An RDF triple — the fundamental unit of data in Kabuk.
///
/// Every piece of information is stored as a triple of
/// (subject, predicate, object). Subjects and predicates are URIs;
/// objects can be URIs or typed literals.
@immutable
class Triple {
  /// Creates an RDF triple with explicit field values.
  const Triple({
    this.id,
    required this.subject,
    required this.predicate,
    required this.objectValue,
    required this.objectType,
    this.objectLang,
    this.objectDatatype,
    this.graph = 'default',
    this.createdAt,
    this.updatedAt,
    this.encrypted = false,
  });

  /// Creates a triple with a URI object.
  const Triple.uri({
    this.id,
    required this.subject,
    required this.predicate,
    required String object,
    this.graph = 'default',
    this.createdAt,
    this.updatedAt,
    this.encrypted = false,
  }) : objectValue = object,
       objectType = ObjectType.uri,
       objectLang = null,
       objectDatatype = null;

  /// Creates a triple with a string literal object.
  const Triple.string({
    this.id,
    required this.subject,
    required this.predicate,
    required String object,
    this.objectLang,
    this.graph = 'default',
    this.createdAt,
    this.updatedAt,
    this.encrypted = false,
  }) : objectValue = object,
       objectType = ObjectType.string,
       objectDatatype = null;

  /// Creates a triple with an integer literal object.
  Triple.integer({
    this.id,
    required this.subject,
    required this.predicate,
    required int object,
    this.graph = 'default',
    this.createdAt,
    this.updatedAt,
    this.encrypted = false,
  }) : objectValue = object.toString(),
       objectType = ObjectType.integer,
       objectLang = null,
       objectDatatype = null;

  /// Creates a triple with a floating-point literal object.
  Triple.float({
    this.id,
    required this.subject,
    required this.predicate,
    required double object,
    this.graph = 'default',
    this.createdAt,
    this.updatedAt,
    this.encrypted = false,
  }) : objectValue = object.toString(),
       objectType = ObjectType.float,
       objectLang = null,
       objectDatatype = null;

  /// Creates a triple with a datetime literal object.
  Triple.datetime({
    this.id,
    required this.subject,
    required this.predicate,
    required DateTime object,
    this.graph = 'default',
    this.createdAt,
    this.updatedAt,
    this.encrypted = false,
  }) : objectValue = object.toIso8601String(),
       objectType = ObjectType.datetime,
       objectLang = null,
       objectDatatype = null;

  /// Creates a triple with a boolean literal object.
  Triple.boolean({
    this.id,
    required this.subject,
    required this.predicate,
    required bool object,
    this.graph = 'default',
    this.createdAt,
    this.updatedAt,
    this.encrypted = false,
  }) : objectValue = object.toString(),
       objectType = ObjectType.boolean,
       objectLang = null,
       objectDatatype = null;

  /// Creates a triple with a blob reference object.
  const Triple.blobRef({
    this.id,
    required this.subject,
    required this.predicate,
    required String hash,
    this.graph = 'default',
    this.createdAt,
    this.updatedAt,
    this.encrypted = false,
  }) : objectValue = hash,
       objectType = ObjectType.blobRef,
       objectLang = null,
       objectDatatype = null;

  /// The database row ID, if persisted.
  final int? id;

  /// The subject URI of this triple.
  final String subject;

  /// The predicate URI of this triple.
  final String predicate;

  /// The serialized object value.
  final String objectValue;

  /// The type of the object value.
  final ObjectType objectType;

  /// The language tag for string literals (e.g. 'en', 'tr').
  final String? objectLang;

  /// The datatype URI for typed literals.
  final String? objectDatatype;

  /// The named graph this triple belongs to.
  final String graph;

  /// When this triple was first created.
  final DateTime? createdAt;

  /// When this triple was last updated.
  final DateTime? updatedAt;

  /// Whether this triple's object value is encrypted at rest.
  final bool encrypted;

  /// Creates a copy of this triple with the given fields replaced.
  Triple copyWith({
    int? id,
    String? subject,
    String? predicate,
    String? objectValue,
    ObjectType? objectType,
    String? objectLang,
    String? objectDatatype,
    String? graph,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? encrypted,
  }) {
    return Triple(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      predicate: predicate ?? this.predicate,
      objectValue: objectValue ?? this.objectValue,
      objectType: objectType ?? this.objectType,
      objectLang: objectLang ?? this.objectLang,
      objectDatatype: objectDatatype ?? this.objectDatatype,
      graph: graph ?? this.graph,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      encrypted: encrypted ?? this.encrypted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Triple &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          subject == other.subject &&
          predicate == other.predicate &&
          objectValue == other.objectValue &&
          objectType == other.objectType &&
          objectLang == other.objectLang &&
          objectDatatype == other.objectDatatype &&
          graph == other.graph &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          encrypted == other.encrypted;

  @override
  int get hashCode => Object.hash(
    id,
    subject,
    predicate,
    objectValue,
    objectType,
    objectLang,
    objectDatatype,
    graph,
    createdAt,
    updatedAt,
    encrypted,
  );

  @override
  String toString() =>
      'Triple($subject, $predicate, $objectValue [$objectType]'
      '${graph != 'default' ? ', graph=$graph' : ''}'
      '${encrypted ? ', encrypted' : ''})';
}
