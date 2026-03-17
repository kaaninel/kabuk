/// Shared markdown renderer with consistent Kabuk theming.
///
/// Provides [KabukMarkdown] for inline markdown rendering (no scroll)
/// and [KabukMarkdownBlock] for scrollable, full-page markdown.
/// Both use the Kabuk dark theme with teal accents and proper code
/// block styling.
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:kabuk/ui/explore/quick_peek_sheet.dart';
import 'package:kabuk/ui/theme.dart';

/// Creates the standard Kabuk [MarkdownStyleSheet] for consistent
/// markdown rendering across the app.
MarkdownStyleSheet kabukMarkdownStyle(BuildContext context) {
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    // Body text.
    p: const TextStyle(
      color: KabukTheme.textPrimary,
      fontSize: 14,
      height: 1.55,
    ),
    // Headings.
    h1: const TextStyle(
      color: KabukTheme.textPrimary,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.3,
      letterSpacing: -0.3,
    ),
    h2: const TextStyle(
      color: KabukTheme.textPrimary,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: 1.3,
    ),
    h3: const TextStyle(
      color: KabukTheme.textPrimary,
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    h4: const TextStyle(
      color: KabukTheme.textPrimary,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    h5: const TextStyle(
      color: KabukTheme.textSecondary,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    h6: const TextStyle(
      color: KabukTheme.textSecondary,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    // Inline code.
    code: const TextStyle(
      color: KabukTheme.accentGreen,
      backgroundColor: KabukTheme.surfaceVariant,
      fontFamily: 'SF Mono',
      fontSize: 13,
    ),
    // Code blocks.
    codeblockDecoration: BoxDecoration(
      color: KabukTheme.surfaceVariant,
      borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
      border: Border.all(color: KabukTheme.divider, width: 0.5),
    ),
    codeblockPadding: const EdgeInsets.all(KabukTheme.spacingSm + 4),
    // Block quotes.
    blockquoteDecoration: BoxDecoration(
      border: const Border(
        left: BorderSide(color: KabukTheme.accentGreen, width: 3),
      ),
      color: KabukTheme.primaryGreen.withAlpha(12),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(
      KabukTheme.spacingMd,
      KabukTheme.spacingSm,
      KabukTheme.spacingSm,
      KabukTheme.spacingSm,
    ),
    blockquote: const TextStyle(
      color: KabukTheme.textSecondary,
      fontSize: 14,
      height: 1.55,
      fontStyle: FontStyle.italic,
    ),
    // Links.
    a: const TextStyle(
      color: KabukTheme.blueAccent,
      decoration: TextDecoration.underline,
      decorationColor: KabukTheme.blueAccent,
    ),
    // Lists.
    listBullet: const TextStyle(color: KabukTheme.accentGreen, fontSize: 14),
    // Table styling.
    tableHead: const TextStyle(
      color: KabukTheme.textPrimary,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    ),
    tableBody: const TextStyle(color: KabukTheme.textPrimary, fontSize: 13),
    tableBorder: TableBorder.all(color: KabukTheme.divider, width: 0.5),
    tableHeadAlign: TextAlign.left,
    tableCellsPadding: const EdgeInsets.symmetric(
      horizontal: KabukTheme.spacingSm,
      vertical: KabukTheme.spacingXs + 2,
    ),
    // Horizontal rule.
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: KabukTheme.divider, width: 1)),
    ),
    // Emphasis.
    em: const TextStyle(
      fontStyle: FontStyle.italic,
      color: KabukTheme.textPrimary,
    ),
    strong: const TextStyle(
      fontWeight: FontWeight.w700,
      color: KabukTheme.textPrimary,
    ),
    del: const TextStyle(
      decoration: TextDecoration.lineThrough,
      color: KabukTheme.textSecondary,
    ),
    // Checkbox.
    checkbox: const TextStyle(color: KabukTheme.accentGreen),
  );
}

/// Inline markdown renderer (non-scrollable).
///
/// Use within chat bubbles, cards, and other constrained areas where
/// markdown should flow with surrounding content.
class KabukMarkdown extends StatelessWidget {
  /// Creates a [KabukMarkdown] renderer.
  const KabukMarkdown({
    required this.data,
    this.selectable = true,
    this.onTapLink,
    this.shrinkWrap = true,
    super.key,
  });

  /// The markdown source text to render.
  final String data;

  /// Whether text is selectable.
  final bool selectable;

  /// Whether to shrink-wrap content.
  final bool shrinkWrap;

  /// Callback when a link is tapped.
  final void Function(String text, String? href, String title)? onTapLink;

  @override
  Widget build(BuildContext context) {
    if (data.trim().isEmpty) return const SizedBox.shrink();

    return MarkdownBody(
      data: data,
      selectable: selectable,
      shrinkWrap: shrinkWrap,
      styleSheet: kabukMarkdownStyle(context),
      onTapLink: onTapLink ??
          (text, href, _) => _defaultLinkHandler(context, href, text),
    );
  }

  void _defaultLinkHandler(BuildContext context, String? href, String text) {
    if (href == null || href.isEmpty) return;
    QuickPeekSheet.show(
      context,
      url: href,
      title: text.isNotEmpty ? text : null,
    );
  }
}

/// Full-page scrollable markdown rendering.
///
/// Use for reading views, note detail pages, and anywhere markdown
/// content needs its own scroll context.
class KabukMarkdownBlock extends StatelessWidget {
  /// Creates a [KabukMarkdownBlock] renderer.
  const KabukMarkdownBlock({
    required this.data,
    this.selectable = true,
    this.padding,
    this.onTapLink,
    super.key,
  });

  /// The markdown source text to render.
  final String data;

  /// Whether text is selectable.
  final bool selectable;

  /// Padding around the markdown content.
  final EdgeInsets? padding;

  /// Callback when a link is tapped.
  final void Function(String text, String? href, String title)? onTapLink;

  @override
  Widget build(BuildContext context) {
    return Markdown(
      data: data,
      selectable: selectable,
      padding: padding ?? const EdgeInsets.all(KabukTheme.spacingMd),
      styleSheet: kabukMarkdownStyle(context),
      onTapLink: onTapLink ??
          (text, href, _) => _defaultLinkHandler(context, href, text),
    );
  }

  void _defaultLinkHandler(BuildContext context, String? href, String text) {
    if (href == null || href.isEmpty) return;
    QuickPeekSheet.show(
      context,
      url: href,
      title: text.isNotEmpty ? text : null,
    );
  }
}
