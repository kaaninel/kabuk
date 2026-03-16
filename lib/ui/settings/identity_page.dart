/// Identity management settings sub-page.
///
/// Shows all Nostr identities with full lifecycle management:
/// list, switch, create, import, rename, export nsec, and delete.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/services/auth.dart';
import 'package:kabuk/ui/settings/settings_shared.dart';
import 'package:kabuk/ui/theme.dart';

/// Identity management sub-page — full identity lifecycle.
class IdentityPage extends ConsumerStatefulWidget {
  /// Creates an [IdentityPage].
  const IdentityPage({super.key});

  @override
  ConsumerState<IdentityPage> createState() => _IdentityPageState();
}

class _IdentityPageState extends ConsumerState<IdentityPage> {
  bool _loading = false;

  Future<void> _generateKeyPair() async {
    setState(() => _loading = true);
    try {
      final auth = ref.read(authServiceProvider);
      await auth.generateKeyPair();
      _invalidateIdentityProviders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New identity created. Back up your nsec!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showImportDialog() async {
    final controller = TextEditingController();
    final nsec = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        title: const Text('Import Identity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste your Nostr private key (nsec) to import an existing identity.',
              style: TextStyle(color: KabukTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'nsec1...',
                hintStyle: const TextStyle(color: KabukTheme.textTertiary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                  borderSide: const BorderSide(color: KabukTheme.divider),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              obscureText: true,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    // Do not dispose controller here — the dialog's dismiss animation
    // may still reference the TextField; let GC reclaim it.
    if (nsec == null || nsec.isEmpty) return;

    setState(() => _loading = true);
    try {
      final auth = ref.read(authServiceProvider);
      final result = await auth.importFromNsec(nsec);
      switch (result) {
        case Success():
          _invalidateIdentityProviders();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Identity imported successfully!'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        case Failure(:final error):
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Import failed: $error'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: KabukTheme.error,
              ),
            );
          }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchTo(UserIdentity identity) async {
    await ref.read(switchIdentityProvider)(identity.id);
    _invalidateIdentityProviders();
  }

  Future<void> _deleteIdentity(UserIdentity identity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        icon: const Icon(Icons.warning_rounded, color: KabukTheme.error, size: 32),
        title: const Text('Delete Identity?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This will permanently delete "${identity.displayName}". '
              'Make sure you have backed up the nsec if you want to '
              'recover this identity later.',
              style: const TextStyle(
                color: KabukTheme.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            if (identity.npub != null)
              Text(
                _truncateNpub(identity.npub!),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: KabukTheme.textTertiary,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: KabukTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final auth = ref.read(authServiceProvider);
    final result = await auth.removeIdentity(identity.id);
    switch (result) {
      case Success():
        _invalidateIdentityProviders();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Identity deleted'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      case Failure(:final error):
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot delete: $error'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: KabukTheme.error,
            ),
          );
        }
    }
  }

  Future<void> _showRenameDialog(UserIdentity identity) async {
    final controller = TextEditingController(text: identity.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        title: const Text('Rename Identity'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Display name',
            hintStyle: const TextStyle(color: KabukTheme.textTertiary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
              borderSide: const BorderSide(color: KabukTheme.divider),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Do not dispose controller here — the dialog's dismiss animation
    // may still reference the TextField; let GC reclaim it.
    if (newName == null || newName.isEmpty) return;

    // Must switch to identity first to rename it, then switch back.
    final auth = ref.read(authServiceProvider);
    final current = await auth.currentUser;
    final wasActive = current?.id == identity.id;
    if (!wasActive) await auth.switchIdentity(identity.id);
    await auth.setDisplayName(newName);
    if (!wasActive && current != null) await auth.switchIdentity(current.id);
    _invalidateIdentityProviders();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Renamed to "$newName"'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _invalidateIdentityProviders() {
    ref.invalidate(currentIdentityProvider);
    ref.invalidate(allIdentitiesProvider);
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label copied to clipboard'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showIdentityDetail(UserIdentity identity, bool isActive) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KabukTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusLg),
        ),
      ),
      builder: (ctx) => _IdentityDetailSheet(
        identity: identity,
        isActive: isActive,
        onCopy: _copyToClipboard,
        onRename: () {
          Navigator.pop(ctx);
          _showRenameDialog(identity);
        },
        onDelete: () {
          Navigator.pop(ctx);
          _deleteIdentity(identity);
        },
        onSwitch: () {
          Navigator.pop(ctx);
          _switchTo(identity);
        },
        onExportNsec: () async {
          final auth = ref.read(authServiceProvider);
          final nsec = await auth.exportNsecFor(identity.id);
          return nsec;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identitiesAsync = ref.watch(allIdentitiesProvider);
    final currentAsync = ref.watch(currentIdentityProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Identities'),
        leading: const BackButton(),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add identity',
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
            ),
            color: KabukTheme.surface,
            onSelected: (value) {
              if (value == 'generate') _generateKeyPair();
              if (value == 'import') _showImportDialog();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'generate',
                child: Row(
                  children: [
                    Icon(Icons.key_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Generate New'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Import nsec'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: identitiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (identities) {
          if (identities.isEmpty) return _buildEmptyState();
          final current = currentAsync.valueOrNull;
          return _buildIdentityList(identities, current);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KabukTheme.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: KabukTheme.warmAccent.withAlpha(25),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.key_rounded,
                color: KabukTheme.warmAccent,
                size: 36,
              ),
            ),
            const SizedBox(height: KabukTheme.spacingLg),
            Text(
              'No Identities',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            const Text(
              'Create a secp256k1 keypair or import an existing nsec '
              'to get started with Nostr.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: KabukTheme.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: KabukTheme.spacingLg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _loading ? null : _generateKeyPair,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Generate'),
                  style: FilledButton.styleFrom(
                    backgroundColor: KabukTheme.warmAccent,
                    foregroundColor: Colors.black,
                  ),
                ),
                const SizedBox(width: KabukTheme.spacingSm),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _showImportDialog,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Import'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentityList(
    List<UserIdentity> identities,
    UserIdentity? current,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingSm,
      ),
      itemCount: identities.length + 1, // +1 for info footer
      itemBuilder: (context, index) {
        if (index == identities.length) return _buildInfoFooter();
        final identity = identities[index];
        final isActive = current?.id == identity.id;
        return _IdentityCard(
          identity: identity,
          isActive: isActive,
          onTap: () => _showIdentityDetail(identity, isActive),
          onSwitch: isActive ? null : () => _switchTo(identity),
        );
      },
    );
  }

  Widget _buildInfoFooter() {
    return Padding(
      padding: const EdgeInsets.only(top: KabukTheme.spacingMd),
      child: Container(
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        decoration: BoxDecoration(
          color: KabukTheme.blueAccent.withAlpha(8),
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          border: Border.all(color: KabukTheme.blueAccent.withAlpha(20)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: KabukTheme.blueAccent.withAlpha(200),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Each identity is a secp256k1 keypair compatible with '
                'Nostr (NIP-01). Tap an identity to view keys, rename, '
                'export, or delete. The active identity is used for '
                'signing messages and DMs.',
                style: TextStyle(
                  color: KabukTheme.blueAccent.withAlpha(200),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _truncateNpub(String npub) {
    if (npub.length <= 24) return npub;
    return '${npub.substring(0, 12)}...${npub.substring(npub.length - 8)}';
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  static Color _colorFromPubKey(String? hex) {
    if (hex == null || hex.length < 6) return KabukTheme.warmAccent;
    final r = int.parse(hex.substring(0, 2), radix: 16);
    final g = int.parse(hex.substring(2, 4), radix: 16);
    final b = int.parse(hex.substring(4, 6), radix: 16);
    return Color.fromRGBO(r, g, b, 1.0);
  }
}

// =============================================================================
// Identity card widget
// =============================================================================

/// A single identity row in the list.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.identity,
    required this.isActive,
    required this.onTap,
    this.onSwitch,
  });

  final UserIdentity identity;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final color = _IdentityPageState._colorFromPubKey(identity.publicKeyHex);
    return Container(
      margin: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
      decoration: BoxDecoration(
        color: KabukTheme.cardColor,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(
          color: isActive
              ? KabukTheme.accentGreen.withAlpha(60)
              : KabukTheme.divider,
          width: isActive ? 1.0 : 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      identity.displayName.isNotEmpty
                          ? identity.displayName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: KabukTheme.spacingSm + 4),
                // Name + npub
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              identity.displayName.isNotEmpty
                                  ? identity.displayName
                                  : 'Unnamed',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: KabukTheme.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: KabukTheme.accentGreen.withAlpha(25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: KabukTheme.accentGreen,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        identity.npub != null
                            ? _IdentityPageState._truncateNpub(identity.npub!)
                            : identity.id.substring(0, 16),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: KabukTheme.textSecondary,
                        ),
                      ),
                      if (identity.createdAt != null)
                        Text(
                          _IdentityPageState._formatDate(identity.createdAt!),
                          style: const TextStyle(
                            fontSize: 10,
                            color: KabukTheme.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                // Switch / active indicator
                if (!isActive && onSwitch != null)
                  IconButton(
                    icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                    color: KabukTheme.textSecondary,
                    tooltip: 'Switch to this identity',
                    onPressed: onSwitch,
                  )
                else if (isActive)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 22,
                    color: KabukTheme.accentGreen,
                  ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: KabukTheme.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Identity detail bottom sheet
// =============================================================================

/// Full detail sheet for a single identity.
class _IdentityDetailSheet extends StatefulWidget {
  const _IdentityDetailSheet({
    required this.identity,
    required this.isActive,
    required this.onCopy,
    required this.onRename,
    required this.onDelete,
    required this.onSwitch,
    required this.onExportNsec,
  });

  final UserIdentity identity;
  final bool isActive;
  final Future<void> Function(String text, String label) onCopy;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onSwitch;
  final Future<String?> Function() onExportNsec;

  @override
  State<_IdentityDetailSheet> createState() => _IdentityDetailSheetState();
}

class _IdentityDetailSheetState extends State<_IdentityDetailSheet> {
  bool _nsecVisible = false;
  String? _nsec;

  Future<void> _revealNsec() async {
    final nsec = await widget.onExportNsec();
    if (nsec != null && mounted) {
      setState(() {
        _nsec = nsec;
        _nsecVisible = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = widget.identity;
    final color = _IdentityPageState._colorFromPubKey(identity.publicKeyHex);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: KabukTheme.spacingMd),
              decoration: BoxDecoration(
                color: KabukTheme.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Identity header
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withAlpha(40),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  identity.displayName.isNotEmpty
                      ? identity.displayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  identity.displayName.isNotEmpty
                      ? identity.displayName
                      : 'Unnamed',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.isActive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: KabukTheme.accentGreen.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: KabukTheme.accentGreen,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (identity.createdAt != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Created ${_IdentityPageState._formatDate(identity.createdAt!)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: KabukTheme.textTertiary,
                  ),
                ),
              ),
            ),
          const SizedBox(height: KabukTheme.spacingLg),

          // Public key section
          const SettingsSectionHeader(
            icon: Icons.public_rounded,
            title: 'Public Key',
            color: KabukTheme.accentGreen,
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          KeyDisplayTile(
            label: 'npub',
            value: identity.npub ?? 'N/A',
            onCopy: identity.npub != null
                ? () => widget.onCopy(identity.npub!, 'npub')
                : null,
          ),
          const SizedBox(height: 6),
          KeyDisplayTile(
            label: 'hex',
            value: identity.publicKeyHex ?? 'N/A',
            onCopy: identity.publicKeyHex != null
                ? () => widget.onCopy(identity.publicKeyHex!, 'Public key hex')
                : null,
          ),
          const SizedBox(height: KabukTheme.spacingLg),

          // Private key section
          const SettingsSectionHeader(
            icon: Icons.lock_rounded,
            title: 'Private Key',
            color: KabukTheme.error,
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          Container(
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            decoration: BoxDecoration(
              color: KabukTheme.error.withAlpha(8),
              borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              border: Border.all(color: KabukTheme.error.withAlpha(25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_rounded,
                      size: 16,
                      color: KabukTheme.error.withAlpha(200),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Never share your nsec with anyone',
                      style: TextStyle(
                        color: KabukTheme.error.withAlpha(200),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KabukTheme.spacingSm),
                if (_nsecVisible && _nsec != null) ...[
                  KeyDisplayTile(
                    label: 'nsec',
                    value: _nsec!,
                    onCopy: () => widget.onCopy(_nsec!, 'nsec'),
                    sensitive: true,
                  ),
                  const SizedBox(height: KabukTheme.spacingSm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _nsecVisible = false;
                        _nsec = null;
                      }),
                      icon: const Icon(Icons.visibility_off_rounded, size: 16),
                      label: const Text('Hide'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KabukTheme.error,
                        side: BorderSide(color: KabukTheme.error.withAlpha(50)),
                      ),
                    ),
                  ),
                ] else
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _revealNsec,
                      icon: const Icon(Icons.visibility_rounded, size: 16),
                      label: const Text('Reveal nsec'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KabukTheme.error,
                        side: BorderSide(color: KabukTheme.error.withAlpha(50)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: KabukTheme.spacingLg),

          // Actions
          const SettingsSectionHeader(
            icon: Icons.tune_rounded,
            title: 'Actions',
            color: KabukTheme.blueAccent,
          ),
          const SizedBox(height: KabukTheme.spacingSm),

          // Rename
          _ActionTile(
            icon: Icons.edit_rounded,
            color: KabukTheme.blueAccent,
            label: 'Rename',
            onTap: widget.onRename,
          ),

          // Switch to (only if not active)
          if (!widget.isActive)
            _ActionTile(
              icon: Icons.swap_horiz_rounded,
              color: KabukTheme.accentGreen,
              label: 'Set as Active',
              onTap: widget.onSwitch,
            ),

          // Delete
          _ActionTile(
            icon: Icons.delete_rounded,
            color: KabukTheme.error,
            label: 'Delete Identity',
            destructive: true,
            onTap: widget.onDelete,
          ),
          const SizedBox(height: KabukTheme.spacingLg),
        ],
      ),
    );
  }
}

/// A simple action row used in the detail sheet.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: destructive
            ? KabukTheme.error.withAlpha(6)
            : KabukTheme.cardColor,
        borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
        border: Border.all(
          color: destructive
              ? KabukTheme.error.withAlpha(20)
              : KabukTheme.divider,
          width: 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KabukTheme.spacingMd,
              vertical: 12,
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: KabukTheme.spacingSm),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: destructive
                          ? KabukTheme.error
                          : KabukTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: KabukTheme.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A monospaced key display tile with copy functionality.
class KeyDisplayTile extends StatelessWidget {
  /// Creates a [KeyDisplayTile].
  const KeyDisplayTile({
    super.key,
    required this.label,
    required this.value,
    this.onCopy,
    this.sensitive = false,
  });

  /// Label text (e.g. 'npub', 'hex').
  final String label;

  /// Key value to display.
  final String value;

  /// Copy callback.
  final VoidCallback? onCopy;

  /// Whether this is a sensitive key.
  final bool sensitive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: sensitive ? KabukTheme.error.withAlpha(5) : KabukTheme.surface,
        borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
        border: Border.all(
          color: sensitive
              ? KabukTheme.error.withAlpha(20)
              : KabukTheme.divider,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: sensitive
                  ? KabukTheme.error.withAlpha(20)
                  : KabukTheme.accentGreen.withAlpha(15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: sensitive ? KabukTheme.error : KabukTheme.accentGreen,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: KabukTheme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onCopy != null)
            IconButton(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 14),
              iconSize: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: KabukTheme.textTertiary,
            ),
        ],
      ),
    );
  }
}
