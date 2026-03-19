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
import 'package:kabuk/ui/explore/article_card.dart';
import 'package:kabuk/ui/explore/explore_view.dart';
import 'package:kabuk/ui/explore/reader_view.dart';
import 'package:kabuk/ui/shared/feed_image.dart';
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
class WebChannelView extends ConsumerStatefulWidget {
  /// Creates a [WebChannelView].
  const WebChannelView({
    required this.url,
    required this.articleUris,
    required this.isMultiArticle,
    super.key,
  });

  /// The original URL that was browsed.
  final String url;

  /// URIs of articles created in the knowledge store.
  final List<String> articleUris;

  /// Whether the page contained multiple articles (index/listing page).
  final bool isMultiArticle;

  @override
  ConsumerState<WebChannelView> createState() => _WebChannelViewState();
}

class _WebChannelViewState extends ConsumerState<WebChannelView> {
  List<ArticleData> _articles = [];
  bool _isLoading = true;
  bool _isSubscribed = false;
  String? _subscriptionUri;

  String get _domain =>
      Uri.tryParse(widget.url)?.host.replaceFirst('www.', '') ?? widget.url;

  @override
  void initState() {
    super.initState();
    _loadArticles();
    _checkSubscriptionState();
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
