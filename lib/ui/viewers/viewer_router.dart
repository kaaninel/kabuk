/// Routes content items to the appropriate viewer widget.
///
/// Central dispatch for content display. All content rendering
/// goes through this router to ensure consistent viewer selection.
library;

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/services/media_cache.dart';
import 'package:kabuk/ui/shared/fullscreen_image_viewer.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:kabuk/ui/viewers/content_cards.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

/// Routes [ContentItem] instances to their best-matching viewer.
abstract final class ViewerRouter {
  /// Opens the appropriate viewer for [item] as a full-screen page.
  ///
  /// Determines the viewer based on [ContentItem.contentType] and
  /// available metadata:
  /// - [ContentType.video] → [ContentVideoPage]
  /// - [ContentType.image] → [FullscreenImageViewer]
  /// - [ContentType.audio] → Audio bottom sheet
  /// - [ContentType.article] → [ContentArticlePage]
  /// - [ContentType.document] → [ContentArticlePage] (fallback)
  /// - Others → [ContentArticlePage] (generic display)
  static Future<void> open(BuildContext context, ContentItem item) async {
    switch (item.contentType) {
      case ContentType.video:
        _openVideo(context, item);
      case ContentType.image:
        _openImage(context, item);
      case ContentType.audio:
        _openAudio(context, item);
      case ContentType.article:
      case ContentType.document:
      case ContentType.profile:
      case ContentType.channel:
      case ContentType.mixed:
        _openArticle(context, item);
    }
  }

  /// Returns the best widget for inline/card display of [item].
  static Widget cardFor(ContentItem item, {VoidCallback? onTap}) {
    return contentCardFor(item, onTap: onTap);
  }

  // ---------------------------------------------------------------------------
  // Private openers
  // ---------------------------------------------------------------------------

  static void _openVideo(BuildContext context, ContentItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContentVideoPage(item: item),
      ),
    );
  }

  static void _openImage(BuildContext context, ContentItem item) {
    final meta = item.metadata;
    final List<String> urls;

    if (meta is ImageMeta && meta.galleryUrls.isNotEmpty) {
      urls = meta.galleryUrls;
    } else if (item.thumbnailUrl != null) {
      urls = [item.thumbnailUrl!];
    } else if (item.url != null) {
      urls = [item.url!];
    } else {
      return;
    }

    if (urls.length == 1) {
      FullscreenImageViewer.show(context, imageUrl: urls.first);
    } else {
      FullscreenImageViewer.showGallery(context, images: urls);
    }
  }

  static void _openAudio(BuildContext context, ContentItem item) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AudioPlayerSheet(item: item),
    );
  }

  static void _openArticle(BuildContext context, ContentItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContentArticlePage(item: item),
      ),
    );
  }
}

// =============================================================================
// Content Video Page
// =============================================================================

/// Full-screen video player for a [ContentItem] with optional [VideoMeta].
///
/// Tries [VideoMeta.streamUrl] first, then [VideoMeta.hlsUrl], then
/// [ContentItem.url]. Shows YouTube-style overlay controls with play/pause,
/// seek bar, and fullscreen toggle. Auto-detects landscape aspect ratio.
class ContentVideoPage extends StatefulWidget {
  /// Creates a [ContentVideoPage].
  const ContentVideoPage({required this.item, super.key});

  /// The content item to play.
  final ContentItem item;

  @override
  State<ContentVideoPage> createState() => _ContentVideoPageState();
}

class _ContentVideoPageState extends State<ContentVideoPage> {
  Player? _player;
  VideoController? _videoController;
  bool _initialized = false;
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _hasError = false;
  String? _errorMessage;
  Timer? _hideTimer;

  bool _isLandscapeVideo = false;

  // Stream-based playback state from media_kit.
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _bufferPosition = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<int?>? _widthSub;

  double get _bufferedProgress {
    if (_duration.inMilliseconds == 0) return 0;
    return (_bufferPosition.inMilliseconds / _duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _initController();
  }

  String? get _videoUrl {
    final meta = widget.item.metadata;
    if (meta is VideoMeta) {
      if (meta.streamUrl != null) return meta.streamUrl;
      if (meta.hlsUrl != null) return meta.hlsUrl;
    }
    return widget.item.url;
  }

  Future<void> _initController() async {
    final url = _videoUrl;
    if (url == null) {
      setState(() {
        _hasError = true;
        _errorMessage = 'No video URL available';
      });
      return;
    }

    final player = Player();
    final videoController = VideoController(player);
    _player = player;
    _videoController = videoController;

    // Set up stream subscriptions for reactive playback state.
    _positionSub = player.stream.position.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durationSub = player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _bufferSub = player.stream.buffer.listen((b) {
      if (mounted) setState(() => _bufferPosition = b);
    });
    _playingSub = player.stream.playing.listen((p) {
      if (mounted) setState(() => _isPlaying = p);
    });
    _bufferingSub = player.stream.buffering.listen((b) {
      if (mounted) setState(() => _isBuffering = b);
    });
    _errorSub = player.stream.error.listen((e) {
      if (mounted && e.isNotEmpty && !_hasError) {
        setState(() {
          _hasError = true;
          _errorMessage = e;
        });
      }
    });

    // Detect landscape aspect ratio for auto-rotation.
    _widthSub = player.stream.width.listen((w) {
      if (w != null && w > 0 && mounted && !_isLandscapeVideo) {
        final h = player.state.height ?? 1;
        if (h > 0) {
          final ar = w / h;
          if (ar > 1.2) {
            _isLandscapeVideo = true;
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
            SystemChrome.setEnabledSystemUIMode(
              SystemUiMode.immersiveSticky,
            );
            setState(() => _isFullscreen = true);
          }
        }
      }
    });

    try {
      await player.open(Media(url));
      if (!mounted) return;

      setState(() => _initialized = true);
      _scheduleHideControls();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load video: $e';
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferSub?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _widthSub?.cancel();
    _player?.dispose();
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------------

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  void _togglePlayPause() {
    final player = _player;
    if (player == null) return;
    if (_isPlaying) {
      player.pause();
    } else {
      player.play();
      _scheduleHideControls();
    }
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      if (_isLandscapeVideo) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } else {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    setState(() => _isFullscreen = !_isFullscreen);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _hasError
          ? _buildError()
          : _initialized
              ? _buildPlayer()
              : _buildLoading(),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 12),
          Text(
            'Loading video…',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: KabukTheme.error,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Video error',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    return GestureDetector(
      onTap: _toggleControls,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Video(
              controller: _videoController!,
              controls: (state) => const SizedBox.shrink(),
            ),
          ),
          if (_isBuffering)
            const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: _VideoControlsOverlay(
                title: widget.item.title,
                isFullscreen: _isFullscreen,
                isPlaying: _isPlaying,
                position: _position,
                duration: _duration,
                bufferedProgress: _bufferedProgress,
                onBack: () => Navigator.of(context).pop(),
                onPlayPause: _togglePlayPause,
                onFullscreen: _toggleFullscreen,
                onSeek: (d) => _player?.seek(d),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Video Controls Overlay
// =============================================================================

/// YouTube-style overlay with gradient bars, centred play/pause,
/// seek bar, time display, and fullscreen toggle.
class _VideoControlsOverlay extends StatelessWidget {
  const _VideoControlsOverlay({
    required this.title,
    required this.isFullscreen,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.bufferedProgress,
    required this.onBack,
    required this.onPlayPause,
    required this.onFullscreen,
    required this.onSeek,
  });

  final String title;
  final bool isFullscreen;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double bufferedProgress;
  final VoidCallback onBack;
  final VoidCallback onPlayPause;
  final VoidCallback onFullscreen;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: Colors.black.withAlpha(60)),

        // Top bar.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withAlpha(180),
                  Colors.transparent,
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                      onPressed: onBack,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Centre play/pause.
        Center(
          child: GestureDetector(
            onTap: onPlayPause,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(90),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 56,
              ),
            ),
          ),
        ),

        // Bottom bar — seek + time + fullscreen.
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
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ContentSeekBar(
                      position: position,
                      duration: duration,
                      bufferedProgress: bufferedProgress,
                      onSeek: onSeek,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${_formatDuration(position)} / '
                          '${_formatDuration(duration)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            isFullscreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: onFullscreen,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Seek Bar
// =============================================================================

/// Seek bar with buffered progress, played progress, and draggable thumb.
class _ContentSeekBar extends StatefulWidget {
  const _ContentSeekBar({
    required this.position,
    required this.duration,
    required this.bufferedProgress,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final double bufferedProgress;
  final ValueChanged<Duration> onSeek;

  @override
  State<_ContentSeekBar> createState() => _ContentSeekBarState();
}

class _ContentSeekBarState extends State<_ContentSeekBar> {
  bool _dragging = false;
  double _dragValue = 0;

  double _progressFor(Duration position, Duration duration) {
    if (duration.inMilliseconds == 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  void _seekTo(double relative) {
    final position = Duration(
      milliseconds: (relative * widget.duration.inMilliseconds).round(),
    );
    widget.onSeek(position);
  }

  @override
  Widget build(BuildContext context) {
    final played = _dragging
        ? _dragValue
        : _progressFor(widget.position, widget.duration);
    final buffered = widget.bufferedProgress;

    return GestureDetector(
      onHorizontalDragStart: (_) {
        setState(() {
          _dragging = true;
          _dragValue = played;
        });
      },
      onHorizontalDragUpdate: (details) {
        final box = context.findRenderObject()! as RenderBox;
        final relative =
            (details.localPosition.dx / box.size.width).clamp(0.0, 1.0);
        setState(() => _dragValue = relative);
      },
      onHorizontalDragEnd: (_) {
        _seekTo(_dragValue);
        setState(() => _dragging = false);
      },
      onHorizontalDragCancel: () => setState(() => _dragging = false),
      onTapUp: (details) {
        final box = context.findRenderObject()! as RenderBox;
        final relative =
            (details.localPosition.dx / box.size.width).clamp(0.0, 1.0);
        _seekTo(relative);
      },
      child: SizedBox(
        height: 32,
        child: CustomPaint(
          painter: _SeekBarPainter(
            played: played,
            buffered: buffered,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Custom painter for the three-layer seek bar + thumb.
class _SeekBarPainter extends CustomPainter {
  _SeekBarPainter({required this.played, required this.buffered});

  final double played;
  final double buffered;

  static const double _trackHeight = 4;
  static const double _thumbRadius = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const rr = Radius.circular(_trackHeight / 2);

    // Background.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, cy - _trackHeight / 2, size.width, _trackHeight),
        rr,
      ),
      Paint()..color = Colors.white12,
    );

    // Buffered.
    if (buffered > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            0,
            cy - _trackHeight / 2,
            size.width * buffered,
            _trackHeight,
          ),
          rr,
        ),
        Paint()..color = Colors.white30,
      );
    }

    // Played.
    if (played > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            0,
            cy - _trackHeight / 2,
            size.width * played,
            _trackHeight,
          ),
          rr,
        ),
        Paint()..color = KabukTheme.primaryGreen,
      );
    }

    // Thumb.
    final thumbX =
        (size.width * played).clamp(_thumbRadius, size.width - _thumbRadius);
    canvas.drawCircle(
      Offset(thumbX, cy),
      _thumbRadius,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_SeekBarPainter old) =>
      played != old.played || buffered != old.buffered;
}

// =============================================================================
// Audio Player Sheet
// =============================================================================

/// Bottom sheet showing audio metadata and a play-in-browser action.
///
/// Displays artwork, title, artist, album, and duration. Actual in-app
/// playback can be added later with `just_audio`.
class _AudioPlayerSheet extends StatelessWidget {
  const _AudioPlayerSheet({required this.item});

  final ContentItem item;

  @override
  Widget build(BuildContext context) {
    final meta = item.metadata is AudioMeta ? item.metadata! as AudioMeta : null;
    final artworkUrl = meta?.artworkUrl ?? item.thumbnailUrl;
    final artist = meta?.artist ?? item.author?.name;
    final album = meta?.album;
    final duration = meta?.duration;

    return Container(
      decoration: BoxDecoration(
        color: context.kabukSurfaceElevated,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusXl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle.
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: context.kabukTextTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Artwork.
          ClipRRect(
            borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
            child: artworkUrl != null
                ? CachedNetworkImage(
                    imageUrl: artworkUrl,
                    cacheManager: KabukCacheManager.instance,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => _artworkPlaceholder(),
                    errorWidget: (_, _, _) => _artworkPlaceholder(),
                  )
                : _artworkPlaceholder(),
          ),
          const SizedBox(height: KabukTheme.spacingLg),

          // Title.
          Text(
            item.title,
            style: TextStyle(
              color: context.kabukTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: KabukTheme.spacingXs),

          // Artist / album.
          if (artist != null || album != null)
            Text(
              [?artist, ?album].join(' · '),
              style: TextStyle(
                color: context.kabukTextSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

          // Duration.
          if (duration != null) ...[
            const SizedBox(height: KabukTheme.spacingXs),
            Text(
              _formatDuration(duration),
              style: TextStyle(
                color: context.kabukTextTertiary,
                fontSize: 12,
              ),
            ),
          ],

          const SizedBox(height: KabukTheme.spacingLg),

          // Play externally.
          if (item.url != null)
            FilledButton.icon(
              onPressed: () async {
                final uri = Uri.parse(item.url!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Play in browser'),
              style: FilledButton.styleFrom(
                backgroundColor: KabukTheme.primaryGreen,
              ),
            ),
        ],
      ),
    );
  }

  Widget _artworkPlaceholder() {
    return Container(
      width: 200,
      height: 200,
      color: KabukTheme.surfaceVariant,
      child: const Icon(
        Icons.music_note_rounded,
        size: 80,
        color: KabukTheme.accentGreen,
      ),
    );
  }
}

// =============================================================================
// Content Article Page
// =============================================================================

/// Full-screen article page for text-based [ContentItem]s.
///
/// Renders title, author, date, description, and body text.
/// Falls back to description-only when no [ArticleMeta.body] is available.
class ContentArticlePage extends StatelessWidget {
  /// Creates a [ContentArticlePage].
  const ContentArticlePage({required this.item, super.key});

  /// The content item to display.
  final ContentItem item;

  @override
  Widget build(BuildContext context) {
    final meta =
        item.metadata is ArticleMeta ? item.metadata! as ArticleMeta : null;
    final body = meta?.body ?? item.description ?? '';
    final readTime = meta?.readTimeMinutes;
    final hasThumbnail = item.thumbnailUrl != null;

    return Scaffold(
      backgroundColor: context.kabukBackground,
      body: CustomScrollView(
        slivers: [
          // Collapsing header image.
          if (hasThumbnail)
            SliverAppBar(
              expandedHeight: 240,
              pinned: true,
              backgroundColor: context.kabukSurface,
              flexibleSpace: FlexibleSpaceBar(
                background: CachedNetworkImage(
                  imageUrl: item.thumbnailUrl!,
                  cacheManager: KabukCacheManager.instance,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const ColoredBox(
                    color: KabukTheme.surfaceVariant,
                  ),
                ),
              ),
            )
          else
            SliverAppBar(
              pinned: true,
              backgroundColor: context.kabukSurface,
            ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(KabukTheme.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title.
                  Text(
                    item.title,
                    style: TextStyle(
                      color: context.kabukTextPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: KabukTheme.spacingSm),

                  // Author + date + read time row.
                  _ArticleMetaRow(
                    author: item.author?.name,
                    publishedAt: item.publishedAt,
                    readTimeMinutes: readTime,
                  ),

                  const SizedBox(height: KabukTheme.spacingLg),

                  // Body.
                  Text(
                    body,
                    style: TextStyle(
                      color: context.kabukTextPrimary,
                      fontSize: 16,
                      height: 1.6,
                    ),
                  ),

                  // Source link.
                  if (item.url != null) ...[
                    const SizedBox(height: KabukTheme.spacingLg),
                    InkWell(
                      onTap: () async {
                        final uri = Uri.parse(item.url!);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      child: Text(
                        'View original',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],

                  // Bottom padding for safe area.
                  SizedBox(
                    height: MediaQuery.paddingOf(context).bottom +
                        KabukTheme.spacingLg,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Author + date + read time row used in the article page.
class _ArticleMetaRow extends StatelessWidget {
  const _ArticleMetaRow({
    this.author,
    this.publishedAt,
    this.readTimeMinutes,
  });

  final String? author;
  final DateTime? publishedAt;
  final int? readTimeMinutes;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      ?author,
      if (publishedAt != null) _formatDate(publishedAt!),
      if (readTimeMinutes != null) '$readTimeMinutes min read',
    ];

    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' · '),
      style: TextStyle(
        color: context.kabukTextSecondary,
        fontSize: 13,
      ),
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
