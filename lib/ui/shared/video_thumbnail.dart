/// Video thumbnail widget with play button overlay.
///
/// Shows a preview image for video content with a centered play icon.
/// Tapping opens the video in a full-screen player or external browser
/// depending on the video URL type.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kabuk/ui/explore/quick_peek_sheet.dart';
import 'package:kabuk/ui/shared/feed_image.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

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
                Container(color: KabukTheme.surfaceVariant),
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
    if (isDirectVideoUrl(videoUrl)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _InlineVideoPlayer(videoUrl: videoUrl),
          fullscreenDialog: true,
        ),
      );
    } else {
      // Try to extract a YouTube video ID for in-app playback.
      final youtubeId = extractYoutubeVideoId(videoUrl);
      if (youtubeId != null) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _YoutubePlayerPage(videoId: youtubeId),
            fullscreenDialog: true,
          ),
        );
      } else {
        // Other external video — open in-app via QuickPeekSheet.
        QuickPeekSheet.show(context, url: videoUrl);
      }
    }
  }
}

/// Full-screen inline video player for direct video URLs.
class _InlineVideoPlayer extends StatefulWidget {
  const _InlineVideoPlayer({required this.videoUrl});

  final String videoUrl;

  @override
  State<_InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<_InlineVideoPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _controller.play();
        }
      }).ignore();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // Never extend behind the appbar — ensures Center aligns the video to
      // the visible, non-occluded portion of the screen.
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
            child: _initialized
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        VideoPlayer(_controller),
                        if (_showControls)
                          _VideoControlsOverlay(controller: _controller),
                      ],
                    ),
                  )
                : const CircularProgressIndicator(color: Colors.white),
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

/// Full-screen YouTube video player using the mobile YouTube website.
///
/// Loads the YouTube mobile watch page in a [WebViewWidget] so the user
/// can watch videos without leaving the app. Uses the full mobile site
/// instead of the embed API to avoid Error 153 issues with WebView.
class _YoutubePlayerPage extends StatefulWidget {
  const _YoutubePlayerPage({required this.videoId});

  final String videoId;

  @override
  State<_YoutubePlayerPage> createState() => _YoutubePlayerPageState();
}

class _YoutubePlayerPageState extends State<_YoutubePlayerPage> {
  late final WebViewController _webController;

  @override
  void initState() {
    super.initState();

    // Use WebKit-specific params on iOS for inline media playback.
    late final PlatformWebViewControllerCreationParams params;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final watchUrl = 'https://m.youtube.com/watch?v=${widget.videoId}';
    _webController = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..loadRequest(Uri.parse(watchUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.black,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      body: WebViewWidget(controller: _webController),
    );
  }
}
