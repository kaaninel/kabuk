/// Fullscreen image viewer with pan & zoom.
///
/// Shows a single image in fullscreen with interactive pan/zoom via
/// [InteractiveViewer]. Tapping anywhere or pressing back closes it.
/// Launch via [FullscreenImageViewer.show].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A full-screen image viewer with pan, zoom, and double-tap-to-fit.
class FullscreenImageViewer extends StatefulWidget {
  /// Creates a [FullscreenImageViewer] showing [imageUrl].
  const FullscreenImageViewer({required this.imageUrl, super.key, this.tag});

  /// The network image URL to display.
  final String imageUrl;

  /// Optional hero animation tag (must match the card's Hero tag).
  final String? tag;

  /// Shows the viewer as a fullscreen dialog route.
  static void show(
    BuildContext context, {
    required String imageUrl,
    String? tag,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        barrierDismissible: true,
        pageBuilder: (_, _, _) =>
            FullscreenImageViewer(imageUrl: imageUrl, tag: tag),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  final _transformController = TransformationController();
  bool _showToolbar = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _transformController.dispose();
    super.dispose();
  }

  void _doubleTapReset() {
    if (_transformController.value != Matrix4.identity()) {
      _transformController.value = Matrix4.identity();
    } else {
      // Zoom to 2.5× centered on the image.
      const scale = 2.5;
      final size = MediaQuery.sizeOf(context);
      final x = -(size.width * (scale - 1) / 2);
      final y = -(size.height * (scale - 1) / 2);
      _transformController.value = Matrix4.identity()
        ..scaleByDouble(scale)
        ..translateByDouble(x / scale, y / scale);
    }
  }

  void _toggleToolbar() => setState(() => _showToolbar = !_showToolbar);

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      widget.imageUrl,
      fit: BoxFit.contain,
      width: double.infinity,
      loadingBuilder: (_, child, event) {
        if (event == null) return child;
        return Center(
          child: CircularProgressIndicator(
            value: event.expectedTotalBytes != null
                ? event.cumulativeBytesLoaded / event.expectedTotalBytes!
                : null,
            color: Colors.white54,
            strokeWidth: 2,
          ),
        );
      },
      errorBuilder: (_, _, _) => const Center(
        child: Icon(
          Icons.broken_image_rounded,
          color: Colors.white38,
          size: 64,
        ),
      ),
    );

    final imageChild = widget.tag != null
        ? Hero(tag: widget.tag!, child: image)
        : image;

    // Wrap in Center so the image is always centered inside the
    // InteractiveViewer viewport regardless of the appbar visibility.
    final viewer = Semantics(
      label: 'Full screen image. Double-tap to zoom, pinch to resize.',
      image: true,
      child: GestureDetector(
        onTap: _toggleToolbar,
        onDoubleTap: _doubleTapReset,
        child: InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.5,
          maxScale: 8.0,
          child: Center(child: imageChild),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      // Do NOT extend behind the appbar — keeps the body area fully bounded
      // so Center and fit:BoxFit.contain work correctly.
      extendBodyBehindAppBar: false,
      appBar: _showToolbar
          ? AppBar(
              backgroundColor: Colors.black.withAlpha(160),
              foregroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
              ),
            )
          : null,
      body: SizedBox.expand(child: viewer),
    );
  }
}
