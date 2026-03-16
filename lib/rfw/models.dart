/// RFW widget library and widget definition models.
///
/// These types describe the structure of an RFW widget library:
/// its metadata, individual widget definitions, and data contracts.
library;

/// A widget library containing one or more RFW widgets.
///
/// Libraries are identified by a namespaced name (e.g., `'kabuk:core'`)
/// and declare which Schema.org types they can render. Multiple widgets
/// may share the same library namespace.
///
/// ```dart
/// final lib = RfwLibrary(
///   name: 'kabuk:notes',
///   version: '1.0.0',
///   author: 'Kabuk Project',
///   description: 'Note display widgets',
///   widgets: { 'NoteCard': noteCardDef, 'NoteList': noteListDef },
///   dependencies: ['kabuk:core'],
///   schemaTypes: ['https://schema.org/Note'],
/// );
/// ```
class RfwLibrary {
  /// Creates an [RfwLibrary].
  const RfwLibrary({
    required this.name,
    required this.version,
    required this.author,
    required this.description,
    required this.widgets,
    this.dependencies = const [],
    this.schemaTypes = const [],
  });

  /// Namespaced identifier, e.g. `'kabuk:core'`.
  final String name;

  /// Semantic version string.
  final String version;

  /// Author or organization name.
  final String author;

  /// Human-readable description of the library.
  final String description;

  /// Widget name → definition map.
  final Map<String, RfwWidgetDef> widgets;

  /// Other libraries this library depends on.
  final List<String> dependencies;

  /// Schema.org types this library is designed to display.
  final List<String> schemaTypes;

  /// Serializes this library to JSON.
  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'author': author,
    'description': description,
    'dependencies': dependencies,
    'schemaTypes': schemaTypes,
    'widgets': widgets.map((k, v) => MapEntry(k, v.toJson())),
  };

  /// Deserializes from JSON.
  factory RfwLibrary.fromJson(Map<String, dynamic> json) => RfwLibrary(
    name: json['name'] as String,
    version: json['version'] as String,
    author: json['author'] as String? ?? '',
    description: json['description'] as String? ?? '',
    widgets:
        (json['widgets'] as Map<String, dynamic>?)?.map(
          (k, v) =>
              MapEntry(k, RfwWidgetDef.fromJson(v as Map<String, dynamic>)),
        ) ??
        {},
    dependencies:
        (json['dependencies'] as List<dynamic>?)?.cast<String>() ?? [],
    schemaTypes: (json['schemaTypes'] as List<dynamic>?)?.cast<String>() ?? [],
  );
}

/// A single widget definition within a library.
///
/// Contains the RFW template source, its expected data contract,
/// and the list of events the widget can emit.
class RfwWidgetDef {
  /// Creates an [RfwWidgetDef].
  const RfwWidgetDef({
    required this.name,
    required this.rfwSource,
    this.description = '',
    this.dataContract = const {},
    this.events = const [],
  });

  /// Widget name, unique within the library.
  final String name;

  /// Human-readable description.
  final String description;

  /// The RFW template source text.
  final String rfwSource;

  /// Expected data bindings: key → type description.
  final Map<String, String> dataContract;

  /// Events this widget can emit (e.g., `'onTap'`, `'onEdit'`).
  final List<String> events;

  /// Serializes this definition to JSON.
  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'rfwSource': rfwSource,
    'dataContract': dataContract,
    'events': events,
  };

  /// Deserializes from JSON.
  factory RfwWidgetDef.fromJson(Map<String, dynamic> json) => RfwWidgetDef(
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    rfwSource: json['rfwSource'] as String? ?? '',
    dataContract:
        (json['dataContract'] as Map<String, dynamic>?)
            ?.cast<String, String>() ??
        {},
    events: (json['events'] as List<dynamic>?)?.cast<String>() ?? [],
  );
}

/// Describes a data binding expected by an RFW widget.
///
/// Used in data contracts to tell the runtime what data
/// to fetch from the knowledge store for this widget.
class RfwBindingSpec {
  /// Creates an [RfwBindingSpec].
  const RfwBindingSpec({
    required this.key,
    required this.type,
    this.schemaType,
    this.required_ = true,
    this.defaultValue,
  });

  /// Binding key name.
  final String key;

  /// Type of data expected: `'uri'`, `'string'`, `'integer'`,
  /// `'query'`, `'list'`.
  final String type;

  /// Schema.org type this binding expects, if any.
  final String? schemaType;

  /// Whether this binding is required.
  final bool required_;

  /// Default value if not provided.
  final Object? defaultValue;
}
