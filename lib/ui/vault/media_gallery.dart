/// Media gallery view — unified gallery for photos, videos, and audio.
///
/// Presents all user media in a filterable grid with tabs for
/// All / Photos / Videos / Audio. Each item shows a thumbnail
/// or icon with metadata. Quick-capture buttons let the user
/// take a photo or record audio without leaving the workspace.
library;

import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/knowledge/types/media.dart';
import 'package:kabuk/ui/vault/vault_view.dart';
import 'package:kabuk/ui/theme.dart';

// ---------------------------------------------------------------------------
// Media gallery view
// ---------------------------------------------------------------------------

/// Grid-based media browser with category filters and capture actions.
class MediaGalleryView extends ConsumerStatefulWidget {
  /// Creates a [MediaGalleryView].
  const MediaGalleryView({
    super.key,
    required this.onCapturePhoto,
    required this.onRecordAudio,
    required this.onRefresh,
  });

  /// Opens the camera overlay.
  final VoidCallback onCapturePhoto;

  /// Opens the audio recorder overlay.
  final VoidCallback onRecordAudio;

  /// Called when the gallery should refresh.
  final VoidCallback onRefresh;

  @override
  ConsumerState<MediaGalleryView> createState() => _MediaGalleryViewState();
}

class _MediaGalleryViewState extends ConsumerState<MediaGalleryView> {
  _MediaFilter _filter = _MediaFilter.all;

  @override
  Widget build(BuildContext context) {
    final mediaAsync = ref.watch(mediaListProvider);

    return Column(
      children: [
        // Filter tabs + capture actions.
        _MediaToolbar(
          filter: _filter,
          onFilterChanged: (f) => setState(() => _filter = f),
          onCapturePhoto: widget.onCapturePhoto,
          onRecordAudio: widget.onRecordAudio,
        ),

        // Grid.
        Expanded(
          child: mediaAsync.when(
            data: (media) {
              final filtered = _applyFilter(media);
              if (filtered.isEmpty) {
                return _MediaEmptyState(filter: _filter);
              }
              return RefreshIndicator(
                color: KabukTheme.accentGreen,
                backgroundColor: KabukTheme.surface,
                onRefresh: () async {
                  ref.invalidate(mediaListProvider);
                  widget.onRefresh();
                },
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    KabukTheme.spacingMd,
                    KabukTheme.spacingXs,
                    KabukTheme.spacingMd,
                    120,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: MediaQuery.of(context).size.width > 900
                        ? 6
                        : MediaQuery.of(context).size.width > 600
                        ? 4
                        : 3,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 1,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    return _MediaTile(media: filtered[index]);
                  },
                ),
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(color: KabukTheme.accentGreen),
            ),
            error: (error, _) => Center(
              child: Text(
                'Failed to load media: $error',
                style: const TextStyle(color: KabukTheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<MediaData> _applyFilter(List<MediaData> media) {
    return switch (_filter) {
      _MediaFilter.all => media,
      _MediaFilter.photos =>
        media.where((m) => m.type == MediaType.image).toList(),
      _MediaFilter.videos =>
        media.where((m) => m.type == MediaType.video).toList(),
      _MediaFilter.audio =>
        media.where((m) => m.type == MediaType.audio).toList(),
    };
  }
}

// ---------------------------------------------------------------------------
// Filter enum
// ---------------------------------------------------------------------------

enum _MediaFilter { all, photos, videos, audio }

// ---------------------------------------------------------------------------
// Media toolbar
// ---------------------------------------------------------------------------

class _MediaToolbar extends StatelessWidget {
  const _MediaToolbar({
    required this.filter,
    required this.onFilterChanged,
    required this.onCapturePhoto,
    required this.onRecordAudio,
  });

  final _MediaFilter filter;
  final ValueChanged<_MediaFilter> onFilterChanged;
  final VoidCallback onCapturePhoto;
  final VoidCallback onRecordAudio;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingXs,
      ),
      child: Row(
        children: [
          // Filter chips.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _MediaFilter.values.map((f) {
                  final isActive = f == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onFilterChanged(f);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? KabukTheme.accentGreen.withAlpha(30)
                              : KabukTheme.surface,
                          borderRadius: BorderRadius.circular(
                            KabukTheme.radiusXl,
                          ),
                          border: Border.all(
                            color: isActive
                                ? KabukTheme.accentGreen
                                : KabukTheme.divider,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          _filterLabel(f),
                          style: TextStyle(
                            color: isActive
                                ? KabukTheme.accentGreen
                                : KabukTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Capture actions.
          _CaptureButton(
            icon: Icons.camera_alt_rounded,
            tooltip: 'Take photo',
            onTap: onCapturePhoto,
          ),
          const SizedBox(width: 4),
          _CaptureButton(
            icon: Icons.mic_rounded,
            tooltip: 'Record audio',
            onTap: onRecordAudio,
          ),
        ],
      ),
    );
  }

  String _filterLabel(_MediaFilter f) => switch (f) {
    _MediaFilter.all => 'All',
    _MediaFilter.photos => 'Photos',
    _MediaFilter.videos => 'Videos',
    _MediaFilter.audio => 'Audio',
  };
}

// ---------------------------------------------------------------------------
// Capture button
// ---------------------------------------------------------------------------

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: KabukTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
            ),
            child: Icon(icon, size: 16, color: KabukTheme.textSecondary),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Media tile
// ---------------------------------------------------------------------------

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.media});

  final MediaData media;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
      child: Container(
        color: KabukTheme.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail or icon.
            _buildThumbnail(),

            // Type badge.
            if (media.type != MediaType.image)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _typeIcon(media.type),
                        size: 10,
                        color: Colors.white,
                      ),
                      if (media.duration != null) ...[
                        const SizedBox(width: 2),
                        Text(
                          media.duration!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // Name overlay.
            if (media.name != null && media.name!.isNotEmpty)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                  child: Text(
                    media.name!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    // Try to show image thumbnail.
    if (media.type == MediaType.image && media.contentUrl != null) {
      final file = File(media.contentUrl!);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover);
      }
    }
    if (media.thumbnail != null) {
      final thumbFile = File(media.thumbnail!);
      if (thumbFile.existsSync()) {
        return Image.file(thumbFile, fit: BoxFit.cover);
      }
    }
    // Fallback icon.
    return Center(
      child: Icon(
        _typeIcon(media.type),
        size: 28,
        color: KabukTheme.textTertiary,
      ),
    );
  }

  IconData _typeIcon(MediaType type) => switch (type) {
    MediaType.image => Icons.image_rounded,
    MediaType.video => Icons.videocam_rounded,
    MediaType.audio => Icons.audiotrack_rounded,
    MediaType.other => Icons.insert_drive_file_rounded,
  };
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _MediaEmptyState extends StatelessWidget {
  const _MediaEmptyState({required this.filter});

  final _MediaFilter filter;

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = switch (filter) {
      _MediaFilter.all => (
        Icons.camera_alt_rounded,
        'No media yet',
        'Capture photos, videos, or audio to get started',
      ),
      _MediaFilter.photos => (
        Icons.image_outlined,
        'No photos yet',
        'Take a photo to see it here',
      ),
      _MediaFilter.videos => (
        Icons.videocam_outlined,
        'No videos yet',
        'Record a video to see it here',
      ),
      _MediaFilter.audio => (
        Icons.audiotrack_outlined,
        'No audio recordings yet',
        'Record audio to see it here',
      ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KabukTheme.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: KabukTheme.textSecondary.withAlpha(128),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            Text(
              title,
              style: const TextStyle(
                color: KabukTheme.textSecondary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            Text(
              subtitle,
              style: TextStyle(
                color: KabukTheme.textSecondary.withAlpha(180),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
