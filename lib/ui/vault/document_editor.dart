/// Document editor — block-based note/document editor.
///
/// Full-screen editor for creating and editing documents. Features:
/// - Large editable title
/// - Block-based content model (text, images, audio, video, code, etc.)
/// - Auto-save with debouncing
/// - Markdown editing for text blocks
/// - Media block insertion from camera, gallery, or audio recorder
///
/// Each document is stored as a Note entity with linked ContentBlock
/// entities in the knowledge store.
library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/content_block.dart';
import 'package:kabuk/knowledge/types/note.dart';
import 'package:kabuk/ui/vault/vault_view.dart';
import 'package:kabuk/ui/shared/kabuk_keyboard.dart';
import 'package:kabuk/ui/shared/markdown_editor.dart';
import 'package:kabuk/ui/theme.dart';

// ---------------------------------------------------------------------------
// Document editor
// ---------------------------------------------------------------------------

/// Full-screen document editor with block-based editing.
///
/// Loads the document identified by [documentUri] from the knowledge
/// store, presents an editable title and a list of content blocks,
/// and auto-saves changes on a debounced timer.
class DocumentEditor extends ConsumerStatefulWidget {
  /// Creates a [DocumentEditor].
  const DocumentEditor({
    super.key,
    required this.documentUri,
    required this.onBack,
  });

  /// URI of the document to edit.
  final String documentUri;

  /// Called when the user navigates back.
  final VoidCallback onBack;

  @override
  ConsumerState<DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends ConsumerState<DocumentEditor> {
  final _titleController = TextEditingController();
  final _titleFocusNode = FocusNode();
  final _bodyController = TextEditingController();
  final _bodyFocusNode = FocusNode();

  /// Tracks which controller is currently focused for keyboard input.
  late TextEditingController _activeController = _bodyController;

  bool _loading = true;
  List<ContentBlockData> _blocks = [];
  Timer? _saveTimer;
  bool _dirty = false;
  bool _navigating = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _titleFocusNode.addListener(_onFocusChange);
    _bodyFocusNode.addListener(_onFocusChange);
    _loadDocument();
    // Reset keyboard mode when entering editor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(keyboardModeProvider.notifier).state = KeyboardMode.none;
      }
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _disposed = true;
    if (_dirty) {
      // Capture text synchronously before controllers are disposed.
      _saveImmediate(
        titleText: _titleController.text,
        bodyText: _bodyController.text,
      );
    }
    _titleFocusNode.removeListener(_onFocusChange);
    _bodyFocusNode.removeListener(_onFocusChange);
    _titleController.dispose();
    _titleFocusNode.dispose();
    _bodyController.dispose();
    _bodyFocusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_titleFocusNode.hasFocus) {
      setState(() => _activeController = _titleController);
    } else if (_bodyFocusNode.hasFocus) {
      setState(() => _activeController = _bodyController);
    }
  }

  Future<void> _loadDocument() async {
    final store = ref.read(knowledgeStoreProvider);
    final note = await store.getNoteData(widget.documentUri);
    final blocks = await store.listDocumentBlocks(widget.documentUri);

    if (!mounted) return;
    setState(() {
      _blocks = blocks;
      _titleController.text =
          (note?.name != null && note!.name != 'Untitled') ? note.name! : '';
      // Build body from blocks, or fall back to note text.
      if (blocks.isNotEmpty) {
        _bodyController.text = _blocksToMarkdown(blocks);
      } else {
        _bodyController.text = note?.text ?? '';
      }
      _loading = false;
    });
  }

  /// Converts blocks to a single markdown string for editing.
  String _blocksToMarkdown(List<ContentBlockData> blocks) {
    final buffer = StringBuffer();
    for (final block in blocks) {
      switch (block.type) {
        case BlockType.heading:
          final prefix = '#' * (block.level ?? 1);
          buffer.writeln('$prefix ${block.content ?? ''}');
        case BlockType.text:
          buffer.writeln(block.content ?? '');
        case BlockType.code:
          final lang = block.language ?? '';
          buffer.writeln('```$lang');
          buffer.writeln(block.content ?? '');
          buffer.writeln('```');
        case BlockType.quote:
          for (final line in (block.content ?? '').split('\n')) {
            buffer.writeln('> $line');
          }
        case BlockType.divider:
          buffer.writeln('---');
        case BlockType.checklist:
          final check = (block.checked ?? false) ? 'x' : ' ';
          buffer.writeln('- [$check] ${block.content ?? ''}');
        case BlockType.image:
          buffer.writeln(
            '![${block.caption ?? 'image'}](${block.mediaUri ?? ''})',
          );
        case BlockType.video:
          buffer.writeln('[video: ${block.caption ?? block.mediaUri ?? ''}]');
        case BlockType.audio:
          buffer.writeln('[audio: ${block.caption ?? block.mediaUri ?? ''}]');
        case BlockType.callout:
          buffer.writeln('> **Note:** ${block.content ?? ''}');
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  void _onTitleChanged(String _) {
    _markDirty();
  }

  void _onBodyChanged(String _) {
    _markDirty();
  }

  void _markDirty() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _saveImmediate);
  }

  Future<void> _saveImmediate({String? titleText, String? bodyText}) async {
    if (!_dirty) return;
    // If disposed and no pre-captured text, controllers are gone — bail out.
    if (_disposed && (titleText == null || bodyText == null)) return;
    _dirty = false;

    try {
      final store = ref.read(knowledgeStoreProvider);
      // Use pre-captured text when provided (dispose path), otherwise read
      // from controllers synchronously before any await.
      final title = (titleText ?? _titleController.text).trim();
      final body = (bodyText ?? _bodyController.text).trim();

      // Auto-generate title from body when user hasn't set one.
      final hasUserTitle = title.isNotEmpty && title != 'Untitled';
      String resolvedTitle;
      if (hasUserTitle) {
        resolvedTitle = title;
      } else if (body.isNotEmpty) {
        // Use the first non-empty line, trimmed to a reasonable length.
        final firstLine = body.split('\n').firstWhere(
          (l) => l.trim().isNotEmpty,
          orElse: () => '',
        ).trim();
        resolvedTitle = firstLine.length > 60
            ? '${firstLine.substring(0, 57)}...'
            : firstLine.isNotEmpty
                ? firstLine
                : 'Untitled';
      } else {
        resolvedTitle = 'Untitled';
      }

      // Update the note entity.
      await store.updateNote(
        widget.documentUri,
        title: resolvedTitle,
        body: body,
      );

      // Delete old blocks and recreate from markdown.
      for (final block in _blocks) {
        await store.deleteContentBlock(block.uri);
      }

      // Parse body back into blocks.
      final newBlocks = _markdownToBlocks(body);
      for (var i = 0; i < newBlocks.length; i++) {
        final b = newBlocks[i];
        await store.createContentBlock(
          parentDocument: widget.documentUri,
          type: b.type,
          order: i,
          content: b.content,
          mediaUri: b.mediaUri,
          caption: b.caption,
          language: b.language,
          checked: b.checked,
          level: b.level,
        );
      }

      // Reload blocks for state consistency.
      final updatedBlocks = await store.listDocumentBlocks(widget.documentUri);
      if (mounted) {
        setState(() => _blocks = updatedBlocks);
        ref.invalidate(notesListProvider);
      }
    } on Object catch (e) {
      _dirty = true; // Mark for retry on next save cycle.
      dev.log('Document save failed: $e', name: 'DocumentEditor', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Save failed — will retry'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: KabukTheme.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
            ),
            margin: const EdgeInsets.all(KabukTheme.spacingMd),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Simple markdown → block parser.
  List<_ParsedBlock> _markdownToBlocks(String markdown) {
    final lines = markdown.split('\n');
    final blocks = <_ParsedBlock>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];

      // Empty lines — skip.
      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // Headings.
      final headingMatch = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
      if (headingMatch != null) {
        blocks.add(
          _ParsedBlock(
            type: BlockType.heading,
            content: headingMatch.group(2),
            level: headingMatch.group(1)!.length,
          ),
        );
        i++;
        continue;
      }

      // Code fences.
      final codeFenceMatch = RegExp(r'^```(\w*)$').firstMatch(line);
      if (codeFenceMatch != null) {
        final lang = codeFenceMatch.group(1);
        final codeLines = <String>[];
        i++;
        while (i < lines.length && lines[i].trim() != '```') {
          codeLines.add(lines[i]);
          i++;
        }
        if (i < lines.length) i++; // Skip closing ```.
        blocks.add(
          _ParsedBlock(
            type: BlockType.code,
            content: codeLines.join('\n'),
            language: (lang?.isNotEmpty ?? false) ? lang : null,
          ),
        );
        continue;
      }

      // Dividers.
      if (RegExp(r'^-{3,}$').hasMatch(line.trim())) {
        blocks.add(const _ParsedBlock(type: BlockType.divider));
        i++;
        continue;
      }

      // Checklists.
      final checkMatch = RegExp(r'^-\s+\[([ xX])\]\s+(.*)$').firstMatch(line);
      if (checkMatch != null) {
        blocks.add(
          _ParsedBlock(
            type: BlockType.checklist,
            content: checkMatch.group(2),
            checked: checkMatch.group(1) != ' ',
          ),
        );
        i++;
        continue;
      }

      // Blockquotes.
      if (line.startsWith('> ')) {
        final quoteLines = <String>[];
        while (i < lines.length && lines[i].startsWith('> ')) {
          quoteLines.add(lines[i].substring(2));
          i++;
        }
        blocks.add(
          _ParsedBlock(type: BlockType.quote, content: quoteLines.join('\n')),
        );
        continue;
      }

      // Images.
      final imgMatch = RegExp(r'^!\[(.*?)\]\((.*?)\)$').firstMatch(line);
      if (imgMatch != null) {
        blocks.add(
          _ParsedBlock(
            type: BlockType.image,
            caption: imgMatch.group(1),
            mediaUri: imgMatch.group(2),
          ),
        );
        i++;
        continue;
      }

      // Default: text paragraph.
      final textLines = <String>[];
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !lines[i].startsWith('#') &&
          !lines[i].startsWith('```') &&
          !lines[i].startsWith('> ') &&
          !RegExp(r'^-\s+\[').hasMatch(lines[i]) &&
          !RegExp(r'^-{3,}$').hasMatch(lines[i].trim()) &&
          !RegExp(r'^!\[').hasMatch(lines[i])) {
        textLines.add(lines[i]);
        i++;
      }
      if (textLines.isNotEmpty) {
        blocks.add(
          _ParsedBlock(type: BlockType.text, content: textLines.join('\n')),
        );
      }
    }

    return blocks;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: KabukTheme.accentGreen),
      );
    }

    final topPadding = MediaQuery.of(context).padding.top;

    return Column(
      children: [
        // Top bar with inline title.
        Padding(
          padding: EdgeInsets.fromLTRB(4, topPadding + 4, 4, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: () async {
                  if (_navigating) return;
                  _navigating = true;
                  if (_dirty) await _saveImmediate();
                  widget.onBack();
                },
                icon: const Icon(Icons.arrow_back_rounded),
                color: KabukTheme.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
              const SizedBox(width: 4),
              // Inline title field in app bar.
              Expanded(
                child: TextField(
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  onChanged: _onTitleChanged,
                  keyboardType: TextInputType.none,
                  showCursor: true,
                  style: const TextStyle(
                    color: KabukTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Untitled',
                    hintStyle: TextStyle(
                      color: KabukTheme.textTertiary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                  ),
                  maxLines: 1,
                  textInputAction: TextInputAction.next,
                  onTap: () {
                    ref.read(keyboardModeProvider.notifier).state =
                        KeyboardMode.text;
                  },
                  onSubmitted: (_) => _bodyFocusNode.requestFocus(),
                ),
              ),
              // Save indicator.
              if (_dirty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: KabukTheme.warmAccent.withAlpha(25),
                    borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                  ),
                  child: const Text(
                    '•',
                    style: TextStyle(
                      color: KabukTheme.warmAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              // More actions.
              PopupMenuButton<String>(
                onSelected: _onMenuAction,
                color: KabukTheme.surfaceElevated,
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: KabukTheme.textSecondary,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'save',
                    child: Row(
                      children: [
                        Icon(
                          Icons.save_rounded,
                          size: 16,
                          color: KabukTheme.textPrimary,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Save now',
                          style: TextStyle(
                            color: KabukTheme.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: KabukTheme.error,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Delete',
                          style: TextStyle(
                            color: KabukTheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Body editor — fills all remaining space.
        Expanded(
          child: MarkdownEditor(
            controller: _bodyController,
            focusNode: _bodyFocusNode,
            hintText: 'Start writing...',
            onChanged: _onBodyChanged,
            onTap: () {
              ref.read(keyboardModeProvider.notifier).state =
                  KeyboardMode.text;
            },
            minLines: 12,
            suppressSystemKeyboard: true,
            showToolbar: false,
            showPreviewToggle: false,
          ),
        ),

        // Custom keyboard with integrated markdown toolbar.
        KabukKeyboardAttachment(
          controller: _activeController,
          showMarkdownToolbar: true,
          markdownFocusNode: _bodyFocusNode,
        ),
      ],
    );
  }

  void _onMenuAction(String action) {
    switch (action) {
      case 'save':
        HapticFeedback.mediumImpact();
        _saveImmediate();
      case 'delete':
        _deleteDocument();
    }
  }

  Future<void> _deleteDocument() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surfaceElevated,
        title: const Text(
          'Delete document?',
          style: TextStyle(color: KabukTheme.textPrimary),
        ),
        content: const Text(
          'This action cannot be undone.',
          style: TextStyle(color: KabukTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: KabukTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: KabukTheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _dirty = false;
      final store = ref.read(knowledgeStoreProvider);
      // Delete all blocks first.
      for (final block in _blocks) {
        await store.deleteContentBlock(block.uri);
      }
      await store.deleteNote(widget.documentUri);
      widget.onBack();
    }
  }
}

// ---------------------------------------------------------------------------
// Parsed block — intermediate model for markdown ↔ block conversion
// ---------------------------------------------------------------------------

/// Lightweight block representation for parsing, before persisting
/// to the knowledge store.
class _ParsedBlock {
  const _ParsedBlock({
    required this.type,
    this.content,
    this.mediaUri,
    this.caption,
    this.language,
    this.checked,
    this.level,
  });

  final BlockType type;
  final String? content;
  final String? mediaUri;
  final String? caption;
  final String? language;
  final bool? checked;
  final int? level;
}
