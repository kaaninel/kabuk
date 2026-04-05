/// Typed content card widgets for grid and list display.
///
/// Each card is styled for a 2-column grid layout with rounded corners,
/// [KabukTheme] colors, and [CachedNetworkImage] thumbnails.
/// Tapping a card defaults to opening [ViewerRouter.open].
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/services/media_cache.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:kabuk/ui/viewers/viewer_router.dart';

// =============================================================================
// Factory
// =============================================================================

/// Returns the appropriate card widget for [item].
Widget contentCardFor(ContentItem item, {VoidCallback? onTap}) {
  return switch (item.contentType) {
    ContentType.video => VideoContentCard(item: item, onTap: onTap),
    ContentType.image => ImageContentCard(item: item, onTap: onTap),
    ContentType.audio => AudioContentCard(item: item, onTap: onTap),
    ContentType.article => ArticleContentCard(item: item, onTap: onTap),
    ContentType.document ||
    ContentType.profile ||
    ContentType.channel ||
    ContentType.mixed =>
      GenericContentCard(item: item, onTap: onTap),
  };
}

// =============================================================================
// Video Content Card
// =============================================================================

/// Card with thumbnail, play icon overlay, duration badge, title, and author.
class VideoContentCard extends StatelessWidget {
  /// Creates a [VideoContentCard].
  const VideoContentCard({required this.item, this.onTap, super.key});

  /// The video content item.
  final ContentItem item;

  /// Optional tap callback. Defaults to [ViewerRouter.open].
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final meta =
        item.metadata is VideoMeta ? item.metadata! as VideoMeta : null;
    final duration = meta?.duration;
    final views = item.extra['viewCount'] ?? item.extra['views'];

    return _CardShell(
      onTap: onTap ?? () => ViewerRouter.open(context, item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail with play icon + duration badge.
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Thumbnail(url: item.thumbnailUrl),
                // Play icon centre.
                const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white70,
                    size: 40,
                  ),
                ),
                // Duration badge bottom-right.
                if (duration != null)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: _Badge(text: _formatDuration(duration)),
                  ),
              ],
            ),
          ),

          // Text content.
          Padding(
            padding: const EdgeInsets.all(KabukTheme.spacingSm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: context.kabukTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                _MetaLine(
                  parts: [
                    if (item.author?.name != null) item.author!.name!,
                    if (views != null) '$views views',
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Image Content Card
// =============================================================================

/// Card with full-bleed image preview, optional gallery count badge,
/// and title overlay at the bottom.
class ImageContentCard extends StatelessWidget {
  /// Creates an [ImageContentCard].
  const ImageContentCard({required this.item, this.onTap, super.key});

  /// The image content item.
  final ContentItem item;

  /// Optional tap callback. Defaults to [ViewerRouter.open].
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final meta =
        item.metadata is ImageMeta ? item.metadata! as ImageMeta : null;
    final galleryCount = meta?.galleryUrls.length ?? 0;

    return _CardShell(
      onTap: onTap ?? () => ViewerRouter.open(context, item),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Thumbnail(url: item.thumbnailUrl),

            // Gallery count badge top-right.
            if (galleryCount > 1)
              Positioned(
                top: 6,
                right: 6,
                child: _Badge(text: '$galleryCount photos'),
              ),

            // Title overlay at bottom.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withAlpha(180),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                  child: Text(
                    item.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Audio Content Card
// =============================================================================

/// Horizontal card with artwork square, title + artist, play icon, and
/// duration.
class AudioContentCard extends StatelessWidget {
  /// Creates an [AudioContentCard].
  const AudioContentCard({required this.item, this.onTap, super.key});

  /// The audio content item.
  final ContentItem item;

  /// Optional tap callback. Defaults to [ViewerRouter.open].
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final meta =
        item.metadata is AudioMeta ? item.metadata! as AudioMeta : null;
    final artworkUrl = meta?.artworkUrl ?? item.thumbnailUrl;
    final artist = meta?.artist ?? item.author?.name;
    final duration = meta?.duration;

    return _CardShell(
      onTap: onTap ?? () => ViewerRouter.open(context, item),
      child: SizedBox(
        height: 72,
        child: Row(
          children: [
            // Artwork square.
            SizedBox(
              width: 72,
              height: 72,
              child: artworkUrl != null
                  ? _Thumbnail(url: artworkUrl)
                  : Container(
                      color: KabukTheme.surfaceVariant,
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: KabukTheme.accentGreen,
                        size: 28,
                      ),
                    ),
            ),

            // Title + artist + duration.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KabukTheme.spacingSm,
                  vertical: KabukTheme.spacingXs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        color: context.kabukTextPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (artist != null || duration != null) ...[
                      const SizedBox(height: 2),
                      _MetaLine(
                        parts: [
                          ?artist,
                          if (duration != null) _formatDuration(duration),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Small play icon.
            Padding(
              padding: const EdgeInsets.only(right: KabukTheme.spacingSm),
              child: Icon(
                Icons.play_circle_outline_rounded,
                color: context.kabukTextSecondary,
                size: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Article Content Card
// =============================================================================

/// Card with bold headline, 2-line excerpt, source + date, and an optional
/// thumbnail on the right.
class ArticleContentCard extends StatelessWidget {
  /// Creates an [ArticleContentCard].
  const ArticleContentCard({required this.item, this.onTap, super.key});

  /// The article content item.
  final ContentItem item;

  /// Optional tap callback. Defaults to [ViewerRouter.open].
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasThumbnail = item.thumbnailUrl != null;
    final excerpt = item.description ?? '';
    final source = item.extra['source'] ?? item.sourcePluginId;

    return _CardShell(
      onTap: onTap ?? () => ViewerRouter.open(context, item),
      child: Padding(
        padding: const EdgeInsets.all(KabukTheme.spacingSm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Text column.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      color: context.kabukTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (excerpt.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      excerpt,
                      style: TextStyle(
                        color: context.kabukTextSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  _MetaLine(
                    parts: [
                      source,
                      if (item.publishedAt != null)
                        _formatDate(item.publishedAt!),
                    ],
                  ),
                ],
              ),
            ),

            // Optional thumbnail.
            if (hasThumbnail) ...[
              const SizedBox(width: KabukTheme.spacingSm),
              ClipRRect(
                borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                child: CachedNetworkImage(
                  imageUrl: item.thumbnailUrl!,
                  cacheManager: KabukCacheManager.instance,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    width: 72,
                    height: 72,
                    color: KabukTheme.surfaceVariant,
                  ),
                  errorWidget: (_, _, _) => Container(
                    width: 72,
                    height: 72,
                    color: KabukTheme.surfaceVariant,
                    child: const Icon(
                      Icons.broken_image_rounded,
                      color: KabukTheme.textTertiary,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Generic Content Card
// =============================================================================

/// Fallback card showing a content-type icon, title, and description.
class GenericContentCard extends StatelessWidget {
  /// Creates a [GenericContentCard].
  const GenericContentCard({required this.item, this.onTap, super.key});

  /// The content item.
  final ContentItem item;

  /// Optional tap callback. Defaults to [ViewerRouter.open].
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      onTap: onTap ?? () => ViewerRouter.open(context, item),
      child: Padding(
        padding: const EdgeInsets.all(KabukTheme.spacingSm),
        child: Row(
          children: [
            // Type icon.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: KabukTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
              ),
              child: Icon(
                _iconForType(item.contentType),
                color: KabukTheme.accentGreen,
                size: 22,
              ),
            ),
            const SizedBox(width: KabukTheme.spacingSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      color: context.kabukTextPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.description!,
                      style: TextStyle(
                        color: context.kabukTextSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconForType(ContentType type) {
    return switch (type) {
      ContentType.document => Icons.description_rounded,
      ContentType.profile => Icons.person_rounded,
      ContentType.channel => Icons.subscriptions_rounded,
      ContentType.mixed => Icons.dashboard_rounded,
      ContentType.video => Icons.videocam_rounded,
      ContentType.image => Icons.image_rounded,
      ContentType.audio => Icons.audiotrack_rounded,
      ContentType.article => Icons.article_rounded,
    };
  }
}

// =============================================================================
// Shared internals
// =============================================================================

/// Card shell with rounded corners, elevated surface background, and ink
/// splash.
class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.kabukSurfaceElevated,
      borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        child: child,
      ),
    );
  }
}

/// Cached thumbnail image that fills its parent.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return Container(
        color: KabukTheme.surfaceVariant,
        child: const Icon(
          Icons.image_rounded,
          color: KabukTheme.textTertiary,
          size: 32,
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: url!,
      cacheManager: KabukCacheManager.instance,
      fit: BoxFit.cover,
      placeholder: (_, _) => Container(color: KabukTheme.surfaceVariant),
      errorWidget: (_, _, _) => Container(
        color: KabukTheme.surfaceVariant,
        child: const Icon(
          Icons.broken_image_rounded,
          color: KabukTheme.textTertiary,
          size: 24,
        ),
      ),
    );
  }
}

/// Small dark badge for duration, gallery count, etc.
class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Dot-separated metadata line in secondary text color.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.parts});

  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' · '),
      style: TextStyle(
        color: context.kabukTextSecondary,
        fontSize: 11,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// =============================================================================
// Helpers
// =============================================================================

/// Formats a [Duration] as `MM:SS` or `H:MM:SS`.
String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}

/// Formats a [DateTime] as `MMM d, yyyy`.
String _formatDate(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}
