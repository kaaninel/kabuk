/// Chat input bar — text field with markdown toolbar and send button.
///
/// Handles text editing, inline markdown formatting, submit on enter,
/// and accessibility. Includes a collapsible compact markdown toolbar
/// for quick formatting.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:kabuk/ui/shared/kabuk_keyboard.dart';
import 'package:kabuk/ui/theme.dart';

/// A text input bar for sending chat messages with markdown formatting.
///
/// Calls [onSend] with the trimmed text when the user taps the send
/// button or presses Enter (without Shift). The text field is cleared
/// after sending. Includes a compact markdown toolbar.
///
/// When [onAttachment] is provided an attachment button is shown that
/// lets the user pick a media file to send alongside (or instead of) text.
///
/// When [replyToMessage] is non-null, a reply banner is shown above the
/// text field. Tap the ✕ in the banner or call [onCancelReply] to dismiss.
///
/// When [onVoiceRecordStart] and [onVoiceRecordEnd] are both provided, a
/// microphone hold-to-record button is shown in place of the send button
/// when the text field is empty.
class ChatInput extends ConsumerStatefulWidget {
  /// Creates a [ChatInput].
  const ChatInput({
    required this.onSend,
    this.enabled = true,
    this.hintText = 'Ask anything\u2026',
    this.onAttachment,
    this.onMediaSelected,
    this.onVoiceRecorded,
    this.replyToMessage,
    this.onCancelReply,
    this.onVoiceRecordStart,
    this.onVoiceRecordEnd,
    this.onChanged,
    super.key,
  });

  /// Called when the user submits a message.
  final ValueChanged<String> onSend;

  /// Whether the input is interactive.
  final bool enabled;

  /// Hint text shown in the text field.
  final String hintText;

  /// Optional callback invoked when the user taps the attachment button.
  ///
  /// When non-null, an attachment (paper-clip) icon is shown to the left
  /// of the text field. The callee is responsible for opening a media
  /// picker and handling the selected file.
  final VoidCallback? onAttachment;

  /// Called when media is selected from the keyboard gallery panel.
  final ValueChanged<List<String>>? onMediaSelected;

  /// Called when a voice recording is completed from the keyboard voice panel.
  final ValueChanged<String>? onVoiceRecorded;

  /// The message being replied to, shown as a banner above the input.
  ///
  /// When non-null, a reply preview is shown. Dismiss it via [onCancelReply].
  final Message? replyToMessage;

  /// Called when the user cancels the reply (taps ✕ in the reply banner).
  final VoidCallback? onCancelReply;

  /// Called when the user starts a voice recording (long-press mic button).
  final VoidCallback? onVoiceRecordStart;

  /// Called when the user ends a voice recording (releases mic button).
  final VoidCallback? onVoiceRecordEnd;

  /// Called whenever the input text changes.
  ///
  /// Used by the parent to send typing indicators.
  final ValueChanged<String>? onChanged;

  @override
  ConsumerState<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends ConsumerState<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    widget.onChanged?.call(_controller.text);
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: KabukTheme.surface,
        border: Border(top: BorderSide(color: KabukTheme.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reply-to banner.
            if (widget.replyToMessage != null) _buildReplyBanner(),
            // Keyboard with embedded input field, formatting, and modes.
            KabukKeyboard(
              controller: _controller,
              focusNode: _focusNode,
              onMediaSelected: widget.onMediaSelected,
              onVoiceRecorded: widget.onVoiceRecorded,
              onSend: _submit,
              onAttachment: widget.onAttachment,
              hintText: widget.hintText,
              enabled: widget.enabled,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the reply-to preview banner.
  Widget _buildReplyBanner() {
    final msg = widget.replyToMessage!;
    final preview = msg.content.length > 60
        ? '${msg.content.substring(0, 60)}…'
        : msg.content;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      decoration: const BoxDecoration(
        color: KabukTheme.surfaceVariant,
        border: Border(
          left: BorderSide(color: KabukTheme.accentGreen, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg.role == 'user' ? 'You' : 'Them',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: KabukTheme.accentGreen,
                  ),
                ),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: KabukTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: widget.onCancelReply,
            icon: const Icon(Icons.close, size: 16),
            color: KabukTheme.textSecondary,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            tooltip: 'Cancel reply',
          ),
        ],
      ),
    );
  }
}
