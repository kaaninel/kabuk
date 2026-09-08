import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/services/channels.dart';
import 'package:kabuk/services/channels/feed_channel_servers.dart';
import 'package:kabuk/services/content_source.dart';
import 'package:kabuk/services/feed.dart';

void main() {
  group('RedditChannelServer', () {
    test('reddit_list builds a sortable subreddit URL and returns items',
        () async {
      final feed = _RecordingFeed();
      final server = RedditChannelServer(feedService: feed);

      final result = await server.callTool('reddit_list', {
        'subreddit': 'r/flutter',
        'sort': 'new',
        'limit': 5,
      });

      expect(result, isA<ChannelContentResult>());
      expect(feed.lastUrl, contains('r/flutter/new.json'));
      expect(feed.lastUrl, contains('limit=5'));
      expect((result as ChannelContentResult).items.single.title, 'Post');
    });

    test('reddit_search passes the query through', () async {
      final feed = _RecordingFeed();
      final server = RedditChannelServer(feedService: feed);

      await server.callTool('reddit_search', {
        'query': 'flutters',
        'limit': 3,
      });

      expect(feed.lastUrl, contains('search.json'));
      expect(feed.lastUrl, contains('q=flutters'));
    });

    test('returns an error for a missing subreddit', () async {
      final server = RedditChannelServer(feedService: _RecordingFeed());
      final result = await server.callTool('reddit_list', {});
      expect(result, isA<ChannelErrorResult>());
    });
  });

  group('NostrChannelServer', () {
    test('nostr_search uses the nostr:search URL', () async {
      final feed = _RecordingFeed();
      final server = NostrChannelServer(feedService: feed);

      await server.callTool('nostr_search', {'query': 'bitcoin'});

      expect(feed.lastUrl, 'nostr:search/bitcoin');
    });

    test('nostr_hashtag uses the nostr:t URL', () async {
      final feed = _RecordingFeed();
      final server = NostrChannelServer(feedService: feed);

      await server.callTool('nostr_hashtag', {'hashtag': '#Bitcoin'});

      expect(feed.lastUrl, 'nostr:t/bitcoin');
    });
  });

  group('RssChannelServer', () {
    test('rss_fetch returns feed items', () async {
      final feed = _RecordingFeed();
      final server = RssChannelServer(feedService: feed);

      final result = await server.callTool(
        'rss_fetch',
        {'url': 'https://example.com/feed.xml'},
      );

      expect(feed.lastUrl, 'https://example.com/feed.xml');
      expect(result, isA<ChannelContentResult>());
    });
  });

  group('UsenetChannelServer', () {
    test('usenet_search builds a usenet:// URL with optional category',
        () async {
      final feed = _RecordingFeed();
      final server = UsenetChannelServer(feedService: feed);

      await server.callTool('usenet_search', {
        'query': 'dune',
        'category': 'movies',
      });

      expect(feed.lastUrl, contains('usenet://search?q=dune'));
      expect(feed.lastUrl, contains('cat=movies'));
    });
  });

  group('error handling', () {
    test('returns an error when the feed service throws', () async {
      final feed = _ThrowingFeed();
      final server = RedditChannelServer(feedService: feed);

      final result = await server.callTool(
        'reddit_list',
        {'subreddit': 'flutter'},
      );
      expect(result, isA<ChannelErrorResult>());
    });

    test('unknown tools return an error', () async {
      final server = RedditChannelServer(feedService: _RecordingFeed());
      final result = await server.callTool('nope', {});
      expect(result, isA<ChannelErrorResult>());
    });
  });
}

class _RecordingFeed implements FeedService {
  String? lastUrl;
  FeedSourceType? lastType;

  @override
  Future<List<FeedItem>> fetchItems(String url, {FeedSourceType? type}) async {
    lastUrl = url;
    lastType = type;
    return [
      FeedItem(
        title: 'Post',
        url: 'https://example.com/1',
        description: 'desc',
        author: 'a',
      ),
    ];
  }

  @override
  Future<({List<FeedItem> items, String? nextCursor})> fetchItemsPage(
    String url, {
    FeedSourceType? type,
    String? cursor,
  }) async {
    return (items: await fetchItems(url, type: type), nextCursor: null);
  }

  @override
  Future<FeedSourceType?> detectType(String url) async => lastType;

  @override
  FeedSource getSource(FeedSourceType type) => _StubSource(type);

  @override
  ContentSource sourceFor(FeedSourceType type) =>
      throw UnimplementedError();
}

class _ThrowingFeed implements FeedService {
  @override
  Future<List<FeedItem>> fetchItems(String url, {FeedSourceType? type}) async {
    throw StateError('network down');
  }

  @override
  Future<({List<FeedItem> items, String? nextCursor})> fetchItemsPage(
    String url, {
    FeedSourceType? type,
    String? cursor,
  }) async =>
      throw StateError('network down');

  @override
  Future<FeedSourceType?> detectType(String url) async => null;

  @override
  FeedSource getSource(FeedSourceType type) => _StubSource(type);

  @override
  ContentSource sourceFor(FeedSourceType type) =>
      throw UnimplementedError();
}

class _StubSource implements FeedSource {
  _StubSource(this.type);
  @override
  final FeedSourceType type;

  @override
  Future<List<FeedItem>> fetch(String url) async => [];

  @override
  Future<bool> validate(String url) async => false;
}