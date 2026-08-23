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
import 'package:kabuk/platform/shared/device_capabilities.dart' show kStandardModelId;
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

  // GPU configuration state.
  int _gpuLayers = 0;
  String _gpuBackend = 'auto';
  bool _gpuTesting = false;
  String? _gpuTestResult;

  @override
  void initState() {
    super.initState();
    _loadModels();
    // Sync GPU state from persisted config.
    final cfg = ref.read(localModelConfigProvider);
    if (cfg != null) {
      _gpuLayers = cfg.nGpuLayers;
      _gpuBackend = cfg.gpuBackend;
    }
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
    final localConfig = LocalModelConfig(
      modelPath: model.path,
      nGpuLayers: _gpuLayers,
      gpuBackend: _gpuBackend,
    );
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

  /// Applies the current GPU settings to the active model config.
  void _applyGpuSettings() {
    final current = ref.read(localModelConfigProvider);
    if (current == null) return;
    final updated = LocalModelConfig(
      modelPath: current.modelPath,
      nGpuLayers: _gpuLayers,
      gpuBackend: _gpuBackend,
      contextSize: current.contextSize,
      maxTokens: current.maxTokens,
      threads: current.threads,
      temperature: current.temperature,
      topP: current.topP,
      minP: current.minP,
      topK: current.topK,
      mmprojPath: current.mmprojPath,
    );
    ref.read(localModelConfigProvider.notifier).setConfig(updated);
  }

  /// Runs a tiny inference to verify the GPU configuration works.
  ///
  /// Sets a crash-recovery flag before starting. If the Vulkan driver
  /// causes a native crash (SIGSEGV), the flag survives and the app
  /// will automatically revert to CPU-only on next launch.
  Future<void> _testGpuConfig() async {
    final current = ref.read(localModelConfigProvider);
    if (current == null) return;

    setState(() {
      _gpuTesting = true;
      _gpuTestResult = null;
    });

    try {
      // Set crash-recovery flag BEFORE GPU inference.
      await ref
          .read(localModelConfigProvider.notifier)
          .markGpuTestPending();

      final testConfig = LocalModelConfig(
        modelPath: current.modelPath,
        nGpuLayers: _gpuLayers,
        gpuBackend: _gpuBackend,
        contextSize: 512,
        maxTokens: 16,
        threads: current.threads,
      );
      final service = LocalLlmService(config: testConfig);
      final response = await service.complete(
        const LlmRequest(
          messages: [LlmMessage.user('Say "ok".')],
          maxTokens: 16,
        ),
      );
      service.dispose();

      // Clear the crash flag — inference survived.
      await ref
          .read(localModelConfigProvider.notifier)
          .clearGpuTestPending();

      if (!mounted) return;
      if (response is ErrorLlmResponse) {
        setState(() => _gpuTestResult = 'error: ${response.message}');
      } else {
        setState(() => _gpuTestResult = 'success');
        // GPU works — persist the settings.
        _applyGpuSettings();
      }
    } on Object catch (e) {
      // Clear crash flag on Dart-level errors (non-fatal).
      await ref
          .read(localModelConfigProvider.notifier)
          .clearGpuTestPending();
      if (!mounted) return;
      setState(() => _gpuTestResult = 'error: $e');
    } finally {
      if (mounted) setState(() => _gpuTesting = false);
    }
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
                  child: Row(
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
                            color: context.kabukTextSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: KabukTheme.spacingLg),
                Text(
                  'INSTALLED',
                  style: TextStyle(
                    color: context.kabukTextSecondary,
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
                      color: context.kabukSurfaceVariant,
                      borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                    ),
                    child: Center(
                      child: Text(
                        'No models installed yet',
                        style: TextStyle(
                          color: context.kabukTextSecondary,
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
                // GPU / inference settings — only when a model is active.
                if (activeLocalConfig != null) ...[
                  Text(
                    'INFERENCE SETTINGS',
                    style: TextStyle(
                      color: context.kabukTextSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: KabukTheme.spacingSm),
                  _GpuSettingsCard(
                    gpuLayers: _gpuLayers,
                    gpuBackend: _gpuBackend,
                    testing: _gpuTesting,
                    testResult: _gpuTestResult,
                    onGpuLayersChanged: (v) {
                      setState(() {
                        _gpuLayers = v;
                        _gpuTestResult = null;
                      });
                    },
                    onGpuBackendChanged: (v) {
                      setState(() {
                        _gpuBackend = v;
                        _gpuTestResult = null;
                      });
                    },
                    onTest: _testGpuConfig,
                    onApply: () {
                      _applyGpuSettings();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('GPU settings saved'),
                          backgroundColor: KabukTheme.primaryGreen,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: KabukTheme.spacingLg),
                ],
                Text(
                  'RECOMMENDED DOWNLOADS',
                  style: TextStyle(
                    color: context.kabukTextSecondary,
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
                    isStandard: model.id == kStandardModelId,
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
              : context.kabukSurfaceVariant,
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          border: Border.all(
            color: isActive
                ? KabukTheme.accentGreen
                : context.kabukDivider.withAlpha(80),
          ),
        ),
        child: ListTile(
          leading: Icon(
            isActive ? Icons.check_circle : Icons.smart_toy_outlined,
            color: isActive ? KabukTheme.accentGreen : context.kabukTextSecondary,
          ),
          title: Text(
            model.name,
            style: TextStyle(
              color: context.kabukTextPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            '${model.formattedSize}'
            '${model.quantization != null ? ' \u00b7 ${model.quantization}' : ''}'
            '${model.parameterCount != null ? ' \u00b7 ${model.parameterCount}' : ''}',
            style: TextStyle(
              color: context.kabukTextSecondary,
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
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: context.kabukTextSecondary,
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
    this.isStandard = false,
    required this.isDownloading,
    required this.progress,
    required this.onDownload,
  });

  final RemoteModelInfo model;
  final bool isInstalled;
  final bool isStandard;
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
          color: context.kabukSurfaceVariant,
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
                        style: TextStyle(
                          color: context.kabukTextPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${model.formattedSize}'
                        '${model.quantization != null ? ' \u00b7 ${model.quantization}' : ''}'
                        '${model.parameterCount != null ? ' \u00b7 ${model.parameterCount}' : ''}',
                        style: TextStyle(
                          color: context.kabukTextSecondary,
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
                else if (isStandard)
                  const Chip(
                    label: Text('Standard', style: TextStyle(fontSize: 11)),
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
                          backgroundColor: context.kabukDivider,
                          color: KabukTheme.accentGreen,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            color: context.kabukTextSecondary,
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
                style: TextStyle(
                  color: context.kabukTextSecondary,
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

/// Card showing GPU / inference configuration with backend picker,
/// GPU layer slider, test button, and apply button.
class _GpuSettingsCard extends StatelessWidget {
  const _GpuSettingsCard({
    required this.gpuLayers,
    required this.gpuBackend,
    required this.testing,
    required this.testResult,
    required this.onGpuLayersChanged,
    required this.onGpuBackendChanged,
    required this.onTest,
    required this.onApply,
  });

  final int gpuLayers;
  final String gpuBackend;
  final bool testing;
  final String? testResult;
  final ValueChanged<int> onGpuLayersChanged;
  final ValueChanged<String> onGpuBackendChanged;
  final VoidCallback onTest;
  final VoidCallback onApply;

  static const _backends = <String, String>{
    'auto': 'Auto',
    'cpu': 'CPU Only',
    'vulkan': 'Vulkan',
    'metal': 'Metal',
  };

  @override
  Widget build(BuildContext context) {
    final isGpuEnabled = gpuLayers > 0;
    final testOk = testResult == 'success';
    final testFailed = testResult != null && !testOk;

    return Container(
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: BoxDecoration(
        color: context.kabukSurfaceVariant,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: context.kabukDivider.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // GPU toggle row.
          Row(
            children: [
              Icon(
                Icons.memory,
                size: 18,
                color: isGpuEnabled
                    ? KabukTheme.accentGreen
                    : context.kabukTextSecondary,
              ),
              const SizedBox(width: KabukTheme.spacingSm),
              Expanded(
                child: Text(
                  'GPU Acceleration',
                  style: TextStyle(
                    color: context.kabukTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Switch.adaptive(
                value: isGpuEnabled,
                activeTrackColor: KabukTheme.accentGreen,
                onChanged: (on) {
                  onGpuLayersChanged(on ? 999 : 0);
                  if (on && gpuBackend == 'cpu') {
                    onGpuBackendChanged('auto');
                  }
                },
              ),
            ],
          ),

          if (isGpuEnabled) ...[
            const SizedBox(height: KabukTheme.spacingSm),
            // Backend dropdown.
            Row(
              children: [
                Text(
                  'Backend',
                  style: TextStyle(
                    color: context.kabukTextSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: KabukTheme.spacingSm),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    children: _backends.entries
                        .where((e) => e.key != 'cpu')
                        .map((e) {
                      final selected = gpuBackend == e.key;
                      return ChoiceChip(
                        label: Text(
                          e.value,
                          style: TextStyle(
                            fontSize: 11,
                            color: selected
                                ? Colors.white
                                : context.kabukTextSecondary,
                          ),
                        ),
                        selected: selected,
                        selectedColor: KabukTheme.primaryGreen,
                        backgroundColor: context.kabukCardColor,
                        side: BorderSide(
                          color: selected
                              ? KabukTheme.accentGreen
                              : context.kabukDivider,
                        ),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => onGpuBackendChanged(e.key),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),

            const SizedBox(height: KabukTheme.spacingSm),
            // GPU layers slider.
            Row(
              children: [
                Text(
                  'Layers',
                  style: TextStyle(
                    color: context.kabukTextSecondary,
                    fontSize: 12,
                  ),
                ),
                Expanded(
                  child: Slider.adaptive(
                    value: gpuLayers.toDouble().clamp(1, 999),
                    min: 1,
                    max: 999,
                    divisions: 40,
                    activeColor: KabukTheme.accentGreen,
                    label: gpuLayers >= 999 ? 'All' : '$gpuLayers',
                    onChanged: (v) => onGpuLayersChanged(v.round()),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    gpuLayers >= 999 ? 'All' : '$gpuLayers',
                    style: TextStyle(
                      color: context.kabukTextPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),

            // Hint text.
            Padding(
              padding: const EdgeInsets.only(
                left: KabukTheme.spacingXs,
                bottom: KabukTheme.spacingSm,
              ),
              child: Text(
                'More layers = faster but uses more GPU memory. '
                'Reduce if you see crashes. Vulkan may not work '
                'on some Adreno GPUs — use Test before Apply.',
                style: TextStyle(
                  color: context.kabukTextSecondary,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ),

            // Test + Apply buttons.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: testing ? null : onTest,
                    icon: testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: KabukTheme.accentGreen,
                            ),
                          )
                        : Icon(
                            testOk
                                ? Icons.check_circle_outline
                                : Icons.play_arrow,
                            size: 16,
                          ),
                    label: Text(
                      testing
                          ? 'Testing…'
                          : testOk
                              ? 'Passed'
                              : 'Test GPU',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: testOk
                          ? KabukTheme.accentGreen
                          : context.kabukTextPrimary,
                      side: BorderSide(
                        color: testOk
                            ? KabukTheme.accentGreen
                            : context.kabukDivider,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(width: KabukTheme.spacingSm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: testing ? null : onApply,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text(
                      'Apply',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: KabukTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),

            // Test result feedback.
            if (testFailed) ...[
              const SizedBox(height: KabukTheme.spacingSm),
              Container(
                padding: const EdgeInsets.all(KabukTheme.spacingSm),
                decoration: BoxDecoration(
                  color: KabukTheme.error.withAlpha(20),
                  borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: KabukTheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'GPU test failed — try reducing layers or '
                        'switching backend.\n'
                        '${testResult!.replaceFirst('error: ', '')}',
                        style: const TextStyle(
                          color: KabukTheme.error,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
