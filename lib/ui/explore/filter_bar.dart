/// Horizontal filter chip bar for feed subscriptions.
///
/// Shows "All", "Nostr", and per-subscription chips with a context menu
/// on long-press for managing (peek, edit, unsubscribe) RSS/Reddit feeds.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/ui/explore/feed_management_sheet.dart';
import 'package:kabuk/ui/theme.dart';

/// Horizontal scrollable row of feed filter chips.
class FilterBar extends StatelessWidget {
  /// Creates a [FilterBar].
  const FilterBar({
    required this.subscriptions,
    required this.selected,
    required this.onSelected,
    this.onUnsubscribed,
    super.key,
  });

  /// Available feed subscriptions.
  final List<FeedSubscriptionData> subscriptions;

  /// Currently selected feed URI, or null for "All".
  final String? selected;

  /// Callback when a chip is tapped.
  final ValueChanged<String?> onSelected;

  /// Callback when a feed is unsubscribed (to refresh data).
  final VoidCallback? onUnsubscribed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _chip(
            label: 'All',
            icon: Icons.public_rounded,
            color: KabukTheme.accentGreen,
            isSelected: selected == null,
            onTap: () => onSelected(null),
          ),
          _chip(
            label: 'Nostr',
            icon: Icons.bolt_rounded,
            color: KabukTheme.purpleAccent,
            isSelected: selected == 'nostr:global',
            onTap: () => onSelected('nostr:global'),
          ),
          ...subscriptions.map((sub) {
            final isReddit = sub.feedType == 'reddit';
            final isNostr = sub.feedType == 'nostr';
            return _chip(
              label: sub.name ?? sub.feedUrl ?? 'Feed',
              icon: isNostr
                  ? Icons.bolt_rounded
                  : isReddit
                  ? Icons.reddit
                  : Icons.rss_feed_rounded,
              color: isNostr
                  ? KabukTheme.purpleAccent
                  : isReddit
                  ? KabukTheme.redditOrange
                  : KabukTheme.blueAccent,
              isSelected: selected == sub.uri,
              onTap: () => onSelected(sub.uri),
              onLongPress: () => _showFeedContextMenu(context, sub),
            );
          }),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onLongPress: onLongPress,
        excludeFromSemantics: true,
        child: FilterChip(
          avatar: Icon(
            icon,
            size: 16,
            color: isSelected ? Colors.white : color,
          ),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? Colors.white : KabukTheme.textSecondary,
            ),
          ),
          selected: isSelected,
          onSelected: (_) {
            HapticFeedback.selectionClick();
            onTap();
          },
          backgroundColor: KabukTheme.surface,
          selectedColor: color.withAlpha(180),
          checkmarkColor: Colors.white,
          showCheckmark: false,
          side: BorderSide(
            color: isSelected ? color : KabukTheme.divider,
            width: isSelected ? 0 : 1,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
    );
  }

  /// Shows a context menu for the given feed subscription.
  void _showFeedContextMenu(BuildContext context, FeedSubscriptionData sub) {
    final isReddit = sub.feedType == 'reddit';
    final color = isReddit ? KabukTheme.redditOrange : KabukTheme.blueAccent;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KabukTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusLg),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with feed name.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isReddit ? Icons.reddit : Icons.rss_feed_rounded,
                          color: color,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sub.name ?? sub.feedUrl ?? 'Feed',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: KabukTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (sub.feedUrl != null)
                              Text(
                                sub.feedUrl!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: KabukTheme.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: KabukTheme.divider),
                // Unsubscribe action.
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: KabukTheme.error,
                  ),
                  title: const Text(
                    'Unsubscribe',
                    style: TextStyle(color: KabukTheme.error),
                  ),
                  subtitle: const Text(
                    'Remove feed and all its articles',
                    style: TextStyle(
                      fontSize: 12,
                      color: KabukTheme.textTertiary,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _confirmUnsubscribe(context, sub);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Confirms and executes feed unsubscription.
  Future<void> _confirmUnsubscribe(
    BuildContext context,
    FeedSubscriptionData sub,
  ) async {
    final confirmed = await showUnsubscribeDialog(context, sub);
    if (!confirmed) return;
    onUnsubscribed?.call();
  }
}
