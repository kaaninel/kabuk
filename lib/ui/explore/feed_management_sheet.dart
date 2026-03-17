/// Feed Management Bottom Sheet — view, edit, and delete feed subscriptions.
///
/// Provides a full management UI for feed subscriptions, accessible from
/// the Explore view's OmniBar or filter bar. Supports renaming feeds,
/// changing categories, adjusting refresh intervals, and unsubscribing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/ui/explore/explore_view.dart';
import 'package:kabuk/ui/theme.dart';

/// Shows the feed management bottom sheet.
///
/// Lists all subscribed feeds and provides edit/delete actions for each.
/// Returns `true` if any changes were made that require a UI refresh.
Future<bool?> showFeedManagementSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _FeedManagementSheet(),
  );
}

/// Shows a confirmation dialog for unsubscribing from a feed.
///
/// Returns `true` if the user confirmed deletion.
Future<bool> showUnsubscribeDialog(
  BuildContext context,
  FeedSubscriptionData feed,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: KabukTheme.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
      ),
      title: const Text('Unsubscribe'),
      content: Text(
        'Remove "${feed.name ?? feed.feedUrl ?? "this feed"}" and all its '
        'articles? This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: KabukTheme.error),
          child: const Text('Unsubscribe'),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _FeedManagementSheet extends ConsumerStatefulWidget {
  const _FeedManagementSheet();

  @override
  ConsumerState<_FeedManagementSheet> createState() =>
      _FeedManagementSheetState();
}

class _FeedManagementSheetState extends ConsumerState<_FeedManagementSheet> {
  bool _changed = false;

  @override
  Widget build(BuildContext context) {
    final subsAsync = ref.watch(subscriptionsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: KabukTheme.surfaceElevated,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(KabukTheme.radiusXl),
            ),
          ),
          child: Column(
            children: [
              // Drag handle.
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: KabukTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.rss_feed_rounded,
                      color: KabukTheme.accentGreen,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Manage Feeds',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: KabukTheme.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: KabukTheme.textTertiary,
                      onPressed: () => Navigator.of(context).pop(_changed),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: KabukTheme.divider),
              // Feed list.
              Expanded(
                child: subsAsync.when(
                  data: (subs) {
                    if (subs.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inbox_rounded,
                                size: 48,
                                color: KabukTheme.textTertiary,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No feed subscriptions yet.\n'
                                'Use the search bar to add feeds.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: KabukTheme.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: subs.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        indent: 68,
                        color: KabukTheme.divider,
                      ),
                      itemBuilder: (context, index) => _FeedTile(
                        feed: subs[index],
                        onDelete: () => _deleteFeed(subs[index]),
                        onEdit: () => _editFeed(subs[index]),
                      ),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text(
                      'Error: $e',
                      style: const TextStyle(color: KabukTheme.textSecondary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteFeed(FeedSubscriptionData feed) async {
    final confirmed = await showUnsubscribeDialog(context, feed);
    if (!confirmed || !mounted) return;

    final store = ref.read(knowledgeStoreProvider);
    await store.deleteFeedSubscription(feed.uri);
    _changed = true;

    ref.invalidate(subscriptionsProvider);
    ref.invalidate(articlesProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unsubscribed from ${feed.name ?? feed.feedUrl ?? "feed"}',
          ),
        ),
      );
    }
  }

  Future<void> _editFeed(FeedSubscriptionData feed) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditFeedSheet(feed: feed),
    );

    if (result == true) {
      _changed = true;
      ref.invalidate(subscriptionsProvider);
    }
  }
}

/// Individual feed tile with icon, name, type badge, and action menu.
class _FeedTile extends StatelessWidget {
  const _FeedTile({
    required this.feed,
    required this.onDelete,
    required this.onEdit,
  });

  final FeedSubscriptionData feed;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final isReddit = feed.feedType == 'reddit';
    final isNostr = feed.feedType == 'nostr';
    final color = isNostr
        ? KabukTheme.purpleAccent
        : isReddit
        ? KabukTheme.redditOrange
        : KabukTheme.blueAccent;
    final icon = isNostr
        ? Icons.bolt_rounded
        : isReddit
        ? Icons.reddit
        : Icons.rss_feed_rounded;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        feed.name ?? feed.feedUrl ?? 'Feed',
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: KabukTheme.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withAlpha(15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              (feed.feedType ?? 'rss').toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (feed.category != null) ...[
            const SizedBox(width: 8),
            Text(
              feed.category!,
              style: const TextStyle(
                fontSize: 12,
                color: KabukTheme.textTertiary,
              ),
            ),
          ],
          if (feed.lastFetched != null) ...[
            const SizedBox(width: 8),
            Text(
              _timeAgo(feed.lastFetched!),
              style: const TextStyle(
                fontSize: 11,
                color: KabukTheme.textTertiary,
              ),
            ),
          ],
        ],
      ),
      trailing: PopupMenuButton<_FeedAction>(
        icon: const Icon(
          Icons.more_vert_rounded,
          color: KabukTheme.textTertiary,
          size: 20,
        ),
        color: KabukTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (action) {
          switch (action) {
            case _FeedAction.edit:
              onEdit();
            case _FeedAction.delete:
              onDelete();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: _FeedAction.edit,
            child: Row(
              children: [
                Icon(
                  Icons.edit_rounded,
                  size: 18,
                  color: KabukTheme.blueAccent,
                ),
                SizedBox(width: 10),
                Text('Edit'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: _FeedAction.delete,
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: KabukTheme.error,
                ),
                SizedBox(width: 10),
                Text('Unsubscribe', style: TextStyle(color: KabukTheme.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

enum _FeedAction { edit, delete }

// =============================================================================
// Edit Feed Sheet
// =============================================================================

/// Bottom sheet for editing a feed subscription's properties.
class EditFeedSheet extends ConsumerStatefulWidget {
  /// Creates an [EditFeedSheet].
  const EditFeedSheet({super.key, required this.feed});

  final FeedSubscriptionData feed;

  @override
  ConsumerState<EditFeedSheet> createState() => _EditFeedSheetState();
}

class _EditFeedSheetState extends ConsumerState<EditFeedSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late int _refreshInterval;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.feed.name ?? '');
    _categoryController = TextEditingController(
      text: widget.feed.category ?? '',
    );
    _refreshInterval = widget.feed.refreshInterval;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: KabukTheme.surfaceElevated,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusXl),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle.
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: KabukTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Header.
            Row(
              children: [
                const Icon(
                  Icons.edit_rounded,
                  color: KabukTheme.blueAccent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Edit Feed',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KabukTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  (widget.feed.feedType ?? 'rss').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: KabukTheme.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Feed URL (read-only).
            Text(
              widget.feed.feedUrl ?? '',
              style: const TextStyle(
                fontSize: 12,
                color: KabukTheme.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            // Name field.
            _label('Display Name'),
            const SizedBox(height: 6),
            _textField(_nameController, 'Feed name'),
            const SizedBox(height: 16),
            // Category field.
            _label('Category'),
            const SizedBox(height: 6),
            _textField(_categoryController, 'Optional category'),
            const SizedBox(height: 16),
            // Refresh interval.
            _label('Refresh Interval'),
            const SizedBox(height: 6),
            _buildRefreshSelector(),
            const SizedBox(height: 28),
            // Save button.
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: KabukTheme.accentGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                  ),
                  disabledBackgroundColor: KabukTheme.accentGreen.withAlpha(80),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: KabukTheme.textSecondary,
      ),
    );
  }

  Widget _textField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: KabukTheme.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: KabukTheme.textTertiary),
        filled: true,
        fillColor: KabukTheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          borderSide: const BorderSide(color: KabukTheme.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          borderSide: const BorderSide(color: KabukTheme.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          borderSide: const BorderSide(color: KabukTheme.accentGreen),
        ),
      ),
    );
  }

  Widget _buildRefreshSelector() {
    const intervals = [
      (15, '15 min'),
      (30, '30 min'),
      (60, '1 hour'),
      (120, '2 hours'),
      (360, '6 hours'),
      (1440, '24 hours'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: intervals.map((entry) {
        final (value, label) = entry;
        final isSelected = _refreshInterval == value;
        return GestureDetector(
          onTap: () => setState(() => _refreshInterval = value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? KabukTheme.accentGreen.withAlpha(20)
                  : KabukTheme.surface,
              borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
              border: Border.all(
                color: isSelected
                    ? KabukTheme.accentGreen.withAlpha(80)
                    : KabukTheme.divider,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? KabukTheme.accentGreen
                    : KabukTheme.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final store = ref.read(knowledgeStoreProvider);
      final name = _nameController.text.trim();
      final category = _categoryController.text.trim();

      await store.updateFeedSubscription(
        widget.feed.uri,
        name: name.isNotEmpty ? name : null,
        category: category.isNotEmpty ? category : null,
        refreshInterval: _refreshInterval,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
