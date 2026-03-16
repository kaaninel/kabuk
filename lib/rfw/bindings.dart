/// RFW data bindings — bridges knowledge store data to RFW widgets.
///
/// Populates `DynamicContent` objects from the knowledge store's RDF
/// triples so that RFW widgets can bind to live data reactively.
library;

import 'dart:async';

import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:rfw/rfw.dart';

/// Bridges knowledge store data into RFW's [DynamicContent].
///
/// Supports three binding modes:
/// - **Entity binding**: a single subject URI → map of its predicates.
/// - **Query binding**: a query pattern → list of matching entities.
/// - **Static binding**: pre-resolved data already in memory.
///
/// Entity and query bindings are reactive: when the knowledge store
/// changes, the [DynamicContent] is refreshed automatically.
class RfwDataBindings {
  /// Creates [RfwDataBindings] connected to a [KnowledgeStore].
  RfwDataBindings(this._store);

  final KnowledgeStore _store;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Create a [DynamicContent] from a map of bindings.
  ///
  /// Each key in [bindings] is a data key accessible in RFW templates.
  /// Values can be:
  /// - A `String` starting with `'entity:'` — binds to a subject URI.
  /// - A `String` starting with `'query:'` — binds to a query predicate.
  /// - Any other value — used as-is (static binding).
  ///
  /// The returned [DynamicContent] is a live object that updates when
  /// underlying data changes.
  Future<DynamicContent> resolve(Map<String, dynamic> bindings) async {
    final content = DynamicContent();

    for (final entry in bindings.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is String && value.startsWith('entity:')) {
        await _bindEntity(content, key, value.substring(7));
      } else if (value is String && value.startsWith('query:')) {
        await _bindQuery(content, key, value.substring(6));
      } else {
        _bindStatic(content, key, value);
      }
    }

    return content;
  }

  /// Bind a single entity's triples as a map under [key].
  ///
  /// The resulting map contains predicate local names as keys
  /// and object values as values.
  Future<void> _bindEntity(
    DynamicContent content,
    String key,
    String subjectUri,
  ) async {
    final triples = await _store.getEntity(subjectUri);
    content.update(key, _triplesToMap(triples));

    // Watch for changes.
    final sub = _store.watch(subject: subjectUri).listen((updated) {
      content.update(key, _triplesToMap(updated));
    });
    _subscriptions.add(sub);
  }

  /// Bind a query result as a list of entity maps under [key].
  Future<void> _bindQuery(
    DynamicContent content,
    String key,
    String predicate,
  ) async {
    final triples = await _store.query().predicate(predicate).execute();

    // Group by subject.
    final grouped = _groupBySubject(triples);
    content.update(key, grouped);

    // Watch for changes.
    final sub = _store.watch(predicate: predicate).listen((updated) {
      content.update(key, _groupBySubject(updated));
    });
    _subscriptions.add(sub);
  }

  /// Bind a static value directly.
  void _bindStatic(DynamicContent content, String key, Object? value) {
    content.update(key, _toDynamicValue(value));
  }

  /// Convert a list of triples for one subject into a [DynamicMap].
  Object _triplesToMap(List<Triple> triples) {
    final map = <String, Object>{};
    for (final triple in triples) {
      final predicateName = _localName(triple.predicate);
      map[predicateName] = triple.objectValue;
    }
    return map;
  }

  /// Group triples by subject, returning a list of maps.
  Object _groupBySubject(List<Triple> triples) {
    final groups = <String, Map<String, Object>>{};
    for (final triple in triples) {
      final map = groups.putIfAbsent(triple.subject, () => {});
      map[_localName(triple.predicate)] = triple.objectValue;
    }
    return groups.values.toList();
  }

  /// Extract the local name from a URI (after last `/` or `#`).
  String _localName(String uri) {
    final hash = uri.lastIndexOf('#');
    final slash = uri.lastIndexOf('/');
    final sep = hash > slash ? hash : slash;
    return sep >= 0 ? uri.substring(sep + 1) : uri;
  }

  /// Convert a Dart value to something RFW's DynamicContent accepts.
  Object _toDynamicValue(Object? value) {
    if (value == null) return '';
    if (value is String || value is int || value is double || value is bool) {
      return value;
    }
    if (value is List) {
      return value.map(_toDynamicValue).toList();
    }
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _toDynamicValue(v)));
    }
    return value.toString();
  }

  /// Cancel all active subscriptions.
  ///
  /// Call this when the widget or view using these bindings is disposed.
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}
