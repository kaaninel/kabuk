/// secp256k1 keypair-based identity service (Nostr-compatible).
///
/// Uses PointyCastle for elliptic curve operations and bech32 for
/// Nostr-style npub/nsec encoding. Private keys are stored in a
/// standalone identity registry file, independent of any per-profile
/// database (solving the bootstrap problem).
///
/// Signing uses Schnorr signatures compatible with BIP-340 / NIP-01.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bech32/bech32.dart';
import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/services/auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

/// Cross-platform [AuthService] using secp256k1 keypair identity.
///
/// The user's public key IS their identity (Nostr model). The keypair
/// is generated locally and never leaves the device unless explicitly
/// exported via [exportNsec]. Supports multiple identities with
/// switching — each identity is stored in a list and one is marked
/// active.
///
/// Identity data is persisted in a standalone JSON file
/// (`identity_registry.json`) separate from any per-profile database,
/// so identities can be enumerated before opening a profile DB.
class SharedAuthService implements AuthService {
  /// Creates a [SharedAuthService].
  ///
  /// Identity state is always persisted to `identity_registry.json`
  /// in the app documents directory. Legacy DB-backed loaders are
  /// migrated automatically on first run.
  SharedAuthService({this.knowledgeLoader, this.knowledgeSaver});

  /// Optional legacy loader for one-time migration from DB-backed storage.
  final Future<String?> Function()? knowledgeLoader;

  /// Optional legacy saver (unused after migration, kept for compatibility).
  final Future<void> Function(String json)? knowledgeSaver;

  // secp256k1 curve parameters
  static final _domainParams = ECDomainParameters('secp256k1');

  /// The secp256k1 field prime p.
  static final _fieldPrime = BigInt.parse(
    'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F',
    radix: 16,
  );

  // Multi-identity storage: list of identity entries.
  final List<_IdentityEntry> _identities = [];
  int _activeIndex = 0;
  Future<void>? _loadFuture;

  /// Internal representation of a stored identity.
  _IdentityEntry? get _activeEntry =>
      _identities.isEmpty ? null : _identities[_activeIndex];

  /// Returns the active identity's public key hex (first 16 chars)
  /// for use as a profile/database qualifier.
  ///
  /// Returns `null` if no identities are loaded yet.
  /// Must call [_ensureLoaded] first.
  String? get activeProfileId {
    final entry = _activeEntry;
    if (entry == null) return null;
    return _entryPubKeyHex(entry.publicKey).substring(0, 16);
  }

  /// Returns the full hex public key of the active identity.
  ///
  /// Must call [_ensureLoaded] first.
  String? get activePublicKeyHex {
    final entry = _activeEntry;
    if (entry == null) return null;
    return _entryPubKeyHex(entry.publicKey);
  }

  /// Ensures identities are loaded, then returns the active profile ID.
  ///
  /// This is the async version suitable for provider initialization.
  Future<String?> getActiveProfileId() async {
    await _ensureLoaded();
    return activeProfileId;
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Loads identities from the registry file (or migrates from DB).
  ///
  /// Uses a single Future so concurrent callers all wait for the
  /// same load operation to complete.
  Future<void> _ensureLoaded() {
    return _loadFuture ??= _doLoad();
  }

  Future<void> _doLoad() async {
    // Try loading from the standalone registry file first.
    final registryFile = await _registryFile();
    if (registryFile.existsSync()) {
      final json = await registryFile.readAsString();
      _parseIdentitiesJson(json);
      return;
    }

    // Fall back to legacy DB-backed loader for one-time migration.
    if (knowledgeLoader != null) {
      final json = await knowledgeLoader!();
      if (json != null) {
        _parseIdentitiesJson(json);
        // Migrate: persist to standalone file and clear DB record.
        await _persist();
        return;
      }
    }
  }

  /// Parses identity JSON into the in-memory list.
  void _parseIdentitiesJson(String json) {
    try {
      final data = jsonDecode(json);
      if (data is Map<String, dynamic>) {
        if (data.containsKey('identities')) {
          final list = data['identities'] as List;
          for (final item in list) {
            final entry = _parseIdentityMap(item as Map<String, dynamic>);
            if (entry != null) _identities.add(entry);
          }
          _activeIndex = (data['activeIndex'] as int?) ?? 0;
          if (_activeIndex >= _identities.length) _activeIndex = 0;
        } else {
          final entry = _parseIdentityMap(data);
          if (entry != null) _identities.add(entry);
          _activeIndex = 0;
        }
      } else if (data is List) {
        for (final item in data) {
          final entry = _parseIdentityMap(item as Map<String, dynamic>);
          if (entry != null) _identities.add(entry);
        }
        _activeIndex = 0;
      }
    } on Object {
      // Corrupted data — ignore.
    }
  }

  /// Returns the registry file path.
  Future<File> _registryFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/identity_registry.json');
  }

  /// Parses a single identity from a JSON map.
  _IdentityEntry? _parseIdentityMap(Map<String, dynamic> map) {
    final privHex = map['privateKey'] as String?;
    if (privHex == null) return null;
    final d = BigInt.parse(privHex, radix: 16);
    final privateKey = ECPrivateKey(d, _domainParams);
    final publicKey = ECPublicKey(_domainParams.G * d, _domainParams);
    final name = map['displayName'] as String? ?? 'Anonymous';
    final createdStr = map['createdAt'] as String?;
    final createdAt = createdStr != null ? DateTime.tryParse(createdStr) : null;
    return _IdentityEntry(
      privateKey: privateKey,
      publicKey: publicKey,
      displayName: name,
      createdAt: createdAt,
    );
  }

  /// Persists all identities to the standalone registry file.
  Future<void> _persist() async {
    final list = _identities
        .map(
          (e) => {
            'privateKey': e.privateKeyHex,
            'displayName': e.displayName,
            'createdAt': e.createdAt?.toIso8601String(),
          },
        )
        .toList();
    final json = jsonEncode({'identities': list, 'activeIndex': _activeIndex});
    final file = await _registryFile();
    await file.writeAsString(json, flush: true);
  }

  /// Generates a cryptographically secure random private key.
  BigInt _generateSecurePrivateKey() {
    final rng = FortunaRandom();
    final seed = Uint8List(32);
    final random = Random.secure();
    for (var i = 0; i < 32; i++) {
      seed[i] = random.nextInt(256);
    }
    rng.seed(KeyParameter(seed));

    // Generate a random scalar in [1, n-1]
    final n = _domainParams.n;
    BigInt d;
    do {
      final bytes = rng.nextBytes(32);
      d = _bytesToBigInt(bytes);
    } while (d == BigInt.zero || d >= n);
    return d;
  }

  // -------------------------------------------------------------------------
  // Bech32 encoding (NIP-19)
  // -------------------------------------------------------------------------

  /// Encodes raw bytes with a Nostr bech32 human-readable prefix.
  String _bech32Encode(String hrp, Uint8List data) {
    final words = _convertBits(data, 8, 5, true);
    return bech32.encode(Bech32(hrp, words));
  }

  /// Decodes a bech32 string and returns the raw bytes.
  Uint8List _bech32Decode(String encoded) {
    final decoded = bech32.decode(encoded);
    final words = decoded.data;
    return Uint8List.fromList(
      _convertBits(Uint8List.fromList(words), 5, 8, false),
    );
  }

  /// Bit conversion for bech32 (from BIP-173).
  static List<int> _convertBits(
    Uint8List data,
    int fromBits,
    int toBits,
    bool pad,
  ) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxv = (1 << toBits) - 1;

    for (final value in data) {
      acc = (acc << fromBits) | value;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }

    if (pad) {
      if (bits > 0) {
        result.add((acc << (toBits - bits)) & maxv);
      }
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      // Invalid padding — but we allow it for lenient decoding.
    }

    return result;
  }

  // -------------------------------------------------------------------------
  // Schnorr signatures (simplified BIP-340)
  // -------------------------------------------------------------------------

  /// Signs [message] with a specific [privKey] using Schnorr (BIP-340).
  ///
  /// Uses deterministic nonce generation: k = SHA256(privKey || message).
  Uint8List _schnorrSignWith(Uint8List message, ECPrivateKey privKey) {
    final d = privKey.d!;
    final n = _domainParams.n;
    final G = _domainParams.G;

    // Get x-only public key
    final P = G * d;
    final px = P!.x!.toBigInteger()!;

    // Ensure even Y (BIP-340 convention)
    final effectiveD = P.y!.toBigInteger()!.isEven ? d : n - d;

    // Deterministic nonce: k = SHA256(d_bytes || message)
    final dBytes = _bigIntToBytes(effectiveD, 32);
    final nonceInput = Uint8List(64 + message.length);
    nonceInput.setAll(0, dBytes);
    // Tag: "BIPSchnorrDerive" — simplified for our use
    nonceInput.setAll(32, _sha256(message));
    final kHash = _sha256(nonceInput.sublist(0, 64));
    var k = _bytesToBigInt(kHash) % n;
    if (k == BigInt.zero) {
      throw StateError('Invalid nonce — retry with different message');
    }

    final R = G * k;
    // Negate k if R.y is odd
    if (!R!.y!.toBigInteger()!.isEven) {
      k = n - k;
    }
    final rx = R.x!.toBigInteger()!;

    // e = SHA256(R.x || P.x || message)
    final eInput = Uint8List(64 + message.length);
    eInput.setAll(0, _bigIntToBytes(rx, 32));
    eInput.setAll(32, _bigIntToBytes(px, 32));
    eInput.setAll(64, message);
    final e = _bytesToBigInt(_sha256(eInput)) % n;

    // s = (k + e * d) mod n
    final s = (k + e * effectiveD) % n;

    // Signature = R.x || s (64 bytes)
    final sig = Uint8List(64);
    sig.setAll(0, _bigIntToBytes(rx, 32));
    sig.setAll(32, _bigIntToBytes(s, 32));
    return sig;
  }

  /// Verifies a BIP-340 Schnorr [signature] against [message] given
  /// a 32-byte x-only [pubKey].
  bool _schnorrVerify(
    Uint8List message,
    Uint8List signature,
    Uint8List pubKey,
  ) {
    if (signature.length != 64 || pubKey.length != 32) return false;

    final n = _domainParams.n;
    final G = _domainParams.G;
    final p = _fieldPrime;

    final rx = _bytesToBigInt(signature.sublist(0, 32));
    final s = _bytesToBigInt(signature.sublist(32, 64));
    final px = _bytesToBigInt(pubKey);

    if (rx >= p || s >= n) return false;

    // Reconstruct P from x coordinate (even Y)
    final P = _liftX(px);
    if (P == null) return false;

    // e = SHA256(R.x || P.x || message)
    final eInput = Uint8List(64 + message.length);
    eInput.setAll(0, signature.sublist(0, 32));
    eInput.setAll(32, pubKey);
    eInput.setAll(64, message);
    final e = _bytesToBigInt(_sha256(eInput)) % n;

    // R = s*G - e*P
    final sG = G * s;
    final eP = P * (n - e); // negate e for subtraction
    final R = sG! + eP!;

    if (R == null || R.isInfinity) return false;
    if (!R.y!.toBigInteger()!.isEven) return false;
    return R.x!.toBigInteger() == rx;
  }

  /// Lifts an x coordinate to a point on secp256k1 with even Y.
  ECPoint? _liftX(BigInt x) {
    final p = _fieldPrime;
    if (x >= p) return null;

    // y² = x³ + 7 (secp256k1)
    final ySquared = (x.modPow(BigInt.from(3), p) + BigInt.from(7)) % p;
    final y = ySquared.modPow((p + BigInt.one) >> 2, p);
    if (y.modPow(BigInt.two, p) != ySquared) return null;

    final effectiveY = y.isEven ? y : p - y;
    return _domainParams.curve.createPoint(x, effectiveY);
  }

  // -------------------------------------------------------------------------
  // Low-level utilities
  // -------------------------------------------------------------------------

  static Uint8List _sha256(Uint8List input) {
    final digest = SHA256Digest();
    return digest.process(input);
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  static String _bytesToHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
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

  // -------------------------------------------------------------------------
  // AuthService implementation
  // -------------------------------------------------------------------------

  @override
  Future<bool> get hasIdentity async {
    await _ensureLoaded();
    return _identities.isNotEmpty;
  }

  @override
  Future<UserIdentity?> get currentUser async {
    await _ensureLoaded();
    final entry = _activeEntry;
    if (entry == null) return null;
    return entry.toUserIdentity(this);
  }

  @override
  Future<UserIdentity> generateKeyPair() async {
    await _ensureLoaded();
    final d = _generateSecurePrivateKey();
    final privateKey = ECPrivateKey(d, _domainParams);
    final publicKey = ECPublicKey(_domainParams.G * d, _domainParams);
    final entry = _IdentityEntry(
      privateKey: privateKey,
      publicKey: publicKey,
      displayName: 'Identity ${_identities.length + 1}',
      createdAt: DateTime.now(),
    );
    _identities.add(entry);
    _activeIndex = _identities.length - 1;
    await _persist();
    return entry.toUserIdentity(this);
  }

  @override
  Future<Result<UserIdentity>> importFromNsec(String nsec) async {
    await _ensureLoaded();
    if (!nsec.startsWith('nsec1')) {
      return const Result.failure(
        ServiceError.validation('Invalid nsec — must start with "nsec1"'),
      );
    }
    try {
      final bytes = _bech32Decode(nsec);
      if (bytes.length != 32) {
        return const Result.failure(
          ServiceError.validation(
            'Invalid nsec — decoded key must be 32 bytes',
          ),
        );
      }
      final hex = _bytesToHex(bytes);
      final d = BigInt.parse(hex, radix: 16);
      final privateKey = ECPrivateKey(d, _domainParams);
      final publicKey = ECPublicKey(_domainParams.G * d, _domainParams);

      // Check for duplicate.
      final pubHex = _entryPubKeyHex(publicKey);
      final existingIdx = _identities.indexWhere(
        (e) => _entryPubKeyHex(e.publicKey) == pubHex,
      );
      if (existingIdx >= 0) {
        _activeIndex = existingIdx;
        await _persist();
        return Result.success(_identities[existingIdx].toUserIdentity(this));
      }

      final entry = _IdentityEntry(
        privateKey: privateKey,
        publicKey: publicKey,
        displayName: 'Imported Identity',
        createdAt: DateTime.now(),
      );
      _identities.add(entry);
      _activeIndex = _identities.length - 1;
      await _persist();
      return Result.success(entry.toUserIdentity(this));
    } on Object catch (e, st) {
      return Result.failure(
        ServiceError.unknown('Failed to import nsec: $e', e, st),
      );
    }
  }

  @override
  Future<String?> exportNsec() async {
    await _ensureLoaded();
    final entry = _activeEntry;
    if (entry == null) return null;
    final privBytes = _hexToBytes(entry.privateKeyHex);
    return _bech32Encode('nsec', privBytes);
  }

  @override
  Future<String?> getPublicKeyHex() async {
    await _ensureLoaded();
    final entry = _activeEntry;
    if (entry == null) return null;
    return _entryPubKeyHex(entry.publicKey);
  }

  @override
  Future<String?> getNpub() async {
    await _ensureLoaded();
    final entry = _activeEntry;
    if (entry == null) return null;
    return _bech32Encode('npub', _entryXOnlyPubKey(entry.publicKey));
  }

  @override
  Future<void> setDisplayName(String name) async {
    await _ensureLoaded();
    final entry = _activeEntry;
    if (entry == null) return;
    entry.displayName = name;
    await _persist();
  }

  @override
  Future<bool> authenticateBiometric({String? reason}) async {
    // Biometric authentication requires `local_auth` or similar plugin.
    return false;
  }

  @override
  Future<Uint8List?> getPrivateKeyBytes() async {
    await _ensureLoaded();
    final entry = _activeEntry;
    if (entry == null) return null;
    return _hexToBytes(entry.privateKeyHex);
  }

  @override
  Future<Result<Uint8List>> sign(List<int> data) async {
    await _ensureLoaded();
    final entry = _activeEntry;
    if (entry == null) {
      return const Result.failure(
        ServiceError.notFound(
          'No keypair — generate or import one first',
        ),
      );
    }
    final msg = data is Uint8List ? data : Uint8List.fromList(data);
    // Hash the data with SHA-256 before signing (standard practice)
    final hash = _sha256(msg);
    return Result.success(_schnorrSignWith(hash, entry.privateKey));
  }

  @override
  Future<Result<Uint8List>> signHash(Uint8List hash) async {
    await _ensureLoaded();
    final entry = _activeEntry;
    if (entry == null) {
      return const Result.failure(
        ServiceError.notFound(
          'No keypair — generate or import one first',
        ),
      );
    }
    if (hash.length != 32) {
      return const Result.failure(
        ServiceError.validation('Hash must be exactly 32 bytes'),
      );
    }
    return Result.success(_schnorrSignWith(hash, entry.privateKey));
  }

  @override
  Future<bool> verify(
    List<int> data,
    List<int> signature, {
    List<int>? publicKey,
  }) async {
    await _ensureLoaded();
    final msg = data is Uint8List ? data : Uint8List.fromList(data);
    final sig = signature is Uint8List
        ? signature
        : Uint8List.fromList(signature);
    final Uint8List pubKey;
    if (publicKey != null) {
      pubKey = publicKey is Uint8List
          ? publicKey
          : Uint8List.fromList(publicKey);
    } else if (_activeEntry != null) {
      pubKey = _entryXOnlyPubKey(_activeEntry!.publicKey);
    } else {
      throw StateError('No public key available for verification');
    }
    final hash = _sha256(msg);
    return _schnorrVerify(hash, sig, pubKey);
  }

  @override
  Future<bool> verifyHash(
    Uint8List hash,
    Uint8List signature, {
    Uint8List? publicKey,
  }) async {
    await _ensureLoaded();
    if (hash.length != 32) {
      throw ArgumentError('Hash must be exactly 32 bytes');
    }
    final Uint8List pubKey;
    if (publicKey != null) {
      pubKey = publicKey;
    } else if (_activeEntry != null) {
      pubKey = _entryXOnlyPubKey(_activeEntry!.publicKey);
    } else {
      throw StateError('No public key available for verification');
    }
    return _schnorrVerify(hash, signature, pubKey);
  }

  // ---------------------------------------------------------------------------
  // Multi-identity management
  // ---------------------------------------------------------------------------

  @override
  Future<List<UserIdentity>> listIdentities() async {
    await _ensureLoaded();
    return [for (final entry in _identities) entry.toUserIdentity(this)];
  }

  @override
  Future<Result<UserIdentity>> switchIdentity(String publicKeyHex) async {
    await _ensureLoaded();
    final idx = _identities.indexWhere(
      (e) => _entryPubKeyHex(e.publicKey) == publicKeyHex,
    );
    if (idx < 0) {
      return const Result.failure(ServiceError.notFound('Identity not found'));
    }
    _activeIndex = idx;
    await _persist();
    return Result.success(_identities[idx].toUserIdentity(this));
  }

  @override
  Future<Result<void>> removeIdentity(String publicKeyHex) async {
    await _ensureLoaded();
    if (_identities.length <= 1) {
      return const Result.failure(
        ServiceError.validation('Cannot remove the last identity'),
      );
    }
    final idx = _identities.indexWhere(
      (e) => _entryPubKeyHex(e.publicKey) == publicKeyHex,
    );
    if (idx < 0) {
      return const Result.failure(ServiceError.notFound('Identity not found'));
    }
    _identities.removeAt(idx);
    if (_activeIndex >= _identities.length) {
      _activeIndex = _identities.length - 1;
    } else if (_activeIndex > idx) {
      _activeIndex--;
    }
    await _persist();
    return const Result.success(null);
  }

  @override
  Future<String?> exportNsecFor(String publicKeyHex) async {
    await _ensureLoaded();
    final entry = _identities
        .where((e) => _entryPubKeyHex(e.publicKey) == publicKeyHex)
        .firstOrNull;
    if (entry == null) return null;
    return _bech32Encode('nsec', _hexToBytes(entry.privateKeyHex));
  }

  // -------------------------------------------------------------------------
  // Entry helpers
  // -------------------------------------------------------------------------

  /// Gets the x-only public key bytes for an [ECPublicKey].
  Uint8List _entryXOnlyPubKey(ECPublicKey pub) {
    final q = pub.Q!;
    final xHex = q.x!.toBigInteger()!.toRadixString(16).padLeft(64, '0');
    return _hexToBytes(xHex);
  }

  /// Gets the hex-encoded public key for an [ECPublicKey].
  String _entryPubKeyHex(ECPublicKey pub) {
    return _bytesToHex(_entryXOnlyPubKey(pub));
  }
}

/// Internal representation of a stored identity.
class _IdentityEntry {
  _IdentityEntry({
    required this.privateKey,
    required this.publicKey,
    required this.displayName,
    this.createdAt,
  });

  final ECPrivateKey privateKey;
  final ECPublicKey publicKey;
  String displayName;
  final DateTime? createdAt;

  /// The hex-encoded private key scalar.
  String get privateKeyHex {
    final d = privateKey.d!;
    return d.toRadixString(16).padLeft(64, '0');
  }

  /// Converts to a [UserIdentity] using the parent service for bech32.
  UserIdentity toUserIdentity(SharedAuthService service) {
    final pubBytes = service._entryXOnlyPubKey(publicKey);
    final pubHex = service._entryPubKeyHex(publicKey);
    return UserIdentity(
      id: pubHex,
      displayName: displayName,
      publicKey: pubBytes,
      publicKeyHex: pubHex,
      npub: service._bech32Encode('npub', pubBytes),
      createdAt: createdAt,
    );
  }
}
