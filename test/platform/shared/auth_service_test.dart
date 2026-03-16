/// Tests for the secp256k1 keypair-based [SharedAuthService].
///
/// Verifies keypair generation, import/export, signing, verification,
/// and Nostr-compatible bech32 encoding (npub/nsec).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/platform/shared/auth_service_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock path_provider to use a temporary directory.
  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kabuk_auth_test_');
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
  group('SharedAuthService', () {
    late SharedAuthService auth;

    setUp(() {
      auth = SharedAuthService();
    });

    test('hasIdentity is false initially', () async {
      expect(await auth.hasIdentity, isFalse);
    });

    test('currentUser is null initially', () async {
      expect(await auth.currentUser, isNull);
    });

    test('generateKeyPair creates a valid identity', () async {
      final identity = await auth.generateKeyPair();

      expect(identity.id, isNotEmpty);
      expect(identity.id.length, equals(64)); // 32-byte hex
      expect(identity.publicKey, isNotNull);
      expect(identity.publicKey!.length, equals(32)); // x-only pubkey
      expect(identity.publicKeyHex, isNotNull);
      expect(identity.publicKeyHex!.length, equals(64));
      expect(identity.npub, isNotNull);
      expect(identity.npub!.startsWith('npub1'), isTrue);
      expect(identity.displayName, equals('Identity 1'));
      expect(identity.createdAt, isNotNull);
    });

    test('generateKeyPair sets hasIdentity to true', () async {
      await auth.generateKeyPair();
      expect(await auth.hasIdentity, isTrue);
    });

    test('currentUser returns identity after generation', () async {
      await auth.generateKeyPair();
      final user = await auth.currentUser;
      expect(user, isNotNull);
      expect(user!.npub!.startsWith('npub1'), isTrue);
    });

    test('each generation creates a unique keypair', () async {
      final id1 = await auth.generateKeyPair();
      final hex1 = id1.publicKeyHex;
      final id2 = await auth.generateKeyPair();
      final hex2 = id2.publicKeyHex;
      expect(hex1, isNot(equals(hex2)));
    });

    test('setDisplayName updates the display name', () async {
      await auth.generateKeyPair();
      await auth.setDisplayName('Alice');
      final user = await auth.currentUser;
      expect(user!.displayName, equals('Alice'));
    });

    group('npub/nsec encoding', () {
      test('getNpub returns npub1 prefixed bech32', () async {
        await auth.generateKeyPair();
        final npub = await auth.getNpub();
        expect(npub, isNotNull);
        expect(npub!.startsWith('npub1'), isTrue);
        expect(npub.length, greaterThan(10));
      });

      test('exportNsec returns nsec1 prefixed bech32', () async {
        await auth.generateKeyPair();
        final nsec = await auth.exportNsec();
        expect(nsec, isNotNull);
        expect(nsec!.startsWith('nsec1'), isTrue);
      });

      test('exportNsec is null when no keypair exists', () async {
        expect(await auth.exportNsec(), isNull);
      });

      test('getNpub is null when no keypair exists', () async {
        expect(await auth.getNpub(), isNull);
      });
    });

    group('import/export roundtrip', () {
      test('importing exported nsec recovers the same identity', () async {
        final original = await auth.generateKeyPair();
        final nsec = await auth.exportNsec();

        // Create a new service and import the nsec
        final auth2 = SharedAuthService();
        final imported = (await auth2.importFromNsec(nsec!)).getOrThrow();

        expect(imported.publicKeyHex, equals(original.publicKeyHex));
        expect(imported.npub, equals(original.npub));
        expect(imported.id, equals(original.id));
      });

      test('importFromNsec returns failure on invalid prefix', () async {
        final result = await auth.importFromNsec('npub1abc');
        expect(result, isA<Failure<dynamic>>());
        expect((result as Failure<dynamic>).error, isA<ValidationError>());
      });

      test('importFromNsec returns failure on garbage input', () async {
        final result = await auth.importFromNsec('nsec1invaliddata');
        expect(result, isA<Failure<dynamic>>());
      });
    });

    group('Schnorr signing', () {
      test('sign produces a 64-byte signature', () async {
        await auth.generateKeyPair();
        final message = Uint8List.fromList(utf8.encode('hello world'));
        final sig = (await auth.sign(message)).getOrThrow();
        expect(sig.length, equals(64));
      });

      test('sign returns failure when no keypair exists', () async {
        final result = await auth.sign(Uint8List.fromList([1, 2, 3]));
        expect(result, isA<Failure<dynamic>>());
        expect((result as Failure<dynamic>).error, isA<NotFoundError>());
      });

      test('verify succeeds for valid signature', () async {
        await auth.generateKeyPair();
        final message = Uint8List.fromList(utf8.encode('test message'));
        final sig = (await auth.sign(message)).getOrThrow();
        final valid = await auth.verify(message, sig);
        expect(valid, isTrue);
      });

      test('verify fails for tampered message', () async {
        await auth.generateKeyPair();
        final message = Uint8List.fromList(utf8.encode('original'));
        final sig = (await auth.sign(message)).getOrThrow();
        final tampered = Uint8List.fromList(utf8.encode('tampered'));
        final valid = await auth.verify(tampered, sig);
        expect(valid, isFalse);
      });

      test('verify fails for tampered signature', () async {
        await auth.generateKeyPair();
        final message = Uint8List.fromList(utf8.encode('test'));
        final sig = (await auth.sign(message)).getOrThrow();
        sig[0] ^= 0xff; // flip bits
        final valid = await auth.verify(message, sig);
        expect(valid, isFalse);
      });

      test('verify with explicit public key works', () async {
        await auth.generateKeyPair();
        final user = await auth.currentUser;
        final message = Uint8List.fromList(utf8.encode('cross-verify'));
        final sig = (await auth.sign(message)).getOrThrow();

        // Verify using a fresh instance with explicit pubkey
        final auth2 = SharedAuthService();
        final valid = await auth2.verify(
          message,
          sig,
          publicKey: user!.publicKey,
        );
        expect(valid, isTrue);
      });

      test('different keys produce different signatures', () async {
        final auth1 = SharedAuthService();
        await auth1.generateKeyPair();
        final auth2 = SharedAuthService();
        await auth2.generateKeyPair();

        final msg = Uint8List.fromList(utf8.encode('same message'));
        final sig1 = (await auth1.sign(msg)).getOrThrow();
        final sig2 = (await auth2.sign(msg)).getOrThrow();
        expect(sig1, isNot(equals(sig2)));
      });

      test('cross-instance verification with imported key', () async {
        await auth.generateKeyPair();
        final nsec = await auth.exportNsec();
        final message = Uint8List.fromList(utf8.encode('sign me'));
        final sig = (await auth.sign(message)).getOrThrow();

        // Import into new instance and verify
        final auth2 = SharedAuthService();
        await auth2.importFromNsec(nsec!);
        final valid = await auth2.verify(message, sig);
        expect(valid, isTrue);
      });
    });

    group('persistence', () {
      test('knowledgeLoader restores keypair', () async {
        String? stored;
        final auth1 = SharedAuthService(
          knowledgeSaver: (json) async => stored = json,
        );
        final identity = await auth1.generateKeyPair();

        // Create a new auth service that loads from the stored data
        final auth2 = SharedAuthService(knowledgeLoader: () async => stored);
        final restored = await auth2.currentUser;
        expect(restored, isNotNull);
        expect(restored!.publicKeyHex, equals(identity.publicKeyHex));
        expect(restored.npub, equals(identity.npub));
      });

      test('display name is persisted', () async {
        String? stored;
        final auth1 = SharedAuthService(
          knowledgeSaver: (json) async => stored = json,
        );
        await auth1.generateKeyPair();
        await auth1.setDisplayName('Bob');

        final auth2 = SharedAuthService(knowledgeLoader: () async => stored);
        final user = await auth2.currentUser;
        expect(user!.displayName, equals('Bob'));
      });
    });
  });
}
