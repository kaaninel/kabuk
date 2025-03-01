import 'package:flutter/material.dart';
import 'base_content_card.dart';

class AudioCard extends BaseContentCard {
  final String? coverUrl;
  final String artist;
  final bool isPlaying;
  final VoidCallback? onPlayPause;

  const AudioCard({
    super.key,
    required this.artist,
    required super.title,
    this.coverUrl,
    this.isPlaying = false,
    this.onPlayPause,
    super.size = ContentCardSize.small,
    super.onTap,
  });

  @override
  Widget buildContent(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (coverUrl != null)
                Image.network(
                  coverUrl!,
                  fit: BoxFit.cover,
                )
              else
                Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.music_note, size: 48),
                ),
              Center(
                child: IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause_circle : Icons.play_circle,
                    size: 48,
                  ),
                  onPressed: onPlayPause,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                artist,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
