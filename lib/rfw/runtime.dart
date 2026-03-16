/// RFW runtime — parses, resolves, and renders Remote Flutter Widgets.
///
/// The runtime is the central coordinator for dynamic UI rendering.
/// It accepts RFW template source text or library references from
/// agent tool results, resolves data bindings from the knowledge
/// store, and produces Flutter widgets.
library;

import 'package:flutter/material.dart';
import 'package:kabuk/config/constants.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/rfw/bindings.dart';
import 'package:kabuk/rfw/registry.dart';
import 'package:rfw/formats.dart'
    as rfw_model
    show ConstructorCall, Switch, WidgetBuilderDeclaration;
import 'package:rfw/formats.dart'
    hide ConstructorCall, Switch, WidgetBuilderDeclaration;
import 'package:rfw/rfw.dart';

/// Callback for handling widget events from RFW.
typedef RfwEventHandler =
    void Function(String widgetName, String eventName, DynamicMap arguments);

/// Orchestrates RFW template resolution, data binding, and rendering.
///
/// The runtime maintains a connection to the [RfwRegistry] for widget
/// library lookup and the [KnowledgeStore] for data bindings. It
/// provides methods to render both library-referenced and raw RFW
/// templates as Flutter widgets.
///
/// ```dart
/// final runtime = KabukRfwRuntime(
///   registry: registry,
///   store: knowledgeStore,
/// );
///
/// // Render a registered widget.
/// final widget = await runtime.renderWidget(
///   libraryName: 'kabuk:core',
///   widgetName: 'Card',
///   bindings: {'title': 'Hello', 'body': 'World'},
/// );
///
/// // Render a raw RFW template.
/// final widget2 = await runtime.renderRaw(
///   source: 'import core; widget Root = Text(text: data.greeting);',
///   data: {'greeting': 'Hello, Kabuk!'},
/// );
/// ```
class KabukRfwRuntime {
  /// Creates a [KabukRfwRuntime] connected to a [registry] and [store].
  KabukRfwRuntime({required this.registry, required this.store}) {
    _initCoreLibraries();
  }

  /// The widget library registry.
  final RfwRegistry registry;

  /// The knowledge store for data bindings.
  final KnowledgeStore store;

  /// The underlying RFW runtime.
  late final Runtime _runtime = Runtime();

  /// Active data binding instances (for disposal).
  final List<RfwDataBindings> _activeBindings = [];

  /// Cache of source → transient library name to avoid re-registering
  /// the same template multiple times (which leaks `_runtime` entries).
  final Map<String, LibraryName> _sourceLibraryCache = {};

  /// Initialize the core Material and local widget libraries.
  void _initCoreLibraries() {
    _runtime.update(
      const LibraryName(<String>['core', 'widgets']),
      createCoreWidgets(),
    );
    _runtime.update(
      const LibraryName(<String>['core', 'material']),
      createMaterialWidgets(),
    );
  }

  /// Render an RFW widget from a registered library.
  ///
  /// Looks up the widget [widgetName] in [libraryName], resolves
  /// the [bindings] from the knowledge store, and returns a
  /// Flutter widget tree.
  ///
  /// Returns an error widget if the library or widget is not found.
  Future<Widget> renderWidget({
    required String libraryName,
    required String widgetName,
    Map<String, dynamic> bindings = const {},
    RfwEventHandler? onEvent,
  }) async {
    final widgetDef = registry.getWidget(libraryName, widgetName);
    if (widgetDef == null) {
      return _errorWidget(
        'Widget "$widgetName" not found in library "$libraryName".',
      );
    }

    return renderRaw(
      source: widgetDef.rfwSource,
      data: bindings,
      onEvent: onEvent,
    );
  }

  /// Render a raw RFW template with inline data.
  ///
  /// Parses the [source] template, populates a [DynamicContent]
  /// from [data], and returns a live Flutter widget.
  ///
  /// Returns an error widget if parsing fails.
  Future<Widget> renderRaw({
    required String source,
    Map<String, dynamic> data = const {},
    RfwEventHandler? onEvent,
  }) async {
    try {
      // Validate before rendering to enforce depth/count limits.
      final validationError = validate(source);
      if (validationError != null) {
        return _errorWidget('Invalid template: $validationError');
      }

      // Parse the RFW template.
      final library = parseLibraryFile(source);

      // Re-use previously registered library if the source is identical.
      final libName = _sourceLibraryCache.putIfAbsent(source, () {
        final name = LibraryName(<String>['dynamic', '${_transientCounter++}']);
        _runtime.update(name, library);
        return name;
      });

      // Resolve data bindings.
      final dataBindings = RfwDataBindings(store);
      _activeBindings.add(dataBindings);
      final content = await dataBindings.resolve(data);

      // Build the rendered widget.
      return RemoteWidget(
        runtime: _runtime,
        data: content,
        widget: FullyQualifiedWidgetName(libName, 'Root'),
        onEvent: onEvent != null
            ? (String name, DynamicMap arguments) {
                onEvent('Root', name, arguments);
              }
            : null,
      );
    } on Exception catch (e) {
      return _errorWidget('Failed to render RFW template: $e');
    }
  }

  /// Validate an RFW template source without rendering.
  ///
  /// Checks for:
  /// 1. Parse errors — malformed RFW syntax.
  /// 2. Excessive widget depth — deeper than [AppConstants.maxRfwWidgetDepth].
  /// 3. Excessive widget count — more than [AppConstants.maxRfwWidgetCount].
  ///
  /// Returns `null` if valid, or an error message if invalid.
  String? validate(String source) {
    try {
      final library = parseLibraryFile(source);

      // Validate structural limits on all widgets in the library.
      for (final widget in library.widgets) {
        final metrics = _measureWidget(widget.root, 0);
        if (metrics.depth > AppConstants.maxRfwWidgetDepth) {
          return 'Widget "${widget.name}" exceeds maximum nesting depth '
              '(${metrics.depth} > ${AppConstants.maxRfwWidgetDepth}).';
        }
        if (metrics.count > AppConstants.maxRfwWidgetCount) {
          return 'Widget "${widget.name}" exceeds maximum widget count '
              '(${metrics.count} > ${AppConstants.maxRfwWidgetCount}).';
        }
      }

      return null;
    } on Exception catch (e) {
      return e.toString();
    }
  }

  /// Measure the depth and count of a widget tree.
  _WidgetMetrics _measureWidget(BlobNode node, int currentDepth) {
    if (node is rfw_model.ConstructorCall) {
      var maxChildDepth = currentDepth;
      var totalCount = 1; // count this node
      for (final arg in node.arguments.entries) {
        final metrics = _measureValue(arg.value, currentDepth + 1);
        if (metrics.depth > maxChildDepth) maxChildDepth = metrics.depth;
        totalCount += metrics.count;
      }
      return _WidgetMetrics(depth: maxChildDepth, count: totalCount);
    }
    if (node is rfw_model.Switch) {
      var maxDepth = currentDepth;
      var totalCount = 0;
      for (final output in node.outputs.values) {
        final metrics = _measureValue(output, currentDepth);
        if (metrics.depth > maxDepth) maxDepth = metrics.depth;
        totalCount += metrics.count;
      }
      return _WidgetMetrics(depth: maxDepth, count: totalCount);
    }
    if (node is rfw_model.WidgetBuilderDeclaration) {
      return _measureWidget(node.widget, currentDepth + 1);
    }
    return _WidgetMetrics(depth: currentDepth, count: 0);
  }

  /// Measure depth/count in a value node (which may contain child widgets).
  _WidgetMetrics _measureValue(Object? value, int currentDepth) {
    if (value is rfw_model.ConstructorCall ||
        value is rfw_model.Switch ||
        value is rfw_model.WidgetBuilderDeclaration) {
      return _measureWidget(value as BlobNode, currentDepth);
    }
    if (value is List) {
      var maxDepth = currentDepth;
      var totalCount = 0;
      for (final item in value) {
        final metrics = _measureValue(item, currentDepth);
        if (metrics.depth > maxDepth) maxDepth = metrics.depth;
        totalCount += metrics.count;
      }
      return _WidgetMetrics(depth: maxDepth, count: totalCount);
    }
    if (value is Map) {
      var maxDepth = currentDepth;
      var totalCount = 0;
      for (final v in value.values) {
        final metrics = _measureValue(v, currentDepth);
        if (metrics.depth > maxDepth) maxDepth = metrics.depth;
        totalCount += metrics.count;
      }
      return _WidgetMetrics(depth: maxDepth, count: totalCount);
    }
    return _WidgetMetrics(depth: currentDepth, count: 0);
  }

  /// Build an error placeholder widget.
  Widget _errorWidget(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withAlpha(80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  int _transientCounter = 0;

  /// Dispose all active data bindings and clear the template cache.
  void dispose() {
    for (final binding in _activeBindings) {
      binding.dispose();
    }
    _activeBindings.clear();
    _sourceLibraryCache.clear();
  }
}

/// Internal metrics for RFW template structural validation.
class _WidgetMetrics {
  const _WidgetMetrics({required this.depth, required this.count});

  /// Maximum nesting depth in the widget tree.
  final int depth;

  /// Total number of widget nodes.
  final int count;
}
