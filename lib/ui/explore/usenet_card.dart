/// Usenet release card widget for the Explore feed.
///
/// Displays a [UsenetReleaseData] search result with title, size,
/// category, quality attributes, and stream/save actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kabuk/knowledge/types/usenet.dart';
import 'package:kabuk/ui/shared/time_format.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// Content Type Detection
// =============================================================================

/// The detected content type of a Usenet release.
enum NzbContentType {
  /// Video files — movies, TV episodes, etc.
  video,

  /// Audio files — music, podcasts, audiobooks.
  audio,

  /// Image files — photos, artwork, galleries.
  image,

  /// Documents — ebooks, PDFs, comics.
  document,

  /// Software — applications, games, installers.
  software,

  /// Archives — compressed files, ISOs, unknown.
  archive,
}

/// Detects the content type of a [release] by inspecting the title extension,
/// category, and newsgroup in priority order.
NzbContentType detectContentType(UsenetReleaseData release) {
  // 1. Check title file extension (most reliable).
  final ext = _extractExtension(release.title);
  if (ext != null) {
    final fromExt = _contentTypeFromExtension(ext);
    if (fromExt != null) return fromExt;
  }

  // 2. Check category.
  final fromCat = _contentTypeFromCategory(release.category);
  if (fromCat != null) return fromCat;

  // 3. Check newsgroup name.
  final fromGroup = _contentTypeFromGroup(release.group);
  if (fromGroup != null) return fromGroup;

  // 4. Default to archive.
  return NzbContentType.archive;
}

/// Extracts a lowercase file extension from a release title, or `null`.
String? _extractExtension(String? title) {
  if (title == null) return null;
  final match = RegExp(r'\.([a-zA-Z0-9]{2,5})(?:\s*-[A-Z0-9]+)?$').firstMatch(title);
  return match?.group(1)?.toLowerCase();
}

NzbContentType? _contentTypeFromExtension(String ext) {
  const video = {
    'mkv', 'mp4', 'avi', 'wmv', 'mov', 'm4v', 'ts', 'webm',
  };
  const audio = {
    'mp3', 'flac', 'aac', 'ogg', 'wav', 'm4a', 'wma', 'ape',
  };
  const image = {
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'tiff', 'svg',
  };
  const document = {'pdf', 'epub', 'mobi', 'cbr', 'cbz', 'djvu'};
  const archive = {'rar', 'zip', '7z', 'tar', 'gz', 'iso', 'nfo'};
  const software = {'exe', 'msi', 'dmg', 'apk', 'deb'};

  if (video.contains(ext)) return NzbContentType.video;
  if (audio.contains(ext)) return NzbContentType.audio;
  if (image.contains(ext)) return NzbContentType.image;
  if (document.contains(ext)) return NzbContentType.document;
  if (software.contains(ext)) return NzbContentType.software;
  if (archive.contains(ext)) return NzbContentType.archive;
  return null;
}

NzbContentType? _contentTypeFromCategory(String? category) {
  return switch (category?.toLowerCase()) {
    'movies' || 'movie' || 'tv' || 'tv shows' || 'television' =>
      NzbContentType.video,
    'music' || 'audio' => NzbContentType.audio,
    'books' || 'ebooks' => NzbContentType.document,
    'games' || 'gaming' || 'software' || 'pc' || 'apps' =>
      NzbContentType.software,
    _ => null,
  };
}

NzbContentType? _contentTypeFromGroup(String? group) {
  if (group == null) return null;
  final g = group.toLowerCase();
  if (g.contains('movie') || g.contains('multimedia') || g.contains('tv')) {
    return NzbContentType.video;
  }
  if (g.contains('sound') || g.contains('mp3') || g.contains('music')) {
    return NzbContentType.audio;
  }
  if (g.contains('picture') || g.contains('image')) {
    return NzbContentType.image;
  }
  if (g.contains('e-book') || g.contains('ebook')) {
    return NzbContentType.document;
  }
  if (g.contains('game')) return NzbContentType.software;
  return null;
}

// =============================================================================
// Usenet Card
// =============================================================================

/// A card displaying a single Usenet release in the Explore feed.
///
/// Shows a cleaned-up release title, file size, category, quality attribute
/// chips, and stream / save action buttons. Visual style matches
/// `ArticleCard` from the same feed. A content-type badge (video, audio,
/// image) is overlaid in the top-right corner to help users quickly identify
/// what kind of content the release contains.
class UsenetCard extends StatelessWidget {
  /// Creates a [UsenetCard] for the given [release].
  const UsenetCard({
    super.key,
    required this.release,
    this.onStream,
    this.onSave,
    this.onTap,
  });

  /// The Usenet release to display.
  final UsenetReleaseData release;

  /// Called when the user taps the **Stream** button.
  final VoidCallback? onStream;

  /// Called when the user taps the **Save** button.
  final VoidCallback? onSave;

  /// Called when the user taps the card body.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = release.title;
    final cleanedTitle = title != null ? _cleanTitle(title) : 'Unknown Release';
    final attrs = _parseAttributes(release.attributes);
    final contentType = detectContentType(release);

    return Semantics(
      label: 'Usenet release: $cleanedTitle',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap?.call();
        },
        child: Container(
          decoration: BoxDecoration(
            color: context.kabukCardColor,
            borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
            border: Border.all(color: context.kabukDivider),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Accent bar — category color.
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: _categoryColor(release.category).withAlpha(180),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(KabukTheme.radiusLg),
                        topRight: Radius.circular(KabukTheme.radiusLg),
                      ),
                    ),
                  ),

                  // Category + age header row.
                  _CategoryHeader(
                    release: release,
                    contentType: contentType,
                  ),

                  // Title.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(
                      cleanedTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: context.kabukTextPrimary,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Size + metadata row.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: _MetadataRow(release: release),
                  ),

                  // Quality attribute chips.
                  if (attrs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: attrs.map(_QualityChip.new).toList(),
                      ),
                    ),

                  // Action bar.
                  _ActionBar(
                    onStream: onStream,
                    onSave: onSave,
                    contentType: contentType,
                  ),
                ],
              ),

              // Content-type overlay badge (video, audio, image only).
              if (_showOverlayBadge(contentType))
                Positioned(
                  top: 8,
                  right: 8,
                  child: _ContentTypeBadge(
                    contentType: contentType,
                    categoryColor: _categoryColor(release.category),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Only video, audio, and image types get a prominent overlay badge.
  static bool _showOverlayBadge(NzbContentType type) => switch (type) {
        NzbContentType.video ||
        NzbContentType.audio ||
        NzbContentType.image =>
          true,
        _ => false,
      };
}

// =============================================================================
// Content Type Badge
// =============================================================================

/// Overlay badge shown in the top-right corner of the card for video, audio,
/// and image content types.
class _ContentTypeBadge extends StatelessWidget {
  const _ContentTypeBadge({
    required this.contentType,
    required this.categoryColor,
  });

  final NzbContentType contentType;
  final Color categoryColor;

  @override
  Widget build(BuildContext context) {
    final (icon, bgColor) = switch (contentType) {
      NzbContentType.video => (
          Icons.play_arrow_rounded,
          Colors.black54,
        ),
      NzbContentType.audio => (
          Icons.music_note_rounded,
          categoryColor.withAlpha(180),
        ),
      NzbContentType.image => (
          Icons.image_rounded,
          Colors.black54,
        ),
      _ => (Icons.help_outline, Colors.black54),
    };

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }
}

// =============================================================================
// Category Header
// =============================================================================

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.release,
    required this.contentType,
  });

  final UsenetReleaseData release;
  final NzbContentType contentType;

  @override
  Widget build(BuildContext context) {
    final category = release.category;
    final color = _categoryColor(category);
    final age = release.publishedAt != null
        ? timeAgoFromDateTime(release.publishedAt!)
        : null;

    // For document/software/archive, override the icon to reflect the
    // detected content type (subtle tint, no overlay badge).
    final iconData = _contentTypeIconOverride(contentType) ??
        _categoryIcon(category);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(iconData, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _categoryLabel(category),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.kabukTextSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (age != null)
            Text(
              age,
              style: TextStyle(
                fontSize: 12,
                color: context.kabukTextTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Metadata Row
// =============================================================================

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.release});

  final UsenetReleaseData release;

  @override
  Widget build(BuildContext context) {
    final sizeText =
        release.sizeBytes != null ? _formatSize(release.sizeBytes!) : null;

    return Row(
      children: [
        // Size badge — prominent since size is key info for Usenet.
        if (sizeText != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: KabukTheme.primaryGreen.withAlpha(30),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: KabukTheme.primaryGreen.withAlpha(60),
                width: 0.5,
              ),
            ),
            child: Text(
              sizeText,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: KabukTheme.accentGreen,
              ),
            ),
          ),
        if (sizeText != null) const SizedBox(width: 8),

        // Indexer name.
        if (release.indexerRef != null)
          Expanded(
            child: Text(
              _indexerDisplayName(release.indexerRef!),
              style: TextStyle(
                fontSize: 11,
                color: context.kabukTextTertiary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          )
        else
          const Spacer(),

        // Poster / group.
        if (release.group != null)
          Text(
            release.group!,
            style: TextStyle(
              fontSize: 11,
              color: context.kabukTextTertiary,
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Quality Chip
// =============================================================================

class _QualityChip extends StatelessWidget {
  const _QualityChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final isHighlight = _isHighlightAttribute(label);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isHighlight
            ? KabukTheme.warmAccent.withAlpha(25)
            : context.kabukSurfaceVariant,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isHighlight
              ? KabukTheme.warmAccent.withAlpha(60)
              : context.kabukDivider,
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isHighlight ? FontWeight.w600 : FontWeight.w500,
          color: isHighlight
              ? KabukTheme.warmAccent
              : context.kabukTextSecondary,
        ),
      ),
    );
  }

  /// Premium quality indicators get a warm accent highlight.
  static bool _isHighlightAttribute(String attr) {
    const highlighted = {
      '2160p', '4K', 'HDR', 'HDR10', 'HDR10+', 'DV',
      'Dolby Vision', 'Remux', 'Atmos', 'DTS-X', 'TrueHD',
    };
    return highlighted.contains(attr);
  }
}

// =============================================================================
// Action Bar
// =============================================================================

class _ActionBar extends StatelessWidget {
  const _ActionBar({this.onStream, this.onSave, required this.contentType});

  final VoidCallback? onStream;
  final VoidCallback? onSave;
  final NzbContentType contentType;

  @override
  Widget build(BuildContext context) {
    final (primaryIcon, primaryLabel, tooltip) =
        _primaryAction(contentType);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          // Primary action — filled style.
          Tooltip(
            message: tooltip,
            child: FilledButton.icon(
              onPressed: onStream,
              icon: Icon(primaryIcon, size: 18),
              label: Text(primaryLabel),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Save — outlined style.
          Tooltip(
            message: 'Save NZB for download',
            child: OutlinedButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save_alt_rounded, size: 18),
              label: const Text('Save'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),

          const Spacer(),

          // Overflow menu.
          Tooltip(
            message: 'More actions',
            child: IconButton(
              icon: Icon(
                Icons.more_horiz_rounded,
                size: 20,
                color: context.kabukTextTertiary,
              ),
              onPressed: () => _showOverflowMenu(context),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  void _showOverflowMenu(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    final offset = box.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx + box.size.width - 48,
        offset.dy + box.size.height,
        offset.dx + box.size.width,
        offset.dy + box.size.height + 48,
      ),
      items: const [
        PopupMenuItem(value: 'copy_nzb', child: Text('Copy NZB URL')),
        PopupMenuItem(value: 'details', child: Text('Release details')),
        PopupMenuItem(value: 'hide', child: Text('Hide this result')),
      ],
    );
  }
}

// =============================================================================
// Helper functions
// =============================================================================

/// Returns the primary action icon, label, and tooltip for a [contentType].
(IconData, String, String) _primaryAction(NzbContentType contentType) {
  return switch (contentType) {
    NzbContentType.video => (
        Icons.play_arrow_rounded,
        'Stream',
        'Stream this release',
      ),
    NzbContentType.audio => (
        Icons.headphones_rounded,
        'Play',
        'Play this audio',
      ),
    NzbContentType.image => (
        Icons.visibility_rounded,
        'View',
        'View this image',
      ),
    NzbContentType.document => (
        Icons.open_in_new_rounded,
        'Open',
        'Open this document',
      ),
    NzbContentType.software || NzbContentType.archive => (
        Icons.download_rounded,
        'Download',
        'Download this release',
      ),
  };
}

/// Returns an alternative icon for document/software/archive content types,
/// used to subtly tint the category header instead of showing an overlay badge.
/// Returns `null` for types that already have an overlay badge.
IconData? _contentTypeIconOverride(NzbContentType contentType) {
  return switch (contentType) {
    NzbContentType.document => Icons.description_rounded,
    NzbContentType.software => Icons.code_rounded,
    NzbContentType.archive => Icons.archive_rounded,
    _ => null,
  };
}

/// Formats [bytes] as a human-readable size string.
String _formatSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  const startIndex = 0;
  var unitIndex = startIndex;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  return unitIndex == 0
      ? '${value.toInt()} ${units[unitIndex]}'
      : '${value.toStringAsFixed(value < 10 ? 2 : 1)} ${units[unitIndex]}';
}

/// Cleans a Usenet release title for display.
///
/// Replaces dots with spaces and strips the trailing release-group tag
/// (e.g. `-SPARKS`, `-FGT`).
String _cleanTitle(String rawTitle) {
  // Replace dots/underscores with spaces.
  var cleaned = rawTitle.replaceAll(RegExp(r'[._]'), ' ');
  // Remove trailing group tag (e.g. "x264-GROUP" → keep "x264").
  cleaned = cleaned.replaceAll(RegExp(r'-[A-Z0-9]{2,}$'), '');
  return cleaned.trim();
}

/// Returns the Material icon for a Usenet content [category].
IconData _categoryIcon(String? category) {
  return switch (category?.toLowerCase()) {
    'movies' || 'movie' => Icons.movie_rounded,
    'tv' || 'tv shows' || 'television' => Icons.tv_rounded,
    'music' || 'audio' => Icons.music_note_rounded,
    'games' || 'gaming' => Icons.games_rounded,
    'software' || 'pc' || 'apps' => Icons.laptop_rounded,
    'books' || 'ebooks' => Icons.menu_book_rounded,
    'xxx' || 'adult' => Icons.eighteen_up_rating_rounded,
    _ => Icons.folder_rounded,
  };
}

/// Returns an accent color for a Usenet content [category].
Color _categoryColor(String? category) {
  return switch (category?.toLowerCase()) {
    'movies' || 'movie' => KabukTheme.blueAccent,
    'tv' || 'tv shows' || 'television' => KabukTheme.purpleAccent,
    'music' || 'audio' => const Color(0xFFE91E63),
    'games' || 'gaming' => KabukTheme.accentGreen,
    'software' || 'pc' || 'apps' => KabukTheme.warmAccent,
    'books' || 'ebooks' => const Color(0xFF8D6E63),
    _ => KabukTheme.textSecondary,
  };
}

/// Returns a human-readable label for a Usenet content [category].
String _categoryLabel(String? category) {
  return switch (category?.toLowerCase()) {
    'movies' || 'movie' => 'Movies',
    'tv' || 'tv shows' || 'television' => 'TV Shows',
    'music' => 'Music',
    'audio' => 'Audio',
    'games' || 'gaming' => 'Games',
    'software' || 'pc' || 'apps' => 'Software',
    'books' || 'ebooks' => 'Books',
    'xxx' || 'adult' => 'Adult',
    final String c => c,
    null => 'Usenet',
  };
}

/// Splits the release attributes list, trimming whitespace and
/// discarding empty entries.
List<String> _parseAttributes(List<String> attrs) {
  return attrs
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty)
      .toList();
}

/// Derives a short display name from an indexer URI.
String _indexerDisplayName(String ref) {
  // Strip common prefixes for compact display.
  if (ref.startsWith('kabuk:')) {
    return ref.substring(6).replaceAll('-', ' ');
  }
  final uri = Uri.tryParse(ref);
  if (uri != null && uri.host.isNotEmpty) return uri.host;
  return ref;
}
