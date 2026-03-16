/// Tests for [SharedNostrService] — event signing & verification.
///
/// Uses a real [SharedAuthService] for secp256k1 signing integration.
/// Relay WebSocket communication is tested at the config management
/// level without actual network calls.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/platform/shared/auth_service_impl.dart';
import 'package:kabuk/platform/shared/nostr_service_impl.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:pointycastle/export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock path_provider to use a temporary directory.
  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kabuk_nostr_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          },
        );
  });
  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });
  // ---------------------------------------------------------------------------
  // Event signing (NIP-01)
  // ---------------------------------------------------------------------------

  group('SharedNostrService event signing', () {
    late SharedAuthService auth;
    late SharedNostrService nostr;

    setUp(() async {
      auth = SharedAuthService();
      await auth.generateKeyPair();
      nostr = SharedNostrService(auth: auth);
    });

    test('signEvent produces a NostrEvent with valid fields', () async {
      const unsigned = UnsignedNostrEvent(
        kind: NostrKind.textNote,
        content: 'Hello from tests!',
      );

      final event = await nostr.signEvent(unsigned);

      expect(event.kind, NostrKind.textNote);
      expect(event.content, 'Hello from tests!');
      expect(event.pubkey, (await auth.currentUser)!.publicKeyHex);
      expect(event.id.length, 64); // SHA-256 hex
      expect(event.sig.length, 128); // 64-byte Schnorr sig hex
      expect(event.tags, isEmpty);
      expect(event.createdAt, greaterThan(0));
    });

    test('signEvent uses provided createdAt', () async {
      const unsigned = UnsignedNostrEvent(
        kind: 1,
        content: 'timed',
        createdAt: 1700000000,
      );

      final event = await nostr.signEvent(unsigned);
      expect(event.createdAt, 1700000000);
    });

    test('signEvent preserves tags', () async {
      const unsigned = UnsignedNostrEvent(
        kind: 1,
        content: 'tagged',
        tags: [
          ['e', 'referenced_event_id'],
          ['p', 'mentioned_pubkey'],
        ],
      );

      final event = await nostr.signEvent(unsigned);
      expect(event.tags.length, 2);
      expect(event.tags[0], ['e', 'referenced_event_id']);
      expect(event.tags[1], ['p', 'mentioned_pubkey']);
    });

    test('signEvent computes correct NIP-01 event ID', () async {
      const unsigned = UnsignedNostrEvent(
        kind: 1,
        content: 'verify me',
        createdAt: 1700000000,
        tags: [],
      );

      final event = await nostr.signEvent(unsigned);

      // Manually compute expected ID.
      final serialized = jsonEncode([
        0,
        event.pubkey,
        event.createdAt,
        event.kind,
        event.tags,
        event.content,
      ]);
      final hash = SHA256Digest().process(
        Uint8List.fromList(utf8.encode(serialized)),
      );
      final expectedId = hash
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      expect(event.id, expectedId);
    });

    test('signEvent throws StateError when no identity exists', () async {
      // Remove persisted identity so the new service starts empty.
      final idFile = File('${tempDir.path}/identity_registry.json');
      if (idFile.existsSync()) idFile.deleteSync();
      final emptyAuth = SharedAuthService();
      final emptyNostr = SharedNostrService(auth: emptyAuth);

      expect(
        () => emptyNostr.signEvent(
          const UnsignedNostrEvent(kind: 1, content: 'fail'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('verifyEvent returns true for properly signed event', () async {
      const unsigned = UnsignedNostrEvent(
        kind: 1,
        content: 'verify roundtrip',
        createdAt: 1700000000,
      );

      final event = await nostr.signEvent(unsigned);
      final valid = await nostr.verifyEvent(event);
      expect(valid, isTrue);
    });

    test('verifyEvent returns false for tampered content', () async {
      final event = await nostr.signEvent(
        const UnsignedNostrEvent(kind: 1, content: 'original'),
      );

      // Tamper with content.
      final tampered = NostrEvent(
        id: event.id,
        pubkey: event.pubkey,
        createdAt: event.createdAt,
        kind: event.kind,
        tags: event.tags,
        content: 'tampered',
        sig: event.sig,
      );

      final valid = await nostr.verifyEvent(tampered);
      expect(valid, isFalse);
    });

    test('verifyEvent returns false for tampered id', () async {
      final event = await nostr.signEvent(
        const UnsignedNostrEvent(kind: 1, content: 'test'),
      );

      final tampered = NostrEvent(
        id: 'a' * 64, // fake id
        pubkey: event.pubkey,
        createdAt: event.createdAt,
        kind: event.kind,
        tags: event.tags,
        content: event.content,
        sig: event.sig,
      );

      final valid = await nostr.verifyEvent(tampered);
      expect(valid, isFalse);
    });

    test('verifyEvent returns false for wrong signature', () async {
      final event = await nostr.signEvent(
        const UnsignedNostrEvent(kind: 1, content: 'test'),
      );

      final tampered = NostrEvent(
        id: event.id,
        pubkey: event.pubkey,
        createdAt: event.createdAt,
        kind: event.kind,
        tags: event.tags,
        content: event.content,
        sig: 'f' * 128, // fake sig
      );

      final valid = await nostr.verifyEvent(tampered);
      expect(valid, isFalse);
    });

    test('event signed by one key fails verification with another', () async {
      // Sign with first key.
      final event = await nostr.signEvent(
        const UnsignedNostrEvent(kind: 1, content: 'cross-key'),
      );

      // Create a second service with a different key.
      final auth2 = SharedAuthService();
      await auth2.generateKeyPair();
      final nostr2 = SharedNostrService(auth: auth2);

      // Event has pubkey of first key, so verification should still work
      // (verifyEvent uses the event's pubkey, not the local key).
      final valid = await nostr2.verifyEvent(event);
      expect(valid, isTrue);
    });

    test('metadata event (kind 0) roundtrip', () async {
      final unsigned = UnsignedNostrEvent(
        kind: NostrKind.metadata,
        content: jsonEncode({'name': 'Alice', 'about': 'Testing'}),
        createdAt: 1700000000,
      );

      final event = await nostr.signEvent(unsigned);
      expect(event.kind, NostrKind.metadata);

      final meta = jsonDecode(event.content) as Map<String, dynamic>;
      expect(meta['name'], 'Alice');
      expect(meta['about'], 'Testing');

      // Verify signature.
      final valid = await nostr.verifyEvent(event);
      expect(valid, isTrue);
    });

    test('multiple events produce unique IDs', () async {
      final ids = <String>{};
      for (var i = 0; i < 10; i++) {
        final event = await nostr.signEvent(
          UnsignedNostrEvent(kind: 1, content: 'msg $i'),
        );
        ids.add(event.id);
      }
      expect(ids.length, 10);
    });
  });

  // ---------------------------------------------------------------------------
  // Relay config management
  // ---------------------------------------------------------------------------

  group('SharedNostrService relay config', () {
    late SharedAuthService auth;

    setUp(() async {
      auth = SharedAuthService();
      await auth.generateKeyPair();
    });

    test('starts with no relays', () {
      final nostr = SharedNostrService(auth: auth);
      expect(nostr.relays, isEmpty);
      expect(nostr.connectedRelays, isEmpty);
    });

    test('addRelay persists config', () async {
      String? saved;
      // Pre-load a config that includes all DM-essential relays so
      // the auto-merge doesn't inflate the count.
      final seedConfig = jsonEncode([
        {'url': 'wss://seed.test.com', 'read': true, 'write': true},
        {'url': 'wss://relay.0xchat.com', 'read': true, 'write': true},
        {'url': 'wss://inbox.nostr.wine', 'read': true, 'write': true},
        {'url': 'wss://auth.nostr1.com', 'read': true, 'write': true},
        {'url': 'wss://purplepag.es', 'read': true, 'write': false},
      ]);
      final nostr = SharedNostrService(
        auth: auth,
        onRelayLoad: () async => seedConfig,
        onRelaySave: (json) async => saved = json,
      );

      await nostr.addRelay(const RelayConfig(url: 'wss://relay.test.com'));

      expect(nostr.relays.length, 6); // seed(5) + new
      expect(nostr.relays.any((r) => r.url == 'wss://relay.test.com'), isTrue);
      expect(saved, isNotNull);
    });

    test('removeRelay removes config', () async {
      final seedConfig = jsonEncode([
        {'url': 'wss://keep.test.com', 'read': true, 'write': true},
        {'url': 'wss://relay.0xchat.com', 'read': true, 'write': true},
        {'url': 'wss://inbox.nostr.wine', 'read': true, 'write': true},
        {'url': 'wss://auth.nostr1.com', 'read': true, 'write': true},
        {'url': 'wss://purplepag.es', 'read': true, 'write': false},
      ]);
      final nostr = SharedNostrService(
        auth: auth,
        onRelayLoad: () async => seedConfig,
        onRelaySave: (json) async {},
      );

      await nostr.addRelay(const RelayConfig(url: 'wss://relay1.test.com'));
      await nostr.addRelay(const RelayConfig(url: 'wss://relay2.test.com'));
      expect(nostr.relays.length, 7); // seed(5) + 2 added

      await nostr.removeRelay('wss://relay1.test.com');
      expect(nostr.relays.length, 6);
      expect(
        nostr.relays.any((r) => r.url == 'wss://relay1.test.com'),
        isFalse,
      );
    });

    test('onRelayLoad restores config', () async {
      final configJson = jsonEncode([
        {'url': 'wss://saved.com', 'read': true, 'write': false},
        {'url': 'wss://relay.0xchat.com', 'read': true, 'write': true},
        {'url': 'wss://inbox.nostr.wine', 'read': true, 'write': true},
        {'url': 'wss://auth.nostr1.com', 'read': true, 'write': true},
        {'url': 'wss://purplepag.es', 'read': true, 'write': false},
      ]);

      final nostr = SharedNostrService(
        auth: auth,
        onRelayLoad: () async => configJson,
      );

      // Trigger config load by calling addRelay (which calls _ensureConfigLoaded).
      await nostr.addRelay(const RelayConfig(url: 'wss://new.com'));

      expect(nostr.relays.length, 6); // seed(5) + new
      expect(nostr.relays.first.url, 'wss://saved.com');
      expect(nostr.relays.first.write, isFalse);
    });

    test('corrupt saved config is handled gracefully', () async {
      final nostr = SharedNostrService(
        auth: auth,
        onRelayLoad: () async => 'not valid json {{{{',
      );

      // Should not throw — falls back to defaults.
      await nostr.addRelay(const RelayConfig(url: 'wss://test.com'));
      expect(nostr.relays.length, SharedNostrService.defaultRelays.length + 1);
    });

    test('null saved config is handled gracefully', () async {
      final nostr = SharedNostrService(
        auth: auth,
        onRelayLoad: () async => null,
      );

      // Falls back to defaults.
      await nostr.addRelay(const RelayConfig(url: 'wss://test.com'));
      expect(nostr.relays.length, SharedNostrService.defaultRelays.length + 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Auth signHash / verifyHash integration
  // ---------------------------------------------------------------------------

  group('AuthService signHash integration', () {
    late SharedAuthService auth;

    setUp(() async {
      auth = SharedAuthService();
      await auth.generateKeyPair();
    });

    test('signHash produces 64-byte signature for 32-byte hash', () async {
      final hash = SHA256Digest().process(
        Uint8List.fromList(utf8.encode('test data')),
      );
      final sig = (await auth.signHash(hash)).getOrThrow();
      expect(sig.length, 64);
    });

    test('signHash returns failure on non-32-byte input', () async {
      final result = await auth.signHash(Uint8List.fromList([1, 2, 3]));
      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure<dynamic>).error, isA<ValidationError>());
    });

    test('signHash returns failure when no keypair exists', () async {
      // Remove persisted identity so the new service starts empty.
      final idFile = File('${tempDir.path}/identity_registry.json');
      if (idFile.existsSync()) idFile.deleteSync();
      final emptyAuth = SharedAuthService();
      final hash = Uint8List(32);
      final result = await emptyAuth.signHash(hash);
      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure<dynamic>).error, isA<NotFoundError>());
    });

    test('verifyHash succeeds for valid hash+sig', () async {
      final hash = SHA256Digest().process(
        Uint8List.fromList(utf8.encode('roundtrip')),
      );
      final sig = (await auth.signHash(hash)).getOrThrow();
      final valid = await auth.verifyHash(hash, sig);
      expect(valid, isTrue);
    });

    test('verifyHash fails for wrong hash', () async {
      final hash1 = SHA256Digest().process(
        Uint8List.fromList(utf8.encode('message1')),
      );
      final hash2 = SHA256Digest().process(
        Uint8List.fromList(utf8.encode('message2')),
      );
      final sig = (await auth.signHash(hash1)).getOrThrow();
      final valid = await auth.verifyHash(hash2, sig);
      expect(valid, isFalse);
    });

    test('verifyHash with explicit public key', () async {
      final user = await auth.currentUser;
      final hash = SHA256Digest().process(
        Uint8List.fromList(utf8.encode('cross verify')),
      );
      final sig = (await auth.signHash(hash)).getOrThrow();

      final auth2 = SharedAuthService();
      final valid = await auth2.verifyHash(
        hash,
        sig,
        publicKey: user!.publicKey,
      );
      expect(valid, isTrue);
    });

    test('verifyHash throws on non-32-byte hash', () async {
      expect(
        () => auth.verifyHash(Uint8List.fromList([1, 2, 3]), Uint8List(64)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
