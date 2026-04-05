/// Plugin lifecycle manager for registering, enabling, and querying
/// content plugins in Kabuk.
///
/// The [PluginRegistry] manages the full lifecycle of [ContentPlugin]
/// instances — registration, initialization, disposal — and persists
/// enabled state via the knowledge store. Riverpod providers expose
/// the registry and reactive enabled-plugin state to the UI layer.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/types/plugin.dart';
import 'package:kabuk/plugins/bundled/bandcamp_plugin.dart';
import 'package:kabuk/plugins/bundled/fourchan_plugin.dart';
import 'package:kabuk/plugins/bundled/hackernews_plugin.dart';
import 'package:kabuk/plugins/bundled/media_plugin.dart';
import 'package:kabuk/plugins/bundled/reddit_plugin.dart';
import 'package:kabuk/plugins/bundled/soundcloud_plugin.dart';
import 'package:kabuk/plugins/bundled/wikipedia_plugin.dart';
import 'package:kabuk/plugins/bundled/youtube_plugin.dart';
import 'package:kabuk/plugins/context.dart';
import 'package:kabuk/plugins/plugin.dart';

/// Manages content plugin registration, initialization, and disposal.
///
/// All bundled plugins are registered via [register] at startup. When
/// [initialize] is called, the registry loads persisted enabled state
/// from the knowledge store and initializes any previously-enabled
/// plugins. The UI can then call [enable] / [disable] to toggle
/// plugins at runtime.
class PluginRegistry {
  /// Creates a [PluginRegistry] backed by [store] for persistence.
  ///
  /// The [contextFactory] callback builds a [PluginContext] scoped to
  /// each plugin's identifier for sandboxed service access.
  PluginRegistry({
    required KnowledgeStore store,
    required PluginContext Function(String pluginId) contextFactory,
  })  : _store = store,
        _contextFactory = contextFactory;

  final KnowledgeStore _store;
  final PluginContext Function(String pluginId) _contextFactory;

  /// All bundled plugins available.
  final Map<String, ContentPlugin> _bundled = {};

  /// Currently enabled and initialized plugins.
  final Map<String, ContentPlugin> _active = {};

  /// Register a bundled plugin.
  ///
  /// This makes the plugin available for enabling but does not
  /// initialize it. Call [initialize] after all plugins are registered
  /// to restore previously-enabled state.
  void register(ContentPlugin plugin) {
    _bundled[plugin.id] = plugin;
  }

  /// All available plugins (bundled).
  List<ContentPlugin> get availablePlugins => _bundled.values.toList();

  /// Currently active (enabled + initialized) plugins.
  List<ContentPlugin> get activePlugins => _active.values.toList();

  /// Enable a plugin — initializes it and persists state.
  ///
  /// If the plugin is already active this is a no-op.
  /// Throws [ArgumentError] if [pluginId] is not a registered plugin.
  Future<void> enable(String pluginId) async {
    if (_active.containsKey(pluginId)) return;
    final plugin = _bundled[pluginId];
    if (plugin == null) {
      throw ArgumentError.value(pluginId, 'pluginId', 'Plugin not registered');
    }

    final ctx = _contextFactory(pluginId);
    await plugin.initialize(ctx);
    _active[pluginId] = plugin;

    // Persist enabled state.
    final existing = await _store.queryPlugin(pluginId);
    if (existing != null) {
      await _store.updatePluginEnabled(existing.uri, enabled: true);
    } else {
      await _store.createPlugin(pluginId: pluginId, enabled: true);
    }
  }

  /// Disable a plugin — disposes it and persists state.
  ///
  /// If the plugin is not active this is a no-op.
  Future<void> disable(String pluginId) async {
    final plugin = _active.remove(pluginId);
    if (plugin == null) return;

    await plugin.dispose();

    // Persist disabled state.
    final existing = await _store.queryPlugin(pluginId);
    if (existing != null) {
      await _store.updatePluginEnabled(existing.uri, enabled: false);
    }
  }

  /// Check if a plugin is enabled.
  bool isEnabled(String pluginId) => _active.containsKey(pluginId);

  /// Get active plugins that have a specific [capability].
  List<ContentPlugin> pluginsForCapability(ContentCapability capability) {
    return _active.values
        .where((p) => p.capabilities.contains(capability))
        .toList();
  }

  /// Try to resolve a [url] through active plugins.
  ///
  /// Returns the first matching plugin and its [ResolvedContent],
  /// or `null` if no plugin can handle the URL.
  Future<(ContentPlugin, ResolvedContent)?> resolveUrl(String url) async {
    for (final plugin in _active.values) {
      if (!plugin.hasCapability(ContentCapability.urlResolve)) continue;
      if (!plugin.canHandleUrl(url)) continue;
      final resolved = await plugin.resolveUrl(url);
      if (resolved is ResolvedNotHandled) continue;
      return (plugin, resolved);
    }
    return null;
  }

  /// Initialize — loads persisted enabled state and initializes saved plugins.
  ///
  /// Call this once after all bundled plugins have been [register]ed.
  /// Reads the knowledge store for previously-enabled plugins and
  /// initializes them in order.
  Future<void> initialize() async {
    final persisted = await _store.queryPlugins();
    for (final data in persisted) {
      if (!data.enabled) continue;
      final plugin = _bundled[data.pluginId];
      if (plugin == null) continue;

      final ctx = _contextFactory(data.pluginId);
      await plugin.initialize(ctx);
      _active[data.pluginId] = plugin;
    }
  }

  /// Dispose all active plugins.
  Future<void> dispose() async {
    for (final plugin in _active.values) {
      await plugin.dispose();
    }
    _active.clear();
  }
}

// =============================================================================
// Riverpod Providers
// =============================================================================

/// The plugin registry instance — initialized once.
///
/// Depends on [knowledgeStoreProvider] for persistence. All bundled
/// plugins should be registered in the provider body before the
/// registry is returned. The registry's [PluginRegistry.initialize]
/// should be called during app startup to restore enabled state.
final pluginRegistryProvider = Provider<PluginRegistry>((ref) {
  final store = ref.watch(knowledgeStoreProvider);
  final vault = ref.watch(vaultServiceProvider);
  final httpClient = http.Client();
  final registry = PluginRegistry(
    store: store,
    contextFactory: (pluginId) => PluginContext(
      pluginId: pluginId,
      httpClient: httpClient,
      vault: vault,
      store: store,
      getConfig: (_) => null,
      log: (message, {error}) {},
    ),
  );
  registerBundledPlugins(registry);
  ref.onDispose(() {
    registry.dispose();
    httpClient.close();
  });
  return registry;
});

/// Reactive set of enabled plugin IDs for UI state.
///
/// Updated when plugins are enabled or disabled so that widgets
/// watching this provider rebuild automatically.
final enabledPluginIdsProvider = StateProvider<Set<String>>((ref) => {});

/// Registers all bundled content plugins with the [registry].
void registerBundledPlugins(PluginRegistry registry) {
  registry.register(RedditPlugin());
  registry.register(FourchanPlugin());
  registry.register(const MediaPlugin());
  registry.register(const YouTubePlugin());
  registry.register(const HackerNewsPlugin());
  registry.register(const WikipediaPlugin());
  registry.register(const SoundCloudPlugin());
  registry.register(const BandcampPlugin());
}
