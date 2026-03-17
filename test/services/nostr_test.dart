/// Tests for the Nostr NIP-01 event model and relay message parsing.
///
/// Covers [NostrEvent], [UnsignedNostrEvent], [NostrFilter],
/// [RelayMessage] parsing, and JSON serialization roundtrips.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/services/nostr.dart';

void main() {
  // ---------------------------------------------------------------------------
  // NostrEvent
  // ---------------------------------------------------------------------------

  group('NostrEvent', () {
    final sampleJson = {
      'id': 'abc123' * 10 + 'abcd',
      'pubkey': 'def456' * 10 + 'def4',
      'created_at': 1700000000,
      'kind': 1,
      'tags': [
        ['e', 'event_id_123'],
        ['p', 'pubkey_456'],
      ],
      'content': 'Hello Nostr!',
      'sig': 'sig789' * 10 + 'sig7',
    };

    test('fromJson parses all fields', () {
      final event = NostrEvent.fromJson(sampleJson);

      expect(event.id, sampleJson['id']);
      expect(event.pubkey, sampleJson['pubkey']);
      expect(event.createdAt, 1700000000);
      expect(event.kind, 1);
      expect(event.tags.length, 2);
      expect(event.tags[0], ['e', 'event_id_123']);
      expect(event.tags[1], ['p', 'pubkey_456']);
      expect(event.content, 'Hello Nostr!');
      expect(event.sig, sampleJson['sig']);
    });

    test('toJson produces correct map', () {
      final event = NostrEvent.fromJson(sampleJson);
      final json = event.toJson();

      expect(json['id'], sampleJson['id']);
      expect(json['pubkey'], sampleJson['pubkey']);
      expect(json['created_at'], 1700000000);
      expect(json['kind'], 1);
      expect(json['tags'], sampleJson['tags']);
      expect(json['content'], 'Hello Nostr!');
      expect(json['sig'], sampleJson['sig']);
    });

    test('fromJson → toJson roundtrip preserves data', () {
      final event = NostrEvent.fromJson(sampleJson);
      final json = event.toJson();
      final event2 = NostrEvent.fromJson(json);

      expect(event2.id, event.id);
      expect(event2.pubkey, event.pubkey);
      expect(event2.createdAt, event.createdAt);
      expect(event2.kind, event.kind);
      expect(event2.tags, event.tags);
      expect(event2.content, event.content);
      expect(event2.sig, event.sig);
    });

    test('serialized returns NIP-01 array format', () {
      final event = NostrEvent.fromJson(sampleJson);
      final ser = event.serialized;

      expect(ser.length, 6);
      expect(ser[0], 0);
      expect(ser[1], event.pubkey);
      expect(ser[2], event.createdAt);
      expect(ser[3], event.kind);
      expect(ser[4], event.tags);
      expect(ser[5], event.content);
    });

    test('serializedString produces valid JSON', () {
      final event = NostrEvent.fromJson(sampleJson);
      final str = event.serializedString;
      final parsed = jsonDecode(str) as List;
      expect(parsed[0], 0);
      expect(parsed[1], event.pubkey);
    });

    test('fromJson handles empty tags', () {
      final json = Map<String, dynamic>.from(sampleJson);
      json['tags'] = <List<dynamic>>[];
      final event = NostrEvent.fromJson(json);
      expect(event.tags, isEmpty);
    });

    test('fromJson handles nested numeric tag values', () {
      final json = Map<String, dynamic>.from(sampleJson);
      json['tags'] = [
        ['expiration', 12345],
      ];
      final event = NostrEvent.fromJson(json);
      // Numbers should be converted to strings via toString
      expect(event.tags[0], ['expiration', '12345']);
    });

    test('toString includes kind and abbreviated pubkey', () {
      final event = NostrEvent.fromJson(sampleJson);
      final str = event.toString();
      expect(str, contains('kind: 1'));
      expect(str, contains('NostrEvent'));
    });
  });

  // ---------------------------------------------------------------------------
  // UnsignedNostrEvent
  // ---------------------------------------------------------------------------

  group('UnsignedNostrEvent', () {
    test('constructor sets defaults', () {
      const event = UnsignedNostrEvent(kind: 1, content: 'test');
      expect(event.kind, 1);
      expect(event.content, 'test');
      expect(event.tags, isEmpty);
      expect(event.createdAt, isNull);
    });

    test('custom tags and timestamp', () {
      const event = UnsignedNostrEvent(
        kind: 0,
        content: '{"name": "Alice"}',
        tags: [
          ['p', 'abc123'],
        ],
        createdAt: 1700000000,
      );
      expect(event.kind, 0);
      expect(event.tags.length, 1);
      expect(event.createdAt, 1700000000);
    });
  });

  // ---------------------------------------------------------------------------
  // NostrKind
  // ---------------------------------------------------------------------------

  group('NostrKind', () {
    test('metadata is 0', () => expect(NostrKind.metadata, 0));
    test('textNote is 1', () => expect(NostrKind.textNote, 1));
    test('contacts is 3', () => expect(NostrKind.contacts, 3));
    test('encryptedDM is 4', () => expect(NostrKind.encryptedDM, 4));
    test('deletion is 5', () => expect(NostrKind.deletion, 5));
    test('repost is 6', () => expect(NostrKind.repost, 6));
    test('reaction is 7', () => expect(NostrKind.reaction, 7));
    test('relayList is 10002', () => expect(NostrKind.relayList, 10002));
  });

  // ---------------------------------------------------------------------------
  // NostrFilter
  // ---------------------------------------------------------------------------

  group('NostrFilter', () {
    test('empty filter produces empty JSON', () {
      const filter = NostrFilter();
      expect(filter.toJson(), isEmpty);
    });

    test('all fields serialize correctly', () {
      const filter = NostrFilter(
        ids: ['id1', 'id2'],
        authors: ['pub1'],
        kinds: [1, 6],
        eTags: ['eid1'],
        pTags: ['pid1', 'pid2'],
        since: 1000,
        until: 2000,
        limit: 50,
      );
      final json = filter.toJson();

      expect(json['ids'], ['id1', 'id2']);
      expect(json['authors'], ['pub1']);
      expect(json['kinds'], [1, 6]);
      expect(json['#e'], ['eid1']);
      expect(json['#p'], ['pid1', 'pid2']);
      expect(json['since'], 1000);
      expect(json['until'], 2000);
      expect(json['limit'], 50);
    });

    test('null fields are omitted', () {
      const filter = NostrFilter(kinds: [1]);
      final json = filter.toJson();
      expect(json.length, 1);
      expect(json.containsKey('ids'), isFalse);
      expect(json.containsKey('authors'), isFalse);
    });

    test('rTags serialize to #r key', () {
      const filter = NostrFilter(
        rTags: ['https://example.com/article'],
        kinds: [NostrKind.reaction],
      );
      final json = filter.toJson();
      expect(json['#r'], ['https://example.com/article']);
      expect(json['kinds'], [7]);
      expect(json.containsKey('#e'), isFalse);
    });

    test('all tag types serialize together', () {
      const filter = NostrFilter(
        eTags: ['eid1'],
        pTags: ['pid1'],
        rTags: ['https://url.com'],
        kinds: [1],
      );
      final json = filter.toJson();
      expect(json['#e'], ['eid1']);
      expect(json['#p'], ['pid1']);
      expect(json['#r'], ['https://url.com']);
    });
  });

  // ---------------------------------------------------------------------------
  // RelayMessage parsing
  // ---------------------------------------------------------------------------

  group('parseRelayMessage', () {
    test('parses EVENT message', () {
      final raw = jsonEncode([
        'EVENT',
        'sub123',
        {
          'id': 'a' * 64,
          'pubkey': 'b' * 64,
          'created_at': 1700000000,
          'kind': 1,
          'tags': <List<dynamic>>[],
          'content': 'hello',
          'sig': 'c' * 128,
        },
      ]);

      final msg = parseRelayMessage(raw);
      expect(msg, isA<RelayEventMessage>());
      final event = msg as RelayEventMessage;
      expect(event.subscriptionId, 'sub123');
      expect(event.event.id, 'a' * 64);
      expect(event.event.content, 'hello');
    });

    test('parses EOSE message', () {
      final raw = jsonEncode(['EOSE', 'sub456']);
      final msg = parseRelayMessage(raw);
      expect(msg, isA<RelayEoseMessage>());
      expect((msg as RelayEoseMessage).subscriptionId, 'sub456');
    });

    test('parses OK message (accepted)', () {
      final raw = jsonEncode(['OK', 'event_id', true, 'success']);
      final msg = parseRelayMessage(raw);
      expect(msg, isA<RelayOkMessage>());
      final ok = msg as RelayOkMessage;
      expect(ok.eventId, 'event_id');
      expect(ok.accepted, isTrue);
      expect(ok.message, 'success');
    });

    test('parses OK message (rejected)', () {
      final raw = jsonEncode(['OK', 'event_id', false, 'rate-limited']);
      final msg = parseRelayMessage(raw);
      expect(msg, isA<RelayOkMessage>());
      final ok = msg as RelayOkMessage;
      expect(ok.accepted, isFalse);
      expect(ok.message, 'rate-limited');
    });

    test('parses OK message without optional message', () {
      final raw = jsonEncode(['OK', 'event_id', true]);
      final msg = parseRelayMessage(raw);
      expect(msg, isA<RelayOkMessage>());
      final ok = msg as RelayOkMessage;
      expect(ok.message, isNull);
    });

    test('parses NOTICE message', () {
      final raw = jsonEncode(['NOTICE', 'relay is shutting down']);
      final msg = parseRelayMessage(raw);
      expect(msg, isA<RelayNoticeMessage>());
      expect((msg as RelayNoticeMessage).message, 'relay is shutting down');
    });

    test('parses CLOSED message with reason', () {
      final raw = jsonEncode(['CLOSED', 'sub789', 'too many subscriptions']);
      final msg = parseRelayMessage(raw);
      expect(msg, isA<RelayClosedMessage>());
      final closed = msg as RelayClosedMessage;
      expect(closed.subscriptionId, 'sub789');
      expect(closed.message, 'too many subscriptions');
    });

    test('parses CLOSED message without reason', () {
      final raw = jsonEncode(['CLOSED', 'sub789']);
      final msg = parseRelayMessage(raw);
      expect(msg, isA<RelayClosedMessage>());
      final closed = msg as RelayClosedMessage;
      expect(closed.subscriptionId, 'sub789');
      expect(closed.message, isNull);
    });

    test('returns null for unknown message type', () {
      final raw = jsonEncode(['UNKNOWN', 'data']);
      expect(parseRelayMessage(raw), isNull);
    });

    test('returns null for empty array', () {
      final raw = jsonEncode([]);
      expect(parseRelayMessage(raw), isNull);
    });

    test('returns null for invalid JSON', () {
      expect(parseRelayMessage('not json'), isNull);
    });

    test('returns null for non-array JSON', () {
      expect(parseRelayMessage('{"type": "EVENT"}'), isNull);
    });

    test('returns null for EVENT with missing fields', () {
      final raw = jsonEncode(['EVENT']);
      expect(parseRelayMessage(raw), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // RelayConfig
  // ---------------------------------------------------------------------------

  group('RelayConfig', () {
    test('constructor defaults read=true, write=true', () {
      const config = RelayConfig(url: 'wss://relay.example.com');
      expect(config.url, 'wss://relay.example.com');
      expect(config.read, isTrue);
      expect(config.write, isTrue);
    });

    test('toJson includes all fields', () {
      const config = RelayConfig(url: 'wss://r.com', read: true, write: false);
      final json = config.toJson();
      expect(json['url'], 'wss://r.com');
      expect(json['read'], isTrue);
      expect(json['write'], isFalse);
    });

    test('fromJson parses correctly', () {
      final config = RelayConfig.fromJson({
        'url': 'wss://example.com',
        'read': false,
        'write': true,
      });
      expect(config.url, 'wss://example.com');
      expect(config.read, isFalse);
      expect(config.write, isTrue);
    });

    test('fromJson defaults read/write to true', () {
      final config = RelayConfig.fromJson({'url': 'wss://test.com'});
      expect(config.read, isTrue);
      expect(config.write, isTrue);
    });

    test('fromJson → toJson roundtrip', () {
      const original = RelayConfig(
        url: 'wss://relay.damus.io',
        read: true,
        write: false,
      );
      final restored = RelayConfig.fromJson(original.toJson());
      expect(restored.url, original.url);
      expect(restored.read, original.read);
      expect(restored.write, original.write);
    });
  });

  // ---------------------------------------------------------------------------
  // Sealed class pattern matching
  // ---------------------------------------------------------------------------

  group('RelayMessage sealed class', () {
    test('exhaustive switch on all subtypes', () {
      final messages = <RelayMessage>[
        const RelayEventMessage(
          subscriptionId: 's',
          event: NostrEvent(
            id: 'id',
            pubkey: 'pk',
            createdAt: 0,
            kind: 1,
            tags: [],
            content: '',
            sig: 'sig',
          ),
        ),
        const RelayEoseMessage(subscriptionId: 's'),
        const RelayOkMessage(eventId: 'e', accepted: true),
        const RelayNoticeMessage(message: 'hi'),
        const RelayClosedMessage(subscriptionId: 's'),
      ];

      for (final msg in messages) {
        // Exhaustive switch — compile-time guarantee all cases handled.
        final label = switch (msg) {
          RelayEventMessage() => 'event',
          RelayEoseMessage() => 'eose',
          RelayOkMessage() => 'ok',
          RelayNoticeMessage() => 'notice',
          RelayClosedMessage() => 'closed',
          RelayAuthMessage() => 'auth',
        };
        expect(label, isNotEmpty);
      }
    });
  });
}
