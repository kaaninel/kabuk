import 'package:flutter/material.dart';
import 'base_content_card.dart';

class ImageCard extends BaseContentCard {
  final String imageUrl;
  final String photographer;
  final bool isLiked;
  final VoidCallback? onLike;

  const ImageCard({
    super.key,
    required this.imageUrl,
    required this.photographer,
    required super.title,
    this.isLiked = false,
    this.onLike,
    super.size = ContentCardSize.small,
    super.onTap,
  });

  @override
  Widget buildContent(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          imageUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Icon(Icons.error_outline, size: 40),
            );
          },
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withAlpha(179),
                ],
              ),
            ),
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    photographer.isEmpty
                        ? 'Unknown photographer'
                        : photographer,
                    style: const TextStyle(color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: Colors.white,
                  ),
                  onPressed: onLike,
                  tooltip: isLiked ? 'Unlike' : 'Like',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
