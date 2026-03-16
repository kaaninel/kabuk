/// OmniBar — Chrome-like unified search, navigation, and subscription bar.
///
/// A single bar that replaces the separate search dialog, filter bar,
/// and saved search row with one unified interface. Inspired by Chrome's
/// address bar and Reddit's scoped search.
///
/// Supports:
/// - **Global and scoped search** — search all feeds or within a specific
///   feed, like Reddit's "Search r/subreddit"
/// - **Feed switching** — integrated feed selector replaces filter chips
/// - **One-tap subscribe** — type `r/subreddit`, `#topic`, or paste a URL
///   to subscribe directly from search results
/// - **Trending topics** and **recent searches** for discovery
/// - **Smart detection** of URLs, subreddits, and hashtags
/// - **User guidance** — contextual hints and onboarding for new users
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/knowledge/types/saved_search.dart';
import 'package:kabuk/services/nip19.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/services/nostr_utils.dart';
import 'package:kabuk/ui/explore/browse_session.dart';
import 'package:kabuk/ui/explore/discovery_providers.dart';
import 'package:kabuk/ui/explore/explore_view.dart';
import 'package:kabuk/ui/explore/feed_management_sheet.dart';
import 'package:kabuk/ui/explore/profile_view.dart';
import 'package:kabuk/ui/explore/topic_following.dart';
import 'package:kabuk/ui/shared/feed_image.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:url_launcher/url_launcher.dart';

// =============================================================================
// Pattern detection helpers
// =============================================================================

/// Detects if a query looks like a subreddit reference.
bool _isSubredditQuery(String q) =>
    RegExp(r'^r/\w+$', caseSensitive: false).hasMatch(q.trim());

/// Detects if a query looks like a hashtag.
bool _isHashtagQuery(String q) {
  final trimmed = q.trim();
  return trimmed.startsWith('#') &&
      trimmed.length > 1 &&
      !trimmed.contains(' ');
}

/// Detects if a query looks like a URL.
bool _isUrlQuery(String q) {
  final trimmed = q.trim();
  return trimmed.startsWith('http://') ||
      trimmed.startsWith('https://') ||
      (trimmed.contains('.') && !trimmed.contains(' ') && trimmed.length > 4);
}

/// Extracts a clean subreddit name from a query (e.g. "r/flutter" → "flutter").
String _subredditName(String q) =>
    q.trim().replaceFirst(RegExp(r'^r/', caseSensitive: false), '');

/// Extracts a clean hashtag from a query (e.g. "#bitcoin" → "bitcoin").
String _hashtagName(String q) => q.trim().replaceFirst('#', '').toLowerCase();

/// Detects if a query looks like a Reddit user profile (e.g. `u/spez`).
bool _isRedditUserQuery(String q) =>
    RegExp(r'^u/\w+$', caseSensitive: false).hasMatch(q.trim());

/// Detects if a query is a Nostr entity: npub1…, nprofile1…, or a 64-char hex pubkey.
bool _isNostrEntityQuery(String q) {
  final t = q.trim();
  if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(t)) return true;
  return t.startsWith('npub1') || t.startsWith('nprofile1');
}

/// Detects if a query looks like a 4chan board reference (e.g. `/g/`, `4chan://g`).
bool _isFourchanBoardQuery(String q) {
  final t = q.trim();
  return RegExp(r'^/[a-z]{1,8}/$', caseSensitive: false).hasMatch(t) ||
      t.startsWith('4chan://') ||
      t.startsWith('4chan:');
}

/// Returns true when the query matches a structured browseable pattern
/// (subreddit, Reddit user, Nostr entity, or 4chan board).
bool _isBrowseableQuery(String q) =>
    _isSubredditQuery(q) ||
    _isRedditUserQuery(q) ||
    _isNostrEntityQuery(q) ||
    _isFourchanBoardQuery(q);

/// Resolves a Nostr entity string to a hex pubkey, or null if unrecognised.
String? _resolveNostrPubkey(String q) {
  final t = q.trim();
  if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(t)) return t;
  try {
    final entity = tryNip19Decode(t);
    if (entity is Nip19Npub) return entity.pubkeyHex;
    if (entity is Nip19Nprofile) return entity.pubkeyHex;
  } on Object {
    // Invalid NIP-19 string — fall through.
  }
  return null;
}

/// Extracts a board name from a 4chan query (e.g. `/g/` → `g`, `4chan://g` → `g`).
String? _extractFourchanBoard(String q) {
  final t = q.trim().toLowerCase();
  if (t.startsWith('4chan://')) return t.substring(8).replaceAll('/', '');
  if (t.startsWith('4chan:')) return t.substring(5).replaceAll('/', '');
  final m = RegExp(r'^/?([a-z]{1,8})/?$').firstMatch(t);
  return m?.group(1);
}

// =============================================================================
// OmniBar — Collapsed bar (sits in the SliverAppBar)
// =============================================================================

/// Chrome-like collapsed search/navigation bar.
///
/// Shows the current feed scope (if any) and a search hint. Tap to open
/// the full [OmniBarSearchPage]. Tap the × on the scope chip to clear
/// the current feed filter.
class OmniBar extends StatelessWidget {
  /// Creates an [OmniBar].
  const OmniBar({
    required this.selectedFeed,
    required this.selectedFeedName,
    required this.selectedFeedType,
    required this.onTap,
    required this.onScopeClear,
    super.key,
  });

  /// Currently selected feed URI, or `null` for "All feeds".
  final String? selectedFeed;

  /// Display name of the selected feed (e.g. "r/technology").
  final String? selectedFeedName;

  /// Feed type of the selected feed (e.g. "reddit", "rss").
  final String? selectedFeedType;

  /// Called when the bar is tapped (opens search page).
  final VoidCallback onTap;

  /// Called when the × on the scope chip is tapped (clears feed filter).
  final VoidCallback onScopeClear;

  @override
  Widget build(BuildContext context) {
    final hasScope = selectedFeed != null;
    final isNostrScope =
        selectedFeed == 'nostr:global' || selectedFeedType == 'nostr';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: KabukTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              size: 20,
              color: KabukTheme.textTertiary,
            ),
            const SizedBox(width: 10),
            // Scope chip (shows current feed context).
            if (hasScope) ...[
              GestureDetector(
                onTap: onScopeClear,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
                  decoration: BoxDecoration(
                    color: _scopeChipColor(isNostrScope).withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _scopeChipColor(isNostrScope).withAlpha(60),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _scopeChipIcon(isNostrScope),
                        size: 13,
                        color: _scopeChipColor(isNostrScope),
                      ),
                      const SizedBox(width: 5),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: Text(
                          selectedFeedName ?? 'Feed',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _scopeChipColor(isNostrScope),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.close_rounded,
                        size: 13,
                        color: _scopeChipColor(isNostrScope).withAlpha(140),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            // Hint text.
            Expanded(
              child: Text(
                hasScope
                    ? 'Search in ${selectedFeedName ?? "feed"}...'
                    : 'Search, subscribe, or enter URL...',
                style: const TextStyle(
                  fontSize: 14,
                  color: KabukTheme.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _scopeChipColor(bool isNostr) {
    if (isNostr) return KabukTheme.purpleAccent;
    if (selectedFeedType == 'reddit') return const Color(0xFFFF4500);
    return KabukTheme.blueAccent;
  }

  IconData _scopeChipIcon(bool isNostr) {
    if (isNostr) return Icons.bolt_rounded;
    if (selectedFeedType == 'reddit') return Icons.reddit;
    return Icons.rss_feed_rounded;
  }
}

// =============================================================================
// OmniBarSearchPage — Full-screen search
// =============================================================================

/// Full-screen search page opened from the [OmniBar].
///
/// Combines feed switching, scoped/global search, trending discovery,
/// subscription actions, and recent search history into a single,
/// guided experience.
class OmniBarSearchPage extends ConsumerStatefulWidget {
  /// Creates an [OmniBarSearchPage].
  const OmniBarSearchPage({
    this.initialScope,
    this.initialScopeName,
    super.key,
  });

  /// Feed URI of the initial search scope (null = global).
  final String? initialScope;

  /// Display name of the initial scope feed.
  final String? initialScopeName;

  @override
  ConsumerState<OmniBarSearchPage> createState() => _OmniBarSearchPageState();
}

class _OmniBarSearchPageState extends ConsumerState<OmniBarSearchPage> {
  final _controller = TextEditingController();
  Timer? _nostrDebounce;
  Timer? _browseDebounce;
  String _query = '';

  // Local (in-memory) search results.
  List<ArticleData> _localResults = [];

  // Nostr relay search results.
  List<NostrEvent> _nostrResults = [];
  List<NostrProfile> _nostrProfiles = [];
  bool _nostrSearching = false;

  // Scope state — which feed are we searching in.
  String? _scope;
  String? _scopeName;

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
    _scopeName = widget.initialScopeName;
  }

  @override
  void dispose() {
    _controller.dispose();
    _nostrDebounce?.cancel();
    _browseDebounce?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Search logic
  // ---------------------------------------------------------------------------

  void _onQueryChanged(String value) {
    final q = value.trim();
    setState(() => _query = q);
    _searchLocal(q);

    // For browseable patterns, start the session after a debounce and pop
    // back to the explore view so the user sees the content.
    _browseDebounce?.cancel();
    if (q.isNotEmpty && _isBrowseableQuery(q)) {
      _browseDebounce = Timer(
        const Duration(milliseconds: 700),
        () => _navigateToBrowse(q),
      );
    }

    // Nostr free-text search — skip for structured patterns.
    _nostrDebounce?.cancel();
    if (q.isNotEmpty && !_isBrowseableQuery(q) && !_isUrlQuery(q)) {
      _nostrDebounce = Timer(
        const Duration(milliseconds: 500),
        () => _searchNostr(q),
      );
    } else if (!_isBrowseableQuery(q)) {
      setState(() {
        _nostrResults = [];
        _nostrProfiles = [];
        _nostrSearching = false;
      });
    }
  }

  /// Resolves the browse session parameters for [q] and navigates back
  /// to the explore view where the content will be displayed.
  void _navigateToBrowse(String q) {
    if (!mounted) return;
    final trimmed = q.trim();
    final String url;
    final String displayName;
    final String sourceType;

    if (_isSubredditQuery(trimmed)) {
      final name = _subredditName(trimmed);
      url = 'r/$name';
      displayName = 'r/$name';
      sourceType = 'reddit';
    } else if (_isRedditUserQuery(trimmed)) {
      final name = trimmed.replaceFirst(
        RegExp(r'^u/', caseSensitive: false),
        '',
      );
      url =
          'https://www.reddit.com/user/$name/submitted.json?limit=25&raw_json=1';
      displayName = 'u/$name';
      sourceType = 'reddit';
    } else if (_isNostrEntityQuery(trimmed)) {
      final pubkey = _resolveNostrPubkey(trimmed);
      if (pubkey == null) return;
      url = pubkey;
      displayName = trimmed.length > 12
          ? '${trimmed.substring(0, 12)}…'
          : trimmed;
      sourceType = 'nostr_profile';
    } else if (_isFourchanBoardQuery(trimmed)) {
      final board = _extractFourchanBoard(trimmed);
      if (board == null) return;
      url = '4chan://$board';
      displayName = '/$board/';
      sourceType = 'fourchan';
    } else {
      return;
    }

    // Start fetching in the background and pop back to the explore view.
    ref
        .read(browseSessionProvider.notifier)
        .browse(url, displayName, sourceType);
    if (mounted) Navigator.of(context).pop();
  }

  void _searchLocal(String query) {
    if (query.isEmpty) {
      setState(() => _localResults = []);
      return;
    }
    final articlesAsync = ref.read(articlesProvider);
    final articles = articlesAsync.valueOrNull ?? [];
    final q = query.toLowerCase();

    final results = articles.where((a) {
      // Scope filter.
      if (_scope != null && a.feedSource != _scope) return false;
      // Text match.
      return (a.name?.toLowerCase().contains(q) ?? false) ||
          (a.description?.toLowerCase().contains(q) ?? false) ||
          (a.author?.toLowerCase().contains(q) ?? false) ||
          a.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();

    setState(() => _localResults = results);
  }

  Future<void> _searchNostr(String query) async {
    if (!mounted) return;
    setState(() => _nostrSearching = true);
    try {
      final nostr = ref.read(nostrServiceProvider);
      final isHashtag = query.startsWith('#') || !query.contains(' ');
      final cleanQuery = query.replaceFirst('#', '').trim();

      final stream = (isHashtag && cleanQuery.isNotEmpty)
          ? nostr.searchByHashtag([cleanQuery.toLowerCase()], limit: 20)
          : nostr.searchContent(query, limit: 20);

      final events = await collectNostrEvents(
        stream,
        where: (e) => e.kind == NostrKind.textNote,
        timeout: const Duration(seconds: 6),
      );

      final seen = <String>{};
      events.removeWhere((e) => !seen.add(e.id));
      events.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Fetch profiles for the top note authors.
      final pubkeys = events.map((e) => e.pubkey).toSet().take(5).toList();
      final profiles = <NostrProfile>[];
      for (final pubkey in pubkeys) {
        try {
          final p = await nostr.fetchProfileCached(pubkey);
          if (p != null) profiles.add(p);
        } on Object {
          // Skip on error.
        }
      }

      if (mounted) {
        setState(() {
          _nostrResults = events;
          _nostrProfiles = profiles;
          _nostrSearching = false;
        });
      }
    } on Object {
      if (mounted) setState(() => _nostrSearching = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Subscribe / follow actions
  // ---------------------------------------------------------------------------

  Future<void> _subscribeToSubreddit(String subreddit) async {
    final name = subreddit.startsWith('r/') ? subreddit : 'r/$subreddit';
    final store = ref.read(knowledgeStoreProvider);

    // Check if already subscribed.
    final existing = await store.listFeedSubscriptions();
    final alreadyExists = existing.any(
      (s) =>
          s.name?.toLowerCase() == name.toLowerCase() ||
          s.feedUrl?.toLowerCase() == name.toLowerCase(),
    );

    if (alreadyExists) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Already subscribed to $name')));
      }
      return;
    }

    await store.createFeedSubscription(
      name: name,
      feedUrl: name,
      feedType: 'reddit',
    );

    ref.invalidate(subscriptionsProvider);
    ref.invalidate(articlesProvider);

    // Auto-fetch the new feed in the background.
    unawaited(
      refreshAllFeeds(ref).then((_) {
        if (mounted) ref.invalidate(articlesProvider);
      }),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Subscribed to $name!'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ),
      );
    }
  }

  Future<void> _subscribeToRss(String url) async {
    var feedUrl = url.trim();
    if (!feedUrl.startsWith('http://') && !feedUrl.startsWith('https://')) {
      feedUrl = 'https://$feedUrl';
    }
    final store = ref.read(knowledgeStoreProvider);

    final existing = await store.listFeedSubscriptions();
    if (existing.any((s) => s.feedUrl == feedUrl)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Already subscribed to this feed')),
        );
      }
      return;
    }

    // Extract domain for name.
    final domain = Uri.tryParse(feedUrl)?.host ?? feedUrl;
    await store.createFeedSubscription(
      name: domain,
      feedUrl: feedUrl,
      feedType: 'rss',
    );

    ref.invalidate(subscriptionsProvider);
    ref.invalidate(articlesProvider);

    // Auto-fetch the new feed in the background.
    unawaited(
      refreshAllFeeds(ref).then((_) {
        if (mounted) ref.invalidate(articlesProvider);
      }),
    );

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Subscribed to $domain!')));
    }
  }

  Future<void> _followHashtag(String hashtag) async {
    final clean = _hashtagName(hashtag);
    try {
      await followTopic(ref, clean);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Now following #$clean on Nostr')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to follow: $e')));
      }
    }
  }

  /// Handles the keyboard submit/go action.
  ///
  /// If the query looks like a URL, opens it in the external browser.
  /// If it looks like a subreddit, subscribes and shows in explore.
  /// Otherwise treats it as a search (results are already shown).
  void _onSubmitted(String value) {
    final q = value.trim();
    if (q.isEmpty) return;

    if (_isUrlQuery(q)) {
      unawaited(_openExternal(q));
    } else if (_isBrowseableQuery(q)) {
      // Cancel pending debounce and navigate immediately.
      _browseDebounce?.cancel();
      _navigateToBrowse(q);
    }
    // For plain text queries the results list is already visible.
  }

  /// Opens a URL in the external browser.
  Future<void> _openExternal(String url) async {
    var openUrl = url.trim();
    if (!openUrl.startsWith('http://') && !openUrl.startsWith('https://')) {
      openUrl = 'https://$openUrl';
    }
    final uri = Uri.tryParse(openUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ---------------------------------------------------------------------------
  // Feed scope
  // ---------------------------------------------------------------------------

  void _setScope(String? feedUri, String? feedName) {
    setState(() {
      _scope = feedUri;
      _scopeName = feedName;
    });
    // Re-run local search with new scope.
    if (_query.isNotEmpty) _searchLocal(_query);
  }

  void _selectFeedAndPop(String? feedUri) {
    ref.read(selectedFeedProvider.notifier).state = feedUri;
    Navigator.of(context).pop();
  }

  /// Opens the feed management sheet.
  Future<void> _openFeedManagement() async {
    final changed = await showFeedManagementSheet(context);
    if (changed == true) {
      ref.invalidate(subscriptionsProvider);
      ref.invalidate(articlesProvider);
    }
  }

  /// Shows a quick action sheet for a single feed subscription.
  void _showFeedActions(BuildContext context, FeedSubscriptionData sub) {
    final isReddit = sub.feedType == 'reddit';
    final color = isReddit ? const Color(0xFFFF4500) : KabukTheme.blueAccent;

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
                // Header.
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
                        child: Text(
                          sub.name ?? sub.feedUrl ?? 'Feed',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: KabukTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: KabukTheme.divider),
                // Filter to this feed.
                ListTile(
                  leading: const Icon(
                    Icons.filter_list_rounded,
                    color: KabukTheme.accentGreen,
                  ),
                  title: const Text('Filter to this feed'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _selectFeedAndPop(sub.uri);
                  },
                ),
                // Unsubscribe.
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
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final confirmed = await showUnsubscribeDialog(context, sub);
                    if (!confirmed) return;
                    final store = ref.read(knowledgeStoreProvider);
                    await store.deleteFeedSubscription(sub.uri);
                    ref.invalidate(subscriptionsProvider);
                    ref.invalidate(articlesProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Unsubscribed from '
                            '${sub.name ?? sub.feedUrl ?? "feed"}',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final subsAsync = ref.watch(subscriptionsProvider);
    final trendingAsync = ref.watch(trendingTopicsProvider);
    final savedAsync = ref.watch(savedSearchesProvider);
    // Re-run local search when articles finish loading so results aren't stale
    // if the user searched before the provider resolved.
    ref.listen(articlesProvider, (prev, next) {
      if (_query.isNotEmpty && next.hasValue) _searchLocal(_query);
    });
    final hasQuery = _query.isNotEmpty;
    final hasSubs = (subsAsync.valueOrNull ?? []).isNotEmpty;

    return Scaffold(
      backgroundColor: KabukTheme.background,
      appBar: AppBar(
        backgroundColor: KabukTheme.surface,
        foregroundColor: KabukTheme.textPrimary,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _buildSearchField(),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          // Scope indicator.
          _buildScopeBar(),

          // Content depends on query state.
          if (!hasQuery) ...[
            // Empty state — discovery mode.
            if (!hasSubs) _buildGettingStarted(),
            _buildFeedsSection(subsAsync),
            _buildTrendingSection(trendingAsync),
            _buildRecentSearches(savedAsync),
            _buildTips(),
          ] else ...[
            // Active search — show results.
            // Browseable patterns (r/x, u/x, npub1..., /g/) auto-navigate to
            // explore view — show a hint while the debounce is pending.
            _buildSmartActions(),
            if (_isBrowseableQuery(_query))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: KabukTheme.accentGreen,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Opening $_query in Explore...',
                      style: const TextStyle(
                        color: KabukTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            if (_localResults.isNotEmpty) _buildLocalResultsSection(),
            if (_nostrSearching)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: KabukTheme.purpleAccent,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Searching Nostr relays...',
                        style: TextStyle(
                          color: KabukTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_nostrResults.isNotEmpty) _buildNostrResultsSection(),
            if (!_nostrSearching &&
                !_isBrowseableQuery(_query) &&
                _localResults.isEmpty &&
                _nostrResults.isEmpty &&
                !_isUrlQuery(_query) &&
                !_isHashtagQuery(_query))
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No results found. Try a different search\n'
                    'or subscribe to more feeds.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: KabukTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sub-builders
  // ---------------------------------------------------------------------------

  Widget _buildSearchField() {
    return TextField(
      controller: _controller,
      autofocus: true,
      onChanged: _onQueryChanged,
      onSubmitted: _onSubmitted,
      style: const TextStyle(color: KabukTheme.textPrimary, fontSize: 16),
      textInputAction: TextInputAction.go,
      decoration: InputDecoration(
        hintText: _scope != null
            ? 'Search in ${_scopeName ?? "feed"}...'
            : 'Search, subscribe, or enter URL...',
        hintStyle: const TextStyle(color: KabukTheme.textTertiary),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingMd,
          vertical: KabukTheme.spacingSm,
        ),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                color: KabukTheme.textTertiary,
                onPressed: () {
                  _controller.clear();
                  _onQueryChanged('');
                },
              )
            : null,
      ),
    );
  }

  Widget _buildScopeBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // "All feeds" chip.
            _scopeChip(
              label: 'All feeds',
              icon: Icons.public_rounded,
              color: KabukTheme.accentGreen,
              isSelected: _scope == null,
              onTap: () => _setScope(null, null),
            ),
            const SizedBox(width: 6),
            // "Nostr" chip.
            _scopeChip(
              label: 'Nostr',
              icon: Icons.bolt_rounded,
              color: KabukTheme.purpleAccent,
              isSelected: _scope == 'nostr:global',
              onTap: () => _setScope('nostr:global', 'Nostr'),
            ),
            // Per-subscription chips (if any).
            ...ref
                .watch(subscriptionsProvider)
                .when(
                  data: (subs) => subs.map(
                    (sub) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _scopeChip(
                        label: sub.name ?? 'Feed',
                        icon: sub.feedType == 'reddit'
                            ? Icons.reddit
                            : Icons.rss_feed_rounded,
                        color: sub.feedType == 'reddit'
                            ? const Color(0xFFFF4500)
                            : KabukTheme.blueAccent,
                        isSelected: _scope == sub.uri,
                        onTap: () => _setScope(sub.uri, sub.name),
                        onLongPress: () => _showFeedActions(context, sub),
                      ),
                    ),
                  ),
                  loading: () => [const SizedBox.shrink()],
                  error: (_, _) => [const SizedBox.shrink()],
                ),
          ],
        ),
      ),
    );
  }

  Widget _scopeChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color.withAlpha(80) : KabukTheme.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? color : KabukTheme.textTertiary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? color : KabukTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Getting Started (onboarding for new users)
  // ---------------------------------------------------------------------------

  Widget _buildGettingStarted() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KabukTheme.accentGreen.withAlpha(15),
            KabukTheme.purpleAccent.withAlpha(10),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KabukTheme.accentGreen.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.explore_rounded,
                size: 24,
                color: KabukTheme.accentGreen.withAlpha(200),
              ),
              const SizedBox(width: 10),
              const Text(
                'Welcome to Explore',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KabukTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Build your personal feed by subscribing to content sources. '
            'Type what you want right here:',
            style: TextStyle(
              color: KabukTheme.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          // Quick subscribe suggestions.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _quickSubscribeChip(
                label: 'r/all',
                icon: Icons.reddit,
                color: const Color(0xFFFF4500),
                onTap: () => _subscribeToSubreddit('r/all'),
              ),
              _quickSubscribeChip(
                label: 'r/technology',
                icon: Icons.reddit,
                color: const Color(0xFFFF4500),
                onTap: () => _subscribeToSubreddit('r/technology'),
              ),
              _quickSubscribeChip(
                label: '#bitcoin',
                icon: Icons.tag_rounded,
                color: KabukTheme.purpleAccent,
                onTap: () => _followHashtag('bitcoin'),
              ),
              _quickSubscribeChip(
                label: '#nostr',
                icon: Icons.tag_rounded,
                color: KabukTheme.purpleAccent,
                onTap: () => _followHashtag('nostr'),
              ),
              _quickSubscribeChip(
                label: '#flutter',
                icon: Icons.tag_rounded,
                color: KabukTheme.purpleAccent,
                onTap: () => _followHashtag('flutter'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickSubscribeChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 14, color: color),
            const SizedBox(width: 4),
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Your Feeds section
  // ---------------------------------------------------------------------------

  Widget _buildFeedsSection(AsyncValue<List<FeedSubscriptionData>> subsAsync) {
    return subsAsync.when(
      data: (subs) {
        if (subs.isEmpty) return const SizedBox.shrink();
        return _section(
          label: 'Your Feeds',
          icon: Icons.rss_feed_rounded,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _openFeedManagement,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: KabukTheme.accentGreen.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: KabukTheme.accentGreen.withAlpha(40),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.settings_rounded,
                        size: 12,
                        color: KabukTheme.accentGreen,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Manage',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: KabukTheme.accentGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          child: SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: subs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final sub = subs[index];
                final isReddit = sub.feedType == 'reddit';
                final color = isReddit
                    ? const Color(0xFFFF4500)
                    : KabukTheme.blueAccent;
                return GestureDetector(
                  onTap: () => _selectFeedAndPop(sub.uri),
                  onLongPress: () => _showFeedActions(context, sub),
                  child: Container(
                    width: 110,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: KabukTheme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: KabukTheme.divider),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isReddit ? Icons.reddit : Icons.rss_feed_rounded,
                          size: 22,
                          color: color,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          sub.name ?? 'Feed',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: KabukTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  // ---------------------------------------------------------------------------
  // Trending section
  // ---------------------------------------------------------------------------

  Widget _buildTrendingSection(AsyncValue<List<TrendingTopic>> trendingAsync) {
    return trendingAsync.when(
      data: (topics) {
        if (topics.isEmpty) return const SizedBox.shrink();
        return _section(
          label: 'Trending on Nostr',
          icon: Icons.trending_up_rounded,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: topics.take(10).map((t) {
                return GestureDetector(
                  onTap: () {
                    _controller.text = '#${t.hashtag}';
                    _onQueryChanged('#${t.hashtag}');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: KabukTheme.purpleAccent.withAlpha(12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: KabukTheme.purpleAccent.withAlpha(30),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '#${t.hashtag}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: KabukTheme.purpleAccent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (t.count > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${t.count}',
                            style: TextStyle(
                              fontSize: 11,
                              color: KabukTheme.purpleAccent.withAlpha(140),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  // ---------------------------------------------------------------------------
  // Recent searches
  // ---------------------------------------------------------------------------

  Widget _buildRecentSearches(AsyncValue<List<SavedSearchData>> savedAsync) {
    return savedAsync.when(
      data: (searches) {
        if (searches.isEmpty) return const SizedBox.shrink();
        final recent = searches.take(6).toList();
        return _section(
          label: 'Recent Searches',
          icon: Icons.history_rounded,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: recent.map((s) {
                final isNostr = s.source?.contains('nostr') ?? false;
                return GestureDetector(
                  onTap: () {
                    _controller.text = s.query ?? '';
                    _onQueryChanged(s.query ?? '');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: KabukTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isNostr ? Icons.bolt_rounded : Icons.search_rounded,
                          size: 14,
                          color: KabukTheme.textTertiary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          s.name ?? s.query ?? 'Search',
                          style: const TextStyle(
                            fontSize: 13,
                            color: KabukTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  // ---------------------------------------------------------------------------
  // Tips (always shown in empty state)
  // ---------------------------------------------------------------------------

  Widget _buildTips() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KabukTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                size: 16,
                color: KabukTheme.warmAccent.withAlpha(180),
              ),
              const SizedBox(width: 8),
              const Text(
                'Quick tips',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: KabukTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _tipRow(
            'r/subreddit',
            'Subscribe to a Reddit community',
            Icons.reddit,
            const Color(0xFFFF4500),
          ),
          const SizedBox(height: 8),
          _tipRow(
            '#topic',
            'Follow a Nostr hashtag',
            Icons.tag_rounded,
            KabukTheme.purpleAccent,
          ),
          const SizedBox(height: 8),
          _tipRow(
            'https://...',
            'Subscribe as feed or open in browser',
            Icons.link_rounded,
            KabukTheme.blueAccent,
          ),
          const SizedBox(height: 8),
          _tipRow(
            'any words',
            'Search your feeds & Nostr network',
            Icons.search_rounded,
            KabukTheme.accentGreen,
          ),
        ],
      ),
    );
  }

  Widget _tipRow(String input, String desc, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color.withAlpha(160)),
        const SizedBox(width: 8),
        Text(
          input,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            desc,
            style: const TextStyle(
              fontSize: 12,
              color: KabukTheme.textTertiary,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Smart actions (subscribe / follow / peek based on query pattern)
  // ---------------------------------------------------------------------------

  Widget _buildSmartActions() {
    final actions = <Widget>[];

    if (_isSubredditQuery(_query)) {
      final name = 'r/${_subredditName(_query)}';
      actions.add(
        _actionTile(
          icon: Icons.add_circle_outline_rounded,
          iconColor: const Color(0xFFFF4500),
          title: 'Subscribe to $name',
          subtitle: 'Add this subreddit to your feed',
          onTap: () => _subscribeToSubreddit(name),
        ),
      );
    }

    if (_isHashtagQuery(_query)) {
      final tag = _hashtagName(_query);
      actions.add(
        _actionTile(
          icon: Icons.add_circle_outline_rounded,
          iconColor: KabukTheme.purpleAccent,
          title: 'Follow #$tag on Nostr',
          subtitle: 'See posts tagged with this topic',
          onTap: () => _followHashtag(tag),
        ),
      );
    }

    if (_isUrlQuery(_query)) {
      actions.add(
        _actionTile(
          icon: Icons.open_in_new_rounded,
          iconColor: KabukTheme.accentGreen,
          title: 'Open in browser',
          subtitle: 'Open this link in your browser',
          onTap: () => unawaited(_openExternal(_query)),
        ),
      );
      actions.add(
        _actionTile(
          icon: Icons.rss_feed_rounded,
          iconColor: KabukTheme.blueAccent,
          title: 'Subscribe as feed',
          subtitle: 'Subscribe to updates from this URL',
          onTap: () => _subscribeToRss(_query),
        ),
      );
    }

    if (_isNostrEntityQuery(_query)) {
      actions.add(
        _actionTile(
          icon: Icons.bolt_rounded,
          iconColor: KabukTheme.purpleAccent,
          title: 'View on njump.me',
          subtitle: 'Open this Nostr entity in your browser',
          onTap: () =>
              unawaited(_openExternal('https://njump.me/${_query.trim()}')),
        ),
      );
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: actions),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: iconColor.withAlpha(10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: iconColor.withAlpha(30)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: iconColor,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: KabukTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: iconColor.withAlpha(120),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Local search results
  // ---------------------------------------------------------------------------

  Widget _buildLocalResultsSection() {
    return _section(
      label: _scope != null
          ? 'In ${_scopeName ?? "feed"} (${_localResults.length})'
          : 'Your articles (${_localResults.length})',
      icon: Icons.article_outlined,
      child: Column(
        children: _localResults.take(10).map((article) {
          return ListTile(
            dense: true,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: KabukTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                article.feedSource?.contains('reddit') == true
                    ? Icons.reddit
                    : Icons.article_outlined,
                size: 18,
                color: KabukTheme.textTertiary,
              ),
            ),
            title: Text(
              article.name ?? 'Untitled',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: article.author != null
                ? Text(
                    article.author!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: KabukTheme.textTertiary,
                    ),
                  )
                : null,
            onTap: () {
              // Return to explore and select this feed if it has a source.
              if (article.feedSource != null) {
                ref.read(selectedFeedProvider.notifier).state =
                    article.feedSource;
              }
              Navigator.of(context).pop();
            },
          );
        }).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Nostr search results
  // ---------------------------------------------------------------------------

  Widget _buildNostrResultsSection() {
    final total = _nostrProfiles.length + _nostrResults.length;
    return _section(
      label: 'Nostr ($total)',
      icon: Icons.bolt_rounded,
      iconColor: KabukTheme.purpleAccent,
      child: Column(
        children: [
          // Profiles first.
          ..._nostrProfiles.map(
            (profile) => ListTile(
              dense: true,
              leading: profile.picture != null
                  ? ClipOval(
                      child: FeedImage(
                        imageUrl: profile.picture!,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                      ),
                    )
                  : CircleAvatar(
                      radius: 18,
                      backgroundColor: KabukTheme.purpleAccent.withAlpha(30),
                      child: Text(
                        profile.displayName.isNotEmpty
                            ? profile.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: KabukTheme.purpleAccent,
                          fontSize: 14,
                        ),
                      ),
                    ),
              title: Text(
                profile.displayName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: profile.nip05 != null
                  ? Text(
                      profile.nip05!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: KabukTheme.purpleAccent,
                      ),
                    )
                  : (profile.about != null && profile.about!.isNotEmpty
                        ? Text(
                            profile.about!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: KabukTheme.textTertiary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: KabukTheme.textTertiary,
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProfileView(pubkey: profile.pubkey),
                  ),
                );
              },
            ),
          ),
          // Notes.
          ..._nostrResults.take(10).map((event) {
            final preview = event.content.length > 150
                ? '${event.content.substring(0, 150)}...'
                : event.content;
            final profile = _nostrProfiles
                .where((p) => p.pubkey == event.pubkey)
                .firstOrNull;
            final author =
                profile?.displayName ?? '${event.pubkey.substring(0, 8)}...';
            return ListTile(
              dense: true,
              leading: profile?.picture != null
                  ? ClipOval(
                      child: FeedImage(
                        imageUrl: profile!.picture!,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                      ),
                    )
                  : CircleAvatar(
                      radius: 18,
                      backgroundColor: KabukTheme.purpleAccent.withAlpha(30),
                      child: const Icon(
                        Icons.bolt_rounded,
                        size: 16,
                        color: KabukTheme.purpleAccent,
                      ),
                    ),
              title: Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                author,
                style: const TextStyle(
                  fontSize: 11,
                  color: KabukTheme.textTertiary,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section helper
  // ---------------------------------------------------------------------------

  Widget _section({
    required String label,
    required IconData icon,
    required Widget child,
    Color? iconColor,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: iconColor ?? KabukTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: KabukTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (trailing != null) ...[const Spacer(), trailing],
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}
