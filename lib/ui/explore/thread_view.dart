/// Thread view — displays a Nostr note with its reply chain.
///
/// Shows the root note at the top, followed by all replies in
/// chronological order. Supports reply composition.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/services/nostr_utils.dart';
import 'package:kabuk/ui/explore/nostr_providers.dart';
import 'package:kabuk/ui/shared/kabuk_keyboard.dart';
import 'package:kabuk/ui/shared/nostr_author_row.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// Providers
// =============================================================================

/// Fetches replies for a given event ID.
final threadRepliesProvider = FutureProvider.family<List<NostrEvent>, String>((
  ref,
  eventId,
) async {
  final nostr = ref.watch(nostrServiceProvider);
  final replies = await collectNostrEvents(nostr.fetchReplies([eventId]));

  // Sort by timestamp ascending (oldest first).
  replies.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return replies;
});

/// Fetches a single event by ID.
final eventByIdProvider = FutureProvider.family<NostrEvent?, String>((
  ref,
  eventId,
) async {
  final nostr = ref.watch(nostrServiceProvider);
  final events = await collectNostrEvents(
    nostr.subscribe([NostrFilter(ids: [eventId], limit: 1)]),
  );
  return events.isNotEmpty ? events.first : null;
});

// =============================================================================
// Thread View
// =============================================================================

/// Displays a Nostr note thread: a root note and all its replies.
///
/// Navigate to this view by passing the root event ID:
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => ThreadView(eventId: event.id),
/// ));
/// ```
class ThreadView extends ConsumerStatefulWidget {
  /// Creates a [ThreadView] for the given root [eventId].
  const ThreadView({required this.eventId, this.rootEvent, super.key});

  /// The root event ID to display.
  final String eventId;

  /// Optional pre-loaded root event to avoid a network fetch.
  final NostrEvent? rootEvent;

  @override
  ConsumerState<ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends ConsumerState<ThreadView> {
  final _replyController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rootAsync = widget.rootEvent != null
        ? AsyncValue.data(widget.rootEvent)
        : ref.watch(eventByIdProvider(widget.eventId));
    final repliesAsync = ref.watch(threadRepliesProvider(widget.eventId));

    return Scaffold(
      backgroundColor: KabukTheme.background,
      appBar: AppBar(
        title: const Text('Thread'),
        backgroundColor: KabukTheme.surface,
        foregroundColor: KabukTheme.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: rootAsync.when(
              data: (rootEvent) {
                if (rootEvent == null) {
                  return const Center(
                    child: Text(
                      'Event not found',
                      style: TextStyle(color: KabukTheme.textSecondary),
                    ),
                  );
                }

                return repliesAsync.when(
                  data: (replies) => _buildThread(rootEvent, replies),
                  loading: () => _buildThread(rootEvent, const []),
                  error: (e, _) => _buildThread(rootEvent, const []),
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(
                  color: KabukTheme.primaryGreen,
                ),
              ),
              error: (e, _) => Center(
                child: Text(
                  'Error: $e',
                  style: const TextStyle(color: KabukTheme.error),
                ),
              ),
            ),
          ),
          _buildReplyInput(),
        ],
      ),
    );
  }

  Widget _buildThread(NostrEvent root, List<NostrEvent> replies) {
    return ListView.builder(
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      itemCount: 1 + replies.length,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _NoteCard(event: root, isRoot: true);
        }
        return Padding(
          padding: const EdgeInsets.only(left: KabukTheme.spacingLg),
          child: _NoteCard(event: replies[index - 1], isRoot: false),
        );
      },
    );
  }

  Widget _buildReplyInput() {
    return Container(
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: const BoxDecoration(
        color: KabukTheme.surface,
        border: Border(top: BorderSide(color: KabukTheme.divider)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: KabukKeyboard(
                simple: true,
                controller: _replyController,
                hintText: 'Write a reply...',
              ),
            ),
            const SizedBox(width: KabukTheme.spacingSm),
            IconButton(
              onPressed: _isSending ? null : _sendReply,
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: KabukTheme.primaryGreen,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              color: KabukTheme.primaryGreen,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    final nostr = ref.read(nostrServiceProvider);

    setState(() => _isSending = true);
    try {
      // Get root event pubkey for the p-tag.
      final rootEvent =
          widget.rootEvent ??
          await ref.read(eventByIdProvider(widget.eventId).future);

      if (rootEvent != null) {
        await nostr.publishReply(widget.eventId, rootEvent.pubkey, text);
        _replyController.clear();
        // Refresh replies.
        ref.invalidate(threadRepliesProvider(widget.eventId));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }
}

// =============================================================================
// Note Card
// =============================================================================

/// A single note in the thread — root or reply.
class _NoteCard extends ConsumerWidget {
  const _NoteCard({required this.event, required this.isRoot});

  final NostrEvent event;
  final bool isRoot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileForPubkeyProvider(event.pubkey));

    return Container(
      margin: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: BoxDecoration(
        color: isRoot ? KabukTheme.surfaceElevated : KabukTheme.cardColor,
        borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
        border: isRoot
            ? Border.all(color: KabukTheme.primaryGreen.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + name + time
          profileAsync.when(
            data: (profile) => NostrAuthorRow(
              name: profile?.displayName ?? '${event.pubkey.substring(0, 8)}...',
              picture: profile?.picture,
              createdAt: event.createdAt,
              size: AuthorRowSize.medium,
              showNip05: true,
              nip05: profile?.nip05,
            ),
            loading: () => NostrAuthorRow(
              name: '${event.pubkey.substring(0, 8)}...',
              createdAt: event.createdAt,
              size: AuthorRowSize.medium,
            ),
            error: (_, _) => NostrAuthorRow(
              name: '${event.pubkey.substring(0, 8)}...',
              createdAt: event.createdAt,
              size: AuthorRowSize.medium,
            ),
          ),

          const SizedBox(height: KabukTheme.spacingSm),

          // Content
          Text(
            event.content,
            style: TextStyle(
              color: KabukTheme.textPrimary,
              fontSize: isRoot ? 15 : 14,
              height: 1.5,
            ),
          ),

          // Tags
          if (event.tags.any((t) => t.isNotEmpty && t[0] == 't')) ...[
            const SizedBox(height: KabukTheme.spacingSm),
            Wrap(
              spacing: KabukTheme.spacingXs,
              children: event.tags
                  .where((t) => t.length >= 2 && t[0] == 't')
                  .map(
                    (t) => Chip(
                      label: Text(
                        '#${t[1]}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: KabukTheme.purpleAccent,
                        ),
                      ),
                      backgroundColor: KabukTheme.surfaceVariant,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide.none,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}


