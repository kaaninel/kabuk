/// Persistent, encrypted [VaultService] with SHA-256 content-addressing.
///
/// Stores entries as AES-256-GCM-encrypted files in the app's documents
/// directory. An in-memory index is kept in sync with a JSON manifest
/// file for fast lookups. Each stored blob is written to its own file
/// named by its SHA-256 content hash.
///
/// Encryption key is derived from a random 256-bit key stored in the
/// manifest. In production this key should be protected by the OS
/// keychain (via `flutter_secure_storage` or Keychain/Keystore APIs).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/services/vault.dart';
import 'package:path_provider/path_provider.dart';

/// File-backed, AES-256-GCM-encrypted [VaultService].
///
/// Data layout on disk:
/// ```
/// <appDocDir>/vault/<profileId>/
///   manifest.json   — entry metadata index + base64-encoded master key
///   blobs/
///     <sha256-hex>  — encrypted blob files
/// ```
///
/// Each identity profile gets its own vault directory and master
/// encryption key, providing complete file-level data isolation.
class SharedVaultService implements VaultService {
  /// Creates a [SharedVaultService] scoped to the given [profileId].
  ///
  /// [profileId] is typically the first 16 hex chars of the identity's
  /// public key. Defaults to `'default'` for backward compatibility.
  SharedVaultService({this.profileId = 'default'});

  /// The profile identifier used to scope the vault directory.
  final String profileId;

  final Map<String, _StoredEntry> _entries = {};
  final StreamController<VaultChange> _changes =
      StreamController<VaultChange>.broadcast();

  bool _initialised = false;
  late Directory _blobDir;
  late File _manifestFile;
  late SecretKey _masterKey;

  final _cipher = AesGcm.with256bits();

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  /// Ensures the vault directory structure and master key exist.
  ///
  /// Called lazily on the first operation. Subsequent calls are no-ops.
  /// Directory is scoped per profile: `vault/<profileId>/blobs/`.
  Future<void> _ensureInit() async {
    if (_initialised) return;

    final appDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory('${appDir.path}/vault/$profileId');
    _blobDir = Directory('${vaultDir.path}/blobs');
    _manifestFile = File('${vaultDir.path}/manifest.json');

    await _blobDir.create(recursive: true);

    if (_manifestFile.existsSync()) {
      await _loadManifest();
    } else {
      // First run — generate a random master key.
      _masterKey = await _cipher.newSecretKey();
      await _saveManifest();
    }

    _initialised = true;
  }

  Future<void> _loadManifest() async {
    final raw = await _manifestFile.readAsString();
    final json = jsonDecode(raw) as Map<String, dynamic>;

    // Restore master key.
    final keyBytes = base64Decode(json['key'] as String);
    _masterKey = SecretKey(keyBytes);

    // Restore entry index.
    final entries = json['entries'] as Map<String, dynamic>? ?? {};
    for (final entry in entries.entries) {
      final map = entry.value as Map<String, dynamic>;
      _entries[entry.key] = _StoredEntry(
        entry: VaultEntry(
          hash: entry.key,
          name: map['name'] as String,
          mimeType: map['mimeType'] as String,
          size: map['size'] as int,
          createdAt: DateTime.parse(map['createdAt'] as String),
          modifiedAt: DateTime.parse(map['modifiedAt'] as String),
          tags:
              (map['tags'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              const [],
          metadata:
              (map['metadata'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, v as String),
              ) ??
              const {},
          encrypted: map['encrypted'] as bool? ?? true,
        ),
      );
    }
  }

  Future<void> _saveManifest() async {
    final keyBytes = await _masterKey.extractBytes();

    final entries = <String, dynamic>{};
    for (final entry in _entries.entries) {
      final e = entry.value.entry;
      entries[entry.key] = {
        'name': e.name,
        'mimeType': e.mimeType,
        'size': e.size,
        'createdAt': e.createdAt.toIso8601String(),
        'modifiedAt': e.modifiedAt.toIso8601String(),
        'tags': e.tags,
        'metadata': e.metadata,
        'encrypted': e.encrypted,
      };
    }

    final json = jsonEncode({
      'key': base64Encode(keyBytes),
      'entries': entries,
    });
    await _manifestFile.writeAsString(json, flush: true);
  }

  // ---------------------------------------------------------------------------
  // Encryption helpers
  // ---------------------------------------------------------------------------

  Future<Uint8List> _encrypt(Uint8List plaintext) async {
    final nonce = _generateNonce();
    final secretBox = await _cipher.encrypt(
      plaintext,
      secretKey: _masterKey,
      nonce: nonce,
    );
    // Format: [12-byte nonce][ciphertext+mac]
    return Uint8List.fromList([
      ...nonce,
      ...secretBox.concatenation().skip(12),
    ]);
  }

  Future<Uint8List> _decrypt(Uint8List blob) async {
    final nonce = blob.sublist(0, 12);
    final ciphertextAndMac = blob.sublist(12);
    final secretBox = SecretBox.fromConcatenation(
      [...nonce, ...ciphertextAndMac],
      nonceLength: 12,
      macLength: 16,
    );
    final plaintext = await _cipher.decrypt(secretBox, secretKey: _masterKey);
    return Uint8List.fromList(plaintext);
  }

  List<int> _generateNonce() {
    final rng = Random.secure();
    return List<int>.generate(12, (_) => rng.nextInt(256));
  }

  // ---------------------------------------------------------------------------
  // Hashing
  // ---------------------------------------------------------------------------

  /// Computes the SHA-256 hex digest of [data].
  Future<String> _sha256(Uint8List data) async {
    final algorithm = Sha256();
    final hash = await algorithm.hash(data);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // ---------------------------------------------------------------------------
  // VaultService interface
  // ---------------------------------------------------------------------------

  @override
  Future<VaultEntry> store(
    Uint8List data, {
    required String name,
    String? mimeType,
    Map<String, String>? metadata,
    List<String>? tags,
    bool encrypt = true,
  }) async {
    await _ensureInit();
    final hash = await _sha256(data);
    final now = DateTime.now();

    final entry = VaultEntry(
      hash: hash,
      name: name,
      mimeType: mimeType ?? 'application/octet-stream',
      size: data.length,
      createdAt: _entries.containsKey(hash)
          ? _entries[hash]!.entry.createdAt
          : now,
      modifiedAt: now,
      tags: tags ?? const [],
      metadata: metadata ?? const {},
      encrypted: encrypt,
    );

    // Write encrypted blob to disk.
    final blobFile = File('${_blobDir.path}/$hash');
    if (encrypt) {
      final encrypted = await _encrypt(data);
      await blobFile.writeAsBytes(encrypted, flush: true);
    } else {
      await blobFile.writeAsBytes(data, flush: true);
    }

    _entries[hash] = _StoredEntry(entry: entry);
    await _saveManifest();
    _changes.add(VaultChange.added(entry));
    return entry;
  }

  @override
  Future<Result<Uint8List>> retrieve(String hash) async {
    await _ensureInit();
    final stored = _entries[hash];
    if (stored == null) {
      return Result.failure(
        ServiceError.notFound('No vault entry with hash: $hash'),
      );
    }

    final blobFile = File('${_blobDir.path}/$hash');
    if (!blobFile.existsSync()) {
      return Result.failure(
        ServiceError.notFound('Blob file missing for hash: $hash'),
      );
    }

    final raw = await blobFile.readAsBytes();
    if (stored.entry.encrypted) {
      return Result.success(await _decrypt(raw));
    }
    return Result.success(raw);
  }

  @override
  Future<Result<void>> delete(String hash) async {
    await _ensureInit();
    if (!_entries.containsKey(hash)) {
      return Result.failure(
        ServiceError.notFound('No vault entry with hash: $hash'),
      );
    }

    _entries.remove(hash);

    final blobFile = File('${_blobDir.path}/$hash');
    if (blobFile.existsSync()) {
      await blobFile.delete();
    }

    await _saveManifest();
    _changes.add(VaultChange.removed(hash));
    return const Result.success(null);
  }

  @override
  Future<List<VaultEntry>> list({
    List<String>? tags,
    String? mimeTypePrefix,
    int? limit,
    int? offset,
  }) async {
    await _ensureInit();
    var results = _entries.values.map((e) => e.entry).toList();

    if (tags != null && tags.isNotEmpty) {
      results = results
          .where((e) => tags.every((t) => e.tags.contains(t)))
          .toList();
    }

    if (mimeTypePrefix != null) {
      results = results
          .where((e) => e.mimeType.startsWith(mimeTypePrefix))
          .toList();
    }

    // Sort by modifiedAt descending.
    results.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));

    if (offset != null && offset > 0) {
      results = results.skip(offset).toList();
    }
    if (limit != null && limit > 0) {
      results = results.take(limit).toList();
    }

    return results;
  }

  @override
  Future<List<VaultEntry>> search(String query) async {
    await _ensureInit();
    final lower = query.toLowerCase();
    return _entries.values
        .map((e) => e.entry)
        .where(
          (e) =>
              e.name.toLowerCase().contains(lower) ||
              e.tags.any((t) => t.toLowerCase().contains(lower)) ||
              e.metadata.values.any((v) => v.toLowerCase().contains(lower)),
        )
        .toList();
  }

  @override
  Stream<VaultChange> watchChanges() => _changes.stream;

  @override
  Future<Result<VaultEntry>> updateTags(String hash, List<String> tags) async {
    await _ensureInit();
    final stored = _entries[hash];
    if (stored == null) {
      return Result.failure(
        ServiceError.notFound('No vault entry with hash: $hash'),
      );
    }

    final updated = VaultEntry(
      hash: stored.entry.hash,
      name: stored.entry.name,
      mimeType: stored.entry.mimeType,
      size: stored.entry.size,
      createdAt: stored.entry.createdAt,
      modifiedAt: DateTime.now(),
      tags: tags,
      metadata: stored.entry.metadata,
      encrypted: stored.entry.encrypted,
    );

    _entries[hash] = _StoredEntry(entry: updated);
    await _saveManifest();
    _changes.add(VaultChange.updated(updated));
    return Result.success(updated);
  }

  @override
  Future<VaultStats> getStats() async {
    await _ensureInit();
    final entries = _entries.values.toList();
    return VaultStats(
      totalSize: entries.fold(0, (sum, e) => sum + e.entry.size),
      entryCount: entries.length,
      encryptedCount: entries.where((e) => e.entry.encrypted).length,
    );
  }

  @override
  Future<VaultEntry> importFromPath(String platformPath) async {
    final bytes = await File(platformPath).readAsBytes();
    final name = platformPath.split('/').last.split('\\').last;
    return store(bytes, name: name);
  }
}

/// Internal storage record for an indexed vault entry.
///
/// Unlike the old in-memory implementation, actual data is on disk.
/// This only holds the metadata [entry] for the in-memory index.
class _StoredEntry {
  const _StoredEntry({required this.entry});

  /// The vault entry metadata.
  final VaultEntry entry;
}
