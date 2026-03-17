/// Nostr feed source — implements [FeedSource] for Nostr hashtag feeds.
///
/// Allows subscribing to Nostr hashtags and topics as feed sources,
/// fitting into the same subscription model as RSS and Reddit.
/// Nostr notes are converted into [FeedItem]s for unified display.
library;

import 'dart:async';

import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/nostr.dart';

/// A [FeedSource] that fetches Nostr text notes by hashtag.
///
/// The [url] parameter is interpreted as a comma-separated list of
/// hashtags (without the `#` prefix). For example: `flutter,dart,mobile`.
///
/// Feed URLs for Nostr sources use the format:
/// - `nostr:t/flutter` — single hashtag
/// - `nostr:t/flutter,dart` — multiple hashtags
/// - `nostr:feed/global` — global feed
/// - `nostr:feed/following` — following feed
/// - `nostr:search/query text` — NIP-50 search
class NostrFeedSource implements FeedSource {
  /// Creates a [NostrFeedSource] backed by the given [NostrService].
  NostrFeedSource({required this.nostr});

  /// The Nostr service for relay communication.
  final NostrService nostr;

  @override
  FeedSourceType get type => FeedSourceType.nostr;

  @override
  Future<List<FeedItem>> fetch(String url) async {
    final parsed = _parseNostrFeedUrl(url);
    final events = <NostrEvent>[];
    final completer = Completer<List<FeedItem>>();

    Timer? timeout;
    StreamSubscription<NostrEvent>? subscription;

    timeout = Timer(const Duration(seconds: 8), () {
      subscription?.cancel();
      if (!completer.isCompleted) {
        completer.complete(_eventsToFeedItems(events));
      }
    });

    final stream = switch (parsed) {
      _NostrHashtagFeed(:final hashtags) => nostr.searchByHashtag(
        hashtags,
        limit: 50,
      ),
      _NostrGlobalFeed() => nostr.fetchGlobalFeed(limit: 50),
      _NostrFollowingFeed(:final pubkeys) => nostr.fetchFollowingFeed(
        pubkeys,
        limit: 50,
      ),
      _NostrSearchFeed(:final query) => nostr.searchContent(query, limit: 50),
    };

    subscription = stream.listen(
      (event) {
        if (event.kind == NostrKind.textNote) {
          events.add(event);
        }
      },
      onDone: () {
        timeout?.cancel();
        if (!completer.isCompleted) {
          completer.complete(_eventsToFeedItems(events));
        }
      },
      onError: (_) {
        // Ignore individual errors.
      },
    );

    return completer.future;
  }

  @override
  Future<bool> validate(String url) async {
    try {
      _parseNostrFeedUrl(url);
      return true;
    } on Object {
      return false;
    }
  }

  /// Converts Nostr events to [FeedItem]s for the unified feed.
  List<FeedItem> _eventsToFeedItems(List<NostrEvent> events) {
    // Deduplicate by event ID.
    final seen = <String>{};
    final unique = <NostrEvent>[];
    for (final event in events) {
      if (seen.add(event.id)) unique.add(event);
    }

    // Sort newest first.
    unique.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return unique.map((event) {
      // Extract hashtags from t tags.
      final categories = <String>[];
      for (final tag in event.tags) {
        if (tag.isNotEmpty && tag[0] == 't' && tag.length >= 2) {
          categories.add(tag[1]);
        }
      }

      // Extract first image URL from content.
      final imageUrl = _extractImageUrl(event.content);

      // Strip URLs before deriving title and description.
      final content = event.content.trim();
      final stripped = content
          .replaceAll(RegExp(r'https?://\S+'), '')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();

      final titleEnd = stripped.indexOf('\n');
      final title = stripped.isEmpty
          ? 'Nostr post'
          : titleEnd > 0 && titleEnd < 120
              ? stripped.substring(0, titleEnd)
              : stripped.length > 120
                  ? '${stripped.substring(0, 120)}…'
                  : stripped;

      return FeedItem(
        title: title,
        url: 'nostr:${event.id}',
        description: stripped.isEmpty || stripped == title
            ? null
            : stripped.length > 5000
                ? '${stripped.substring(0, 5000)}…'
                : stripped,
        author: _resolveAuthorName(event),
        imageUrl: imageUrl,
        datePublished: DateTime.fromMillisecondsSinceEpoch(
          event.createdAt * 1000,
        ),
        identifier: event.id,
        categories: categories,
      );
    }).toList();
  }

  /// Tries to extract a display name from the event.
  String? _resolveAuthorName(NostrEvent event) {
    return '@${event.pubkey.substring(0, 8)}';
  }

  /// Extracts the first image URL from note content.
  static String? _extractImageUrl(String content) {
    final match = RegExp(
      r'https?://\S+\.(?:jpg|jpeg|png|gif|webp|svg)',
      caseSensitive: false,
    ).firstMatch(content);
    return match?.group(0);
  }
}

/// Parsed Nostr feed URL.
sealed class _NostrFeedType {}

final class _NostrHashtagFeed extends _NostrFeedType {
  _NostrHashtagFeed(this.hashtags);
  final List<String> hashtags;
}

final class _NostrGlobalFeed extends _NostrFeedType {}

final class _NostrFollowingFeed extends _NostrFeedType {
  _NostrFollowingFeed(this.pubkeys);
  final List<String> pubkeys;
}

final class _NostrSearchFeed extends _NostrFeedType {
  _NostrSearchFeed(this.query);
  final String query;
}

/// Parses a Nostr feed URL into its component parts.
///
/// Supported formats:
/// - `nostr:t/flutter` or `nostr:t/flutter,dart`
/// - `nostr:feed/global`
/// - `nostr:feed/following`
/// - `nostr:search/query text`
/// - `#flutter` (shorthand for `nostr:t/flutter`)
_NostrFeedType _parseNostrFeedUrl(String url) {
  final trimmed = url.trim();

  // Shorthand: bare hashtag(s).
  if (trimmed.startsWith('#')) {
    final hashtags = trimmed
        .split(RegExp(r'[,\s]+'))
        .map((h) => h.replaceFirst('#', '').toLowerCase().trim())
        .where((h) => h.isNotEmpty)
        .toList();
    if (hashtags.isEmpty) throw FormatException('Empty hashtag: $url');
    return _NostrHashtagFeed(hashtags);
  }

  // nostr: prefixed URLs.
  if (trimmed.startsWith('nostr:t/')) {
    final hashtagStr = trimmed.substring('nostr:t/'.length);
    final hashtags = hashtagStr
        .split(',')
        .map((h) => h.toLowerCase().trim())
        .where((h) => h.isNotEmpty)
        .toList();
    if (hashtags.isEmpty) throw FormatException('Empty hashtag: $url');
    return _NostrHashtagFeed(hashtags);
  }

  if (trimmed == 'nostr:feed/global') {
    return _NostrGlobalFeed();
  }

  if (trimmed.startsWith('nostr:feed/following')) {
    // Following feed — pubkeys will be resolved at fetch time via the service.
    return _NostrFollowingFeed([]);
  }

  if (trimmed.startsWith('nostr:search/')) {
    final query = trimmed.substring('nostr:search/'.length).trim();
    if (query.isEmpty) throw FormatException('Empty search query: $url');
    return _NostrSearchFeed(query);
  }

  throw FormatException('Unrecognized Nostr feed URL: $url');
}
