/// Usenet credential management layer wrapping the Vault service.
///
/// Provides typed access to NNTP provider passwords and Newznab indexer
/// API keys. Credentials are stored encrypted via [VaultService] and
/// referenced by content hash so the knowledge store can link
/// `kabuk:passwordRef` / `kabuk:apiKeyRef` predicates to vault entries
/// without holding plaintext secrets.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:kabuk/config/result.dart';
import 'package:kabuk/services/vault.dart';

/// Manages Usenet credentials (provider passwords, indexer API keys)
/// through the encrypted [VaultService].
///
/// Each credential is stored as a UTF-8-encoded [Uint8List] with
/// encryption enabled. Entries are tagged for efficient lookup:
///
/// * Provider passwords: tags `usenet`, `provider`, `credential`
/// * Indexer API keys:   tags `usenet`, `indexer`, `credential`
///
/// The vault returns a content-addressed [VaultEntry.hash] that can be
/// persisted in the knowledge store as a `kabuk:passwordRef` or
/// `kabuk:apiKeyRef` triple value.
class UsenetCredentialStore {
  /// Creates a [UsenetCredentialStore] backed by [vault].
  UsenetCredentialStore({required VaultService vault}) : _vault = vault;

  final VaultService _vault;

  // ---------------------------------------------------------------------------
  // Provider passwords
  // ---------------------------------------------------------------------------

  /// Stores an NNTP provider [password] for [providerId].
  ///
  /// If a password already exists for this provider it is replaced.
  /// Returns the vault entry hash that can be used as a
  /// `kabuk:passwordRef` value in the knowledge store.
  Future<String> storeProviderPassword(
    String providerId,
    String password,
  ) async {
    await _deleteExisting(_providerName(providerId), _providerTags);

    final entry = await _vault.store(
      _encode(password),
      name: _providerName(providerId),
      tags: _providerTags,
      encrypt: true,
    );
    return entry.hash;
  }

  /// Retrieves the NNTP password for [providerId], or `null` if none is
  /// stored.
  Future<String?> getProviderPassword(String providerId) async {
    final entry = await _findEntry(_providerName(providerId), _providerTags);
    if (entry == null) return null;

    final result = await _vault.retrieve(entry.hash);
    return switch (result) {
      Success(:final value) => _decode(value),
      Failure() => null,
    };
  }

  /// Deletes the stored password for [providerId].
  ///
  /// No-op if no password exists for the given provider.
  Future<void> deleteProviderPassword(String providerId) async {
    await _deleteExisting(_providerName(providerId), _providerTags);
  }

  /// Returns `true` if a password is stored for [providerId].
  Future<bool> hasProviderPassword(String providerId) async {
    final entry = await _findEntry(_providerName(providerId), _providerTags);
    return entry != null;
  }

  // ---------------------------------------------------------------------------
  // Indexer API keys
  // ---------------------------------------------------------------------------

  /// Stores a Newznab indexer [apiKey] for [indexerId].
  ///
  /// If an API key already exists for this indexer it is replaced.
  /// Returns the vault entry hash that can be used as a
  /// `kabuk:apiKeyRef` value in the knowledge store.
  Future<String> storeIndexerApiKey(
    String indexerId,
    String apiKey,
  ) async {
    await _deleteExisting(_indexerName(indexerId), _indexerTags);

    final entry = await _vault.store(
      _encode(apiKey),
      name: _indexerName(indexerId),
      tags: _indexerTags,
      encrypt: true,
    );
    return entry.hash;
  }

  /// Retrieves the API key for [indexerId], or `null` if none is stored.
  Future<String?> getIndexerApiKey(String indexerId) async {
    final entry = await _findEntry(_indexerName(indexerId), _indexerTags);
    if (entry == null) return null;

    final result = await _vault.retrieve(entry.hash);
    return switch (result) {
      Success(:final value) => _decode(value),
      Failure() => null,
    };
  }

  /// Deletes the stored API key for [indexerId].
  ///
  /// No-op if no API key exists for the given indexer.
  Future<void> deleteIndexerApiKey(String indexerId) async {
    await _deleteExisting(_indexerName(indexerId), _indexerTags);
  }

  /// Returns `true` if an API key is stored for [indexerId].
  Future<bool> hasIndexerApiKey(String indexerId) async {
    final entry = await _findEntry(_indexerName(indexerId), _indexerTags);
    return entry != null;
  }

  // ---------------------------------------------------------------------------
  // Vault hash lookup (for knowledge store references)
  // ---------------------------------------------------------------------------

  /// Returns the vault hash for the stored provider password, or `null`.
  ///
  /// Use this to populate `kabuk:passwordRef` triples in the knowledge
  /// store without reading the actual secret.
  Future<String?> getProviderPasswordHash(String providerId) async {
    final entry = await _findEntry(_providerName(providerId), _providerTags);
    return entry?.hash;
  }

  /// Returns the vault hash for the stored indexer API key, or `null`.
  ///
  /// Use this to populate `kabuk:apiKeyRef` triples in the knowledge
  /// store without reading the actual secret.
  Future<String?> getIndexerApiKeyHash(String indexerId) async {
    final entry = await _findEntry(_indexerName(indexerId), _indexerTags);
    return entry?.hash;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static const _providerTags = ['usenet', 'provider', 'credential'];
  static const _indexerTags = ['usenet', 'indexer', 'credential'];

  static String _providerName(String id) => 'usenet_provider_$id';
  static String _indexerName(String id) => 'usenet_indexer_$id';

  static Uint8List _encode(String value) =>
      Uint8List.fromList(utf8.encode(value));

  static String _decode(Uint8List bytes) => utf8.decode(bytes);

  /// Finds a single vault entry by [name] within entries matching [tags].
  Future<VaultEntry?> _findEntry(String name, List<String> tags) async {
    final entries = await _vault.list(tags: tags);
    for (final entry in entries) {
      if (entry.name == name) return entry;
    }
    return null;
  }

  /// Deletes the vault entry for [name] if one exists among [tags].
  Future<void> _deleteExisting(String name, List<String> tags) async {
    final entry = await _findEntry(name, tags);
    if (entry != null) {
      await _vault.delete(entry.hash);
    }
  }
}
