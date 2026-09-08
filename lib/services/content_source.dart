/// Unified content source abstraction.
///
/// Every content origin — RSS/Reddit/4chan/Nostr/Usenet feed sources, content
/// plugins (YouTube, Wikipedia, …), and parsed web pages — is exposed through
/// a single [ContentSource] interface that supports cursor pagination. This is
/// the shared contract used by the feed refresh engine and the channel UI, so
/// "a feed" and "a channel" are the same thing: a source of [FeedItem]s.
library;

import 'dart:async';

import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/plugins/plugin.dart';
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/web_extractor.dart';

/// A paged fetch request for a [ContentSource].
class ContentQuery {
  /// Creates a [ContentQuery].
  const ContentQuery({
    required this.url,
    this.page = 0,
    this.cursor,
    this.perPage = 50,
    this.sort,
  });

  /// The source URL / identifier being fetched.
  final String url;

  /// Zero-based page number (for sources without cursors).
  final int page;

  /// Opaque pagination cursor returned by a previous `nextCursor`.
  final String? cursor;

  /// Items per page.
  final int perPage;

  /// Optional server-side sort hint (`new`, `hot`, `top` for Reddit).
  final String? sort;
}

/// A single page of results from a [ContentSource].
class ContentPage {
  /// Creates a [ContentPage].
  const ContentPage({required this.items, this.nextCursor});

  /// The items in this page.
  final List<FeedItem> items;

  /// Opaque cursor for the next page, or `null` when there is none.
  final String? nextCursor;
}

/// A paginated source of [FeedItem]s.
abstract interface class ContentSource {
  /// Stable identifier for this source (e.g. `rss`, `reddit`,
  /// `plugin:youtube`, `web`).
  String get id;

  /// Fetches one page of content.
  Future<ContentPage> fetchPage(ContentQuery query);

  /// Validates that [url] is a valid input for this source.
  Future<bool> validate(String url);
}

/// Re-parses a web page (subscription) into article links without an LLM.
///
/// Used to refresh `web:` subscriptions periodically. Article bodies are not
/// re-extracted (that stays one-time via [ReaderModeService]); this cheaply
/// discovers new article links on index/listing pages so followed websites
/// pick up fresh content.
class WebContentSource implements ContentSource {
  /// Creates a [WebContentSource].
  WebContentSource({this.fetchTimeout = const Duration(seconds: 15)});

  /// Per-fetch timeout to bound the refresh pass.
  final Duration fetchTimeout;

  @override
  String get id => 'web';

  @override
  Future<ContentPage> fetchPage(ContentQuery query) async {
    final extraction = await WebExtractor.fromUrl(query.url).timeout(
      fetchTimeout,
      onTimeout: () =>
          throw TimeoutException('Timed out parsing ${query.url}'),
    );
    final items = extraction.articleLinks
        .where((l) => l.url.startsWith('http') && l.title.trim().isNotEmpty)
        .map(
          (l) => FeedItem(
            title: l.title.trim(),
            url: l.url,
            description: l.description,
            imageUrl: l.image,
          ),
        )
        .toList();
    return ContentPage(items: items, nextCursor: null);
  }

  @override
  Future<bool> validate(String url) => Future.value(url.startsWith('http'));
}

/// Adapts a [FeedService] source type into a [ContentSource].
///
/// Uses [FeedService.fetchItemsPage] so cursor-aware sources (Reddit) keep
/// their server-side pagination while the rest fall back to a single page.
class FeedSourceContentSource implements ContentSource {
  /// Creates a [FeedSourceContentSource] for [type].
  FeedSourceContentSource({required FeedService feedService, required this.type})
      : _feedService = feedService;

  final FeedService _feedService;

  /// The underlying feed source type.
  final FeedSourceType type;

  @override
  String get id => type.name;

  @override
  Future<ContentPage> fetchPage(ContentQuery query) async {
    final result = await _feedService.fetchItemsPage(
      query.url,
      type: type,
      cursor: query.cursor,
    );
    return ContentPage(items: result.items, nextCursor: result.nextCursor);
  }

  @override
  Future<bool> validate(String url) => _feedService.getSource(type).validate(url);
}

/// Adapts a [ContentPlugin] (channel or search capability) into a [ContentSource].
///
/// Converts plugin [ContentItem]s into the shared [FeedItem] model so plugin
/// channels (YouTube, Wikipedia, SoundCloud, …) behave exactly like feed
/// subscriptions.
class PluginContentSource implements ContentSource {
  PluginContentSource._({
    required this.plugin,
    this.entityId,
    this.searchQuery,
  });

  /// A channel-backed plugin source fetching [entityId]'s content.
  factory PluginContentSource.channel(ContentPlugin plugin, String entityId) =>
      PluginContentSource._(plugin: plugin, entityId: entityId);

  /// A search-backed plugin source for [query].
  factory PluginContentSource.search(ContentPlugin plugin, String query) =>
      PluginContentSource._(plugin: plugin, searchQuery: query);

  /// The wrapped plugin.
  final ContentPlugin plugin;

  /// Channel entity identifier (channel mode), or `null` for search mode.
  final String? entityId;

  /// Search query (search mode), or `null` for channel mode.
  final String? searchQuery;

  @override
  String get id => 'plugin:${plugin.id}';

  @override
  Future<ContentPage> fetchPage(ContentQuery query) async {
    final List<ContentItem> items;
    if (entityId != null) {
      if (!plugin.hasCapability(ContentCapability.channel)) {
        return const ContentPage(items: []);
      }
      items = await plugin.fetchChannel(
        entityId!,
        page: query.page,
        perPage: query.perPage,
      );
    } else {
      if (!plugin.hasCapability(ContentCapability.search)) {
        return const ContentPage(items: []);
      }
      items = await plugin.search(
        searchQuery ?? query.url,
        page: query.page,
        perPage: query.perPage,
      );
    }
    return ContentPage(
      items: items.map(contentItemToFeedItem).toList(),
      nextCursor: items.length >= query.perPage
          ? '${query.page + 1}'
          : null,
    );
  }

  @override
  Future<bool> validate(String url) => Future.value(true);
}

/// Converts a plugin [ContentItem] into the shared [FeedItem] model.
FeedItem contentItemToFeedItem(ContentItem item) {
  String? videoUrl;
  String? imageUrl = item.thumbnailUrl;
  switch (item.metadata) {
    case VideoMeta(:final hlsUrl, :final streamUrl):
      videoUrl = hlsUrl ?? streamUrl;
    case AudioMeta(:final streamUrl, :final artworkUrl):
      videoUrl = streamUrl;
      imageUrl ??= artworkUrl;
    case ImageMeta(:final galleryUrls):
      imageUrl ??= galleryUrls.isNotEmpty ? galleryUrls.first : null;
    default:
      break;
  }

  return FeedItem(
    title: item.title,
    url: item.url ?? 'plugin:${item.sourcePluginId}/${item.externalId}',
    description: item.description,
    author: item.author?.name,
    imageUrl: imageUrl,
    videoUrl: videoUrl,
    datePublished: item.publishedAt,
    identifier: item.externalId,
    categories: item.tags,
  );
}