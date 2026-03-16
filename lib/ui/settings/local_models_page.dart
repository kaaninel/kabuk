/// Local models management settings sub-page.
///
/// Provides UI for listing installed GGUF models, downloading
/// recommended models, selecting the active model, and deleting models.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/agents/http_llm.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/local_llm.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/services/model_manager.dart';
import 'package:kabuk/ui/theme.dart';

/// Settings page for managing on-device GGUF models.
class LocalModelsPage extends ConsumerStatefulWidget {
  /// Creates a [LocalModelsPage].
  const LocalModelsPage({super.key});

  @override
  ConsumerState<LocalModelsPage> createState() => _LocalModelsPageState();
}

class _LocalModelsPageState extends ConsumerState<LocalModelsPage> {
  List<LocalModelInfo> _models = [];
  bool _loading = true;
  String? _downloadingModelId;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    setState(() => _loading = true);
    try {
      final manager = ref.read(modelManagerProvider);
      final models = await manager.listLocalModels();
      if (!mounted) return;
      setState(() {
        _models = models;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _downloadModel(RemoteModelInfo model) async {
    if (_downloadingModelId != null) return;
    setState(() {
      _downloadingModelId = model.id;
      _downloadProgress = 0.0;
    });

    try {
      final manager = ref.read(modelManagerProvider);
      await for (final progress in manager.downloadModel(model)) {
        if (!mounted) return;
        setState(() => _downloadProgress = progress.progress);
      }
      await _loadModels();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    } finally {
      if (mounted) setState(() => _downloadingModelId = null);
    }
  }

  Future<void> _deleteModel(LocalModelInfo model) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text('Delete ${model.name} (${model.formattedSize})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: KabukTheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final manager = ref.read(modelManagerProvider);
    await manager.deleteModel(model);
    await _loadModels();
  }

  void _selectModel(LocalModelInfo model) {
    final localConfig = LocalModelConfig(modelPath: model.path);
    ref.read(localModelConfigProvider.notifier).setConfig(localConfig);
    ref
        .read(llmConfigProvider.notifier)
        .setConfig(
          const LlmConfig(
            provider: LlmProvider.local,
            baseUrl: '',
            apiKey: '',
            defaultModel: 'local',
          ),
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Switched to ${model.name}'),
        backgroundColor: KabukTheme.primaryGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.read(modelManagerProvider);
    final recommended = manager.recommendedModels;
    final activeLocalConfig = ref.watch(localModelConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Local Models')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(KabukTheme.spacingMd),
              children: [
                Container(
                  padding: const EdgeInsets.all(KabukTheme.spacingMd),
                  decoration: BoxDecoration(
                    color: KabukTheme.primaryGreen.withAlpha(15),
                    borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                    border: Border.all(
                      color: KabukTheme.accentGreen.withAlpha(40),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: KabukTheme.accentGreen,
                      ),
                      SizedBox(width: KabukTheme.spacingSm),
                      Expanded(
                        child: Text(
                          'Local models run entirely on your device — no '
                          'API key or internet needed. Smaller models are '
                          'faster but less capable.',
                          style: TextStyle(
                            fontSize: 12,
                            color: KabukTheme.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: KabukTheme.spacingLg),
                const Text(
                  'INSTALLED',
                  style: TextStyle(
                    color: KabukTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: KabukTheme.spacingSm),
                if (_models.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(KabukTheme.spacingLg),
                    decoration: BoxDecoration(
                      color: KabukTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                    ),
                    child: const Center(
                      child: Text(
                        'No models installed yet',
                        style: TextStyle(
                          color: KabukTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else
                  ...(_models.map((m) {
                    final isActive = activeLocalConfig?.modelPath == m.path;
                    return _InstalledModelTile(
                      model: m,
                      isActive: isActive,
                      onSelect: () => _selectModel(m),
                      onDelete: () => _deleteModel(m),
                    );
                  })),
                const SizedBox(height: KabukTheme.spacingLg),
                const Text(
                  'RECOMMENDED DOWNLOADS',
                  style: TextStyle(
                    color: KabukTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: KabukTheme.spacingSm),
                ...(recommended.map((model) {
                  final isInstalled = _models.any(
                    (m) => m.fileName == model.fileName,
                  );
                  return _DownloadModelTile(
                    model: model,
                    isInstalled: isInstalled,
                    isDownloading: _downloadingModelId == model.id,
                    progress: _downloadProgress,
                    onDownload: () => _downloadModel(model),
                  );
                })),
                const SizedBox(height: 60),
              ],
            ),
    );
  }
}

/// Tile showing an installed local model.
class _InstalledModelTile extends StatelessWidget {
  const _InstalledModelTile({
    required this.model,
    required this.isActive,
    required this.onSelect,
    required this.onDelete,
  });

  final LocalModelInfo model;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isActive
              ? KabukTheme.primaryGreen.withAlpha(15)
              : KabukTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          border: Border.all(
            color: isActive
                ? KabukTheme.accentGreen
                : KabukTheme.divider.withAlpha(80),
          ),
        ),
        child: ListTile(
          leading: Icon(
            isActive ? Icons.check_circle : Icons.smart_toy_outlined,
            color: isActive ? KabukTheme.accentGreen : KabukTheme.textSecondary,
          ),
          title: Text(
            model.name,
            style: const TextStyle(
              color: KabukTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            '${model.formattedSize}'
            '${model.quantization != null ? ' \u00b7 ${model.quantization}' : ''}'
            '${model.parameterCount != null ? ' \u00b7 ${model.parameterCount}' : ''}',
            style: const TextStyle(
              color: KabukTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isActive)
                TextButton(
                  onPressed: onSelect,
                  child: const Text(
                    'Use',
                    style: TextStyle(color: KabukTheme.accentGreen),
                  ),
                ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: KabukTheme.textSecondary,
                ),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tile showing a downloadable model from the recommended list.
class _DownloadModelTile extends StatelessWidget {
  const _DownloadModelTile({
    required this.model,
    required this.isInstalled,
    required this.isDownloading,
    required this.progress,
    required this.onDownload,
  });

  final RemoteModelInfo model;
  final bool isInstalled;
  final bool isDownloading;
  final double progress;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        decoration: BoxDecoration(
          color: KabukTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        style: const TextStyle(
                          color: KabukTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${model.formattedSize}'
                        '${model.quantization != null ? ' \u00b7 ${model.quantization}' : ''}'
                        '${model.parameterCount != null ? ' \u00b7 ${model.parameterCount}' : ''}',
                        style: const TextStyle(
                          color: KabukTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isInstalled)
                  const Chip(
                    label: Text('Installed', style: TextStyle(fontSize: 11)),
                    backgroundColor: Color(0xFF1B3A2A),
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                    labelStyle: TextStyle(color: KabukTheme.accentGreen),
                  )
                else if (isDownloading)
                  SizedBox(
                    width: 80,
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          value: progress,
                          backgroundColor: KabukTheme.divider,
                          color: KabukTheme.accentGreen,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: KabukTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text(
                      'Download',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: KabukTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
              ],
            ),
            if (model.description != null) ...[
              const SizedBox(height: 6),
              Text(
                model.description!,
                style: const TextStyle(
                  color: KabukTheme.textSecondary,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
