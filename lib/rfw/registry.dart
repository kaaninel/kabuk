/// RFW widget registry — stores and retrieves widget libraries.
///
/// The registry is the single point of access for finding widget
/// definitions by library name and widget name. Libraries can be
/// registered at startup (built-in) or installed dynamically.
library;

import 'package:kabuk/rfw/models.dart';

/// Stores and retrieves RFW widget libraries.
///
/// The registry maintains an in-memory index of all installed
/// widget libraries. Each library is identified by a namespaced
/// name (e.g., `'kabuk:core'`). The registry supports lookup by
/// library + widget name, or by Schema.org type.
///
/// ```dart
/// final registry = RfwRegistry();
/// registry.install(coreLibrary);
/// final widgetDef = registry.getWidget('kabuk:core', 'Card');
/// ```
class RfwRegistry {
  /// Creates an empty [RfwRegistry].
  RfwRegistry();

  final Map<String, RfwLibrary> _libraries = {};

  /// All installed library names.
  Iterable<String> get libraryNames => _libraries.keys;

  /// All installed libraries.
  Iterable<RfwLibrary> get libraries => _libraries.values;

  /// Install a widget [library].
  ///
  /// If a library with the same name already exists, it is replaced.
  void install(RfwLibrary library) {
    _libraries[library.name] = library;
  }

  /// Uninstall a library by [name].
  ///
  /// Returns `true` if the library was present and removed.
  bool uninstall(String name) => _libraries.remove(name) != null;

  /// Get a library by [name], or `null` if not installed.
  RfwLibrary? getLibrary(String name) => _libraries[name];

  /// Get a widget definition by [libraryName] and [widgetName].
  ///
  /// Returns `null` if the library or widget is not found.
  RfwWidgetDef? getWidget(String libraryName, String widgetName) {
    return _libraries[libraryName]?.widgets[widgetName];
  }

  /// Find all widget definitions that declare support for a
  /// given Schema.org [typeUri].
  ///
  /// Returns a list of `(libraryName, widgetDef)` pairs.
  List<(String, RfwWidgetDef)> findWidgetsForType(String typeUri) {
    final results = <(String, RfwWidgetDef)>[];
    for (final lib in _libraries.values) {
      if (lib.schemaTypes.contains(typeUri)) {
        for (final widget in lib.widgets.values) {
          results.add((lib.name, widget));
        }
      }
    }
    return results;
  }

  /// Check if all dependencies for a [library] are satisfied.
  ///
  /// Returns a list of missing dependency names. An empty list
  /// means all dependencies are satisfied.
  List<String> checkDependencies(RfwLibrary library) {
    final missing = <String>[];
    for (final dep in library.dependencies) {
      // Parse "name >= version" format.
      final parts = dep.split(' ');
      final name = parts.first;
      if (!_libraries.containsKey(name)) {
        missing.add(dep);
      }
    }
    return missing;
  }

  /// Clear all installed libraries.
  void clear() => _libraries.clear();
}
