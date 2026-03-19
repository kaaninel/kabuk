/// Audio capture — immersive audio recording overlay.
///
/// Full-screen dark recording interface with waveform visualization,
/// timer, and recording controls. Designed to match the visual
/// language of the camera-first Vault view.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/media.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:record/record.dart';

/// Immersive audio recording screen.
///
/// Provides a full-screen recording experience with a real-time
/// amplitude waveform, large timer display, and intuitive controls.
/// The visual style matches the camera viewfinder aesthetic.
class AudioCapture extends ConsumerStatefulWidget {
  /// Creates an [AudioCapture].
  const AudioCapture({super.key, required this.onSaved, required this.onClose});

  /// Called after a recording is saved.
  final VoidCallback onSaved;

  /// Called when the user closes without saving.
  final VoidCallback onClose;

  @override
  ConsumerState<AudioCapture> createState() => _AudioCaptureState();
}

class _AudioCaptureState extends ConsumerState<AudioCapture>
    with SingleTickerProviderStateMixin {
  AudioRecorder? _recorder;
  bool _isRecording = false;
  bool _isPaused = false;
  String? _recordedPath;
  final _nameController = TextEditingController();
  bool _saving = false;

  // Timer.
  Timer? _timer;
  int _elapsedSeconds = 0;

  // Amplitude visualization.
  final _amplitudes = <double>[];
  StreamSubscription<Amplitude>? _amplitudeSub;

  // Pulsing animation for the record indicator.
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _recorder = AudioRecorder();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amplitudeSub?.cancel();
    _recorder?.dispose();
    _nameController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  String get _formattedTime {
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _startRecording() async {
    final recorder = _recorder;
    if (recorder == null) return;

    final hasPermission = await recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Microphone permission required'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: KabukTheme.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
            ),
            margin: const EdgeInsets.all(KabukTheme.spacingMd),
          ),
        );
      }
      return;
    }

    final tempDir = await ref
        .read(mediaServiceProvider)
        .getTemporaryDirectoryPath();
    final path =
        '$tempDir/kabuk_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );

    _amplitudeSub = recorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen((amp) {
          if (mounted) {
            setState(() {
              final normalized = ((amp.current + 50) / 50).clamp(0.0, 1.0);
              _amplitudes.add(normalized);
              if (_amplitudes.length > 80) _amplitudes.removeAt(0);
            });
          }
        });

    unawaited(HapticFeedback.mediumImpact());
    unawaited(_pulseController.repeat(reverse: true));

    setState(() {
      _isRecording = true;
      _isPaused = false;
      _elapsedSeconds = 0;
      _amplitudes.clear();
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isRecording && !_isPaused) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  Future<void> _pauseRecording() async {
    final recorder = _recorder;
    if (recorder == null) return;

    unawaited(HapticFeedback.lightImpact());
    if (_isPaused) {
      await recorder.resume();
      unawaited(_pulseController.repeat(reverse: true));
      setState(() => _isPaused = false);
    } else {
      await recorder.pause();
      _pulseController.stop();
      setState(() => _isPaused = true);
    }
  }

  Future<void> _stopRecording() async {
    final recorder = _recorder;
    if (recorder == null) return;

    _timer?.cancel();
    unawaited(_amplitudeSub?.cancel());
    _amplitudeSub = null;
    _pulseController.stop();
    final path = await recorder.stop();

    unawaited(HapticFeedback.heavyImpact());
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _recordedPath = path;
    });
  }

  Future<void> _cancelRecording() async {
    final recorder = _recorder;
    if (recorder == null) return;

    _timer?.cancel();
    unawaited(_amplitudeSub?.cancel());
    _amplitudeSub = null;
    _pulseController.stop();
    await recorder.cancel();

    setState(() {
      _isRecording = false;
      _isPaused = false;
      _elapsedSeconds = 0;
      _amplitudes.clear();
    });
  }

  void _discardRecording() {
    setState(() {
      _recordedPath = null;
      _elapsedSeconds = 0;
      _amplitudes.clear();
    });
  }

  Future<void> _save() async {
    if (_recordedPath == null) return;
    setState(() => _saving = true);
    unawaited(HapticFeedback.mediumImpact());

    try {
      final store = ref.read(knowledgeStoreProvider);
      final name = _nameController.text.trim();

      await store.createMediaObject(
        name: name.isEmpty
            ? 'Recording ${DateTime.now().toIso8601String()}'
            : name,
        type: MediaType.audio,
        contentUrl: _recordedPath!,
        encodingFormat: 'audio/aac',
        duration: 'PT${_elapsedSeconds}S',
      );

      if (mounted) {
        unawaited(HapticFeedback.heavyImpact());
        widget.onSaved();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).viewPadding.top;
    const bottomPadding = 0.0;

    return Container(
      color: KabukTheme.background,
      child: Column(
        children: [
          // Top bar.
          Padding(
            padding: EdgeInsets.fromLTRB(8, topPadding + 8, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: _isRecording ? _cancelRecording : widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                  color: KabukTheme.textSecondary,
                  tooltip: _isRecording ? 'Cancel recording' : 'Close',
                ),
                // Mode label.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: KabukTheme.warmAccent.withAlpha(20),
                    borderRadius: BorderRadius.circular(KabukTheme.radiusXl),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mic_rounded,
                        size: 14,
                        color: KabukTheme.warmAccent,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Audio',
                        style: TextStyle(
                          color: KabukTheme.warmAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Invisible spacer to balance the close button.
                const SizedBox(width: 48),
              ],
            ),
          ),

          // Main area — timer + waveform.
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Status indicator.
                if (_isRecording)
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, _) => Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            (_isPaused
                                    ? KabukTheme.textTertiary
                                    : KabukTheme.warmAccent)
                                .withAlpha(
                                  (255 * _pulseAnimation.value).round(),
                                ),
                      ),
                    ),
                  ),
                if (_isRecording) const SizedBox(height: KabukTheme.spacingMd),

                // Timer.
                Text(
                  _formattedTime,
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 4,
                    color: _isRecording
                        ? KabukTheme.warmAccent
                        : _recordedPath != null
                        ? KabukTheme.textPrimary
                        : KabukTheme.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: KabukTheme.spacingLg),

                // Waveform.
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KabukTheme.spacingXl,
                  ),
                  child: Semantics(
                    label: _isRecording
                        ? (_isPaused
                              ? 'Recording paused'
                              : 'Recording in progress')
                        : _recordedPath != null
                        ? 'Recording complete'
                        : 'Ready to record',
                    child: SizedBox(
                      height: 80,
                      child: _amplitudes.isEmpty
                          ? Center(
                              child: Text(
                                _isRecording
                                    ? 'Listening...'
                                    : _recordedPath != null
                                    ? 'Recording complete'
                                    : 'Tap the button to start',
                                style: const TextStyle(
                                  color: KabukTheme.textTertiary,
                                  fontSize: 14,
                                ),
                              ),
                            )
                          : RepaintBoundary(
                              child: CustomPaint(
                                size: const Size(double.infinity, 80),
                                painter: _WaveformPainter(
                                  amplitudes: _amplitudes,
                                  color: _isPaused
                                      ? KabukTheme.textTertiary
                                      : KabukTheme.warmAccent,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),

                // Recording status label.
                if (_isRecording) ...[
                  const SizedBox(height: KabukTheme.spacingMd),
                  Text(
                    _isPaused ? 'Paused' : 'Recording',
                    style: TextStyle(
                      color: _isPaused
                          ? KabukTheme.textTertiary
                          : KabukTheme.warmAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Bottom controls.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KabukTheme.spacingLg,
              KabukTheme.spacingMd,
              KabukTheme.spacingLg,
              bottomPadding + KabukTheme.spacingLg,
            ),
            child: _buildControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    // State: idle → show big record button.
    if (!_isRecording && _recordedPath == null) {
      return Center(
        child: Semantics(
          label: 'Start recording',
          button: true,
          child: GestureDetector(
            onTap: _startRecording,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KabukTheme.warmAccent,
                boxShadow: [
                  BoxShadow(
                    color: KabukTheme.warmAccent.withAlpha(60),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
        ),
      );
    }

    // State: recording → pause, stop, cancel.
    if (_isRecording) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: Icons.close_rounded,
            label: 'Cancel',
            color: KabukTheme.error,
            onTap: _cancelRecording,
          ),
          _ControlButton(
            icon: _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            label: _isPaused ? 'Resume' : 'Pause',
            color: KabukTheme.textSecondary,
            onTap: _pauseRecording,
          ),
          _ControlButton(
            icon: Icons.stop_rounded,
            label: 'Done',
            color: KabukTheme.warmAccent,
            filled: true,
            onTap: _stopRecording,
          ),
        ],
      );
    }

    // State: recorded → name, discard, save.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Name field.
        Container(
          decoration: BoxDecoration(
            color: KabukTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          ),
          child: TextField(
            controller: _nameController,
            style: const TextStyle(fontSize: 15, color: KabukTheme.textPrimary),
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Name this recording...',
              hintStyle: TextStyle(
                color: KabukTheme.textTertiary,
                fontSize: 15,
              ),
              prefixIcon: Icon(
                Icons.label_outline_rounded,
                size: 20,
                color: KabukTheme.textTertiary,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                vertical: KabukTheme.spacingMd,
              ),
            ),
          ),
        ),
        const SizedBox(height: KabukTheme.spacingMd),
        // Action buttons.
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _discardRecording,
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: KabukTheme.divider),
                    borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                  ),
                  child: const Text(
                    'Discard',
                    style: TextStyle(
                      color: KabukTheme.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: KabukTheme.spacingSm),
            Expanded(
              flex: 2,
              child: Semantics(
                label: 'Save Recording',
                button: true,
                enabled: !_saving,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: _saving ? null : _save,
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: KabukTheme.warmAccent,
                      borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                      boxShadow: [
                        BoxShadow(
                          color: KabukTheme.warmAccent.withAlpha(60),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.save_alt_rounded,
                                color: Colors.white,
                                size: 20,
                                semanticLabel: '',
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Save Recording',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

/// A circular control button with a label underneath.
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: label,
          button: true,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? color : color.withAlpha(20),
                border: filled ? null : Border.all(color: color.withAlpha(60)),
                boxShadow: filled
                    ? [
                        BoxShadow(
                          color: color.withAlpha(50),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Icon(icon, color: filled ? Colors.white : color, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Custom painter for the audio waveform visualization.
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.amplitudes, required this.color});

  final List<double> amplitudes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;

    const barWidth = 3.0;
    const gap = 2.0;
    final maxBars = (size.width / (barWidth + gap)).floor();
    final samplesToShow = amplitudes.length > maxBars
        ? amplitudes.sublist(amplitudes.length - maxBars)
        : amplitudes;

    final centerY = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (var i = 0; i < samplesToShow.length; i++) {
      final x = size.width - ((samplesToShow.length - i) * (barWidth + gap));
      final amplitude = samplesToShow[i];
      final barHeight = (amplitude * size.height * 0.85).clamp(
        2.0,
        size.height,
      );

      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      amplitudes.length != oldDelegate.amplitudes.length ||
      color != oldDelegate.color;
}
