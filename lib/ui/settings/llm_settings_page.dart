/// LLM configuration settings sub-page.
///
/// Kabuk standardizes on the on-device MiniCPM5 1B model for the agent.
/// This page configures the optional **remote subagent endpoint** — a
/// single OpenAI-compatible endpoint the user provides (LM Studio, vLLM,
/// llama.cpp server, a hosted gateway, etc.). No external providers
/// (OpenAI, Anthropic) are offered.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/agents/http_llm.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/ui/theme.dart';

/// Internal enum for tracking connection test state.
enum ConnectionTestStatus {
  /// No test has been run.
  idle,

  /// Test is in progress.
  testing,

  /// Test succeeded.
  success,

  /// Test failed.
  error,
}

/// LLM configuration sub-page — the remote subagent endpoint.
class LlmSettingsPage extends ConsumerStatefulWidget {
  /// Creates a [LlmSettingsPage].
  const LlmSettingsPage({super.key});

  @override
  ConsumerState<LlmSettingsPage> createState() => _LlmSettingsPageState();
}

class _LlmSettingsPageState extends ConsumerState<LlmSettingsPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _apiKeyController;
  late TextEditingController _modelController;
  late TextEditingController _baseUrlController;
  late TextEditingController _maxTokensController;
  double _temperature = 0.7;
  int _timeoutSeconds = 60;
  bool _obscureApiKey = true;

  ConnectionTestStatus _testStatus = ConnectionTestStatus.idle;
  String? _testMessage;

  /// The standard remote model name for the custom endpoint.
  static const String _defaultRemoteModel = 'minicpm5-1b';

  @override
  void initState() {
    super.initState();
    final existing = ref.read(llmConfigProvider);
    // Only the OpenAI-compatible wire format is used for the remote tier.
    _apiKeyController = TextEditingController(text: existing?.apiKey ?? '');
    _modelController = TextEditingController(
      text: existing?.defaultModel ?? _defaultRemoteModel,
    );
    _baseUrlController = TextEditingController(
      text: existing?.baseUrl ?? '',
    );
    _maxTokensController = TextEditingController(
      text: (existing?.defaultMaxTokens ?? 4096).toString(),
    );
    _temperature = existing?.defaultTemperature ?? 0.7;
    _timeoutSeconds = existing?.timeoutSeconds ?? 60;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _baseUrlController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  LlmConfig? _buildConfig({int? maxTokens, int? timeoutSeconds}) {
    if (!_formKey.currentState!.validate()) return null;
    return LlmConfig.openAICompatible(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim().isEmpty
          ? null
          : _modelController.text.trim(),
      // Base constructor defaults are applied; override token/timeout when
      // building a test config.
    ).copyWithTestParams(
      maxTokens: maxTokens,
      timeoutSeconds: timeoutSeconds,
    );
  }

  void _save() {
    final config = _buildConfig();
    if (config == null) return;

    ref.read(llmConfigProvider.notifier).setConfig(config);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Remote endpoint saved'),
        backgroundColor: KabukTheme.primaryGreen,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _testConnection() async {
    final config = _buildConfig(maxTokens: 32, timeoutSeconds: 15);
    if (config == null) return;

    setState(() {
      _testStatus = ConnectionTestStatus.testing;
      _testMessage = null;
    });

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
            _testStatus = ConnectionTestStatus.success;
            _testMessage = 'Connected! Response: "${content.trim()}"';
          });
        case ToolCallsLlmResponse():
          setState(() {
            _testStatus = ConnectionTestStatus.success;
            _testMessage = 'Connected! (received tool call response)';
          });
        case ErrorLlmResponse(:final message):
          setState(() {
            _testStatus = ConnectionTestStatus.error;
            _testMessage = message;
          });
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _testStatus = ConnectionTestStatus.error;
        _testMessage = e.toString();
      });
    }
  }

  void _clearConfig() {
    ref.read(llmConfigProvider.notifier).setConfig(null);
    setState(() {
      _testStatus = ConnectionTestStatus.idle;
      _testMessage = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Remote endpoint cleared'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentConfig = ref.watch(llmConfigProvider);
    final isConfigured = currentConfig != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote LLM Endpoint'),
        actions: [
          if (isConfigured)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear configuration',
              onPressed: _clearConfig,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusBanner(isConfigured),
              const SizedBox(height: KabukTheme.spacingLg),

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
                    const Icon(
                      Icons.smart_toy_outlined,
                      size: 16,
                      color: KabukTheme.accentGreen,
                    ),
                    const SizedBox(width: KabukTheme.spacingSm),
                    Expanded(
                      child: Text(
                        'The agent runs on-device on MiniCPM5 1B. '
                        'This optional endpoint is used only as a remote '
                        'subagent for complex tasks. Point it at any '
                        'OpenAI-compatible server you control.',
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

              _buildSectionLabel('Base URL'),
              const SizedBox(height: KabukTheme.spacingSm),
              _buildBaseUrlField(),
              const SizedBox(height: KabukTheme.spacingLg),

              _buildSectionLabel('Model'),
              const SizedBox(height: KabukTheme.spacingSm),
              _buildModelField(),
              const SizedBox(height: KabukTheme.spacingLg),

              _buildSectionLabel('API Key (optional)'),
              const SizedBox(height: KabukTheme.spacingSm),
              _buildApiKeyField(),
              const SizedBox(height: KabukTheme.spacingLg),

              _buildSectionLabel(
                'Temperature: ${_temperature.toStringAsFixed(2)}',
              ),
              const SizedBox(height: KabukTheme.spacingSm),
              _buildTemperatureSlider(),
              const SizedBox(height: KabukTheme.spacingLg),

              _buildSectionLabel('Max Tokens'),
              const SizedBox(height: KabukTheme.spacingSm),
              _buildMaxTokensField(),
              const SizedBox(height: KabukTheme.spacingLg),

              _buildSectionLabel('Timeout: ${_timeoutSeconds}s'),
              const SizedBox(height: KabukTheme.spacingSm),
              _buildTimeoutSlider(),
              const SizedBox(height: KabukTheme.spacingLg),

              if (_testStatus != ConnectionTestStatus.idle) _buildTestResult(),
              if (_testStatus != ConnectionTestStatus.idle)
                const SizedBox(height: KabukTheme.spacingMd),

              _buildActionButtons(),
              const SizedBox(height: KabukTheme.spacingXl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner(bool isConfigured) {
    return Container(
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: BoxDecoration(
        color: isConfigured
            ? KabukTheme.primaryGreen.withAlpha(25)
            : KabukTheme.error.withAlpha(25),
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(
          color: isConfigured
              ? KabukTheme.primaryGreen.withAlpha(80)
              : KabukTheme.error.withAlpha(80),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConfigured ? Icons.check_circle_outline : Icons.info_outline,
            color: isConfigured ? KabukTheme.accentGreen : KabukTheme.error,
            size: 24,
          ),
          const SizedBox(width: KabukTheme.spacingSm),
          Expanded(
            child: Text(
              isConfigured
                  ? 'Endpoint configured: '
                        '${ref.read(llmConfigProvider)!.defaultModel ?? "default"}'
                  : 'No remote endpoint configured — the on-device '
                        'MiniCPM5 1B handles everything.',
              style: TextStyle(
                color:
                    isConfigured ? KabukTheme.accentGreen : KabukTheme.error,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) => Text(
    label,
    style: TextStyle(
      color: context.kabukTextSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
  );

  Widget _buildApiKeyField() {
    return TextFormField(
      controller: _apiKeyController,
      obscureText: _obscureApiKey,
      autocorrect: false,
      enableSuggestions: false,
      style: TextStyle(color: context.kabukTextPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'sk-... (optional for self-hosted gateways)',
        hintStyle: TextStyle(color: context.kabukTextSecondary.withAlpha(100)),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureApiKey ? Icons.visibility_off : Icons.visibility,
            size: 20,
            color: context.kabukTextSecondary,
          ),
          onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
        ),
      ),
    );
  }

  Widget _buildModelField() {
    return TextFormField(
      controller: _modelController,
      style: TextStyle(color: context.kabukTextPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: _defaultRemoteModel,
        hintStyle: TextStyle(color: context.kabukTextSecondary.withAlpha(100)),
      ),
    );
  }

  Widget _buildBaseUrlField() {
    return TextFormField(
      controller: _baseUrlController,
      style: TextStyle(color: context.kabukTextPrimary, fontSize: 14),
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        hintText: 'https://your-endpoint/v1',
        hintStyle: TextStyle(color: context.kabukTextSecondary.withAlpha(100)),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Base URL is required';
        }
        final uri = Uri.tryParse(value.trim());
        if (uri == null || !uri.hasScheme) {
          return 'Enter a valid URL (e.g. https://your-endpoint/v1)';
        }
        return null;
      },
    );
  }

  Widget _buildTemperatureSlider() {
    return SliderTheme(
      data: SliderThemeData(
        activeTrackColor: KabukTheme.primaryGreen,
        inactiveTrackColor: context.kabukSurfaceVariant,
        thumbColor: KabukTheme.accentGreen,
        overlayColor: KabukTheme.primaryGreen.withAlpha(40),
        valueIndicatorColor: KabukTheme.primaryGreen,
        valueIndicatorTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
      ),
      child: Slider(
        value: _temperature,
        min: 0.0,
        max: 1.5,
        divisions: 30,
        label: _temperature.toStringAsFixed(2),
        onChanged: (value) => setState(() => _temperature = value),
      ),
    );
  }

  Widget _buildMaxTokensField() {
    return TextFormField(
      controller: _maxTokensController,
      style: TextStyle(color: context.kabukTextPrimary, fontSize: 14),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        hintText: '4096',
        hintStyle: TextStyle(color: context.kabukTextSecondary.withAlpha(100)),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Max tokens is required';
        }
        final n = int.tryParse(value.trim());
        if (n == null || n < 1) {
          return 'Enter a positive integer';
        }
        return null;
      },
    );
  }

  Widget _buildTimeoutSlider() {
    return SliderTheme(
      data: SliderThemeData(
        activeTrackColor: KabukTheme.primaryGreen,
        inactiveTrackColor: context.kabukSurfaceVariant,
        thumbColor: KabukTheme.accentGreen,
        overlayColor: KabukTheme.primaryGreen.withAlpha(40),
        valueIndicatorColor: KabukTheme.primaryGreen,
        valueIndicatorTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
      ),
      child: Slider(
        value: _timeoutSeconds.toDouble(),
        min: 10,
        max: 120,
        divisions: 22,
        label: '${_timeoutSeconds}s',
        onChanged: (value) => setState(() => _timeoutSeconds = value.round()),
      ),
    );
  }

  Widget _buildTestResult() {
    final Color color;
    final IconData icon;

    switch (_testStatus) {
      case ConnectionTestStatus.testing:
        color = context.kabukTextSecondary;
        icon = Icons.hourglass_top;
      case ConnectionTestStatus.success:
        color = KabukTheme.accentGreen;
        icon = Icons.check_circle;
      case ConnectionTestStatus.error:
        color = KabukTheme.error;
        icon = Icons.error_outline;
      case ConnectionTestStatus.idle:
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
          if (_testStatus == ConnectionTestStatus.testing)
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
              _testStatus == ConnectionTestStatus.testing
                  ? 'Testing connection...'
                  : _testMessage ?? '',
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _testStatus == ConnectionTestStatus.testing
                ? null
                : _testConnection,
            icon: const Icon(Icons.wifi_tethering, size: 18),
            label: const Text('Test'),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.kabukTextPrimary,
              side: BorderSide(color: context.kabukDivider),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              ),
            ),
          ),
        ),
        const SizedBox(width: KabukTheme.spacingSm),
        Expanded(
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save'),
            style: FilledButton.styleFrom(
              backgroundColor: KabukTheme.primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

extension on LlmConfig {
  /// Returns a copy with overridden test params.
  LlmConfig copyWithTestParams({int? maxTokens, int? timeoutSeconds}) =>
      LlmConfig(
        provider: provider,
        baseUrl: baseUrl,
        apiKey: apiKey,
        defaultModel: defaultModel,
        defaultTemperature: defaultTemperature,
        defaultMaxTokens: maxTokens ?? this.defaultMaxTokens,
        timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      );
}