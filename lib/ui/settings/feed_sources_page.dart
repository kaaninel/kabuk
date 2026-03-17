/// Feed Sources — full-page management for feed subscriptions.
///
/// Accessible from Settings, this page lists all configured feed sources
/// with add/edit/delete capabilities. Reuses the knowledge store's
/// [FeedSubscriptionData] and the edit sheet from `feed_management_sheet`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/ui/explore/explore_view.dart';
import 'package:kabuk/ui/explore/feed_management_sheet.dart';
import 'package:kabuk/ui/theme.dart';

/// Full-page feed source management, accessible from Settings.
class FeedSourcesPage extends ConsumerStatefulWidget {
  /// Creates a [FeedSourcesPage].
  const FeedSourcesPage({super.key});

  @override
  ConsumerState<FeedSourcesPage> createState() => _FeedSourcesPageState();
}

class _FeedSourcesPageState extends ConsumerState<FeedSourcesPage> {
  @override
  Widget build(BuildContext context) {
    final subsAsync = ref.watch(subscriptionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed Sources'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add feed source',
            onPressed: () => _showAddFeedDialog(context),
          ),
        ],
      ),
      body: subsAsync.when(
        data: (subs) {
          if (subs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: KabukTheme.warmAccent.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.rss_feed_rounded,
                        size: 36,
                        color: KabukTheme.warmAccent,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'No feed sources yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: KabukTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add subreddits, RSS feeds, or Nostr topics\n'
                      'to populate your Explore feed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: KabukTheme.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _showAddFeedDialog(context),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Source'),
                      style: FilledButton.styleFrom(
                        backgroundColor: KabukTheme.accentGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(KabukTheme.radiusMd),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(
              horizontal: KabukTheme.spacingMd,
              vertical: KabukTheme.spacingSm,
            ),
            itemCount: subs.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: KabukTheme.spacingXs),
            itemBuilder: (context, index) => _FeedSourceTile(
              feed: subs[index],
              onDelete: () => _deleteFeed(subs[index]),
              onEdit: () => _editFeed(subs[index]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Error loading feeds: $e',
            style: const TextStyle(color: KabukTheme.textSecondary),
          ),
        ),
      ),
      floatingActionButton: subsAsync.whenOrNull(
        data: (subs) => subs.isNotEmpty
            ? FloatingActionButton(
                onPressed: () => _showAddFeedDialog(context),
                backgroundColor: KabukTheme.accentGreen,
                child: const Icon(Icons.add_rounded, color: Colors.white),
              )
            : null,
      ),
    );
  }

  Future<void> _deleteFeed(FeedSubscriptionData feed) async {
    final confirmed = await showUnsubscribeDialog(context, feed);
    if (!confirmed || !mounted) return;

    final store = ref.read(knowledgeStoreProvider);
    await store.deleteFeedSubscription(feed.uri);

    ref.invalidate(subscriptionsProvider);
    ref.invalidate(articlesProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Removed ${feed.name ?? feed.feedUrl ?? "feed"}',
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
      ref.invalidate(subscriptionsProvider);
    }
  }

  Future<void> _showAddFeedDialog(BuildContext context) async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddFeedDialog(),
    );

    if (added == true) {
      ref.invalidate(subscriptionsProvider);
      ref.invalidate(articlesProvider);
    }
  }
}

// ---------------------------------------------------------------------------
// Feed source tile
// ---------------------------------------------------------------------------

class _FeedSourceTile extends StatelessWidget {
  const _FeedSourceTile({
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
    final isFourchan = feed.feedType == 'fourchan';
    final color = isNostr
        ? KabukTheme.purpleAccent
        : isReddit
            ? KabukTheme.redditOrange
            : isFourchan
                ? const Color(0xFF648034)
                : KabukTheme.blueAccent;
    final icon = isNostr
        ? Icons.bolt_rounded
        : isReddit
            ? Icons.reddit
            : isFourchan
                ? Icons.image_rounded
                : Icons.rss_feed_rounded;

    return Container(
      decoration: BoxDecoration(
        color: KabukTheme.cardColor,
        borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
        border: Border.all(color: KabukTheme.divider, width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        feed.name ?? feed.feedUrl ?? 'Feed',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: KabukTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
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
                            Flexible(
                              child: Text(
                                feed.category!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: KabukTheme.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: KabukTheme.textTertiary,
                  ),
                  tooltip: 'Remove',
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Feed Dialog
// ---------------------------------------------------------------------------

class _AddFeedDialog extends ConsumerStatefulWidget {
  const _AddFeedDialog();

  @override
  ConsumerState<_AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends ConsumerState<_AddFeedDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  FeedSourceType _selectedType = FeedSourceType.reddit;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KabukTheme.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
      ),
      title: const Row(
        children: [
          Icon(Icons.add_rounded, color: KabukTheme.accentGreen, size: 22),
          SizedBox(width: 10),
          Text('Add Feed Source'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type selector
            const Text(
              'Source Type',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: KabukTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            _buildTypeSelector(),
            const SizedBox(height: 20),
            // URL / identifier field
            Text(
              _urlLabel,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: KabukTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              style: const TextStyle(
                color: KabukTheme.textPrimary,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: _urlHint,
                hintStyle: const TextStyle(color: KabukTheme.textTertiary),
                filled: true,
                fillColor: KabukTheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(KabukTheme.radiusSm),
                  borderSide: const BorderSide(color: KabukTheme.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(KabukTheme.radiusSm),
                  borderSide: const BorderSide(color: KabukTheme.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(KabukTheme.radiusSm),
                  borderSide:
                      const BorderSide(color: KabukTheme.accentGreen),
                ),
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 16),
            // Display name field
            const Text(
              'Display Name (optional)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: KabukTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              style: const TextStyle(
                color: KabukTheme.textPrimary,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: 'Custom feed name',
                hintStyle: const TextStyle(color: KabukTheme.textTertiary),
                filled: true,
                fillColor: KabukTheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(KabukTheme.radiusSm),
                  borderSide: const BorderSide(color: KabukTheme.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(KabukTheme.radiusSm),
                  borderSide: const BorderSide(color: KabukTheme.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(KabukTheme.radiusSm),
                  borderSide:
                      const BorderSide(color: KabukTheme.accentGreen),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _addFeed,
          style: FilledButton.styleFrom(
            backgroundColor: KabukTheme.accentGreen,
            foregroundColor: Colors.white,
          ),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Add'),
        ),
      ],
    );
  }

  Widget _buildTypeSelector() {
    const types = [
      (FeedSourceType.reddit, Icons.reddit, 'Reddit', KabukTheme.redditOrange),
      (FeedSourceType.rss, Icons.rss_feed_rounded, 'RSS', KabukTheme.blueAccent),
      (FeedSourceType.nostr, Icons.bolt_rounded, 'Nostr', KabukTheme.purpleAccent),
      (FeedSourceType.fourchan, Icons.image_rounded, '4chan', Color(0xFF648034)),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: types.map((entry) {
        final (type, icon, label, color) = entry;
        final isSelected = _selectedType == type;
        return GestureDetector(
          onTap: () => setState(() => _selectedType = type),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? color.withAlpha(20) : KabukTheme.surface,
              borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
              border: Border.all(
                color: isSelected ? color.withAlpha(80) : KabukTheme.divider,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: isSelected ? color : KabukTheme.textTertiary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? color : KabukTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String get _urlLabel => switch (_selectedType) {
    FeedSourceType.reddit => 'Subreddit Name',
    FeedSourceType.rss || FeedSourceType.atom => 'Feed URL',
    FeedSourceType.nostr => 'Nostr Hashtag or npub',
    FeedSourceType.fourchan => 'Board Name',
  };

  String get _urlHint => switch (_selectedType) {
    FeedSourceType.reddit => 'e.g. technology, flutter, privacy',
    FeedSourceType.rss || FeedSourceType.atom => 'https://example.com/feed.xml',
    FeedSourceType.nostr => 'e.g. bitcoin, npub1...',
    FeedSourceType.fourchan => 'e.g. g, sci, wg',
  };

  Future<void> _addFeed() async {
    final input = _urlController.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'Please enter a value');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final store = ref.read(knowledgeStoreProvider);
      final feedType = _selectedType.name;

      // Build feed URL and display name based on type.
      final (feedUrl, displayName) = switch (_selectedType) {
        FeedSourceType.reddit => (
          'https://www.reddit.com/r/${input.replaceAll(RegExp(r'^r/'), '')}.json',
          'r/${input.replaceAll(RegExp(r'^r/'), '')}',
        ),
        FeedSourceType.fourchan => (
          'https://a.4cdn.org/${input.replaceAll("/", "")}/catalog.json',
          '/${input.replaceAll("/", "")}/',
        ),
        FeedSourceType.nostr => (
          input,
          input.startsWith('npub') ? input.substring(0, 16) : '#$input',
        ),
        FeedSourceType.rss || FeedSourceType.atom => (
          input,
          _nameController.text.trim().isNotEmpty
              ? _nameController.text.trim()
              : Uri.tryParse(input)?.host ?? input,
        ),
      };

      final name = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : displayName;

      await store.createFeedSubscription(
        name: name,
        feedUrl: feedUrl,
        feedType: feedType,
      );

      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to add feed: $e';
        });
      }
    }
  }
}
