/// Explore view — a rich, engaging content feed with Nostr social layer.
///
/// Shows articles from subscribed feeds (Reddit, RSS, Nostr) in a beautiful
/// scrollable feed with large images, video thumbnails, pull-to-refresh,
/// and category filtering. All content can be shared to Nostr for reactions,
/// comments, and reposts. Falls back to onboarding when no subscriptions exist.
library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/media_cache.dart';
import 'package:kabuk/ui/explore/browse_session.dart';
import 'package:kabuk/ui/explore/explore_widgets.dart';
import 'package:kabuk/ui/explore/nostr_providers.dart';
import 'package:kabuk/ui/shared/identity_quick_switcher.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// Helpers
// =============================================================================

/// Maps a raw exception to a short, user-friendly message.
String friendlyError(Object e) {
  final msg = e.toString().toLowerCase();
  if (msg.contains('socketexception') || msg.contains('failed host lookup')) {
    return 'No internet connection — check your network';
  }
  if (msg.contains('timeout') || msg.contains('timed out')) {
    return 'Request timed out — please try again';
  }
  if (msg.contains('403') || msg.contains('forbidden')) {
    return 'Access denied — this content may be restricted';
  }
  if (msg.contains('404') || msg.contains('not found')) {
    return 'Content not found';
  }
  if (msg.contains('429') || msg.contains('rate limit')) {
    return 'Too many requests — please wait a moment';
  }
  return 'Something went wrong — please try again';
}

// =============================================================================
// Providers
// =============================================================================

/// Watches all Article entities reactively via the `rdf:type` predicate.
final articleTypeTriplesProvider = StreamProvider<List<Triple>>((ref) {
  final store = ref.watch(knowledgeStoreProvider);
  return store.watch(predicate: NS.rdfType, object: NS.schemaArticle);
});

/// Loads the full list of articles with all their data.
final articlesProvider = FutureProvider<List<ArticleData>>((ref) async {
  ref.watch(articleTypeTriplesProvider);
  final store = ref.watch(knowledgeStoreProvider);
  final all = await store.listArticles(limit: 200);
  // Deduplicate by URL — the same content can be stored under different
  // feedSource URIs if subscriptions were recreated between sessions.
  final seenUrls = <String>{};
  return all.where((a) {
    final key = a.url ?? a.uri;
    return seenUrls.add(key);
  }).toList();
});

/// Loads feed subscriptions for filter chips.
final subscriptionsProvider = FutureProvider<List<FeedSubscriptionData>>((
  ref,
) async {
  ref.watch(articleTypeTriplesProvider);
  final store = ref.watch(knowledgeStoreProvider);
  return store.listFeedSubscriptions();
});

/// Currently selected feed filter (null = all feeds).
final selectedFeedProvider = StateProvider<String?>((ref) => null);

/// Sort mode for the feed display.
///
/// - `'new'`: newest first (chronological, the default)
/// - `'hot'`: highest engagement first (score derived from fetched data)
/// - `'top'`: highest upvote count first
enum FeedSort { newest, hot, top }

/// Currently selected sort mode.
final feedSortProvider = StateProvider<FeedSort>((ref) => FeedSort.newest);

/// Whether a network refresh is currently in progress.
final _feedRefreshingProvider = StateProvider<bool>((ref) => false);

/// Fetches new articles from all subscribed feeds concurrently.
///
/// Each feed is fetched in parallel. New articles are persisted to
/// Fetches new articles from all subscribed feeds concurrently.
///
/// Each feed is fetched in parallel. New articles are persisted to
/// the knowledge store. The caller should invalidate [articlesProvider]
/// after this returns to reflect new content in the UI.
///
/// Per-subscription [FeedSubscriptionData.refreshInterval] is respected:
/// feeds that were fetched within their interval are skipped.
///
/// Reddit feeds use the current [feedSortProvider] value to choose the
/// appropriate server-side sort endpoint (`/new.json`, `/hot.json`, etc.).
Future<int> refreshAllFeeds(WidgetRef ref) async {
  final store = ref.read(knowledgeStoreProvider);
  final feedService = ref.read(feedServiceProvider);
  final subs = await store.listFeedSubscriptions();
  if (subs.isEmpty) return 0;

  // Map current sort mode to a Reddit-compatible sort endpoint name.
  final sort = ref.read(feedSortProvider);
  final redditSort = switch (sort) {
    FeedSort.newest => 'new',
    FeedSort.hot => 'hot',
    FeedSort.top => 'top',
  };

  // Fetch all feeds concurrently.
  final futures = <Future<List<ArticleData>>>[];
  for (final sub in subs) {
    if (sub.feedUrl == null) continue;
    futures.add(_fetchFeed(store, feedService, sub, redditSort: redditSort));
  }

  final results = await Future.wait(futures);
  return results.expand((list) => list).length;
}

/// Fetches a single feed subscription and returns new (deduplicated) articles.
///
/// Respects [FeedSubscriptionData.refreshInterval]: if the feed was fetched
/// more recently than its interval, the fetch is skipped and an empty list
/// is returned to avoid redundant network requests.
Future<List<ArticleData>> _fetchFeed(
  KnowledgeStore store,
  FeedService feedService,
  FeedSubscriptionData sub, {
  String redditSort = 'hot',
}) async {
  // Skip if the feed was fetched more recently than its configured interval.
  final last = sub.lastFetched;
  if (last != null) {
    final age = DateTime.now().difference(last);
    if (age < Duration(minutes: sub.refreshInterval)) return [];
  }

  try {
    final sourceType = FeedSourceType.values.firstWhere(
      (t) => t.name == sub.feedType,
      orElse: () => FeedSourceType.rss,
    );

    // For Reddit sources, inject the server-side sort into the URL.
    final fetchUrl = sourceType == FeedSourceType.reddit && sub.feedUrl != null
        ? _buildRedditSortUrl(sub.feedUrl!, redditSort)
        : sub.feedUrl!;

    final items = await feedService.fetchItems(fetchUrl, type: sourceType);
    // Deduplicate globally by URL — prevents duplicates when a subscription
    // is recreated with a new feedSource URI between sessions.
    final allExisting = await store.listArticles(limit: 2000);
    final existingByUrl = {
      for (final a in allExisting)
        if (a.url != null) a.url!: a,
    };

    final newArticles = <ArticleData>[];
    for (final item in items) {
      final cached = existingByUrl[item.url];
      if (cached != null) {
        // For Nostr items, patch stale titles (e.g. bare hashtag from mirror bots).
        final isNostr = item.url.startsWith('nostr:');
        if (isNostr && cached.name != item.title && item.title.isNotEmpty) {
          await store.updateArticleTitleAndDescription(
            cached.uri,
            title: item.title,
            description: item.description,
          );
        }
        continue;
      }
      final uri = await store.createArticle(
        title: item.title,
        description: item.description,
        url: item.url,
        author: item.author,
        image: item.imageUrl,
        feedSource: sub.uri,
        datePublished: item.datePublished,
        tags: item.categories,
        galleryImages: item.galleryImages,
      );
      newArticles.add(
        ArticleData(
          uri: uri,
          name: item.title,
          description: item.description,
          url: item.url,
          author: item.author,
          image: item.imageUrl,
          feedSource: sub.uri,
          datePublished: item.datePublished,
          tags: item.categories,
          galleryImages: item.galleryImages,
        ),
      );
    }
    await store.updateFeedLastFetched(sub.uri);
    return newArticles;
  } on Object catch (e) {
    dev.log(
      'Feed refresh failed for ${sub.uri}: $e',
      name: 'Explore',
      error: e,
    );
    return [];
  }
}

/// Builds a Reddit JSON URL with the specified sort endpoint.
///
/// Replaces any existing sort path (e.g. `/hot.json`) with [sort],
/// so `r/flutter` with sort `'new'` becomes
/// `https://www.reddit.com/r/flutter/new.json?limit=50&raw_json=1`.
String _buildRedditSortUrl(String baseUrl, String sort) {
  // Strip .json suffix and any previous sort path component.
  var url = baseUrl
      .replaceAll(RegExp(r'/\w+\.json(\?.*)?$'), '') // remove /XXX.json[?...]
      .replaceAll(RegExp(r'\?.*$'), '') // remove stray query strings
      .trimRight();
  if (url.endsWith('/')) url = url.substring(0, url.length - 1);
  return '$url/$sort.json?limit=50&raw_json=1';
}

// =============================================================================
// Explore View
// =============================================================================

/// The main Explore tab — a social-media-style content feed.
class ExploreView extends ConsumerStatefulWidget {
  /// Creates an [ExploreView].
  const ExploreView({super.key});

  @override
  ConsumerState<ExploreView> createState() => _ExploreViewState();
}

class _ExploreViewState extends ConsumerState<ExploreView>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  bool _didAutoRefresh = false;

  /// Tracks an in-progress refresh so concurrent callers can await it.
  Future<void>? _refreshFuture;

  /// The currently displayed list of articles.
  List<ArticleData> _displayedArticles = [];

  /// URIs of articles already in the displayed list (for dedup).
  final Set<String> _displayedUris = {};

  /// Per-article GlobalKeys for scroll restoration after navigation.
  final Map<String, GlobalKey> _itemKeys = {};

  /// URI of the article the user last opened; used to scroll back on return.
  String? _lastOpenedUri;

  /// When the last successful refresh completed.
  DateTime? _lastRefreshedAt;

  /// Periodic timer that keeps content fresh while the app is open.
  Timer? _refreshTimer;

  // ── Incremental pagination ────────────────────────────────────────────────

  /// Per-subscription `after` cursor for Reddit pagination.
  final Map<String, String?> _afterTokens = {};

  /// Whether a "load more" fetch is in progress.
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Auto-refresh feeds on first mount (after frame so providers are ready).
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoRefresh());
    // Background refresh every 30 minutes while the view is alive.
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _silentRefresh(),
    );
    // Detect when the user scrolls to the bottom → load more.
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Re-check freshness when the app returns to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final last = _lastRefreshedAt;
      final stale =
          last == null ||
          DateTime.now().difference(last) > const Duration(minutes: 30);
      if (stale) _silentRefresh();
    }
  }

  /// Auto-refresh once per session when the Explore view first appears.
  Future<void> _autoRefresh() async {
    if (_didAutoRefresh) return;
    _didAutoRefresh = true;
    await _refreshFeed();
  }

  /// Triggered by the scroll controller — fires "load more" near the bottom.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final nearBottom = pos.pixels >= pos.maxScrollExtent - 400;
    if (nearBottom && !_isLoadingMore && _refreshFuture == null) {
      _loadMore();
    }
  }

  /// Fetches the next page of results for the currently visible feed.
  ///
  /// For Reddit sources, uses the `after` cursor from the last fetch.
  /// For non-Reddit sources (RSS / Nostr) there is nothing to page through.
  Future<void> _loadMore() async {
    if (_isLoadingMore || !mounted) return;
    final selectedFeed = ref.read(selectedFeedProvider);
    // Determine which subscriptions are currently visible.
    final subs = ref.read(subscriptionsProvider).valueOrNull ?? [];
    final FeedSubscriptionData? sub;
    if (selectedFeed == null || selectedFeed == 'nostr:global') {
      sub = null; // whole-feed view — pick first Reddit sub if any
    } else {
      sub = subs.where((s) => s.uri == selectedFeed).firstOrNull;
    }

    final redditSubs = selectedFeed == null
        ? subs
              .where((s) => s.feedType == 'reddit' && s.feedUrl != null)
              .toList()
        : (sub?.feedType == 'reddit' ? [sub!] : <FeedSubscriptionData>[]);

    if (redditSubs.isEmpty) return; // no paginatable source

    setState(() => _isLoadingMore = true);
    try {
      final store = ref.read(knowledgeStoreProvider);
      final feedService = ref.read(feedServiceProvider);
      final sort = ref.read(feedSortProvider);
      final redditSort = switch (sort) {
        FeedSort.newest => 'new',
        FeedSort.hot => 'hot',
        FeedSort.top => 'top',
      };

      for (final sub in redditSubs) {
        final baseUrl = _buildRedditSortUrl(sub.feedUrl!, redditSort);
        final cursor = _afterTokens[sub.uri];
        final result = await feedService.fetchItemsPage(
          baseUrl,
          type: FeedSourceType.reddit,
          cursor: cursor,
        );
        // Persist new articles and update the displayed list.
        for (final item in result.items) {
          if (_displayedUris.contains(item.url)) continue;
          final uri = await store.createArticle(
            title: item.title,
            description: item.description,
            url: item.url,
            author: item.author,
            image: item.imageUrl,
            feedSource: sub.uri,
            datePublished: item.datePublished,
            tags: item.categories,
            galleryImages: item.galleryImages,
          );
          final article = ArticleData(
            uri: uri,
            name: item.title,
            description: item.description,
            url: item.url,
            author: item.author,
            image: item.imageUrl,
            feedSource: sub.uri,
            datePublished: item.datePublished,
            tags: item.categories,
            galleryImages: item.galleryImages,
          );
          _displayedArticles.add(article);
          _displayedUris.add(uri);
        }
        _afterTokens[sub.uri] = result.nextCursor;
      }
    } on Object catch (e) {
      dev.log('Load more failed: $e', name: 'Explore', error: e);
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  /// Background refresh — does not block the UI or show indicators.
  Future<void> _silentRefresh() async {
    if (!mounted) return;
    dev.log('Silent background refresh triggered', name: 'Explore');
    try {
      if (_refreshFuture != null) return;
      _refreshFuture = _doRefresh();
      await _refreshFuture!;
    } finally {
      _refreshFuture = null;
    }
  }

  /// Scrolls to the article that was last opened, if it is still in the list.
  void _scrollToLastOpened() {
    final uri = _lastOpenedUri;
    if (uri == null) return;

    // Give the list a frame to settle before measuring.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[uri];
      final ctx = key?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.3, // position the item ~30% from the top for context
      );
    });
  }

  /// Pull-to-refresh: fetches new content from all subscribed feeds
  /// and the Nostr network in the background.
  ///
  /// New articles appear via the animated list without rebuilding
  /// the entire feed. The provider invalidation is minimal — only
  /// the articles list re-reads from the store to incorporate
  /// anything that was stored during the background fetch.
  Future<void> _refreshFeed() async {
    unawaited(HapticFeedback.mediumImpact());
    // If a refresh is already in progress, await it instead of returning
    // immediately — this ensures RefreshIndicator waits for real completion.
    if (_refreshFuture != null) return _refreshFuture!;
    _refreshFuture = _doRefresh();
    try {
      await _refreshFuture!;
    } finally {
      _refreshFuture = null;
    }
  }

  Future<void> _doRefresh() async {
    // Skip network fetch if there is no connectivity.
    final connResult = await Connectivity().checkConnectivity();
    final online = hasNetwork(connResult);

    ref.read(_feedRefreshingProvider.notifier).state = true;
    try {
      if (online) {
        // Refresh traditional feeds and Nostr in parallel.
        await Future.wait([
          refreshAllFeeds(ref),
          refreshNostrFeed(ref, limit: 30),
        ]);
        _lastRefreshedAt = DateTime.now();
      }
      // Prune stale articles regardless of connectivity — keeps the store lean.
      final store = ref.read(knowledgeStoreProvider);
      await store.pruneStaleArticles();
    } on Object catch (_) {
      // Swallow — individual feed errors handled inside each function.
    }
    if (!mounted) {
      ref.read(_feedRefreshingProvider.notifier).state = false;
      return;
    }
    ref.read(_feedRefreshingProvider.notifier).state = false;
    // Absorb the new articles into the main list.
    // The articlesProvider re-reads from the knowledge store where
    // the new articles have already been persisted.
    ref.invalidate(articlesProvider);
    ref.invalidate(subscriptionsProvider);
    ref.invalidate(nostrNotesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final articlesAsync = ref.watch(articlesProvider);
    final subsAsync = ref.watch(subscriptionsProvider);
    final selectedFeed = ref.watch(selectedFeedProvider);
    final browseSession = ref.watch(browseSessionProvider);
    final connectivity =
        ref.watch(connectivityProvider).valueOrNull ?? const [];
    final isOffline = !hasNetwork(connectivity);
    final isWifiConn = onWifi(connectivity);

    // Resolve selected feed name/type for the OmniBar.
    // When a browse session is active it takes precedence in the bar.
    final selectedFeedName = browseSession != null
        ? browseSession.displayName
        : _resolveSelectedFeedName(subsAsync, selectedFeed);
    final selectedFeedType = browseSession != null
        ? browseSession.sourceType
        : _resolveSelectedFeedType(subsAsync, selectedFeed);

    return Scaffold(
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxScrolled) => [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: KabukTheme.background,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 12,
            title: OmniBar(
              selectedFeed: browseSession != null
                  ? 'browse:${browseSession.url}'
                  : selectedFeed,
              selectedFeedName: selectedFeedName,
              selectedFeedType: selectedFeedType,
              onTap: () => _openOmnibarSearch(context),
              onScopeClear: browseSession != null
                  ? () => ref.read(browseSessionProvider.notifier).clear()
                  : () => ref.read(selectedFeedProvider.notifier).state = null,
            ),
            actions: [const IdentityQuickSwitcher(radius: 15)],
          ),
          // Feed filter chips — hidden during browse mode.
          if (browseSession == null)
            SliverToBoxAdapter(
              child: FilterBar(
                subscriptions: subsAsync.valueOrNull ?? const [],
                selected: selectedFeed,
                onSelected: (uri) =>
                    ref.read(selectedFeedProvider.notifier).state = uri,
                onUnsubscribed: () {
                  ref.invalidate(subscriptionsProvider);
                  ref.invalidate(articlesProvider);
                },
              ),
            ),
        ],
        body: browseSession != null
            ? _buildBrowseView(context, browseSession, isOffline: isOffline)
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: articlesAsync.when(
                  data: (articles) {
                    if (articles.isEmpty) {
                      return RefreshIndicator(
                        key: const ValueKey('empty'),
                        onRefresh: _refreshFeed,
                        color: KabukTheme.accentGreen,
                        child: CustomScrollView(
                          slivers: [
                            if (isOffline) _buildOfflineBanner(),
                            SliverFillRemaining(
                              child: EmptyFeedState(
                                onSearchTap: () => _openOmnibarSearch(context),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return KeyedSubtree(
                      key: const ValueKey('feed'),
                      child: _buildFeed(
                        context,
                        articles,
                        subsAsync,
                        selectedFeed,
                        isOffline: isOffline,
                        isWifi: isWifiConn,
                      ),
                    );
                  },
                  loading: () => const KeyedSubtree(
                      key: ValueKey('skeleton'),
                      child: _FeedSkeleton(),
                    ),
                  error: (e, _) => Center(
                    key: const ValueKey('error'),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            size: 48,
                            color: KabukTheme.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            friendlyError(e),
                            style: const TextStyle(
                              color: KabukTheme.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () {
                              ref.invalidate(articlesProvider);
                            },
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Browse view
  // ---------------------------------------------------------------------------

  Widget _buildBrowseView(
    BuildContext context,
    BrowseSession session, {
    bool isOffline = false,
  }) {
    // When browse session finishes loading, trigger pagination near end.
    if (!session.loadingMore) {
      _scrollController.removeListener(_onScroll);
      _scrollController.addListener(_onBrowseScroll);
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref
            .read(browseSessionProvider.notifier)
            .browse(session.url, session.displayName, session.sourceType);
      },
      color: KabukTheme.accentGreen,
      child: CustomScrollView(
        slivers: [
          if (isOffline) _buildOfflineBanner(),
          // Subscribe banner.
          SliverToBoxAdapter(child: _buildBrowseBanner(session)),
          // Loading skeleton.
          if (session.loading)
            const SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: KabukTheme.accentGreen),
                    SizedBox(height: 16),
                    Text(
                      'Loading content...',
                      style: TextStyle(
                        color: KabukTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (session.error.isNotEmpty && session.articles.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 48,
                        color: KabukTheme.textSecondary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to load ${session.displayName}',
                        style: const TextStyle(
                          color: KabukTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        friendlyError(session.error),
                        style: const TextStyle(
                          color: KabukTheme.textTertiary,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          ref
                              .read(browseSessionProvider.notifier)
                              .browse(
                                session.url,
                                session.displayName,
                                session.sourceType,
                              );
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (session.articles.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  'No content found.',
                  style: TextStyle(color: KabukTheme.textSecondary),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index == 0) return _buildSortBar(context);
                  final i = index - 1;
                  if (i >= session.articles.length) {
                    return const SizedBox.shrink();
                  }
                  final article = session.articles[i];
                  final itemKey = _itemKeys.putIfAbsent(
                    article.uri,
                    GlobalKey.new,
                  );
                  return Padding(
                    key: itemKey,
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ArticleCard(
                      article: article,
                      onBeforeOpen: () {
                        _lastOpenedUri = article.uri;
                      },
                      onReturnFromDetail: _scrollToLastOpened,
                    ),
                  );
                }, childCount: session.articles.length + 1),
              ),
            ),
          // Load-more indicator.
          SliverToBoxAdapter(
            child: session.loadingMore
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: KabukTheme.accentGreen,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }

  /// Subscribe banner shown at the top of the browse view.
  ///
  /// Returns [SizedBox.shrink] when the source is already subscribed.
  Widget _buildBrowseBanner(BrowseSession session) {
    final subs = ref.watch(subscriptionsProvider).valueOrNull ?? [];
    final isAlreadySubscribed = subs.any(
      (s) => s.feedUrl == session.url || s.name == session.displayName,
    );

    // No banner needed when the user is already subscribed.
    if (isAlreadySubscribed) return const SizedBox.shrink();

    final isNostrProfile = session.sourceType == 'nostr_profile';
    final isReddit = session.sourceType == 'reddit';
    final isFourchan = session.sourceType == 'fourchan';

    Color bannerColor;
    IconData bannerIcon;
    if (isReddit) {
      bannerColor = const Color(0xFFFF4500);
      bannerIcon = Icons.reddit;
    } else if (isNostrProfile) {
      bannerColor = KabukTheme.purpleAccent;
      bannerIcon = Icons.bolt_rounded;
    } else if (isFourchan) {
      bannerColor = KabukTheme.warmAccent;
      bannerIcon = Icons.forum_outlined;
    } else {
      bannerColor = KabukTheme.blueAccent;
      bannerIcon = Icons.rss_feed_rounded;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bannerColor.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bannerColor.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(bannerIcon, size: 18, color: bannerColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Browsing ${session.displayName}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: bannerColor,
                  ),
                ),
                Text(
                  isNostrProfile
                      ? 'Not subscribed — tap × in the bar to leave'
                      : 'Viewing without subscribing',
                  style: const TextStyle(
                    fontSize: 11,
                    color: KabukTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (!isNostrProfile)
            Semantics(
              label: 'Subscribe',
              button: true,
              excludeSemantics: true,
              child: GestureDetector(
              onTap: () => _subscribeToBrowseSession(session),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: bannerColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: bannerColor.withAlpha(60)),
                ),
                child: Text(
                  'Subscribe',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: bannerColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Subscribes to the currently browsed source and keeps the browse view open.
  Future<void> _subscribeToBrowseSession(BrowseSession session) async {
    final store = ref.read(knowledgeStoreProvider);
    final existing = await store.listFeedSubscriptions();

    if (existing.any(
      (s) => s.feedUrl == session.url || s.name == session.displayName,
    )) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Already subscribed to ${session.displayName}'),
          ),
        );
      }
      return;
    }

    final feedType = switch (session.sourceType) {
      'nostr_profile' => 'nostr',
      _ => session.sourceType,
    };

    await store.createFeedSubscription(
      name: session.displayName,
      feedUrl: session.url,
      feedType: feedType,
    );

    ref.invalidate(subscriptionsProvider);
    ref.invalidate(articlesProvider);
    unawaited(
      refreshAllFeeds(ref).then((_) {
        if (mounted) ref.invalidate(articlesProvider);
      }),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Subscribed to ${session.displayName}!')),
      );
    }
  }

  /// Scroll listener used during browse mode — triggers pagination.
  void _onBrowseScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final nearBottom = pos.pixels >= pos.maxScrollExtent - 400;
    if (nearBottom) {
      unawaited(ref.read(browseSessionProvider.notifier).loadMore());
    }
  }

  /// Opens the full-screen OmniBar search page.
  void _openOmnibarSearch(BuildContext context) {
    final selectedFeed = ref.read(selectedFeedProvider);
    final subsAsync = ref.read(subscriptionsProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OmniBarSearchPage(
          initialScope: selectedFeed,
          initialScopeName: _resolveSelectedFeedName(subsAsync, selectedFeed),
        ),
      ),
    );
  }

  /// Resolves the display name for the selected feed.
  String? _resolveSelectedFeedName(
    AsyncValue<List<FeedSubscriptionData>> subsAsync,
    String? selectedFeed,
  ) {
    if (selectedFeed == null) return null;
    if (selectedFeed == 'nostr:global') return 'Nostr';
    return subsAsync.whenOrNull(
      data: (subs) =>
          subs.where((s) => s.uri == selectedFeed).firstOrNull?.name,
    );
  }

  /// Resolves the feed type for the selected feed.
  String? _resolveSelectedFeedType(
    AsyncValue<List<FeedSubscriptionData>> subsAsync,
    String? selectedFeed,
  ) {
    if (selectedFeed == null) return null;
    if (selectedFeed == 'nostr:global') return 'nostr';
    return subsAsync.whenOrNull(
      data: (subs) =>
          subs.where((s) => s.uri == selectedFeed).firstOrNull?.feedType,
    );
  }

  Widget _buildFeed(
    BuildContext context,
    List<ArticleData> allArticles,
    AsyncValue<List<FeedSubscriptionData>> subsAsync,
    String? selectedFeed, {
    bool isOffline = false,
    bool isWifi = true,
  }) {
    final sort = ref.watch(feedSortProvider);

    // For the Nostr global feed, match any article with a 'nostr' feed source,
    // since individual Nostr notes are stored with 'nostr:...' source URIs.
    var articles = switch (selectedFeed) {
      null => allArticles,
      'nostr:global' =>
        allArticles
            .where((a) => a.feedSource?.startsWith('nostr') ?? false)
            .toList(),
      _ => allArticles.where((a) => a.feedSource == selectedFeed).toList(),
    };

    // Apply client-side sort based on the selected sort mode.
    articles = _sortArticles(List.of(articles), sort);

    // Sync the displayed list with the provider data.
    // Insert new articles at the top with animation.
    _syncDisplayedArticles(articles);

    return RefreshIndicator(
      onRefresh: _refreshFeed,
      color: KabukTheme.accentGreen,
      child: CustomScrollView(
        slivers: [
          // Offline notice — shown whenever there is no network connection.
          if (isOffline) _buildOfflineBanner(),
          // Empty filter state.
          if (articles.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.filter_alt_off_rounded,
                      size: 48,
                      color: KabukTheme.textTertiary.withAlpha(120),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No articles from this feed yet',
                      style: TextStyle(color: KabukTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  // index 0 = sort bar; subsequent = article cards.
                  if (index == 0) return _buildSortBar(context);
                  final i = index - 1;
                  if (i >= _displayedArticles.length) {
                    return const SizedBox.shrink();
                  }
                  return _buildItemCard(_displayedArticles[i], i);
                }, childCount: _displayedArticles.length + 1),
              ),
            ),
          // Load-more indicator shown at the very bottom.
          SliverToBoxAdapter(
            child: _isLoadingMore
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: KabukTheme.accentGreen,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }

  /// Syncs the displayed list with provider data.
  void _syncDisplayedArticles(List<ArticleData> articles) {
    final newUris = articles.map((a) => a.uri).toSet();

    // If the set of articles changed significantly (filter/sort change, etc.)
    // reset the list entirely.
    final currentUris = _displayedUris;
    final overlap = currentUris.intersection(newUris);
    final isFilterChange =
        _displayedArticles.isNotEmpty &&
        (overlap.length < _displayedArticles.length * 0.5 ||
            overlap.length < articles.length * 0.5);

    if (_displayedArticles.isEmpty || isFilterChange) {
      _displayedArticles = List.of(articles);
      _displayedUris
        ..clear()
        ..addAll(newUris);
      return;
    }

    // Merge new articles into the displayed list, and update changed fields
    // (e.g. Nostr titles repaired by re-fetch logic).
    for (final article in articles) {
      if (!_displayedUris.contains(article.uri)) {
        _displayedArticles.add(article);
        _displayedUris.add(article.uri);
      } else {
        // Update in-place if the title changed (e.g. after Nostr title patch).
        final idx = _displayedArticles.indexWhere((a) => a.uri == article.uri);
        if (idx >= 0 && _displayedArticles[idx].name != article.name) {
          _displayedArticles[idx] = article;
        }
      }
    }
  }

  /// Builds the sort toggle row (Newest / Hot / Top).
  Widget _buildSortBar(BuildContext context) {
    final currentSort = ref.watch(feedSortProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Row(
        children: [
          _sortChip(
            FeedSort.newest,
            'New',
            Icons.schedule_rounded,
            currentSort,
          ),
          const SizedBox(width: 6),
          _sortChip(
            FeedSort.hot,
            'Hot',
            Icons.local_fire_department_rounded,
            currentSort,
          ),
          const SizedBox(width: 6),
          _sortChip(
            FeedSort.top,
            'Top',
            Icons.trending_up_rounded,
            currentSort,
          ),
        ],
      ),
    );
  }

  Widget _sortChip(
    FeedSort sort,
    String label,
    IconData icon,
    FeedSort current,
  ) {
    final isSelected = sort == current;
    return Semantics(
      label: label,
      button: true,
      selected: isSelected,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          ref.read(feedSortProvider.notifier).state = sort;
        },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? KabukTheme.accentGreen.withAlpha(30)
              : KabukTheme.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? KabukTheme.accentGreen.withAlpha(120)
                : KabukTheme.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected
                  ? KabukTheme.accentGreen
                  : KabukTheme.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? KabukTheme.accentGreen
                    : KabukTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Sorts [articles] according to [sort].
  List<ArticleData> _sortArticles(List<ArticleData> articles, FeedSort sort) {
    return switch (sort) {
      FeedSort.newest =>
        articles..sort((a, b) {
          final aDate = a.datePublished ?? DateTime(2000);
          final bDate = b.datePublished ?? DateTime(2000);
          return bDate.compareTo(aDate);
        }),
      FeedSort.hot =>
        articles..sort((a, b) {
          final aScore = _engagementScore(a);
          final bScore = _engagementScore(b);
          return bScore.compareTo(aScore);
        }),
      FeedSort.top =>
        articles..sort((a, b) {
          final aUp = _parseUpvotes(a.description);
          final bUp = _parseUpvotes(b.description);
          return bUp.compareTo(aUp);
        }),
    };
  }

  /// Computes a simple engagement score from upvotes + comments in description.
  int _engagementScore(ArticleData a) {
    final upvotes = _parseUpvotes(a.description);
    final comments = _parseComments(a.description);
    return upvotes + (comments * 2);
  }

  int _parseUpvotes(String? desc) {
    if (desc == null) return 0;
    final m = RegExp(r'\u2b06\s*([\d,]+)').firstMatch(desc);
    return m != null ? int.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0 : 0;
  }

  int _parseComments(String? desc) {
    if (desc == null) return 0;
    final m = RegExp(r'\ud83d\udcac\s*([\d,]+)').firstMatch(desc);
    return m != null ? int.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0 : 0;
  }

  /// Slim banner shown at the top of the feed when the device is offline.
  SliverToBoxAdapter _buildOfflineBanner() {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: _OfflineBanner(),
      ),
    );
  }

  /// Builds a single article card row (no animation — list uses SliverList now).
  Widget _buildItemCard(ArticleData article, int index) {
    // Stable key per article — used for scroll restoration after navigation.
    final itemKey = _itemKeys.putIfAbsent(article.uri, GlobalKey.new);

    // Eagerly pre-fetch the next two articles' images only on WiFi to avoid
    // consuming mobile data unexpectedly.
    final connectivity = ref.read(connectivityProvider).valueOrNull ?? const [];
    if (onWifi(connectivity)) {
      for (
        var i = index + 1;
        i <= index + 2 && i < _displayedArticles.length;
        i++
      ) {
        final img = _displayedArticles[i].image;
        if (img != null && img.startsWith('http')) {
          KabukCacheManager.instance.downloadFile(img);
        }
      }
    }

    return Padding(
      key: itemKey,
      padding: const EdgeInsets.only(bottom: 12),
      child: ArticleCard(
        article: article,
        onBeforeOpen: () {
          _lastOpenedUri = article.uri;
        },
        onReturnFromDetail: _scrollToLastOpened,
      ),
    );
  }
}

// =============================================================================
// Offline banner
// =============================================================================

/// Compact banner shown at the top of the feed when the device has no network.
///
/// Informs the user that cached content is available offline while new content
/// cannot be fetched. Disappears automatically when connectivity is restored.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KabukTheme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KabukTheme.divider),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 15,
            color: KabukTheme.textTertiary,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline \u2014 showing cached content',
              style: TextStyle(fontSize: 12, color: KabukTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Skeleton loading screen
// =============================================================================

/// Shows pulsing skeleton cards while the feed is loading for the first time.
class _FeedSkeleton extends StatefulWidget {
  const _FeedSkeleton();

  @override
  State<_FeedSkeleton> createState() => _FeedSkeletonState();
}

class _FeedSkeletonState extends State<_FeedSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: 6,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, _) => _SkeletonCard(shimmerValue: _anim.value),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.shimmerValue});

  final double shimmerValue;

  @override
  Widget build(BuildContext context) {
    const base = KabukTheme.cardColor;
    final shimmer = Color.lerp(base, KabukTheme.divider, shimmerValue * 0.6)!;

    return Container(
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KabukTheme.divider),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Source header skeleton.
          Row(
            children: [
              _box(28, 28, shimmer, radius: 8),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _box(80, 10, shimmer, radius: 4),
                  const SizedBox(height: 4),
                  _box(50, 9, shimmer, radius: 4),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Title skeleton.
          _box(double.infinity, 14, shimmer, radius: 4),
          const SizedBox(height: 6),
          _box(220, 14, shimmer, radius: 4),
          const SizedBox(height: 12),
          // Image placeholder.
          _box(double.infinity, 160, shimmer, radius: 12),
          const SizedBox(height: 12),
          // Action bar skeleton.
          Row(
            children: [
              _box(48, 10, shimmer, radius: 4),
              const SizedBox(width: 12),
              _box(48, 10, shimmer, radius: 4),
              const Spacer(),
              _box(24, 20, shimmer, radius: 4),
            ],
          ),
        ],
      ),
    );
  }

  Widget _box(double w, double h, Color color, {double radius = 0}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
