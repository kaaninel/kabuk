/// Nostr relay management settings sub-page.
///
/// Provides UI for adding, removing, and monitoring Nostr relay connections.
/// Relays are split into DM messaging relays (NIP-17 inbox, essential for
/// reaching 0xchat and other DM-capable clients) and general relays.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/ui/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Relay catalogue — url, label, category, and notes shown in the UI.
// ─────────────────────────────────────────────────────────────────────────────

enum _RelayCategory { dm, general }

class _RelayCatalogEntry {
  const _RelayCatalogEntry({
    required this.url,
    required this.label,
    required this.category,
    this.note = '',
    this.defaultWrite = true,
  });

  final String url;
  final String label;
  final _RelayCategory category;
  final String note;
  final bool defaultWrite;
}

const _relayCatalogue = [
  // --- DM / inbox ---
  _RelayCatalogEntry(
    url: 'wss://relay.0xchat.com',
    label: '0xchat Relay',
    category: _RelayCategory.dm,
    note: 'Native inbox for 0xchat users',
  ),
  _RelayCatalogEntry(
    url: 'wss://inbox.nostr.wine',
    label: 'Nostr Wine Inbox',
    category: _RelayCategory.dm,
    note: 'NIP-17 DM inbox relay',
  ),
  _RelayCatalogEntry(
    url: 'wss://purplepag.es',
    label: 'Purple Pages',
    category: _RelayCategory.dm,
    note: 'NIP-65 relay list metadata (read only)',
    defaultWrite: false,
  ),
  // --- General ---
  _RelayCatalogEntry(
    url: 'wss://relay.damus.io',
    label: 'Damus Relay',
    category: _RelayCategory.general,
    note: 'High-availability public relay',
  ),
  _RelayCatalogEntry(
    url: 'wss://relay.nostr.band',
    label: 'Nostr Band',
    category: _RelayCategory.general,
    note: 'Search and analytics relay (NIP-50)',
  ),
  _RelayCatalogEntry(
    url: 'wss://nos.lol',
    label: 'nos.lol',
    category: _RelayCategory.general,
    note: 'Fast public relay',
  ),
  _RelayCatalogEntry(
    url: 'wss://relay.snort.social',
    label: 'Snort Relay',
    category: _RelayCategory.general,
    note: 'Snort social client relay',
  ),
  _RelayCatalogEntry(
    url: 'wss://nostr.wine',
    label: 'Nostr Wine',
    category: _RelayCategory.general,
    note: 'Paid relay (read only recommended)',
    defaultWrite: false,
  ),
  _RelayCatalogEntry(
    url: 'wss://relay.primal.net',
    label: 'Primal Relay',
    category: _RelayCategory.general,
    note: 'Primal client cache relay',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

/// Page for managing Nostr relay connections.
class RelaySettingsPage extends ConsumerStatefulWidget {
  /// Creates a [RelaySettingsPage].
  const RelaySettingsPage({super.key});

  @override
  ConsumerState<RelaySettingsPage> createState() => _RelaySettingsPageState();
}

class _RelaySettingsPageState extends ConsumerState<RelaySettingsPage> {
  final _urlController = TextEditingController();
  bool _read = true;
  bool _write = true;
  bool _adding = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _addRelay({
    required String url,
    bool read = true,
    bool write = true,
  }) async {
    setState(() => _adding = true);
    try {
      final nostr = ref.read(nostrServiceProvider);
      await nostr.addRelay(RelayConfig(url: url, read: read, write: write));
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _addManual() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !url.startsWith('wss://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid relay URL (wss://...)'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await _addRelay(url: url, read: _read, write: _write);
    if (mounted) _urlController.clear();
  }

  Future<void> _addAllDmRelays(Set<String> existing) async {
    final nostr = ref.read(nostrServiceProvider);
    for (final entry in _relayCatalogue.where(
      (e) => e.category == _RelayCategory.dm && !existing.contains(e.url),
    )) {
      await nostr.addRelay(
        RelayConfig(url: entry.url, read: true, write: entry.defaultWrite),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _removeRelay(String url) async {
    final nostr = ref.read(nostrServiceProvider);
    await nostr.removeRelay(url);
    if (mounted) setState(() {});
  }

  Future<void> _reconnectRelay(String url) async {
    final nostr = ref.read(nostrServiceProvider);
    await nostr.disconnectRelay(url);
    await nostr.connectRelay(url);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final nostr = ref.watch(nostrServiceProvider);
    final relays = nostr.relays;
    final connected = nostr.connectedRelays.toSet();
    final configuredUrls = relays.map((r) => r.url).toSet();

    // Split relays into DM vs general categories.
    final dmCatalogUrls = _relayCatalogue
        .where((e) => e.category == _RelayCategory.dm)
        .map((e) => e.url)
        .toSet();
    final configuredDmRelays = relays
        .where((r) => dmCatalogUrls.contains(r.url))
        .toList();
    final missingDmRelays = _relayCatalogue
        .where(
          (e) =>
              e.category == _RelayCategory.dm &&
              !configuredUrls.contains(e.url),
        )
        .toList();
    final hasMissingDmRelays = missingDmRelays.isNotEmpty;

    // Custom (not in catalogue) relays the user added manually.
    final catalogueUrls = _relayCatalogue.map((e) => e.url).toSet();
    final customRelays = relays
        .where((r) => !catalogueUrls.contains(r.url))
        .toList();

    // General catalogue relays that are configured.
    final configuredGeneralRelays = relays
        .where(
          (r) =>
              !dmCatalogUrls.contains(r.url) && catalogueUrls.contains(r.url),
        )
        .toList();

    // General catalogue suggestions not yet added.
    final unaddedGeneral = _relayCatalogue
        .where(
          (e) =>
              e.category == _RelayCategory.general &&
              !configuredUrls.contains(e.url),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nostr Relays'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: KabukTheme.spacingMd),
            child: Chip(
              label: Text(
                '${connected.length}/${relays.length}',
                style: const TextStyle(
                  color: KabukTheme.accentGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              side: BorderSide(color: context.kabukDivider),
              avatar: Icon(
                Icons.cell_tower_rounded,
                size: 16,
                color: connected.isNotEmpty
                    ? KabukTheme.success
                    : context.kabukTextSecondary,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        children: [
          // ─── DM Relay Status Banner ───────────────────────────────────────
          if (hasMissingDmRelays)
            _DmRelayBanner(
              missingCount: missingDmRelays.length,
              onAddAll: _adding ? null : () => _addAllDmRelays(configuredUrls),
            )
          else
            _dmReadyBanner(context),
          const SizedBox(height: KabukTheme.spacingLg),

          // ─── DM / Inbox Relays ────────────────────────────────────────────
          const _SectionHeader(
            icon: Icons.mark_email_unread_rounded,
            label: 'DM — Messaging Relays',
            color: KabukTheme.nostrPurple,
          ),
          const SizedBox(height: KabukTheme.spacingXs),
          Padding(
            padding: EdgeInsets.only(bottom: KabukTheme.spacingSm),
            child: Text(
              'Required for encrypted DMs (NIP-17) to reach 0xchat and other '
              'clients. Gift-wrapped messages are sent directly to these relays.',
              style: TextStyle(
                fontSize: 12,
                color: context.kabukTextSecondary,
                height: 1.4,
              ),
            ),
          ),

          // Configured DM relays.
          if (configuredDmRelays.isNotEmpty)
            ...configuredDmRelays.map(
              (relay) => _RelayTile(
                relay: relay,
                isConnected: connected.contains(relay.url),
                label: _labelFor(relay.url),
                note: _noteFor(relay.url),
                badgeColor: KabukTheme.nostrPurple,
                onReconnect: () => _reconnectRelay(relay.url),
                onRemove: () => _removeRelay(relay.url),
              ),
            ),

          // Missing DM relays as one-tap add chips.
          if (missingDmRelays.isNotEmpty) ...[
            const SizedBox(height: KabukTheme.spacingSm),
            Wrap(
              spacing: KabukTheme.spacingSm,
              runSpacing: KabukTheme.spacingSm,
              children: missingDmRelays.map((entry) {
                return ActionChip(
                  avatar: const Icon(
                    Icons.add,
                    size: 14,
                    color: KabukTheme.nostrPurple,
                  ),
                  label: Text(
                    entry.label,
                    style: const TextStyle(fontSize: 12),
                  ),
                  tooltip: entry.note,
                  onPressed: _adding
                      ? null
                      : () => _addRelay(
                          url: entry.url,
                          read: true,
                          write: entry.defaultWrite,
                        ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: KabukTheme.spacingLg),

          // ─── General Relays ───────────────────────────────────────────────
          if (configuredGeneralRelays.isNotEmpty ||
              customRelays.isNotEmpty) ...[
            const _SectionHeader(
              icon: Icons.wifi_rounded,
              label: 'General Relays',
              color: KabukTheme.warmAccent,
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            ...configuredGeneralRelays.map(
              (relay) => _RelayTile(
                relay: relay,
                isConnected: connected.contains(relay.url),
                label: _labelFor(relay.url),
                note: _noteFor(relay.url),
                badgeColor: KabukTheme.warmAccent,
                onReconnect: () => _reconnectRelay(relay.url),
                onRemove: () => _removeRelay(relay.url),
              ),
            ),
            ...customRelays.map(
              (relay) => _RelayTile(
                relay: relay,
                isConnected: connected.contains(relay.url),
                label: relay.url.replaceFirst('wss://', ''),
                note: 'Custom',
                badgeColor: context.kabukTextSecondary,
                onReconnect: () => _reconnectRelay(relay.url),
                onRemove: () => _removeRelay(relay.url),
              ),
            ),
            SizedBox(height: KabukTheme.spacingLg),
          ],

          // ─── Suggested General Relays ─────────────────────────────────────
          if (unaddedGeneral.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.add_circle_outline_rounded,
              label: 'Suggested General Relays',
              color: context.kabukTextSecondary,
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            Wrap(
              spacing: KabukTheme.spacingSm,
              runSpacing: KabukTheme.spacingSm,
              children: unaddedGeneral.map((entry) {
                return ActionChip(
                  avatar: const Icon(Icons.add, size: 14),
                  label: Text(
                    entry.label,
                    style: const TextStyle(fontSize: 12),
                  ),
                  tooltip: entry.note,
                  onPressed: _adding
                      ? null
                      : () => _addRelay(
                          url: entry.url,
                          read: true,
                          write: entry.defaultWrite,
                        ),
                );
              }).toList(),
            ),
            SizedBox(height: KabukTheme.spacingLg),
          ],

          // ─── Add Custom Relay ─────────────────────────────────────────────
          _SectionHeader(
            icon: Icons.add_link_rounded,
            label: 'Add Custom Relay',
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
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    hintText: 'wss://relay.example.com',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: KabukTheme.spacingSm,
                      vertical: KabukTheme.spacingSm,
                    ),
                  ),
                ),
                const SizedBox(height: KabukTheme.spacingSm),
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: _read,
                        onChanged: (v) => setState(() => _read = v ?? true),
                        title: const Text(
                          'Read',
                          style: TextStyle(fontSize: 13),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: _write,
                        onChanged: (v) => setState(() => _write = v ?? true),
                        title: const Text(
                          'Write',
                          style: TextStyle(fontSize: 13),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KabukTheme.spacingSm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _adding ? null : _addManual,
                    icon: _adding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add, size: 18),
                    label: Text(_adding ? 'Connecting...' : 'Add Relay'),
                    style: FilledButton.styleFrom(
                      backgroundColor: KabukTheme.warmAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  static String _labelFor(String url) {
    for (final entry in _relayCatalogue) {
      if (entry.url == url) return entry.label;
    }
    return url.replaceFirst('wss://', '');
  }

  static String _noteFor(String url) {
    for (final entry in _relayCatalogue) {
      if (entry.url == url) return entry.note;
    }
    return '';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DM status banners
// ─────────────────────────────────────────────────────────────────────────────

class _DmRelayBanner extends StatelessWidget {
  const _DmRelayBanner({required this.missingCount, required this.onAddAll});

  final int missingCount;
  final VoidCallback? onAddAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: BoxDecoration(
        color: KabukTheme.nostrPurple.withAlpha(20),
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(
          color: KabukTheme.nostrPurple.withAlpha(80),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: KabukTheme.nostrPurple,
            size: 20,
          ),
          const SizedBox(width: KabukTheme.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DM relays missing',
                  style: TextStyle(
                    color: KabukTheme.nostrPurple,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$missingCount inbox relay${missingCount > 1 ? 's' : ''} not '
                  'configured. Messages to 0xchat and other NIP-17 clients '
                  'may not be delivered.',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.kabukTextSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: KabukTheme.spacingSm),
                FilledButton.icon(
                  onPressed: onAddAll,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add All DM Relays'),
                  style: FilledButton.styleFrom(
                    backgroundColor: KabukTheme.nostrPurple,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _dmReadyBanner(BuildContext context) => Container(
  padding: const EdgeInsets.symmetric(
    horizontal: KabukTheme.spacingMd,
    vertical: KabukTheme.spacingSm,
  ),
  decoration: BoxDecoration(
    color: KabukTheme.success.withAlpha(15),
    borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
    border: Border.all(color: KabukTheme.success.withAlpha(60), width: 1),
  ),
  child: Row(
    children: [
      Icon(Icons.check_circle_rounded, color: KabukTheme.success, size: 16),
      SizedBox(width: KabukTheme.spacingSm),
      Expanded(
        child: Text(
          'DM relays configured — encrypted messages can reach 0xchat and '
          'other NIP-17 clients.',
          style: TextStyle(
            fontSize: 12,
            color: context.kabukTextSecondary,
            height: 1.4,
          ),
        ),
      ),
    ],
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Relay tile
// ─────────────────────────────────────────────────────────────────────────────

class _RelayTile extends StatelessWidget {
  const _RelayTile({
    required this.relay,
    required this.isConnected,
    required this.label,
    required this.note,
    required this.badgeColor,
    required this.onReconnect,
    required this.onRemove,
  });

  final RelayConfig relay;
  final bool isConnected;
  final String label;
  final String note;
  final Color badgeColor;
  final VoidCallback onReconnect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
      decoration: BoxDecoration(
        color: context.kabukCardColor,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(
          color: isConnected
              ? KabukTheme.success.withAlpha(80)
              : context.kabukDivider,
          width: 0.5,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
          color: isConnected ? KabukTheme.success : KabukTheme.error,
          size: 20,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            _badge(
              [if (relay.read) 'r', if (relay.write) 'w'].join('+'),
              badgeColor,
            ),
          ],
        ),
        subtitle: note.isNotEmpty
            ? Text(note, style: const TextStyle(fontSize: 11))
            : null,
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 18),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'reconnect',
              child: Row(
                children: [
                  Icon(Icons.refresh, size: 16),
                  SizedBox(width: 8),
                  Text('Reconnect'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'remove',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 16, color: KabukTheme.error),
                  SizedBox(width: 8),
                  Text('Remove', style: TextStyle(color: KabukTheme.error)),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            switch (value) {
              case 'reconnect':
                onReconnect();
              case 'remove':
                onRemove();
            }
          },
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: color.withAlpha(25),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        color: color,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
  );
}
