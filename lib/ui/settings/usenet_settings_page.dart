/// Usenet Settings Page — manage indexers, providers, and cache.
///
/// Provides a full settings page for Usenet configuration, including
/// Newznab indexer setup, NNTP provider management with drag-to-reorder
/// priority, and cache statistics/controls.
///
/// Reuses the providers and data types from
/// [UsenetSettingsSheet](../../explore/usenet_settings_sheet.dart).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/usenet.dart';
import 'package:kabuk/services/usenet.dart';
import 'package:kabuk/ui/explore/usenet_settings_sheet.dart';
import 'package:kabuk/ui/theme.dart';

/// Full-page settings view for managing Usenet indexers, NNTP providers,
/// and cache.
///
/// Presents three tabs: Indexers, Providers, and Cache. Supports add, edit,
/// delete, and test-connection operations for indexers and providers, plus
/// cache size control and clearing.
class UsenetSettingsPage extends ConsumerStatefulWidget {
  /// Creates a [UsenetSettingsPage].
  const UsenetSettingsPage({super.key});

  @override
  ConsumerState<UsenetSettingsPage> createState() => _UsenetSettingsPageState();
}

class _UsenetSettingsPageState extends ConsumerState<UsenetSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Usenet Settings'),
          bottom: TabBar(
            indicatorColor: KabukTheme.blueAccent,
            labelColor: KabukTheme.blueAccent,
            unselectedLabelColor: context.kabukTextSecondary,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: context.kabukDivider,
            tabs: const [
              Tab(text: 'Indexers'),
              Tab(text: 'Providers'),
              Tab(text: 'Cache'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _IndexersSection(),
            _ProvidersSection(),
            _CacheSection(),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Indexers Section
// =============================================================================

class _IndexersSection extends ConsumerWidget {
  const _IndexersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indexersAsync = ref.watch(usenetIndexersProvider);

    return Column(
      children: [
        Expanded(
          child: indexersAsync.when(
            data: (indexers) {
              if (indexers.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color: context.kabukTextTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No indexers configured.\n'
                          'Add a Newznab indexer to search for content.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.kabukTextSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: indexers.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  indent: 68,
                  color: context.kabukDivider,
                ),
                itemBuilder: (context, index) => _IndexerTile(
                  indexer: indexers[index],
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(
                'Error: $e',
                style: TextStyle(color: context.kabukTextSecondary),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _IndexerFormDialog.show(context, ref),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text(
                'Add Indexer',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: KabukTheme.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IndexerTile extends ConsumerWidget {
  const _IndexerTile({required this.indexer});

  final UsenetIndexerData indexer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: KabukTheme.blueAccent.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.search_rounded,
              color: KabukTheme.blueAccent,
              size: 22,
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: indexer.enabled
                      ? KabukTheme.success
                      : KabukTheme.error,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
      title: Text(
        indexer.name ?? 'Indexer',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: context.kabukTextPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        indexer.baseUrl ?? '',
        style: TextStyle(fontSize: 12, color: context.kabukTextTertiary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch.adaptive(
            value: indexer.enabled,
            activeTrackColor: KabukTheme.accentGreen,
            onChanged: (value) async {
              final store = ref.read(knowledgeStoreProvider);
              await store.updateUsenetIndexer(indexer.uri, enabled: value);
              ref.invalidate(usenetIndexersProvider);
            },
          ),
          PopupMenuButton<_IndexerAction>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: context.kabukTextTertiary,
              size: 20,
            ),
            color: context.kabukSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (action) {
              switch (action) {
                case _IndexerAction.edit:
                  _IndexerFormDialog.show(context, ref, existing: indexer);
                case _IndexerAction.delete:
                  _confirmDeleteIndexer(context, ref, indexer);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _IndexerAction.edit,
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_rounded,
                      size: 18,
                      color: KabukTheme.blueAccent,
                    ),
                    SizedBox(width: 10),
                    Text('Edit'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _IndexerAction.delete,
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: KabukTheme.error,
                    ),
                    SizedBox(width: 10),
                    Text('Delete', style: TextStyle(color: KabukTheme.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Future<void> _confirmDeleteIndexer(
    BuildContext context,
    WidgetRef ref,
    UsenetIndexerData indexer,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.kabukSurfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
        ),
        title: const Text('Delete Indexer'),
        content: Text(
          'Remove "${indexer.name ?? "this indexer"}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: KabukTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final store = ref.read(knowledgeStoreProvider);
    await store.deleteUsenetIndexer(indexer.uri);
    ref.invalidate(usenetIndexersProvider);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${indexer.name ?? "indexer"}')),
      );
    }
  }
}

enum _IndexerAction { edit, delete }

// =============================================================================
// Indexer Form Dialog
// =============================================================================

class _IndexerFormDialog extends ConsumerStatefulWidget {
  const _IndexerFormDialog({this.existing});

  final UsenetIndexerData? existing;

  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    UsenetIndexerData? existing,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _IndexerFormDialog(existing: existing),
    );
    if (changed == true) {
      ref.invalidate(usenetIndexersProvider);
    }
  }

  @override
  ConsumerState<_IndexerFormDialog> createState() => _IndexerFormDialogState();
}

class _IndexerFormDialogState extends ConsumerState<_IndexerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _apiKeyCtrl;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _urlCtrl = TextEditingController(text: widget.existing?.baseUrl ?? '');
    _apiKeyCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.kabukSurfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
      ),
      title: Text(_isEditing ? 'Edit Indexer' : 'Add Indexer'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Name'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  style: TextStyle(
                    color: context.kabukTextPrimary,
                    fontSize: 15,
                  ),
                  decoration: _inputDecoration(context, 'My Indexer'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: 16),
                _buildLabel('Base URL'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _urlCtrl,
                  style: TextStyle(
                    color: context.kabukTextPrimary,
                    fontSize: 15,
                  ),
                  decoration: _inputDecoration(
                    context,
                    'https://indexer.example/api',
                  ),
                  keyboardType: TextInputType.url,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'URL is required';
                    final uri = Uri.tryParse(v.trim());
                    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                      return 'Enter a valid URL';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildLabel(
                  _isEditing ? 'API Key (leave blank to keep)' : 'API Key',
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _apiKeyCtrl,
                  style: TextStyle(
                    color: context.kabukTextPrimary,
                    fontSize: 15,
                  ),
                  decoration: _inputDecoration(context, '••••••••••'),
                  obscureText: true,
                  validator: (v) {
                    if (!_isEditing && (v == null || v.trim().isEmpty)) {
                      return 'API key is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                if (_isEditing)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _testing ? null : _testConnection,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.wifi_tethering_rounded,
                              size: 18,
                            ),
                      label: const Text('Test Connection'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KabukTheme.blueAccent,
                        side: const BorderSide(color: KabukTheme.blueAccent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            KabukTheme.radiusSm,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_testResult != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _testResult!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _testResult!.startsWith('✓')
                          ? KabukTheme.success
                          : KabukTheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: KabukTheme.blueAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
            ),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final usenet = ref.read(usenetServiceProvider);
      final result = await usenet.testIndexer(widget.existing!.uri);
      if (!mounted) return;
      setState(() {
        _testResult = result.isSuccess
            ? '✓ Connection successful'
            : '✗ Connection failed';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _testResult = '✗ Error: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final store = ref.read(knowledgeStoreProvider);
      final vault = ref.read(vaultServiceProvider);
      final name = _nameCtrl.text.trim();
      final url = _urlCtrl.text.trim();
      final apiKey = _apiKeyCtrl.text.trim();

      if (_isEditing) {
        String? newApiKeyRef;
        if (apiKey.isNotEmpty) {
          final entry = await vault.store(
            Uint8List.fromList(utf8.encode(apiKey)),
            name: 'usenet-indexer-apikey-$name',
            tags: ['usenet', 'api-key', name],
          );
          newApiKeyRef = entry.hash;
        }
        await store.updateUsenetIndexer(
          widget.existing!.uri,
          name: name,
          baseUrl: url,
          apiKeyRef: newApiKeyRef,
        );
      } else {
        final entry = await vault.store(
          Uint8List.fromList(utf8.encode(apiKey)),
          name: 'usenet-indexer-apikey-$name',
          tags: ['usenet', 'api-key', name],
        );
        await store.createUsenetIndexer(
          name: name,
          baseUrl: url,
          apiKeyRef: entry.hash,
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.kabukTextSecondary,
      ),
    );
  }
}

// =============================================================================
// Providers Section
// =============================================================================

class _ProvidersSection extends ConsumerStatefulWidget {
  const _ProvidersSection();

  @override
  ConsumerState<_ProvidersSection> createState() => _ProvidersSectionState();
}

class _ProvidersSectionState extends ConsumerState<_ProvidersSection> {
  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(usenetProvidersProvider);

    return Column(
      children: [
        Expanded(
          child: providersAsync.when(
            data: (providers) {
              if (providers.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 48,
                          color: context.kabukTextTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No providers configured.\n'
                          'Add an NNTP server to download content.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.kabukTextSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final sorted = List.of(providers)
                ..sort((a, b) => a.priority.compareTo(b.priority));
              return ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: sorted.length,
                onReorder: (oldIdx, newIdx) =>
                    _onReorder(sorted, oldIdx, newIdx),
                itemBuilder: (context, index) {
                  final provider = sorted[index];
                  return _ProviderTile(
                    key: ValueKey(provider.uri),
                    provider: provider,
                    priorityIndex: index,
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(
                'Error: $e',
                style: TextStyle(color: context.kabukTextSecondary),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _ProviderFormDialog.show(context, ref),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text(
                'Add Provider',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: KabukTheme.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onReorder(
    List<UsenetProviderData> sorted,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex--;
    final item = sorted.removeAt(oldIndex);
    sorted.insert(newIndex, item);

    final store = ref.read(knowledgeStoreProvider);
    for (var i = 0; i < sorted.length; i++) {
      await store.updateUsenetProvider(sorted[i].uri, priority: i);
    }
    ref.invalidate(usenetProvidersProvider);
  }
}

class _ProviderTile extends ConsumerWidget {
  const _ProviderTile({
    super.key,
    required this.provider,
    required this.priorityIndex,
  });

  final UsenetProviderData provider;
  final int priorityIndex;

  String get _priorityLabel {
    if (priorityIndex == 0) return 'Primary';
    return 'Backup $priorityIndex';
  }

  Color get _priorityColor {
    if (priorityIndex == 0) return KabukTheme.accentGreen;
    return KabukTheme.warmAccent;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostPort = [
      provider.host ?? '—',
      if (provider.port != null) ':${provider.port}',
    ].join();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: ReorderableDragStartListener(
        index: priorityIndex,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: KabukTheme.primaryGreen.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.drag_handle_rounded,
            color: KabukTheme.primaryGreen,
            size: 22,
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              provider.name ?? 'Provider',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.kabukTextPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _priorityColor.withAlpha(20),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _priorityLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _priorityColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Icon(
            provider.ssl ? Icons.lock_rounded : Icons.lock_open_rounded,
            size: 12,
            color: provider.ssl
                ? KabukTheme.success
                : context.kabukTextTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            hostPort,
            style: TextStyle(fontSize: 12, color: context.kabukTextTertiary),
          ),
          const SizedBox(width: 12),
          Text(
            '${provider.connections} connections',
            style: TextStyle(fontSize: 12, color: context.kabukTextTertiary),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch.adaptive(
            value: provider.enabled,
            activeTrackColor: KabukTheme.accentGreen,
            onChanged: (value) async {
              final store = ref.read(knowledgeStoreProvider);
              await store.updateUsenetProvider(provider.uri, enabled: value);
              ref.invalidate(usenetProvidersProvider);
            },
          ),
          PopupMenuButton<_ProviderAction>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: context.kabukTextTertiary,
              size: 20,
            ),
            color: context.kabukSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (action) {
              switch (action) {
                case _ProviderAction.edit:
                  _ProviderFormDialog.show(context, ref, existing: provider);
                case _ProviderAction.delete:
                  _confirmDeleteProvider(context, ref, provider);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _ProviderAction.edit,
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_rounded,
                      size: 18,
                      color: KabukTheme.blueAccent,
                    ),
                    SizedBox(width: 10),
                    Text('Edit'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _ProviderAction.delete,
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: KabukTheme.error,
                    ),
                    SizedBox(width: 10),
                    Text('Delete', style: TextStyle(color: KabukTheme.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Future<void> _confirmDeleteProvider(
    BuildContext context,
    WidgetRef ref,
    UsenetProviderData provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.kabukSurfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
        ),
        title: const Text('Delete Provider'),
        content: Text(
          'Remove "${provider.name ?? "this provider"}"? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: KabukTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final store = ref.read(knowledgeStoreProvider);
    await store.deleteUsenetProvider(provider.uri);
    ref.invalidate(usenetProvidersProvider);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${provider.name ?? "provider"}')),
      );
    }
  }
}

enum _ProviderAction { edit, delete }

// =============================================================================
// Provider Form Dialog
// =============================================================================

class _ProviderFormDialog extends ConsumerStatefulWidget {
  const _ProviderFormDialog({this.existing});

  final UsenetProviderData? existing;

  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    UsenetProviderData? existing,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ProviderFormDialog(existing: existing),
    );
    if (changed == true) {
      ref.invalidate(usenetProvidersProvider);
    }
  }

  @override
  ConsumerState<_ProviderFormDialog> createState() =>
      _ProviderFormDialogState();
}

class _ProviderFormDialogState extends ConsumerState<_ProviderFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _retentionCtrl;
  late double _connections;
  late bool _ssl;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _hostCtrl = TextEditingController(text: p?.host ?? '');
    _portCtrl = TextEditingController(text: '${p?.port ?? 563}');
    _usernameCtrl = TextEditingController(text: p?.username ?? '');
    _passwordCtrl = TextEditingController();
    _retentionCtrl = TextEditingController(
      text: p?.retentionDays != null ? '${p!.retentionDays}' : '',
    );
    _connections = (p?.connections ?? 10).toDouble();
    _ssl = p?.ssl ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _retentionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.kabukSurfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
      ),
      title: Text(_isEditing ? 'Edit Provider' : 'Add Provider'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Name'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  style: TextStyle(
                    color: context.kabukTextPrimary,
                    fontSize: 15,
                  ),
                  decoration: _inputDecoration(context, 'My Provider'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: 16),
                _buildLabel('Host'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _hostCtrl,
                  style: TextStyle(
                    color: context.kabukTextPrimary,
                    fontSize: 15,
                  ),
                  decoration: _inputDecoration(context, 'news.example.com'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Host is required'
                      : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('Port'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _portCtrl,
                            style: TextStyle(
                              color: context.kabukTextPrimary,
                              fontSize: 15,
                            ),
                            decoration: _inputDecoration(context, '563'),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              if (int.tryParse(v.trim()) == null) {
                                return 'Invalid';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('SSL'),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 48,
                            child: Row(
                              children: [
                                Icon(
                                  _ssl
                                      ? Icons.lock_rounded
                                      : Icons.lock_open_rounded,
                                  color: _ssl
                                      ? KabukTheme.success
                                      : context.kabukTextTertiary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Switch.adaptive(
                                  value: _ssl,
                                  activeTrackColor: KabukTheme.accentGreen,
                                  onChanged: (v) =>
                                      setState(() => _ssl = v),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildLabel('Username'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _usernameCtrl,
                  style: TextStyle(
                    color: context.kabukTextPrimary,
                    fontSize: 15,
                  ),
                  decoration: _inputDecoration(context, 'username'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Username is required'
                      : null,
                ),
                const SizedBox(height: 16),
                _buildLabel(
                  _isEditing
                      ? 'Password (leave blank to keep)'
                      : 'Password',
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passwordCtrl,
                  style: TextStyle(
                    color: context.kabukTextPrimary,
                    fontSize: 15,
                  ),
                  decoration: _inputDecoration(context, '••••••••••'),
                  obscureText: true,
                  validator: (v) {
                    if (!_isEditing && (v == null || v.trim().isEmpty)) {
                      return 'Password is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildLabel('Connections: ${_connections.round()}'),
                const SizedBox(height: 6),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: KabukTheme.primaryGreen,
                    thumbColor: KabukTheme.primaryGreen,
                    inactiveTrackColor: context.kabukDivider,
                    overlayColor: KabukTheme.primaryGreen.withAlpha(40),
                  ),
                  child: Slider(
                    value: _connections,
                    min: 1,
                    max: 50,
                    divisions: 49,
                    label: '${_connections.round()}',
                    onChanged: (v) => setState(() => _connections = v),
                  ),
                ),
                const SizedBox(height: 16),
                _buildLabel('Retention (days, optional)'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _retentionCtrl,
                  style: TextStyle(
                    color: context.kabukTextPrimary,
                    fontSize: 15,
                  ),
                  decoration: _inputDecoration(context, 'e.g. 3600'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v != null && v.trim().isNotEmpty) {
                      if (int.tryParse(v.trim()) == null) {
                        return 'Invalid number';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                if (_isEditing)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _testing ? null : _testConnection,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.wifi_tethering_rounded,
                              size: 18,
                            ),
                      label: const Text('Test Connection'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KabukTheme.primaryGreen,
                        side: const BorderSide(
                          color: KabukTheme.primaryGreen,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            KabukTheme.radiusSm,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_testResult != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _testResult!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _testResult!.startsWith('✓')
                          ? KabukTheme.success
                          : KabukTheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: KabukTheme.primaryGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
            ),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final usenet = ref.read(usenetServiceProvider);
      final result = await usenet.testProvider(widget.existing!.uri);
      if (!mounted) return;
      setState(() {
        _testResult = result.isSuccess
            ? '✓ Connection successful'
            : '✗ Connection failed';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _testResult = '✗ Error: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final store = ref.read(knowledgeStoreProvider);
      final vault = ref.read(vaultServiceProvider);
      final name = _nameCtrl.text.trim();
      final host = _hostCtrl.text.trim();
      final port = int.parse(_portCtrl.text.trim());
      final username = _usernameCtrl.text.trim();
      final password = _passwordCtrl.text.trim();
      final connections = _connections.round();
      final retentionText = _retentionCtrl.text.trim();
      final retentionDays =
          retentionText.isNotEmpty ? int.tryParse(retentionText) : null;

      if (_isEditing) {
        String? newPasswordRef;
        if (password.isNotEmpty) {
          final entry = await vault.store(
            Uint8List.fromList(utf8.encode(password)),
            name: 'usenet-provider-password-$name',
            tags: ['usenet', 'password', name],
          );
          newPasswordRef = entry.hash;
        }
        await store.updateUsenetProvider(
          widget.existing!.uri,
          name: name,
          host: host,
          port: port,
          username: username,
          passwordRef: newPasswordRef,
          connections: connections,
          ssl: _ssl,
          retentionDays: retentionDays,
        );
      } else {
        final entry = await vault.store(
          Uint8List.fromList(utf8.encode(password)),
          name: 'usenet-provider-password-$name',
          tags: ['usenet', 'password', name],
        );
        await store.createUsenetProvider(
          name: name,
          host: host,
          port: port,
          username: username,
          passwordRef: entry.hash,
          connections: connections,
          ssl: _ssl,
          retentionDays: retentionDays,
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.kabukTextSecondary,
      ),
    );
  }
}

// =============================================================================
// Cache Section
// =============================================================================

class _CacheSection extends ConsumerStatefulWidget {
  const _CacheSection();

  @override
  ConsumerState<_CacheSection> createState() => _CacheSectionState();
}

class _CacheSectionState extends ConsumerState<_CacheSection> {
  /// Maximum cache size in bytes. Default 2 GB.
  double _maxCacheBytes = 2.0 * 1024 * 1024 * 1024;
  bool _clearing = false;

  @override
  Widget build(BuildContext context) {
    final cacheSizeAsync = ref.watch(usenetCacheSizeProvider);
    final streamsAsync = ref.watch(usenetActiveStreamsProvider);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Cache size section.
        Text(
          'Cache Usage',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.kabukTextPrimary,
          ),
        ),
        const SizedBox(height: 12),
        cacheSizeAsync.when(
          data: (cacheBytes) {
            final usedGb = cacheBytes / (1024 * 1024 * 1024);
            final maxGb = _maxCacheBytes / (1024 * 1024 * 1024);
            final fraction = _maxCacheBytes > 0
                ? (cacheBytes / _maxCacheBytes).clamp(0.0, 1.0)
                : 0.0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${usedGb.toStringAsFixed(1)} GB / '
                      '${maxGb.toStringAsFixed(1)} GB',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.kabukTextPrimary,
                      ),
                    ),
                    Text(
                      '${(fraction * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 13,
                        color: fraction > 0.9
                            ? KabukTheme.error
                            : context.kabukTextSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 8,
                    backgroundColor: context.kabukDivider,
                    valueColor: AlwaysStoppedAnimation(
                      fraction > 0.9
                          ? KabukTheme.error
                          : fraction > 0.7
                              ? KabukTheme.warmAccent
                              : KabukTheme.accentGreen,
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(
            'Error loading cache size: $e',
            style: TextStyle(color: context.kabukTextSecondary),
          ),
        ),
        const SizedBox(height: 24),

        // Max cache slider.
        Text(
          'Max Cache Size: '
          '${(_maxCacheBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.kabukTextSecondary,
          ),
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: KabukTheme.primaryGreen,
            thumbColor: KabukTheme.primaryGreen,
            inactiveTrackColor: context.kabukDivider,
            overlayColor: KabukTheme.primaryGreen.withAlpha(40),
          ),
          child: Slider(
            value: _maxCacheBytes,
            min: 500 * 1024 * 1024, // 500 MB
            max: 10.0 * 1024 * 1024 * 1024, // 10 GB
            divisions: 19,
            label:
                '${(_maxCacheBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB',
            onChanged: (v) => setState(() => _maxCacheBytes = v),
            onChangeEnd: (v) async {
              final usenet = ref.read(usenetServiceProvider);
              await usenet.setCacheLimit(v.round());
            },
          ),
        ),
        const SizedBox(height: 24),

        // Active streams.
        Text(
          'Active Streams',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.kabukTextPrimary,
          ),
        ),
        const SizedBox(height: 12),
        streamsAsync.when(
          data: (streams) {
            if (streams.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.kabukSurface,
                  borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.stream_rounded,
                      size: 20,
                      color: context.kabukTextTertiary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'No active streams',
                      style: TextStyle(
                        fontSize: 14,
                        color: context.kabukTextSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: streams.map((s) {
                final progress = s.totalBytes > 0
                    ? s.bytesStreamed / s.totalBytes
                    : 0.0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.kabukSurface,
                    borderRadius: BorderRadius.circular(
                      KabukTheme.radiusSm,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.nzbTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.kabukTextPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _streamStateChip(context, s.state),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 4,
                                backgroundColor: context.kabukDivider,
                                valueColor: const AlwaysStoppedAnimation(
                                  KabukTheme.blueAccent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(progress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.kabukTextTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(
            'Error: $e',
            style: TextStyle(color: context.kabukTextSecondary),
          ),
        ),
        const SizedBox(height: 24),

        // Clear cache button.
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _clearing ? null : _clearCache,
            icon: _clearing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_rounded, size: 20),
            label: const Text(
              'Clear Cache',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: KabukTheme.error,
              side: const BorderSide(color: KabukTheme.error),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _streamStateChip(BuildContext context, StreamState state) {
    final (label, color) = switch (state) {
      StreamState.buffering => ('Buffering', KabukTheme.warmAccent),
      StreamState.playing => ('Playing', KabukTheme.success),
      StreamState.paused => ('Paused', KabukTheme.blueAccent),
      StreamState.seeking => ('Seeking', KabukTheme.warmAccent),
      StreamState.stopped => ('Stopped', KabukTheme.textSecondary),
      StreamState.error => ('Error', KabukTheme.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.kabukSurfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
        ),
        title: const Text('Clear Cache'),
        content: const Text(
          'Remove all cached articles and segments? '
          'Active streams may be interrupted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: KabukTheme.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearing = true);
    try {
      final usenet = ref.read(usenetServiceProvider);
      await usenet.clearCache();
      ref.invalidate(usenetCacheSizeProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache cleared')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear cache: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }
}

// =============================================================================
// Shared helpers
// =============================================================================

InputDecoration _inputDecoration(BuildContext context, String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: context.kabukTextTertiary),
    filled: true,
    fillColor: context.kabukSurface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
      borderSide: BorderSide(color: context.kabukDivider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
      borderSide: BorderSide(color: context.kabukDivider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
      borderSide: const BorderSide(color: KabukTheme.blueAccent),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
      borderSide: const BorderSide(color: KabukTheme.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
      borderSide: const BorderSide(color: KabukTheme.error),
    ),
  );
}
