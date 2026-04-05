/// My Profile page — displays the active user's Nostr identity with a
/// public-key QR code and one-tap copy actions.
///
/// Shows:
///  • Banner + avatar (from kind-0 metadata, or gradient/initial fallback)
///  • Display name and edit dialog
///  • Bio / about text
///  • NIP-05 identifier
///  • npub1 QR code (full-screen zoomable sheet on tap)
///  • Copy buttons for npub and hex pubkey
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/services/auth.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/ui/explore/nostr_providers.dart';
import 'package:kabuk/ui/shared/feed_image.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:qr_flutter/qr_flutter.dart';

// =============================================================================
// My Profile Page
// =============================================================================

/// Displays the current user's profile with a public-key QR code.
class MyProfilePage extends ConsumerWidget {
  /// Creates a [MyProfilePage].
  const MyProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(currentIdentityProvider);

    return identityAsync.when(
      data: (identity) {
        if (identity == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('My Profile')),
            body: Center(
              child: Text(
                'No identity found.',
                style: TextStyle(color: context.kabukTextSecondary),
              ),
            ),
          );
        }
        return _ProfileBody(identity: identity);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('My Profile')),
        body: const Center(
          child: CircularProgressIndicator(color: KabukTheme.primaryGreen),
        ),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('My Profile')),
        body: Center(
          child: Text(
            'Error: $e',
            style: const TextStyle(color: KabukTheme.error),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Profile Body
// =============================================================================

class _ProfileBody extends ConsumerStatefulWidget {
  const _ProfileBody({required this.identity});

  final UserIdentity identity;

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  @override
  Widget build(BuildContext context) {
    final pubkeyHex = widget.identity.publicKeyHex ?? widget.identity.id;
    final profileAsync = ref.watch(profileForPubkeyProvider(pubkeyHex));
    final nostrProfile = profileAsync.valueOrNull;

    final npub = widget.identity.npub ?? '';
    final displayName = nostrProfile?.name.isNotEmpty == true
        ? nostrProfile!.name
        : widget.identity.displayName;

    return Scaffold(
      backgroundColor: context.kabukBackground,
      body: CustomScrollView(
        slivers: [
          // ---- Banner + AppBar ----
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: context.kabukSurface,
            foregroundColor: context.kabukTextPrimary,
            title: const Text('My Profile'),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit profile',
                onPressed: () => _showEditDialog(context, nostrProfile),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: nostrProfile?.banner != null
                  ? FeedImage(
                      imageUrl: nostrProfile!.banner!,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            KabukTheme.primaryGreen,
                            KabukTheme.purpleAccent,
                          ],
                        ),
                      ),
                    ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(KabukTheme.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- Avatar + name row ----
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _Avatar(
                        picture: nostrProfile?.picture,
                        name: displayName,
                        radius: 40,
                      ),
                      const SizedBox(width: KabukTheme.spacingMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: context.kabukTextPrimary,
                              ),
                            ),
                            if (nostrProfile?.nip05 != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: KabukTheme.spacingXs,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.verified_rounded,
                                      size: 14,
                                      color: KabukTheme.primaryGreen,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        nostrProfile!.nip05!,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: KabukTheme.primaryGreen,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: KabukTheme.spacingMd),

                  // ---- Bio ----
                  if (nostrProfile?.about?.isNotEmpty == true) ...[
                    Text(
                      nostrProfile!.about!,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.kabukTextSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: KabukTheme.spacingMd),
                  ],

                  Divider(color: context.kabukDivider),
                  const SizedBox(height: KabukTheme.spacingMd),

                  // ---- QR Code ----
                  if (npub.isNotEmpty) ...[
                    Text(
                      'Public Key',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.kabukTextSecondary,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: KabukTheme.spacingSm),
                    _QrCard(npub: npub),
                    const SizedBox(height: KabukTheme.spacingMd),
                  ],

                  // ---- Copy buttons ----
                  if (npub.isNotEmpty)
                    _CopyTile(
                      label: 'npub',
                      value: npub,
                      icon: Icons.person_outline_rounded,
                    ),
                  if (pubkeyHex.isNotEmpty)
                    _CopyTile(
                      label: 'hex pubkey',
                      value: pubkeyHex,
                      icon: Icons.tag_rounded,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(
    BuildContext context,
    NostrProfile? profile,
  ) async {
    final nameCtrl = TextEditingController(
      text: profile?.name ?? widget.identity.displayName,
    );
    final aboutCtrl = TextEditingController(text: profile?.about ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.kabukSurface,
        title: const Text('Edit Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Display name',
                hintText: 'Your name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                  borderSide: BorderSide(color: context.kabukDivider),
                ),
              ),
              autofocus: true,
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            TextField(
              controller: aboutCtrl,
              decoration: InputDecoration(
                labelText: 'Bio',
                hintText: 'Tell the world about yourself',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                  borderSide: BorderSide(color: context.kabukDivider),
                ),
              ),
              maxLines: 3,
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
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final nostr = ref.read(nostrServiceProvider);
    final auth = ref.read(authServiceProvider);
    await auth.setDisplayName(nameCtrl.text.trim());
    await nostr.publishMetadata(
      name: nameCtrl.text.trim(),
      about: aboutCtrl.text.trim(),
    );

    ref.invalidate(currentIdentityProvider);
    final pubkeyHex = widget.identity.publicKeyHex ?? widget.identity.id;
    ref.invalidate(profileForPubkeyProvider(pubkeyHex));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// =============================================================================
// QR Card
// =============================================================================

/// A tappable card that shows the npub as a QR code.
///
/// Tapping expands the QR into a fullscreen bottom sheet for easy scanning.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.npub});

  final String npub;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFullScreen(context),
      child: Container(
        decoration: BoxDecoration(
          color: context.kabukSurfaceElevated,
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          border: Border.all(color: context.kabukDivider),
        ),
        padding: const EdgeInsets.all(KabukTheme.spacingLg),
        child: Column(
          children: [
            Center(
              child: QrImageView(
                data: npub,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                padding: const EdgeInsets.all(12),
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: context.kabukBackground,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: context.kabukBackground,
                ),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            Text(
              '${npub.substring(0, 16)}…${npub.substring(npub.length - 8)}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: context.kabukTextTertiary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.zoom_out_map_rounded,
                  size: 13,
                  color: context.kabukTextTertiary,
                ),
                SizedBox(width: 4),
                Text(
                  'Tap to expand',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.kabukTextTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showFullScreen(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.kabukSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusLg),
        ),
      ),
      builder: (ctx) => _QrFullScreen(npub: npub),
    );
  }
}

// =============================================================================
// Full-Screen QR Sheet
// =============================================================================

class _QrFullScreen extends StatelessWidget {
  const _QrFullScreen({required this.npub});

  final String npub;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final qrSize = (size.width - 80).clamp(200.0, 380.0);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingLg,
          vertical: KabukTheme.spacingXl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.kabukDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingLg),
            Text(
              'Scan to follow / contact',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.kabukTextPrimary,
              ),
            ),
            const SizedBox(height: KabukTheme.spacingLg),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              ),
              padding: const EdgeInsets.all(16),
              child: QrImageView(
                data: npub,
                version: QrVersions.auto,
                size: qrSize,
                backgroundColor: Colors.white,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: context.kabukBackground,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: context.kabukBackground,
                ),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingLg),
            SelectableText(
              npub,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: context.kabukTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: npub));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('npub copied to clipboard'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                Navigator.pop(context);
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy npub'),
              style: FilledButton.styleFrom(
                backgroundColor: KabukTheme.primaryGreen,
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Copy Tile
// =============================================================================

/// A tile that shows a truncated key value and copies the full value on tap.
class _CopyTile extends StatelessWidget {
  const _CopyTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final short = value.length > 24
        ? '${value.substring(0, 12)}…${value.substring(value.length - 8)}'
        : value;

    return Padding(
      padding: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$label copied'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: KabukTheme.spacingMd,
            vertical: KabukTheme.spacingSm,
          ),
          decoration: BoxDecoration(
            color: context.kabukSurfaceVariant,
            borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
            border: Border.all(color: context.kabukDivider),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: context.kabukTextSecondary),
              const SizedBox(width: KabukTheme.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.kabukTextTertiary,
                        letterSpacing: 0.6,
                      ),
                    ),
                    Text(
                      short,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: context.kabukTextPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.copy_rounded,
                size: 16,
                color: context.kabukTextTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Avatar
// =============================================================================

/// Circular avatar with picture URL or initial letter fallback.
class _Avatar extends StatelessWidget {
  const _Avatar({this.picture, required this.name, required this.radius});

  final String? picture;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (picture != null && picture!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: context.kabukSurfaceVariant,
        child: ClipOval(
          child: FeedImage(
            imageUrl: picture!,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    final initial = name.isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    return CircleAvatar(
      radius: radius,
      backgroundColor: KabukTheme.primaryGreen,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.75,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
