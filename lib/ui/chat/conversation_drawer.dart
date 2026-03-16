/// Conversation management drawer for the chat view.
///
/// Provides a side-panel listing all conversations with options to
/// create, rename, and delete conversations.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:kabuk/ui/theme.dart';

/// Drawer listing all conversations with management actions.
///
/// Supports:
/// - Selecting a conversation (sets [activeConversationProvider]).
/// - Creating a new conversation.
/// - Renaming a conversation via long-press.
/// - Deleting a conversation with a confirmation dialog.
class ConversationDrawer extends ConsumerWidget {
  /// Creates a [ConversationDrawer].
  const ConversationDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationsProvider);
    final activeId = ref.watch(activeConversationProvider);

    return Drawer(
      backgroundColor: KabukTheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, ref),
            const Divider(height: 1, color: KabukTheme.divider),
            Expanded(
              child: conversationsAsync.when(
                data: (conversations) => _buildConversationList(
                  context,
                  ref,
                  conversations,
                  activeId,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    'Error: $e',
                    style: const TextStyle(color: KabukTheme.error),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the drawer header with title and "New Chat" button.
  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingSm,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.chat_bubble_outline,
            color: KabukTheme.accentGreen,
            size: 22,
          ),
          const SizedBox(width: KabukTheme.spacingSm),
          Text('Conversations', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'New chat',
            color: KabukTheme.accentGreen,
            onPressed: () {
              ref.read(activeConversationProvider.notifier).state = null;
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  /// Builds the scrollable list of conversations.
  Widget _buildConversationList(
    BuildContext context,
    WidgetRef ref,
    List<Conversation> conversations,
    String? activeId,
  ) {
    if (conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KabukTheme.spacingXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 48,
                color: KabukTheme.textSecondary.withAlpha(100),
              ),
              const SizedBox(height: KabukTheme.spacingMd),
              const Text(
                'No conversations yet',
                style: TextStyle(color: KabukTheme.textSecondary),
              ),
              const SizedBox(height: KabukTheme.spacingSm),
              const Text(
                'Start chatting to create one.',
                style: TextStyle(color: KabukTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: KabukTheme.spacingSm),
      itemCount: conversations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final conv = conversations[index];
        final isActive = conv.id == activeId;

        return _ConversationTile(
          conversation: conv,
          isActive: isActive,
          onTap: () {
            ref.read(activeConversationProvider.notifier).state = conv.id;
            Navigator.of(context).pop();
          },
          onRename: () => _showRenameDialog(context, ref, conv),
          onDelete: () => _showDeleteDialog(context, ref, conv),
        );
      },
    );
  }

  /// Shows a dialog to rename a conversation.
  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    Conversation conversation,
  ) async {
    final controller = TextEditingController(text: conversation.title);

    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
        title: const Text('Rename conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: KabukTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Enter a new title',
            hintStyle: TextStyle(color: KabukTheme.textSecondary),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            style: FilledButton.styleFrom(
              backgroundColor: KabukTheme.primaryGreen,
            ),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (newTitle != null && newTitle.trim().isNotEmpty) {
      final db = ref.read(databaseProvider);
      await db.upsertConversation(
        ConversationsCompanion(
          id: Value(conversation.id),
          title: Value(newTitle.trim()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// Shows a confirmation dialog before deleting a conversation.
  Future<void> _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    Conversation conversation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
        title: const Text('Delete conversation?'),
        content: Text(
          'This will permanently delete "${conversation.title}" '
          'and all its messages. This cannot be undone.',
          style: const TextStyle(color: KabukTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: KabukTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = ref.read(databaseProvider);
      await db.deleteConversation(conversation.id);

      // Clear active conversation if needed.
      if (ref.read(activeConversationProvider) == conversation.id) {
        ref.read(activeConversationProvider.notifier).state = null;
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Conversation tile
// ---------------------------------------------------------------------------

/// A single conversation entry in the drawer list.
class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.isActive,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  /// The conversation data to display.
  final Conversation conversation;

  /// Whether this conversation is currently active.
  final bool isActive;

  /// Called when the tile is tapped.
  final VoidCallback onTap;

  /// Called when the user chooses to rename.
  final VoidCallback onRename;

  /// Called when the user chooses to delete.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KabukTheme.spacingSm),
      child: Material(
        color: isActive
            ? KabukTheme.primaryGreen.withAlpha(30)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          onTap: onTap,
          onLongPress: () => _showContextMenu(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KabukTheme.spacingMd,
              vertical: KabukTheme.spacingSm + 2,
            ),
            child: Row(
              children: [
                Icon(
                  isActive ? Icons.chat : Icons.chat_bubble_outline,
                  size: 20,
                  color: isActive
                      ? KabukTheme.accentGreen
                      : KabukTheme.textSecondary,
                ),
                const SizedBox(width: KabukTheme.spacingSm + 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isActive
                              ? KabukTheme.textPrimary
                              : KabukTheme.textPrimary.withAlpha(200),
                          fontSize: 14,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTimestamp(conversation.updatedAt),
                        style: const TextStyle(
                          color: KabukTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _DeleteButton(onPressed: onDelete),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Shows a context menu on long-press with rename and delete options.
  void _showContextMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KabukTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusMd),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(KabukTheme.spacingMd),
              child: Text(
                conversation.title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1, color: KabukTheme.divider),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onRename();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: KabukTheme.error,
              ),
              title: const Text(
                'Delete',
                style: TextStyle(color: KabukTheme.error),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onDelete();
              },
            ),
            const SizedBox(height: KabukTheme.spacingSm),
          ],
        ),
      ),
    );
  }

  /// Formats a conversation timestamp into a human-readable string.
  String _formatTimestamp(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}/${date.year}';
  }
}

/// Small delete button shown at the trailing edge of a conversation tile.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onPressed});

  /// Called when the delete icon is tapped.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: const Icon(Icons.delete_outline),
        color: KabukTheme.textSecondary,
        tooltip: 'Delete conversation',
        onPressed: onPressed,
      ),
    );
  }
}
