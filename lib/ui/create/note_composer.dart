/// Note composer — minimal, immersive note creation screen.
///
/// Full-screen dark text editor with a translucent background,
/// designed to feel native alongside the camera-first Create view.
/// Supports markdown, tags, and saves to the knowledge store.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/note.dart';
import 'package:kabuk/ui/shared/markdown_editor.dart';
import 'package:kabuk/ui/theme.dart';

/// Immersive note composer with a clean, focused writing experience.
///
/// Occupies the full screen with a dark background and large typography,
/// inspired by Instagram's text story creation mode. The title field
/// is prominent, followed by a markdown editor for the body.
class NoteComposer extends ConsumerStatefulWidget {
  /// Creates a [NoteComposer].
  const NoteComposer({super.key, required this.onSaved, required this.onClose});

  /// Called after a note is saved successfully.
  final VoidCallback onSaved;

  /// Called when the user closes without saving.
  final VoidCallback onClose;

  @override
  ConsumerState<NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends ConsumerState<NoteComposer> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _tagController = TextEditingController();
  final _titleFocus = FocusNode();
  final _bodyFocus = FocusNode();
  final _editorKey = GlobalKey<MarkdownEditorState>();
  final _tags = <String>[];
  bool _saving = false;
  bool _showTags = false;

  @override
  void initState() {
    super.initState();
    // Auto-focus the title after a brief delay.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _tagController.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  bool get _hasContent =>
      _titleController.text.trim().isNotEmpty ||
      _bodyController.text.trim().isNotEmpty;

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      HapticFeedback.lightImpact();
      setState(() => _tags.add(tag));
      _tagController.clear();
    }
  }

  Future<void> _saveNote() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty && body.isEmpty) return;

    setState(() => _saving = true);
    unawaited(HapticFeedback.mediumImpact());

    try {
      final store = ref.read(knowledgeStoreProvider);

      await store.createNote(
        title: title.isEmpty ? 'Untitled' : title,
        body: body.isEmpty ? null : body,
        tags: _tags,
      );

      if (mounted) {
        unawaited(HapticFeedback.heavyImpact());
        widget.onSaved();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _handleClose() {
    if (_hasContent) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: KabukTheme.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
          ),
          title: const Text('Discard note?'),
          content: const Text(
            'You have unsaved changes. Are you sure you want to discard this note?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                widget.onClose();
              },
              style: TextButton.styleFrom(foregroundColor: KabukTheme.error),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
    } else {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).viewPadding.top;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        color: KabukTheme.background,
        child: Column(
          children: [
            // Top bar.
            Padding(
              padding: EdgeInsets.fromLTRB(8, topPadding + 8, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Close.
                  IconButton(
                    onPressed: _handleClose,
                    icon: const Icon(Icons.close_rounded),
                    color: KabukTheme.textSecondary,
                    iconSize: 24,
                  ),
                  // Save.
                  _saving
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: KabukTheme.accentGreen,
                            ),
                          ),
                        )
                      : GestureDetector(
                          onTap: _hasContent ? _saveNote : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _hasContent
                                  ? KabukTheme.accentGreen
                                  : KabukTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(
                                KabukTheme.radiusXl,
                              ),
                            ),
                            child: Text(
                              'Save',
                              style: TextStyle(
                                color: _hasContent
                                    ? Colors.white
                                    : KabukTheme.textTertiary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                ],
              ),
            ),

            // Title.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KabukTheme.spacingLg,
                KabukTheme.spacingMd,
                KabukTheme.spacingLg,
                0,
              ),
              child: TextField(
                controller: _titleController,
                focusNode: _titleFocus,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                  color: KabukTheme.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
                decoration: const InputDecoration(
                  hintText: 'Title',
                  hintStyle: TextStyle(
                    color: KabukTheme.textTertiary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (_) => _bodyFocus.requestFocus(),
              ),
            ),

            // Body — markdown editor.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KabukTheme.spacingLg,
                ),
                child: MarkdownEditor(
                  key: _editorKey,
                  controller: _bodyController,
                  focusNode: _bodyFocus,
                  hintText: 'Start writing...',
                  minLines: 8,
                  maxLines: null,
                  showToolbar: true,
                  showPreviewToggle: true,
                ),
              ),
            ),

            // Bottom — tags.
            Container(
              padding: EdgeInsets.fromLTRB(
                KabukTheme.spacingMd,
                KabukTheme.spacingSm,
                KabukTheme.spacingMd,
                MediaQuery.of(context).viewPadding.bottom +
                    KabukTheme.spacingSm,
              ),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: KabukTheme.divider, width: 0.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Tags toggle.
                  GestureDetector(
                    onTap: () => setState(() => _showTags = !_showTags),
                    child: Row(
                      children: [
                        Icon(
                          _showTags
                              ? Icons.expand_less_rounded
                              : Icons.tag_rounded,
                          size: 18,
                          color: KabukTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _tags.isEmpty
                              ? 'Add tags'
                              : '${_tags.length} tag${_tags.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: KabukTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_showTags) ...[
                    const SizedBox(height: KabukTheme.spacingSm),
                    // Tag input.
                    Container(
                      decoration: BoxDecoration(
                        color: KabukTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(
                          KabukTheme.radiusSm,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _tagController,
                              onSubmitted: (_) => _addTag(),
                              style: const TextStyle(
                                fontSize: 13,
                                color: KabukTheme.textPrimary,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Type a tag...',
                                hintStyle: TextStyle(
                                  color: KabukTheme.textTertiary,
                                  fontSize: 13,
                                ),
                                prefixIcon: Icon(
                                  Icons.tag_rounded,
                                  size: 16,
                                  color: KabukTheme.textTertiary,
                                ),
                                prefixIconConstraints: BoxConstraints(
                                  minWidth: 32,
                                ),
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _addTag,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            color: KabukTheme.accentGreen,
                            iconSize: 18,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_tags.isNotEmpty) ...[
                      const SizedBox(height: KabukTheme.spacingSm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: KabukTheme.spacingXs,
                          runSpacing: KabukTheme.spacingXs,
                          children: _tags
                              .map(
                                (tag) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: KabukTheme.accentGreen.withAlpha(20),
                                    borderRadius: BorderRadius.circular(
                                      KabukTheme.radiusSm,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        tag,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: KabukTheme.accentGreen,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        onTap: () =>
                                            setState(() => _tags.remove(tag)),
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 14,
                                          color: KabukTheme.accentGreen
                                              .withAlpha(180),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
