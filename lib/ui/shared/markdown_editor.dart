/// Full-featured markdown editor with live preview.
///
/// Provides a split or toggle view with a markdown source editor on one
/// side and a rendered preview on the other. Includes a formatting toolbar
/// and supports both full-page and embedded usage.
library;

import 'package:flutter/material.dart';
import 'package:kabuk/ui/shared/kabuk_markdown.dart';
import 'package:kabuk/ui/shared/markdown_toolbar.dart';
import 'package:kabuk/ui/theme.dart';

/// A full markdown editor with toolbar and live preview.
///
/// Use this for note creation, content authoring, and anywhere a rich
/// text editing experience is needed. Supports toggling between edit
/// and preview modes, or a side-by-side split on wider screens.
class MarkdownEditor extends StatefulWidget {
  /// Creates a [MarkdownEditor].
  const MarkdownEditor({
    this.controller,
    this.initialText,
    this.hintText = 'Start writing in markdown...',
    this.onChanged,
    this.onTap,
    this.minLines = 12,
    this.maxLines,
    this.autofocus = false,
    this.showToolbar = true,
    this.showPreviewToggle = true,
    this.readOnly = false,
    this.suppressSystemKeyboard = false,
    this.focusNode,
    super.key,
  });

  /// External text controller (one is created internally if null).
  final TextEditingController? controller;

  /// Initial text to populate the editor with.
  final String? initialText;

  /// Placeholder text when empty.
  final String hintText;

  /// Called when the text changes.
  final ValueChanged<String>? onChanged;

  /// Called when the editor is tapped.
  final VoidCallback? onTap;

  /// Minimum number of visible lines.
  final int minLines;

  /// Maximum number of visible lines (null = unlimited).
  final int? maxLines;

  /// Whether to autofocus the editor.
  final bool autofocus;

  /// Whether to show the formatting toolbar.
  final bool showToolbar;

  /// Whether to show the preview toggle.
  final bool showPreviewToggle;

  /// Whether the editor is read-only (shows preview only).
  final bool readOnly;

  /// Whether to suppress the system keyboard (for custom keyboard use).
  ///
  /// Unlike [readOnly], this keeps the editor editable and the toolbar
  /// visible, but prevents the system keyboard from appearing.
  final bool suppressSystemKeyboard;

  /// External focus node.
  final FocusNode? focusNode;

  @override
  State<MarkdownEditor> createState() => MarkdownEditorState();
}

/// State for [MarkdownEditor].
///
/// Exposed so parent widgets can access [text] and [controller].
class MarkdownEditorState extends State<MarkdownEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _ownController = false;
  bool _ownFocusNode = false;
  bool _isPreview = false;

  /// The current text content.
  String get text => _controller.text;

  /// The text editing controller.
  TextEditingController get controller => _controller;

  /// Clears the editor content.
  void clear() {
    _controller.clear();
    setState(() => _isPreview = false);
  }

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController(text: widget.initialText ?? '');
      _ownController = true;
    }
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownFocusNode = true;
    }
    _controller.addListener(_onTextChanged);

    if (widget.readOnly) _isPreview = true;
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (_ownController) _controller.dispose();
    if (_ownFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    widget.onChanged?.call(_controller.text);
    setState(() {}); // Rebuild for preview updates.
  }

  void _togglePreview() {
    if (widget.readOnly) return;
    setState(() => _isPreview = !_isPreview);
    if (!_isPreview) {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar.
        if (widget.showToolbar && !widget.readOnly)
          MarkdownToolbar(
            controller: _controller,
            focusNode: _focusNode,
            showPreviewToggle: widget.showPreviewToggle,
            isPreview: _isPreview,
            onPreviewToggle: _togglePreview,
          ),
        // Editor / Preview.
        Expanded(child: _isPreview ? _buildPreview() : _buildEditor()),
      ],
    );
  }

  Widget _buildEditor() {
    return Container(
      color: context.kabukSurfaceElevated,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        readOnly: widget.readOnly,
        showCursor: true,
        keyboardType: widget.suppressSystemKeyboard
            ? TextInputType.none
            : TextInputType.multiline,
        maxLines: widget.maxLines,
        minLines: widget.maxLines == null ? null : widget.minLines,
        expands: widget.maxLines == null,
        textAlignVertical: TextAlignVertical.top,
        textCapitalization: TextCapitalization.sentences,
        onTap: widget.onTap,
        style: TextStyle(
          color: context.kabukTextPrimary,
          fontSize: 15,
          height: 1.65,
          fontFamily: 'SF Mono',
        ),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(
            color: context.kabukTextTertiary,
            fontSize: 15,
            fontFamily: 'SF Mono',
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.all(KabukTheme.spacingMd),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final content = _controller.text;

    if (content.trim().isEmpty) {
      return Container(
        color: context.kabukSurfaceElevated,
        child: Center(
          child: Text(
            'Nothing to preview',
            style: TextStyle(color: context.kabukTextTertiary, fontSize: 14),
          ),
        ),
      );
    }

    return Container(
      color: context.kabukSurfaceElevated,
      child: KabukMarkdownBlock(
        data: content,
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
      ),
    );
  }
}

/// An inline markdown editor without preview — a TextField replacement
/// that adds toolbar formatting support. Ideal for chat inputs and
/// compact editing contexts.
class InlineMarkdownEditor extends StatelessWidget {
  /// Creates an [InlineMarkdownEditor].
  const InlineMarkdownEditor({
    required this.controller,
    this.focusNode,
    this.hintText = 'Type with markdown...',
    this.maxLines = 5,
    this.minLines = 1,
    this.enabled = true,
    this.onSubmitted,
    this.textInputAction,
    super.key,
  });

  /// Text editing controller.
  final TextEditingController controller;

  /// Focus node.
  final FocusNode? focusNode;

  /// Placeholder text.
  final String hintText;

  /// Maximum visible lines.
  final int maxLines;

  /// Minimum visible lines.
  final int minLines;

  /// Whether the field is interactive.
  final bool enabled;

  /// Called when the user submits.
  final ValueChanged<String>? onSubmitted;

  /// The text input action.
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      textInputAction: textInputAction ?? TextInputAction.newline,
      maxLines: maxLines,
      minLines: minLines,
      keyboardType: TextInputType.multiline,
      style: TextStyle(color: context.kabukTextPrimary),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: context.kabukTextSecondary),
        filled: true,
        fillColor: context.kabukSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingMd,
          vertical: KabukTheme.spacingSm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
