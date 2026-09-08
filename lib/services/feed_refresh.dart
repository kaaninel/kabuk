/// Feed refresh engine — the single place that fetches new content.
///
/// Consolidates the feed-refresh logic that previously lived inside the
/// Explore widget into one engine so:
/// - every caller (Explore view, feed sources page, chip fetch-on-select,
///   background refresh) goes through the same code path,
/// - failures are surfaced per-source instead of swallowed,
/// - each network fetch is timeout-bounded so one hung host can't stall the
///   whole pass.
library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/services/content_source.dart';
import 'package:kabuk/services/feed.dart';
import 'package:meta/meta.dart';

/// Result of fetching a single feed subscription.
///
/// Replaces the old silent `[]`-on-error behaviour: every feed reports either
/// a new-article count or an [error] so the UI can surface failures instead of
/// pretending "nothing new".
@immutable
class FeedRefreshResult {
  /// Creates a [FeedRefreshResult].
  const FeedRefreshResult({
    required this.uri,
    required this.name,
    this.newCount = 0,
    this.error,
  });

  /// The subscription URI.
  final String uri;

  /// Human-readable feed name.
  final String name;

  /// Number of new articles persisted.
  final int newCount;

  /// Non-null when this feed's fetch failed.
  final Object? error;

  /// Whether the fetch succeeded.
  bool get ok => error == null;
}

/// Aggregate outcome of a full feed refresh pass.
class FeedRefreshSummary {
  /// Creates a [FeedRefreshSummary].
  FeedRefreshSummary({
    this.results = const [],
    this.nostrNewCount = 0,
    this.nostrError,
  });

  /// Per-subscription results.
  final List<FeedRefreshResult> results;

  /// New Nostr notes ingested.
  int nostrNewCount;

  /// Nostr fetch error, if any.
  Object? nostrError;

  /// Total new items across all feeds.
  int get totalNew =>
      results.fold(nostrNewCount, (sum, r) => sum + r.newCount);

  /// Subscriptions that failed to fetch.
  List<FeedRefreshResult> get failures =>
      results.where((r) => r.error != null).toList();

  /// Whether any fetch failed.
  bool get hasFailures => failures.isNotEmpty || nostrError != null;
}

/// The engine that fetches new articles for all (or one) feed subscriptions.
///
/// Pure service logic — no widgets, no Riverpod. Callers wire in the store,
/// feed service, and (optionally) callbacks for the current Reddit sort and
/// the Nostr global-feed pass.
class FeedRefreshEngine {
  /// Creates a [FeedRefreshEngine].
  FeedRefreshEngine({
    required this.store,
    required this.feedService,
    this.redditSort,
    this.refreshNostr,
  });

  /// Knowledge store for reading subscriptions and persisting articles.
  final KnowledgeStore store;

  /// Feed service for fetching items from the sources.
  final FeedService feedService;

  /// Returns the current Reddit server-side sort (`new`/`hot`/`top`).
  final String Function()? redditSort;

  /// Optional callback to refresh the Nostr global feed after the feed pass.
  final Future<int> Function()? refreshNostr;

  /// Default timeout applied to each single-feed network fetch.
  static const Duration _fetchTimeout = Duration(seconds: 5);

  /// Fetches new articles for all subscribed feeds (optionally just [onlyUri]).
  ///
  /// Respects each feed's [FeedSubscriptionData.refreshInterval] unless
  /// [force] is true. `web` subscriptions (one-time AI-parsed pages) and
  /// subscriptions without a URL are skipped.
  Future<FeedRefreshSummary> refreshAll({
    bool force = false,
    String? onlyUri,
  }) async {
    final subs = await store.listFeedSubscriptions();
    if (subs.isEmpty) return FeedRefreshSummary();

    final sort = redditSort?.call() ?? 'hot';

    final futures = <Future<FeedRefreshResult>>[];
    for (final sub in subs) {
      if (sub.feedUrl == null) continue;
      if (onlyUri != null && sub.uri != onlyUri) continue;
      futures.add(_fetchFeed(sub, redditSort: sort, force: force));
    }

    final results = await Future.wait(futures);
    return FeedRefreshSummary(results: results);
  }

  /// Fetches one feed subscription and returns the outcome.
  ///
  /// Skips feeds fetched more recently than their configured interval (when
  /// [force] is false). Failures are captured in the returned
  /// [FeedRefreshResult.error] rather than silently dropped.
  Future<FeedRefreshResult> _fetchFeed(
    FeedSubscriptionData sub, {
    String redditSort = 'hot',
    bool force = false,
  }) async {
    final name = sub.name ?? sub.feedUrl ?? 'feed';

    if (!force) {
      final last = sub.lastFetched;
      if (last != null) {
        final age = DateTime.now().difference(last);
        if (age < Duration(minutes: sub.refreshInterval)) {
          return FeedRefreshResult(uri: sub.uri, name: name);
        }
      }
    }

    try {
      final List<FeedItem> items;
      if (sub.feedType == 'web') {
        // Web subscriptions are re-parsed (cheap link discovery, no LLM)
        // rather than skipped — previously they never refreshed at all.
        final web = WebContentSource();
        final page = await web
            .fetchPage(ContentQuery(url: sub.feedUrl!))
            .timeout(_fetchTimeout);
        items = page.items;
      } else {
        final sourceType = FeedSourceType.values.firstWhere(
          (t) => t.name == sub.feedType,
          orElse: () => FeedSourceType.rss,
        );

        // For Reddit sources, inject the server-side sort into the URL.
        final fetchUrl =
            sourceType == FeedSourceType.reddit && sub.feedUrl != null
                ? buildRedditSortUrl(sub.feedUrl!, redditSort)
                : sub.feedUrl!;

        items = await feedService
            .fetchItems(fetchUrl, type: sourceType)
            .timeout(_fetchTimeout);
      }

      final newCount = await _persistItems(sub, items);
      await store.updateFeedLastFetched(sub.uri);
      return FeedRefreshResult(
        uri: sub.uri,
        name: name,
        newCount: newCount,
      );
    } on Object catch (e) {
      dev.log(
        'Feed refresh failed for ${sub.uri}: $e',
        name: 'FeedRefresh',
        error: e,
      );
      return FeedRefreshResult(uri: sub.uri, name: name, error: e);
    }
  }

  /// Persists new [items] for [sub], deduplicating across the whole store by
  /// URL. Returns the number of new articles stored.
  Future<int> _persistItems(FeedSubscriptionData sub, List<FeedItem> items) async {
    final existingByUrl = await store.listArticleUrlIndex();
    var newCount = 0;
    for (final item in items) {
      final cachedSubject = existingByUrl[item.url];
      if (cachedSubject != null) {
        // For Nostr items, patch stale titles (e.g. bare hashtag from mirror bots).
        final isNostr = item.url.startsWith('nostr:');
        if (isNostr) {
          final cached = await store.getArticleData(cachedSubject);
          if (cached != null &&
              cached.name != item.title &&
              item.title.isNotEmpty) {
            await store.updateArticleTitleAndDescription(
              cached.uri,
              title: item.title,
              description: item.description,
            );
          }
        }
        continue;
      }
      await store.createArticle(
        title: item.title,
        description: item.description,
        url: item.url,
        videoUrl: item.videoUrl,
        author: item.author,
        image: item.imageUrl,
        feedSource: sub.uri,
        datePublished: item.datePublished,
        tags: item.categories,
        galleryImages: item.galleryImages,
      );
      existingByUrl[item.url] = sub.uri;
      newCount++;
    }
    return newCount;
  }

  /// Runs the feed pass and then the Nostr global pass, returning a summary.
  ///
  /// Nostr runs after the feed pass (never in parallel) so the feed renders
  /// without waiting on relay streams.
  Future<FeedRefreshSummary> refreshAllWithNostr({
    bool force = false,
    String? onlyUri,
  }) async {
    final summary = await refreshAll(force: force, onlyUri: onlyUri);
    final nostr = refreshNostr;
    if (nostr != null) {
      try {
        summary.nostrNewCount = await nostr();
      } on Object catch (e) {
        summary.nostrError = e;
      }
    }
    return summary;
  }
}

/// Builds a Reddit JSON URL with the specified sort endpoint.
///
/// Replaces any existing sort path (e.g. `/hot.json`) with [sort],
/// so `r/flutter` with sort `'new'` becomes
/// `https://www.reddit.com/r/flutter/new.json?limit=50&raw_json=1`.
String buildRedditSortUrl(String baseUrl, String sort) {
  // Strip .json suffix and any previous sort path component.
  var url = baseUrl
      .replaceAll(RegExp(r'/\w+\.json(\?.*)?$'), '') // remove /XXX.json[?...]
      .replaceAll(RegExp(r'\?.*$'), '') // remove stray query strings
      .trimRight();
  if (url.endsWith('/')) url = url.substring(0, url.length - 1);
  return '$url/$sort.json?limit=50&raw_json=1';
}