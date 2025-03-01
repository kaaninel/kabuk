import 'package:flutter/material.dart';
import 'base_content_card.dart';

class VideoCard extends BaseContentCard {
  final String thumbnailUrl;
  final String creator;
  final Duration duration;

  const VideoCard({
    super.key,
    required this.thumbnailUrl,
    required this.creator,
    required this.duration,
    required super.title,
    super.size = ContentCardSize.small,
    super.onTap,
  });

  @override
  Widget buildContent(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          thumbnailUrl,
          fit: BoxFit.cover,
        ),
        Center(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(128), // 0.5 opacity = 128 alpha
              shape: BoxShape.circle,
            ),
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(179), // 0.7 opacity = ~179 alpha
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _formatDuration(duration),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
