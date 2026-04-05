/// Plugin metadata knowledge store type for the Kabuk knowledge store.
///
/// Provides [PluginData] for structured access to Plugin entities
/// (registered content plugins), plus [KnowledgeStorePluginExtension]
/// convenience methods on [KnowledgeStore].
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

/// Immutable representation of a registered content plugin.
///
/// Stores metadata about a plugin's registration state in the
/// knowledge store, including whether it is enabled and any
/// persisted configuration.
@immutable
class PluginData {
  /// Creates a [PluginData] with the given field values.
  const PluginData({
    required this.uri,
    required this.pluginId,
    this.enabled = false,
    this.configJson,
    this.installedAt,
  });

  /// Constructs a [PluginData] from a subject [uri] and its [triples].
  factory PluginData.fromTriples(String uri, List<Triple> triples) {
    return PluginData(
      uri: uri,
      pluginId: triples
              .where((t) => t.predicate == NS.kabukPluginId)
              .firstOrNull
              ?.objectValue ??
          '',
      enabled: triples
              .where((t) => t.predicate == NS.kabukPluginEnabled)
              .firstOrNull
              ?.objectValue ==
          'true',
      configJson: triples
          .where((t) => t.predicate == NS.kabukPluginConfig)
          .firstOrNull
          ?.objectValue,
      installedAt: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.kabukPluginInstalledAt)
            .firstOrNull
            ?.objectValue,
      ),
    );
  }

  /// The entity URI (e.g. `kabuk:Plugin/<uuid>`).
  final String uri;

  /// The unique string identifier of the plugin (e.g. `rss`, `reddit`).
  final String pluginId;

  /// Whether the plugin is currently enabled.
  final bool enabled;

  /// JSON-encoded configuration map for the plugin, or `null` if unconfigured.
  final String? configJson;

  /// When the plugin was first registered in the knowledge store.
  final DateTime? installedAt;

  static DateTime? _tryParseDateTime(String? value) =>
      value == null ? null : DateTime.tryParse(value);
}

/// Convenience methods for working with Plugin entities in the knowledge store.
extension KnowledgeStorePluginExtension on KnowledgeStore {
  /// Creates a new Plugin entity and returns its URI.
  Future<String> createPlugin({
    required String pluginId,
    bool enabled = false,
    String? configJson,
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('Plugin');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.kabukPlugin,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.kabukPluginId, pluginId);
      await ctx.set(uri, NS.kabukPluginEnabled, enabled.toString());
      if (configJson != null) {
        await ctx.set(uri, NS.kabukPluginConfig, configJson);
      }
      await ctx.set(
        uri,
        NS.kabukPluginInstalledAt,
        DateTime.now().toIso8601String(),
      );
      return uri;
    });
  }

  /// Retrieves all registered plugins from the knowledge store.
  Future<List<PluginData>> queryPlugins() async {
    final typeTriples =
        await query().where(NS.rdfType, equals: NS.kabukPlugin).execute();
    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    final plugins = <PluginData>[];
    for (final uri in uris) {
      final triples = allTriples[uri];
      if (triples == null || triples.isEmpty) continue;
      plugins.add(PluginData.fromTriples(uri, triples));
    }
    return plugins;
  }

  /// Retrieves a single plugin by its [pluginId], or `null` if not found.
  Future<PluginData?> queryPlugin(String pluginId) async {
    final triples = await query()
        .where(NS.rdfType, equals: NS.kabukPlugin)
        .where(NS.kabukPluginId, equals: pluginId)
        .execute();
    if (triples.isEmpty) return null;
    final uri = triples.first.subject;
    final entityTriples = await getEntity(uri);
    if (entityTriples.isEmpty) return null;
    return PluginData.fromTriples(uri, entityTriples);
  }

  /// Updates whether a plugin is enabled.
  Future<void> updatePluginEnabled(String uri, {required bool enabled}) {
    return mutate((ctx) async {
      await ctx.set(uri, NS.kabukPluginEnabled, enabled.toString());
    });
  }

  /// Updates the JSON configuration for a plugin.
  Future<void> updatePluginConfig(String uri, {required String configJson}) {
    return mutate((ctx) async {
      await ctx.set(uri, NS.kabukPluginConfig, configJson);
    });
  }
}
