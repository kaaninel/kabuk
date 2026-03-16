/// Tests for NIP-09, NIP-23, NIP-51 data models and filter extensions.
///
/// Verifies [NostrFilter.dTags] serialization, [NostrLongFormContent]
/// parsing, [NostrBookmarkList] / [NostrMuteList] data classes, and
/// [NostrKind] constants for the new event types.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/services/nostr.dart';

void main() {
  // ---------------------------------------------------------------------------
  // NostrKind constants
  // ---------------------------------------------------------------------------

  group('NostrKind constants', () {
    test('event deletion is kind 5', () {
      expect(NostrKind.deletion, 5);
    });

    test('mute list is kind 10000', () {
      expect(NostrKind.muteList, 10000);
    });

    test('pin list is kind 10001', () {
      expect(NostrKind.pinList, 10001);
    });

    test('categorized people list is kind 30000', () {
      expect(NostrKind.categorizedPeopleList, 30000);
    });

    test('categorized bookmark list is kind 30001', () {
      expect(NostrKind.categorizedBookmarkList, 30001);
    });

    test('long form content is kind 30023', () {
      expect(NostrKind.longFormContent, 30023);
    });
  });

  // ---------------------------------------------------------------------------
  // NostrFilter.dTags
  // ---------------------------------------------------------------------------

  group('NostrFilter.dTags', () {
    test('serializes dTags as #d in toJson', () {
      const filter = NostrFilter(kinds: [30023], dTags: ['my-article-slug']);
      final json = filter.toJson();

      expect(json['#d'], ['my-article-slug']);
      expect(json['kinds'], [30023]);
    });

    test('omits #d when dTags is null', () {
      const filter = NostrFilter(kinds: [1]);
      final json = filter.toJson();

      expect(json.containsKey('#d'), isFalse);
    });

    test('supports multiple dTags', () {
      const filter = NostrFilter(dTags: ['slug-1', 'slug-2', 'slug-3']);
      final json = filter.toJson();

      expect(json['#d'], hasLength(3));
    });
  });

  // ---------------------------------------------------------------------------
  // NostrLongFormContent
  // ---------------------------------------------------------------------------

  group('NostrLongFormContent', () {
    test('fromEvent parses all fields', () {
      final event = NostrEvent.fromJson({
        'id': 'a' * 64,
        'pubkey': 'b' * 64,
        'created_at': 1700000000,
        'kind': 30023,
        'tags': [
          ['d', 'my-article'],
          ['title', 'My Test Article'],
          ['summary', 'A test article for testing.'],
          ['image', 'https://example.com/image.png'],
          ['published_at', '1700000000'],
          ['t', 'testing'],
          ['t', 'nostr'],
        ],
        'content': '# Hello World\n\nThis is a test article.',
        'sig': 'c' * 128,
      });

      final article = NostrLongFormContent.fromEvent(event);

      expect(article.identifier, 'my-article');
      expect(article.title, 'My Test Article');
      expect(article.summary, 'A test article for testing.');
      expect(article.image, 'https://example.com/image.png');
      expect(article.publishedAt, DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
      expect(article.hashtags, ['testing', 'nostr']);
      expect(article.content, '# Hello World\n\nThis is a test article.');
      expect(article.authorPubkey, 'b' * 64);
    });

    test('fromEvent handles missing optional fields', () {
      final event = NostrEvent.fromJson({
        'id': 'a' * 64,
        'pubkey': 'b' * 64,
        'created_at': 1700000000,
        'kind': 30023,
        'tags': [
          ['d', 'minimal-article'],
        ],
        'content': 'Just content.',
        'sig': 'c' * 128,
      });

      final article = NostrLongFormContent.fromEvent(event);

      expect(article.identifier, 'minimal-article');
      expect(article.title, 'Untitled');
      expect(article.summary, isNull);
      expect(article.image, isNull);
      expect(article.publishedAt, isNull);
      expect(article.hashtags, isEmpty);
    });

    test('fromEvent handles missing d-tag', () {
      final event = NostrEvent.fromJson({
        'id': 'a' * 64,
        'pubkey': 'b' * 64,
        'created_at': 1700000000,
        'kind': 30023,
        'tags': <List<String>>[],
        'content': 'No d-tag article.',
        'sig': 'c' * 128,
      });

      final article = NostrLongFormContent.fromEvent(event);

      expect(article.identifier, '');
    });
  });

  // ---------------------------------------------------------------------------
  // NostrBookmarkList
  // ---------------------------------------------------------------------------

  group('NostrBookmarkList', () {
    test('creates with all fields', () {
      const list = NostrBookmarkList(
        name: 'favorites',
        eventIds: ['event1', 'event2'],
        urls: ['https://example.com'],
        hashtags: ['nostr'],
      );

      expect(list.name, 'favorites');
      expect(list.eventIds, hasLength(2));
      expect(list.urls, ['https://example.com']);
      expect(list.hashtags, ['nostr']);
    });

    test('defaults to empty lists', () {
      const list = NostrBookmarkList(name: 'empty');

      expect(list.eventIds, isEmpty);
      expect(list.urls, isEmpty);
      expect(list.hashtags, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // NostrMuteList
  // ---------------------------------------------------------------------------

  group('NostrMuteList', () {
    test('creates with all fields', () {
      const list = NostrMuteList(
        pubkeys: ['pub1', 'pub2'],
        eventIds: ['event1'],
        hashtags: ['spam'],
      );

      expect(list.pubkeys, hasLength(2));
      expect(list.eventIds, hasLength(1));
      expect(list.hashtags, ['spam']);
    });

    test('defaults to empty lists', () {
      const list = NostrMuteList();

      expect(list.pubkeys, isEmpty);
      expect(list.eventIds, isEmpty);
      expect(list.hashtags, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // NostrFilter.tTags
  // ---------------------------------------------------------------------------

  group('NostrFilter.tTags', () {
    test('serializes tTags as #t in toJson', () {
      const filter = NostrFilter(kinds: [1], tTags: ['bitcoin', 'nostr']);
      final json = filter.toJson();

      expect(json['#t'], ['bitcoin', 'nostr']);
    });
  });
}
