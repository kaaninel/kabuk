/// Conversation detail — shows messages and input for a single conversation.
///
/// Pushed as a full-screen route from either the conversation list
/// or the Quick Chat expand button. Shares state with the overlay
/// through Riverpod providers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:kabuk/ui/chat/chat_input.dart';
import 'package:kabuk/ui/chat/chat_service.dart';
import 'package:kabuk/ui/chat/message_bubble.dart';
import 'package:kabuk/ui/chat/message_info_sheet.dart';
import 'package:kabuk/ui/settings/settings_view.dart';
import 'package:kabuk/ui/shared/error_retry.dart';
import 'package:kabuk/ui/shared/kabuk_markdown.dart';
import 'package:kabuk/ui/theme.dart';

/// Full-screen conversation view for a single thread.
///
/// Displays the message list, streaming response, and input bar.
/// When [isNewChat] is true, shows an empty-state prompt instead
/// of a spinner while waiting for the first message.
class ConversationDetail extends ConsumerStatefulWidget {
  /// Creates a [ConversationDetail].
  const ConversationDetail({
    required this.title,
    this.isNewChat = false,
    super.key,
  });

  /// The display title shown in the app bar.
  final String title;

  /// Whether this was opened without an existing conversation.
  final bool isNewChat;

  @override
  ConsumerState<ConversationDetail> createState() => _ConversationDetailState();
}

class _ConversationDetailState extends ConsumerState<ConversationDetail> {
  final _scrollController = ScrollController();
  bool _isNearBottom = true;
  // Guards against queuing multiple identical scroll callbacks per frame.
  bool _scrollScheduled = false;

  /// Optimistic messages that haven't yet appeared from the DB stream.
  /// Cleared automatically when the stream delivers the matching message.
  final _pendingOptimistic = <Message>[];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    const threshold = 100.0;
    final isNear =
        _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <
        threshold;
    if (isNear != _isNearBottom) {
      setState(() => _isNearBottom = isNear);
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    // Add optimistic message immediately for instant UI feedback.
    final optimisticMsg = Message(
      id: 'optimistic_${DateTime.now().microsecondsSinceEpoch}',
      conversationId: ref.read(activeConversationProvider) ?? '',
      role: 'user',
      agentName: null,
      content: text,
      metadata: null,
      timestamp: DateTime.now(),
      nostrEventId: null,
      status: 'sending',
      replyToId: null,
      isPinned: false,
      expiresAt: null,
    );
    setState(() => _pendingOptimistic.add(optimisticMsg));
    _scrollToBottom();

    await ref.read(chatServiceProvider).sendMessage(text);
    _scrollToBottom();
  }

  void _scrollToBottom({bool animated = true}) {
    // Debounce: only queue one callback per frame to avoid flooding the
    // post-frame callback queue during fast LLM streaming.
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (_scrollController.hasClients) {
        if (animated) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
        _isNearBottom = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversationId = ref.watch(activeConversationProvider);
    final messagesAsync = ref.watch(messagesProvider);
    final isProcessing = ref.watch(isProcessingProvider);
    final streamingText = ref.watch(streamingTextProvider);
    final processingStatus = ref.watch(processingStatusProvider);

    // Auto-scroll when new messages arrive and clear optimistic messages.
    ref.listen(messagesProvider, (prev, next) {
      final prevLen = prev?.valueOrNull?.length ?? 0;
      final nextLen = next.valueOrNull?.length ?? 0;
      if (nextLen > prevLen) {
        // DB now has the real messages — clear optimistic copies.
        if (_pendingOptimistic.isNotEmpty) {
          setState(_pendingOptimistic.clear);
        }
        if (_isNearBottom) _scrollToBottom();
      }
    });

    // Auto-scroll during streaming.
    ref.listen(streamingTextProvider, (_, next) {
      if (next != null && _isNearBottom) _scrollToBottom(animated: false);
    });

    return PopScope(
      onPopInvokedWithResult: (_, _) {
        if (widget.isNewChat) {
          ref.read(activeConversationProvider.notifier).state = null;
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Column(
          children: [
            // Message list.
            Expanded(
              child: Stack(
                children: [
                  conversationId == null && widget.isNewChat
                      ? _buildEmptyState(context)
                      : messagesAsync.when(
                          data: _buildMessageList,
                          loading: () {
                            // Avoid flashing a spinner when transitioning from
                            // the empty state after the first message is sent.
                            // Use cached data if available; otherwise show a
                            // blank area so the transition is seamless.
                            final cached = messagesAsync.valueOrNull;
                            if (cached != null) {
                              return _buildMessageList(cached);
                            }
                            if (widget.isNewChat && conversationId != null) {
                              return const SizedBox.expand();
                            }
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          },
                          error: (e, _) => ErrorRetryWidget.fromError(
                            e,
                            onRetry: () => ref.invalidate(messagesProvider),
                          ),
                        ),
                  // Scroll-to-bottom FAB.
                  if (!_isNearBottom && conversationId != null)
                    Positioned(
                      right: KabukTheme.spacingMd,
                      bottom: KabukTheme.spacingSm,
                      child: FloatingActionButton.small(
                        onPressed: _scrollToBottom,
                        backgroundColor: KabukTheme.cardColor.withAlpha(230),
                        foregroundColor: KabukTheme.textSecondary,
                        elevation: 2,
                        child: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ),
                ],
              ),
            ),
            // Streaming response.
            if (streamingText != null)
              _buildStreamingBubble(context, streamingText),
            // Thinking / status indicator.
            if (isProcessing && streamingText == null)
              _ThinkingBubble(status: processingStatus),
            // Input bar.
            ChatInput(onSend: _sendMessage),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamingBubble(BuildContext context, String text) {
    final maxWidth = MediaQuery.of(context).size.width * 0.75;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingXs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: KabukTheme.primaryGreen.withAlpha(40),
            child: const Icon(
              Icons.smart_toy_outlined,
              size: 18,
              color: KabukTheme.accentGreen,
            ),
          ),
          const SizedBox(width: KabukTheme.spacingSm),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: KabukTheme.spacingMd,
                  vertical: KabukTheme.spacingSm + 2,
                ),
                decoration: BoxDecoration(
                  color: KabukTheme.cardColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(KabukTheme.radiusMd),
                    topRight: Radius.circular(KabukTheme.radiusMd),
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(KabukTheme.radiusMd),
                  ),
                  border: Border.all(color: KabukTheme.divider, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KabukMarkdown(data: text),
                    const Text(
                      '▍',
                      style: TextStyle(
                        color: KabukTheme.accentGreen,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isConfigured = ref.watch(llmConfigProvider) != null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(KabukTheme.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isConfigured ? Icons.chat_outlined : Icons.warning_amber_rounded,
              size: 48,
              color: isConfigured
                  ? KabukTheme.accentGreen.withAlpha(100)
                  : KabukTheme.error.withAlpha(180),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            Text(
              isConfigured ? 'Start chatting' : 'AI Not Configured',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            Text(
              isConfigured
                  ? 'Ask me anything — I can help with notes,\nsearch, and everyday tasks.'
                  : 'Set up an LLM provider to enable chat.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (!isConfigured) ...[
              const SizedBox(height: KabukTheme.spacingLg),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SettingsView()),
                ),
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Configure AI'),
              ),
            ],
            if (isConfigured) ...[
              const SizedBox(height: KabukTheme.spacingLg),
              Wrap(
                spacing: KabukTheme.spacingSm,
                runSpacing: KabukTheme.spacingSm,
                alignment: WrapAlignment.center,
                children: [
                  _SuggestionChip(
                    icon: Icons.edit_note_rounded,
                    label: 'Create a note',
                    onTap: () => _sendMessage('Create a note'),
                  ),
                  _SuggestionChip(
                    icon: Icons.search_rounded,
                    label: 'Search my data',
                    onTap: () => _sendMessage('Search my knowledge store'),
                  ),
                  _SuggestionChip(
                    icon: Icons.event_rounded,
                    label: 'What\'s on my calendar?',
                    onTap: () => _sendMessage('What events do I have?'),
                  ),
                  _SuggestionChip(
                    icon: Icons.rss_feed_rounded,
                    label: 'Subscribe to a feed',
                    onTap: () => _sendMessage('Subscribe to r/technology'),
                  ),
                  _SuggestionChip(
                    icon: Icons.help_outline_rounded,
                    label: 'What can you do?',
                    onTap: () => _sendMessage('What can you help me with?'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Shows a bottom sheet with message metadata / details.
  void _showMessageInfo(BuildContext context, Message message) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KabukTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusXl),
        ),
      ),
      builder: (ctx) => MessageInfoSheet(message: message),
    );
  }

  Widget _buildMessageList(List<Message> messages) {
    // Merge optimistic messages that haven't appeared in DB yet.
    final merged = [...messages, ..._pendingOptimistic];
    if (merged.isEmpty) return _buildEmptyState(context);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingSm,
      ),
      itemCount: merged.length,
      itemBuilder: (context, index) => MessageBubble(
        message: merged[index],
        onTapInfo: () => _showMessageInfo(context, merged[index]),
      ),
    );
  }
}

/// A tappable suggestion chip shown in the empty-state.
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Animated thinking indicator shown while the AI is processing.
///
/// Displays a pulsing dot and a status label (e.g. "Thinking…",
/// "Using Create note…") so the user knows the AI is working.
class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble({this.status});

  /// Current processing status text. Falls back to "Thinking…".
  final String? status;

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.status ?? 'Thinking\u2026';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingSm,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: KabukTheme.primaryGreen.withAlpha(40),
            child: const Icon(
              Icons.smart_toy_outlined,
              size: 18,
              color: KabukTheme.accentGreen,
            ),
          ),
          const SizedBox(width: KabukTheme.spacingSm),
          FadeTransition(
            opacity: _controller.drive(Tween(begin: 0.4, end: 1.0)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: KabukTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: KabukTheme.accentGreen.withAlpha(180),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: KabukTheme.textSecondary,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
