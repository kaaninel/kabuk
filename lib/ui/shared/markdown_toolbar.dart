/// Markdown formatting toolbar — provides quick-access buttons for
/// common markdown syntax insertion.
///
/// Used in both the full markdown editor and the chat input bar.
/// Each button wraps the current selection or inserts syntax at
/// the cursor position.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kabuk/ui/theme.dart';

/// Defines a markdown formatting action.
class MarkdownAction {
  /// Creates a [MarkdownAction].
  const MarkdownAction({
    required this.icon,
    required this.tooltip,
    required this.prefix,
    this.suffix,
    this.blockPrefix,
    this.isBlock = false,
  });

  /// The icon to display.
  final IconData icon;

  /// Tooltip label.
  final String tooltip;

  /// Text inserted before the selection (or at cursor).
  final String prefix;

  /// Text inserted after the selection (optional).
  final String? suffix;

  /// For block-level insertions (inserted on a new line before).
  final String? blockPrefix;

  /// Whether this is a block-level action (inserts on new lines).
  final bool isBlock;
}

/// Standard markdown formatting actions.
abstract final class MarkdownActions {
  /// Bold text.
  static const bold = MarkdownAction(
    icon: Icons.format_bold_rounded,
    tooltip: 'Bold',
    prefix: '**',
    suffix: '**',
  );

  /// Italic text.
  static const italic = MarkdownAction(
    icon: Icons.format_italic_rounded,
    tooltip: 'Italic',
    prefix: '_',
    suffix: '_',
  );

  /// Strikethrough text.
  static const strikethrough = MarkdownAction(
    icon: Icons.strikethrough_s_rounded,
    tooltip: 'Strikethrough',
    prefix: '~~',
    suffix: '~~',
  );

  /// Inline code.
  static const inlineCode = MarkdownAction(
    icon: Icons.code_rounded,
    tooltip: 'Inline code',
    prefix: '`',
    suffix: '`',
  );

  /// Code block.
  static const codeBlock = MarkdownAction(
    icon: Icons.data_object_rounded,
    tooltip: 'Code block',
    prefix: '```\n',
    suffix: '\n```',
    isBlock: true,
  );

  /// Heading 1.
  static const h1 = MarkdownAction(
    icon: Icons.title_rounded,
    tooltip: 'Heading 1',
    prefix: '# ',
    isBlock: true,
  );

  /// Heading 2.
  static const h2 = MarkdownAction(
    icon: Icons.title_rounded,
    tooltip: 'Heading 2',
    prefix: '## ',
    isBlock: true,
  );

  /// Heading 3.
  static const h3 = MarkdownAction(
    icon: Icons.title_rounded,
    tooltip: 'Heading 3',
    prefix: '### ',
    isBlock: true,
  );

  /// Bullet list.
  static const bulletList = MarkdownAction(
    icon: Icons.format_list_bulleted_rounded,
    tooltip: 'Bullet list',
    prefix: '- ',
    isBlock: true,
  );

  /// Numbered list.
  static const numberedList = MarkdownAction(
    icon: Icons.format_list_numbered_rounded,
    tooltip: 'Numbered list',
    prefix: '1. ',
    isBlock: true,
  );

  /// Task list / checkbox.
  static const taskList = MarkdownAction(
    icon: Icons.check_box_outlined,
    tooltip: 'Task list',
    prefix: '- [ ] ',
    isBlock: true,
  );

  /// Block quote.
  static const quote = MarkdownAction(
    icon: Icons.format_quote_rounded,
    tooltip: 'Quote',
    prefix: '> ',
    isBlock: true,
  );

  /// Link.
  static const link = MarkdownAction(
    icon: Icons.link_rounded,
    tooltip: 'Link',
    prefix: '[',
    suffix: '](url)',
  );

  /// Horizontal rule.
  static const horizontalRule = MarkdownAction(
    icon: Icons.horizontal_rule_rounded,
    tooltip: 'Divider',
    prefix: '\n---\n',
    isBlock: true,
  );

  /// The default compact set (for chat input).
  static const List<MarkdownAction> compact = [
    bold,
    italic,
    inlineCode,
    link,
    bulletList,
    quote,
  ];

  /// The full set (for the markdown editor).
  static const List<MarkdownAction> full = [
    h1,
    h2,
    h3,
    bold,
    italic,
    strikethrough,
    inlineCode,
    codeBlock,
    link,
    bulletList,
    numberedList,
    taskList,
    quote,
    horizontalRule,
  ];
}

/// A horizontal toolbar of markdown formatting buttons.
///
/// [compact] mode shows fewer buttons suitable for chat input.
/// Full mode shows the complete set for the markdown editor.
class MarkdownToolbar extends StatelessWidget {
  /// Creates a [MarkdownToolbar].
  const MarkdownToolbar({
    required this.controller,
    this.focusNode,
    this.compact = false,
    this.actions,
    this.onPreviewToggle,
    this.showPreviewToggle = false,
    this.isPreview = false,
    super.key,
  });

  /// The text editing controller to apply formatting to.
  final TextEditingController controller;

  /// Focus node to refocus after formatting.
  final FocusNode? focusNode;

  /// Whether to use the compact action set.
  final bool compact;

  /// Custom action list (overrides compact/full).
  final List<MarkdownAction>? actions;

  /// Callback to toggle preview mode.
  final VoidCallback? onPreviewToggle;

  /// Whether to show the preview toggle button.
  final bool showPreviewToggle;

  /// Whether preview mode is currently active.
  final bool isPreview;

  List<MarkdownAction> get _actions =>
      actions ?? (compact ? MarkdownActions.compact : MarkdownActions.full);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: context.kabukSurfaceVariant,
        border: Border(
          bottom: BorderSide(color: context.kabukDivider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: KabukTheme.spacingSm,
              ),
              itemCount: _actions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 2),
              itemBuilder: (context, index) {
                final action = _actions[index];
                return _ToolbarButton(
                  action: action,
                  onTap: () => _applyAction(action),
                );
              },
            ),
          ),
          if (showPreviewToggle) ...[
            Container(width: 0.5, height: 28, color: context.kabukDivider),
            _ToolbarButton(
              action: MarkdownAction(
                icon: isPreview ? Icons.edit_rounded : Icons.visibility_rounded,
                tooltip: isPreview ? 'Edit' : 'Preview',
                prefix: '',
              ),
              onTap: onPreviewToggle,
              isActive: isPreview,
            ),
            const SizedBox(width: KabukTheme.spacingXs),
          ],
        ],
      ),
    );
  }

  /// Apply a markdown formatting action to the text controller.
  void _applyAction(MarkdownAction action) {
    HapticFeedback.selectionClick();
    final text = controller.text;
    final selection = controller.selection;

    if (!selection.isValid) {
      // No valid selection — insert at end.
      final insert = '${action.prefix}${action.suffix ?? ''}';
      controller
        ..text = '$text$insert'
        ..selection = TextSelection.collapsed(
          offset: text.length + action.prefix.length,
        );
      focusNode?.requestFocus();
      return;
    }

    final start = selection.start;
    final end = selection.end;
    final selectedText = text.substring(start, end);

    if (action.isBlock && action.suffix == null) {
      // Block-level prefix only (e.g. `## `, `- `).
      // If at the start of a line, just insert prefix.
      // Otherwise, insert newline + prefix.
      final beforeCursor = text.substring(0, start);
      final needsNewline =
          beforeCursor.isNotEmpty && !beforeCursor.endsWith('\n');
      final prefix = needsNewline ? '\n${action.prefix}' : action.prefix;

      final newText =
          '${text.substring(0, start)}$prefix$selectedText${text.substring(end)}';
      controller
        ..text = newText
        ..selection = TextSelection.collapsed(
          offset: start + prefix.length + selectedText.length,
        );
    } else {
      // Wrap selection with prefix/suffix.
      final suffix = action.suffix ?? '';
      final newText =
          '${text.substring(0, start)}${action.prefix}$selectedText$suffix${text.substring(end)}';
      controller
        ..text = newText
        ..selection = TextSelection(
          baseOffset: start + action.prefix.length,
          extentOffset: start + action.prefix.length + selectedText.length,
        );
    }

    focusNode?.requestFocus();
  }
}

/// A single toolbar button.
class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.action,
    this.onTap,
    this.isActive = false,
  });

  final MarkdownAction action;
  final VoidCallback? onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: action.tooltip,
      child: Material(
        color: isActive
            ? KabukTheme.primaryGreen.withAlpha(30)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              action.icon,
              size: 18,
              color: isActive
                  ? KabukTheme.accentGreen
                  : context.kabukTextSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
