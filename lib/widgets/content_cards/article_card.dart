import 'package:flutter/material.dart';
import 'base_content_card.dart';

class ArticleCard extends BaseContentCard {
  final String headline;
  final String? coverImageUrl;
  final String author;
  final String category;

  const ArticleCard({
    super.key,
    required this.headline,
    required this.author,
    required this.category,
    required super.title,
    this.coverImageUrl,
    super.size = ContentCardSize.small,
    super.onTap,
  });

  @override
  Widget buildContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (coverImageUrl != null)
              Expanded(
                flex: 2,
                child: Image.network(
                  coverImageUrl!,
                  fit: BoxFit.cover,
                ),
              ),
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      headline,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Text(
                      'By $author',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
