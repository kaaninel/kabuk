/// Native channel view for browsed web content.
///
/// Displays web content that has been parsed into semantic objects in the
/// knowledge base. Works like a channel/subreddit view but for any URL.
/// The user can optionally subscribe to the page via the follow button.
///
/// This is how Kabuk browses the web — URLs are parsed into native
/// articles and displayed in a channel format, not in a WebView.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/services/reader_mode.dart';
import 'package:kabuk/services/web_extractor.dart';
import 'package:kabuk/ui/explore/article_card.dart';
import 'package:kabuk/ui/explore/explore_view.dart';
import 'package:kabuk/ui/explore/reader_view.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// WebChannelView
// =============================================================================

/// Displays parsed web content as a native channel.
///
/// Shows articles extracted from a URL in the same format as Reddit/RSS
/// channels. Single-article pages show the full reader view inline.
/// Multi-article pages (index/listing) show article cards.
///
/// The follow button lets users subscribe to the page for future updates.
/// Supports pagination (load more) and navigation links.
class WebChannelView extends ConsumerStatefulWidget {
  /// Creates a [WebChannelView].
  const WebChannelView({
    required this.url,
    required this.articleUris,
    required this.isMultiArticle,
    this.nextPageUrl,
    this.navigationLinks = const [],
    super.key,
  });

  /// The original URL that was browsed.
  final String url;

  /// URIs of articles created in the knowledge store.
  final List<String> articleUris;

  /// Whether the page contained multiple articles (index/listing page).
  final bool isMultiArticle;

  /// URL of the next page, if pagination was detected.
  final String? nextPageUrl;

  /// Navigation links for browsing other sections of the site.
  final List<ExtractedLink> navigationLinks;

  @override
  ConsumerState<WebChannelView> createState() => _WebChannelViewState();
}

class _WebChannelViewState extends ConsumerState<WebChannelView> {
  List<ArticleData> _articles = [];
  bool _isLoading = true;
  bool _isSubscribed = false;
  String? _subscriptionUri;
  bool _isLoadingMore = false;
  String? _nextPageUrl;
  final _scrollController = ScrollController();

  String get _domain =>
      Uri.tryParse(widget.url)?.host.replaceFirst('www.', '') ?? widget.url;

  @override
  void initState() {
    super.initState();
    _nextPageUrl = widget.nextPageUrl;
    _loadArticles();
    _checkSubscriptionState();
    _scrollController.addListener(_onScroll);
    // Schedule periodic refreshes to pick up background image updates.
    // Background enrichment processes 5 articles per batch with 5s timeout,
    // so larger channels need multiple refresh cycles.
    for (final delay in [5, 12, 25, 45]) {
      Future.delayed(Duration(seconds: delay), _refreshArticleImages);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isLoadingMore || _nextPageUrl == null) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 400) {
      _loadMoreArticles();
    }
  }

  Future<void> _loadArticles() async {
    final store = ref.read(knowledgeStoreProvider);
    final loaded = <ArticleData>[];

    for (final uri in widget.articleUris) {
      final article = await store.getArticleData(uri);
      if (article != null) loaded.add(article);
    }

    if (mounted) {
      setState(() {
        _articles = loaded;
        _isLoading = false;
      });
    }
  }

  /// Re-reads articles from the store to pick up background image updates.
  Future<void> _refreshArticleImages() async {
    if (!mounted || _articles.isEmpty) return;
    final store = ref.read(knowledgeStoreProvider);
    final refreshed = <ArticleData>[];
    var hasChanges = false;

    for (final article in _articles) {
      final fresh = await store.getArticleData(article.uri);
      if (fresh != null) {
        refreshed.add(fresh);
        if (fresh.image != article.image) hasChanges = true;
      } else {
        refreshed.add(article);
      }
    }

    if (mounted && hasChanges) {
      setState(() => _articles = refreshed);
    }
  }

  Future<void> _checkSubscriptionState() async {
    final store = ref.read(knowledgeStoreProvider);
    final subs = await store.listFeedSubscriptions();
    final match = subs
        .where((s) => s.feedUrl == widget.url)
        .firstOrNull;
    if (mounted) {
      setState(() {
        _isSubscribed = match != null;
        _subscriptionUri = match?.uri;
      });
    }
  }

  /// Fetches the next page of articles when pagination is available.
  Future<void> _loadMoreArticles() async {
    final nextUrl = _nextPageUrl;
    if (nextUrl == null || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final service = ref.read(readerModeServiceProvider);
      final result = await service.processUrl(nextUrl);

      if (!mounted) return;

      // Load the new article data.
      final store = ref.read(knowledgeStoreProvider);
      final newArticles = <ArticleData>[];
      for (final uri in result.articleUris) {
        final article = await store.getArticleData(uri);
        if (article != null) newArticles.add(article);
      }

      if (!mounted) return;
      setState(() {
        _articles = [..._articles, ...newArticles];
        _nextPageUrl = result.nextPageUrl;
        _isLoadingMore = false;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _nextPageUrl = null; // Don't retry on failure.
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load more: $e')),
        );
      }
    }
  }

  /// Navigates to a URL within the current channel context.
  void _browseLink(String url) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _LinkLoader(url: url),
      ),
    );
  }

  Future<void> _toggleSubscription() async {
    final store = ref.read(knowledgeStoreProvider);

    if (_isSubscribed && _subscriptionUri != null) {
      // Unsubscribe.
      await store.deleteFeedSubscription(_subscriptionUri!);
      ref.invalidate(subscriptionsProvider);
      if (mounted) {
        setState(() {
          _isSubscribed = false;
          _subscriptionUri = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unfollowed $_domain')),
        );
      }
    } else {
      // Subscribe — also tag existing articles with feedSource.
      final subUri = await store.createFeedSubscription(
        name: _domain,
        feedUrl: widget.url,
        feedType: 'web',
      );

      // Tag existing articles so they show under this subscription.
      for (final uri in widget.articleUris) {
        await store.updateArticleFeedSource(uri, subUri);
      }

      ref.invalidate(subscriptionsProvider);
      ref.invalidate(articlesProvider);

      if (mounted) {
        setState(() {
          _isSubscribed = true;
          _subscriptionUri = subUri;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Following $_domain')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Single-article page → show full reader view with subscribe button.
    if (!widget.isMultiArticle && widget.articleUris.isNotEmpty) {
      return _SingleArticleView(
        articleUri: widget.articleUris.first,
        url: widget.url,
        domain: _domain,
        isSubscribed: _isSubscribed,
        onToggleSubscription: _toggleSubscription,
      );
    }

    // Multi-article page → channel-style card list.
    return Scaffold(
      backgroundColor: KabukTheme.background,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // ── App bar ──
          SliverAppBar(
            expandedHeight: 100,
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
                      KabukTheme.blueAccent.withAlpha(140),
                      KabukTheme.blueAccent.withAlpha(40),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 20),
                tooltip: 'Copy URL',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('URL copied')),
                  );
                },
              ),
            ],
          ),

          // ── Channel header ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(KabukTheme.spacingMd),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: KabukTheme.blueAccent.withAlpha(38),
                    child: const Icon(
                      Icons.language_rounded,
                      size: 24,
                      color: KabukTheme.blueAccent,
                    ),
                  ),
                  const SizedBox(width: KabukTheme.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _domain,
                          style: const TextStyle(
                            color: KabukTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_articles.length} articles',
                          style: const TextStyle(
                            color: KabukTheme.textTertiary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _SubscribeButton(
                    isSubscribed: _isSubscribed,
                    onToggle: _toggleSubscription,
                  ),
                ],
              ),
            ),
          ),

          // ── Navigation links (categories/sections) ──
          if (widget.navigationLinks.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: KabukTheme.spacingMd,
                  ),
                  itemCount: widget.navigationLinks.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final link = widget.navigationLinks[index];
                    return ActionChip(
                      avatar: const Icon(Icons.link_rounded, size: 14),
                      label: Text(
                        link.title,
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: KabukTheme.surface,
                      side: const BorderSide(color: KabukTheme.divider),
                      onPressed: () => _browseLink(link.url),
                    );
                  },
                ),
              ),
            ),

          const SliverToBoxAdapter(
            child: Divider(color: KabukTheme.divider, height: 1),
          ),

          // ── Content ──
          if (_isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(
                  color: KabukTheme.blueAccent,
                ),
              ),
            )
          else if (_articles.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'No articles found on this page',
                  style: TextStyle(color: KabukTheme.textSecondary),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return ArticleCard(
                    article: _articles[index],
                    articles: _articles,
                    index: index,
                  );
                },
                childCount: _articles.length,
              ),
            ),

          // ── Load more indicator ──
          if (_isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: CircularProgressIndicator(
                    color: KabukTheme.blueAccent,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else if (_nextPageUrl != null && _articles.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: TextButton.icon(
                    onPressed: _loadMoreArticles,
                    icon: const Icon(Icons.expand_more_rounded),
                    label: const Text('Load more'),
                    style: TextButton.styleFrom(
                      foregroundColor: KabukTheme.blueAccent,
                    ),
                  ),
                ),
              ),
            ),

          // Bottom padding.
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }
}

// =============================================================================
// Single article view wrapper
// =============================================================================

/// Wraps [ReaderView] with a subscribe button in the app bar for
/// single-article pages.
class _SingleArticleView extends StatelessWidget {
  const _SingleArticleView({
    required this.articleUri,
    required this.url,
    required this.domain,
    required this.isSubscribed,
    required this.onToggleSubscription,
  });

  final String articleUri;
  final String url;
  final String domain;
  final bool isSubscribed;
  final VoidCallback onToggleSubscription;

  @override
  Widget build(BuildContext context) {
    return ReaderView(
      articleUri: articleUri,
      url: url,
    );
  }
}

// =============================================================================
// Subscribe button
// =============================================================================

/// Follow/unfollow button for web channels.
class _SubscribeButton extends StatelessWidget {
  const _SubscribeButton({
    required this.isSubscribed,
    required this.onToggle,
  });

  final bool isSubscribed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: isSubscribed
          ? OutlinedButton.icon(
              onPressed: onToggle,
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Following'),
              style: OutlinedButton.styleFrom(
                foregroundColor: KabukTheme.blueAccent,
                side: const BorderSide(color: KabukTheme.blueAccent),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
            )
          : FilledButton.icon(
              onPressed: onToggle,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Follow'),
              style: FilledButton.styleFrom(
                backgroundColor: KabukTheme.blueAccent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
            ),
    );
  }
}

// =============================================================================
// Link loader — navigates to a URL and shows it as a WebChannelView
// =============================================================================

/// Loads a URL through the reader mode pipeline and displays it.
class _LinkLoader extends ConsumerStatefulWidget {
  const _LinkLoader({required this.url});

  final String url;

  @override
  ConsumerState<_LinkLoader> createState() => _LinkLoaderState();
}

class _LinkLoaderState extends ConsumerState<_LinkLoader> {
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final service = ref.read(readerModeServiceProvider);
      final result = await service.processUrl(widget.url);

      if (!mounted) return;

      // Replace this page with the channel view.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => WebChannelView(
            url: widget.url,
            articleUris: result.articleUris,
            isMultiArticle: result.isMultiArticle,
            nextPageUrl: result.nextPageUrl,
            navigationLinks: result.navigationLinks,
          ),
        ),
      );
    } on Object catch (e) {
      if (mounted) setState(() { _error = '$e'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KabukTheme.background,
      appBar: AppBar(
        backgroundColor: KabukTheme.surface,
        foregroundColor: KabukTheme.textPrimary,
        title: Text(
          Uri.tryParse(widget.url)?.host ?? widget.url,
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: KabukTheme.blueAccent)
            : Text(
                _error ?? 'Failed to load',
                style: const TextStyle(color: KabukTheme.textSecondary),
              ),
      ),
    );
  }
}
