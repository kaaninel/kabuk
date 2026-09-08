import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:kabuk/knowledge/drift_store.dart';
import 'package:kabuk/knowledge/types/article.dart';

void main() {
  late KabukDatabase db;
  late DriftKnowledgeStore store;

  setUp(() async {
    db = KabukDatabase(NativeDatabase.memory());
    await db.findTriples(); // wait for FTS/triggers setup
    store = DriftKnowledgeStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('createArticle', () {
    test('stamps a 14-day TTL for unread articles', () async {
      final pub = DateTime.utc(2026, 8, 1, 12);
      final uri = await store.createArticle(
        title: 'Hello',
        url: 'https://example.com/a',
        feedSource: 'kabuk:FeedSubscription/1',
        datePublished: pub,
      );
      final article = await store.getArticleData(uri);
      expect(article, isNotNull);
      final expected = pub.add(kUnreadArticleTtl);
      expect(article!.expiresAt, expected);
    });
  });

  group('listArticles', () {
    Future<void> seed(String url, DateTime published, {List<String> tags = const [], String? feedSource, String title = 'T'}) {
      return store.createArticle(
        title: title,
        url: url,
        feedSource: feedSource ?? 'kabuk:FeedSubscription/1',
        datePublished: published,
        tags: tags,
      );
    }

    test('paginates with the before cursor', () async {
      await seed('https://x/1', DateTime.utc(2026, 8, 1));
      await seed('https://x/2', DateTime.utc(2026, 8, 2));
      await seed('https://x/3', DateTime.utc(2026, 8, 3));

      final page1 = await store.listArticles(limit: 2);
      expect(page1.map((a) => a.url), ['https://x/3', 'https://x/2']);

      final page2 = await store.listArticles(
        limit: 2,
        before: page1.last.datePublished,
      );
      expect(page2.map((a) => a.url), ['https://x/1']);
    });

    test('OR-filters on a set of feed sources', () async {
      await seed('https://x/1', DateTime.utc(2026, 8, 1), feedSource: 'kabuk:FeedSubscription/a');
      await seed('https://x/2', DateTime.utc(2026, 8, 2), feedSource: 'kabuk:FeedSubscription/b');
      await seed('https://x/3', DateTime.utc(2026, 8, 3), feedSource: 'kabuk:FeedSubscription/c');

      final filtered = await store.listArticles(
        feedSources: ['kabuk:FeedSubscription/a', 'kabuk:FeedSubscription/c'],
      );
      expect(filtered.map((a) => a.url).toSet(), {'https://x/1', 'https://x/3'});
    });

    test('filters by keyword', () async {
      await seed('https://x/1', DateTime.utc(2026, 8, 1), title: 'Flutter release');
      await seed('https://x/2', DateTime.utc(2026, 8, 2), title: 'Rust borrow checker');

      final hits = await store.listArticles(keyword: 'flutter');
      expect(hits.map((a) => a.url), ['https://x/1']);
    });

    test('hides NSFW when requested', () async {
      await seed('https://x/1', DateTime.utc(2026, 8, 1), tags: ['nsfw']);
      await seed('https://x/2', DateTime.utc(2026, 8, 2));

      final clean = await store.listArticles(hideNsfw: true);
      expect(clean.map((a) => a.url), ['https://x/2']);
    });

    test('excludes muted sources', () async {
      await seed('https://x/1', DateTime.utc(2026, 8, 1), feedSource: 'kabuk:FeedSubscription/a');
      await seed('https://x/2', DateTime.utc(2026, 8, 2), feedSource: 'kabuk:FeedSubscription/b');

      final visible = await store.listArticles(
        mutedSources: ['kabuk:FeedSubscription/a'],
      );
      expect(visible.map((a) => a.url), ['https://x/2']);
    });
  });

  group('preferences', () {
    test('set/get/delete roundtrip', () async {
      await store.setPreference('feed.filters.hideNsfw', 'false');
      expect(await store.getPreference('feed.filters.hideNsfw'), 'false');

      await store.setPreference('feed.filters.hideNsfw', 'true');
      expect(await store.getPreference('feed.filters.hideNsfw'), 'true');

      await store.deletePreference('feed.filters.hideNsfw');
      expect(await store.getPreference('feed.filters.hideNsfw'), isNull);
    });
  });

  group('retagArticles', () {
    test('re-tags articles from a pseudo source to a subscription URI', () async {
      final uri = await store.createArticle(
        title: 'Post',
        url: 'https://x/1',
        feedSource: 'reddit:r/flutter',
      );
      await store.createArticle(
        title: 'Other',
        url: 'https://x/2',
        feedSource: 'kabuk:FeedSubscription/other',
      );

      final moved = await store.retagArticles(
        'reddit:r/flutter',
        'kabuk:FeedSubscription/1',
      );
      expect(moved, 1);

      final article = await store.getArticleData(uri);
      expect(article!.feedSource, 'kabuk:FeedSubscription/1');
    });

    test('is a no-op when from == to', () async {
      expect(
        await store.retagArticles('a', 'a'),
        0,
      );
    });
  });

  group('pruneStaleArticles', () {
    test('keeps unread articles within the 14-day TTL', () async {
      final uri = await store.createArticle(
        title: 'Recent',
        url: 'https://x/1',
        feedSource: 'kabuk:FeedSubscription/1',
        datePublished: DateTime.now().subtract(const Duration(days: 1)),
      );
      final pruned = await store.pruneStaleArticles();
      expect(pruned, 0);
      expect(await store.getArticleData(uri), isNotNull);
    });

    test('deletes expired unread articles', () async {
      final uri = await store.createArticle(
        title: 'Old',
        url: 'https://x/1',
        feedSource: 'kabuk:FeedSubscription/1',
        datePublished: DateTime.now().subtract(const Duration(days: 30)),
      );
      final pruned = await store.pruneStaleArticles();
      expect(pruned, 1);
      expect(await store.getArticleData(uri), isNull);
    });
  });
}