/// Streaming video/audio player view for Usenet content.
///
/// Connects to a [StreamSession]'s local HTTP server and plays the content
/// using `media_kit`. Provides YouTube-style overlay controls for seek,
/// pause/play, fullscreen, and stream management actions (save, open external,
/// stop). Automatically rotates to landscape for wide videos to maximise
/// display area. Falls back to an audio-only layout when the MIME type starts
/// with `audio/`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/knowledge/types/usenet.dart';
import 'package:kabuk/platform/shared/usenet/release_parser.dart';
import 'package:kabuk/services/usenet.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

// =============================================================================
// Usenet Player Page
// =============================================================================

/// Full-screen streaming player for Usenet content.
///
/// Accepts a [StreamSession] whose [StreamSession.localUrl] points to
/// the local HTTP server. Initialises a [Player] + [VideoController]
/// against that URL and shows either a video surface or an audio-only
/// layout depending on [mimeType].
///
/// For landscape videos (aspect ratio > 1.2) the page forces landscape
/// orientation to maximise the visible display area on portrait-locked
/// phones. Portrait and square videos keep the default portrait layout.
class UsenetPlayerPage extends ConsumerStatefulWidget {
  /// Creates a [UsenetPlayerPage].
  const UsenetPlayerPage({
    required this.session,
    super.key,
    this.mimeType,
    this.alternativeSources,
  });

  /// The active streaming session to play.
  final StreamSession session;

  /// Optional MIME type hint (e.g. `video/mp4`, `audio/flac`).
  ///
  /// When the MIME type starts with `audio/` the player renders an
  /// audio-only layout instead of a video surface.
  final String? mimeType;

  /// Alternative NZB releases for the same content.
  ///
  /// When provided, the quality settings sheet shows these as switchable
  /// source options, each parsed with [ReleaseParser] for quality metadata.
  final List<UsenetReleaseData>? alternativeSources;

  @override
  ConsumerState<UsenetPlayerPage> createState() => _UsenetPlayerPageState();
}

class _UsenetPlayerPageState extends ConsumerState<UsenetPlayerPage> {
  Player? _player;
  VideoController? _videoController;
  bool _initialized = false;
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _hasError = false;
  String? _errorMessage;
  Timer? _hideControlsTimer;
  Timer? _sessionPollTimer;

  /// Whether the video's native aspect ratio is landscape (> 1.2).
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

  StreamSession _session = const StreamSession(
    id: '',
    nzbTitle: '',
    localUrl: '',
    bytesStreamed: 0,
    totalBytes: 0,
    state: StreamState.buffering,
  );

  bool get _isAudio => widget.mimeType?.startsWith('audio/') ?? false;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _startSessionPolling();
    _waitForReadyThenInit();
  }

  /// Polls the stream server until the pipeline is ready, then initialises
  /// the video controller. This prevents the player from hitting 503
  /// responses during the initial buffering phase.
  Future<void> _waitForReadyThenInit() async {
    const pollInterval = Duration(seconds: 1);
    const maxWait = Duration(minutes: 2);
    final deadline = DateTime.now().add(maxWait);

    while (mounted && DateTime.now().isBefore(deadline)) {
      final usenet = ref.read(usenetServiceProvider);
      final streams = await usenet.getActiveStreams();
      final session =
          streams.where((s) => s.id == widget.session.id).firstOrNull;

      if (session != null) {
        setState(() => _session = session);

        if (session.state == StreamState.error) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Stream failed during buffering';
          });
          return;
        }

        if (session.state == StreamState.playing ||
            session.state == StreamState.paused) {
          await _initController();
          return;
        }
      }

      await Future<void>.delayed(pollInterval);
    }

    // Timed out waiting.
    if (mounted) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Stream timed out waiting for buffer';
      });
    }
  }

  Future<void> _initController() async {
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
          if (ar > 1.2 && !_isAudio) {
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
      await player.open(Media(widget.session.localUrl));
      if (!mounted) return;

      setState(() => _initialized = true);
      _scheduleHideControls();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load stream: $e';
      });
    }
  }

  void _startSessionPolling() {
    _sessionPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollSession(),
    );
  }

  Future<void> _pollSession() async {
    final usenet = ref.read(usenetServiceProvider);
    final streams = await usenet.getActiveStreams();
    final updated =
        streams.where((s) => s.id == widget.session.id).firstOrNull;
    if (updated != null && mounted) {
      setState(() => _session = updated);
      if (updated.state == StreamState.error) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Stream Error';
        });
      }
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _sessionPollTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferSub?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _widthSub?.cancel();
    _player?.dispose();
    // Always restore orientation and system UI on exit.
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Controls visibility
  // ---------------------------------------------------------------------------

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  // ---------------------------------------------------------------------------
  // Fullscreen
  // ---------------------------------------------------------------------------

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await _exitFullscreen();
    } else {
      await _enterFullscreen();
    }
    setState(() => _isFullscreen = !_isFullscreen);
  }

  Future<void> _enterFullscreen() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _exitFullscreen() async {
    // Landscape videos stay in landscape but regain system UI.
    // Portrait videos return to portrait orientation.
    if (_isLandscapeVideo) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

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

  Future<void> _retry() async {
    setState(() {
      _hasError = false;
      _errorMessage = null;
      _initialized = false;
    });
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferSub?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _widthSub?.cancel();
    _isLandscapeVideo = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _bufferPosition = Duration.zero;
    _isPlaying = false;
    _isBuffering = false;
    await _player?.dispose();
    _player = null;
    _videoController = null;
    await _waitForReadyThenInit();
  }

  Future<void> _openExternal() async {
    final uri = Uri.parse(widget.session.localUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _stopStream() async {
    final usenet = ref.read(usenetServiceProvider);
    await usenet.stopStream(widget.session.id);
    if (mounted) Navigator.of(context).pop();
  }

  void _showQualitySettings() {
    const parser = ReleaseParser();
    final currentQuality = parser.parse(_session.nzbTitle);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _QualitySettingsSheet(
        currentTitle: _session.nzbTitle,
        currentQuality: currentQuality,
        totalBytes: _session.totalBytes,
        alternativeSources: widget.alternativeSources,
        onSourceSelected: _switchSource,
      ),
    );
  }

  Future<void> _switchSource(UsenetReleaseData source) async {
    Navigator.of(context).pop(); // dismiss the sheet
    final usenet = ref.read(usenetServiceProvider);

    // Stop current stream.
    await usenet.stopStream(widget.session.id);

    // Fetch and start new stream.
    final nzbUrl = source.nzbUrl;
    if (nzbUrl == null || !mounted) return;

    final nzbResult = await usenet.fetchNzb(nzbUrl);
    if (!mounted) return;

    if (nzbResult case Success(:final value)) {
      final streamResult = await usenet.startStream(value);
      if (!mounted) return;
      if (streamResult case Success(:final value)) {
        // Replace the current player with the new session.
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => UsenetPlayerPage(
              session: value,
              mimeType: widget.mimeType,
              alternativeSources: widget.alternativeSources,
            ),
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isAudio ? _buildAudioScaffold() : _buildVideoScaffold(),
    );
  }

  // ---------------------------------------------------------------------------
  // Video scaffold — fills entire screen, controls are an overlay
  // ---------------------------------------------------------------------------

  Widget _buildVideoScaffold() {
    if (_hasError) {
      return SafeArea(
        child: Column(
          children: [
            Expanded(child: _ErrorView(message: _errorMessage, onRetry: _retry)),
            _BottomInfoBar(session: _session),
            _ActionBar(
              onSave: () {},
              onOpenExternal: _openExternal,
              onStop: _stopStream,
            ),
          ],
        ),
      );
    }

    if (!_initialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 12),
            Text(
              'Buffering stream…',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _toggleControls,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video surface — media_kit handles aspect ratio internally.
          Center(
            child: Video(
              controller: _videoController!,
              controls: (state) => const SizedBox.shrink(),
            ),
          ),

          // Buffering spinner.
          if (_isBuffering)
            const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),

          // YouTube-style controls overlay with fade animation.
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: _YouTubeControlsOverlay(
                title: _session.nzbTitle,
                isFullscreen: _isFullscreen,
                isPlaying: _isPlaying,
                position: _position,
                duration: _duration,
                bufferedProgress: _bufferedProgress,
                onBack: () => Navigator.of(context).pop(),
                onPlayPause: _togglePlayPause,
                onFullscreen: _toggleFullscreen,
                onSeek: (d) => _player?.seek(d),
                onSettings: _showQualitySettings,
              ),
            ),
          ),

          // Bottom info bar + action bar (below video, only when controls
          // visible and NOT fullscreen).
          if (_showControls && !_isFullscreen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BottomInfoBar(session: _session),
                  _ActionBar(
                    onSave: () {},
                    onOpenExternal: _openExternal,
                    onStop: _stopStream,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Audio scaffold
  // ---------------------------------------------------------------------------

  Widget _buildAudioScaffold() {
    if (_hasError) {
      return SafeArea(
        child: Column(
          children: [
            Expanded(child: _ErrorView(message: _errorMessage, onRetry: _retry)),
            _BottomInfoBar(session: _session),
            _ActionBar(
              onSave: () {},
              onOpenExternal: _openExternal,
              onStop: _stopStream,
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          // Top bar with back button.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Audio content.
          Expanded(
            child: GestureDetector(
              onTap: _toggleControls,
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Album art placeholder.
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: KabukTheme.surfaceVariant,
                      borderRadius:
                          BorderRadius.circular(KabukTheme.radiusXl),
                    ),
                    child: const Icon(
                      Icons.music_note_rounded,
                      size: 80,
                      color: KabukTheme.accentGreen,
                    ),
                  ),
                  const SizedBox(height: KabukTheme.spacingLg),

                  // Title.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _session.nzbTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: KabukTheme.spacingXl),

                  // Seek bar + time + play/pause.
                  if (_initialized) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: _VideoSeekBar(
                        position: _position,
                        duration: _duration,
                        bufferedProgress: _bufferedProgress,
                        onSeek: (d) => _player?.seek(d),
                      ),
                    ),
                    const SizedBox(height: KabukTheme.spacingSm),
                    _TimeRow(position: _position, duration: _duration),
                    const SizedBox(height: KabukTheme.spacingLg),
                    IconButton(
                      iconSize: 64,
                      icon: Icon(
                        _isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_filled_rounded,
                        color: Colors.white,
                      ),
                      onPressed: _togglePlayPause,
                    ),
                  ] else
                    const CircularProgressIndicator(color: Colors.white),
                ],
              ),
            ),
          ),

          // Bottom info + actions.
          _BottomInfoBar(session: _session),
          _ActionBar(
            onSave: () {},
            onOpenExternal: _openExternal,
            onStop: _stopStream,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// YouTube-style Controls Overlay
// =============================================================================

/// Polished YouTube-style overlay with gradient bars, centred play/pause,
/// custom seek bar, time display, and fullscreen toggle.
class _YouTubeControlsOverlay extends StatelessWidget {
  const _YouTubeControlsOverlay({
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
    this.onSettings,
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
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Scrim behind controls so they remain legible.
        Container(color: Colors.black.withAlpha(60)),

        // Top gradient bar — back, title, overflow menu.
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
                    IconButton(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Centre play/pause button with a semi-transparent circle.
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

        // Bottom gradient bar — seek bar, time, fullscreen.
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
                    _VideoSeekBar(
                      position: position,
                      duration: duration,
                      bufferedProgress: bufferedProgress,
                      onSeek: onSeek,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _TimeRow(position: position, duration: duration),
                        const Spacer(),
                        if (onSettings != null)
                          IconButton(
                            icon: const Icon(
                              Icons.settings,
                              color: Colors.white,
                              size: 22,
                            ),
                            onPressed: onSettings,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
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
// Quality Settings Bottom Sheet
// =============================================================================

/// YouTube-style quality/source picker shown from the gear icon.
///
/// Displays the current stream's parsed quality metadata and, when
/// [alternativeSources] is provided, a list of switchable sources sorted
/// by quality score.
class _QualitySettingsSheet extends StatelessWidget {
  const _QualitySettingsSheet({
    required this.currentTitle,
    required this.currentQuality,
    required this.totalBytes,
    this.alternativeSources,
    this.onSourceSelected,
  });

  final String currentTitle;
  final ReleaseQuality currentQuality;
  final int totalBytes;
  final List<UsenetReleaseData>? alternativeSources;
  final ValueChanged<UsenetReleaseData>? onSourceSelected;

  @override
  Widget build(BuildContext context) {
    const parser = ReleaseParser();
    final sources = alternativeSources ?? [];

    // Parse and sort alternatives by quality score descending.
    final parsed = sources.map((s) {
      final q = parser.parse(s.title ?? '');
      return (release: s, quality: q);
    }).toList()
      ..sort((a, b) => b.quality.score.compareTo(a.quality.score));

    return Container(
      decoration: BoxDecoration(
        color: context.kabukSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusLg),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.kabukTextTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Quality',
                style: TextStyle(
                  color: context.kabukTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            const Divider(height: 1),

            // Current quality — highlighted
            _QualityTile(
              label: currentQuality.label,
              isSelected: true,
              subtitle: 'Current · ${_formatBytes(totalBytes)}',
            ),

            // Alternative sources
            if (parsed.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Sources',
                  style: TextStyle(
                    color: context.kabukTextSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ...parsed.map(
                (entry) => _QualityTile(
                  label: entry.quality.label,
                  isSelected: false,
                  subtitle: _sourceSubtitle(entry.release, entry.quality),
                  onTap: () => onSourceSelected?.call(entry.release),
                ),
              ),
            ],

            // Extra info section
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _InfoRow(
                label: 'Audio',
                value: currentQuality.audio ?? 'Unknown',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: _InfoRow(
                label: 'Size',
                value: _formatBytes(totalBytes),
              ),
            ),
            if (currentQuality.group != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: _InfoRow(
                  label: 'Group',
                  value: currentQuality.group!,
                ),
              ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _sourceSubtitle(UsenetReleaseData release, ReleaseQuality quality) {
    final parts = <String>[];
    if (release.sizeBytes != null) {
      parts.add(_formatBytes(release.sizeBytes!));
    }
    if (quality.group != null) parts.add(quality.group!);
    return parts.isEmpty ? '' : parts.join(' · ');
  }
}

/// A single row in the quality picker list.
class _QualityTile extends StatelessWidget {
  const _QualityTile({
    required this.label,
    required this.isSelected,
    this.subtitle,
    this.onTap,
  });

  final String label;
  final bool isSelected;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: isSelected
                  ? KabukTheme.primaryGreen
                  : context.kabukTextTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? KabukTheme.primaryGreen
                          : context.kabukTextPrimary,
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: context.kabukTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Key-value info row for the bottom section.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.kabukTextSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: context.kabukTextPrimary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Custom Seek Bar
// =============================================================================

/// Custom YouTube-style seek bar with buffered progress, played progress,
/// and a draggable white thumb.
class _VideoSeekBar extends StatefulWidget {
  const _VideoSeekBar({
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
  State<_VideoSeekBar> createState() => _VideoSeekBarState();
}

class _VideoSeekBarState extends State<_VideoSeekBar> {
  bool _dragging = false;
  double _dragValue = 0;

  static const double _trackHeight = 4;
  static const double _thumbRadius = 7;
  static const double _touchTargetHeight = 32;

  double _progressFor(Duration position, Duration duration) {
    if (duration.inMilliseconds == 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  void _seekToRelative(double relative) {
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
      onHorizontalDragStart: (details) {
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
        _seekToRelative(_dragValue);
        setState(() => _dragging = false);
      },
      onHorizontalDragCancel: () => setState(() => _dragging = false),
      onTapUp: (details) {
        final box = context.findRenderObject()! as RenderBox;
        final relative =
            (details.localPosition.dx / box.size.width).clamp(0.0, 1.0);
        _seekToRelative(relative);
      },
      child: SizedBox(
        height: _touchTargetHeight,
        child: CustomPaint(
          painter: _SeekBarPainter(
            played: played,
            buffered: buffered,
            trackHeight: _trackHeight,
            thumbRadius: _dragging ? _thumbRadius + 2 : _thumbRadius,
            playedColor: KabukTheme.primaryGreen,
            bufferedColor: Colors.white30,
            backgroundColor: Colors.white12,
            thumbColor: Colors.white,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Custom painter for the three-layer seek bar + thumb.
class _SeekBarPainter extends CustomPainter {
  _SeekBarPainter({
    required this.played,
    required this.buffered,
    required this.trackHeight,
    required this.thumbRadius,
    required this.playedColor,
    required this.bufferedColor,
    required this.backgroundColor,
    required this.thumbColor,
  });

  final double played;
  final double buffered;
  final double trackHeight;
  final double thumbRadius;
  final Color playedColor;
  final Color bufferedColor;
  final Color backgroundColor;
  final Color thumbColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, cy - trackHeight / 2, size.width, trackHeight),
      Radius.circular(trackHeight / 2),
    );

    // Background track.
    canvas.drawRRect(trackRect, Paint()..color = backgroundColor);

    // Buffered track.
    if (buffered > 0) {
      final bufferedWidth = size.width * buffered;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, cy - trackHeight / 2, bufferedWidth, trackHeight),
          Radius.circular(trackHeight / 2),
        ),
        Paint()..color = bufferedColor,
      );
    }

    // Played track.
    if (played > 0) {
      final playedWidth = size.width * played;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, cy - trackHeight / 2, playedWidth, trackHeight),
          Radius.circular(trackHeight / 2),
        ),
        Paint()..color = playedColor,
      );
    }

    // Thumb.
    final thumbX = (size.width * played).clamp(thumbRadius, size.width - thumbRadius);
    canvas.drawCircle(
      Offset(thumbX, cy),
      thumbRadius,
      Paint()..color = thumbColor,
    );
  }

  @override
  bool shouldRepaint(_SeekBarPainter old) =>
      played != old.played ||
      buffered != old.buffered ||
      thumbRadius != old.thumbRadius;
}

// =============================================================================
// Time Row
// =============================================================================

/// Displays `position / duration` text.
class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${_formatDuration(position)} / '
      '${_formatDuration(duration)}',
      style: const TextStyle(color: Colors.white70, fontSize: 12),
    );
  }
}

// =============================================================================
// Bottom Info Bar
// =============================================================================

/// Shows stream title, download progress, and state indicator.
class _BottomInfoBar extends StatelessWidget {
  const _BottomInfoBar({required this.session});

  final StreamSession session;

  @override
  Widget build(BuildContext context) {
    final downloadPercent = session.totalBytes > 0
        ? (session.bytesDownloaded / session.totalBytes * 100).clamp(0, 100)
        : 0.0;
    final downloadedText = _formatBytes(session.bytesDownloaded);
    final totalText = _formatBytes(session.totalBytes);
    final streamedText = _formatBytes(session.bytesStreamed);

    final statusText = switch (session.state) {
      StreamState.buffering =>
        'Buffering: ${downloadPercent.toStringAsFixed(0)}% '
            '($downloadedText / $totalText)',
      _ =>
        'Streaming: $streamedText / $totalText | '
            'Downloaded: ${downloadPercent.toStringAsFixed(0)}%',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: context.kabukSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            session.nzbTitle,
            style: TextStyle(
              color: context.kabukTextPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: context.kabukTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              _StateChip(state: session.state),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// State Chip
// =============================================================================

/// Small colored chip representing the current [StreamState].
class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final StreamState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      StreamState.buffering => ('Buffering', KabukTheme.warmAccent),
      StreamState.playing => ('Playing', KabukTheme.success),
      StreamState.paused => ('Paused', KabukTheme.textSecondary),
      StreamState.seeking => ('Seeking', KabukTheme.blueAccent),
      StreamState.stopped => ('Stopped', KabukTheme.textTertiary),
      StreamState.error => ('Error', KabukTheme.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// =============================================================================
// Action Bar
// =============================================================================

/// Bottom action buttons for save, open external, and stop.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onSave,
    required this.onOpenExternal,
    required this.onStop,
  });

  final VoidCallback onSave;
  final VoidCallback onOpenExternal;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      color: context.kabukSurface,
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save_alt_rounded, size: 18),
              label: const Text('Save'),
              style: FilledButton.styleFrom(
                backgroundColor: KabukTheme.primaryGreen,
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onOpenExternal,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('External'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Stop'),
              style: OutlinedButton.styleFrom(
                foregroundColor: KabukTheme.error,
                side: const BorderSide(color: KabukTheme.error, width: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Error View
// =============================================================================

/// Centered error with optional retry.
class _ErrorView extends StatelessWidget {
  const _ErrorView({this.message, this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
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
              message ?? 'Stream Error',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(
                  backgroundColor: KabukTheme.primaryGreen,
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
// Helpers
// =============================================================================

/// Formats a [Duration] as `MM:SS` or `H:MM:SS` for longer content.
String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}

/// Formats [bytes] as a human-readable size string.
String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  return unitIndex == 0
      ? '${value.toInt()} ${units[unitIndex]}'
      : '${value.toStringAsFixed(value < 10 ? 2 : 1)} ${units[unitIndex]}';
}
