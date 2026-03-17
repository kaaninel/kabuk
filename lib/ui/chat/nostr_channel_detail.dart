/// Nostr public channel chat view — NIP-28 group messaging.
///
/// Displays messages for a public channel identified by its kind-40 event ID
/// (channelEventId). Messages are sent as kind-42 events via
/// [NostrService.sendChannelMessage] and received through
/// [NostrService.watchChannelMessages].
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/ui/chat/chat_input.dart';
import 'package:kabuk/ui/shared/error_retry.dart';
import 'package:kabuk/ui/theme.dart';

// ---------------------------------------------------------------------------
// Scoped providers
// ---------------------------------------------------------------------------

/// Streams kind-42 messages for a given channel event ID.
final _channelMessagesProvider =
    StreamProvider.family<List<NostrEvent>, String>((ref, channelId) {
      final nostr = ref.watch(nostrServiceProvider);
      final controller = StreamController<List<NostrEvent>>();
      final messages = <String, NostrEvent>{};
      final sub = nostr.watchChannelMessages(channelId).listen((ev) {
        messages[ev.id] = ev;
        // Sort newest-last for ListView display.
        final sorted = messages.values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        if (!controller.isClosed) controller.add(sorted);
      });
      ref.onDispose(() {
        sub.cancel();
        controller.close();
      });
      return controller.stream;
    });

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Full-screen chat view for a NIP-28 public channel.
///
/// Displays the scrollable message list with sender avatars resolved via
/// [nostrProfileProvider], an optional reply banner, and the [ChatInput]
/// bar at the bottom.
class NostrChannelDetail extends ConsumerStatefulWidget {
  /// Creates a [NostrChannelDetail].
  const NostrChannelDetail({
    required this.conversationId,
    required this.channelEventId,
    required this.channelName,
    this.channelAbout,
    super.key,
  });

  /// The local conversation ID stored in the Drift database.
  final String conversationId;

  /// The NIP-28 kind-40 event ID that identifies the channel.
  final String channelEventId;

  /// The channel name shown in the AppBar.
  final String channelName;

  /// Optional channel description shown as an AppBar subtitle.
  final String? channelAbout;

  @override
  ConsumerState<NostrChannelDetail> createState() => _NostrChannelDetailState();
}

class _NostrChannelDetailState extends ConsumerState<NostrChannelDetail> {
  final _scrollController = ScrollController();
  bool _isNearBottom = true;
  bool _isSending = false;

  /// The event being replied to.
  NostrEvent? _replyToEvent;

  /// My own Nostr pubkey — resolved once to avoid async on every build.
  String? _myPubkey;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _resolveMyPubkey();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(activeConversationProvider.notifier).state =
            widget.conversationId;
        ref.read(databaseProvider).resetUnreadCount(widget.conversationId);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _resolveMyPubkey() async {
    final key = await ref.read(authServiceProvider).getPublicKeyHex();
    if (mounted) setState(() => _myPubkey = key);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    const threshold = 100.0;
    final isNear =
        _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <
        threshold;
    if (isNear != _isNearBottom) setState(() => _isNearBottom = isNear);
  }

  // ---------------------------------------------------------------------------
  // Send
  // ---------------------------------------------------------------------------

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isSending) return;
    setState(() => _isSending = true);
    final replyId = _replyToEvent?.id;
    final replyContent = _replyToEvent?.content;
    setState(() => _replyToEvent = null);

    try {
      final nostr = ref.read(nostrServiceProvider);
      await nostr.sendChannelMessage(
        widget.channelEventId,
        text.trim(),
        replyTo: replyId,
      );
      _scrollToBottom();
      await ref
          .read(databaseProvider)
          .updateConversationPreview(
            widget.conversationId,
            lastMessage: text.trim(),
            lastMessageAt: DateTime.now(),
          );
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      // Restore reply state so the user can retry.
      if (replyId != null && mounted) {
        final dummyReply = _replyToEvent;
        if (dummyReply == null && replyContent != null) {
          // Recreate a minimal stub so the UI shows the reply banner again.
          setState(() {
            _replyToEvent = NostrEvent(
              id: replyId,
              pubkey: '',
              createdAt: 0,
              kind: 42,
              tags: const [],
              content: replyContent,
              sig: '',
            );
          });
        }
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(
      _channelMessagesProvider(widget.channelEventId),
    );

    return Scaffold(
      backgroundColor: KabukTheme.background,
      appBar: AppBar(
        backgroundColor: KabukTheme.surface,
        leadingWidth: 48,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.tag_rounded,
                  size: 16,
                  color: KabukTheme.accentGreen,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    widget.channelName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (widget.channelAbout != null && widget.channelAbout!.isNotEmpty)
              Text(
                widget.channelAbout!,
                style: const TextStyle(
                  fontSize: 12,
                  color: KabukTheme.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              )
            else
              Text(
                'Public channel · ${widget.channelEventId.substring(0, 8)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: KabukTheme.textSecondary,
                ),
              ),
          ],
        ),
        actions: [
          PopupMenuButton<_ChannelAction>(
            icon: const Icon(Icons.more_vert_rounded),
            color: KabukTheme.surfaceElevated,
            onSelected: (action) => _handleAppBarAction(context, action),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _ChannelAction.copyChannelId,
                child: ListTile(
                  leading: Icon(Icons.copy_rounded, size: 20),
                  title: Text('Copy Channel ID'),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: _ChannelAction.channelInfo,
                child: ListTile(
                  leading: Icon(Icons.info_outline_rounded, size: 20),
                  title: Text('Channel Info'),
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Message list.
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: KabukTheme.accentGreen),
              ),
              error: (e, _) => ErrorRetryWidget.fromError(
                e,
                onRetry: () => ref.invalidate(
                  _channelMessagesProvider(widget.channelEventId),
                ),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tag_rounded,
                          size: 48,
                          color: KabukTheme.textTertiary,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'No messages yet.\nBe the first to say something!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: KabukTheme.textSecondary),
                        ),
                      ],
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_isNearBottom) _scrollToBottom(animated: false);
                });
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: KabukTheme.spacingMd,
                    vertical: KabukTheme.spacingSm,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (ctx, i) => _MessageBubble(
                    key: ValueKey(messages[i].id),
                    event: messages[i],
                    isOwn: messages[i].pubkey == _myPubkey,
                    onReply: (ev) => setState(() => _replyToEvent = ev),
                    onDelete: messages[i].pubkey == _myPubkey
                        ? _deleteMessage
                        : null,
                  ),
                );
              },
            ),
          ),
          // Scroll-to-bottom FAB.
          if (!_isNearBottom)
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(
                  right: KabukTheme.spacingMd,
                  bottom: KabukTheme.spacingSm,
                ),
                child: FloatingActionButton.small(
                  onPressed: _scrollToBottom,
                  backgroundColor: KabukTheme.surfaceElevated,
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: KabukTheme.accentGreen,
                  ),
                ),
              ),
            ),
          // Reply banner.
          if (_replyToEvent != null) _buildReplyBanner(),
          // Input bar.
          ChatInput(onSend: _sendMessage),
        ],
      ),
    );
  }

  Widget _buildReplyBanner() {
    final ev = _replyToEvent!;
    return Container(
      color: KabukTheme.surfaceVariant,
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingXs,
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: KabukTheme.accentGreen,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to ${ev.pubkey.length >= 8 ? ev.pubkey.substring(0, 8) : ev.pubkey}…',
                  style: const TextStyle(
                    fontSize: 11,
                    color: KabukTheme.accentGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  ev.content,
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
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(() => _replyToEvent = null),
            color: KabukTheme.textSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _deleteMessage(NostrEvent ev) async {
    try {
      await ref.read(nostrServiceProvider).deleteEvents([ev.id]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _handleAppBarAction(BuildContext context, _ChannelAction action) {
    switch (action) {
      case _ChannelAction.copyChannelId:
        Clipboard.setData(ClipboardData(text: widget.channelEventId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Channel ID copied'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case _ChannelAction.channelInfo:
        _showChannelInfo(context);
    }
  }

  void _showChannelInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KabukTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(KabukTheme.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: KabukTheme.accentGreen.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.tag_rounded,
                    color: KabukTheme.accentGreen,
                  ),
                ),
                const SizedBox(width: KabukTheme.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.channelName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (widget.channelAbout != null &&
                          widget.channelAbout!.isNotEmpty)
                        Text(
                          widget.channelAbout!,
                          style: const TextStyle(
                            color: KabukTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            const Divider(color: KabukTheme.divider),
            const SizedBox(height: KabukTheme.spacingSm),
            SelectableText(
              'Channel ID: ${widget.channelEventId}',
              style: const TextStyle(
                fontSize: 12,
                color: KabukTheme.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private types
// ---------------------------------------------------------------------------

enum _ChannelAction { copyChannelId, channelInfo }

// ---------------------------------------------------------------------------
// Message bubble
// ---------------------------------------------------------------------------

/// A single message bubble for a NIP-28 channel message.
class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({
    required this.event,
    required this.isOwn,
    required this.onReply,
    this.onDelete,
    super.key,
  });

  final NostrEvent event;
  final bool isOwn;
  final ValueChanged<NostrEvent> onReply;
  final ValueChanged<NostrEvent>? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(nostrProfileProvider(event.pubkey));
    final displayName = profileAsync.maybeWhen(
      data: (p) => p?.displayName ?? p?.name ?? _shortPubkey(event.pubkey),
      orElse: () => _shortPubkey(event.pubkey),
    );
    final avatarUrl = profileAsync.maybeWhen(
      data: (p) => p?.picture,
      orElse: () => null,
    );
    final time = DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000);

    // Check for a reply reference tag.
    final replyTag = event.tags
        .where((t) => t.length >= 4 && t[0] == 'e' && t[3] == 'reply')
        .firstOrNull;
    final rootTag = replyTag == null
        ? event.tags
              .where((t) => t.length >= 4 && t[0] == 'e' && t[3] == 'root')
              .firstOrNull
        : null;
    final hasReply = replyTag != null || rootTag != null;

    return GestureDetector(
      onLongPress: () => _showMessageMenu(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isOwn) ...[
              _Avatar(url: avatarUrl, pubkey: event.pubkey),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: isOwn
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isOwn)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      child: Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 11,
                          color: KabukTheme.accentGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isOwn
                          ? KabukTheme.accentGreen.withAlpha(50)
                          : KabukTheme.surfaceElevated,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(KabukTheme.radiusMd),
                        topRight: const Radius.circular(KabukTheme.radiusMd),
                        bottomLeft: isOwn
                            ? const Radius.circular(KabukTheme.radiusMd)
                            : const Radius.circular(4),
                        bottomRight: isOwn
                            ? const Radius.circular(4)
                            : const Radius.circular(KabukTheme.radiusMd),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasReply)
                          Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: KabukTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(6),
                              border: Border(
                                left: BorderSide(
                                  color: KabukTheme.accentGreen.withAlpha(160),
                                  width: 3,
                                ),
                              ),
                            ),
                            child: const Text(
                              'Reply to message',
                              style: TextStyle(
                                fontSize: 11,
                                color: KabukTheme.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        Text(
                          event.content,
                          style: const TextStyle(
                            fontSize: 14,
                            color: KabukTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                    child: Text(
                      _relativeTime(time),
                      style: const TextStyle(
                        fontSize: 10,
                        color: KabukTheme.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isOwn) const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  void _showMessageMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KabukTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: KabukTheme.textTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.reply_rounded, size: 20),
            title: const Text('Reply'),
            onTap: () {
              Navigator.of(ctx).pop();
              onReply(event);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded, size: 20),
            title: const Text('Copy text'),
            onTap: () {
              Navigator.of(ctx).pop();
              Clipboard.setData(ClipboardData(text: event.content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.fingerprint_rounded, size: 20),
            title: const Text('Copy event ID'),
            onTap: () {
              Navigator.of(ctx).pop();
              Clipboard.setData(ClipboardData(text: event.id));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Event ID copied'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          if (onDelete != null)
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: KabukTheme.error,
              ),
              title: const Text(
                'Delete',
                style: TextStyle(color: KabukTheme.error),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                onDelete!(event);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static String _shortPubkey(String pubkey) =>
      pubkey.length >= 8 ? '${pubkey.substring(0, 8)}…' : pubkey;

  static String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '${time.day}/${time.month} $h:$m';
  }
}

// ---------------------------------------------------------------------------
// Avatar
// ---------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  const _Avatar({required this.pubkey, this.url});

  final String pubkey;
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(
        radius: 16,
        backgroundImage: NetworkImage(url!),
        backgroundColor: KabukTheme.surfaceVariant,
        onBackgroundImageError: (_, _) {},
      );
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: KabukTheme.surfaceVariant,
      child: Text(
        pubkey.isNotEmpty ? pubkey[0].toUpperCase() : '#',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: KabukTheme.accentGreen,
        ),
      ),
    );
  }
}
