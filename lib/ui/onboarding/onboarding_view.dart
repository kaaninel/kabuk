/// Onboarding / first-run flow for Kabuk.
///
/// A three-page [PageView] that guides the user through:
/// 1. A welcome screen introducing the agent-first OS.
/// 2. Simplified LLM configuration (provider, API key, model, test).
/// 3. A "You're all set!" screen with quick-start tips.
///
/// On completion, persists an onboarding-complete flag in the knowledge
/// store so the flow is not shown again.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/agents/http_llm.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/local_llm.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/platform/shared/device_capabilities.dart';
import 'package:kabuk/services/model_manager.dart';
import 'package:kabuk/ui/onboarding/onboarding_page.dart';
import 'package:kabuk/ui/theme.dart';

/// The onboarding view shown on the first app launch.
///
/// Presents a horizontal [PageView] with three pages — welcome,
/// AI configuration, and ready — and persists a completion flag
/// in the knowledge store when the user finishes.
class OnboardingView extends ConsumerStatefulWidget {
  /// Creates an [OnboardingView].
  ///
  /// [onComplete] is called after the onboarding flag has been persisted.
  const OnboardingView({required this.onComplete, super.key});

  /// Callback invoked when onboarding is complete.
  final VoidCallback onComplete;

  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  final _pageController = PageController();
  int _currentPage = 0;

  // ---- LLM config form state ----
  final _formKey = GlobalKey<FormState>();
  LlmProvider _provider = LlmProvider.local;
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  bool _obscureApiKey = true;
  _TestStatus _testStatus = _TestStatus.idle;
  String? _testMessage;

  // ---- Local model state ----
  List<LocalModelInfo> _localModels = [];
  LocalModelInfo? _selectedLocalModel;
  String? _downloadingModelId;
  double _downloadProgress = 0.0;
  bool _loadingModels = false;

  // ---- Auto-download state ----
  RemoteModelInfo? _recommendedModel;
  bool _autoDownloadStarted = false;

  // ---- Key backup page state ----
  String? _npub;
  String? _nsec;
  bool _nsecVisible = false;
  bool _keyGenerated = false;
  bool _generatingKey = false;
  bool _keyBackupAcknowledged = false;

  @override
  void initState() {
    super.initState();
    // Default to local provider and begin detecting device capabilities
    // so we can auto-pick and download the best model.
    _initAutoModelSelection();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  /// Detects device capabilities and auto-picks the best model.
  ///
  /// If no local model is already installed, starts downloading the
  /// recommended model automatically so the user has a working LLM
  /// by the time they finish onboarding.
  Future<void> _initAutoModelSelection() async {
    // Load existing local models first.
    await _loadLocalModels();

    // If a model is already installed, no need to auto-download.
    if (_localModels.isNotEmpty) return;

    // Detect device capabilities and pick the best model.
    final device = await DeviceCapabilities.detect();
    if (!mounted) return;
    final manager = ref.read(modelManagerProvider);
    // Kabuk standardizes on MiniCPM5 1B — prefer it whenever it fits.
    final recommended = pickStandardModelForDevice(
      device,
      manager.recommendedModels,
    );

    if (!mounted) return;
    setState(() => _recommendedModel = recommended);

    // Auto-start the download.
    unawaited(_autoDownloadModel(recommended));
  }

  /// Downloads the recommended model automatically during onboarding.
  Future<void> _autoDownloadModel(RemoteModelInfo model) async {
    if (_autoDownloadStarted) return;
    _autoDownloadStarted = true;

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

      // Refresh local model list and auto-select the downloaded model.
      await _loadLocalModels();

      // Auto-save the config so the model is ready to use.
      if (_selectedLocalModel != null) {
        _saveLlmConfig();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testStatus = _TestStatus.error;
        _testMessage = 'Auto-download failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _downloadingModelId = null);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Provider helpers
  // ---------------------------------------------------------------------------

  static String _defaultModelFor(LlmProvider provider) => switch (provider) {
    LlmProvider.anthropic => 'claude-sonnet-4-20250514',
    LlmProvider.openai => 'minicpm5-1b',
    LlmProvider.ollama => 'llama3.1',
    LlmProvider.local => '',
  };

  static String _defaultBaseUrlFor(LlmProvider provider) => switch (provider) {
    LlmProvider.anthropic => 'https://api.anthropic.com/v1',
    LlmProvider.openai => '',
    LlmProvider.ollama => 'http://localhost:11434',
    LlmProvider.local => 'http://localhost:8080',
  };

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _onProviderChanged(LlmProvider provider) {
    setState(() {
      _provider = provider;
      _modelController.text = _defaultModelFor(provider);
      _baseUrlController.text = _defaultBaseUrlFor(provider);
      _testStatus = _TestStatus.idle;
      _testMessage = null;
    });
    if (provider == LlmProvider.local) {
      _loadLocalModels();
    }
  }

  Future<void> _loadLocalModels() async {
    setState(() => _loadingModels = true);
    try {
      final manager = ref.read(modelManagerProvider);
      final models = await manager.listLocalModels();
      if (!mounted) return;
      setState(() {
        _localModels = models;
        _loadingModels = false;
        if (models.isNotEmpty && _selectedLocalModel == null) {
          _selectedLocalModel = models.first;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingModels = false);
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
      // Refresh local model list after download.
      await _loadLocalModels();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testStatus = _TestStatus.error;
        _testMessage = 'Download failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _downloadingModelId = null);
      }
    }
  }

  void _saveLlmConfig() {
    if (_provider == LlmProvider.local) {
      // Save local model config.
      if (_selectedLocalModel == null) return;
      final localConfig = LocalModelConfig(
        modelPath: _selectedLocalModel!.path,
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
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    // Remote tier: the user's own OpenAI-compatible endpoint.
    final config = LlmConfig.openAICompatible(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim().isEmpty
          ? null
          : _modelController.text.trim(),
    );

    ref.read(llmConfigProvider.notifier).setConfig(config);
  }

  Future<void> _testConnection() async {
    // Local models don't need a connection test — validate model exists.
    if (_provider == LlmProvider.local) {
      if (_selectedLocalModel == null) {
        setState(() {
          _testStatus = _TestStatus.error;
          _testMessage = 'No local model selected. Download one first.';
        });
        return;
      }
      setState(() {
        _testStatus = _TestStatus.testing;
        _testMessage = null;
      });

      try {
        final localConfig = LocalModelConfig(
          modelPath: _selectedLocalModel!.path,
          maxTokens: 32,
        );
        final service = LocalLlmService(config: localConfig);
        final response = await service.complete(
          const LlmRequest(
            messages: [LlmMessage.user('Say "hello" in one word.')],
            maxTokens: 32,
          ),
        );

        if (!mounted) return;
        await service.dispose();

        switch (response) {
          case TextLlmResponse(:final content):
            setState(() {
              _testStatus = _TestStatus.success;
              _testMessage = 'Model loaded! Response: "${content.trim()}"';
            });
          case ToolCallsLlmResponse():
            setState(() {
              _testStatus = _TestStatus.success;
              _testMessage = 'Model loaded! (received tool call response)';
            });
          case ErrorLlmResponse(:final message):
            setState(() {
              _testStatus = _TestStatus.error;
              _testMessage = message;
            });
        }
      } on Exception catch (e) {
        if (!mounted) return;
        setState(() {
          _testStatus = _TestStatus.error;
          _testMessage = 'Failed to load model: $e';
        });
      }
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _testStatus = _TestStatus.testing;
      _testMessage = null;
    });

    final config = LlmConfig(
      provider: LlmProvider.openai,
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      defaultModel: _modelController.text.trim().isEmpty
          ? null
          : _modelController.text.trim(),
      defaultMaxTokens: 32,
      timeoutSeconds: 15,
    );

    final service = HttpLlmService(config: config);

    try {
      final response = await service.complete(
        const LlmRequest(
          messages: [LlmMessage.user('Say "hello" in one word.')],
          maxTokens: 32,
        ),
      );

      if (!mounted) return;

      switch (response) {
        case TextLlmResponse(:final content):
          setState(() {
            _testStatus = _TestStatus.success;
            _testMessage = 'Connected! Response: "${content.trim()}"';
          });
        case ToolCallsLlmResponse():
          setState(() {
            _testStatus = _TestStatus.success;
            _testMessage = 'Connected! (received tool call response)';
          });
        case ErrorLlmResponse(:final message):
          setState(() {
            _testStatus = _TestStatus.error;
            _testMessage = message;
          });
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _testStatus = _TestStatus.error;
        _testMessage = e.toString();
      });
    }
  }

  /// Generates and caches the user's keypair for display on the backup page.
  ///
  /// Called when the user navigates to the key backup page so the nsec is
  /// ready to display. Safe to call multiple times — returns immediately if
  /// a key has already been generated in this session.
  Future<void> _ensureKeyGenerated() async {
    if (_keyGenerated || _generatingKey) return;
    setState(() => _generatingKey = true);
    try {
      final auth = ref.read(authServiceProvider);
      if (!await auth.hasIdentity) {
        final identity = await auth.generateKeyPair();
        ref.invalidate(activeProfileIdProvider);
        ref.invalidate(currentIdentityProvider);
        ref.invalidate(allIdentitiesProvider);
        if (!mounted) return;
        setState(() {
          _npub = identity.npub;
          _keyGenerated = true;
        });
      } else {
        final hex = await auth.getPublicKeyHex();
        // Fetch npub from the identity store if available.
        final identities = await ref.read(allIdentitiesProvider.future);
        final activeId = ref.read(activeProfileIdProvider).valueOrNull;
        final identity =
            identities.where((i) => i.id == activeId).firstOrNull ??
            identities.firstOrNull;
        if (!mounted) return;
        setState(() {
          _npub = identity?.npub ?? hex;
          _keyGenerated = true;
        });
      }
    } finally {
      if (mounted) setState(() => _generatingKey = false);
    }
  }

  /// Reveals the nsec once the user explicitly requests it.
  Future<void> _revealNsec() async {
    final auth = ref.read(authServiceProvider);
    final nsec = await auth.exportNsec();
    if (!mounted) return;
    setState(() {
      _nsec = nsec;
      _nsecVisible = true;
    });
  }

  /// Persists the onboarding-complete flag and notifies the parent.
  Future<void> _completeOnboarding() async {
    // Key is already generated when the user reached the backup page.
    // This guard handles the edge case where the user skipped directly
    // to the final page without triggering _ensureKeyGenerated.
    final auth = ref.read(authServiceProvider);
    if (!await auth.hasIdentity) {
      await auth.generateKeyPair();
      ref.invalidate(activeProfileIdProvider);
      ref.invalidate(currentIdentityProvider);
      ref.invalidate(allIdentitiesProvider);
    }

    widget.onComplete();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.kabukBackground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Page view.
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) {
                  setState(() => _currentPage = page);
                  // Pre-generate the key when the user reaches the backup page.
                  if (page == 2) _ensureKeyGenerated();
                },
                physics: const ClampingScrollPhysics(),
                children: [
                  _buildWelcomePage(),
                  _buildConfigurePage(),
                  _buildKeyBackupPage(),
                  _buildReadyPage(),
                ],
              ),
            ),

            // Page indicator dots.
            Padding(
              padding: const EdgeInsets.only(bottom: KabukTheme.spacingLg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, _buildDot),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a single page indicator dot.
  Widget _buildDot(int index) {
    final isActive = index == _currentPage;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? KabukTheme.accentGreen : context.kabukDivider,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Page 1: Welcome
  // ---------------------------------------------------------------------------

  Widget _buildWelcomePage() {
    final isDownloading = _downloadingModelId != null;
    final hasModel = _localModels.isNotEmpty;

    return OnboardingPage(
      icon: Icons.auto_awesome,
      title: 'Welcome to Kabuk',
      description:
          'An agent-first personal OS where AI agents work on your '
          'behalf. Chat naturally, and let specialized agents handle '
          'the rest — from notes to calendars to files.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Show auto-download progress.
          if (isDownloading && _recommendedModel != null) ...[
            Container(
              padding: const EdgeInsets.all(KabukTheme.spacingMd),
              decoration: BoxDecoration(
                color: context.kabukSurfaceVariant,
                borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: KabukTheme.accentGreen,
                        ),
                      ),
                      const SizedBox(width: KabukTheme.spacingSm),
                      Expanded(
                        child: Text(
                          'Downloading ${_recommendedModel!.name} '
                          '(${_recommendedModel!.formattedSize})...',
                          style: TextStyle(
                            color: context.kabukTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: KabukTheme.spacingSm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _downloadProgress,
                      backgroundColor: context.kabukDivider,
                      color: KabukTheme.accentGreen,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: context.kabukTextSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
          ] else if (hasModel) ...[
            Container(
              padding: const EdgeInsets.all(KabukTheme.spacingMd),
              decoration: BoxDecoration(
                color: KabukTheme.accentGreen.withAlpha(20),
                borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                border: Border.all(color: KabukTheme.accentGreen.withAlpha(60)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: KabukTheme.accentGreen,
                    size: 20,
                  ),
                  const SizedBox(width: KabukTheme.spacingSm),
                  Expanded(
                    child: Text(
                      'AI model ready: ${_selectedLocalModel?.name ?? _localModels.first.name}',
                      style: const TextStyle(
                        color: KabukTheme.accentGreen,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
          ],
          FilledButton(
            onPressed: () {
              _goToPage(1);
              // Pre-generate the keypair in parallel so it's ready by page 2.
              _ensureKeyGenerated();
            },
            style: FilledButton.styleFrom(
              backgroundColor: KabukTheme.primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: KabukTheme.spacingXl,
                vertical: KabukTheme.spacingMd,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              ),
            ),
            child: const Text('Get Started', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Page 2: Configure AI
  // ---------------------------------------------------------------------------

  Widget _buildConfigurePage() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: KabukTheme.spacingLg),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const SizedBox(height: KabukTheme.spacingXl),

            // Header icon.
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: KabukTheme.primaryGreen.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.psychology,
                size: 40,
                color: KabukTheme.accentGreen,
              ),
            ),
            const SizedBox(height: KabukTheme.spacingMd),

            Text(
              'Configure AI',
              style: TextStyle(
                color: context.kabukTextPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            Text(
              'The agent runs on-device on MiniCPM5 1B — it auto-downloads '
              'during setup. You can optionally add your own remote '
              'OpenAI-compatible endpoint for complex subagent tasks.',
              style: TextStyle(
                color: context.kabukTextSecondary,
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KabukTheme.spacingLg),

            // Provider selector — on-device MiniCPM or a custom endpoint.
            _buildLabel('Provider'),
            const SizedBox(height: KabukTheme.spacingSm),
            SegmentedButton<LlmProvider>(
              segments: const [
                ButtonSegment(
                  value: LlmProvider.local,
                  label: Text('On-device'),
                  icon: Icon(Icons.phone_android, size: 16),
                ),
                ButtonSegment(
                  value: LlmProvider.openai,
                  label: Text('Custom endpoint'),
                  icon: Icon(Icons.dns_rounded, size: 16),
                ),
              ],
              selected: {_provider},
              onSelectionChanged: (s) => _onProviderChanged(s.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return KabukTheme.accentGreen;
                  }
                  return context.kabukTextSecondary;
                }),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingMd),

            // Local model picker (on-device MiniCPM).
            if (_provider == LlmProvider.local) ...[_buildLocalModelSection()],

            // Remote custom endpoint fields.
            if (_provider != LlmProvider.local) ...[
              _buildLabel('Base URL'),
              const SizedBox(height: KabukTheme.spacingSm),
              TextFormField(
                controller: _baseUrlController,
                style: TextStyle(
                  color: context.kabukTextPrimary,
                  fontSize: 14,
                ),
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: 'https://your-endpoint/v1',
                  hintStyle: TextStyle(
                    color: context.kabukTextSecondary.withAlpha(100),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Base URL is required';
                  }
                  final uri = Uri.tryParse(value.trim());
                  if (uri == null || !uri.hasScheme) {
                    return 'Enter a valid URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: KabukTheme.spacingMd),
              _buildLabel('Model'),
              const SizedBox(height: KabukTheme.spacingSm),
              TextFormField(
                controller: _modelController,
                style: TextStyle(
                  color: context.kabukTextPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'minicpm5-1b',
                  hintStyle: TextStyle(
                    color: context.kabukTextSecondary.withAlpha(100),
                  ),
                ),
              ),
              const SizedBox(height: KabukTheme.spacingMd),
              _buildLabel('API Key (optional)'),
              const SizedBox(height: KabukTheme.spacingSm),
              TextFormField(
                controller: _apiKeyController,
                obscureText: _obscureApiKey,
                autocorrect: false,
                enableSuggestions: false,
                style: TextStyle(
                  color: context.kabukTextPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'sk-... (optional)',
                  hintStyle: TextStyle(
                    color: context.kabukTextSecondary.withAlpha(100),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureApiKey
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: 20,
                      color: context.kabukTextSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _obscureApiKey = !_obscureApiKey),
                  ),
                ),
              ),
              const SizedBox(height: KabukTheme.spacingMd),
            ],

            // Test result.
            if (_testStatus != _TestStatus.idle) ...[
              _buildTestResult(),
              const SizedBox(height: KabukTheme.spacingMd),
            ],

            const SizedBox(height: KabukTheme.spacingMd),
          ],
        ),
      ),
    ),
  ),

  // Bottom action buttons — outside scroll view.
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: KabukTheme.spacingLg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Test + Save buttons.
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _testStatus == _TestStatus.testing
                    ? null
                    : _testConnection,
                icon: const Icon(Icons.wifi_tethering, size: 18),
                label: const Text('Test'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.kabukTextPrimary,
                  side: BorderSide(color: context.kabukDivider),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      KabukTheme.radiusMd,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: KabukTheme.spacingSm),
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  _saveLlmConfig();
                  _goToPage(2);
                },
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Save & Continue'),
                style: FilledButton.styleFrom(
                  backgroundColor: KabukTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      KabukTheme.radiusMd,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: KabukTheme.spacingSm),

        // Skip option.
        TextButton(
          onPressed: () => _goToPage(2),
          child: Text(
            'Skip for now',
            style: TextStyle(color: context.kabukTextSecondary, fontSize: 14),
          ),
        ),
        const SizedBox(height: KabukTheme.spacingSm),
      ],
    ),
  ),
],
    );
  }

  // ---------------------------------------------------------------------------
  // Page 3: Key Backup
  // ---------------------------------------------------------------------------

  /// Onboarding page that surfaces the user's Nostr keypair for backup.
  ///
  /// The user is shown their public key (npub) and can optionally reveal
  /// and copy their private key (nsec). A checkbox acknowledges that the key
  /// has been saved before proceeding to the final page.
  Widget _buildKeyBackupPage() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: KabukTheme.spacingLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: KabukTheme.spacingXl),

          // Header icon.
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: KabukTheme.error.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.key_rounded,
                size: 40,
                color: KabukTheme.error,
              ),
            ),
          ),
          const SizedBox(height: KabukTheme.spacingMd),

          Text(
            'Back Up Your Key',
            style: TextStyle(
              color: context.kabukTextPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          Text(
            'Your Nostr private key is the only way to access your '
            'account. If you lose it, your identity cannot be recovered.',
            style: TextStyle(
              color: context.kabukTextSecondary,
              fontSize: 14,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KabukTheme.spacingLg),

          // Relay bootstrap note.
          Container(
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            decoration: BoxDecoration(
              color: KabukTheme.accentGreen.withAlpha(15),
              borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              border: Border.all(color: KabukTheme.accentGreen.withAlpha(50)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.wifi_tethering_rounded,
                  size: 18,
                  color: KabukTheme.accentGreen,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Relays configured automatically — 8 public relays '
                    'including NIP-17 inbox relays for private messaging.',
                    style: TextStyle(
                      color: KabukTheme.accentGreen,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: KabukTheme.spacingMd),

          // Key display area.
          if (_generatingKey)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: KabukTheme.spacingLg),
                child: CircularProgressIndicator(color: KabukTheme.accentGreen),
              ),
            )
          else if (_keyGenerated) ...[
            // Public key section.
            _buildKeySection(
              icon: Icons.public_rounded,
              title: 'Your Public Key (npub)',
              subtitle: 'Share this with others so they can message you.',
              color: KabukTheme.accentGreen,
              child: _KeyTile(
                label: 'npub',
                value: _npub ?? '—',
                sensitive: false,
              ),
            ),
            const SizedBox(height: KabukTheme.spacingMd),

            // Private key section.
            _buildKeySection(
              icon: Icons.lock_rounded,
              title: 'Your Private Key (nsec)',
              subtitle: 'Never share this with anyone. Store it offline.',
              color: KabukTheme.error,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_nsecVisible && _nsec != null) ...[
                    _KeyTile(label: 'nsec', value: _nsec!, sensitive: true),
                    const SizedBox(height: KabukTheme.spacingSm),
                    OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _nsecVisible = false;
                        _nsec = null;
                      }),
                      icon: const Icon(Icons.visibility_off_rounded, size: 16),
                      label: const Text('Hide'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KabukTheme.error,
                        side: BorderSide(color: KabukTheme.error.withAlpha(60)),
                      ),
                    ),
                  ] else
                    OutlinedButton.icon(
                      onPressed: _revealNsec,
                      icon: const Icon(Icons.visibility_rounded, size: 16),
                      label: const Text('Reveal & Copy nsec'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KabukTheme.error,
                        side: BorderSide(color: KabukTheme.error.withAlpha(60)),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: KabukTheme.spacingMd),
        ],
      ),
    ),
  ),

  // Bottom action buttons — outside scroll view.
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: KabukTheme.spacingLg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Acknowledgement checkbox.
        GestureDetector(
          onTap: () => setState(
            () => _keyBackupAcknowledged = !_keyBackupAcknowledged,
          ),
          child: Row(
            children: [
              Checkbox(
                value: _keyBackupAcknowledged,
                onChanged: (v) =>
                    setState(() => _keyBackupAcknowledged = v ?? false),
                activeColor: KabukTheme.accentGreen,
                side: BorderSide(color: context.kabukTextSecondary),
              ),
              const SizedBox(width: KabukTheme.spacingSm),
              Expanded(
                child: Text(
                  'I\'ve saved my private key in a safe place.',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.kabukTextPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: KabukTheme.spacingSm),

        // Continue button.
        FilledButton(
          onPressed: _keyBackupAcknowledged ? () => _goToPage(3) : null,
          style: FilledButton.styleFrom(
            backgroundColor: KabukTheme.primaryGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
            ),
          ),
          child: const Text('Continue', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: KabukTheme.spacingSm),
        TextButton(
          onPressed: () => _goToPage(3),
          child: Text(
            'Skip (I\'ll do this later in Settings)',
            style: TextStyle(color: context.kabukTextSecondary, fontSize: 13),
          ),
        ),
        const SizedBox(height: KabukTheme.spacingSm),
      ],
    ),
  ),
],
    );
  }

  Widget _buildKeySection({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: BoxDecoration(
        color: color.withAlpha(8),
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: color.withAlpha(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color.withAlpha(200)),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: color.withAlpha(220),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: context.kabukTextSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          child,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Page 4: Ready
  // ---------------------------------------------------------------------------

  Widget _buildReadyPage() {
    return OnboardingPage(
      icon: Icons.rocket_launch,
      title: "You're All Set!",
      description: 'Here are a few things to try:',
      child: Column(
        children: [
          _buildTip(Icons.chat, 'Try the Chat', 'Ask an agent anything.'),
          const SizedBox(height: KabukTheme.spacingSm),
          _buildTip(
            Icons.explore,
            'Explore Your Data',
            'Browse your knowledge store.',
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          _buildTip(
            Icons.note_add,
            'Create Notes',
            'Capture ideas on the fly.',
          ),
          const SizedBox(height: KabukTheme.spacingLg),
          FilledButton(
            onPressed: _completeOnboarding,
            style: FilledButton.styleFrom(
              backgroundColor: KabukTheme.primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: KabukTheme.spacingXl,
                vertical: KabukTheme.spacingMd,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              ),
            ),
            child: const Text(
              'Start Using Kabuk',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared widgets
  // ---------------------------------------------------------------------------

  /// Builds the local model selection and download section.
  Widget _buildLocalModelSection() {
    final manager = ref.read(modelManagerProvider);
    final recommended = manager.recommendedModels;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Installed models.
        _buildLabel('Installed Models'),
        const SizedBox(height: KabukTheme.spacingSm),
        if (_loadingModels)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: KabukTheme.spacingMd),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_localModels.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            decoration: BoxDecoration(
              color: context.kabukSurfaceVariant,
              borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
              border: Border.all(color: context.kabukDivider.withAlpha(80)),
            ),
            child: Text(
              'No models installed yet. Download one below.',
              style: TextStyle(color: context.kabukTextSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          )
        else
          ...(_localModels.map(_buildLocalModelTile)),
        const SizedBox(height: KabukTheme.spacingMd),

        // Download section.
        _buildLabel('Download a Model'),
        const SizedBox(height: KabukTheme.spacingSm),
        Text(
          'Tiny models run on-device with no internet needed. '
          'Smaller models are faster but less capable.',
          style: TextStyle(
            color: context.kabukTextSecondary,
            fontSize: 12,
            height: 1.3,
          ),
        ),
        const SizedBox(height: KabukTheme.spacingSm),
        ...(recommended.map(_buildDownloadModelTile)),
        const SizedBox(height: KabukTheme.spacingMd),
      ],
    );
  }

  /// A selectable tile for a locally installed model.
  Widget _buildLocalModelTile(LocalModelInfo model) {
    final isSelected = _selectedLocalModel?.id == model.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => setState(() => _selectedLocalModel = model),
        borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
        child: Container(
          padding: const EdgeInsets.all(KabukTheme.spacingSm),
          decoration: BoxDecoration(
            color: isSelected
                ? KabukTheme.primaryGreen.withAlpha(20)
                : context.kabukSurfaceVariant,
            borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
            border: Border.all(
              color: isSelected
                  ? KabukTheme.accentGreen
                  : context.kabukDivider.withAlpha(80),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected
                    ? KabukTheme.accentGreen
                    : context.kabukTextSecondary,
                size: 20,
              ),
              const SizedBox(width: KabukTheme.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: TextStyle(
                        color: context.kabukTextPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${model.formattedSize}'
                      '${model.quantization != null ? ' \u00b7 ${model.quantization}' : ''}',
                      style: TextStyle(
                        color: context.kabukTextSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A tile for a downloadable recommended model.
  Widget _buildDownloadModelTile(RemoteModelInfo model) {
    final isDownloading = _downloadingModelId == model.id;
    final isInstalled = _localModels.any((m) => m.fileName == model.fileName);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(KabukTheme.spacingSm),
        decoration: BoxDecoration(
          color: context.kabukSurfaceVariant,
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
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
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${model.formattedSize}'
                        '${model.quantization != null ? ' \u00b7 ${model.quantization}' : ''}',
                        style: TextStyle(
                          color: context.kabukTextSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isInstalled)
                  const Icon(
                    Icons.check_circle,
                    color: KabukTheme.accentGreen,
                    size: 20,
                  )
                else if (isDownloading)
                  SizedBox(
                    width: 60,
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          value: _downloadProgress,
                          backgroundColor: context.kabukDivider,
                          color: KabukTheme.accentGreen,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            color: context.kabukTextSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    height: 30,
                    child: OutlinedButton(
                      onPressed: () => _downloadModel(model),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KabukTheme.accentGreen,
                        side: const BorderSide(color: KabukTheme.accentGreen),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            KabukTheme.radiusSm,
                          ),
                        ),
                      ),
                      child: const Text(
                        'Download',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
            if (model.description != null) ...[
              const SizedBox(height: 4),
              Text(
                model.description!,
                style: TextStyle(
                  color: context.kabukTextSecondary,
                  fontSize: 11,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: TextStyle(
          color: context.kabukTextSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTip(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: BoxDecoration(
        color: context.kabukSurfaceVariant,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, color: KabukTheme.accentGreen, size: 24),
          const SizedBox(width: KabukTheme.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.kabukTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.kabukTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestResult() {
    final Color color;
    final IconData icon;

    switch (_testStatus) {
      case _TestStatus.testing:
        color = context.kabukTextSecondary;
        icon = Icons.hourglass_top;
      case _TestStatus.success:
        color = KabukTheme.accentGreen;
        icon = Icons.check_circle;
      case _TestStatus.error:
        color = KabukTheme.error;
        icon = Icons.error_outline;
      case _TestStatus.idle:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_testStatus == _TestStatus.testing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, color: color, size: 20),
          const SizedBox(width: KabukTheme.spacingSm),
          Expanded(
            child: Text(
              _testStatus == _TestStatus.testing
                  ? 'Testing connection...'
                  : _testMessage ?? '',
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _KeyTile — compact display for a Nostr key string
// ---------------------------------------------------------------------------

/// A compact tile that shows a Nostr key value with a copy-to-clipboard button.
///
/// When [sensitive] is true the tile gets a red tint to indicate a secret.
class _KeyTile extends StatelessWidget {
  const _KeyTile({
    required this.label,
    required this.value,
    required this.sensitive,
  });

  final String label;
  final String value;
  final bool sensitive;

  @override
  Widget build(BuildContext context) {
    final color = sensitive ? KabukTheme.error : KabukTheme.accentGreen;
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label copied to clipboard'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingSm,
          vertical: KabukTheme.spacingXs,
        ),
        decoration: BoxDecoration(
          color: context.kabukSurfaceVariant,
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          border: Border.all(color: color.withAlpha(30)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: KabukTheme.spacingSm),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: context.kabukTextPrimary,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 16),
              color: context.kabukTextSecondary,
              tooltip: 'Copy $label',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$label copied to clipboard'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Test status enum
// ---------------------------------------------------------------------------

/// Internal enum for tracking connection test state.
enum _TestStatus {
  /// No test has been run.
  idle,

  /// Test in progress.
  testing,

  /// Test succeeded.
  success,

  /// Test failed.
  error,
}
