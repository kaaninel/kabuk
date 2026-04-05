/// Native channel view for browsed web content.
///
/// Displays web content that has been parsed into semantic objects in the
/// knowledge base. Works like a channel/subreddit view but for any URL.
/// The user can optionally subscribe to the page via the follow button.
///
/// This is how Kabuk browses the web — URLs are parsed into native
/// articles and displayed in a channel format, not in a WebView.
library;

import 'dart:developer' as dev;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/knowledge/types/media.dart';
import 'package:kabuk/knowledge/types/webpage.dart';
import 'package:kabuk/services/reader_mode.dart';
import 'package:kabuk/services/web_extractor.dart';
import 'package:kabuk/ui/explore/article_card.dart';
import 'package:kabuk/ui/explore/explore_view.dart';
import 'package:kabuk/ui/explore/reader_view.dart';
import 'package:kabuk/ui/explore/semantic_cards.dart';
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
  List<_EntityEntry> _entityEntries = [];
  bool _isLoading = true;
  bool _isSubscribed = false;
  String? _subscriptionUri;
  bool _isLoadingMore = false;
  String? _nextPageUrl;
  final _scrollController = ScrollController();

  String get _domain =>
      Uri.tryParse(widget.url)?.host.replaceFirst('www.', '') ?? widget.url;

  /// Generic site navigation labels to filter out from navigation links.
  static const _genericNavLabels = {
    'home', 'random', 'nearby', 'watch', 'watchlist', 'about', 'contact',
    'contact us', 'privacy', 'privacy policy', 'terms', 'terms of service',
    'login', 'log in', 'sign in', 'sign up', 'register', 'help', 'faq',
    'search', 'settings', 'preferences', 'donate', 'contributions',
    'main page', 'special pages', 'upload', 'create account',
    'what links here', 'related changes', 'printable version',
    'permanent link', 'page information', 'cite this page',
  };

  /// Navigation links filtered to remove generic site navigation.
  List<ExtractedLink> get _filteredNavLinks {
    return widget.navigationLinks.where((link) {
      final label = link.title.trim().toLowerCase();
      if (label.isEmpty || label.length < 2) return false;
      if (_genericNavLabels.contains(label)) return false;
      // Filter links pointing to login/auth/special pages.
      final url = link.url.toLowerCase();
      if (url.contains('/login') ||
          url.contains('/signup') ||
          url.contains('/register') ||
          url.contains('action=edit') ||
          url.contains('special:')) {
        return false;
      }
      return true;
    }).toList();
  }

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

  /// Extracts a clean domain name from a URL (e.g. "theverge.com").
  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      return host.startsWith('www.') ? host.substring(4) : host;
    } catch (_) {
      return '';
    }
  }

  /// Returns true if an entity name is boilerplate for the given source URL.
  ///
  /// Filters out platform/hosting entities that appear on every page of a
  /// site (e.g. Wikimedia on Wikipedia, Automattic on WordPress.com).
  static bool _isBoilerplateEntity(String normName, String url) {
    if (normName.isEmpty) return false;
    // Wikipedia / Wikimedia boilerplate.
    if (url.contains('wikipedia.org') || url.contains('wikimedia.org')) {
      if (normName.contains('wikimedia') ||
          normName.contains('wikipedia') ||
          normName.contains('contributors to')) {
        return true;
      }
    }
    // Generic hosting/platform entities.
    const boilerplate = {
      'cloudflare', 'google analytics', 'facebook pixel',
      'google tag manager', 'doubleclick', 'adsense',
    };
    return boilerplate.contains(normName);
  }

  Future<void> _loadArticles() async {
    final store = ref.read(knowledgeStoreProvider);
    final loaded = <ArticleData>[];

    for (final uri in widget.articleUris) {
      final article = await store.getArticleData(uri);
      if (article != null) loaded.add(article);
    }

    // Load non-article semantic entities from the WebPage's member list.
    final articleUriSet = widget.articleUris.toSet();
    final entities = <_EntityEntry>[];

    // Try finding the WebPage with the URL (findWebPageByUrl already
    // normalises and tries variants).
    final webPage = await store.findWebPageByUrl(widget.url);

    // Helper to resolve entity type, checking kabuk:semanticType first.
    Future<String> resolveType(String uri) async {
      final semanticType = (await store
              .query()
              .subject(uri)
              .predicate(NS.kabukSemanticType)
              .execute())
          .firstOrNull
          ?.objectValue;
      return semanticType ?? _entityTypeFromUri(uri);
    }

    // Fallback: search for entities with kabuk:extractedFrom matching the
    // domain when no WebPage record was found.
    if (webPage == null) {
      dev.log(
        '[WebChannel] No WebPage found for ${widget.url}, trying domain '
        'fallback',
        name: 'WebChannelView',
      );
      final domain =
          Uri.tryParse(widget.url)?.host.replaceFirst('www.', '') ?? '';
      if (domain.isNotEmpty) {
        final seen = <String>{};
        // Only load entities that were extracted from this specific URL —
        // not all memberEntity triples in the entire knowledge store.
        final extracted = await store
            .query()
            .predicate(NS.kabukExtractedFrom)
            .execute();
        for (final t in extracted) {
          final sourceUrl = t.objectValue;
          // Only include entities extracted from URLs in the same domain.
          final sourceDomain =
              Uri.tryParse(sourceUrl)?.host.replaceFirst('www.', '') ?? '';
          if (sourceDomain != domain) continue;
          final entityUri = t.subject;
          if (articleUriSet.contains(entityUri)) continue;
          if (!seen.add(entityUri)) continue;
          final type = await resolveType(entityUri);
          if (_supportedEntityTypes.contains(type)) {
            entities.add(_EntityEntry(uri: entityUri, type: type));
          }
        }
      }
    } else {
      final seen = <String>{};
      for (final memberUri in webPage.memberEntities) {
        if (articleUriSet.contains(memberUri)) continue;
        if (!seen.add(memberUri)) continue; // skip duplicate URIs
        final type = await resolveType(memberUri);
        if (_supportedEntityTypes.contains(type)) {
          entities.add(_EntityEntry(uri: memberUri, type: type));
        }
      }
    }

    // Name-based dedup: same entity type + normalised name → keep first.
    // Also handles aliases where one name contains another (e.g. "SpaceX" vs
    // "Space Exploration Technologies Corporation").
    final dedupedEntities = <_EntityEntry>[];
    final entityNameMap = <String, String>{}; // uri → normalised name
    final seenNames = <String, List<String>>{}; // type → list of normalised names
    // Collect sameAs, URL, and description data for cross-reference dedup.
    final entityUrls = <String, String>{}; // uri → url
    final entitySameAs = <String, Set<String>>{}; // uri → sameAs set
    final entityDescs = <String, String>{}; // uri → description
    for (final entry in entities) {
      final nameTriples =
          await store.query().subject(entry.uri).predicate(NS.schemaName).execute();
      final rawName = nameTriples.firstOrNull?.objectValue ?? '';
      final normName = rawName.trim().toLowerCase();
      entityNameMap[entry.uri] = normName;

      // Load URL, sameAs, and description for cross-reference dedup.
      final urlTriples =
          await store.query().subject(entry.uri).predicate(NS.schemaUrl).execute();
      entityUrls[entry.uri] = urlTriples.firstOrNull?.objectValue.toLowerCase().trim() ?? '';
      final sameAsTriples =
          await store.query().subject(entry.uri).predicate(NS.schemaSameAs).execute();
      entitySameAs[entry.uri] =
          sameAsTriples.map((t) => t.objectValue.toLowerCase().trim()).toSet();
      final descTriples =
          await store.query().subject(entry.uri).predicate(NS.schemaDescription).execute();
      entityDescs[entry.uri] = descTriples.firstOrNull?.objectValue.toLowerCase().trim() ?? '';

      final typeNames = seenNames.putIfAbsent(entry.type, () => <String>[]);
      if (normName.isEmpty) {
        dedupedEntities.add(entry);
        continue;
      }
      // Check exact match, containment, or word-overlap for orgs (e.g. "SpaceX"
      // vs "Space Exploration Technologies Corporation").
      bool isDuplicate;
      if (normName.length < 3) {
        isDuplicate = typeNames.any((existing) => existing == normName);
      } else {
        final normWords = normName.split(RegExp(r'\s+')).toSet();
        final normCompact = normName.replaceAll(' ', '');
        isDuplicate = typeNames.any((existing) {
          if (existing == normName) return true;
          if (existing.contains(normName) || normName.contains(existing)) {
            return true;
          }
          // Compact comparison: "theverge" == "the verge" compacted.
          final existingCompact = existing.replaceAll(' ', '');
          if (existingCompact == normCompact) return true;
          // Word overlap: if all words of the shorter name appear in the longer
          // name, treat as duplicate (e.g. "Wikimedia Foundation" in
          // "Wikimedia Foundation, Inc.").
          final existingWords = existing.split(RegExp(r'\s+')).toSet();
          final shorter =
              normWords.length <= existingWords.length ? normWords : existingWords;
          final longer =
              normWords.length > existingWords.length ? normWords : existingWords;
          if (shorter.length >= 2 && shorter.every((w) => longer.contains(w))) {
            return true;
          }
          // CamelCase brand vs expanded name: "SpaceX" vs "Space Exploration"
          // Check if the shorter name (as one word) starts with or is a prefix
          // of the first word of the longer name, combined with description
          // cross-reference.
          final desc = entityDescs[entry.uri] ?? '';
          if (normName.length >= 4 && existingWords.length >= 2) {
            // Check if shorter name appears in longer's description
            final existingUri = dedupedEntities
                .where((e) => entityNameMap[e.uri] == existing)
                .firstOrNull?.uri;
            if (existingUri != null) {
              final existDesc = entityDescs[existingUri] ?? '';
              if (existDesc.contains(normName)) return true;
              if (desc.contains(existing)) return true;
            }
          } else if (existing.length >= 4 && normWords.length >= 2) {
            final existingUri = dedupedEntities
                .where((e) => entityNameMap[e.uri] == existing)
                .firstOrNull?.uri;
            if (existingUri != null) {
              final existDesc = entityDescs[existingUri] ?? '';
              if (desc.contains(existing)) return true;
              if (existDesc.contains(normName)) return true;
            }
          }
          // Brand-abbreviation pattern: single-token name whose leading
          // portion matches the first word of a multi-word name after
          // stripping corporate suffixes (e.g. "SpaceX" starts with "Space",
          // first word of "Space Exploration" → 5/6 coverage → same entity).
          const corpSuffixes = [
            'inc', 'inc.', 'llc', 'ltd', 'corp', 'corp.', 'corporation',
            'company', 'co', 'co.', 'group', 'holdings', 'technologies',
            'technology', 'the',
          ];
          var sn = normName;
          var se = existing;
          for (final sfx in corpSuffixes) {
            sn = sn.replaceAll(RegExp('\\b${RegExp.escape(sfx)}\\b'), '').trim();
            se = se.replaceAll(RegExp('\\b${RegExp.escape(sfx)}\\b'), '').trim();
          }
          sn = sn.replaceAll(RegExp(r'[,.\s]+$'), '').trim();
          se = se.replaceAll(RegExp(r'[,.\s]+$'), '').trim();
          if (sn.isNotEmpty && se.isNotEmpty) {
            // Re-check after stripping (catches cases missed earlier).
            if (sn == se || sn.contains(se) || se.contains(sn)) return true;
            final snW = sn.split(' ').where((w) => w.length >= 3).toList();
            final seW = se.split(' ').where((w) => w.length >= 3).toList();
            final single = snW.length == 1 && seW.length > 1
                ? sn.replaceAll(' ', '')
                : seW.length == 1 && snW.length > 1
                    ? se.replaceAll(' ', '')
                    : null;
            final multiFirst = snW.length == 1 && seW.length > 1
                ? seW.first
                : seW.length == 1 && snW.length > 1
                    ? snW.first
                    : null;
            if (single != null && multiFirst != null &&
                multiFirst.length >= 4 &&
                single.startsWith(multiFirst) &&
                multiFirst.length >= (single.length * 0.7).ceil()) {
              return true;
            }
          }
          return false;
        });
      }
      if (!isDuplicate) {
        typeNames.add(normName);
        dedupedEntities.add(entry);
      }
    }

    // Second dedup pass: cross-reference via sameAs, URL, and description.
    // This catches cases where names differ completely (e.g. brand name vs
    // full legal name) but the entities are linked via sameAs or one entity's
    // name appears in the other's description.
    final crossRefDeduped = <_EntityEntry>[];
    for (final entry in dedupedEntities) {
      final entryUrl = entityUrls[entry.uri] ?? '';
      final entrySameAs = entitySameAs[entry.uri] ?? const {};
      final entryName = entityNameMap[entry.uri] ?? '';
      final entryDesc = entityDescs[entry.uri] ?? '';

      final isDup = crossRefDeduped.any((existing) {
        if (existing.type != entry.type) return false;
        final existingUrl = entityUrls[existing.uri] ?? '';
        final existingSameAs = entitySameAs[existing.uri] ?? const {};

        // Check if entry's URL is in existing's sameAs or vice versa.
        if (existingUrl.isNotEmpty && entrySameAs.contains(existingUrl)) {
          return true;
        }
        if (entryUrl.isNotEmpty && existingSameAs.contains(entryUrl)) {
          return true;
        }
        // Check if their sameAs sets overlap.
        if (existingSameAs.intersection(entrySameAs).isNotEmpty) return true;

        // Description cross-reference: one entity's name in the other's
        // description (e.g. "SpaceX" in desc of "Space Exploration
        // Technologies Corporation").
        final existingName = entityNameMap[existing.uri] ?? '';
        final existingDesc = entityDescs[existing.uri] ?? '';
        if (entryName.length >= 4 && existingDesc.contains(entryName)) {
          return true;
        }
        if (existingName.length >= 4 && entryDesc.contains(existingName)) {
          return true;
        }

        return false;
      });
      if (!isDup) crossRefDeduped.add(entry);
    }

    // Filter out platform/boilerplate entities that appear on every page of a
    // site (e.g. "Contributors to Wikimedia projects", "Wikimedia Foundation").
    final cleanedEntities = crossRefDeduped.where((entry) {
      final name = entityNameMap[entry.uri] ?? '';
      return !_isBoilerplateEntity(name, widget.url);
    }).toList();

    // Filter out articles that look like navigation categories, site-about
    // pages, or other non-article content.
    final siteDomain = _extractDomain(widget.url);
    final filteredArticles = loaded.where((a) {
      final title = (a.name ?? '').trim();
      final desc = (a.description ?? '').trim();
      // Must have a title.
      if (title.isEmpty) return false;
      // Title is a URL → failed extraction.
      if (title.startsWith('http://') || title.startsWith('https://')) {
        return false;
      }
      // Very short title with no description and no image → likely nav category.
      if (title.length < 40 && desc.isEmpty && a.image == null) return false;
      // Site-about page: title matches site/domain name and desc mentions
      // "website", "online", "platform" → this is the site description, not an
      // article.
      if (siteDomain.isNotEmpty) {
        final tLower = title.toLowerCase();
        final tCompact = tLower.replaceAll(' ', '');
        final dLower = desc.toLowerCase();
        final domLower = siteDomain.toLowerCase();
        final domBase = domLower.split('.').first; // e.g. "theverge"
        final titleMatchesSite = tLower == domLower ||
            tLower == domLower.replaceAll('.', ' ') ||
            tCompact == domBase || // "the verge" → "theverge" == "theverge"
            tLower.contains(domBase) ||
            domBase.contains(tCompact);
        if (titleMatchesSite &&
            (dLower.contains('website') ||
                dLower.contains('online') ||
                dLower.contains('platform') ||
                dLower.contains('founded in') ||
                dLower.contains('news site') ||
                dLower.contains('publication'))) {
          return false;
        }
      }
      return true;
    }).toList();

    dev.log(
      '[WebChannel] url=${widget.url} webPage=${webPage?.uri} '
      'articles=${filteredArticles.length} (raw ${loaded.length}) '
      'entities=${cleanedEntities.length} (raw ${entities.length})',
      name: 'WebChannelView',
    );

    if (mounted) {
      setState(() {
        _articles = filteredArticles;
        _entityEntries = cleanedEntities;
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

      // Filter out navigation-category articles (same as initial load).
      final filtered = newArticles.where((a) {
        final title = (a.name ?? '').trim();
        final desc = (a.description ?? '').trim();
        if (title.isEmpty) return false;
        if (title.startsWith('http://') || title.startsWith('https://')) {
          return false;
        }
        if (title.length < 40 && desc.isEmpty && a.image == null) return false;
        return true;
      }).toList();

      if (!mounted) return;
      setState(() {
        _articles = [..._articles, ...filtered];
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
        builder: (_) => WebChannelLoader(url: url),
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

  /// Short summary for the channel header showing per-type counts.
  String get _summaryText {
    final parts = <String>[];
    if (_articles.isNotEmpty) {
      parts.add('${_articles.length} article${_articles.length == 1 ? '' : 's'}');
    }
    // Count each entity type individually.
    final typeCounts = <String, int>{};
    for (final e in _entityEntries) {
      typeCounts[e.type] = (typeCounts[e.type] ?? 0) + 1;
    }
    for (final MapEntry(:key, :value) in typeCounts.entries) {
      final label = switch (key) {
        'Person' => value == 1 ? 'person' : 'people',
        'Place' => value == 1 ? 'place' : 'places',
        'Product' => value == 1 ? 'product' : 'products',
        'Organization' => value == 1 ? 'org' : 'orgs',
        _ => key.toLowerCase(),
      };
      parts.add('$value $label');
    }
    return parts.isEmpty ? 'No content' : parts.join(' · ');
  }

  /// Builds sliver sections for each non-article entity type.
  ///
  /// People are rendered as a horizontal scrollable strip for prominence;
  /// other types use the standard vertical card list.
  List<Widget> _buildEntitySections() {
    if (_entityEntries.isEmpty) return const [];

    // Group by type.
    final grouped = <String, List<_EntityEntry>>{};
    for (final entry in _entityEntries) {
      (grouped[entry.type] ??= []).add(entry);
    }

    // Sort sections by config order, then render.
    final sortedTypes = grouped.keys.toList()
      ..sort((a, b) {
        final oa = _sectionConfig[a]?.$3 ?? 99;
        final ob = _sectionConfig[b]?.$3 ?? 99;
        return oa.compareTo(ob);
      });

    final slivers = <Widget>[];
    for (final type in sortedTypes) {
      final entries = grouped[type]!;
      final config = _sectionConfig[type];
      final emoji = config?.$1 ?? '📎';
      final label = config?.$2 ?? type;

      slivers.add(SliverToBoxAdapter(
        child: _SectionHeader(emoji: emoji, label: label, count: entries.length),
      ));

      // People get a horizontal scrollable strip for prominence.
      if (type == 'Person') {
        slivers.add(SliverToBoxAdapter(
          child: SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                return _PersonChip(uri: entries[index].uri);
              },
            ),
          ),
        ));
      } else if (type == 'ImageObject') {
        // Image objects get a masonry/grid gallery view.
        final allUris = entries.map((e) => e.uri).toList();
        slivers.add(SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.0,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return _ImageEntityCard(
                  uri: entries[index].uri,
                  allUris: allUris,
                  index: index,
                );
              },
              childCount: entries.length,
            ),
          ),
        ));
      } else {
        slivers.add(SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final entry = entries[index];
              return SemanticEntityCard(
                entityUri: entry.uri,
                entityType: entry.type,
              );
            },
            childCount: entries.length,
          ),
        ));
      }
    }
    return slivers;
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
    final topPadding = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: context.kabukBackground,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // ── Channel header (replaces separate app bar + info section) ──
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.fromLTRB(8, topPadding + 8, 12, 12),
              decoration: BoxDecoration(
                color: context.kabukSurface,
                border: Border(
                  bottom: BorderSide(color: context.kabukDivider, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  // Back button.
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Favicon.
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: KabukTheme.blueAccent.withAlpha(38),
                    child: ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: 'https://$_domain/favicon.ico',
                        width: 22,
                        height: 22,
                        fit: BoxFit.contain,
                        placeholder: (_, _) => const Icon(
                          Icons.language_rounded,
                          size: 18,
                          color: KabukTheme.blueAccent,
                        ),
                        errorWidget: (_, _, _) => const Icon(
                          Icons.language_rounded,
                          size: 18,
                          color: KabukTheme.blueAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Domain + summary.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _domain,
                          style: TextStyle(
                            color: context.kabukTextPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _summaryText,
                          style: TextStyle(
                            color: context.kabukTextTertiary,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Copy URL button.
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'Copy URL',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('URL copied')),
                      );
                    },
                  ),
                  // Subscribe button.
                  _SubscribeButton(
                    isSubscribed: _isSubscribed,
                    onToggle: _toggleSubscription,
                  ),
                ],
              ),
            ),
          ),

          // ── Navigation links (categories/sections) ──
          if (_filteredNavLinks.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: KabukTheme.spacingMd,
                  ),
                  itemCount: _filteredNavLinks.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final link = _filteredNavLinks[index];
                    return ActionChip(
                      avatar: const Icon(Icons.link_rounded, size: 14),
                      label: Text(
                        link.title,
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: context.kabukSurface,
                      side: BorderSide(color: context.kabukDivider),
                      onPressed: () => _browseLink(link.url),
                    );
                  },
                ),
              ),
            ),

          SliverToBoxAdapter(
            child: Divider(color: context.kabukDivider, height: 1),
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
          else if (_articles.isEmpty && _entityEntries.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'No content found on this page',
                  style: TextStyle(color: context.kabukTextSecondary),
                ),
              ),
            )
          else ...[
            // ── Semantic entity sections (shown first for prominence) ──
            ..._buildEntitySections(),
            // ── Articles section ──
            if (_articles.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(
                  emoji: '📰',
                  label: 'Articles',
                  count: _articles.length,
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ArticleCard(
                        article: _articles[index],
                        articles: _articles,
                        index: index,
                      ),
                    );
                  },
                  childCount: _articles.length,
                ),
              ),
            ],
          ],

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
// Helpers and models
// =============================================================================

/// Holds a non-article entity URI and its Schema.org type for display.
class _EntityEntry {
  const _EntityEntry({required this.uri, required this.type});
  final String uri;
  final String type;
}

/// Entity types that have dedicated card widgets.
const _supportedEntityTypes = {
  'Person',
  'Product',
  'Place',
  'Organization',
  'ImageObject',
  'Article',
  'WebPage',
};

/// Section config: emoji prefix, display label, and sort order.
const _sectionConfig = <String, (String, String, int)>{
  'Article': ('📰', 'Articles', 0),
  'Person': ('👤', 'People', 1),
  'Product': ('🛍️', 'Products', 2),
  'Place': ('📍', 'Places', 3),
  'Organization': ('🏢', 'Organizations', 4),
  'ImageObject': ('🖼️', 'Gallery', 5),
  'WebPage': ('🔗', 'Pages', 6),
};

/// Extracts the Schema.org type name from a Kabuk entity URI.
///
/// URIs follow the pattern `kabuk:TypeName/uuid`.
String _entityTypeFromUri(String uri) {
  final parts = uri.split(':');
  if (parts.length < 2) return 'Article';
  final typePart = parts[1].split('/').first;
  return typePart;
}

// =============================================================================
// Section header widget
// =============================================================================

/// Displays a labeled section divider (e.g. "📰 Articles (3)").
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.emoji,
    required this.label,
    required this.count,
  });

  final String emoji;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: context.kabukTextPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: TextStyle(
              color: context.kabukTextTertiary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Person chip for horizontal strip
// =============================================================================

/// Compact circular chip showing a person's initials and name.
///
/// Used in the horizontal people strip at the top of a channel view.
/// Tapping expands to the full [PersonCard] in a bottom sheet.
class _PersonChip extends ConsumerWidget {
  const _PersonChip({required this.uri});

  final String uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPerson = ref.watch(personDataProvider(uri));

    return asyncPerson.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Color(0x20AB47BC),
              ),
              SizedBox(height: 6),
              SizedBox(height: 10, width: 48),
            ],
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (person) {
        if (person == null) return const SizedBox.shrink();
        final name = person.name ??
            person.givenName ??
            person.familyName ??
            'Unknown';
        final initials = _initials(name);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: GestureDetector(
            onTap: () => _showPersonSheet(context, uri),
            child: SizedBox(
              width: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: KabukTheme.purpleAccent.withAlpha(38),
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: KabukTheme.purpleAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    style: TextStyle(
                      color: context.kabukTextPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Shows the full PersonCard in a bottom sheet.
  static void _showPersonSheet(BuildContext context, String uri) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.kabukCardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        child: PersonCard(uri: uri),
      ),
    );
  }

  /// Extracts up to two initials from a name.
  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
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

class _ImageEntityCard extends ConsumerWidget {
  const _ImageEntityCard({
    required this.uri,
    required this.allUris,
    required this.index,
  });

  final String uri;
  final List<String> allUris;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // We fetch media data directly since we don't have a provider yet.
    // In a real app, we'd use a FutureProvider(family) or similar.
    final store = ref.watch(knowledgeStoreProvider);

    return FutureBuilder<MediaData?>(
      future: store.getMediaData(uri),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            decoration: BoxDecoration(
              color: context.kabukSurface.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
          );
        }
        final media = snapshot.data;
        if (media == null) return const SizedBox.shrink();

        final url = media.contentUrl ?? media.thumbnail;
        if (url == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _FullScreenImageView(
                  imageUris: allUris,
                  initialIndex: index,
                ),
              ),
            );
          },
          child: Hero(
            tag: uri,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: context.kabukSurface.withOpacity(0.5),
                ),
                errorWidget: (context, url, error) => Container(
                  color: context.kabukSurface.withOpacity(0.5),
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: context.kabukTextTertiary,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FullScreenImageView extends StatefulWidget {
  const _FullScreenImageView({
    required this.imageUris,
    required this.initialIndex,
  });

  final List<String> imageUris;
  final int initialIndex;

  @override
  State<_FullScreenImageView> createState() => _FullScreenImageViewState();
}

class _FullScreenImageViewState extends State<_FullScreenImageView> {
  late PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.imageUris.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              return _FullScreenImagePage(uri: widget.imageUris[index]);
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
              ),
            ),
          ),
          if (widget.imageUris.length > 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${widget.imageUris.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FullScreenImagePage extends ConsumerWidget {
  const _FullScreenImagePage({required this.uri});

  final String uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(knowledgeStoreProvider);

    return FutureBuilder<MediaData?>(
      future: store.getMediaData(uri),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        final media = snapshot.data;
        if (media == null) return const SizedBox.shrink();

        final url = media.contentUrl ?? media.thumbnail;
        if (url == null) return const SizedBox.shrink();

        return Center(
          child: Hero(
            tag: uri,
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (context, url, error) => const Icon(
                  Icons.broken_image_rounded,
                  color: Colors.white70,
                  size: 48,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// Link loader — navigates to a URL and shows it as a WebChannelView
// =============================================================================

/// Loads a URL through the reader mode pipeline and displays it.
class WebChannelLoader extends ConsumerStatefulWidget {
  const WebChannelLoader({required this.url, super.key});

  final String url;

  @override
  ConsumerState<WebChannelLoader> createState() => _WebChannelLoaderState();
}

class _WebChannelLoaderState extends ConsumerState<WebChannelLoader> {
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
    final topPadding = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: context.kabukBackground,
      body: Column(
        children: [
          // Compact header matching WebChannelView style.
          Container(
            padding: EdgeInsets.fromLTRB(8, topPadding + 8, 12, 12),
            decoration: BoxDecoration(
              color: context.kabukSurface,
              border: Border(
                bottom: BorderSide(color: context.kabukDivider, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    Uri.tryParse(widget.url)?.host ?? widget.url,
                    style: TextStyle(
                      fontSize: 14,
                      color: context.kabukTextSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator(
                      color: KabukTheme.blueAccent)
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 40,
                            color: context.kabukTextTertiary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _error ?? 'Failed to load',
                            style: TextStyle(
                              color: context.kabukTextSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () {
                              setState(() {
                                _isLoading = true;
                                _error = null;
                              });
                              _load();
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Retry'),
                            style: FilledButton.styleFrom(
                              backgroundColor: KabukTheme.blueAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
