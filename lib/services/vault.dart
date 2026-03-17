import 'dart:typed_data';

import 'package:kabuk/config/errors.dart' show NotFoundError;
import 'package:kabuk/config/exports.dart' show NotFoundError;
import 'package:kabuk/config/result.dart';

/// Encrypted, tag-based file storage abstraction.
///
/// VaultService handles all file storage with built-in encryption,
/// content-addressing (SHA-256 hash), and tag-based organization.
/// Files are identified by their content hash, ensuring deduplication
/// and integrity verification. Platform implementations live in
/// `lib/platform/`.
///
/// All data is encrypted at rest by default. Tags provide a flexible
/// organizational layer that agents and UI can use for filtering and
/// discovery without needing a separate taxonomy.
abstract interface class VaultService {
  /// Stores [data] in the vault with encryption and content-addressing.
  ///
  /// Returns a [VaultEntry] describing the stored file, including its
  /// SHA-256 content hash. If a file with the same hash already exists,
  /// implementations may deduplicate storage but must update metadata.
  ///
  /// - [name]: Human-readable filename for display purposes.
  /// - [mimeType]: Optional MIME type (e.g. `image/png`). Aids retrieval
  ///   and preview.
  /// - [metadata]: Arbitrary key-value pairs attached to the entry.
  /// - [tags]: Organizational tags for filtering and search.
  /// - [encrypt]: Whether to encrypt the data at rest. Defaults to `true`.
  Future<VaultEntry> store(
    Uint8List data, {
    required String name,
    String? mimeType,
    Map<String, String>? metadata,
    List<String>? tags,
    bool encrypt = true,
  });

  /// Retrieves the raw bytes for the file identified by [hash].
  ///
  /// If the file is encrypted, it is transparently decrypted before
  /// returning. Returns [Failure] with [NotFoundError] if the hash
  /// does not exist.
  Future<Result<Uint8List>> retrieve(String hash);

  /// Permanently deletes the vault entry identified by [hash].
  ///
  /// After deletion, the hash will no longer resolve and a
  /// [VaultChange.removed] event is emitted. Returns [Failure]
  /// with [NotFoundError] if the hash does not exist.
  Future<Result<void>> delete(String hash);

  /// Lists vault entries matching the given filter criteria.
  ///
  /// - [tags]: If provided, only entries containing **all** specified
  ///   tags are returned.
  /// - [mimeTypePrefix]: Filters by MIME type prefix (e.g. `image/`).
  /// - [limit]: Maximum number of entries to return.
  /// - [offset]: Number of entries to skip, for pagination.
  ///
  /// Results are ordered by [VaultEntry.modifiedAt] descending.
  Future<List<VaultEntry>> list({
    List<String>? tags,
    String? mimeTypePrefix,
    int? limit,
    int? offset,
  });

  /// Searches vault entries by [query] against names, tags, and metadata.
  ///
  /// The query is matched case-insensitively. Implementations may use
  /// full-text search or simple substring matching depending on platform
  /// capabilities.
  Future<List<VaultEntry>> search(String query);

  /// Emits a [VaultChange] whenever entries are added, removed, or updated.
  ///
  /// The stream is broadcast — multiple listeners may subscribe. Events
  /// are emitted after the underlying storage operation completes
  /// successfully.
  Stream<VaultChange> watchChanges();

  /// Replaces the tag list for the entry identified by [hash].
  ///
  /// Returns the updated [VaultEntry]. Emits a [VaultChange.updated]
  /// event. Returns [Failure] with [NotFoundError] if the hash
  /// does not exist.
  Future<Result<VaultEntry>> updateTags(String hash, List<String> tags);

  /// Returns aggregate statistics about the vault's contents.
  Future<VaultStats> getStats();

  /// Imports a file from a platform-specific path into the vault.
  ///
  /// [platformPath] is an opaque string whose format depends on the
  /// host platform (e.g. content URI on Android, file path on desktop).
  /// The file is read, hashed, encrypted (by default), and stored.
  Future<VaultEntry> importFromPath(String platformPath);
}

/// A file entry stored in the vault.
///
/// Each entry is identified by its content [hash] (SHA-256) and carries
/// metadata for display, filtering, and retrieval.
class VaultEntry {
  /// Creates a new [VaultEntry].
  const VaultEntry({
    required this.hash,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.createdAt,
    required this.modifiedAt,
    required this.tags,
    required this.metadata,
    required this.encrypted,
  });

  /// SHA-256 content hash, used as the primary identifier.
  final String hash;

  /// Human-readable filename for display.
  final String name;

  /// MIME type of the stored content (e.g. `application/pdf`).
  final String mimeType;

  /// Size of the stored data in bytes.
  final int size;

  /// Timestamp when the entry was first stored.
  final DateTime createdAt;

  /// Timestamp of the last metadata update.
  final DateTime modifiedAt;

  /// Organizational tags attached to the entry.
  final List<String> tags;

  /// Arbitrary key-value metadata associated with the entry.
  final Map<String, String> metadata;

  /// Whether the stored data is encrypted at rest.
  final bool encrypted;

  @override
  String toString() => 'VaultEntry(hash: $hash, name: $name, size: $size)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is VaultEntry && hash == other.hash;

  @override
  int get hashCode => hash.hashCode;
}

/// A change event emitted by the vault when entries are mutated.
///
/// Use exhaustive pattern matching to handle all cases:
/// ```dart
/// switch (change) {
///   case VaultEntryAdded(:final entry) => handleAdded(entry),
///   case VaultEntryRemoved(:final hash) => handleRemoved(hash),
///   case VaultEntryUpdated(:final entry) => handleUpdated(entry),
/// }
/// ```
sealed class VaultChange {
  /// An entry was added to the vault.
  const factory VaultChange.added(VaultEntry entry) = VaultEntryAdded;

  /// An entry was removed from the vault.
  const factory VaultChange.removed(String hash) = VaultEntryRemoved;

  /// An entry's metadata or tags were updated.
  const factory VaultChange.updated(VaultEntry entry) = VaultEntryUpdated;
}

/// Emitted when a new entry is added to the vault.
class VaultEntryAdded implements VaultChange {
  /// Creates a [VaultEntryAdded] event.
  const VaultEntryAdded(this.entry);

  /// The newly added vault entry.
  final VaultEntry entry;
}

/// Emitted when an entry is removed from the vault.
class VaultEntryRemoved implements VaultChange {
  /// Creates a [VaultEntryRemoved] event.
  const VaultEntryRemoved(this.hash);

  /// The content hash of the removed entry.
  final String hash;
}

/// Emitted when an existing entry's metadata or tags are updated.
class VaultEntryUpdated implements VaultChange {
  /// Creates a [VaultEntryUpdated] event.
  const VaultEntryUpdated(this.entry);

  /// The updated vault entry with new metadata.
  final VaultEntry entry;
}

/// Aggregate statistics about the vault's contents.
class VaultStats {
  /// Creates a [VaultStats] instance.
  const VaultStats({
    required this.totalSize,
    required this.entryCount,
    required this.encryptedCount,
  });

  /// Total size of all stored data in bytes.
  final int totalSize;

  /// Total number of entries in the vault.
  final int entryCount;

  /// Number of entries that are encrypted at rest.
  final int encryptedCount;

  @override
  String toString() =>
      'VaultStats(entries: $entryCount, totalSize: $totalSize, encrypted: $encryptedCount)';
}
