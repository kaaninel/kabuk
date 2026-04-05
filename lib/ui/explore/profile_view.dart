/// User profile page — displays a Nostr user's profile and notes.
///
/// Shows banner, avatar, name, bio, NIP-05, follower info,
/// follow/unfollow action, and a list of the user's notes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/services/nostr_utils.dart';
import 'package:kabuk/ui/explore/nostr_providers.dart';
import 'package:kabuk/ui/explore/thread_view.dart';
import 'package:kabuk/ui/shared/feed_image.dart';
import 'package:kabuk/ui/shared/time_format.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// Providers
// =============================================================================

/// Fetches notes authored by a given pubkey.
final userNotesProvider = FutureProvider.family<List<NostrEvent>, String>((
  ref,
  pubkey,
) async {
  final nostr = ref.watch(nostrServiceProvider);
  final notes = await collectNostrEvents(
    nostr.subscribe([
      NostrFilter(authors: [pubkey], kinds: [NostrKind.textNote], limit: 50),
    ]),
    timeout: const Duration(seconds: 8),
  );

  // Most recent first.
  notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return notes;
});

/// Checks whether the current user follows a given pubkey.
final isFollowingProvider = FutureProvider.family<bool, String>((
  ref,
  pubkey,
) async {
  final contacts = await ref.watch(nostrContactsProvider.future);
  return contacts.contains(pubkey);
});

/// NIP-05 verification result for a pubkey + identifier pair.
final nip05VerifiedProvider =
    FutureProvider.family<bool, ({String nip05, String pubkey})>((
      ref,
      params,
    ) async {
      final nostr = ref.watch(nostrServiceProvider);
      return nostr.verifyNip05(params.nip05, params.pubkey);
    });

// =============================================================================
// Profile View
// =============================================================================

/// Displays a Nostr user's profile page.
///
/// Navigate by pushing:
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => ProfileView(pubkey: 'hex_pubkey'),
/// ));
/// ```
class ProfileView extends ConsumerStatefulWidget {
  /// Creates a [ProfileView] for the given user [pubkey].
  const ProfileView({required this.pubkey, super.key});

  /// The user's public key (hex).
  final String pubkey;

  @override
  ConsumerState<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<ProfileView> {
  bool _isToggling = false;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileForPubkeyProvider(widget.pubkey));
    final notesAsync = ref.watch(userNotesProvider(widget.pubkey));
    final isFollowingAsync = ref.watch(isFollowingProvider(widget.pubkey));

    return Scaffold(
      backgroundColor: context.kabukBackground,
      body: profileAsync.when(
        data: (profile) =>
            _buildProfile(context, profile, notesAsync, isFollowingAsync),
        loading: () => const Center(
          child: CircularProgressIndicator(color: KabukTheme.primaryGreen),
        ),
        error: (e, _) => Center(
          child: Text(
            'Error: $e',
            style: const TextStyle(color: KabukTheme.error),
          ),
        ),
      ),
    );
  }

  Widget _buildProfile(
    BuildContext context,
    NostrProfile? profile,
    AsyncValue<List<NostrEvent>> notesAsync,
    AsyncValue<bool> isFollowingAsync,
  ) {
    final name = profile?.displayName ?? '${widget.pubkey.substring(0, 8)}...';
    final topPadding = MediaQuery.of(context).padding.top;

    return CustomScrollView(
      slivers: [
        // --- Merged header (back + avatar + name + follow) ---
        SliverToBoxAdapter(
          child: Container(
            padding: EdgeInsets.fromLTRB(8, topPadding + 8, 12, 12),
            decoration: BoxDecoration(
              color: context.kabukSurface,
              border: Border(
                bottom: BorderSide(color: context.kabukDivider, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36, minHeight: 36,
                  ),
                ),
                const SizedBox(width: 4),
                // Avatar.
                profile?.picture != null
                    ? ClipOval(
                        child: FeedImage(
                          imageUrl: profile!.picture!,
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                        ),
                      )
                    : CircleAvatar(
                        radius: 18,
                        backgroundColor: context.kabukSurfaceVariant,
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontSize: 16,
                            color: context.kabukTextPrimary,
                          ),
                        ),
                      ),
                const SizedBox(width: 10),
                // Name + NIP-05.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: context.kabukTextPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (profile?.nip05 != null)
                        Text(
                          profile!.nip05!,
                          style: TextStyle(
                            color: KabukTheme.primaryGreen,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      else
                        Text(
                          '${widget.pubkey.substring(0, 12)}…',
                          style: TextStyle(
                            color: context.kabukTextTertiary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Follow button.
                isFollowingAsync.when(
                  data: (following) => _FollowButton(
                    isFollowing: following,
                    isLoading: _isToggling,
                    onPressed: () => _toggleFollow(following),
                  ),
                  loading: () => const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: KabukTheme.primaryGreen,
                    ),
                  ),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),

        // --- Profile details (bio, lightning address) ---
        if ((profile?.about != null && profile!.about!.isNotEmpty) ||
            profile?.lud16 != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (profile?.about != null && profile!.about!.isNotEmpty)
                    Text(
                      profile.about!,
                      style: TextStyle(
                        color: context.kabukTextSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  if (profile?.lud16 != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.bolt_rounded,
                          size: 14,
                          color: Color(0xFFFFC107),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          profile!.lud16!,
                          style: TextStyle(
                            color: context.kabukTextTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Divider(color: context.kabukDivider, height: 1),
                ],
              ),
            ),
          ),

        // --- Notes header ---
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Notes',
              style: TextStyle(
                color: context.kabukTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        // --- Notes list ---
        notesAsync.when(
          data: (notes) {
            if (notes.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'No notes yet',
                    style: TextStyle(color: context.kabukTextSecondary),
                  ),
                ),
              );
            }
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _UserNoteCard(
                  event: notes[index],
                  authorName: name,
                  authorPicture: profile?.picture,
                ),
                childCount: notes.length,
              ),
            );
          },
          loading: () => const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: CircularProgressIndicator(color: KabukTheme.primaryGreen),
            ),
          ),
          error: (e, _) => SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'Error: $e',
                style: const TextStyle(color: KabukTheme.error),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleFollow(bool currentlyFollowing) async {
    if (_isToggling) return;
    setState(() => _isToggling = true);

    try {
      final nostr = ref.read(nostrServiceProvider);
      final contacts = await nostr.fetchContactList();

      final updated = currentlyFollowing
          ? (contacts..remove(widget.pubkey))
          : (contacts..add(widget.pubkey));

      await nostr.publishContactList(updated);

      // Refresh follow state.
      ref.invalidate(isFollowingProvider(widget.pubkey));
      ref.invalidate(nostrContactsProvider);
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }
}

// =============================================================================
// Sub-widgets
// =============================================================================

/// Follow / Unfollow button with loading state.
class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.isFollowing,
    required this.isLoading,
    required this.onPressed,
  });

  final bool isFollowing;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: isFollowing
            ? context.kabukSurfaceVariant
            : KabukTheme.primaryGreen,
        foregroundColor: isFollowing ? context.kabukTextSecondary : Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingMd,
          vertical: KabukTheme.spacingSm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
      ),
      child: isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.kabukTextPrimary,
              ),
            )
          : Text(isFollowing ? 'Unfollow' : 'Follow'),
    );
  }
}

/// A compact note card for the profile's notes list.
class _UserNoteCard extends StatelessWidget {
  const _UserNoteCard({
    required this.event,
    required this.authorName,
    this.authorPicture,
  });

  final NostrEvent event;
  final String authorName;
  final String? authorPicture;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ThreadView(eventId: event.id, rootEvent: event),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingMd,
          vertical: KabukTheme.spacingXs,
        ),
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        decoration: BoxDecoration(
          color: context.kabukCardColor,
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timestamp
            Text(
              formatDate(event.createdAt),
              style: TextStyle(
                color: context.kabukTextTertiary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: KabukTheme.spacingXs),

            // Content (truncated)
            Text(
              event.content,
              style: TextStyle(
                color: context.kabukTextPrimary,
                fontSize: 14,
                height: 1.5,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),

            // Tags
            if (event.tags.any((t) => t.isNotEmpty && t[0] == 't')) ...[
              const SizedBox(height: KabukTheme.spacingSm),
              Wrap(
                spacing: KabukTheme.spacingXs,
                children: event.tags
                    .where((t) => t.length >= 2 && t[0] == 't')
                    .take(5) // Max 5 tags shown
                    .map(
                      (t) => Text(
                        '#${t[1]}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: KabukTheme.purpleAccent,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
