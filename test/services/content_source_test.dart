import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/plugins/context.dart';
import 'package:kabuk/plugins/plugin.dart';
import 'package:kabuk/services/content_source.dart';
import 'package:kabuk/services/feed_refresh.dart';

void main() {
  group('contentItemToFeedItem', () {
    test('maps an article item', () {
      final item = ContentItem(
        sourcePluginId: 'wikipedia',
        externalId: '1',
        contentType: ContentType.article,
        title: 'Article',
        description: 'Desc',
        url: 'https://en.wikipedia.org/wiki/X',
        author: const ContentAuthor(name: 'A'),
        publishedAt: DateTime.utc(2026, 8, 1),
        tags: const ['reference'],
      );
      final feed = contentItemToFeedItem(item);
      expect(feed.title, 'Article');
      expect(feed.url, 'https://en.wikipedia.org/wiki/X');
      expect(feed.author, 'A');
      expect(feed.categories, ['reference']);
      expect(feed.videoUrl, isNull);
    });

    test('maps a video item using the HLS stream', () {
      final item = ContentItem(
        sourcePluginId: 'youtube',
        externalId: 'abc',
        contentType: ContentType.video,
        title: 'Video',
        thumbnailUrl: 'https://img/thumb.jpg',
        metadata: const VideoMeta(hlsUrl: 'https://stream/hls.m3u8'),
      );
      final feed = contentItemToFeedItem(item);
      expect(feed.videoUrl, 'https://stream/hls.m3u8');
      expect(feed.imageUrl, 'https://img/thumb.jpg');
    });

    test('falls back to a plugin: URL when the item has none', () {
      final item = ContentItem(
        sourcePluginId: 'youtube',
        externalId: 'abc',
        contentType: ContentType.video,
        title: 'No URL',
      );
      expect(contentItemToFeedItem(item).url, 'plugin:youtube/abc');
    });
  });

  group('PluginContentSource', () {
    test('channel mode delegates to fetchChannel and paginates', () async {
      final plugin = _FakePlugin(itemsPerPage: 2);
      final source = PluginContentSource.channel(plugin, 'channel-1');

      final page0 = await source.fetchPage(const ContentQuery(url: 'x', page: 0, perPage: 2));
      expect(page0.items.length, 2);
      expect(page0.items.first.url, 'plugin:fake/0');
      expect(page0.nextCursor, '1');

      final page1 = await source.fetchPage(const ContentQuery(url: 'x', page: 1, perPage: 2));
      expect(page1.items.length, 1);
      expect(page1.items.first.url, 'plugin:fake/2');
      expect(page1.nextCursor, isNull);
    });

    test('search mode delegates to plugin.search', () async {
      final plugin = _FakePlugin(itemsPerPage: 3);
      final source = PluginContentSource.search(plugin, 'cats');
      final page = await source.fetchPage(const ContentQuery(url: 'cats', page: 0, perPage: 3));
      expect(page.items.length, 3);
      expect(plugin.lastSearch, 'cats');
    });
  });

  group('buildRedditSortUrl', () {
    test('replaces existing sort path', () {
      expect(
        buildRedditSortUrl('https://www.reddit.com/r/flutter/hot.json?limit=50&raw_json=1', 'new'),
        'https://www.reddit.com/r/flutter/new.json?limit=50&raw_json=1',
      );
    });

    test('appends sort to a bare subreddit URL', () {
      expect(
        buildRedditSortUrl('https://www.reddit.com/r/flutter', 'top'),
        'https://www.reddit.com/r/flutter/top.json?limit=50&raw_json=1',
      );
    });
  });
}

class _FakePlugin implements ContentPlugin {
  _FakePlugin({this.itemsPerPage = 2});

  final int itemsPerPage;
  String? lastSearch;

  @override
  String get id => 'fake';
  @override
  String get name => 'Fake';
  @override
  String get description => 'Test plugin';
  @override
  String get version => '1.0.0';
  @override
  IconData get iconData => Icons.ac_unit;
  @override
  PluginCategory get category => PluginCategory.other;
  @override
  Set<ContentCapability> get capabilities =>
      {ContentCapability.search, ContentCapability.channel};

  @override
  bool hasCapability(ContentCapability capability) =>
      capabilities.contains(capability);
  @override
  List<PluginConfigField> get configFields => const [];

  @override
  bool canHandleUrl(String url) => url.contains('fake');
  @override
  Future<void> dispose() async {}
  @override
  Future<void> initialize(PluginContext context) async {}

  @override
  Future<List<ContentItem>> fetchChannel(
    String entityId, {
    int page = 0,
    int perPage = 20,
  }) async {
    final start = page * perPage;
    final count = (3 - start).clamp(0, perPage);
    return [
      for (var i = 0; i < count; i++)
        ContentItem(
          sourcePluginId: id,
          externalId: '${start + i}',
          contentType: ContentType.article,
          title: 'Item ${start + i}',
        ),
    ];
  }

  @override
  Future<List<ContentItem>> search(
    String query, {
    int page = 0,
    int perPage = 20,
  }) async {
    lastSearch = query;
    return [
      for (var i = 0; i < itemsPerPage; i++)
        ContentItem(
          sourcePluginId: id,
          externalId: '$i',
          contentType: ContentType.article,
          title: 'Result $i',
        ),
    ];
  }

  @override
  Future<List<ContentItem>> fetchTrending({
    int page = 0,
    int perPage = 20,
  }) async => [];

  @override
  Future<ResolvedContent> resolveUrl(String url) async =>
      const ResolvedNotHandled();
}