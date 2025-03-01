import 'package:flutter/material.dart';

enum ContentCardSize { small, horizontal, vertical, large }

abstract class BaseContentCard extends StatelessWidget {
  final String title;
  final ContentCardSize size;
  final VoidCallback? onTap;

  const BaseContentCard({
    super.key,
    required this.title,
    this.size = ContentCardSize.small,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget buildContent(BuildContext context);
}
