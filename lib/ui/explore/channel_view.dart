/// Unified channel/profile view for any content author.
///
/// Displays an author's content as native article cards, regardless of
/// the underlying source (Reddit, 4chan, RSS, Nostr). Fetches the
/// author's content from the source, stores it in the knowledge base,
/// and renders using the same article cards as the main feed.
///
/// This is the universal "user profile" for Explore — every author
/// across every service gets the same native treatment.
library;

import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/ui/explore/article_card.dart';
import 'package:kabuk/ui/explore/explore_view.dart';
import 'package:kabuk/ui/explore/profile_view.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// Source-specific author URL builders
// =============================================================================

/// Builds the feed URL to fetch an author's content from a given source.
String? _authorFeedUrl(String author, FeedSourceType source) {
  return switch (source) {
    FeedSourceType.reddit =>
      'https://www.reddit.com/user/$author/submitted.json?limit=50&raw_json=1',
    _ => null, // Other sources don't have author feed URLs
  };
}

/// Builds the feed URL to fetch a channel's content from a given source.
String? _channelFeedUrl(String channel, FeedSourceType source) {
  return switch (source) {
    FeedSourceType.reddit =>
      'https://www.reddit.com/r/$channel/hot.json?limit=50&raw_json=1',
    _ => null,
  };
}

/// Returns the display prefix for an author from a given source.
String _authorDisplayName(String author, FeedSourceType source) {
  return switch (source) {
    FeedSourceType.reddit => 'u/$author',
    FeedSourceType.nostr => author.length > 16
        ? '${author.substring(0, 8)}…'
        : author,
    FeedSourceType.fourchan => 'Anonymous',
    _ => author,
  };
}

/// Accent color per source type.
Color _sourceColor(FeedSourceType source) {
  return switch (source) {
    FeedSourceType.reddit => KabukTheme.redditOrange,
    FeedSourceType.nostr => KabukTheme.nostrPurple,
    FeedSourceType.fourchan => const Color(0xFF789922),
    _ => KabukTheme.blueAccent,
  };
}

/// Icon per source type.
IconData _sourceIcon(FeedSourceType source) {
  return switch (source) {
    FeedSourceType.reddit => Icons.reddit_rounded,
    FeedSourceType.nostr => Icons.electric_bolt_rounded,
    FeedSourceType.fourchan => Icons.forum_rounded,
    FeedSourceType.rss => Icons.rss_feed_rounded,
    FeedSourceType.atom => Icons.rss_feed_rounded,
  };
}

// =============================================================================
// Channel View
// =============================================================================

/// Unified author/channel view for any content source.
///
/// Fetches the author's content from the source, stores it in the
/// knowledge store as articles, and renders native article cards.
///
/// For Nostr authors, delegates to [ProfileView] which has
/// protocol-specific features (follow/unfollow, NIP-05 verification).
///
/// Usage:
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => ChannelView(
///     author: 'spez',
///     sourceType: FeedSourceType.reddit,
///   ),
/// ));
/// ```
class ChannelView extends ConsumerStatefulWidget {
  /// Creates a [ChannelView] for the given [author] or [channel].
  ///
  /// Provide [author] for user profiles, or [channel] for
  /// subreddit / feed channels. At least one must be provided.
  const ChannelView({
    this.author,
    this.channel,
    required this.sourceType,
    super.key,
  }) : assert(author != null || channel != null);

  /// The author identifier (username, pubkey, etc.).
  final String? author;

  /// The channel identifier (subreddit name, etc.).
  final String? channel;

  /// Whether this view is showing a channel (not an author).
  bool get isChannel => channel != null;

  /// The content source type.
  final FeedSourceType sourceType;

  @override
  ConsumerState<ChannelView> createState() => _ChannelViewState();
}

class _ChannelViewState extends ConsumerState<ChannelView> {
  List<ArticleData> _articles = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _nextCursor;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadChannel();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isLoadingMore || !_hasMore) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // Trigger load when within 400px of the bottom.
    if (currentScroll >= maxScroll - 400) {
      _loadMore();
    }
  }

  Future<void> _loadChannel() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _nextCursor = null;
      _hasMore = true;
    });

    try {
      final store = ref.read(knowledgeStoreProvider);
      final feedService = ref.read(feedServiceProvider);

      if (widget.isChannel) {
        // Channel mode: load articles from the knowledge store by tag.
        final tag = 'r/${widget.channel}';
        final all = await store.listArticles(limit: 200);
        final existing = all
            .where((a) => a.tags.contains(tag))
            .toList();

        if (mounted) {
          setState(() {
            _articles = existing;
            if (existing.isNotEmpty) _isLoading = false;
          });
        }

        // Fetch fresh content from the subreddit.
        await _fetchChannelContent(store, feedService);
      } else {
        // Author mode: load articles from the knowledge store by author.
        final existing = await store.listArticles(
          author: widget.author,
          limit: 200,
        );

        if (mounted) {
          setState(() {
            _articles = existing;
            if (existing.isNotEmpty) _isLoading = false;
          });
        }

        // Then fetch fresh content from the source.
        await _fetchAuthorContent(store, feedService);
      }
    } on Object catch (e, st) {
      dev.log(
        'Channel load failed: $e',
        name: 'ChannelView',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() {
          _error = _articles.isEmpty ? e.toString() : null;
          _isLoading = false;
        });
      }
    }
  }

  /// Loads the next page of content using the cursor from the last fetch.
  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _nextCursor == null) return;

    setState(() => _isLoadingMore = true);

    try {
      final store = ref.read(knowledgeStoreProvider);
      final feedService = ref.read(feedServiceProvider);
      final feedUrl = widget.isChannel
          ? _channelFeedUrl(widget.channel!, widget.sourceType)
          : _authorFeedUrl(widget.author!, widget.sourceType);

      if (feedUrl == null) {
        setState(() {
          _isLoadingMore = false;
          _hasMore = false;
        });
        return;
      }

      final page = await feedService.fetchItemsPage(
        feedUrl,
        type: widget.sourceType,
        cursor: _nextCursor,
      );

      _nextCursor = page.nextCursor;
      if (page.nextCursor == null || page.items.isEmpty) {
        _hasMore = false;
      }

      final newArticles = await _storeAndDedup(store, page.items);

      if (mounted) {
        setState(() {
          _mergeArticles(newArticles);
          _isLoadingMore = false;
        });
      }
    } on Object catch (e) {
      dev.log('Load more failed: $e', name: 'ChannelView');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  /// Stores new items in the knowledge base and deduplicates against existing.
  Future<List<ArticleData>> _storeAndDedup(
    KnowledgeStore store,
    List<FeedItem> items,
  ) async {
    final existingUrls = {
      for (final a in _articles)
        if (a.url != null) a.url!,
    };

    final allExisting = await store.listArticles(limit: 2000);
    final globalUrls = {
      for (final a in allExisting)
        if (a.url != null) a.url!: a,
    };

    final newArticles = <ArticleData>[];
    for (final item in items) {
      if (existingUrls.contains(item.url)) continue;
      if (globalUrls.containsKey(item.url)) {
        newArticles.add(globalUrls[item.url]!);
        continue;
      }

      final uri = await store.createArticle(
        title: item.title,
        description: item.description,
        url: item.url,
        videoUrl: item.videoUrl,
        author: item.author ?? widget.author ?? '',
        feedSource: widget.isChannel ? widget.sourceType.name : null,
        image: item.imageUrl,
        datePublished: item.datePublished,
        tags: item.categories,
        galleryImages: item.galleryImages,
      );

      newArticles.add(ArticleData(
        uri: uri,
        name: item.title,
        description: item.description,
        url: item.url,
        videoUrl: item.videoUrl,
        author: item.author ?? widget.author ?? '',
        image: item.imageUrl,
        datePublished: item.datePublished,
        tags: item.categories,
        galleryImages: item.galleryImages,
      ));
    }
    return newArticles;
  }

  /// Merges new articles into [_articles], deduping by URL and sorting by date.
  void _mergeArticles(List<ArticleData> newArticles) {
    if (newArticles.isEmpty) return;
    final seen = <String>{};
    final merged = <ArticleData>[];
    for (final a in [..._articles, ...newArticles]) {
      final key = a.url ?? a.uri;
      if (seen.add(key)) merged.add(a);
    }
    merged.sort((a, b) {
      final da = a.datePublished ?? DateTime(2000);
      final db = b.datePublished ?? DateTime(2000);
      return db.compareTo(da);
    });
    _articles = merged;
  }

  Future<void> _fetchAuthorContent(
    KnowledgeStore store,
    FeedService feedService,
  ) async {
    final feedUrl = _authorFeedUrl(widget.author!, widget.sourceType);
    if (feedUrl == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final page = await feedService.fetchItemsPage(
        feedUrl,
        type: widget.sourceType,
      );

      _nextCursor = page.nextCursor;
      if (page.nextCursor == null || page.items.isEmpty) {
        _hasMore = false;
      }

      final newArticles = await _storeAndDedup(store, page.items);

      if (mounted && newArticles.isNotEmpty) {
        setState(() => _mergeArticles(newArticles));
      }
    } on Object catch (e) {
      dev.log(
        'Channel fetch failed for ${widget.author ?? widget.channel}: $e',
        name: 'ChannelView',
      );
      if (mounted && _articles.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not refresh — showing cached content'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  /// Fetches subreddit/channel content from the source.
  Future<void> _fetchChannelContent(
    KnowledgeStore store,
    FeedService feedService,
  ) async {
    final feedUrl = _channelFeedUrl(widget.channel!, widget.sourceType);
    if (feedUrl == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final page = await feedService.fetchItemsPage(
        feedUrl,
        type: widget.sourceType,
      );

      _nextCursor = page.nextCursor;
      if (page.nextCursor == null || page.items.isEmpty) {
        _hasMore = false;
      }

      final newArticles = await _storeAndDedup(store, page.items);

      if (mounted && newArticles.isNotEmpty) {
        setState(() => _mergeArticles(newArticles));
      }
    } on Object catch (e) {
      dev.log(
        'Channel fetch failed for r/${widget.channel}: $e',
        name: 'ChannelView',
      );
      if (mounted && _articles.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not refresh — showing cached content'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final color = _sourceColor(widget.sourceType);
    final displayName = widget.isChannel
        ? 'r/${widget.channel}'
        : _authorDisplayName(widget.author!, widget.sourceType);

    return Scaffold(
      backgroundColor: KabukTheme.background,
      body: RefreshIndicator(
        onRefresh: _loadChannel,
        color: color,
        child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // --- Header ---
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: KabukTheme.surface,
            foregroundColor: KabukTheme.textPrimary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withAlpha(180),
                      color.withAlpha(60),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // --- Author info ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(KabukTheme.spacingMd),
              child: Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: color.withAlpha(38),
                    child: Icon(
                      _sourceIcon(widget.sourceType),
                      size: 28,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: KabukTheme.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: KabukTheme.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_articles.length} posts · ${widget.sourceType.name}',
                          style: const TextStyle(
                            color: KabukTheme.textTertiary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _FollowButton(
                    author: widget.author,
                    channel: widget.channel,
                    sourceType: widget.sourceType,
                    color: color,
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(
            child: Divider(color: KabukTheme.divider, height: 1),
          ),

          // --- Content ---
          if (_isLoading && _articles.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(color: color),
              ),
            )
          else if (_error != null && _articles.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: KabukTheme.textTertiary,
                    ),
                    const SizedBox(height: KabukTheme.spacingMd),
                    const Text(
                      'Could not load content',
                      style: TextStyle(
                        color: KabukTheme.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: KabukTheme.spacingSm),
                    TextButton.icon(
                      onPressed: _loadChannel,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (_articles.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'No posts found',
                  style: TextStyle(color: KabukTheme.textSecondary),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final article = _articles[index];
                  return ArticleCard(
                    article: article,
                    articles: _articles,
                    index: index,
                  );
                },
                childCount: _articles.length,
              ),
            ),

          // Loading indicator at bottom while fetching more.
          if ((_isLoading || _isLoadingMore) && _articles.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(KabukTheme.spacingLg),
                child: Center(
                  child: CircularProgressIndicator(
                    color: color,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),

          // Bottom padding.
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
      ),
    );
  }
}

// =============================================================================
// Follow / Subscribe button
// =============================================================================

/// A button that toggles follow state for a channel author.
///
/// Checks existing feed subscriptions to determine initial state and
/// creates/deletes a subscription on tap.
class _FollowButton extends ConsumerStatefulWidget {
  const _FollowButton({
    this.author,
    this.channel,
    required this.sourceType,
    required this.color,
  });

  final String? author;
  final String? channel;
  final FeedSourceType sourceType;
  final Color color;

  /// The display name for this follow target.
  String get displayName {
    if (channel != null) return 'r/$channel';
    return author ?? '';
  }

  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  bool _isFollowing = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkFollowState();
  }

  Future<void> _checkFollowState() async {
    final store = ref.read(knowledgeStoreProvider);
    final subs = await store.listFeedSubscriptions();
    final feedUrl = widget.channel != null
        ? _channelFeedUrl(widget.channel!, widget.sourceType)
        : _authorFeedUrl(widget.author!, widget.sourceType);
    final isFollowing = subs.any(
      (s) => s.feedUrl == feedUrl,
    );
    if (mounted) {
      setState(() {
        _isFollowing = isFollowing;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    final store = ref.read(knowledgeStoreProvider);

    if (_isFollowing) {
      // Unfollow: find and delete the subscription.
      final subs = await store.listFeedSubscriptions();
      final feedUrl = widget.channel != null
          ? _channelFeedUrl(widget.channel!, widget.sourceType)
          : _authorFeedUrl(widget.author!, widget.sourceType);
      final match = subs.cast<FeedSubscriptionData?>().firstWhere(
            (s) => s!.feedUrl == feedUrl,
            orElse: () => null,
          );
      if (match != null) {
        await store.deleteFeedSubscription(match.uri);
      }
    } else {
      // Follow: create a new feed subscription.
      final feedUrl = widget.channel != null
          ? _channelFeedUrl(widget.channel!, widget.sourceType)
          : _authorFeedUrl(widget.author!, widget.sourceType);
      if (feedUrl == null) return;
      await store.createFeedSubscription(
        name: widget.displayName,
        feedUrl: feedUrl,
        feedType: widget.sourceType.name,
      );
    }

    ref.invalidate(subscriptionsProvider);
    if (mounted) {
      setState(() => _isFollowing = !_isFollowing);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: _isFollowing
          ? OutlinedButton.icon(
              onPressed: _toggleFollow,
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Following'),
              style: OutlinedButton.styleFrom(
                foregroundColor: widget.color,
                side: BorderSide(color: widget.color),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
            )
          : FilledButton.icon(
              onPressed: _toggleFollow,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Follow'),
              style: FilledButton.styleFrom(
                backgroundColor: widget.color,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
            ),
    );
  }
}
