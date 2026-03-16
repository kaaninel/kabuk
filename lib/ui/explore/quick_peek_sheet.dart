/// Quick Peek sheet — in-app web preview and subreddit feed peek.
///
/// Provides [QuickPeekSheet] for previewing URLs inline via WebView,
/// and [SubredditPeekSheet] for viewing a subreddit's top posts without
/// subscribing. Launched via long-press on article cards / filter chips,
/// or via the "Peek URL" action in the Explore app bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/follow.dart';
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/ui/shared/feed_image.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

// =============================================================================
// Quick Peek Sheet (WebView)
// =============================================================================

/// A draggable bottom sheet that renders a URL in an in-app WebView.
///
/// Used for quick-peeking article URLs without leaving the app.
/// Supports navigation controls (back/forward/refresh) and an
/// "Open in Browser" escape hatch.
class QuickPeekSheet extends StatefulWidget {
  /// Creates a [QuickPeekSheet] for the given [url].
  const QuickPeekSheet({required this.url, this.title, super.key});

  /// The URL to preview.
  final String url;

  /// Optional title shown in the header (e.g. article name).
  final String? title;

  /// Shows the [QuickPeekSheet] as a modal bottom sheet.
  static void show(BuildContext context, {required String url, String? title}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false, // Prevent sheet drag from stealing WebView scroll.
      backgroundColor: Colors.transparent,
      builder: (_) => QuickPeekSheet(url: url, title: title),
    );
  }

  @override
  State<QuickPeekSheet> createState() => _QuickPeekSheetState();
}

class _QuickPeekSheetState extends State<QuickPeekSheet> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _progress = 0;
  String _currentTitle = '';

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.title ?? '';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(KabukTheme.surface)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress / 100.0);
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() => _isLoading = false);
              _controller.getTitle().then((title) {
                if (mounted && title != null && title.isNotEmpty) {
                  setState(() => _currentTitle = title);
                }
              }).ignore();
              // Inject dark-mode hints so sites that respect prefers-color-scheme
              // render appropriately inside the dark Kabuk shell.
              _controller.runJavaScript('''
(function() {
  try {
    var meta = document.querySelector('meta[name="color-scheme"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.name = 'color-scheme';
      document.head && document.head.appendChild(meta);
    }
    meta.content = 'dark';
    var style = document.createElement('style');
    style.id = '__kabuk_dark';
    if (!document.getElementById('__kabuk_dark')) {
      style.textContent = ':root { color-scheme: dark; }';
      document.head && document.head.appendChild(style);
    }
  } catch(e) {}
})();
''').ignore();
            }
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final displayTitle = _currentTitle.isNotEmpty
        ? _currentTitle
        : _domainFrom(widget.url);

    // Use a fixed-height container instead of DraggableScrollableSheet
    // so that vertical drag/scroll gestures pass through to the WebView.
    final screenHeight = MediaQuery.of(context).size.height;
    return SizedBox(
      height: screenHeight * 0.9,
      child: Container(
        decoration: const BoxDecoration(
          color: KabukTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle — swipe down here to dismiss.
            GestureDetector(
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null &&
                    details.primaryVelocity! > 300) {
                  Navigator.of(context).pop();
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DragHandle(),
                  // Header with title and controls.
                  _PeekHeader(
                    title: displayTitle,
                    onClose: () => Navigator.of(context).pop(),
                    onOpenExternal: () => _openExternal(widget.url),
                    onRefresh: () => _controller.reload(),
                  ),
                ],
              ),
            ),
            // Loading progress bar.
            if (_isLoading)
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: Colors.transparent,
                color: KabukTheme.accentGreen,
                minHeight: 2,
              )
            else
              const SizedBox(height: 2),
            // WebView — Expanded fills all remaining space.
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                child: WebViewWidget(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _domainFrom(String url) {
    try {
      return Uri.parse(url).host;
    } on Object {
      return url;
    }
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// =============================================================================
// Subreddit Peek Sheet
// =============================================================================

/// A draggable bottom sheet that loads and displays a subreddit's posts.
///
/// Fetches the subreddit feed inline using [FeedService] and renders
/// the posts in a compact list. Allows the user to peek at a subreddit
/// without subscribing.
class SubredditPeekSheet extends ConsumerStatefulWidget {
  /// Creates a [SubredditPeekSheet].
  const SubredditPeekSheet({
    required this.subredditName,
    required this.feedUrl,
    super.key,
  });

  /// Display name (e.g. "r/technology").
  final String subredditName;

  /// The feed URL to fetch.
  final String feedUrl;

  /// Shows the [SubredditPeekSheet] as a modal bottom sheet.
  static void show(
    BuildContext context, {
    required String subredditName,
    required String feedUrl,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          SubredditPeekSheet(subredditName: subredditName, feedUrl: feedUrl),
    );
  }

  @override
  ConsumerState<SubredditPeekSheet> createState() => _SubredditPeekSheetState();
}

class _SubredditPeekSheetState extends ConsumerState<SubredditPeekSheet> {
  List<FeedItem>? _items;
  bool _loading = true;
  String? _error;
  bool _isFollowed = false;
  String? _followUri;

  @override
  void initState() {
    super.initState();
    _fetchPosts();
    _checkFollowState();
  }

  Future<void> _checkFollowState() async {
    final profileUrl = 'https://www.reddit.com/${widget.subredditName}';
    final store = ref.read(knowledgeStoreProvider);
    final followed = await store.isFollowing(profileUrl);
    final followUri = followed ? await store.followedUriFor(profileUrl) : null;
    if (mounted) {
      setState(() {
        _isFollowed = followed;
        _followUri = followUri;
      });
    }
  }

  Future<void> _toggleFollow() async {
    final profileUrl = 'https://www.reddit.com/${widget.subredditName}';
    final store = ref.read(knowledgeStoreProvider);
    if (_isFollowed && _followUri != null) {
      await store.unfollowUser(_followUri!);
      if (mounted) {
        setState(() {
          _isFollowed = false;
          _followUri = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unfollowed ${widget.subredditName}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      final uri = await store.createFollowedUser(
        name: widget.subredditName,
        profileUrl: profileUrl,
      );
      if (mounted) {
        setState(() {
          _isFollowed = true;
          _followUri = uri;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Following ${widget.subredditName}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _fetchPosts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final feedService = ref.read(feedServiceProvider);
      final items = await feedService.fetchItems(
        widget.feedUrl,
        type: FeedSourceType.reddit,
      );
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: KabukTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _DragHandle(),
              // Header.
              _PeekHeader(
                title: widget.subredditName,
                icon: Icons.reddit,
                iconColor: const Color(0xFFFF4500),
                onClose: () => Navigator.of(context).pop(),
                onRefresh: _fetchPosts,
                onOpenExternal: () => _openExternal(
                  'https://www.reddit.com/${widget.subredditName}',
                ),
              ),
              // Follow / Unfollow action row.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _toggleFollow,
                      icon: Icon(
                        _isFollowed
                            ? Icons.bookmark_remove_rounded
                            : Icons.bookmark_add_rounded,
                        size: 16,
                      ),
                      label: Text(_isFollowed ? 'Unfollow' : 'Follow'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _isFollowed
                            ? KabukTheme.textSecondary
                            : KabukTheme.accentGreen,
                        side: BorderSide(
                          color: _isFollowed
                              ? KabukTheme.divider
                              : KabukTheme.accentGreen.withAlpha(150),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 32),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: KabukTheme.divider),
              // Content.
              Expanded(child: _buildContent(scrollController)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(ScrollController scrollController) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(color: KabukTheme.accentGreen),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: KabukTheme.error.withAlpha(180),
              ),
              const SizedBox(height: 12),
              const Text(
                'Failed to load',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: KabukTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: KabukTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _fetchPosts,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: TextButton.styleFrom(
                  foregroundColor: KabukTheme.accentGreen,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final items = _items;
    if (items == null || items.isEmpty) {
      return const Center(
        child: Text(
          'No posts found',
          style: TextStyle(color: KabukTheme.textSecondary),
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: KabukTheme.divider),
      itemBuilder: (context, index) => _SubredditPostTile(item: items[index]),
    );
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// =============================================================================
// Peek URL Input Dialog
// =============================================================================

/// Dialog that lets users type or paste a URL to quick-peek.
class PeekUrlDialog extends StatefulWidget {
  /// Creates a [PeekUrlDialog].
  const PeekUrlDialog({super.key});

  /// Shows the dialog and opens a peek sheet if the user enters a URL.
  static void show(BuildContext context) {
    showDialog<void>(context: context, builder: (_) => const PeekUrlDialog());
  }

  @override
  State<PeekUrlDialog> createState() => _PeekUrlDialogState();
}

class _PeekUrlDialogState extends State<PeekUrlDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    Navigator.of(context).pop();

    // Detect if it's a subreddit reference.
    final subredditMatch = RegExp(
      r'^(?:https?://(?:www\.)?reddit\.com/)?/?r/(\w+)',
    ).firstMatch(text);

    if (subredditMatch != null) {
      final sub = subredditMatch.group(1)!;
      SubredditPeekSheet.show(
        context,
        subredditName: 'r/$sub',
        feedUrl: 'r/$sub',
      );
      return;
    }

    // Ensure it has a scheme.
    var url = text;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    QuickPeekSheet.show(context, url: url);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: KabukTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 120),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header.
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: KabukTheme.accentGreen.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.travel_explore_rounded,
                    size: 20,
                    color: KabukTheme.accentGreen,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Quick Peek',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KabukTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Hint text.
            const Text(
              'Enter a URL or subreddit to preview:',
              style: TextStyle(fontSize: 13, color: KabukTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            // Input field.
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              onSubmitted: (_) => _submit(),
              textInputAction: TextInputAction.go,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'https://example.com or r/flutter',
                hintStyle: const TextStyle(
                  color: KabukTheme.textTertiary,
                  fontSize: 14,
                ),
                prefixIcon: const Icon(
                  Icons.link_rounded,
                  size: 20,
                  color: KabukTheme.textTertiary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: KabukTheme.surfaceVariant,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            // Buttons.
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: KabukTheme.textSecondary,
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('Peek'),
                  style: FilledButton.styleFrom(
                    backgroundColor: KabukTheme.accentGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Shared Peek Widgets
// =============================================================================

/// Drag handle for bottom sheets.
class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 4),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: KabukTheme.textTertiary.withAlpha(80),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Header bar for peek sheets with title, optional icon, and action buttons.
class _PeekHeader extends StatelessWidget {
  const _PeekHeader({
    required this.title,
    required this.onClose,
    this.icon,
    this.iconColor,
    this.onRefresh,
    this.onOpenExternal,
  });

  final String title;
  final VoidCallback onClose;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onRefresh;
  final VoidCallback? onOpenExternal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Row(
        children: [
          // Optional icon.
          if (icon != null) ...[
            Icon(icon, size: 20, color: iconColor ?? KabukTheme.accentGreen),
            const SizedBox(width: 8),
          ],
          // Title.
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: KabukTheme.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Refresh button.
          if (onRefresh != null)
            IconButton(
              icon: const Icon(
                Icons.refresh_rounded,
                size: 20,
                color: KabukTheme.textSecondary,
              ),
              onPressed: onRefresh,
              tooltip: 'Refresh',
              visualDensity: VisualDensity.compact,
            ),
          // Open in browser.
          if (onOpenExternal != null)
            IconButton(
              icon: const Icon(
                Icons.open_in_new_rounded,
                size: 20,
                color: KabukTheme.textSecondary,
              ),
              onPressed: onOpenExternal,
              tooltip: 'Open in browser',
              visualDensity: VisualDensity.compact,
            ),
          // Close.
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 20,
              color: KabukTheme.textSecondary,
            ),
            onPressed: onClose,
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// A compact tile for a single subreddit post inside [SubredditPeekSheet].
class _SubredditPostTile extends StatelessWidget {
  const _SubredditPostTile({required this.item});

  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;

    return InkWell(
      onTap: () {
        // Open the post URL in a nested quick peek.
        QuickPeekSheet.show(context, url: item.url, title: item.title);
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail.
            if (hasImage)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: FeedImage(
                      imageUrl: item.imageUrl!,
                      width: 72,
                      height: 72,
                    ),
                  ),
                ),
              ),
            // Text content.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title.
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: KabukTheme.textPrimary,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Meta row.
                  Row(
                    children: [
                      if (item.author != null) ...[
                        Text(
                          item.author!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: KabukTheme.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (item.datePublished != null)
                        Text(
                          _formatTimeAgo(item.datePublished!),
                          style: const TextStyle(
                            fontSize: 12,
                            color: KabukTheme.textTertiary,
                          ),
                        ),
                    ],
                  ),
                  // Description preview.
                  if (item.description != null &&
                      item.description!.isNotEmpty &&
                      !_isStatsOnly(item.description!))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _cleanDescription(item.description!),
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: KabukTheme.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            // Peek indicator.
            const Padding(
              padding: EdgeInsets.only(top: 2, left: 4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: KabukTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isStatsOnly(String desc) {
    final trimmed = desc.trim();
    return RegExp(r'^[⬆💬·\s\d,.|]+$').hasMatch(trimmed) ||
        RegExp(r'^[\d,]+\s+(upvotes?|points?)\s*[|·]').hasMatch(trimmed);
  }

  String _cleanDescription(String desc) {
    return desc
        .replaceAll(
          RegExp(r'\s*[·|]?\s*⬆\s*[\d,]+\s*([·|]\s*💬\s*[\d,]+)?\s*$'),
          '',
        )
        .replaceAll(RegExp(r'\s*[·|]?\s*💬\s*[\d,]+\s*$'), '')
        .trim();
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}w';
    return '${diff.inDays ~/ 30}mo';
  }
}
