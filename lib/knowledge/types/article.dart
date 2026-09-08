/// Schema.org Article type helpers for the Kabuk knowledge store.
///
/// Provides [ArticleData] for structured access to Article entities
/// (feed items from RSS, Reddit, etc.), plus [KnowledgeStoreArticleExtension]
/// convenience methods on [KnowledgeStore].
library;

import 'dart:convert';

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:kabuk/knowledge/types/nostr_social.dart';
import 'package:meta/meta.dart';

/// Default time-to-live for unread articles before they are pruned.
///
/// Raised from 48 hours to 14 days so users don't silently lose content they
/// simply haven't opened yet. Read articles extend to 7 days from view, and
/// bookmarked articles are never pruned.
const Duration kUnreadArticleTtl = Duration(days: 14);

/// Immutable representation of a Schema.org Article entity.
///
/// Represents a single item from an RSS feed, Reddit post, or similar
/// content source. All fields are extracted from the underlying RDF triples.
@immutable
class ArticleData {
  /// Creates an [ArticleData] with the given field values.
  const ArticleData({
    required this.uri,
    this.name,
    this.description,
    this.url,
    this.videoUrl,
    this.datePublished,
    this.author,
    this.image,
    this.feedSource,
    this.read = false,
    this.nostrEventId,
    this.nostrStats = const NostrSocialStats(),
    this.tags = const [],
    this.galleryImages = const [],
    this.expiresAt,
  });

  /// Constructs an [ArticleData] from a subject [uri] and its [triples].
  factory ArticleData.fromTriples(String uri, List<Triple> triples) {
    return ArticleData(
      uri: uri,
      name: triples
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue,
      description: triples
          .where((t) => t.predicate == NS.schemaDescription)
          .firstOrNull
          ?.objectValue,
      url: triples
          .where((t) => t.predicate == NS.schemaUrl)
          .firstOrNull
          ?.objectValue,
      videoUrl: triples
          .where((t) => t.predicate == NS.kabukVideoUrl)
          .firstOrNull
          ?.objectValue,
      datePublished: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaDatePublished)
            .firstOrNull
            ?.objectValue,
      ),
      author: triples
          .where((t) => t.predicate == NS.schemaAuthor)
          .firstOrNull
          ?.objectValue,
      image: triples
          .where((t) => t.predicate == NS.schemaImage)
          .firstOrNull
          ?.objectValue,
      feedSource: triples
          .where((t) => t.predicate == NS.kabukFeedSource)
          .firstOrNull
          ?.objectValue,
      read:
          triples
              .where((t) => t.predicate == NS.kabukRead)
              .firstOrNull
              ?.objectValue ==
          'true',
      nostrEventId: triples
          .where((t) => t.predicate == NS.kabukNostrEventId)
          .firstOrNull
          ?.objectValue,
      nostrStats: NostrSocialStats(
        reactionCount:
            int.tryParse(
              triples
                      .where((t) => t.predicate == NS.kabukNostrReactionCount)
                      .firstOrNull
                      ?.objectValue ??
                  '',
            ) ??
            0,
        replyCount:
            int.tryParse(
              triples
                      .where((t) => t.predicate == NS.kabukNostrReplyCount)
                      .firstOrNull
                      ?.objectValue ??
                  '',
            ) ??
            0,
        repostCount:
            int.tryParse(
              triples
                      .where((t) => t.predicate == NS.kabukNostrRepostCount)
                      .firstOrNull
                      ?.objectValue ??
                  '',
            ) ??
            0,
        userReacted:
            triples
                .where((t) => t.predicate == NS.kabukNostrUserReacted)
                .firstOrNull
                ?.objectValue ==
            'true',
        userReposted:
            triples
                .where((t) => t.predicate == NS.kabukNostrUserReposted)
                .firstOrNull
                ?.objectValue ==
            'true',
      ),
      tags: triples
          .where((t) => t.predicate == NS.kabukTag)
          .map((t) => t.objectValue)
          .toList(),
      galleryImages: _parseGalleryImages(
        triples
            .where((t) => t.predicate == NS.kabukGalleryImages)
            .firstOrNull
            ?.objectValue,
      ),
      expiresAt: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.kabukExpiresAt)
            .firstOrNull
            ?.objectValue,
      ),
    );
  }

  /// The entity URI (e.g. `kabuk:Article/<uuid>`).
  final String uri;

  /// The article headline (`schema:name`).
  final String? name;

  /// A short description or summary (`schema:description`).
  final String? description;

  /// The canonical URL of the article (`schema:url`).
  final String? url;

  /// Direct video URL for video posts (`kabuk:videoUrl`).
  ///
  /// For Reddit hosted videos this is the `v.redd.it` fallback URL.
  /// For YouTube links this is the YouTube URL.
  /// `null` for non-video posts.
  final String? videoUrl;

  /// When the article was published (`schema:datePublished`).
  final DateTime? datePublished;

  /// The author name (`schema:author`).
  final String? author;

  /// An image URL associated with the article (`schema:image`).
  final String? image;

  /// The URI of the feed subscription this article came from (`kabuk:feedSource`).
  final String? feedSource;

  /// Whether the user has read this article (`kabuk:read`).
  final bool read;

  /// The Nostr event ID if this article has been shared to Nostr.
  final String? nostrEventId;

  /// Cached social stats from Nostr (reactions, replies, reposts).
  final NostrSocialStats nostrStats;

  /// User-assigned tags (`kabuk:tag`).
  final List<String> tags;

  /// Gallery image URLs for multi-image posts (`kabuk:galleryImages`).
  ///
  /// Non-empty only when the source post had multiple images (e.g. Reddit
  /// gallery posts). The first element mirrors [image] when present.
  final List<String> galleryImages;

  /// When this article should be pruned from the local store (`kabuk:expiresAt`).
  ///
  /// - Unread articles expire 48 h after [datePublished].
  /// - After the user reads an article the expiry is extended to 7 days.
  /// - Bookmarked articles are excluded from pruning regardless of this value.
  final DateTime? expiresAt;

  static DateTime? _tryParseDateTime(String? value) =>
      value == null ? null : DateTime.tryParse(value);

  static List<String> _parseGalleryImages(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<String>();
    } on Object {
      return const [];
    }
  }
}

/// Immutable representation of a feed subscription.
///
/// Tracks the source URL, type (rss, reddit, atom), and metadata
/// for a content feed the user has subscribed to.
@immutable
class FeedSubscriptionData {
  /// Creates a [FeedSubscriptionData] with the given field values.
  const FeedSubscriptionData({
    required this.uri,
    this.name,
    this.feedUrl,
    this.feedType,
    this.category,
    this.lastFetched,
    this.refreshInterval = 30,
    this.tags = const [],
  });

  /// Constructs a [FeedSubscriptionData] from a subject [uri] and its [triples].
  factory FeedSubscriptionData.fromTriples(String uri, List<Triple> triples) {
    return FeedSubscriptionData(
      uri: uri,
      name: triples
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue,
      feedUrl: triples
          .where((t) => t.predicate == NS.kabukFeedUrl)
          .firstOrNull
          ?.objectValue,
      feedType: triples
          .where((t) => t.predicate == NS.kabukFeedType)
          .firstOrNull
          ?.objectValue,
      category: triples
          .where((t) => t.predicate == NS.kabukFeedCategory)
          .firstOrNull
          ?.objectValue,
      lastFetched: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.kabukLastFetched)
            .firstOrNull
            ?.objectValue,
      ),
      refreshInterval:
          int.tryParse(
            triples
                    .where((t) => t.predicate == NS.kabukRefreshInterval)
                    .firstOrNull
                    ?.objectValue ??
                '',
          ) ??
          30,
      tags: triples
          .where((t) => t.predicate == NS.kabukTag)
          .map((t) => t.objectValue)
          .toList(),
    );
  }

  /// The entity URI (e.g. `kabuk:FeedSubscription/<uuid>`).
  final String uri;

  /// The display name of the feed (`schema:name`).
  final String? name;

  /// The source URL of the feed (`kabuk:feedUrl`).
  final String? feedUrl;

  /// The type of feed source: `rss`, `atom`, `reddit` (`kabuk:feedType`).
  final String? feedType;

  /// A category or subreddit name (`kabuk:feedCategory`).
  final String? category;

  /// When this feed was last fetched (`kabuk:lastFetched`).
  final DateTime? lastFetched;

  /// Refresh interval in minutes (`kabuk:refreshInterval`).
  final int refreshInterval;

  /// User-assigned tags (`kabuk:tag`).
  final List<String> tags;

  static DateTime? _tryParseDateTime(String? value) =>
      value == null ? null : DateTime.tryParse(value);
}

/// Convenience methods for working with Article entities in the knowledge store.
extension KnowledgeStoreArticleExtension on KnowledgeStore {
  /// Creates a new Article entity and returns its URI.
  Future<String> createArticle({
    required String title,
    String? description,
    String? url,
    String? videoUrl,
    String? author,
    String? image,
    String? feedSource,
    DateTime? datePublished,
    List<String> tags = const [],
    List<String> galleryImages = const [],
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('Article');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.schemaArticle,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, title);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      if (url != null) {
        await ctx.set(uri, NS.schemaUrl, url);
      }
      if (author != null) {
        await ctx.set(uri, NS.schemaAuthor, author);
      }
      if (image != null) {
        await ctx.set(uri, NS.schemaImage, image);
      }
      if (videoUrl != null) {
        await ctx.set(uri, NS.kabukVideoUrl, videoUrl);
      }
      if (feedSource != null) {
        await ctx.set(
          uri,
          NS.kabukFeedSource,
          feedSource,
          objectType: ObjectType.uri,
        );
      }
      final pubDate = (datePublished ?? DateTime.now()).toIso8601String();
      await ctx.set(uri, NS.schemaDatePublished, pubDate);
      await ctx.set(
        uri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );
      await ctx.set(uri, NS.kabukRead, 'false');
      // Stamp expiry: unread articles expire 14 days after publication.
      final pub = datePublished ?? DateTime.now();
      final expiry = pub.add(kUnreadArticleTtl);
      await ctx.set(uri, NS.kabukExpiresAt, expiry.toIso8601String());
      for (final tag in tags) {
        await ctx.add(uri, NS.kabukTag, tag);
      }
      if (galleryImages.isNotEmpty) {
        await ctx.set(uri, NS.kabukGalleryImages, jsonEncode(galleryImages));
      }
      return uri;
    });
  }

  /// Updates the title and description of an existing article.
  ///
  /// Useful to repair cached articles that were stored with poor titles
  /// (e.g. bare hashtag names from Nostr mirror bots) after fetch-logic
  /// improvements.
  Future<void> updateArticleTitleAndDescription(
    String uri, {
    required String title,
    String? description,
  }) {
    return mutate((ctx) async {
      await ctx.set(uri, NS.schemaName, title);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
    });
  }

  /// Updates the image URL of an existing article.
  ///
  /// Used by og:image enrichment to backfill images for RSS articles
  /// that didn't include media tags in their feed.
  Future<void> updateArticleImage(String uri, String imageUrl) {
    return mutate((ctx) async {
      await ctx.set(uri, NS.schemaImage, imageUrl);
    });
  }

  /// Updates the gallery images list for an existing article.
  ///
  /// Used when lazy-loading article content discovers multiple images
  /// on the article page (e.g. photo galleries, house listings).
  Future<void> updateArticleGalleryImages(
    String uri,
    List<String> galleryImages,
  ) {
    return mutate((ctx) async {
      await ctx.set(uri, NS.kabukGalleryImages, jsonEncode(galleryImages));
    });
  }

  /// Updates the feed source of an existing article.
  ///
  /// Used when a user subscribes to a page after browsing it — the
  /// articles were created without a subscription, and now need to be
  /// associated with the new subscription URI.
  Future<void> updateArticleFeedSource(String uri, String feedSource) {
    return mutate((ctx) async {
      await ctx.set(uri, NS.kabukFeedSource, feedSource);
    });
  }

  /// Retrieves a single Article by [uri], or `null` if not found.
  Future<ArticleData?> getArticleData(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return ArticleData.fromTriples(uri, triples);
  }

  /// Lists Articles ordered by most recently published.
  ///
  /// [before] acts as a pagination cursor: only articles published strictly
  /// before the given timestamp are returned (combine with [limit] to page
  /// through the feed). [feedSources] OR-filters on `kabuk:feedSource`
  /// (applied post-hydration), [keyword] filters title/description, and
  /// [hideNsfw]/[mutedSources] apply the same rules as the Explore content
  /// filters.
  ///
  /// Sorting and pagination happen in Dart after hydration because the
  /// triple store cannot order/filter across predicates in a single-table
  /// query.
  Future<List<ArticleData>> listArticles({
    int limit = 50,
    String? feedSource,
    String? author,
    bool? unreadOnly,
    List<String> feedSources = const [],
    String? keyword,
    bool? hideNsfw,
    List<String> mutedSources = const [],
    DateTime? before,
  }) async {
    var q = query().where(NS.rdfType, equals: NS.schemaArticle);
    if (feedSource != null) {
      q = q.where(NS.kabukFeedSource, equals: feedSource);
    }
    if (author != null) {
      q = q.where(NS.schemaAuthor, equals: author);
    }

    final typeTriples = await q.execute();
    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    var articles = <ArticleData>[];
    for (final uri in uris) {
      final triples = allTriples[uri];
      if (triples == null || triples.isEmpty) continue;
      final article = ArticleData.fromTriples(uri, triples);
      if (unreadOnly == true && article.read) continue;
      // OR-filter on a set of feed sources.
      if (feedSources.isNotEmpty &&
          !feedSources.contains(article.feedSource)) {
        continue;
      }
      // Keyword filter (title/description).
      if (keyword != null && keyword.isNotEmpty) {
        final text =
            '${article.name ?? ''} ${article.description ?? ''}'
                .toLowerCase();
        if (!text.contains(keyword.toLowerCase())) continue;
      }
      // NSFW heuristic.
      if (hideNsfw == true) {
        final hasNsfwTag = article.tags.any(
          (t) => t.toLowerCase() == 'nsfw' || t.toLowerCase() == 'over18',
        );
        final titleNsfw = (article.name ?? '').toLowerCase().contains('nsfw');
        if (hasNsfwTag || titleNsfw) continue;
      }
      // Muted sources.
      if (mutedSources.isNotEmpty &&
          article.feedSource != null &&
          mutedSources.contains(article.feedSource)) {
        continue;
      }
      articles.add(article);
    }

    // Newest first.
    articles.sort((a, b) {
      final aDate = a.datePublished ?? DateTime(2000);
      final bDate = b.datePublished ?? DateTime(2000);
      return bDate.compareTo(aDate);
    });

    // Pagination cursor.
    if (before != null) {
      articles.removeWhere(
        (a) =>
            a.datePublished == null ||
            !a.datePublished!.isBefore(before),
      );
    }
    if (articles.length > limit) {
      articles = articles.sublist(0, limit);
    }
    return articles;
  }

  /// Marks an article as read and extends its expiry to 7 days from now.
  ///
  /// Also records [NS.kabukLastViewedAt] so that recently-viewed articles
  /// survive the prune sweep even if the user does not explicitly bookmark them.
  Future<void> markArticleRead(String uri) {
    return mutate((ctx) async {
      await ctx.set(uri, NS.kabukRead, 'true');
      final now = DateTime.now();
      await ctx.set(uri, NS.kabukLastViewedAt, now.toIso8601String());
      // Extend expiry: read articles kept for 7 days for offline reference.
      await ctx.set(
        uri,
        NS.kabukExpiresAt,
        now.add(const Duration(days: 7)).toIso8601String(),
      );
    });
  }

  /// Deletes all expired, unread, un-bookmarked articles from the store.
  ///
  /// Rules:
  /// - Articles whose `kabuk:expiresAt` is in the past are candidates.
  /// - Articles marked `kabuk:read = true` are skipped (extended expiry above).
  /// - Articles linked to a `kabuk:Bookmark` entity are never deleted.
  ///
  /// Call this on app startup and after every successful feed refresh to keep
  /// the knowledge store lean without losing content the user actually wants.
  Future<int> pruneStaleArticles() async {
    final now = DateTime.now();

    // Gather all article URIs.
    final typeTriples = await query()
        .where(NS.rdfType, equals: NS.schemaArticle)
        .execute();
    final allUris = typeTriples.map((t) => t.subject).toSet();

    // Determine which articles are saved as bookmarks.
    final bookmarkTriples = await query()
        .where(NS.rdfType, equals: NS.kabukBookmark)
        .execute();
    final bookmarkedUris = bookmarkTriples.map((t) => t.subject).toSet();

    final toDelete = <String>[];

    if (allUris.isNotEmpty) {
      final allTriples = await getEntities(allUris.toList());
      for (final uri in allUris) {
        if (bookmarkedUris.contains(uri)) continue; // never prune bookmarks
        final triples = allTriples[uri];
        if (triples == null || triples.isEmpty) continue;
        final article = ArticleData.fromTriples(uri, triples);
        if (article.read) continue; // read articles use their extended expiry
        final exp = article.expiresAt;
        if (exp != null && exp.isBefore(now)) {
          toDelete.add(uri);
        }
      }
    }

    if (toDelete.isEmpty) return 0;

    await mutate((ctx) async {
      for (final uri in toDelete) {
        await ctx.remove(subject: uri);
      }
    });
    return toDelete.length;
  }

  /// Creates a new feed subscription and returns its URI.
  Future<String> createFeedSubscription({
    required String name,
    required String feedUrl,
    required String feedType,
    String? category,
    int refreshInterval = 30,
    List<String> tags = const [],
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('FeedSubscription');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.kabukFeedSubscription,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      await ctx.set(uri, NS.kabukFeedUrl, feedUrl);
      await ctx.set(uri, NS.kabukFeedType, feedType);
      if (category != null) {
        await ctx.set(uri, NS.kabukFeedCategory, category);
      }
      await ctx.set(uri, NS.kabukRefreshInterval, refreshInterval.toString());
      await ctx.set(
        uri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );
      for (final tag in tags) {
        await ctx.add(uri, NS.kabukTag, tag);
      }
      return uri;
    });
  }

  /// Retrieves a single feed subscription by [uri], or `null` if not found.
  Future<FeedSubscriptionData?> getFeedSubscription(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return FeedSubscriptionData.fromTriples(uri, triples);
  }

  /// Lists all feed subscriptions.
  Future<List<FeedSubscriptionData>> listFeedSubscriptions({
    int limit = 50,
  }) async {
    final typeTriples = await query()
        .where(NS.rdfType, equals: NS.kabukFeedSubscription)
        .orderBy(NS.schemaDateCreated, descending: true)
        .limit(limit)
        .execute();

    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    return [
      for (final uri in uris)
        if (allTriples[uri] case final triples? when triples.isNotEmpty)
          FeedSubscriptionData.fromTriples(uri, triples),
    ];
  }

  /// Updates the last-fetched timestamp on a feed subscription.
  Future<void> updateFeedLastFetched(String feedUri) {
    return mutate((ctx) async {
      await ctx.set(
        feedUri,
        NS.kabukLastFetched,
        DateTime.now().toIso8601String(),
      );
    });
  }

  /// Deletes a feed subscription and all its articles.
  ///
  /// Uses a direct triple query to find article URIs by their
  /// `kabuk:feedSource` back-link, avoiding the overhead of
  /// hydrating full [ArticleData] objects for bulk deletion.
  Future<void> deleteFeedSubscription(String feedUri) async {
    // Query article URIs linked to this feed via kabuk:feedSource.
    final feedSourceTriples = await query()
        .where(NS.kabukFeedSource, equals: feedUri)
        .execute();
    final articleUris = feedSourceTriples.map((t) => t.subject).toSet();

    return mutate((ctx) async {
      // Remove all articles belonging to this feed.
      for (final articleUri in articleUris) {
        await ctx.remove(subject: articleUri);
      }
      // Remove the feed subscription itself.
      await ctx.remove(subject: feedUri);
    });
  }

  /// Updates a feed subscription's mutable properties.
  ///
  /// Only non-null parameters are updated; others are left unchanged.
  Future<void> updateFeedSubscription(
    String feedUri, {
    String? name,
    String? category,
    int? refreshInterval,
  }) {
    return mutate((ctx) async {
      if (name != null) {
        await ctx.set(feedUri, NS.schemaName, name);
      }
      if (category != null) {
        await ctx.set(feedUri, NS.kabukFeedCategory, category);
      }
      if (refreshInterval != null) {
        await ctx.set(
          feedUri,
          NS.kabukRefreshInterval,
          refreshInterval.toString(),
        );
      }
    });
  }

  /// Returns a map from `schema:url` → entity URI across the whole store.
  ///
  /// Used for deduplication during feed refresh and channel ingestion. This is
  /// O(all URLs) instead of hydrating full entities, so it scales far better
  /// than the old `listArticles(limit: 2000)` dedup window.
  Future<Map<String, String>> listArticleUrlIndex() async {
    final urlTriples = await query().predicate(NS.schemaUrl).execute();
    final index = <String, String>{};
    for (final t in urlTriples) {
      final url = t.objectValue;
      if (url.isNotEmpty && !index.containsKey(url)) {
        index[url] = t.subject;
      }
    }
    return index;
  }

  /// Re-tags articles from one `kabuk:feedSource` value to another.
  ///
  /// Used when a user follows a channel whose content was previously stored
  /// under a pseudo feedSource (e.g. `reddit:r/flutter`); the articles are
  /// relabeled to the real subscription URI so they appear under the chip.
  /// Returns the number of articles re-tagged.
  Future<int> retagArticles(String fromFeedSource, String toFeedSource) async {
    if (fromFeedSource == toFeedSource) return 0;
    final triples = await query()
        .where(NS.kabukFeedSource, equals: fromFeedSource)
        .execute();
    final uris = triples.map((t) => t.subject).toSet();
    if (uris.isEmpty) return 0;
    await mutate((ctx) async {
      for (final uri in uris) {
        await ctx.set(
          uri,
          NS.kabukFeedSource,
          toFeedSource,
          objectType: ObjectType.uri,
        );
      }
    });
    return uris.length;
  }
}

/// Convenience methods for persisting user preferences as `kabuk:Preference`
/// entities (one entity per key, with `kabuk:preferenceKey`/`kabuk:preferenceValue`).
extension KnowledgeStorePreferenceExtension on KnowledgeStore {
  /// Sets a preference [key] to the string [value], upserting the entity.
  Future<void> setPreference(String key, String value) async {
    final existing = await query()
        .where(NS.kabukPreferenceKey, equals: key)
        .execute();
    final uri = existing.firstOrNull?.subject;
    await mutate((ctx) async {
      final target = uri ?? ctx.create('Preference');
      await ctx.set(
        target,
        NS.rdfType,
        NS.kabukPreference,
        objectType: ObjectType.uri,
      );
      await ctx.set(target, NS.kabukPreferenceKey, key);
      await ctx.set(target, NS.kabukPreferenceValue, value);
    });
  }

  /// Reads a preference [key], returning `null` when unset.
  Future<String?> getPreference(String key) async {
    final triples = await query()
        .where(NS.kabukPreferenceKey, equals: key)
        .execute();
    if (triples.isEmpty) return null;
    final uri = triples.first.subject;
    final entity = await getEntity(uri);
    return entity
        .where((t) => t.predicate == NS.kabukPreferenceValue)
        .firstOrNull
        ?.objectValue;
  }

  /// Deletes a preference [key] if present.
  Future<void> deletePreference(String key) async {
    final triples = await query()
        .where(NS.kabukPreferenceKey, equals: key)
        .execute();
    final uri = triples.firstOrNull?.subject;
    if (uri == null) return;
    await mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }
}
