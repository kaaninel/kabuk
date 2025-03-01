import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class MarkdownPreview extends StatelessWidget {
  final String content;
  final double? fontSize;
  final bool darkMode;

  const MarkdownPreview({
    super.key,
    required this.content,
    this.fontSize,
    this.darkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Markdown(
        data: content,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(
            fontSize: fontSize,
            color: darkMode ? Colors.white : Colors.black87,
          ),
          h1: TextStyle(
            fontSize: fontSize != null ? fontSize! * 2 : 32,
            color: darkMode ? Colors.white : Colors.black87,
          ),
          h2: TextStyle(
            fontSize: fontSize != null ? fontSize! * 1.5 : 24,
            color: darkMode ? Colors.white : Colors.black87,
          ),
          h3: TextStyle(
            fontSize: fontSize != null ? fontSize! * 1.2 : 20,
            color: darkMode ? Colors.white : Colors.black87,
          ),
          code: TextStyle(
            backgroundColor: darkMode ? Colors.grey[800] : Colors.grey[200],
            color: theme.colorScheme.primary,
          ),
          codeblockDecoration: BoxDecoration(
            color: darkMode ? Colors.grey[850] : Colors.grey[100],
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}