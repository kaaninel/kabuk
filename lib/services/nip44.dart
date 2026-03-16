/// NIP-44 v2 encrypted messaging — ChaCha20 with HMAC-SHA256.
///
/// Implements the Nostr NIP-44 versioned encryption scheme using:
/// - ECDH (secp256k1) for shared secret derivation
/// - HKDF-SHA256 for key derivation
/// - ChaCha20 (IETF) for stream encryption
/// - HMAC-SHA256 for message authentication
///
/// Reference: https://github.com/nostr-protocol/nips/blob/master/44.md
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// NIP-44 v2 encryption and decryption utilities.
///
/// All methods are static — this is a pure cryptographic utility class
/// with no state.
abstract final class Nip44 {
  static final _domainParams = ECDomainParameters('secp256k1');
  static final _fieldPrime = BigInt.parse(
    'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F',
    radix: 16,
  );

  /// NIP-44 version byte.
  static const _version = 2;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Computes ECDH shared secret between [privateKey] and [publicKey].
  ///
  /// Both keys are 32-byte arrays. [publicKey] is an x-only key
  /// (BIP-340 / NIP-01 format). Returns the 32-byte x-coordinate
  /// of the resulting EC point.
  static Uint8List computeSharedSecret(
    Uint8List privateKey,
    Uint8List publicKey,
  ) {
    if (privateKey.length != 32) {
      throw ArgumentError('Private key must be 32 bytes');
    }
    if (publicKey.length != 32) {
      throw ArgumentError('Public key must be 32 bytes');
    }

    final d = _bytesToBigInt(privateKey);
    final n = _domainParams.n;
    if (d <= BigInt.zero || d >= n) {
      throw ArgumentError('Private key out of valid range');
    }

    final px = _bytesToBigInt(publicKey);

    // Lift x-only pubkey to an EC point (even Y per BIP-340).
    final point = _liftX(px);
    if (point == null) throw ArgumentError('Invalid public key');

    // Shared secret = d * P
    final shared = point * d;
    if (shared == null || shared.isInfinity) {
      throw StateError('ECDH failed — invalid result');
    }

    return _bigIntToBytes(shared.x!.toBigInteger()!, 32);
  }

  /// Derives a NIP-44 conversation key from an ECDH shared secret.
  ///
  /// Uses HKDF-Extract with salt `"nip44-v2"`.
  static Uint8List deriveConversationKey(Uint8List sharedSecret) {
    final salt = Uint8List.fromList(utf8.encode('nip44-v2'));
    return _hkdfExtract(salt, sharedSecret);
  }

  /// Derives a conversation key directly from two keys.
  ///
  /// Convenience method combining [computeSharedSecret] and
  /// [deriveConversationKey].
  static Uint8List getConversationKey(
    Uint8List privateKey,
    Uint8List publicKey,
  ) {
    final shared = computeSharedSecret(privateKey, publicKey);
    return deriveConversationKey(shared);
  }

  /// Encrypts [plaintext] using the [conversationKey].
  ///
  /// Returns the base64-encoded NIP-44 v2 payload.
  static String encrypt(String plaintext, Uint8List conversationKey) {
    // Random 32-byte nonce (used as HKDF info, not ChaCha20 nonce).
    final nonce = _randomBytes(32);

    // Derive ChaCha20 key (32), nonce (12), and HMAC key (32) = 76 bytes.
    final keys = _hkdfExpand(conversationKey, nonce, 76);
    final chachaKey = keys.sublist(0, 32);
    final chachaNonce = keys.sublist(32, 44);
    final hmacKey = keys.sublist(44, 76);

    // Pad the plaintext per NIP-44.
    final padded = _pad(plaintext);

    // Encrypt with ChaCha20 (IETF variant, 12-byte nonce).
    final ciphertext = _chacha20(chachaKey, chachaNonce, padded);

    // Compute HMAC-SHA256 over (nonce || ciphertext).
    final hmacInput = Uint8List(nonce.length + ciphertext.length);
    hmacInput.setAll(0, nonce);
    hmacInput.setAll(nonce.length, ciphertext);
    final mac = _hmacSha256(hmacKey, hmacInput);

    // Assemble: version(1) || nonce(32) || ciphertext(N) || mac(32).
    final payload = Uint8List(1 + 32 + ciphertext.length + 32);
    payload[0] = _version;
    payload.setRange(1, 33, nonce);
    payload.setRange(33, 33 + ciphertext.length, ciphertext);
    payload.setRange(33 + ciphertext.length, payload.length, mac);

    return base64Encode(payload);
  }

  /// Decrypts a base64-encoded NIP-44 [payload] using the [conversationKey].
  ///
  /// Throws [FormatException] on invalid payload, version mismatch,
  /// or HMAC verification failure.
  static String decrypt(String payload, Uint8List conversationKey) {
    final data = base64Decode(payload);

    // Minimum: version(1) + nonce(32) + padded_min(34) + mac(32) = 99
    if (data.length < 99) {
      throw const FormatException('NIP-44 payload too short');
    }

    final version = data[0];
    if (version != _version) {
      throw FormatException('Unsupported NIP-44 version: $version');
    }

    final nonce = data.sublist(1, 33);
    final ciphertext = data.sublist(33, data.length - 32);
    final mac = data.sublist(data.length - 32);

    // Derive keys.
    final keys = _hkdfExpand(conversationKey, Uint8List.fromList(nonce), 76);
    final chachaKey = keys.sublist(0, 32);
    final chachaNonce = keys.sublist(32, 44);
    final hmacKey = keys.sublist(44, 76);

    // Verify HMAC before decryption (encrypt-then-MAC).
    final hmacInput = Uint8List(nonce.length + ciphertext.length);
    hmacInput.setAll(0, nonce);
    hmacInput.setAll(nonce.length, ciphertext);
    final expectedMac = _hmacSha256(hmacKey, hmacInput);

    if (!_constantTimeEqual(mac, expectedMac)) {
      throw const FormatException('NIP-44 HMAC verification failed');
    }

    // Decrypt.
    final padded = _chacha20(
      chachaKey,
      chachaNonce,
      Uint8List.fromList(ciphertext),
    );

    return _unpad(padded);
  }

  /// Generates a random secp256k1 keypair for gift wrapping.
  ///
  /// Returns a record of `(privateKey, publicKey)` as 32-byte arrays.
  /// The public key is x-only (BIP-340 format).
  static ({Uint8List privateKey, Uint8List publicKey})
  generateThrowawayKeypair() {
    final n = _domainParams.n;
    BigInt d;
    do {
      d = _bytesToBigInt(_randomBytes(32));
    } while (d == BigInt.zero || d >= n);

    final point = _domainParams.G * d;
    final px = point!.x!.toBigInteger()!;

    return (
      privateKey: _bigIntToBytes(d, 32),
      publicKey: _bigIntToBytes(px, 32),
    );
  }

  // ---------------------------------------------------------------------------
  // NIP-44 padding
  // ---------------------------------------------------------------------------

  /// Calculates the padded length for a given [unpaddedLen].
  ///
  /// The padding scheme rounds up to the next power-of-2 boundary
  /// divided into chunks, hiding the actual message length.
  static int calcPaddedLen(int unpaddedLen) {
    if (unpaddedLen <= 0) throw ArgumentError('Length must be > 0');
    if (unpaddedLen <= 32) return 32;

    final nextPower = 1 << (_log2(unpaddedLen - 1) + 1);
    final chunk = max(32, nextPower ~/ 8);
    return chunk * ((unpaddedLen + chunk - 1) ~/ chunk);
  }

  static int _log2(int x) {
    var result = 0;
    var val = x;
    while (val > 1) {
      val >>= 1;
      result++;
    }
    return result;
  }

  static Uint8List _pad(String plaintext) {
    final unpadded = utf8.encode(plaintext);
    final unpaddedLen = unpadded.length;
    if (unpaddedLen < 1 || unpaddedLen > 65535) {
      throw ArgumentError('Plaintext length must be 1–65535 bytes');
    }

    final paddedLen = calcPaddedLen(unpaddedLen);
    // 2-byte big-endian length prefix + padded content.
    final result = Uint8List(2 + paddedLen);
    result[0] = (unpaddedLen >> 8) & 0xff;
    result[1] = unpaddedLen & 0xff;
    result.setRange(2, 2 + unpaddedLen, unpadded);
    // Remaining bytes are zero (Uint8List default).
    return result;
  }

  static String _unpad(Uint8List padded) {
    if (padded.length < 2) {
      throw const FormatException('Padded data too short');
    }

    final unpaddedLen = (padded[0] << 8) | padded[1];
    if (unpaddedLen < 1 || 2 + unpaddedLen > padded.length) {
      throw const FormatException('Invalid padding length');
    }

    final expectedPaddedLen = calcPaddedLen(unpaddedLen);
    if (expectedPaddedLen + 2 != padded.length) {
      throw const FormatException('Invalid total padded length');
    }

    // Verify zero padding bytes.
    for (var i = 2 + unpaddedLen; i < padded.length; i++) {
      if (padded[i] != 0) {
        throw const FormatException('Non-zero padding byte');
      }
    }

    return utf8.decode(padded.sublist(2, 2 + unpaddedLen));
  }

  // ---------------------------------------------------------------------------
  // Cryptographic primitives
  // ---------------------------------------------------------------------------

  /// HKDF-Extract: PRK = HMAC-SHA256(salt, IKM).
  static Uint8List _hkdfExtract(Uint8List salt, Uint8List ikm) {
    return _hmacSha256(salt, ikm);
  }

  /// HKDF-Expand: derives [length] bytes from [prk] and [info].
  static Uint8List _hkdfExpand(Uint8List prk, Uint8List info, int length) {
    const hashLen = 32; // SHA-256 output
    final n = (length + hashLen - 1) ~/ hashLen;
    final okm = Uint8List(length);
    var prev = Uint8List(0);

    for (var i = 1; i <= n; i++) {
      final input = Uint8List(prev.length + info.length + 1);
      input.setAll(0, prev);
      input.setAll(prev.length, info);
      input[prev.length + info.length] = i;

      prev = _hmacSha256(prk, input);

      final start = (i - 1) * hashLen;
      final end = min(start + hashLen, length);
      okm.setRange(start, end, prev);
    }

    return okm;
  }

  /// HMAC-SHA256.
  static Uint8List _hmacSha256(Uint8List key, Uint8List data) {
    final hmac = HMac(SHA256Digest(), 64);
    hmac.init(KeyParameter(key));
    return hmac.process(data);
  }

  /// ChaCha20 (IETF variant, 12-byte nonce).
  static Uint8List _chacha20(Uint8List key, Uint8List nonce, Uint8List input) {
    final engine = ChaCha7539Engine();
    engine.init(true, ParametersWithIV(KeyParameter(key), nonce));
    final output = Uint8List(input.length);
    engine.processBytes(input, 0, input.length, output, 0);
    return output;
  }

  /// Lifts an x-coordinate to a secp256k1 point with even Y.
  static ECPoint? _liftX(BigInt x) {
    final p = _fieldPrime;
    if (x >= p) return null;

    // y² = x³ + 7 (secp256k1 curve equation)
    final ySquared = (x.modPow(BigInt.from(3), p) + BigInt.from(7)) % p;
    final y = ySquared.modPow((p + BigInt.one) >> 2, p);
    if (y.modPow(BigInt.two, p) != ySquared) return null;

    final effectiveY = y.isEven ? y : p - y;
    return _domainParams.curve.createPoint(x, effectiveY);
  }

  /// Constant-time byte comparison to prevent timing attacks.
  static bool _constantTimeEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// Cryptographically secure random bytes.
  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  // ---------------------------------------------------------------------------
  // Byte/BigInt utilities (public for use by NIP-17 and other modules)
  // ---------------------------------------------------------------------------

  /// Converts bytes to a [BigInt].
  static BigInt bytesToBigInt(Uint8List bytes) => _bytesToBigInt(bytes);

  /// Converts a [BigInt] to a fixed-length byte array.
  static Uint8List bigIntToBytes(BigInt value, int length) =>
      _bigIntToBytes(value, length);

  /// Converts bytes to a hex string.
  static String bytesToHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Converts a hex string to bytes.
  static Uint8List hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static Uint8List _bigIntToBytes(BigInt value, int length) {
    final result = Uint8List(length);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      result[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    return result;
  }
}
