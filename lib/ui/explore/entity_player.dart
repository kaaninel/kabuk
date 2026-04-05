/// Entity-centric streaming player for movies and TV episodes.
///
/// Shows entity metadata (poster, title, year) during buffering — not NZB
/// file details. Internally uses [StreamOrchestrator] for automatic source
/// selection and fallback. Provides a YouTube-like quality picker.
library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/streaming_prefs.dart';
import 'package:kabuk/platform/shared/usenet/usenet_resolver.dart';
import 'package:kabuk/services/usenet.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// =============================================================================
// Entity info passed to the player
// =============================================================================

/// Minimal entity info for display during buffering.
@immutable
class PlayableEntity {
  const PlayableEntity({
    required this.title,
    this.subtitle,
    this.year,
    this.posterUrl,
    this.backdropUrl,
    this.overview,
    this.imdbId,
    this.tvdbId,
    this.season,
    this.episode,
    this.episodeTitle,
  });

  final String title;
  final String? subtitle;
  final int? year;
  final String? posterUrl;
  final String? backdropUrl;
  final String? overview;
  final String? imdbId;
  final int? tvdbId;
  final int? season;
  final int? episode;
  final String? episodeTitle;

  /// Whether this is a TV episode (has season/episode).
  bool get isTvEpisode => season != null && episode != null;

  /// Display label like "S02E05 · Episode Title".
  String get displaySubtitle {
    if (isTvEpisode) {
      final se = 'S${season!.toString().padLeft(2, '0')}'
          'E${episode!.toString().padLeft(2, '0')}';
      if (episodeTitle != null) return '$se · $episodeTitle';
      return se;
    }
    if (subtitle != null) return subtitle!;
    if (year != null) return '$year';
    return '';
  }
}

// =============================================================================
// Entity Player Page
// =============================================================================

/// Netflix/YouTube-like player that takes an entity and handles everything.
///
/// Flow:
/// 1. Shows entity poster/backdrop + "Finding best source..."
/// 2. Orchestrator resolves, ranks, and starts the best NZB
/// 3. Shows buffering progress with quality info
/// 4. Plays video when ready
/// 5. On failure, auto-retries with next-best source
/// 6. Gear icon → quality picker with all available sources
class EntityPlayerPage extends ConsumerStatefulWidget {
  const EntityPlayerPage({
    required this.entity,
    super.key,
  });

  final PlayableEntity entity;

  @override
  ConsumerState<EntityPlayerPage> createState() => _EntityPlayerPageState();
}

class _EntityPlayerPageState extends ConsumerState<EntityPlayerPage> {
  // -- Player state --
  Player? _player;
  VideoController? _videoController;
  bool _initialized = false;
  bool _isPlaying = false;
  bool _isBuffering = true;
  bool _isFullscreen = false;
  bool _isLandscapeVideo = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _bufferPosition = Duration.zero;
  bool _controlsVisible = true;
  Timer? _hideControlsTimer;

  // -- Subscriptions --
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<int?>? _widthSub;
  StreamSubscription<OrchestratorEvent>? _orchestratorSub;

  // -- Orchestrator state --
  StreamOrchestrator? _orchestrator;
  _OrchestratorPhase _phase = _OrchestratorPhase.resolving;
  String _statusMessage = 'Finding best source...';
  ResolvedSource? _activeSource;
  List<ResolvedSource> _allSources = [];
  bool _hasError = false;
  String _errorMessage = '';
  int _retryCount = 0;

  PlayableEntity get _entity => widget.entity;

  @override
  void initState() {
    super.initState();
    _startOrchestrator();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferSub?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _widthSub?.cancel();
    _orchestratorSub?.cancel();
    _player?.dispose();
    // Restore orientation on exit.
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Orchestrator
  // ---------------------------------------------------------------------------

  Future<void> _startOrchestrator() async {
    final orchestrator = ref.read(streamOrchestratorProvider);
    _orchestrator = orchestrator;

    // Listen to orchestrator events.
    _orchestratorSub = orchestrator.events.listen(_onOrchestratorEvent);

    // Load preferences.
    final prefsAsync = await ref.read(streamingPrefsProvider.future);
    final prefs = prefsAsync;

    if (_entity.isTvEpisode) {
      await orchestrator.playTvEpisode(
        tvdbId: _entity.tvdbId,
        seriesTitle: _entity.title,
        season: _entity.season,
        episode: _entity.episode,
        prefs: prefs,
      );
    } else {
      await orchestrator.playMovie(
        imdbId: _entity.imdbId,
        title: _entity.title,
        year: _entity.year,
        prefs: prefs,
      );
    }
  }

  void _onOrchestratorEvent(OrchestratorEvent event) {
    if (!mounted) return;

    switch (event) {
      case OrchestratorResolving(:final entity):
        setState(() {
          _phase = _OrchestratorPhase.resolving;
          _statusMessage = 'Searching for "$entity"...';
        });

      case OrchestratorSourcesFound(:final sources, :final selected):
        setState(() {
          _allSources = sources;
          _activeSource = selected;
          _phase = _OrchestratorPhase.fetching;
          _statusMessage = 'Found ${sources.length} sources';
        });

      case OrchestratorFetchingNzb(:final source):
        setState(() {
          _activeSource = source;
          _phase = _OrchestratorPhase.fetching;
          _statusMessage = 'Loading ${source.label}...';
        });

      case OrchestratorBuffering(:final source, :final percent):
        setState(() {
          _phase = _OrchestratorPhase.buffering;
          _statusMessage =
              'Buffering ${source.label}... ${(percent * 100).toInt()}%';
        });

      case OrchestratorPlaying(:final session, :final source, :final allSources):
        setState(() {
          _activeSource = source;
          _allSources = allSources;
          _phase = _OrchestratorPhase.playing;
          _statusMessage = 'Playing ${source.label}';
        });
        _initPlayer(session);

      case OrchestratorRetrying(
          :final reason,
          :final nextSource,
          :final attempt,
          :final maxAttempts,
        ):
        setState(() {
          _retryCount = attempt - 1;
          _phase = _OrchestratorPhase.retrying;
          _statusMessage =
              'Trying ${nextSource.label}... (attempt $attempt/$maxAttempts)';
        });

      case OrchestratorFailed(:final message, :final triedCount):
        setState(() {
          _hasError = true;
          _errorMessage = message;
          _phase = _OrchestratorPhase.failed;
          _statusMessage = 'Failed after trying $triedCount sources';
        });
    }
  }

  // ---------------------------------------------------------------------------
  // Player init
  // ---------------------------------------------------------------------------

  Future<void> _initPlayer(StreamSession session) async {
    final player = Player();
    final videoController = VideoController(player);
    _player = player;
    _videoController = videoController;

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
      if (mounted && e.isNotEmpty) {
        final lower = e.toLowerCase();
        if (lower.contains('audio device') ||
            lower.contains('no sound') ||
            lower.contains('ao init')) {
          dev.log('EntityPlayer: ignoring audio warning: $e');
          return;
        }
      }
    });
    _widthSub = player.stream.width.listen((w) {
      if (w != null && w > 0 && mounted && !_isLandscapeVideo) {
        final h = player.state.height ?? 1;
        if (h > 0 && w / h > 1.2) {
          _isLandscapeVideo = true;
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          setState(() => _isFullscreen = true);
        }
      }
    });

    try {
      await player.open(Media(session.localUrl));
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _isBuffering = false;
      });
      _scheduleHideControls();
    } on Object catch (e) {
      dev.log('EntityPlayer: player.open failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------------

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHideControls();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _togglePlayPause() {
    final player = _player;
    if (player == null) return;
    player.playOrPause();
    _scheduleHideControls();
  }

  void _seekRelative(Duration offset) {
    final player = _player;
    if (player == null) return;
    final target = _position + offset;
    player.seek(target);
    _scheduleHideControls();
  }

  // ---------------------------------------------------------------------------
  // Quality picker
  // ---------------------------------------------------------------------------

  void _showQualityPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _QualityPickerSheet(
        sources: _allSources,
        activeSource: _activeSource,
        onSourceSelected: _switchToSource,
      ),
    );
  }

  Future<void> _switchToSource(ResolvedSource source) async {
    Navigator.of(context).pop(); // Dismiss sheet.
    if (source == _activeSource) return;

    setState(() {
      _initialized = false;
      _phase = _OrchestratorPhase.fetching;
      _statusMessage = 'Switching to ${source.label}...';
    });

    // Clean up old player.
    await _player?.dispose();
    _player = null;
    _videoController = null;

    final prefs = await ref.read(streamingPrefsProvider.future);
    await _orchestrator?.switchSource(source, prefs);
  }

  Future<void> _retryLowerQuality() async {
    setState(() {
      _hasError = false;
      _phase = _OrchestratorPhase.resolving;
      _statusMessage = 'Trying lower quality...';
    });

    // Re-run orchestrator with relaxed prefs.
    final prefs = await ref.read(streamingPrefsProvider.future);
    final relaxed = prefs.copyWith(
      resolution: PreferredResolution.any,
      hdr: HdrPreference.any,
      maxFileSizeMb: 0,
    );

    final orchestrator = ref.read(streamOrchestratorProvider);
    _orchestrator = orchestrator;
    _orchestratorSub?.cancel();
    _orchestratorSub = orchestrator.events.listen(_onOrchestratorEvent);

    if (_entity.isTvEpisode) {
      await orchestrator.playTvEpisode(
        tvdbId: _entity.tvdbId,
        seriesTitle: _entity.title,
        season: _entity.season,
        episode: _entity.episode,
        prefs: relaxed,
      );
    } else {
      await orchestrator.playMovie(
        imdbId: _entity.imdbId,
        title: _entity.title,
        year: _entity.year,
        prefs: relaxed,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Playing state — show video.
    if (_initialized && _videoController != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video surface.
              Center(child: Video(controller: _videoController!)),

              // Controls overlay.
              if (_controlsVisible) ...[
                _buildGradientOverlay(),
                _buildTopBar(theme, cs),
                _buildCenterControls(cs),
                _buildBottomControls(theme, cs),
              ],

              // Buffering indicator over video.
              if (_isBuffering)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white70),
                ),
            ],
          ),
        ),
      );
    }

    // Pre-play state — show entity info + status.
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildPrePlayScreen(theme, cs),
    );
  }

  // ---------------------------------------------------------------------------
  // Pre-play screen (entity poster + status)
  // ---------------------------------------------------------------------------

  Widget _buildPrePlayScreen(ThemeData theme, ColorScheme cs) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Backdrop image.
        if (_entity.backdropUrl != null)
          Positioned.fill(
            child: Image.network(
              _entity.backdropUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),

        // Dark overlay.
        Container(color: Colors.black.withValues(alpha: 0.75)),

        // Content.
        SafeArea(
          child: Column(
            children: [
              // Close button.
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),

              const Spacer(),

              // Entity info.
              if (_entity.posterUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _entity.posterUrl!,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                _entity.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              if (_entity.displaySubtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _entity.displaySubtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 32),

              // Status.
              if (_hasError)
                _buildErrorState(theme, cs)
              else
                _buildLoadingState(theme, cs),

              const Spacer(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState(ThemeData theme, ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _statusMessage,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
        if (_activeSource != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _activeSource!.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white60,
              ),
            ),
          ),
        ],
        if (_retryCount > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Attempt ${_retryCount + 1}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white38,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorState(ThemeData theme, ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, color: cs.error, size: 48),
        const SizedBox(height: 12),
        Text(
          _errorMessage,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _retryLowerQuality,
          icon: const Icon(Icons.refresh),
          label: const Text('Try Lower Quality'),
          style: FilledButton.styleFrom(
            backgroundColor: cs.primary,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Go Back', style: TextStyle(color: Colors.white54)),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Video overlay widgets
  // ---------------------------------------------------------------------------

  Widget _buildGradientOverlay() {
    return Column(
      children: [
        Container(
          height: 100,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black54, Colors.transparent],
            ),
          ),
        ),
        const Spacer(),
        Container(
          height: 120,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black54, Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(ThemeData theme, ColorScheme cs) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _entity.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_entity.displaySubtitle.isNotEmpty)
                      Text(
                        _entity.displaySubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white60,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Quality badge.
              if (_activeSource != null)
                GestureDetector(
                  onTap: _showQualityPicker,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white38),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _activeSource!.quality.resolution ?? 'HD',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white70),
                onPressed: _showQualityPicker,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterControls(ColorScheme cs) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.replay_10, size: 36, color: Colors.white70),
            onPressed: () => _seekRelative(const Duration(seconds: -10)),
          ),
          const SizedBox(width: 24),
          Container(
            decoration: BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: IconButton(
              iconSize: 48,
              icon: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              onPressed: _togglePlayPause,
            ),
          ),
          const SizedBox(width: 24),
          IconButton(
            icon:
                const Icon(Icons.forward_30, size: 36, color: Colors.white70),
            onPressed: () => _seekRelative(const Duration(seconds: 30)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(ThemeData theme, ColorScheme cs) {
    final posMs = _position.inMilliseconds.toDouble();
    final durMs = _duration.inMilliseconds.toDouble();
    final bufMs = _bufferPosition.inMilliseconds.toDouble();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress bar.
              Stack(
                children: [
                  // Buffer progress.
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: SliderComponentShape.noThumb,
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: Colors.white24,
                      inactiveTrackColor: Colors.white10,
                    ),
                    child: Slider(
                      value: durMs > 0
                          ? (bufMs / durMs).clamp(0.0, 1.0)
                          : 0.0,
                      onChanged: (_) {},
                    ),
                  ),
                  // Playback progress.
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: cs.primary,
                      inactiveTrackColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: durMs > 0
                          ? (posMs / durMs).clamp(0.0, 1.0)
                          : 0.0,
                      onChanged: (v) {
                        final target =
                            Duration(milliseconds: (v * durMs).toInt());
                        _player?.seek(target);
                        _scheduleHideControls();
                      },
                    ),
                  ),
                ],
              ),
              // Time + quality info.
              Row(
                children: [
                  Text(
                    '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const Spacer(),
                  if (_activeSource != null)
                    Text(
                      _activeSource!.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white54,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// =============================================================================
// Quality Picker Sheet
// =============================================================================

class _QualityPickerSheet extends StatelessWidget {
  const _QualityPickerSheet({
    required this.sources,
    required this.activeSource,
    required this.onSourceSelected,
  });

  final List<ResolvedSource> sources;
  final ResolvedSource? activeSource;
  final ValueChanged<ResolvedSource> onSourceSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle.
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.tune, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Quality',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Source list.
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: sources.length,
              itemBuilder: (context, index) {
                final source = sources[index];
                final isActive = source == activeSource;
                return _QualityTile(
                  source: source,
                  isActive: isActive,
                  onTap: () => onSourceSelected(source),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityTile extends StatelessWidget {
  const _QualityTile({
    required this.source,
    required this.isActive,
    required this.onTap,
  });

  final ResolvedSource source;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final q = source.quality;

    return ListTile(
      dense: true,
      selected: isActive,
      selectedTileColor: cs.primary.withValues(alpha: 0.08),
      leading: isActive
          ? Icon(Icons.check_circle, color: cs.primary, size: 20)
          : const Icon(Icons.radio_button_unchecked,
              color: Colors.grey, size: 20),
      title: Row(
        children: [
          // Resolution badge.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _resolutionColor(q.resolution).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              q.resolution ?? '?',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: _resolutionColor(q.resolution),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Source + codec.
          Expanded(
            child: Text(
              [
                if (q.source != null) q.source!,
                if (q.codec != null) q.codec!,
                if (q.hdr != null) q.hdr!,
              ].join(' · '),
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          if (q.audio != null)
            Text(
              q.audio!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          const Spacer(),
          Text(
            source.sizeLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
      onTap: isActive ? null : onTap,
    );
  }

  static Color _resolutionColor(String? res) => switch (res) {
        '2160p' => const Color(0xFFFFD700),
        '1080p' => const Color(0xFF4CAF50),
        '720p' => const Color(0xFF2196F3),
        _ => const Color(0xFF9E9E9E),
      };
}

// ---------------------------------------------------------------------------
// Phase enum
// ---------------------------------------------------------------------------

enum _OrchestratorPhase {
  resolving,
  fetching,
  buffering,
  playing,
  retrying,
  failed,
}

// ---------------------------------------------------------------------------
// Navigation helper
// ---------------------------------------------------------------------------

/// Pushes the [EntityPlayerPage] with a slide-up transition.
Future<void> pushEntityPlayer(
  BuildContext context,
  PlayableEntity entity,
) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => EntityPlayerPage(entity: entity),
      transitionsBuilder: (_, animation, __, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 350),
    ),
  );
}
