/// OmniBar — Chrome-like unified search, navigation, and browse bar.
///
/// A single bar that replaces the separate search dialog, filter bar,
/// and saved search row with one unified interface. Inspired by Chrome's
/// address bar and Reddit's scoped search.
///
/// Supports:
/// - **Global and scoped search** — search all feeds or within a specific
///   feed, like Reddit's "Search r/subreddit"
/// - **Feed switching** — integrated feed selector replaces filter chips
/// - **URL browsing** — paste a URL to browse it natively; subscribe
///   optionally via a follow button in the channel view
/// - **One-tap subscribe** — type `r/subreddit` or `#topic` to subscribe
/// - **Trending topics** and **recent searches** for discovery
/// - **Smart detection** of URLs, subreddits, and hashtags
/// - **User guidance** — contextual hints and onboarding for new users
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/agents/observation.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/knowledge/types/saved_search.dart';
import 'package:kabuk/knowledge/types/usenet.dart';
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/plugins/plugin.dart';
import 'package:kabuk/plugins/registry.dart';
import 'package:kabuk/services/media_metadata.dart';
import 'package:kabuk/services/nip19.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/services/nostr_utils.dart';
import 'package:kabuk/services/reader_mode.dart';
import 'package:kabuk/services/usenet.dart';
import 'package:kabuk/ui/explore/article_detail_page.dart' show openUrlSmart;
import 'package:kabuk/ui/explore/browse_session.dart';
import 'package:kabuk/ui/explore/discovery_providers.dart';
import 'package:kabuk/ui/explore/explore_tab.dart';
import 'package:kabuk/ui/explore/explore_view.dart';
import 'package:kabuk/ui/explore/feed_management_sheet.dart';
import 'package:kabuk/ui/explore/entity_player.dart' show PlayableEntity, pushEntityPlayer;
import 'package:kabuk/ui/explore/media_detail_page.dart' show pushMediaDetail;
import 'package:kabuk/ui/explore/profile_view.dart';
import 'package:kabuk/ui/explore/topic_following.dart';
import 'package:kabuk/ui/explore/usenet_detail_page.dart' show pushUsenetDetail;
import 'package:kabuk/ui/explore/web_channel_view.dart';
import 'package:kabuk/ui/shared/feed_image.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:kabuk/ui/viewers/viewer_router.dart';

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
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return true;
  }
  // Only treat as URL if it has a recognized TLD and no spaces.
  if (trimmed.contains(' ')) return false;
  const tlds = {
    '.com', '.org', '.net', '.io', '.co', '.dev', '.app', '.edu', '.gov',
    '.me', '.info', '.xyz', '.news', '.blog', '.tech', '.ai', '.tv', '.uk',
    '.de', '.fr', '.jp', '.ru', '.nl', '.se', '.no', '.fi', '.us', '.ca',
    '.au', '.br', '.in', '.it', '.es', '.pt', '.pl', '.cz', '.be', '.ch',
    '.at', '.eu',
  };
  final lower = trimmed.toLowerCase();
  return tlds.any((tld) {
    final idx = lower.indexOf(tld);
    // TLD must appear at end or be followed by a path separator.
    return idx > 0 &&
        (idx + tld.length == lower.length ||
            lower[idx + tld.length] == '/');
  });
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

/// Detects if a query looks like a Usenet search.
///
/// Supported forms:
/// - `nzb:query` — search all indexers for "query"
/// - `usenet:query` — same as above
/// - `nzb:movies:query` — search with a category filter
/// - `usenet:tv:query` — search with a category filter
bool _isUsenetQuery(String q) {
  final t = q.trim().toLowerCase();
  return t.startsWith('nzb:') || t.startsWith('usenet:');
}

/// Parses a Usenet search query into its components.
///
/// Returns a record of `(query, category)` where [category] is `null`
/// when no category prefix was given.
///
/// Examples:
/// - `nzb:interstellar`    → `('interstellar', null)`
/// - `usenet:movies:dune`  → `('dune', 'movies')`
({String query, String? category}) _parseUsenetQuery(String q) {
  final t = q.trim();
  // Strip the leading prefix (nzb: or usenet:).
  final afterPrefix = t.contains(':')
      ? t.substring(t.indexOf(':') + 1)
      : t;

  // Check for an optional category segment: `category:searchTerms`.
  const categories = {
    'movies', 'tv', 'tvshows', 'music', 'games',
    'software', 'books', 'audio', 'other',
  };
  final colonIdx = afterPrefix.indexOf(':');
  if (colonIdx > 0) {
    final maybeCat = afterPrefix.substring(0, colonIdx).toLowerCase();
    if (categories.contains(maybeCat)) {
      return (
        query: afterPrefix.substring(colonIdx + 1).trim(),
        category: maybeCat,
      );
    }
  }

  return (query: afterPrefix.trim(), category: null);
}

/// Builds a `usenet://` URL for a Usenet search query.
///
/// When [category] is provided, appends it as a `&cat=` parameter.
String _buildUsenetSearchUrl(String query, {String? category}) {
  final encoded = Uri.encodeComponent(query);
  final base = 'usenet://search?q=$encoded';
  if (category != null && category.isNotEmpty) {
    return '$base&cat=${Uri.encodeComponent(category)}';
  }
  return base;
}

/// Detects if a query uses the `media:` prefix for TMDB-only search.
///
/// Examples: `media:breaking bad`, `media:inception`.
bool _isMediaQuery(String q) {
  final t = q.trim().toLowerCase();
  return t.startsWith('media:');
}

/// Strips the `media:` prefix from a query.
String _parseMediaQuery(String q) {
  final t = q.trim();
  if (t.toLowerCase().startsWith('media:')) {
    return t.substring(6).trim();
  }
  return t;
}

/// Accent colour for TMDB / media search elements.
const _mediaAccent = Color(0xFF00BCD4);

/// Returns true when the query matches a structured browseable pattern
/// (subreddit, Reddit user, Nostr entity, 4chan board, or Usenet search).
bool _isBrowseableQuery(String q) =>
    _isSubredditQuery(q) ||
    _isRedditUserQuery(q) ||
    _isNostrEntityQuery(q) ||
    _isFourchanBoardQuery(q) ||
    _isUsenetQuery(q) ||
    _isMediaQuery(q);

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
class OmniBar extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final hasScope = selectedFeed != null;
    final isNostrScope =
        selectedFeed == 'nostr:global' || selectedFeedType == 'nostr';
    final activeTab = ref.watch(activeExploreTabProvider);
    final isClassic = activeTab?.mode == ExploreTabMode.classic;

    // In classic mode with a URL, display the URL instead of the hint.
    final displayText = hasScope
        ? 'Search in ${selectedFeedName ?? "feed"}...'
        : isClassic && activeTab?.url != null
            ? _formatDisplayUrl(activeTab!.url!)
            : 'Search or enter URL…';

    return Semantics(
      button: true,
      label: 'Search or enter URL',
      child: Material(
        color: context.kabukSurfaceVariant,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: context.kabukTextTertiary,
                  ),
                  // Mode toggle — semantic ✨ / classic 🌐.
                  GestureDetector(
                    onTap: () {
                      final tabs = ref.read(exploreTabsProvider.notifier);
                      final active = ref.read(activeExploreTabProvider);
                      if (active != null) {
                        tabs.setActiveMode(
                          active.mode == ExploreTabMode.semantic
                              ? ExploreTabMode.classic
                              : ExploreTabMode.semantic,
                        );
                      }
                    },
                    child: Tooltip(
                      message: isClassic
                          ? 'Switch to Semantic mode'
                          : 'Switch to Classic mode',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          isClassic
                              ? Icons.language_rounded
                              : Icons.auto_awesome_rounded,
                          size: 18,
                          color: isClassic
                              ? KabukTheme.warmAccent
                              : KabukTheme.blueAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
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
            // Hint text or URL display.
            Expanded(
              child: Text(
                displayText,
                style: TextStyle(
                  fontSize: 14,
                  color: isClassic && activeTab?.url != null
                      ? context.kabukTextSecondary
                      : context.kabukTextTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
            ),
          ),
        ),
      ),
    );
  }

  /// Formats a URL for compact display (strips scheme and www prefix).
  static String _formatDisplayUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.replaceFirst('www.', '');
      final path = uri.path == '/' ? '' : uri.path;
      return '$host$path';
    } catch (_) {
      return url;
    }
  }

  Color _scopeChipColor(bool isNostr) {
    if (isNostr) return KabukTheme.purpleAccent;
    if (selectedFeedType == 'reddit') return KabukTheme.redditOrange;
    if (selectedFeedType == 'usenet') return KabukTheme.warmAccent;
    return KabukTheme.blueAccent;
  }

  IconData _scopeChipIcon(bool isNostr) {
    if (isNostr) return Icons.bolt_rounded;
    if (selectedFeedType == 'reddit') return Icons.reddit;
    if (selectedFeedType == 'usenet') return Icons.cloud_download_rounded;
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
  Timer? _usenetDebounce;
  Timer? _mediaDebounce;
  Timer? _pluginDebounce;
  String _query = '';

  // Local (in-memory) search results.
  List<ArticleData> _localResults = [];

  // Nostr relay search results.
  List<NostrEvent> _nostrResults = [];
  List<NostrProfile> _nostrProfiles = [];
  bool _nostrSearching = false;

  // Usenet indexer search results.
  List<UsenetRelease> _usenetResults = [];
  bool _usenetSearching = false;
  String? _usenetError;

  // TMDB media search results.
  List<MediaSearchResult> _mediaResults = [];
  bool _mediaSearching = false;

  // Plugin search results — keyed by plugin name.
  Map<String, List<ContentItem>> _pluginResults = {};
  bool _pluginSearching = false;

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
    _usenetDebounce?.cancel();
    _mediaDebounce?.cancel();
    _pluginDebounce?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Search logic
  // ---------------------------------------------------------------------------

  void _onQueryChanged(String value) {
    final q = value.trim();
    debugPrint('[Omnibar] _onQueryChanged: "$q" isUrl=${_isUrlQuery(q)}');
    setState(() => _query = q);
    _searchLocal(q);

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

    // Usenet indexer search — skip for structured patterns and URLs.
    _usenetDebounce?.cancel();
    if (q.isNotEmpty && !_isBrowseableQuery(q) && !_isUrlQuery(q)) {
      _usenetDebounce = Timer(
        const Duration(milliseconds: 500),
        () => _searchUsenet(q),
      );
    } else {
      setState(() {
        _usenetResults = [];
        _usenetSearching = false;
        _usenetError = null;
      });
    }

    // TMDB media search — for default queries and `media:` prefix.
    // Uses composite service (TVmaze + IMDb search proxy + optional TMDB).
    _mediaDebounce?.cancel();
    final isMedia = _isMediaQuery(q);
    if (q.isNotEmpty && (!_isBrowseableQuery(q) || isMedia) && !_isUrlQuery(q)) {
      final mediaQuery = isMedia ? _parseMediaQuery(q) : q;
      if (mediaQuery.isNotEmpty) {
        _mediaDebounce = Timer(
          const Duration(milliseconds: 500),
          () => _searchMedia(mediaQuery),
        );
      }
    } else {
      setState(() {
        _mediaResults = [];
        _mediaSearching = false;
      });
    }

    // Plugin search — query all enabled plugins with search capability.
    _pluginDebounce?.cancel();
    if (q.isNotEmpty && !_isBrowseableQuery(q) && !_isUrlQuery(q)) {
      _pluginDebounce = Timer(
        const Duration(milliseconds: 500),
        () => _searchPlugins(q),
      );
    } else {
      setState(() {
        _pluginResults = {};
        _pluginSearching = false;
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
    } else if (_isUsenetQuery(trimmed)) {
      final parsed = _parseUsenetQuery(trimmed);
      if (parsed.query.isEmpty) return;
      url = _buildUsenetSearchUrl(parsed.query, category: parsed.category);
      displayName = parsed.category != null
          ? 'nzb:${parsed.category}:${parsed.query}'
          : 'nzb:${parsed.query}';
      sourceType = 'usenet';
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

  Future<void> _searchUsenet(String query) async {
    if (!mounted) return;
    debugPrint('[Omnibar] _searchUsenet: "$query"');
    setState(() {
      _usenetSearching = true;
      _usenetError = null;
    });
    try {
      final usenet = ref.read(usenetServiceProvider);
      final result = await usenet.search(query, limit: 10);
      if (!mounted) return;
      setState(() {
        switch (result) {
          case Success(:final value):
            _usenetResults = value;
            _usenetError = null;
            debugPrint('[Omnibar] Usenet results: ${value.length}');
          case Failure(:final error):
            _usenetResults = [];
            _usenetError = error.toString();
            debugPrint('[Omnibar] Usenet search failed: $error');
        }
        _usenetSearching = false;
      });
    } on Object catch (e) {
      debugPrint('[Omnibar] Usenet search exception: $e');
      if (mounted) {
        setState(() {
          _usenetSearching = false;
          _usenetError = 'Search failed: $e';
        });
      }
    }
  }

  Future<void> _searchMedia(String query) async {
    if (!mounted) return;
    final service = ref.read(mediaMetadataServiceProvider);
    setState(() => _mediaSearching = true);
    try {
      final result = await service.search(query);
      if (!mounted) return;
      setState(() {
        switch (result) {
          case Success(:final value):
            _mediaResults = value;
          case Failure():
            _mediaResults = [];
        }
        _mediaSearching = false;
      });
    } on Object {
      if (mounted) setState(() => _mediaSearching = false);
    }
  }

  Future<void> _searchPlugins(String query) async {
    if (!mounted) return;
    setState(() => _pluginSearching = true);
    try {
      final registry = ref.read(pluginRegistryProvider);
      final searchPlugins =
          registry.pluginsForCapability(ContentCapability.search);
      final results = <String, List<ContentItem>>{};
      for (final plugin in searchPlugins) {
        try {
          final items = await plugin.search(query, perPage: 5);
          if (items.isNotEmpty) {
            results[plugin.name] = items;
          }
        } on Object catch (e) {
          debugPrint('[Omnibar] Plugin ${plugin.id} search failed: $e');
        }
      }
      if (!mounted) return;
      setState(() {
        _pluginResults = results;
        _pluginSearching = false;
      });
    } on Object {
      if (mounted) setState(() => _pluginSearching = false);
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

  Future<void> _followHashtag(String hashtag) async {
    final clean = _hashtagName(hashtag);
    try {
      await followTopic(ref, clean);
      ref.invalidate(subscriptionsProvider);
      ref.invalidate(articlesProvider);
      unawaited(
        refreshAllFeeds(ref).then((_) {
          if (mounted) ref.invalidate(articlesProvider);
        }),
      );
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
      _browseUrl(q);
    } else if (_isBrowseableQuery(q)) {
      _navigateToBrowse(q);
    }
    // For plain text queries the results list is already visible.
  }

  /// Opens a URL in-app, routing Reddit URLs to native views.
  void _openExternal(String url) {
    var openUrl = url.trim();
    if (!openUrl.startsWith('http://') && !openUrl.startsWith('https://')) {
      openUrl = 'https://$openUrl';
    }
    openUrlSmart(context, openUrl);
  }

  /// Parses a URL with AI, stores semantic objects in the knowledge base,
  /// and navigates to a native channel view showing the extracted content.
  /// Does NOT auto-subscribe — the user can follow from the channel view.
  ///
  /// When [preferClassicWebProvider] is enabled, HTTP/HTTPS URLs are opened
  /// directly in Classic Web mode instead of the semantic pipeline.
  Future<void> _browseUrl(String url) async {
    debugPrint('[Omnibar] _browseUrl called with: $url');
    var feedUrl = url.trim();
    if (!feedUrl.startsWith('http://') && !feedUrl.startsWith('https://')) {
      feedUrl = 'https://$feedUrl';
    }

    // Classic Web override — switch the active tab to a full WebView.
    if (ref.read(preferClassicWebProvider)) {
      ref.read(exploreTabsProvider.notifier)
        ..setActiveMode(ExploreTabMode.classic)
        ..updateActiveUrl(feedUrl);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // Try resolving via content plugins before falling back to web view.
    try {
      final registry = ref.read(pluginRegistryProvider);
      final resolved = await registry.resolveUrl(feedUrl);
      if (resolved != null && mounted) {
        final (_, content) = resolved;
        switch (content) {
          case ResolvedContentItem(:final item):
            if (mounted) {
              Navigator.of(context).pop();
              await ViewerRouter.open(context, item);
            }
            return;
          case ResolvedChannel(:final entityUri, :final title):
            // Perception: the user resolved a URL to a channel.
            ref.read(observationBusProvider).publish(
              ChannelResolvedEvent(
                source: feedUrl,
                channelUri: entityUri,
                title: title,
              ),
            );
            if (mounted) {
              await Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => WebChannelView(
                    url: feedUrl,
                    articleUris: [entityUri],
                    isMultiArticle: false,
                  ),
                ),
              );
            }
            return;
          case ResolvedNotHandled():
            break;
        }
      }
    } on Object catch (e) {
      debugPrint('[Omnibar] Plugin URL resolve failed: $e');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Loading page…')),
    );

    try {
      // Process the page — articles are stored in knowledge base.
      final service = ref.read(readerModeServiceProvider);
      final uri = Uri.tryParse(feedUrl);
      final domain = uri?.host.replaceFirst('www.', '') ?? feedUrl;
      final result = await service.processUrl(
        feedUrl,
        feedSource: 'web:$domain',
      );

      ref.invalidate(articlesProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();

      // Navigate to native channel view showing parsed content.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => WebChannelView(
            url: feedUrl,
            articleUris: result.articleUris,
            isMultiArticle: result.isMultiArticle,
            nextPageUrl: result.nextPageUrl,
            navigationLinks: result.navigationLinks,
          ),
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load page: $e')),
        );
      }
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
    final tab = ref.read(activeExploreTabProvider);
    if (tab != null) {
      ref.read(exploreTabsProvider.notifier).updateTab(
        tab.id,
        (t) => t.copyWith(selectedFeed: feedUri),
      );
    }
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
    final color = isReddit ? KabukTheme.redditOrange : KabukTheme.blueAccent;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.kabukSurfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusLg),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          bottom: false,
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.kabukTextPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: context.kabukDivider),
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
                  subtitle: Text(
                    'Remove feed and all its articles',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.kabukTextTertiary,
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
      backgroundColor: context.kabukBackground,
      appBar: AppBar(
        backgroundColor: context.kabukSurface,
        foregroundColor: context.kabukTextPrimary,
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
            _buildSmartActions(),
            if (_localResults.isNotEmpty &&
                _scope != 'nostr:global' &&
                _scope != 'usenet:all')
              _buildLocalResultsSection(),
            if (_nostrSearching && _scope != 'usenet:all')
              Padding(
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
                          color: context.kabukTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_nostrResults.isNotEmpty && _scope != 'usenet:all')
              _buildNostrResultsSection(),
            // Media results first — entity-centric cards with posters.
            if (_mediaSearching)
              Padding(
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
                          color: _mediaAccent,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Searching TV & Movies…',
                        style: TextStyle(
                          color: context.kabukTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_mediaResults.isNotEmpty)
              _buildMediaResultsSection(),
            if (!_mediaSearching &&
                _mediaResults.isEmpty &&
                !_isBrowseableQuery(_query) &&
                !_isUrlQuery(_query) &&
                _query.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.movie_outlined,
                      size: 14,
                      color: context.kabukTextTertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No movies or TV shows found',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.kabukTextTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Usenet results below media results.
            if (_usenetSearching && _scope != 'nostr:global')
              Padding(
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
                          color: KabukTheme.warmAccent,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Searching Usenet indexers...',
                        style: TextStyle(
                          color: context.kabukTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_usenetResults.isNotEmpty && _scope != 'nostr:global')
              _buildUsenetResultsSection(),
            if (_usenetError != null &&
                !_usenetSearching &&
                _scope != 'nostr:global')
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  _usenetError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            // Plugin search results.
            if (_pluginSearching)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: KabukTheme.accentGreen,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Searching plugins…',
                        style: TextStyle(
                          color: context.kabukTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            for (final entry in _pluginResults.entries)
              _buildPluginResultsSection(entry.key, entry.value),
            if (!_nostrSearching &&
                !_usenetSearching &&
                !_mediaSearching &&
                !_pluginSearching &&
                !_isBrowseableQuery(_query) &&
                _localResults.isEmpty &&
                _nostrResults.isEmpty &&
                _usenetResults.isEmpty &&
                _mediaResults.isEmpty &&
                _pluginResults.isEmpty &&
                !_isUrlQuery(_query) &&
                !_isHashtagQuery(_query))
              Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No results found. Try a different search\n'
                    'or subscribe to more feeds.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.kabukTextSecondary,
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
    final isUrl = _isUrlQuery(_query);
    final isBrowseable = _isBrowseableQuery(_query);
    final isUsenet = _isUsenetQuery(_query);
    final showGoArrow = isUrl || isBrowseable;
    return TextField(
      controller: _controller,
      autofocus: true,
      onChanged: _onQueryChanged,
      onSubmitted: _onSubmitted,
      textInputAction: showGoArrow ? TextInputAction.go : TextInputAction.search,
      maxLines: 1,
      minLines: 1,
      style: TextStyle(color: context.kabukTextPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: _scope != null
            ? 'Search in ${_scopeName ?? "feed"}...'
            : 'Search or enter URL\u2026',
        hintStyle: TextStyle(
          color: context.kabukTextSecondary,
          fontSize: 14,
        ),
        filled: true,
        fillColor: context.kabukSurfaceVariant,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        suffixIcon: showGoArrow
            ? IconButton(
                icon: Icon(
                  Icons.arrow_forward_rounded,
                  color: isUsenet
                      ? KabukTheme.warmAccent
                      : isBrowseable && !isUrl
                          ? KabukTheme.purpleAccent
                          : KabukTheme.blueAccent,
                  size: 20,
                ),
                onPressed: () => _onSubmitted(_controller.text),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              )
            : null,
        suffixIconConstraints: showGoArrow
            ? const BoxConstraints(minWidth: 36, minHeight: 36)
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
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
            const SizedBox(width: 6),
            // "Usenet" chip.
            _scopeChip(
              label: 'Usenet',
              icon: Icons.cloud_download_rounded,
              color: KabukTheme.warmAccent,
              isSelected: _scope == 'usenet:all',
              onTap: () => _setScope('usenet:all', 'Usenet'),
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
                            ? KabukTheme.redditOrange
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
            color: isSelected ? color.withAlpha(80) : context.kabukDivider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? color : context.kabukTextTertiary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? color : context.kabukTextSecondary,
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
              Text(
                'Welcome to Explore',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.kabukTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Build your personal feed by subscribing to content sources. '
            'Type what you want right here:',
            style: TextStyle(
              color: context.kabukTextSecondary,
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
                color: KabukTheme.redditOrange,
                onTap: () => _subscribeToSubreddit('r/all'),
              ),
              _quickSubscribeChip(
                label: 'r/technology',
                icon: Icons.reddit,
                color: KabukTheme.redditOrange,
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
                    ? KabukTheme.redditOrange
                    : KabukTheme.blueAccent;
                return GestureDetector(
                  onTap: () => _selectFeedAndPop(sub.uri),
                  onLongPress: () => _showFeedActions(context, sub),
                  child: Container(
                    width: 110,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.kabukCardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.kabukDivider),
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
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: context.kabukTextPrimary,
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
        // Deduplicate by query text, keeping the most-recent entry for each.
        final seen = <String>{};
        final deduped = searches
            .where((s) => seen.add((s.query ?? s.name ?? '').toLowerCase()))
            .toList();
        final recent = deduped.take(6).toList();
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
                      color: context.kabukSurfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isNostr ? Icons.bolt_rounded : Icons.search_rounded,
                          size: 14,
                          color: context.kabukTextTertiary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          s.name ?? s.query ?? 'Search',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.kabukTextSecondary,
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
        color: context.kabukSurface,
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
              Text(
                'Quick tips',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.kabukTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _tipRow(
            'r/subreddit',
            'Subscribe to a Reddit community',
            Icons.reddit,
            KabukTheme.redditOrange,
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
            'Browse page natively',
            Icons.link_rounded,
            KabukTheme.blueAccent,
          ),
          const SizedBox(height: 8),
          _tipRow(
            'nzb:query',
            'Search Usenet indexers',
            Icons.cloud_download_rounded,
            KabukTheme.warmAccent,
          ),
          const SizedBox(height: 8),
          _tipRow(
            'media:query',
            'Search TV shows & movies',
            Icons.movie_outlined,
            _mediaAccent,
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
            style: TextStyle(
              fontSize: 12,
              color: context.kabukTextTertiary,
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
    final subs = ref.watch(subscriptionsProvider).valueOrNull ?? [];

    if (_isSubredditQuery(_query)) {
      final name = 'r/${_subredditName(_query)}';
      // Always show browse action first.
      actions.add(
        _actionTile(
          icon: Icons.explore_outlined,
          iconColor: KabukTheme.redditOrange,
          title: 'Browse $name',
          subtitle: 'View posts without subscribing',
          onTap: () => _navigateToBrowse(_query),
        ),
      );
      final alreadySubscribed = subs.any(
        (s) =>
            s.name?.toLowerCase() == name.toLowerCase() ||
            s.feedUrl?.toLowerCase() == name.toLowerCase(),
      );
      if (!alreadySubscribed) {
        actions.add(
          _actionTile(
            icon: Icons.add_circle_outline_rounded,
            iconColor: KabukTheme.redditOrange,
            title: 'Subscribe to $name',
            subtitle: 'Add this subreddit to your feed',
            onTap: () => _subscribeToSubreddit(name),
          ),
        );
      }
    }

    if (_isRedditUserQuery(_query)) {
      final user = _query.trim();
      actions.add(
        _actionTile(
          icon: Icons.person_outline_rounded,
          iconColor: KabukTheme.blueAccent,
          title: 'View $user posts',
          subtitle: 'Browse this user\'s submissions',
          onTap: () => _navigateToBrowse(_query),
        ),
      );
    }

    if (_isFourchanBoardQuery(_query)) {
      final board = _extractFourchanBoard(_query.trim());
      if (board != null) {
        actions.add(
          _actionTile(
            icon: Icons.explore_outlined,
            iconColor: KabukTheme.accentGreen,
            title: 'Browse /$board/',
            subtitle: 'View threads on this board',
            onTap: () => _navigateToBrowse(_query),
          ),
        );
      }
    }

    if (_isHashtagQuery(_query)) {
      final tag = _hashtagName(_query);
      final alreadyFollowing = subs.any(
        (s) =>
            s.feedType == 'nostr' &&
            (s.feedUrl == 'nostr:t/$tag' || s.name?.toLowerCase() == '#$tag'),
      );
      if (!alreadyFollowing) {
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
    }

    if (_isUrlQuery(_query)) {
      final displayUrl = _query.trim().replaceFirst(RegExp(r'^https?://'), '');
      actions.add(
        _actionTile(
          icon: Icons.arrow_forward_rounded,
          iconColor: KabukTheme.blueAccent,
          title: displayUrl,
          subtitle: 'Go to this page',
          onTap: () => _browseUrl(_query),
        ),
      );
    }

    if (_isNostrEntityQuery(_query)) {
      actions.add(
        _actionTile(
          icon: Icons.explore_outlined,
          iconColor: KabukTheme.purpleAccent,
          title: 'View Nostr profile',
          subtitle: 'Browse this Nostr entity',
          onTap: () => _navigateToBrowse(_query),
        ),
      );
      actions.add(
        _actionTile(
          icon: Icons.bolt_rounded,
          iconColor: KabukTheme.purpleAccent,
          title: 'View on njump.me',
          subtitle: 'Preview this Nostr entity in-app',
          onTap: () => _openExternal('https://njump.me/${_query.trim()}'),
        ),
      );
    }

    if (_isUsenetQuery(_query)) {
      final parsed = _parseUsenetQuery(_query);
      final label = parsed.category != null
          ? '${parsed.category}:${parsed.query}'
          : parsed.query;
      actions.add(
        _actionTile(
          icon: Icons.cloud_download_rounded,
          iconColor: KabukTheme.warmAccent,
          title: 'Search Usenet for "$label"',
          subtitle: parsed.category != null
              ? 'Browse ${parsed.category} on all indexers'
              : 'Search across all Usenet indexers',
          onTap: () => _navigateToBrowse(_query),
        ),
      );
    }

    if (_isMediaQuery(_query)) {
      final parsed = _parseMediaQuery(_query);
      if (parsed.isNotEmpty) {
        actions.add(
          _actionTile(
            icon: Icons.movie_outlined,
            iconColor: _mediaAccent,
            title: 'Search for "$parsed"',
            subtitle: 'Find movies and TV shows',
            onTap: () => _searchMedia(parsed),
          ),
        );
      }
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
      child: Semantics(
        button: true,
        label: title,
        child: TextButton(
          onPressed: () {
            debugPrint('[Omnibar] Action tile tapped: $title');
            onTap();
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.all(14),
            backgroundColor: iconColor.withAlpha(10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: iconColor.withAlpha(30)),
            ),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: context.kabukTextTertiary,
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
                color: context.kabukSurfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                article.feedSource?.contains('reddit') == true
                    ? Icons.reddit
                    : Icons.article_outlined,
                size: 18,
                color: context.kabukTextTertiary,
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
                    style: TextStyle(
                      fontSize: 12,
                      color: context.kabukTextTertiary,
                    ),
                  )
                : null,
            onTap: () {
              // Return to explore and select this feed if it has a source.
              if (article.feedSource != null) {
                final tab = ref.read(activeExploreTabProvider);
                if (tab != null) {
                  ref.read(exploreTabsProvider.notifier).updateTab(
                    tab.id,
                    (t) => t.copyWith(selectedFeed: article.feedSource),
                  );
                }
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
                            style: TextStyle(
                              fontSize: 11,
                              color: context.kabukTextTertiary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null),
              trailing: Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: context.kabukTextTertiary,
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
                style: TextStyle(
                  fontSize: 11,
                  color: context.kabukTextTertiary,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Usenet search results
  // ---------------------------------------------------------------------------

  Widget _buildUsenetResultsSection() {
    return _section(
      label: 'Usenet (${_usenetResults.length})',
      icon: Icons.cloud_download_rounded,
      iconColor: KabukTheme.warmAccent,
      child: Column(
        children: _usenetResults.take(10).map((release) {
          final sizeText =
              release.sizeBytes > 0 ? _formatBytesCompact(release.sizeBytes) : null;
          final categoryLabel = release.category.name;
          return ListTile(
            dense: true,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: KabukTheme.warmAccent.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.cloud_download_rounded,
                size: 18,
                color: KabukTheme.warmAccent,
              ),
            ),
            title: Text(
              release.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Row(
              children: [
                if (sizeText != null) ...[
                  Text(
                    sizeText,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.kabukTextTertiary,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: KabukTheme.warmAccent.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    categoryLabel,
                    style: const TextStyle(
                      fontSize: 10,
                      color: KabukTheme.warmAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: context.kabukTextTertiary,
            ),
            onTap: () {
              final data = UsenetReleaseData(
                uri: 'usenet:release:${release.id}',
                title: release.title,
                indexerRef: release.indexerId,
                nzbUrl: release.nzbUrl,
                sizeBytes: release.sizeBytes,
                publishedAt: release.publishedAt,
                category: release.category.name,
                group: release.group,
                poster: release.poster,
                description: release.description,
                imdbId: release.imdbId,
                tvdbId: release.tvdbId,
              );
              pushUsenetDetail(context, release: data);
            },
          );
        }).toList(),
      ),
    );
  }

  /// Formats a byte count into a compact human-readable string.
  static String _formatBytesCompact(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  // ---------------------------------------------------------------------------
  // Media search results (composite: TVmaze + IMDbAPI + optional TMDB)
  // ---------------------------------------------------------------------------

  Widget _buildMediaResultsSection() {
    final mediaService = ref.read(mediaMetadataServiceProvider);
    return _section(
      label: 'TV & Movies (${_mediaResults.length})',
      icon: Icons.movie_outlined,
      iconColor: _mediaAccent,
      child: Column(
        children: _mediaResults.take(10).map((result) {
          final posterUrl = result.posterPath != null
              ? mediaService.imageUrl(result.posterPath!, size: MediaImageSize.small)
              : null;
          final yearText = result.releaseYear != null
              ? '${result.releaseYear}'
              : null;
          final typeName = switch (result.mediaType) {
            MediaType.movie => 'Movie',
            MediaType.tvSeries => 'TV',
          };
          final voteText = result.voteAverage != null && result.voteAverage! > 0
              ? result.voteAverage!.toStringAsFixed(1)
              : null;

          return ListTile(
            dense: true,
            leading: SizedBox(
              width: 46,
              height: 68,
              child: posterUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        posterUrl,
                        width: 46,
                        height: 68,
                        fit: BoxFit.cover,
                        errorBuilder: (_, e, st) => _mediaPosterFallback(),
                      ),
                    )
                  : _mediaPosterFallback(),
            ),
            title: Text(
              result.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: _mediaAccent.withAlpha(25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    typeName,
                    style: const TextStyle(
                      fontSize: 10,
                      color: _mediaAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (yearText != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    yearText,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.kabukTextTertiary,
                    ),
                  ),
                ],
                if (voteText != null) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.star_rounded,
                    size: 12,
                    color: KabukTheme.warmAccent.withAlpha(180),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    voteText,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.kabukTextTertiary,
                    ),
                  ),
                ],
              ],
            ),
            trailing: result.mediaType == MediaType.movie
                ? IconButton(
                    icon: const Icon(
                      Icons.play_circle_fill_rounded,
                      color: KabukTheme.accentGreen,
                      size: 28,
                    ),
                    tooltip: 'Play',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Navigator.of(context).pop();
                      pushEntityPlayer(
                        context,
                        PlayableEntity(
                          title: result.title,
                          year: result.releaseYear,
                          posterUrl: posterUrl,
                          imdbId: result.imdbId,
                        ),
                      );
                    },
                  )
                : Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: context.kabukTextTertiary,
                  ),
            onTap: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              pushMediaDetail(
                context,
                navigator: navigator,
                tmdbId: result.id,
                mediaType: result.mediaType,
                title: result.title,
                posterPath: result.posterPath,
              );
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _mediaPosterFallback() {
    return Container(
      width: 46,
      height: 68,
      decoration: BoxDecoration(
        color: _mediaAccent.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(
        Icons.movie_outlined,
        size: 20,
        color: _mediaAccent,
      ),
    );
  }

  Widget _buildPluginResultsSection(String pluginName, List<ContentItem> items) {
    return _section(
      label: '$pluginName (${items.length})',
      icon: Icons.extension_rounded,
      iconColor: KabukTheme.accentGreen,
      child: Column(
        children: items.map((item) {
          return ListTile(
            dense: true,
            leading: item.thumbnailUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      item.thumbnailUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: KabukTheme.accentGreen.withAlpha(20),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.extension_rounded,
                          size: 18,
                          color: KabukTheme.accentGreen,
                        ),
                      ),
                    ),
                  )
                : Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: KabukTheme.accentGreen.withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.extension_rounded,
                      size: 18,
                      color: KabukTheme.accentGreen,
                    ),
                  ),
            title: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: item.description != null
                ? Text(
                    item.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.kabukTextSecondary,
                    ),
                  )
                : null,
            onTap: () {
              ViewerRouter.open(context, item);
            },
          );
        }).toList(),
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
                  color: iconColor ?? context.kabukTextSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: context.kabukTextSecondary,
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
