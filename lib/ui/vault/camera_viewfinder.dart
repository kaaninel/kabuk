/// Camera viewfinder — full-screen live camera preview with capture controls.
///
/// Provides an Instagram/Snapchat-style camera experience with
/// tap-to-capture, hold-to-record, flash toggle, and camera flip.
library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kabuk/ui/theme.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Available cameras on the device.
final availableCamerasProvider = FutureProvider<List<CameraDescription>>((ref) {
  return availableCameras();
});

/// The active camera controller.
final cameraControllerProvider = StateProvider<CameraController?>(
  (ref) => null,
);

/// Flash mode state.
final flashModeProvider = StateProvider<FlashMode>((ref) => FlashMode.auto);

/// Whether currently recording video.
final isRecordingVideoProvider = StateProvider<bool>((ref) => false);

// ---------------------------------------------------------------------------
// Camera viewfinder widget
// ---------------------------------------------------------------------------

/// Full-screen camera viewfinder with overlay controls.
///
/// Renders a live camera preview that fills the entire screen.
/// Overlay controls include flash toggle, camera flip, and a
/// shutter button that adapts based on the current capture mode.
class CameraViewfinder extends ConsumerStatefulWidget {
  /// Creates a [CameraViewfinder].
  const CameraViewfinder({
    super.key,
    required this.onPhotoCaptured,
    required this.onVideoCaptured,
    required this.isVideoMode,
  });

  /// Called when a photo is captured, with the file path.
  final ValueChanged<String> onPhotoCaptured;

  /// Called when a video recording completes, with the file path.
  final ValueChanged<String> onVideoCaptured;

  /// Whether the viewfinder is in video mode.
  final bool isVideoMode;

  @override
  ConsumerState<CameraViewfinder> createState() => _CameraViewfinderState();
}

class _CameraViewfinderState extends ConsumerState<CameraViewfinder>
    with WidgetsBindingObserver {
  CameraController? _controller;
  int _currentCameraIndex = 0;
  bool _isInitializing = true;
  String? _error;
  bool _isCapturing = false;
  bool _isRecording = false;

  // Video recording timer.
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    // Null-out before disposing to prevent double-dispose if a lifecycle
    // event races with widget disposal.
    final c = _controller;
    _controller = null;
    c?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _controller = null;
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    setState(() {
      _isInitializing = true;
      _error = null;
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _error = 'No cameras found';
          _isInitializing = false;
        });
        return;
      }

      // Default to back camera.
      _currentCameraIndex = 0;
      for (var i = 0; i < cameras.length; i++) {
        if (cameras[i].lensDirection == CameraLensDirection.back) {
          _currentCameraIndex = i;
          break;
        }
      }

      await _setupController(cameras[_currentCameraIndex]);
    } catch (e) {
      setState(() {
        _error = 'Camera initialization failed';
        _isInitializing = false;
      });
    }
  }

  Future<void> _setupController(CameraDescription camera) async {
    final previous = _controller;
    _controller = null;
    if (previous != null) {
      await previous.dispose();
    }

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _controller = controller;

    try {
      await controller.initialize();
      // Re-apply flash mode — best-effort since some cameras (e.g. front)
      // may not support it.
      try {
        await controller.setFlashMode(ref.read(flashModeProvider));
      } catch (_) {}

      if (mounted) {
        setState(() => _isInitializing = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to start camera';
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _flipCamera() async {
    final cameras = await availableCameras();
    if (cameras.length < 2) return;

    unawaited(HapticFeedback.lightImpact());
    _currentCameraIndex = (_currentCameraIndex + 1) % cameras.length;
    await _setupController(cameras[_currentCameraIndex]);
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;

    unawaited(HapticFeedback.selectionClick());
    final modes = [FlashMode.auto, FlashMode.always, FlashMode.off];
    final current = ref.read(flashModeProvider);
    final nextIndex = (modes.indexOf(current) + 1) % modes.length;
    final next = modes[nextIndex];

    await controller.setFlashMode(next);
    ref.read(flashModeProvider.notifier).state = next;
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null || _isCapturing) return;

    setState(() => _isCapturing = true);
    unawaited(HapticFeedback.mediumImpact());

    try {
      final file = await controller.takePicture();
      widget.onPhotoCaptured(file.path);
    } on Object catch (e) {
      dev.log('Photo capture failed: $e', name: 'Camera', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to capture photo. Please retry.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _startVideoRecording() async {
    final controller = _controller;
    if (controller == null || _isRecording) return;

    try {
      await controller.startVideoRecording();
      unawaited(HapticFeedback.heavyImpact());
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });
      ref.read(isRecordingVideoProvider.notifier).state = true;

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordingSeconds++);
      });
    } on Object catch (e) {
      dev.log('Video recording start failed: $e', name: 'Camera', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start recording.')),
        );
      }
    }
  }

  Future<void> _stopVideoRecording() async {
    final controller = _controller;
    if (controller == null || !_isRecording) return;

    _recordingTimer?.cancel();

    try {
      final file = await controller.stopVideoRecording();
      unawaited(HapticFeedback.heavyImpact());
      setState(() => _isRecording = false);
      ref.read(isRecordingVideoProvider.notifier).state = false;
      widget.onVideoCaptured(file.path);
    } on Object catch (e) {
      dev.log('Video recording stop failed: $e', name: 'Camera', error: e);
      setState(() => _isRecording = false);
      ref.read(isRecordingVideoProvider.notifier).state = false;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to save video.')));
      }
    }
  }

  String get _formattedRecordingTime {
    final m = (_recordingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_recordingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final flashMode = ref.watch(flashModeProvider);

    if (_error != null) {
      // When no camera is available (simulator / no hardware), offer a
      // graceful gallery fallback instead of a dead-end error state.
      if (_error == 'No cameras found') {
        return _CameraUnavailableFallback(
          onPickFromLibrary: () async {
            final picker = ImagePicker();
            final picked = await picker.pickImage(source: ImageSource.gallery);
            if (picked != null) {
              widget.onPhotoCaptured(picked.path);
            }
          },
        );
      }
      return _CameraErrorState(error: _error!, onRetry: _initCamera);
    }

    if (_isInitializing || _controller == null) {
      return const _CameraLoadingState();
    }

    final controller = _controller!;
    if (!controller.value.isInitialized) {
      return const _CameraLoadingState();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview — fills entire space.
        ClipRRect(
          borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
          child: _buildCameraPreview(controller),
        ),

        // Recording time indicator.
        if (_isRecording)
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(200),
                  borderRadius: BorderRadius.circular(KabukTheme.radiusXl),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formattedRecordingTime,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Top controls — flash, flip.
        if (!_isRecording)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Flash toggle.
                _OverlayButton(
                  icon: _flashIcon(flashMode),
                  onTap: _toggleFlash,
                  label: _flashLabel(flashMode),
                ),
                // Camera flip.
                _OverlayButton(
                  icon: Icons.flip_camera_ios_rounded,
                  onTap: _flipCamera,
                ),
              ],
            ),
          ),

        // Bottom: shutter button.
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Center(
            child: _ShutterButton(
              isVideoMode: widget.isVideoMode,
              isRecording: _isRecording,
              isCapturing: _isCapturing,
              onTap: widget.isVideoMode
                  ? (_isRecording ? _stopVideoRecording : _startVideoRecording)
                  : _capturePhoto,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraPreview(CameraController controller) {
    // Scale the preview to fill, maintaining aspect ratio.
    final mediaSize = MediaQuery.of(context).size;
    final scale =
        1 /
        (controller.value.aspectRatio * (mediaSize.width / mediaSize.height));

    return Transform.scale(
      scale: scale.clamp(1.0, 2.5),
      alignment: Alignment.center,
      child: CameraPreview(controller),
    );
  }

  IconData _flashIcon(FlashMode mode) => switch (mode) {
    FlashMode.auto => Icons.flash_auto_rounded,
    FlashMode.always => Icons.flash_on_rounded,
    FlashMode.off => Icons.flash_off_rounded,
    FlashMode.torch => Icons.flashlight_on_rounded,
  };

  String _flashLabel(FlashMode mode) => switch (mode) {
    FlashMode.auto => 'Auto',
    FlashMode.always => 'On',
    FlashMode.off => 'Off',
    FlashMode.torch => 'Torch',
  };
}

// ---------------------------------------------------------------------------
// Shutter button
// ---------------------------------------------------------------------------

/// Instagram/Snapchat-style shutter button.
///
/// In photo mode: white circle, tap to capture.
/// In video mode: red circle, tap to start/stop recording.
class _ShutterButton extends StatefulWidget {
  const _ShutterButton({
    required this.isVideoMode,
    required this.isRecording,
    required this.isCapturing,
    required this.onTap,
  });

  final bool isVideoMode;
  final bool isRecording;
  final bool isCapturing;
  final VoidCallback onTap;

  @override
  State<_ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<_ShutterButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outerSize = widget.isRecording ? 88.0 : 80.0;
    final innerSize = widget.isRecording ? 32.0 : 64.0;
    final innerRadius = widget.isRecording ? 8.0 : 32.0;
    final innerColor = widget.isVideoMode ? Colors.red : Colors.white;

    return GestureDetector(
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) =>
            Transform.scale(scale: _scaleAnimation.value, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: outerSize,
          height: outerSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.isRecording ? Colors.red : Colors.white,
              width: 4,
            ),
          ),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: innerSize,
              height: innerSize,
              decoration: BoxDecoration(
                color: widget.isCapturing
                    ? innerColor.withAlpha(150)
                    : innerColor,
                borderRadius: BorderRadius.circular(innerRadius),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay controls
// ---------------------------------------------------------------------------

/// A translucent circular button overlaid on the camera preview.
class _OverlayButton extends StatelessWidget {
  const _OverlayButton({required this.icon, required this.onTap, this.label});

  final IconData icon;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

/// Shown while the camera is initializing.
class _CameraLoadingState extends StatelessWidget {
  const _CameraLoadingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KabukTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: KabukTheme.accentGreen,
              strokeWidth: 2,
            ),
            SizedBox(height: KabukTheme.spacingMd),
            Text(
              'Starting camera...',
              style: TextStyle(color: KabukTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the camera fails to initialize.
class _CameraErrorState extends StatelessWidget {
  const _CameraErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KabukTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KabukTheme.error.withAlpha(20),
              ),
              child: const Icon(
                Icons.camera_alt_outlined,
                color: KabukTheme.error,
                size: 28,
              ),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            Text(
              error,
              style: const TextStyle(
                color: KabukTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: TextButton.styleFrom(
                foregroundColor: KabukTheme.accentGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder used when computing the [AnimatedBuilder] analogue.
///
/// Dart's `AnimatedBuilder` is actually just [AnimatedWidget] with a builder.
/// This uses the real [AnimatedBuilder] class from Flutter.
// The AnimatedBuilder usage above is correct — it's Flutter's built-in widget.

// ---------------------------------------------------------------------------
// Camera unavailable fallback
// ---------------------------------------------------------------------------

/// Shown when the device has no camera (simulator, restricted hardware).
///
/// Offers a designed fallback — not an error — that lets the user pick
/// an image from their photo library instead.
class _CameraUnavailableFallback extends StatelessWidget {
  const _CameraUnavailableFallback({required this.onPickFromLibrary});

  final VoidCallback onPickFromLibrary;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KabukTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(KabukTheme.spacingXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KabukTheme.accentGreen.withAlpha(25),
                ),
                child: const Icon(
                  Icons.photo_library_outlined,
                  color: KabukTheme.accentGreen,
                  size: 36,
                ),
              ),
              const SizedBox(height: KabukTheme.spacingLg),
              const Text(
                'Camera unavailable',
                style: TextStyle(
                  color: KabukTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: KabukTheme.spacingSm),
              const Text(
                'No camera was found on this device.\nYou can still choose a photo from your library.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: KabukTheme.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: KabukTheme.spacingLg),
              FilledButton.icon(
                onPressed: onPickFromLibrary,
                icon: const Icon(Icons.photo_rounded, size: 18),
                label: const Text('Choose from Library'),
                style: FilledButton.styleFrom(
                  backgroundColor: KabukTheme.accentGreen,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: KabukTheme.spacingLg,
                    vertical: KabukTheme.spacingMd,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
