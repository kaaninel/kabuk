/// Shared Nostr author row widget — avatar + name + optional NIP-05 + timestamp.
///
/// Consolidates the near-identical `_NoteHeader`, `_AuthorRow`, and
/// `_CompactAuthor` implementations into a single reusable widget
/// with configurable sizing via [AuthorRowSize].
library;

import 'package:flutter/material.dart';

import 'package:kabuk/ui/shared/feed_image.dart';
import 'package:kabuk/ui/shared/time_format.dart';
import 'package:kabuk/ui/theme.dart';

/// Predefined sizing presets for [NostrAuthorRow].
enum AuthorRowSize {
  /// 20px avatar, smaller text — search results.
  compact(avatarRadius: 10, nameFontSize: 12, timeFontSize: 11),

  /// 28px avatar, normal text — feed cards.
  small(avatarRadius: 14, nameFontSize: 13, timeFontSize: 12),

  /// 32px avatar, normal text — thread notes.
  medium(avatarRadius: 16, nameFontSize: 13, timeFontSize: 12);

  const AuthorRowSize({
    required this.avatarRadius,
    required this.nameFontSize,
    required this.timeFontSize,
  });

  /// Radius for the circular avatar (diameter = 2×).
  final double avatarRadius;

  /// Font size for the author name.
  final double nameFontSize;

  /// Font size for the timestamp.
  final double timeFontSize;
}

/// Displays a Nostr note author in a horizontal row.
///
/// Shows avatar (picture or fallback initial), display name, optional
/// NIP-05 verified badge, and a relative timestamp.
///
/// Use [AuthorRowSize] presets to control the visual density:
/// ```dart
/// NostrAuthorRow(
///   name: 'Alice',
///   picture: 'https://example.com/avatar.jpg',
///   createdAt: event.createdAt,
///   size: AuthorRowSize.medium,
///   showNip05: true,
///   nip05: 'alice@example.com',
/// )
/// ```
class NostrAuthorRow extends StatelessWidget {
  /// Creates a Nostr author row.
  const NostrAuthorRow({
    super.key,
    required this.name,
    required this.createdAt,
    this.picture,
    this.nip05,
    this.showNip05 = false,
    this.size = AuthorRowSize.small,
    this.nameColor,
    this.nameWeight,
  });

  /// Display name — falls back to truncated pubkey externally.
  final String name;

  /// Profile picture URL, or `null` for the letter fallback.
  final String? picture;

  /// Unix timestamp (seconds) of the note.
  final int createdAt;

  /// NIP-05 identifier (e.g. `user@example.com`). Shown only when
  /// [showNip05] is `true` and this is non-null.
  final String? nip05;

  /// Whether to show the NIP-05 verified badge.
  final bool showNip05;

  /// Visual density preset.
  final AuthorRowSize size;

  /// Override name color (defaults to the theme's text primary color).
  final Color? nameColor;

  /// Override name font weight (defaults to [FontWeight.w600]).
  final FontWeight? nameWeight;

  @override
  Widget build(BuildContext context) {
    final avatarDiameter = size.avatarRadius * 2;
    final time = timeAgo(createdAt);

    return Row(
      children: [
        // Avatar
        if (picture != null)
          ClipOval(
            child: FeedImage(
              imageUrl: picture!,
              width: avatarDiameter,
              height: avatarDiameter,
              fit: BoxFit.cover,
            ),
          )
        else
          CircleAvatar(
            radius: size.avatarRadius,
            backgroundColor: context.kabukSurfaceVariant,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                color: context.kabukTextSecondary,
                fontSize: size.nameFontSize - 2,
              ),
            ),
          ),

        SizedBox(
          width: size == AuthorRowSize.compact
              ? KabukTheme.spacingXs
              : KabukTheme.spacingSm,
        ),

        // Name
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              color: nameColor ?? context.kabukTextPrimary,
              fontWeight: nameWeight ?? FontWeight.w600,
              fontSize: size.nameFontSize,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // NIP-05 badge
        if (showNip05 && nip05 != null) ...[
          const Icon(
            Icons.verified_rounded,
            size: 14,
            color: KabukTheme.purpleAccent,
          ),
          const SizedBox(width: KabukTheme.spacingXs),
        ],

        // Timestamp
        Text(
          time,
          style: TextStyle(
            color: context.kabukTextTertiary,
            fontSize: size.timeFontSize,
          ),
        ),
      ],
    );
  }
}
