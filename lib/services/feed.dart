/// Feed service — abstract interface for fetching content from external sources.
///
/// Defines [FeedService] which manages multiple [FeedSource] implementations
/// (RSS, Reddit, etc.) and provides a unified API for fetching, parsing,
/// and storing feed content in the knowledge store.
library;

import 'package:meta/meta.dart';

/// A single item from a content feed.
///
/// This is the transport type returned by [FeedSource.fetch].
/// It is converted into knowledge store triples by [FeedService].
@immutable
class FeedItem {
  /// Creates a [FeedItem].
  const FeedItem({
    required this.title,
    required this.url,
    this.description,
    this.author,
    this.imageUrl,
    this.datePublished,
    this.identifier,
    this.categories = const [],
    this.galleryImages = const [],
  });

  /// The headline or title of the item.
  final String title;

  /// The canonical URL of the item.
  final String url;

  /// A short description or summary.
  final String? description;

  /// The author name.
  final String? author;

  /// An image URL (thumbnail, preview, etc.).
  final String? imageUrl;

  /// When the item was published.
  final DateTime? datePublished;

  /// A unique identifier (GUID for RSS, post ID for Reddit, etc.).
  final String? identifier;

  /// Categories or tags from the source.
  final List<String> categories;

  /// Gallery image URLs (e.g. for Reddit gallery posts).
  ///
  /// Non-empty only when the post contains multiple images.
  /// The first element is the same as [imageUrl] when present.
  final List<String> galleryImages;
}

/// The type of feed source.
enum FeedSourceType {
  /// RSS 2.0 feed.
  rss,

  /// Atom feed.
  atom,

  /// Reddit subreddit (JSON API).
  reddit,

  /// Nostr relay feed (NIP-01 kind 1 text notes).
  nostr,

  /// 4chan board (public JSON API).
  fourchan,
}

/// Abstract interface for a content feed source.
///
/// Each implementation knows how to fetch and parse items from a
/// specific type of source (RSS, Reddit, etc.).
abstract interface class FeedSource {
  /// The type of this source.
  FeedSourceType get type;

  /// Fetches items from the given [url].
  ///
  /// Returns a list of [FeedItem]s parsed from the remote source.
  /// Throws on network or parse errors.
  Future<List<FeedItem>> fetch(String url);

  /// Validates that the given [url] is a valid source for this type.
  ///
  /// Returns `true` if the URL can be fetched and parsed by this source.
  Future<bool> validate(String url);
}

/// The feed service that manages multiple feed sources.
///
/// Coordinates fetching from different source types and provides
/// a unified API for the feed agent.
abstract interface class FeedService {
  /// Returns the [FeedSource] for the given [type].
  FeedSource getSource(FeedSourceType type);

  /// Fetches items from a URL, auto-detecting the source type if possible.
  ///
  /// If [type] is provided, uses that source directly.
  /// Otherwise, attempts to detect the type from the URL or content.
  ///
  /// Throws on network or parse errors.
  Future<List<FeedItem>> fetchItems(String url, {FeedSourceType? type});

  /// Fetches a paginated page of items, returning items and an optional cursor.
  ///
  /// Pass the returned nextCursor as [cursor] in subsequent calls to load
  /// more items. For non-paginated sources (RSS, Atom) the cursor is always
  /// `null`. Currently only Reddit sources support cursors.
  ///
  /// Throws on network or parse errors.
  Future<({List<FeedItem> items, String? nextCursor})> fetchItemsPage(
    String url, {
    FeedSourceType? type,
    String? cursor,
  });

  /// Validates a feed URL and returns the detected source type, or `null`.
  Future<FeedSourceType?> detectType(String url);
}
