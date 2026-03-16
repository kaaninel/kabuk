/// Service provider configuration settings sub-page.
///
/// Lists all service providers with enable/disable toggles and
/// detail configuration pages for API keys and base URLs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/ui/settings/settings_shared.dart';
import 'package:kabuk/ui/theme.dart';

/// Lists all service providers with enable/disable toggles.
class ServiceProvidersPage extends ConsumerWidget {
  /// Creates a [ServiceProvidersPage].
  const ServiceProvidersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(serviceProvidersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Service Providers')),
      body: ListView(
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        children: [
          // Info banner.
          Container(
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            decoration: BoxDecoration(
              color: KabukTheme.blueAccent.withAlpha(10),
              borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              border: Border.all(color: KabukTheme.blueAccent.withAlpha(30)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: KabukTheme.blueAccent.withAlpha(180),
                  size: 20,
                ),
                const SizedBox(width: KabukTheme.spacingSm),
                Expanded(
                  child: Text(
                    'Enable services to let agents fetch and sync data from '
                    'external platforms. Credentials are stored locally.',
                    style: TextStyle(
                      color: KabukTheme.blueAccent.withAlpha(200),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: KabukTheme.spacingMd),

          for (final provider in providers) ...[
            _ServiceProviderRow(provider: provider),
            const SizedBox(height: KabukTheme.spacingSm),
          ],
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}

/// A row for a single service provider.
class _ServiceProviderRow extends ConsumerWidget {
  const _ServiceProviderRow({required this.provider});

  final ServiceProviderConfig provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: KabukTheme.cardColor,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(
          color: provider.enabled
              ? provider.color.withAlpha(40)
              : KabukTheme.divider,
          width: provider.enabled ? 1.0 : 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ServiceProviderDetailPage(providerId: provider.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: provider.color.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(provider.icon, size: 22, color: provider.color),
                ),
                const SizedBox(width: KabukTheme.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        provider.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: KabukTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: provider.enabled,
                  activeThumbColor: provider.color,
                  onChanged: (value) {
                    ref
                        .read(serviceProvidersProvider.notifier)
                        .update(provider.copyWith(enabled: value));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Detail/configuration page for a single service provider.
class ServiceProviderDetailPage extends ConsumerStatefulWidget {
  /// Creates a [ServiceProviderDetailPage].
  const ServiceProviderDetailPage({super.key, required this.providerId});

  /// The ID of the provider to configure.
  final String providerId;

  @override
  ConsumerState<ServiceProviderDetailPage> createState() =>
      _ServiceProviderDetailPageState();
}

class _ServiceProviderDetailPageState
    extends ConsumerState<ServiceProviderDetailPage> {
  late TextEditingController _apiKeyController;
  late TextEditingController _baseUrlController;
  late TextEditingController _usernameController;
  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();
    final provider = ref
        .read(serviceProvidersProvider)
        .firstWhere((p) => p.id == widget.providerId);
    _apiKeyController = TextEditingController(text: provider.apiKey ?? '');
    _baseUrlController = TextEditingController(text: provider.baseUrl ?? '');
    _usernameController = TextEditingController(text: provider.username ?? '');
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _save() {
    final providers = ref.read(serviceProvidersProvider);
    final provider = providers.firstWhere((p) => p.id == widget.providerId);

    ref
        .read(serviceProvidersProvider.notifier)
        .update(
          provider.copyWith(
            apiKey: _apiKeyController.text.trim().isEmpty
                ? null
                : _apiKeyController.text.trim(),
            baseUrl: _baseUrlController.text.trim().isEmpty
                ? null
                : _baseUrlController.text.trim(),
            username: _usernameController.text.trim().isEmpty
                ? null
                : _usernameController.text.trim(),
          ),
        );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Service configuration saved'),
        backgroundColor: KabukTheme.primaryGreen,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref
        .watch(serviceProvidersProvider)
        .firstWhere((p) => p.id == widget.providerId);

    return Scaffold(
      appBar: AppBar(title: Text(provider.name)),
      body: ListView(
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        children: [
          // Provider header.
          Container(
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            decoration: BoxDecoration(
              color: provider.color.withAlpha(10),
              borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              border: Border.all(color: provider.color.withAlpha(30)),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: provider.color.withAlpha(25),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(provider.icon, size: 28, color: provider.color),
                ),
                const SizedBox(width: KabukTheme.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        provider.description,
                        style: const TextStyle(
                          color: KabukTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: KabukTheme.spacingLg),

          // Enable toggle.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: KabukTheme.spacingMd,
              vertical: KabukTheme.spacingSm,
            ),
            decoration: BoxDecoration(
              color: KabukTheme.cardColor,
              borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              border: Border.all(color: KabukTheme.divider, width: 0.5),
            ),
            child: Row(
              children: [
                const Text(
                  'Enabled',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const Spacer(),
                Switch.adaptive(
                  value: provider.enabled,
                  activeThumbColor: provider.color,
                  onChanged: (value) {
                    ref
                        .read(serviceProvidersProvider.notifier)
                        .update(provider.copyWith(enabled: value));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: KabukTheme.spacingLg),

          // Credentials section.
          Text(
            'CREDENTIALS',
            style: TextStyle(
              color: provider.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: KabukTheme.spacingSm),

          // Username.
          _buildLabel('Username / Account'),
          const SizedBox(height: KabukTheme.spacingXs),
          TextFormField(
            controller: _usernameController,
            style: const TextStyle(color: KabukTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(hintText: 'Optional'),
          ),
          const SizedBox(height: KabukTheme.spacingMd),

          // API Key.
          _buildLabel('API Key / Token'),
          const SizedBox(height: KabukTheme.spacingXs),
          TextFormField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(color: KabukTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Optional — required for some endpoints',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureApiKey ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                  color: KabukTheme.textSecondary,
                ),
                onPressed: () =>
                    setState(() => _obscureApiKey = !_obscureApiKey),
              ),
            ),
          ),
          const SizedBox(height: KabukTheme.spacingMd),

          // Base URL.
          _buildLabel('Base URL'),
          const SizedBox(height: KabukTheme.spacingXs),
          TextFormField(
            controller: _baseUrlController,
            style: const TextStyle(color: KabukTheme.textPrimary, fontSize: 14),
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: provider.baseUrl ?? 'https://...',
            ),
          ),
          const SizedBox(height: KabukTheme.spacingLg),

          // Save button.
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save Configuration'),
            style: FilledButton.styleFrom(
              backgroundColor: provider.color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              ),
            ),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildLabel(String label) => Text(
    label,
    style: const TextStyle(
      color: KabukTheme.textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
  );
}
