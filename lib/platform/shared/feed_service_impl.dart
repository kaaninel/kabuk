/// Shared [FeedService] implementation.
///
/// Coordinates multiple [FeedSource] implementations and provides
/// auto-detection of feed types from URLs.
library;

import 'package:kabuk/platform/shared/fourchan_source.dart';
import 'package:kabuk/platform/shared/nostr_feed_source.dart';
import 'package:kabuk/platform/shared/reddit_source.dart';
import 'package:kabuk/platform/shared/rss_source.dart';
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/mesh.dart';
import 'package:kabuk/services/nostr.dart';

/// Cross-platform [FeedService] backed by RSS, Reddit, and Nostr sources.
class SharedFeedService implements FeedService {
  /// Creates a [SharedFeedService] with the given [mesh] service
  /// and optional [nostr] service for Nostr feed support.
  SharedFeedService({required MeshService mesh, NostrService? nostr})
    : _sources = {
        FeedSourceType.rss: RssFeedSource(mesh: mesh),
        FeedSourceType.atom: RssFeedSource(mesh: mesh), // Atom uses same parser
        FeedSourceType.reddit: RedditFeedSource(mesh: mesh),
        FeedSourceType.fourchan: FourchanFeedSource(mesh: mesh),
        if (nostr != null) FeedSourceType.nostr: NostrFeedSource(nostr: nostr),
      };

  final Map<FeedSourceType, FeedSource> _sources;

  @override
  FeedSource getSource(FeedSourceType type) => _sources[type]!;

  @override
  Future<List<FeedItem>> fetchItems(String url, {FeedSourceType? type}) async {
    final sourceType =
        type ?? await detectType(url).timeout(const Duration(seconds: 10), onTimeout: () => null);
    if (sourceType == null) {
      throw const FeedDetectionException(
        'Could not detect feed type. Please specify the type explicitly.',
      );
    }
    return _sources[sourceType]!.fetch(url);
  }

  @override
  Future<({List<FeedItem> items, String? nextCursor})> fetchItemsPage(
    String url, {
    FeedSourceType? type,
    String? cursor,
  }) async {
    final sourceType = type ?? await detectType(url);
    if (sourceType == null) {
      throw const FeedDetectionException(
        'Could not detect feed type. Please specify the type explicitly.',
      );
    }
    final source = _sources[sourceType];
    if (source is RedditFeedSource) {
      return source.fetchPage(url, afterCursor: cursor);
    }
    // Non-Reddit sources don't support cursors; fetch all items.
    final items = await source!.fetch(url);
    return (items: items, nextCursor: null);
  }

  @override
  Future<FeedSourceType?> detectType(String url) async {
    final lower = url.toLowerCase().trim();

    // Nostr URL patterns.
    if (lower.startsWith('nostr:') ||
        lower.startsWith('#') ||
        lower.contains('nostr')) {
      if (_sources.containsKey(FeedSourceType.nostr)) {
        return FeedSourceType.nostr;
      }
    }

    // Reddit URL patterns.
    if (lower.contains('reddit.com') ||
        lower.startsWith('r/') ||
        lower.startsWith('/r/')) {
      return FeedSourceType.reddit;
    }

    // 4chan URL patterns.
    if (lower.startsWith('4chan://') ||
        lower.startsWith('4chan:') ||
        lower.contains('boards.4chan.org') ||
        lower.contains('boards.4channel.org')) {
      return FeedSourceType.fourchan;
    }

    // Common RSS/Atom file extensions.
    if (lower.endsWith('.rss') ||
        lower.endsWith('.xml') ||
        lower.endsWith('.atom') ||
        lower.contains('/feed') ||
        lower.contains('/rss')) {
      return FeedSourceType.rss;
    }

    // Try validating as RSS/Atom first (more common).
    final rssSource = _sources[FeedSourceType.rss]!;
    if (await rssSource.validate(url)) {
      return FeedSourceType.rss;
    }

    // Then try Reddit.
    final redditSource = _sources[FeedSourceType.reddit]!;
    if (await redditSource.validate(url)) {
      return FeedSourceType.reddit;
    }

    return null;
  }
}

/// Exception thrown when the feed type cannot be auto-detected.
class FeedDetectionException implements Exception {
  /// Creates a [FeedDetectionException] with a [message].
  const FeedDetectionException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'FeedDetectionException: $message';
}
