/// Shared identity quick-switcher avatar widget.
///
/// Shows the current identity's initial in a circle avatar. Tapping
/// opens a popup menu to switch between identities, generate a new
/// one, import an nsec, or navigate to the full identity management
/// page. Designed to be placed in any page's [AppBar.actions] or
/// [AppBar.leading] for a consistent identity switch gesture.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/services/auth.dart';
import 'package:kabuk/ui/settings/identity_page.dart';
import 'package:kabuk/ui/theme.dart';

/// A compact identity avatar with a popup menu for quick switching.
///
/// Place this in any [AppBar] (as `leading` or in `actions`) to give
/// the user one-tap access to identity management from every page.
///
/// ```dart
/// AppBar(
///   actions: [const IdentityQuickSwitcher()],
/// )
/// ```
class IdentityQuickSwitcher extends ConsumerWidget {
  /// Creates an [IdentityQuickSwitcher].
  const IdentityQuickSwitcher({super.key, this.radius = 16});

  /// Radius of the circle avatar.
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identitiesAsync = ref.watch(allIdentitiesProvider);
    final currentAsync = ref.watch(currentIdentityProvider);

    final current = currentAsync.valueOrNull;
    final initials = _initials(current);
    final hasIdentity = current != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: PopupMenuButton<String>(
        offset: const Offset(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
        color: KabukTheme.surface,
        child: Semantics(
          label: 'Switch identity',
          button: true,
          excludeSemantics: true,
          child: CircleAvatar(
          radius: radius,
          backgroundColor: hasIdentity
              ? _colorFromHex(current.publicKeyHex)
              : KabukTheme.accentGreen,
          child: hasIdentity && initials.isNotEmpty
              ? Text(
                  initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: radius * 0.85,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : Icon(
                  Icons.bolt_rounded,
                  color: Colors.white,
                  size: radius,
                ),
          ),
        ),
        itemBuilder: (ctx) {
          final identities = identitiesAsync.valueOrNull ?? [];
          return [
            if (identities.isEmpty)
              const PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  'No identities yet',
                  style: TextStyle(
                    color: KabukTheme.textTertiary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ...identities.map(
                (id) => PopupMenuItem<String>(
                  value: id.id,
                  child: Row(
                    children: [
                      Icon(
                        current?.id == id.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: current?.id == id.id
                            ? KabukTheme.accentGreen
                            : KabukTheme.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: _colorFromHex(id.publicKeyHex),
                        child: Text(
                          _initials(id),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              id.displayName.isNotEmpty
                                  ? id.displayName
                                  : 'Unnamed',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              id.npub != null
                                  ? '${id.npub!.substring(0, 16)}...'
                                  : '${id.id.substring(0, 8)}...',
                              style: const TextStyle(
                                fontSize: 11,
                                color: KabukTheme.textSecondary,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: '__new__',
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Generate New'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: '__import__',
              child: Row(
                children: [
                  Icon(Icons.download_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Import nsec'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: '__manage__',
              child: Row(
                children: [
                  Icon(Icons.manage_accounts_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Manage Identities'),
                ],
              ),
            ),
          ];
        },
        onSelected: (value) async {
          if (value == '__new__') {
            final name = await _showNameDialog(context);
            if (name == null || !context.mounted) return;
            final auth = ref.read(authServiceProvider);
            final created = await auth.generateKeyPair();
            if (name.isNotEmpty) {
              await auth.setDisplayName(name);
            }
            if (!context.mounted) return;
            // Full cascade switch so all providers rebind to the new identity.
            final switcher = ref.read(switchIdentityProvider);
            await switcher(created.id);
          } else if (value == '__import__') {
            if (context.mounted) {
              unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const IdentityPage()),
                ),
              );
            }
          } else if (value == '__manage__') {
            if (context.mounted) {
              unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const IdentityPage()),
                ),
              );
            }
          } else {
            final switcher = ref.read(switchIdentityProvider);
            await switcher(value);
          }
        },
      ),
    );
  }

  /// Shows a dialog to name a new identity before creation.
  ///
  /// Returns the entered name, or `null` if the user cancelled.
  static Future<String?> _showNameDialog(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        title: const Text('New Identity'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter a name (optional)',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  /// Derives a single display initial from a [UserIdentity].
  ///
  /// Always uses the first character of the display name so the avatar
  /// never shows a two-digit hex string (e.g. "52") that users mistake
  /// for a notification count badge. Falls back to a single hex char
  /// only when the display name is empty.
  static String _initials(UserIdentity? identity) {
    if (identity == null) return '';
    if (identity.displayName.isNotEmpty) {
      return identity.displayName[0].toUpperCase();
    }
    final hex = identity.publicKeyHex;
    if ((hex?.length ?? 0) >= 1) {
      return hex![0].toUpperCase();
    }
    return '';
  }

  /// Generates a deterministic colour from a hex public key.
  static Color _colorFromHex(String? hex) {
    if (hex == null || hex.length < 6) return KabukTheme.accentGreen;
    try {
      final r = int.parse(hex.substring(0, 2), radix: 16);
      final g = int.parse(hex.substring(2, 4), radix: 16);
      final b = int.parse(hex.substring(4, 6), radix: 16);
      return Color.fromRGBO(r, g, b, 1.0);
    } on FormatException {
      return KabukTheme.accentGreen;
    }
  }
}
