/// Plugin marketplace page for browsing, enabling, and configuring
/// content plugins.
///
/// Displays a searchable, category-filtered grid of plugin cards.
/// Tapping a card opens a detail bottom sheet with full description,
/// capabilities, and configuration form.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/plugin.dart';
import 'package:kabuk/plugins/plugin.dart';
import 'package:kabuk/plugins/registry.dart';
import 'package:kabuk/ui/marketplace/marketplace_providers.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// MarketplacePage
// =============================================================================

/// Full-screen marketplace for browsing and managing content plugins.
class MarketplacePage extends ConsumerStatefulWidget {
  /// Creates a [MarketplacePage].
  const MarketplacePage({super.key});

  @override
  ConsumerState<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends ConsumerState<MarketplacePage> {
  bool _searching = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        ref.read(marketplaceSearchProvider.notifier).state = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final plugins = ref.watch(filteredPluginsProvider);
    final selectedCategory = ref.watch(marketplaceCategoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: context.kabukTextPrimary),
                decoration: InputDecoration(
                  hintText: 'Search plugins…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  fillColor: Colors.transparent,
                  filled: true,
                  hintStyle: TextStyle(color: context.kabukTextTertiary),
                ),
                onChanged: (value) {
                  ref.read(marketplaceSearchProvider.notifier).state = value;
                },
              )
            : const Text('Marketplace'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
        ],
      ),
      body: Column(
        children: [
          // Category chips
          _CategoryChips(
            selected: selectedCategory,
            onSelected: (cat) {
              ref.read(marketplaceCategoryProvider.notifier).state = cat;
            },
          ),

          // Plugin grid
          Expanded(
            child: plugins.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.extension_off_rounded,
                          size: 48,
                          color: context.kabukTextTertiary,
                        ),
                        const SizedBox(height: KabukTheme.spacingMd),
                        Text(
                          'No plugins found',
                          style: TextStyle(color: context.kabukTextSecondary),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(KabukTheme.spacingMd),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: KabukTheme.spacingSm,
                      crossAxisSpacing: KabukTheme.spacingSm,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: plugins.length,
                    itemBuilder: (context, index) {
                      final entry = plugins[index];
                      return _PluginCard(
                        plugin: entry.plugin,
                        enabled: entry.enabled,
                        onToggle: () => _togglePlugin(entry.plugin, entry.enabled),
                        onTap: () => _showDetail(context, entry.plugin, entry.enabled),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePlugin(ContentPlugin plugin, bool currentlyEnabled) async {
    final registry = ref.read(pluginRegistryProvider);
    final notifier = ref.read(enabledPluginIdsProvider.notifier);
    if (currentlyEnabled) {
      await registry.disable(plugin.id);
      notifier.state = {...notifier.state}..remove(plugin.id);
    } else {
      await registry.enable(plugin.id);
      notifier.state = {...notifier.state, plugin.id};
    }
  }

  void _showDetail(BuildContext context, ContentPlugin plugin, bool enabled) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.kabukSurfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusXl),
        ),
      ),
      builder: (_) => _PluginDetailSheet(
        plugin: plugin,
        initiallyEnabled: enabled,
      ),
    );
  }
}

// =============================================================================
// Category Chips
// =============================================================================

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.selected, required this.onSelected});

  final PluginCategory? selected;
  final ValueChanged<PluginCategory?> onSelected;

  static const _categories = [
    (null, 'All', Icons.apps_rounded),
    (PluginCategory.social, 'Social', Icons.people_rounded),
    (PluginCategory.media, 'Media', Icons.play_circle_rounded),
    (PluginCategory.news, 'News', Icons.newspaper_rounded),
    (PluginCategory.music, 'Music', Icons.music_note_rounded),
    (PluginCategory.reference, 'Reference', Icons.menu_book_rounded),
    (PluginCategory.other, 'Other', Icons.extension_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: KabukTheme.spacingMd),
        separatorBuilder: (_, _) =>
            const SizedBox(width: KabukTheme.spacingSm),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final (category, label, icon) = _categories[index];
          final isSelected = selected == category;
          return ChoiceChip(
            avatar: Icon(icon, size: 18),
            label: Text(label),
            selected: isSelected,
            backgroundColor: context.kabukSurfaceVariant,
            selectedColor: KabukTheme.primaryGreen.withAlpha(40),
            labelStyle: TextStyle(
              color: isSelected
                  ? KabukTheme.accentGreen
                  : context.kabukTextPrimary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 12,
            ),
            side: BorderSide(
              color: isSelected
                  ? KabukTheme.primaryGreen.withAlpha(80)
                  : context.kabukDivider,
              width: 0.5,
            ),
            onSelected: (_) => onSelected(category),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Plugin Card
// =============================================================================

class _PluginCard extends StatelessWidget {
  const _PluginCard({
    required this.plugin,
    required this.enabled,
    required this.onToggle,
    required this.onTap,
  });

  final ContentPlugin plugin;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: context.kabukSurfaceElevated,
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          border: Border.all(color: context.kabukDivider, width: 0.5),
        ),
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Icon(plugin.iconData, size: 36, color: _categoryColor(plugin.category)),
            const SizedBox(height: KabukTheme.spacingSm),

            // Name
            Text(
              plugin.name,
              style: TextStyle(
                color: context.kabukTextPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: KabukTheme.spacingXs),

            // Description
            Expanded(
              child: Text(
                plugin.description,
                style: TextStyle(
                  color: context.kabukTextSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Bottom row: category badge + toggle
            Row(
              children: [
                _CategoryBadge(category: plugin.category),
                const Spacer(),
                SizedBox(
                  height: 24,
                  child: Switch.adaptive(
                    value: enabled,
                    onChanged: (_) => onToggle(),
                    activeTrackColor: KabukTheme.primaryGreen,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Category Badge
// =============================================================================

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final PluginCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _categoryColor(category).withAlpha(25),
        borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
      ),
      child: Text(
        category.name[0].toUpperCase() + category.name.substring(1),
        style: TextStyle(
          color: _categoryColor(category),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Returns a consistent accent color for each [PluginCategory].
Color _categoryColor(PluginCategory category) {
  return switch (category) {
    PluginCategory.social => KabukTheme.blueAccent,
    PluginCategory.media => KabukTheme.warmAccent,
    PluginCategory.news => KabukTheme.accentGreen,
    PluginCategory.music => KabukTheme.purpleAccent,
    PluginCategory.reference => KabukTheme.primaryGreen,
    PluginCategory.other => KabukTheme.textSecondary,
  };
}

// =============================================================================
// Plugin Detail Bottom Sheet
// =============================================================================

class _PluginDetailSheet extends ConsumerStatefulWidget {
  const _PluginDetailSheet({
    required this.plugin,
    required this.initiallyEnabled,
  });

  final ContentPlugin plugin;
  final bool initiallyEnabled;

  @override
  ConsumerState<_PluginDetailSheet> createState() =>
      _PluginDetailSheetState();
}

class _PluginDetailSheetState extends ConsumerState<_PluginDetailSheet> {
  late bool _enabled;
  late Map<String, dynamic> _configValues;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initiallyEnabled;
    _configValues = {
      for (final field in widget.plugin.configFields)
        field.key: field.defaultValue ?? (field.type == PluginConfigFieldType.toggle ? 'false' : ''),
    };
  }

  @override
  Widget build(BuildContext context) {
    final plugin = widget.plugin;
    final hasConfig = plugin.configFields.isNotEmpty;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            KabukTheme.spacingLg,
            KabukTheme.spacingMd,
            KabukTheme.spacingLg,
            KabukTheme.spacingXl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.kabukTextTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: KabukTheme.spacingLg),

              // Header: icon, name, version
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _categoryColor(plugin.category).withAlpha(25),
                      borderRadius:
                          BorderRadius.circular(KabukTheme.radiusMd),
                    ),
                    child: Icon(
                      plugin.iconData,
                      size: 32,
                      color: _categoryColor(plugin.category),
                    ),
                  ),
                  const SizedBox(width: KabukTheme.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plugin.name,
                          style: TextStyle(
                            color: context.kabukTextPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'v${plugin.version}',
                          style: TextStyle(
                            color: context.kabukTextTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KabukTheme.spacingLg),

              // Description
              Text(
                plugin.description,
                style: TextStyle(
                  color: context.kabukTextSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: KabukTheme.spacingMd),

              // Category + capabilities chips
              Wrap(
                spacing: KabukTheme.spacingSm,
                runSpacing: KabukTheme.spacingSm,
                children: [
                  _CategoryBadge(category: plugin.category),
                  for (final cap in plugin.capabilities)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.kabukSurfaceVariant,
                        borderRadius:
                            BorderRadius.circular(KabukTheme.radiusSm),
                      ),
                      child: Text(
                        cap.name,
                        style: TextStyle(
                          color: context.kabukTextSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),

              // Config fields
              if (hasConfig) ...[
                const SizedBox(height: KabukTheme.spacingLg),
                Text(
                  'Configuration',
                  style: TextStyle(
                    color: context.kabukTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: KabukTheme.spacingSm),
                for (final field in plugin.configFields) ...[
                  _buildConfigField(context, field),
                  const SizedBox(height: KabukTheme.spacingSm),
                ],
              ],

              const SizedBox(height: KabukTheme.spacingLg),

              // Enable / Disable button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _handleToggle,
                  icon: Icon(
                    _enabled
                        ? Icons.toggle_on_rounded
                        : Icons.toggle_off_rounded,
                  ),
                  label: Text(_enabled ? 'Disable Plugin' : 'Enable Plugin'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _enabled
                        ? KabukTheme.error
                        : KabukTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: KabukTheme.spacingMd),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(KabukTheme.radiusMd),
                    ),
                  ),
                ),
              ),

              // Save config button
              if (hasConfig) ...[
                const SizedBox(height: KabukTheme.spacingSm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _saveConfig,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save Configuration'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.kabukTextPrimary,
                      side: BorderSide(color: context.kabukDivider),
                      padding: const EdgeInsets.symmetric(
                          vertical: KabukTheme.spacingMd),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(KabukTheme.radiusMd),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Config field builder
  // ---------------------------------------------------------------------------

  Widget _buildConfigField(BuildContext context, PluginConfigField field) {
    return switch (field.type) {
      PluginConfigFieldType.text => _buildTextField(context, field),
      PluginConfigFieldType.password =>
        _buildTextField(context, field, obscure: true),
      PluginConfigFieldType.number =>
        _buildTextField(context, field, number: true),
      PluginConfigFieldType.toggle => _buildToggleField(context, field),
      PluginConfigFieldType.choice => _buildChoiceField(context, field),
    };
  }

  Widget _buildTextField(
    BuildContext context,
    PluginConfigField field, {
    bool obscure = false,
    bool number = false,
  }) {
    return TextField(
      obscureText: obscure,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: context.kabukTextPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: field.label,
        labelStyle: TextStyle(color: context.kabukTextSecondary),
        helperText: field.description,
        helperStyle: TextStyle(color: context.kabukTextTertiary, fontSize: 11),
        suffixIcon: obscure
            ? const Icon(Icons.lock_outline_rounded, size: 18)
            : null,
      ),
      onChanged: (value) => _configValues[field.key] = value,
    );
  }

  Widget _buildToggleField(BuildContext context, PluginConfigField field) {
    final value = _configValues[field.key] == 'true';
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(
        field.label,
        style: TextStyle(color: context.kabukTextPrimary, fontSize: 14),
      ),
      subtitle: field.description != null
          ? Text(
              field.description!,
              style:
                  TextStyle(color: context.kabukTextTertiary, fontSize: 11),
            )
          : null,
      value: value,
      activeTrackColor: KabukTheme.primaryGreen,
      onChanged: (v) {
        setState(() => _configValues[field.key] = v.toString());
      },
    );
  }

  Widget _buildChoiceField(BuildContext context, PluginConfigField field) {
    final current = _configValues[field.key] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (field.description != null) ...[
          Text(
            field.description!,
            style: TextStyle(color: context.kabukTextTertiary, fontSize: 11),
          ),
          const SizedBox(height: KabukTheme.spacingXs),
        ],
        DropdownButtonFormField<String>(
          initialValue: field.choices.contains(current) ? current : null,
          decoration: InputDecoration(
            labelText: field.label,
            labelStyle: TextStyle(color: context.kabukTextSecondary),
          ),
          dropdownColor: context.kabukSurfaceElevated,
          style: TextStyle(color: context.kabukTextPrimary, fontSize: 14),
          items: field.choices
              .map(
                (c) => DropdownMenuItem(
                  value: c,
                  child: Text(c),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _configValues[field.key] = value);
            }
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _handleToggle() async {
    final registry = ref.read(pluginRegistryProvider);
    final notifier = ref.read(enabledPluginIdsProvider.notifier);
    if (_enabled) {
      await registry.disable(widget.plugin.id);
      notifier.state = {...notifier.state}..remove(widget.plugin.id);
    } else {
      await registry.enable(widget.plugin.id);
      notifier.state = {...notifier.state, widget.plugin.id};
    }
    setState(() => _enabled = !_enabled);
  }

  Future<void> _saveConfig() async {
    final pluginId = widget.plugin.id;
    final configJson = jsonEncode(_configValues);

    final ks = ref.read(knowledgeStoreProvider);
    final data = await ks.queryPlugin(pluginId);
    if (data != null) {
      await ks.updatePluginConfig(data.uri, configJson: configJson);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Configuration saved'),
          backgroundColor: KabukTheme.primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          ),
        ),
      );
    }
  }
}
