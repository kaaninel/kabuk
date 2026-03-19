/// Cached network image widget for feed content.
///
/// Wraps [CachedNetworkImage] with Kabuk-styled loading/error states
/// and consistent border radius handling.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:kabuk/services/media_cache.dart';
import 'package:kabuk/ui/theme.dart';

/// A network image with caching, loading shimmer, and error fallback.
///
/// Designed for feed cards — supports aspect ratio constraints,
/// border radius, and optional overlay gradients.
class FeedImage extends StatelessWidget {
  /// Creates a [FeedImage].
  const FeedImage({
    required this.imageUrl,
    super.key,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.showGradientOverlay = false,
  });

  /// The URL of the image to display.
  final String imageUrl;

  /// Known Reddit placeholder URLs that are not real images.
  static const _redditPlaceholders = {'self', 'default', 'nsfw', 'spoiler', ''};

  /// Whether [url] is a valid, displayable image URL.
  ///
  /// Returns `false` for Reddit placeholder strings (e.g. "self", "default")
  /// and malformed URLs.
  static bool isValidImageUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    if (_redditPlaceholders.contains(url.toLowerCase())) return false;
    final uri = Uri.tryParse(url);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  /// Optional fixed height.
  final double? height;

  /// Optional fixed width.
  final double? width;

  /// How to fit the image within the bounds. Defaults to [BoxFit.cover].
  final BoxFit fit;

  /// Border radius for clipping. Defaults to no rounding.
  final BorderRadius? borderRadius;

  /// Whether to show a bottom gradient overlay (for text-over-image).
  final bool showGradientOverlay;

  @override
  Widget build(BuildContext context) {
    // Derive a Referer header from the image URL so CDNs don't block us.
    final uri = Uri.tryParse(imageUrl);
    final headers = <String, String>{
      if (uri != null && uri.host.isNotEmpty)
        'Referer': '${uri.scheme}://${uri.host}/',
    };

    Widget image = Container(
      color: KabukTheme.surfaceVariant,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        cacheManager: KabukCacheManager.instance,
        httpHeaders: headers,
        height: height,
        width: width ?? double.infinity,
        fit: fit,
        // Filter out tiny tracking pixels (< 10×10).
        imageBuilder: (context, imageProvider) {
          return Image(
            image: imageProvider,
            height: height,
            width: width ?? double.infinity,
            fit: fit,
            frameBuilder: (ctx, child, frame, wasSyncLoaded) {
              if (frame == null) {
                return _ShimmerPlaceholder(height: height, width: width);
              }
              return child;
            },
          );
        },
        placeholder: (_, _) =>
            _ShimmerPlaceholder(height: height, width: width),
        errorWidget: (_, _, _) =>
            _ErrorPlaceholder(height: height, width: width),
        fadeInDuration: const Duration(milliseconds: 200),
      ),
    );

    if (showGradientOverlay) {
      image = Stack(
        children: [
          image,
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withAlpha(180)],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}

/// Shimmer-style loading placeholder.
class _ShimmerPlaceholder extends StatefulWidget {
  const _ShimmerPlaceholder({this.height, this.width});

  final double? height;
  final double? width;

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, _) => Container(
        height: widget.height,
        width: widget.width ?? double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(_animation.value - 1, 0),
            end: Alignment(_animation.value, 0),
            colors: const [
              KabukTheme.surfaceVariant,
              KabukTheme.surfaceElevated,
              KabukTheme.surfaceVariant,
            ],
          ),
        ),
      ),
    );
  }
}

/// Error placeholder shown when image fails to load.
class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({this.height, this.width});

  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width ?? double.infinity,
      color: KabukTheme.surfaceVariant,
      child: const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: KabukTheme.textTertiary,
          size: 32,
        ),
      ),
    );
  }
}
