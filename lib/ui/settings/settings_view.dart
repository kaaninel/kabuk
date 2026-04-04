/// Settings — hub page for app configuration.
///
/// Provides sections for LLM provider config, service provider setup,
/// identity management, relay configuration, and about information.
///
/// Sub-pages are split into separate files for maintainability:
/// - [IdentityPage] in identity_page.dart
/// - [LlmSettingsPage] in llm_settings_page.dart
/// - [ServiceProvidersPage] in service_providers_page.dart
/// - [RelaySettingsPage] in relay_settings_page.dart
/// - [LocalModelsPage] in local_models_page.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/config/constants.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/ui/explore/explore_view.dart';
import 'package:kabuk/ui/explore/usenet_settings_sheet.dart';
import 'package:kabuk/ui/settings/dev_mode_page.dart';
import 'package:kabuk/ui/settings/feed_sources_page.dart';
import 'package:kabuk/ui/settings/identity_page.dart';
import 'package:kabuk/ui/settings/llm_settings_page.dart';
import 'package:kabuk/ui/settings/local_models_page.dart';
import 'package:kabuk/ui/settings/my_profile_page.dart';
import 'package:kabuk/ui/settings/relay_settings_page.dart';
import 'package:kabuk/ui/settings/service_providers_page.dart';
import 'package:kabuk/ui/settings/settings_shared.dart';
import 'package:kabuk/ui/settings/usenet_settings_page.dart';
import 'package:kabuk/ui/theme.dart';

// Re-export shared types so existing imports still work.
export 'package:kabuk/ui/settings/settings_shared.dart';

/// Settings hub — main settings page with multiple sections.
class SettingsView extends ConsumerStatefulWidget {
  /// Creates a [SettingsView].
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  /// Tap count toward the Easter-egg dev mode unlock (requires 7 taps).
  int _versionTapCount = 0;

  void _onVersionTap() {
    _versionTapCount++;
    final remaining = 7 - _versionTapCount;
    if (remaining > 0 && remaining <= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$remaining more tap${remaining == 1 ? '' : 's'} to unlock developer mode',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    } else if (_versionTapCount >= 7) {
      _versionTapCount = 0;
      final notifier = ref.read(devModeProvider.notifier);
      final current = ref.read(devModeProvider);
      notifier.setEnabled(!current);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            current ? 'Developer mode disabled' : 'Developer mode enabled',
          ),
          backgroundColor: current
              ? context.kabukTextSecondary
              : KabukTheme.accentGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final llmConfig = ref.watch(llmConfigProvider);
    final providers = ref.watch(serviceProvidersProvider);
    final enabledCount = providers.where((p) => p.enabled).length;
    final identityAsync = ref.watch(currentIdentityProvider);
    final allIds = ref.watch(allIdentitiesProvider);
    final devMode = ref.watch(devModeProvider);
    final feedSubs = ref.watch(subscriptionsProvider);
    final feedCount = feedSubs.valueOrNull?.length ?? 0;
    final usenetIndexers = ref.watch(usenetIndexersProvider);
    final usenetProviders = ref.watch(usenetProvidersProvider);
    final usenetCount = (usenetIndexers.valueOrNull?.length ?? 0) +
        (usenetProviders.valueOrNull?.length ?? 0);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        children: [
          // --- Identity Section ---
          const SettingsSectionHeader(
            icon: Icons.key_rounded,
            title: 'Identity',
            color: KabukTheme.warmAccent,
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          SettingsTile(
            icon: Icons.account_circle_rounded,
            iconColor: KabukTheme.accentGreen,
            title: 'My Profile',
            subtitle: 'View your public key & QR code',
            trailing: Icon(
              Icons.chevron_right,
              color: context.kabukTextSecondary,
              size: 20,
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MyProfilePage()),
            ),
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          identityAsync.when(
            data: (identity) {
              final count = allIds.valueOrNull?.length ?? 0;
              final subtitle = identity != null
                  ? '${identity.npub != null ? '${identity.npub!.substring(0, 20)}...' : identity.id.substring(0, 16)}'
                        '${count > 1 ? ' · $count identities' : ''}'
                  : 'Generate a secp256k1 keypair';
              return SettingsTile(
                icon: identity != null
                    ? Icons.verified_user_rounded
                    : Icons.person_add_rounded,
                iconColor: KabukTheme.warmAccent,
                title: identity != null
                    ? (identity.displayName.isNotEmpty
                          ? identity.displayName
                          : 'Unnamed Identity')
                    : 'Set Up Identity',
                subtitle: subtitle,
                trailing: Semantics(
                  label: identity != null ? 'Active' : 'Not set up',
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: identity != null
                          ? KabukTheme.success
                          : context.kabukTextSecondary,
                    ),
                  ),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const IdentityPage()),
                ),
              );
            },
            loading: () => SettingsTile(
              icon: Icons.hourglass_empty_rounded,
              iconColor: context.kabukTextSecondary,
              title: 'Loading identity...',
              subtitle: 'Checking keypair',
            ),
            error: (_, _) => const SettingsTile(
              icon: Icons.error_outline_rounded,
              iconColor: KabukTheme.error,
              title: 'Identity Error',
              subtitle: 'Could not load keypair',
            ),
          ),
          const SizedBox(height: KabukTheme.spacingLg),

          // --- AI / LLM Section ---
          const SettingsSectionHeader(
            icon: Icons.psychology_rounded,
            title: 'AI Provider',
            color: KabukTheme.accentGreen,
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          SettingsTile(
            icon: Icons.smart_toy_rounded,
            iconColor: KabukTheme.accentGreen,
            title: 'LLM Configuration',
            subtitle: llmConfig != null
                ? '${_providerLabel(llmConfig.provider)} \u00b7 ${llmConfig.defaultModel ?? "default"}'
                : 'Not configured',
            trailing: Semantics(
              label: llmConfig != null ? 'Configured' : 'Not configured',
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: llmConfig != null
                      ? KabukTheme.success
                      : KabukTheme.error,
                ),
              ),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LlmSettingsPage()),
            ),
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          SettingsTile(
            icon: Icons.phone_android_rounded,
            iconColor: KabukTheme.accentGreen,
            title: 'Local Models',
            subtitle: 'Manage on-device GGUF models',
            trailing: Icon(
              Icons.chevron_right,
              color: context.kabukTextSecondary,
              size: 20,
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LocalModelsPage()),
            ),
          ),
          const SizedBox(height: KabukTheme.spacingLg),

          // --- Service Providers Section ---
          const SettingsSectionHeader(
            icon: Icons.cloud_rounded,
            title: 'Service Providers',
            color: KabukTheme.blueAccent,
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          SettingsTile(
            icon: Icons.api_rounded,
            iconColor: KabukTheme.blueAccent,
            title: 'Configure Services',
            subtitle: enabledCount > 0
                ? '$enabledCount service${enabledCount > 1 ? 's' : ''} enabled'
                : 'No services configured',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: KabukTheme.blueAccent.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$enabledCount/${providers.length}',
                style: const TextStyle(
                  color: KabukTheme.blueAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ServiceProvidersPage(),
              ),
            ),
          ),
          for (final provider in providers.where((p) => p.enabled)) ...[
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: SettingsTile(
                icon: provider.icon,
                iconColor: provider.color,
                title: provider.name,
                subtitle: 'Enabled',
                compact: true,
                trailing: const Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: KabukTheme.success,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ServiceProviderDetailPage(providerId: provider.id),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: KabukTheme.spacingLg),

          // --- Feed Sources Section ---
          const SettingsSectionHeader(
            icon: Icons.rss_feed_rounded,
            title: 'Feed Sources',
            color: KabukTheme.warmAccent,
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          SettingsTile(
            icon: Icons.rss_feed_rounded,
            iconColor: KabukTheme.warmAccent,
            title: 'Feed Sources',
            subtitle: feedCount > 0
                ? '$feedCount source${feedCount > 1 ? 's' : ''} configured'
                : 'No sources configured',
            trailing: Icon(
              Icons.chevron_right,
              color: context.kabukTextSecondary,
              size: 20,
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const FeedSourcesPage(),
              ),
            ),
          ),
          const SizedBox(height: KabukTheme.spacingLg),

          // --- Usenet Section ---
          const SettingsSectionHeader(
            icon: Icons.dns_rounded,
            title: 'Usenet',
            color: KabukTheme.blueAccent,
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          SettingsTile(
            icon: Icons.search_rounded,
            iconColor: KabukTheme.blueAccent,
            title: 'Indexers & Providers',
            subtitle: usenetCount > 0
                ? '$usenetCount configured'
                : 'Manage Newznab indexers and NNTP servers',
            trailing: usenetCount > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: KabukTheme.blueAccent.withAlpha(15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$usenetCount',
                      style: const TextStyle(
                        color: KabukTheme.blueAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : Icon(
                    Icons.chevron_right,
                    color: context.kabukTextSecondary,
                    size: 20,
                  ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const UsenetSettingsPage(),
              ),
            ),
          ),
          const SizedBox(height: KabukTheme.spacingLg),

          // --- Nostr Relays Section ---
          const SettingsSectionHeader(
            icon: Icons.cell_tower_rounded,
            title: 'Nostr Relays',
            color: KabukTheme.warmAccent,
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          SettingsTile(
            icon: Icons.cell_tower_rounded,
            iconColor: KabukTheme.warmAccent,
            title: 'Manage Relays',
            subtitle: _relaySubtitle(),
            trailing: Semantics(
              label: _hasConnectedRelays() ? 'Connected' : 'Disconnected',
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hasConnectedRelays()
                      ? KabukTheme.success
                      : context.kabukTextSecondary,
                ),
              ),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const RelaySettingsPage(),
              ),
            ),
          ),
          const SizedBox(height: KabukTheme.spacingLg),

          // --- Appearance Section ---
          const SettingsSectionHeader(
            icon: Icons.palette_rounded,
            title: 'Appearance',
            color: KabukTheme.purpleAccent,
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          _AppearanceSection(),
          const SizedBox(height: KabukTheme.spacingLg),

          // --- Data & Storage Section (dev mode only – features not yet built) ---
          if (devMode) ...[
            const SettingsSectionHeader(
              icon: Icons.storage_rounded,
              title: 'Data & Storage',
              color: KabukTheme.purpleAccent,
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            SettingsTile(
              icon: Icons.dns_rounded,
              iconColor: KabukTheme.purpleAccent,
              title: 'Knowledge Store',
              subtitle: 'Coming soon · RDF triple store',
              onTap: () => showComingSoonDialog(
                context,
                title: 'Knowledge Store',
                icon: Icons.dns_rounded,
                description:
                    'Browse, query, and manage your RDF knowledge graph.\n\n'
                    'Features in development:\n'
                    '\u2022 Triple browser with SPARQL-like filtering\n'
                    '\u2022 Import/export in Turtle and JSON-LD formats\n'
                    '\u2022 Storage statistics and compaction',
              ),
            ),
            SettingsTile(
              icon: Icons.lock_rounded,
              iconColor: KabukTheme.warmAccent,
              title: 'Encryption',
              subtitle: 'Coming soon · Vault-based encryption at rest',
              onTap: () => showComingSoonDialog(
                context,
                title: 'Encryption',
                icon: Icons.lock_rounded,
                description:
                    'Manage vault encryption for your local data store.\n\n'
                    'Features in development:\n'
                    '\u2022 Change encryption passphrase\n'
                    '\u2022 Biometric unlock configuration\n'
                    '\u2022 Key rotation and backup recovery',
              ),
            ),
            const SizedBox(height: KabukTheme.spacingLg),
          ],

          // --- About Section ---
          SettingsSectionHeader(
            icon: Icons.info_outline_rounded,
            title: 'About',
            color: context.kabukTextSecondary,
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          Container(
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            decoration: BoxDecoration(
              color: context.kabukCardColor,
              borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              border: Border.all(color: context.kabukDivider, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: KabukTheme.accentGreen.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.terminal_rounded,
                        color: KabukTheme.accentGreen,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: KabukTheme.spacingSm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kabuk OS',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Agent-centric personal OS shell',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.kabukTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: KabukTheme.spacingSm),
                GestureDetector(
                  onTap: _onVersionTap,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    'v${AppConstants.appVersion} · Tap 7× to toggle developer mode',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.kabukTextTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // --- Developer Section (visible when dev mode is on) ---
          if (devMode) ...[
            const SizedBox(height: KabukTheme.spacingLg),
            const SettingsSectionHeader(
              icon: Icons.bug_report_rounded,
              title: 'Developer',
              color: KabukTheme.warmAccent,
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            SettingsTile(
              icon: Icons.terminal_rounded,
              iconColor: KabukTheme.warmAccent,
              title: 'Developer Tools',
              subtitle: 'Store inspector · Providers · LLM costs',
              trailing: Icon(
                Icons.chevron_right,
                color: context.kabukTextSecondary,
                size: 20,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DevModePage()),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            SettingsTile(
              icon: Icons.toggle_on_rounded,
              iconColor: KabukTheme.warmAccent,
              title: 'Disable Developer Mode',
              subtitle: 'Return to normal mode',
              onTap: () {
                ref.read(devModeProvider.notifier).setEnabled(false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Developer mode disabled'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  static String _providerLabel(LlmProvider provider) => switch (provider) {
    LlmProvider.anthropic => 'Anthropic',
    LlmProvider.openai => 'OpenAI',
    LlmProvider.ollama => 'Ollama',
    LlmProvider.local => 'Local',
  };

  String _relaySubtitle() {
    final nostr = ref.watch(nostrServiceProvider);
    final connected = nostr.connectedRelays.length;
    final total = nostr.relays.length;
    if (total == 0) return 'No relays configured';
    return '$connected/$total connected';
  }

  bool _hasConnectedRelays() {
    final nostr = ref.watch(nostrServiceProvider);
    return nostr.connectedRelays.isNotEmpty;
  }
}

// ---------------------------------------------------------------------------
// Appearance settings section
// ---------------------------------------------------------------------------

/// Inline appearance settings with theme mode and navbar style pickers.
class _AppearanceSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final navStyle = ref.watch(navbarStyleProvider);

    return Column(
      children: [
        // Theme mode
        SettingsTile(
          icon: Icons.brightness_6_rounded,
          iconColor: KabukTheme.purpleAccent,
          title: 'Theme',
          subtitle: switch (themeMode) {
            ThemeMode.dark => 'Dark',
            ThemeMode.light => 'Light',
            ThemeMode.system => 'System',
          },
          trailing: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_rounded, size: 16),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_rounded, size: 16),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.settings_brightness_rounded, size: 16),
              ),
            ],
            selected: {themeMode},
            onSelectionChanged: (set) {
              ref.read(themeModeProvider.notifier).setMode(set.first);
            },
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ),
        const SizedBox(height: KabukTheme.spacingSm),
        // Navbar style
        SettingsTile(
          icon: Icons.dock_rounded,
          iconColor: KabukTheme.purpleAccent,
          title: 'Navigation Bar',
          subtitle: switch (navStyle) {
            NavbarStyle.classic => 'Classic',
            NavbarStyle.compact => 'Compact',
            NavbarStyle.pill => 'Pill',
          },
          trailing: SegmentedButton<NavbarStyle>(
            segments: const [
              ButtonSegment(
                value: NavbarStyle.classic,
                label: Text('Classic', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: NavbarStyle.compact,
                label: Text('Compact', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: NavbarStyle.pill,
                label: Text('Pill', style: TextStyle(fontSize: 11)),
              ),
            ],
            selected: {navStyle},
            onSelectionChanged: (set) {
              ref.read(navbarStyleProvider.notifier).setStyle(set.first);
            },
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
