import "package:schema/schema.dart";
import "package:sqlite3/sqlite3.dart";

class Memory {
  static final Map<String, Memory> _cache = {};
  factory Memory(String id) =>
      _cache.putIfAbsent(id, () => Memory._(id, sqlite3.open("memory/$id.db")));

  final String id;
  final Database _db;
  Memory._(this.id, this._db) {
    _db.execute("""
CREATE TABLE IF NOT EXISTS quads (
  id PRIMARY KEY INCREMENTAL, 
  subject TEXT, 
  predicate TEXT, 
  object BLOB, 
  context BLOB,
  is_object_ref BOOLEAN,
  is_context_ref BOOLEAN
)""");
  }

  void add(Data data) {
    _db.execute("INSERT INTO quads VALUES (?, ?, ?, ?, ?, ?, ?)", data.toSQL());
  }

  Iterable<Data> find(
      {Subject? subject, Predicate? predicate, Object? object, Object? context}) {
    final where = [
      if (subject != null) "subject = ?",
      if (predicate != null) "predicate = ?",
      if (object != null) "object = ?",
      if (context != null) "context = ?",
    ].join(" AND ");
    final params = [
      if (subject != null) subject.toSQL(),
      if (predicate != null) predicate.toSQL(),
      if (object != null) object.toSQL(),
      if (context != null) context.toSQL(),
    ];
    final query = _db.prepare("SELECT * FROM quads WHERE $where");
    return query.select(params).map((row) => Data.fromSQL(row.values));
  }

  void close() {
    _db.dispose();
    _cache.remove(id);
  }
}
