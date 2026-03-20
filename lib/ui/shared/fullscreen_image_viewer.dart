/// Fullscreen image gallery viewer with pan & zoom.
///
/// Shows one or more images in fullscreen with interactive pan/zoom via
/// [InteractiveViewer]. Swipe left/right to navigate between images.
/// Tapping toggles the toolbar; double-tap zooms. Press back to close.
/// Launch via [FullscreenImageViewer.show] or [FullscreenImageViewer.showGallery].
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:kabuk/services/media_cache.dart';

/// A full-screen image viewer with pan, zoom, swipe gallery, and
/// double-tap-to-fit.
class FullscreenImageViewer extends StatefulWidget {
  /// Creates a [FullscreenImageViewer] showing [images] starting at
  /// [initialIndex].
  const FullscreenImageViewer({
    required this.images,
    this.initialIndex = 0,
    this.tag,
    super.key,
  });

  /// List of network image URLs to display.
  final List<String> images;

  /// Index of the image to show first.
  final int initialIndex;

  /// Optional hero animation tag for the initial image.
  final String? tag;

  /// Shows a single image as a fullscreen dialog.
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
        pageBuilder: (_, _, _) => FullscreenImageViewer(
          images: [imageUrl],
          tag: tag,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  /// Shows a gallery of images starting at [initialIndex].
  ///
  /// The user can swipe left/right to navigate between all images
  /// in the channel or article. Returns the index of the last viewed
  /// image when the viewer is closed, or `null` if unchanged.
  static Future<int?> showGallery(
    BuildContext context, {
    required List<String> images,
    int initialIndex = 0,
    String? tag,
  }) {
    if (images.isEmpty) return Future.value(null);
    return Navigator.of(context).push<int>(
      PageRouteBuilder<int>(
        opaque: false,
        barrierColor: Colors.black,
        barrierDismissible: true,
        pageBuilder: (_, _, _) => FullscreenImageViewer(
          images: images,
          initialIndex: initialIndex.clamp(0, images.length - 1),
          tag: tag,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  late final PageController _pageController;
  late int _currentPage;
  bool _showToolbar = true;

  bool get _isGallery => widget.images.length > 1;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex;
    _pageController = PageController(initialPage: _currentPage);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController.dispose();
    super.dispose();
  }

  void _toggleToolbar() => setState(() => _showToolbar = !_showToolbar);

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Image pages (fills entire screen)
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              final isInitial = index == widget.initialIndex;
              return _ZoomableImage(
                imageUrl: widget.images[index],
                tag: isInitial ? widget.tag : null,
                onTap: _toggleToolbar,
              );
            },
          ),

          // Top toolbar: close button + page counter
          if (_showToolbar)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(top: topPad),
                color: Colors.black.withAlpha(160),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 28),
                      onPressed: () =>
                          Navigator.of(context).pop(_currentPage),
                      tooltip: 'Close',
                      padding: const EdgeInsets.all(16),
                    ),
                    if (_isGallery)
                      Expanded(
                        child: Text(
                          '${_currentPage + 1} / ${widget.images.length}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      const Spacer(),
                    // Invisible spacer to center the title
                    const SizedBox(width: 56),
                  ],
                ),
              ),
            ),

          // Bottom page indicator
          if (_isGallery && _showToolbar)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomPad + 16,
              child: _PageIndicator(
                count: widget.images.length,
                current: _currentPage,
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Zoomable image page
// =============================================================================

/// A single zoomable image page within the gallery.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({
    required this.imageUrl,
    required this.onTap,
    this.tag,
  });

  final String imageUrl;
  final String? tag;
  final VoidCallback onTap;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final _transformController = TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _doubleTapReset() {
    if (_transformController.value != Matrix4.identity()) {
      _transformController.value = Matrix4.identity();
    } else {
      const scale = 2.5;
      final size = MediaQuery.sizeOf(context);
      final x = -(size.width * (scale - 1) / 2);
      final y = -(size.height * (scale - 1) / 2);
      _transformController.value = Matrix4.identity()
        ..scaleByDouble(scale, scale, scale, 1.0)
        ..translateByDouble(x / scale, y / scale, 0.0, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget image = CachedNetworkImage(
      imageUrl: widget.imageUrl,
      cacheManager: KabukCacheManager.instance,
      fit: BoxFit.contain,
      width: double.infinity,
      placeholder: (_, _) => const Center(
        child: CircularProgressIndicator(
          color: Colors.white54,
          strokeWidth: 2,
        ),
      ),
      errorWidget: (_, _, _) => const Center(
        child: Icon(
          Icons.broken_image_rounded,
          color: Colors.white38,
          size: 64,
        ),
      ),
    );

    if (widget.tag != null) {
      image = Hero(tag: widget.tag!, child: image);
    }

    return Semantics(
      label: 'Full screen image. Double-tap to zoom, pinch to resize.',
      image: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: _doubleTapReset,
        child: InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.5,
          maxScale: 8.0,
          child: Center(child: image),
        ),
      ),
    );
  }
}

// =============================================================================
// Page indicator
// =============================================================================

/// Compact dot indicator for gallery pages.
class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    if (count > 20) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${current + 1} / $count',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 8 : 6,
          height: isActive ? 8 : 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? Colors.white : Colors.white38,
          ),
        );
      }),
    );
  }
}
