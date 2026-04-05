/// Riverpod providers for marketplace state management.
///
/// Provides category filtering, search, and a derived filtered list
/// of available plugins with their enabled status.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/plugins/plugin.dart';
import 'package:kabuk/plugins/registry.dart';

/// Selected category filter (`null` means show all).
final marketplaceCategoryProvider = StateProvider<PluginCategory?>((ref) => null);

/// Search query for filtering plugins.
final marketplaceSearchProvider = StateProvider<String>((ref) => '');

/// Filtered list of available plugins paired with their enabled state.
///
/// Applies the current [marketplaceCategoryProvider] filter first, then
/// the [marketplaceSearchProvider] text search against name + description.
final filteredPluginsProvider =
    Provider<List<({ContentPlugin plugin, bool enabled})>>((ref) {
  final registry = ref.watch(pluginRegistryProvider);
  final enabledIds = ref.watch(enabledPluginIdsProvider);
  final category = ref.watch(marketplaceCategoryProvider);
  final search = ref.watch(marketplaceSearchProvider).toLowerCase();

  var plugins = registry.availablePlugins;

  // Filter by category.
  if (category != null) {
    plugins = plugins.where((p) => p.category == category).toList();
  }

  // Filter by search query.
  if (search.isNotEmpty) {
    plugins = plugins
        .where(
          (p) =>
              p.name.toLowerCase().contains(search) ||
              p.description.toLowerCase().contains(search),
        )
        .toList();
  }

  return plugins
      .map((p) => (plugin: p, enabled: enabledIds.contains(p.id)))
      .toList();
});
