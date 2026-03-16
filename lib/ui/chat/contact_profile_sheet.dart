/// Contact profile — full Nostr profile with public notes feed.
///
/// Shows kind-0 profile metadata (avatar, banner, bio, NIP-05) and a
/// scrollable list of the contact's recent public notes (kind 1).
/// Accessible by tapping the contact name/avatar in any chat header.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/ui/theme.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Full-screen contact profile.
///
/// Push this route when the user taps a contact's name or avatar.
class ContactProfileSheet extends ConsumerWidget {
  /// Creates a [ContactProfileSheet].
  const ContactProfileSheet({
    required this.pubkeyHex,
    required this.displayName,
    super.key,
  });

  /// The contact's Nostr public key (64-char hex).
  final String pubkeyHex;

  /// Fallback display name shown while the profile loads.
  final String displayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(nostrProfileProvider(pubkeyHex));
    final notesAsync = ref.watch(contactPublicNotesProvider(pubkeyHex));

    final profile = profileAsync.valueOrNull;
    final name = profile?.displayName ?? displayName;

    return Scaffold(
      backgroundColor: KabukTheme.background,
      body: CustomScrollView(
        slivers: [
          // ── Banner + app bar ──────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: KabukTheme.surface,
            leading: const BackButton(),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 20),
                tooltip: 'Copy public key',
                onPressed: () => _copyPubkey(context),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _BannerBackground(
                pubkeyHex: pubkeyHex,
                bannerUrl: profile?.banner,
              ),
            ),
          ),

          // ── Profile header ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _ProfileHeader(
              pubkeyHex: pubkeyHex,
              name: name,
              about: profile?.about,
              pictureUrl: profile?.picture,
              nip05: profile?.nip05,
              onCopyKey: () => _copyPubkey(context),
            ),
          ),

          // ── Notes section header ──────────────────────────────────────────
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                KabukTheme.spacingMd,
                KabukTheme.spacingMd,
                KabukTheme.spacingMd,
                KabukTheme.spacingSm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.article_outlined,
                    size: 14,
                    color: KabukTheme.textSecondary,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Notes',
                    style: TextStyle(
                      color: KabukTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Notes feed ────────────────────────────────────────────────────
          notesAsync.when(
            data: (notes) {
              if (notes.isEmpty) {
                return const SliverToBoxAdapter(child: _EmptyNotes());
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _NoteTile(event: notes[index], profile: profile),
                  childCount: notes.length,
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(KabukTheme.spacingXl),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
            error: (_, _) => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(KabukTheme.spacingMd),
                child: Center(
                  child: Text(
                    'Could not load notes',
                    style: TextStyle(
                      color: KabukTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: KabukTheme.spacingXl),
          ),
        ],
      ),
    );
  }

  void _copyPubkey(BuildContext context) {
    Clipboard.setData(ClipboardData(text: pubkeyHex));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Public key copied'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Banner background
// ---------------------------------------------------------------------------

class _BannerBackground extends StatelessWidget {
  const _BannerBackground({required this.pubkeyHex, required this.bannerUrl});

  final String pubkeyHex;
  final String? bannerUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (bannerUrl != null)
          Image.network(
            bannerUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _ColorBanner(pubkeyHex: pubkeyHex),
          )
        else
          _ColorBanner(pubkeyHex: pubkeyHex),
        // Bottom gradient fade into background
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 80,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  KabukTheme.background.withAlpha(230),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ColorBanner extends StatelessWidget {
  const _ColorBanner({required this.pubkeyHex});

  final String pubkeyHex;

  @override
  Widget build(BuildContext context) {
    final color = _pubkeyColor(pubkeyHex);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withAlpha(140)],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile header (avatar, name, bio, key badge)
// ---------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.pubkeyHex,
    required this.name,
    required this.about,
    required this.pictureUrl,
    required this.nip05,
    required this.onCopyKey,
  });

  final String pubkeyHex;
  final String name;
  final String? about;
  final String? pictureUrl;
  final String? nip05;
  final VoidCallback onCopyKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KabukTheme.spacingMd,
        0,
        KabukTheme.spacingMd,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar overlapping banner
          Transform.translate(
            offset: const Offset(0, -36),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Profile picture
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: KabukTheme.background, width: 3),
                  ),
                  child: CircleAvatar(
                    radius: 38,
                    backgroundColor: _pubkeyColor(pubkeyHex),
                    backgroundImage: pictureUrl != null
                        ? NetworkImage(pictureUrl!)
                        : null,
                    onBackgroundImageError: pictureUrl != null
                        ? (_, _) {}
                        : null,
                    child: pictureUrl == null
                        ? Text(
                            _initials(name),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),

          // Name row (float up under avatar translate offset)
          Transform.translate(
            offset: const Offset(0, -28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: KabukTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (nip05 != null)
                      Tooltip(
                        message: 'Verified: $nip05',
                        child: const Icon(
                          Icons.verified_rounded,
                          color: KabukTheme.accentGreen,
                          size: 18,
                        ),
                      ),
                  ],
                ),
                if (nip05 != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    nip05!,
                    style: const TextStyle(
                      color: KabukTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: KabukTheme.spacingSm),
                if (about != null && about!.isNotEmpty) ...[
                  Text(
                    about!,
                    style: const TextStyle(
                      color: KabukTheme.textPrimary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: KabukTheme.spacingSm),
                ],

                // Copyable public key badge
                GestureDetector(
                  onTap: onCopyKey,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: KabukTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.key_rounded,
                          size: 11,
                          color: KabukTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${pubkeyHex.substring(0, 8)}…'
                          '${pubkeyHex.substring(pubkeyHex.length - 8)}',
                          style: const TextStyle(
                            color: KabukTheme.textSecondary,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.copy_rounded,
                          size: 10,
                          color: KabukTheme.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: KabukTheme.spacingMd),
                const Divider(color: KabukTheme.divider, height: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Note tile
// ---------------------------------------------------------------------------

/// A single public note card in the feed.
class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.event, required this.profile});

  final NostrEvent event;
  final NostrProfile? profile;

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000);
    final name = profile?.displayName ?? '${event.pubkey.substring(0, 8)}…';
    final pictureUrl = profile?.picture;
    final avatarColor = _pubkeyColor(event.pubkey);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        KabukTheme.spacingMd,
        0,
        KabukTheme.spacingMd,
        KabukTheme.spacingSm,
      ),
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: BoxDecoration(
        color: KabukTheme.cardColor,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: KabukTheme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: avatarColor,
                backgroundImage: pictureUrl != null
                    ? NetworkImage(pictureUrl)
                    : null,
                onBackgroundImageError: pictureUrl != null ? (_, _) {} : null,
                child: pictureUrl == null
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: KabukTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatTime(time),
                style: const TextStyle(
                  color: KabukTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            event.content,
            style: const TextStyle(
              color: KabukTheme.textPrimary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${date.month}/${date.day}';
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(KabukTheme.spacingXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.article_outlined,
            size: 36,
            color: KabukTheme.textSecondary.withAlpha(80),
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          const Text(
            'No public notes yet',
            style: TextStyle(color: KabukTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Deterministic color from pubkey hash.
Color _pubkeyColor(String pubkey) {
  const palette = [
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
    Color(0xFF42A5F5),
    Color(0xFF66BB6A),
  ];
  if (pubkey.isEmpty) return palette[0];
  final hash = pubkey.codeUnits.fold<int>(0, (h, c) => h + c);
  return palette[hash % palette.length];
}

/// Two-letter initials from a display name.
String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
  return name.isNotEmpty ? name[0].toUpperCase() : '?';
}
