/// Video thumbnail widget with play button overlay.
///
/// Shows a preview image for video content with a centered play icon.
/// Tapping opens the video in a full-screen native player that resolves
/// YouTube streams via youtube_explode_dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kabuk/ui/shared/feed_image.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Whether a URL points to a directly playable video file.
bool isDirectVideoUrl(String url) {
  final lower = url.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.m3u8') ||
      lower.contains('v.redd.it') ||
      lower.contains('/DASH_');
}

/// Extracts the YouTube video ID from a [url], or `null` if not a YouTube URL.
///
/// Supports these URL forms:
/// - `https://www.youtube.com/watch?v=VIDEOID`
/// - `https://youtu.be/VIDEOID`
/// - `https://m.youtube.com/watch?v=VIDEOID`
/// - `https://youtube.com/shorts/VIDEOID`
String? extractYoutubeVideoId(String url) {
  try {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();
    if (!host.contains('youtube.com') && !host.contains('youtu.be')) {
      return null;
    }
    if (host.contains('youtu.be')) {
      final id = uri.pathSegments.firstOrNull;
      return id?.isNotEmpty == true ? id : null;
    }
    // youtube.com/watch?v=ID or youtube.com/shorts/ID
    var id = uri.queryParameters['v'];
    if (id != null && id.isNotEmpty) return id;
    if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'shorts') {
      id = uri.pathSegments[1];
      return id.isNotEmpty ? id : null;
    }
    return null;
  } on Object {
    return null;
  }
}

/// A thumbnail image with play button overlay for video posts.
///
/// If a [thumbnailUrl] is available, shows it with a play icon.
/// Tapping opens the video — either inline for direct URLs, or
/// in an external browser for YouTube/external links.
class VideoThumbnail extends StatelessWidget {
  /// Creates a [VideoThumbnail].
  const VideoThumbnail({
    required this.videoUrl,
    super.key,
    this.thumbnailUrl,
    this.height = 220,
    this.borderRadius,
  });

  /// The URL of the video content.
  final String videoUrl;

  /// Optional thumbnail / preview image URL.
  final String? thumbnailUrl;

  /// Height of the thumbnail. Defaults to 220.
  final double height;

  /// Border radius for clipping.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openVideo(context),
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background: thumbnail image or dark placeholder.
              if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
                FeedImage(
                  imageUrl: thumbnailUrl!,
                  height: height,
                  fit: BoxFit.cover,
                )
              else
                Container(color: context.kabukSurfaceVariant),
              // Dark overlay.
              Container(color: Colors.black.withAlpha(80)),
              // Play button.
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withAlpha(200),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
              // Video badge.
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(160),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.videocam_rounded,
                        color: Colors.white70,
                        size: 14,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'VIDEO',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openVideo(BuildContext context) {
    // All videos go through the native player — it resolves YouTube
    // streams via youtube_explode_dart at playback time.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _NativeVideoPlayer(videoUrl: videoUrl),
        fullscreenDialog: true,
      ),
    );
  }
}

/// Unified full-screen native video player.
///
/// Handles all video types:
/// - Direct URLs (MP4, WebM, HLS) → plays immediately via [VideoPlayerController]
/// - YouTube URLs → resolves direct stream via `youtube_explode_dart`, then plays natively
/// - Other URLs → attempts direct playback
class _NativeVideoPlayer extends StatefulWidget {
  const _NativeVideoPlayer({required this.videoUrl});

  final String videoUrl;

  @override
  State<_NativeVideoPlayer> createState() => _NativeVideoPlayerState();
}

class _NativeVideoPlayerState extends State<_NativeVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _showControls = true;
  String? _error;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final youtubeId = extractYoutubeVideoId(widget.videoUrl);
    if (youtubeId != null) {
      // Resolve YouTube stream URL via youtube_explode.
      setState(() => _resolving = true);
      try {
        final yt = YoutubeExplode();
        try {
          final manifest = await yt.videos.streamsClient.getManifest(youtubeId);
          // Prefer muxed streams (video+audio) for simplicity.
          final muxed = manifest.muxed.sortByVideoQuality();
          if (muxed.isNotEmpty) {
            _startPlayback(muxed.last.url.toString());
          } else {
            // Fall back to video-only stream.
            final videoOnly = manifest.videoOnly.sortByVideoQuality();
            if (videoOnly.isNotEmpty) {
              _startPlayback(videoOnly.last.url.toString());
            } else {
              if (mounted) setState(() => _error = 'No playable stream found');
            }
          }
        } finally {
          yt.close();
        }
      } on Object catch (e) {
        if (mounted) {
          setState(() => _error = 'Could not load video: $e');
        }
      }
    } else {
      // Direct URL — resolve v.redd.it if needed, then play.
      var url = widget.videoUrl;
      if (url.contains('v.redd.it') &&
          !url.contains('HLSPlaylist') &&
          !url.contains('DASHPlaylist') &&
          !url.contains('DASH_') &&
          !url.toLowerCase().endsWith('.mp4') &&
          !url.toLowerCase().endsWith('.m3u8')) {
        if (url.endsWith('/')) url = url.substring(0, url.length - 1);
        url = '$url/HLSPlaylist.m3u8';
      }
      _startPlayback(url);
    }
  }

  void _startPlayback(String url) {
    if (!mounted) return;
    setState(() => _resolving = false);
    _controller = VideoPlayerController.networkUrl(Uri.parse(url))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _controller?.play();
        }
      }).catchError((Object e) {
        if (mounted) setState(() => _error = 'Playback error: $e');
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: false,
      appBar: _showControls
          ? AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              elevation: 0,
              systemOverlayStyle: const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
              ),
            )
          : null,
      body: GestureDetector(
        onTap: _toggleControls,
        child: SizedBox.expand(
          child: Center(
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.white54, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : _initialized && _controller != null
                    ? AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            VideoPlayer(_controller!),
                            if (_showControls)
                              _VideoControlsOverlay(controller: _controller!),
                          ],
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          if (_resolving) ...[
                            const SizedBox(height: 12),
                            const Text(
                              'Resolving video stream…',
                              style: TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          ],
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}

/// Simple video controls overlay with play/pause and progress.
class _VideoControlsOverlay extends StatelessWidget {
  const _VideoControlsOverlay({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (_, value, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withAlpha(180)],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: () {
                  value.isPlaying ? controller.pause() : controller.play();
                },
              ),
              Expanded(
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: KabukTheme.accentGreen,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(value.position),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
