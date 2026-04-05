/// Usenet type helpers for the Kabuk knowledge store.
///
/// Provides data classes and [KnowledgeStore] extension methods for
/// Usenet-related entities: indexers (Newznab), NNTP providers,
/// search releases, and parsed NZB metadata.
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// UsenetIndexerData
// ---------------------------------------------------------------------------

/// Immutable representation of a `kabuk:UsenetIndexer` entity.
///
/// A Newznab-compatible indexer that provides search and NZB downloads.
@immutable
class UsenetIndexerData {
  /// Creates a [UsenetIndexerData] with the given field values.
  const UsenetIndexerData({
    required this.uri,
    this.name,
    this.baseUrl,
    this.apiKeyRef,
    this.enabled = true,
    this.capabilities = const [],
    this.lastSync,
  });

  /// Constructs a [UsenetIndexerData] from a subject [uri] and its [triples].
  factory UsenetIndexerData.fromTriples(String uri, List<Triple> triples) {
    final capsRaw = triples
        .where((t) => t.predicate == NS.kabukCapabilities)
        .firstOrNull
        ?.objectValue;

    return UsenetIndexerData(
      uri: uri,
      name: triples
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue,
      baseUrl: triples
          .where((t) => t.predicate == NS.schemaUrl)
          .firstOrNull
          ?.objectValue,
      apiKeyRef: triples
          .where((t) => t.predicate == NS.kabukApiKeyRef)
          .firstOrNull
          ?.objectValue,
      enabled: triples
              .where((t) => t.predicate == NS.kabukEnabled)
              .firstOrNull
              ?.objectValue !=
          'false',
      capabilities: capsRaw != null && capsRaw.isNotEmpty
          ? capsRaw.split(',')
          : const [],
      lastSync: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.kabukLastSync)
            .firstOrNull
            ?.objectValue,
      ),
    );
  }

  /// The entity URI in the knowledge store.
  final String uri;

  /// Display name of the indexer (`schema:name`).
  final String? name;

  /// Base URL for the Newznab API (`schema:url`).
  final String? baseUrl;

  /// Vault reference for the encrypted API key (`kabuk:apiKeyRef`).
  final String? apiKeyRef;

  /// Whether this indexer is active (`kabuk:enabled`).
  final bool enabled;

  /// Capability strings reported by the indexer (`kabuk:capabilities`).
  final List<String> capabilities;

  /// When this indexer was last synchronised (`kabuk:lastSync`).
  final DateTime? lastSync;
}

// ---------------------------------------------------------------------------
// UsenetProviderData
// ---------------------------------------------------------------------------

/// Immutable representation of a `kabuk:UsenetProvider` entity.
///
/// An NNTP server that provides article downloads.
@immutable
class UsenetProviderData {
  /// Creates a [UsenetProviderData] with the given field values.
  const UsenetProviderData({
    required this.uri,
    this.name,
    this.host,
    this.port,
    this.username,
    this.passwordRef,
    this.connections = 10,
    this.priority = 0,
    this.ssl = true,
    this.enabled = true,
    this.retentionDays,
  });

  /// Constructs a [UsenetProviderData] from a subject [uri] and its [triples].
  factory UsenetProviderData.fromTriples(String uri, List<Triple> triples) {
    return UsenetProviderData(
      uri: uri,
      name: triples
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue,
      host: triples
          .where((t) => t.predicate == NS.kabukHost)
          .firstOrNull
          ?.objectValue,
      port: int.tryParse(
        triples
                .where((t) => t.predicate == NS.kabukPort)
                .firstOrNull
                ?.objectValue ??
            '',
      ),
      username: triples
          .where((t) => t.predicate == NS.kabukUsername)
          .firstOrNull
          ?.objectValue,
      passwordRef: triples
          .where((t) => t.predicate == NS.kabukPasswordRef)
          .firstOrNull
          ?.objectValue,
      connections: int.tryParse(
            triples
                    .where((t) => t.predicate == NS.kabukConnections)
                    .firstOrNull
                    ?.objectValue ??
                '',
          ) ??
          10,
      priority: int.tryParse(
            triples
                    .where((t) => t.predicate == NS.kabukPriority)
                    .firstOrNull
                    ?.objectValue ??
                '',
          ) ??
          0,
      ssl: triples
              .where((t) => t.predicate == NS.kabukSsl)
              .firstOrNull
              ?.objectValue !=
          'false',
      enabled: triples
              .where((t) => t.predicate == NS.kabukEnabled)
              .firstOrNull
              ?.objectValue !=
          'false',
      retentionDays: int.tryParse(
        triples
                .where((t) => t.predicate == NS.kabukRetentionDays)
                .firstOrNull
                ?.objectValue ??
            '',
      ),
    );
  }

  /// The entity URI in the knowledge store.
  final String uri;

  /// Display name of the provider (`schema:name`).
  final String? name;

  /// NNTP server hostname (`kabuk:host`).
  final String? host;

  /// NNTP server port (`kabuk:port`).
  final int? port;

  /// Authentication username (`kabuk:username`).
  final String? username;

  /// Vault reference for the encrypted password (`kabuk:passwordRef`).
  final String? passwordRef;

  /// Number of simultaneous connections (`kabuk:connections`).
  final int connections;

  /// Download priority — lower is higher priority (`kabuk:priority`).
  final int priority;

  /// Whether the connection uses SSL/TLS (`kabuk:ssl`).
  final bool ssl;

  /// Whether this provider is active (`kabuk:enabled`).
  final bool enabled;

  /// Article retention period in days (`kabuk:retentionDays`).
  final int? retentionDays;
}

// ---------------------------------------------------------------------------
// UsenetReleaseData
// ---------------------------------------------------------------------------

/// Immutable representation of a `kabuk:UsenetRelease` entity.
///
/// A search result from an indexer representing an available Usenet post.
@immutable
class UsenetReleaseData {
  /// Creates a [UsenetReleaseData] with the given field values.
  const UsenetReleaseData({
    required this.uri,
    this.title,
    this.indexerRef,
    this.nzbUrl,
    this.sizeBytes,
    this.publishedAt,
    this.category,
    this.group,
    this.poster,
    this.description,
    this.imdbId,
    this.tvdbId,
    this.attributes = const [],
  });

  /// Constructs a [UsenetReleaseData] from a subject [uri] and its [triples].
  factory UsenetReleaseData.fromTriples(String uri, List<Triple> triples) {
    final attrsRaw = triples
        .where((t) => t.predicate == NS.kabukUsenetAttributes)
        .firstOrNull
        ?.objectValue;

    return UsenetReleaseData(
      uri: uri,
      title: triples
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue,
      indexerRef: triples
          .where((t) => t.predicate == NS.kabukIndexerRef)
          .firstOrNull
          ?.objectValue,
      nzbUrl: triples
          .where((t) => t.predicate == NS.kabukNzbUrl)
          .firstOrNull
          ?.objectValue,
      sizeBytes: int.tryParse(
        triples
                .where((t) => t.predicate == NS.kabukSizeBytes)
                .firstOrNull
                ?.objectValue ??
            '',
      ),
      publishedAt: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaDatePublished)
            .firstOrNull
            ?.objectValue,
      ),
      category: triples
          .where((t) => t.predicate == NS.kabukUsenetCategory)
          .firstOrNull
          ?.objectValue,
      group: triples
          .where((t) => t.predicate == NS.kabukNewsgroup)
          .firstOrNull
          ?.objectValue,
      poster: triples
          .where((t) => t.predicate == NS.kabukPoster)
          .firstOrNull
          ?.objectValue,
      description: triples
          .where((t) => t.predicate == NS.schemaDescription)
          .firstOrNull
          ?.objectValue,
      imdbId: triples
          .where((t) => t.predicate == NS.kabukImdbId)
          .firstOrNull
          ?.objectValue,
      tvdbId: triples
          .where((t) => t.predicate == NS.kabukTvdbId)
          .firstOrNull
          ?.objectValue,
      attributes: attrsRaw != null && attrsRaw.isNotEmpty
          ? attrsRaw.split(',')
          : const [],
    );
  }

  /// The entity URI in the knowledge store.
  final String uri;

  /// Release title (`schema:name`).
  final String? title;

  /// URI of the source `UsenetIndexer` entity (`kabuk:indexerRef`).
  final String? indexerRef;

  /// URL to download the NZB file (`kabuk:nzbUrl`).
  final String? nzbUrl;

  /// File size in bytes (`kabuk:sizeBytes`).
  final int? sizeBytes;

  /// When the release was published (`schema:datePublished`).
  final DateTime? publishedAt;

  /// Usenet content category (`kabuk:usenetCategory`).
  final String? category;

  /// Usenet newsgroup name (`kabuk:newsgroup`).
  final String? group;

  /// The Usenet poster/uploader (`kabuk:poster`).
  final String? poster;

  /// Free-text description (`schema:description`).
  final String? description;

  /// IMDB identifier for movie/TV content (`kabuk:imdbId`).
  final String? imdbId;

  /// TVDB identifier for TV content (`kabuk:tvdbId`).
  final String? tvdbId;

  /// Quality attributes such as `2160p`, `HDR` (`kabuk:usenetAttributes`).
  final List<String> attributes;
}

// ---------------------------------------------------------------------------
// NzbFileData
// ---------------------------------------------------------------------------

/// Immutable representation of a `kabuk:NzbFile` entity.
///
/// Parsed metadata from an NZB XML file.
@immutable
class NzbFileData {
  /// Creates an [NzbFileData] with the given field values.
  const NzbFileData({
    required this.uri,
    this.title,
    this.releaseRef,
    this.totalBytes,
    this.fileCount,
    this.segmentCount,
    this.hasPar2 = false,
    this.hasRar = false,
    this.contentType,
  });

  /// Constructs an [NzbFileData] from a subject [uri] and its [triples].
  factory NzbFileData.fromTriples(String uri, List<Triple> triples) {
    return NzbFileData(
      uri: uri,
      title: triples
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue,
      releaseRef: triples
          .where((t) => t.predicate == NS.kabukReleaseRef)
          .firstOrNull
          ?.objectValue,
      totalBytes: int.tryParse(
        triples
                .where((t) => t.predicate == NS.kabukTotalBytes)
                .firstOrNull
                ?.objectValue ??
            '',
      ),
      fileCount: int.tryParse(
        triples
                .where((t) => t.predicate == NS.kabukFileCount)
                .firstOrNull
                ?.objectValue ??
            '',
      ),
      segmentCount: int.tryParse(
        triples
                .where((t) => t.predicate == NS.kabukSegmentCount)
                .firstOrNull
                ?.objectValue ??
            '',
      ),
      hasPar2: triples
              .where((t) => t.predicate == NS.kabukHasPar2)
              .firstOrNull
              ?.objectValue ==
          'true',
      hasRar: triples
              .where((t) => t.predicate == NS.kabukHasRar)
              .firstOrNull
              ?.objectValue ==
          'true',
      contentType: triples
          .where((t) => t.predicate == NS.kabukContentType)
          .firstOrNull
          ?.objectValue,
    );
  }

  /// The entity URI in the knowledge store.
  final String uri;

  /// Display title (`schema:name`).
  final String? title;

  /// URI of the source `UsenetRelease` entity (`kabuk:releaseRef`).
  final String? releaseRef;

  /// Total size in bytes (`kabuk:totalBytes`).
  final int? totalBytes;

  /// Number of files in the NZB (`kabuk:fileCount`).
  final int? fileCount;

  /// Number of segments in the NZB (`kabuk:segmentCount`).
  final int? segmentCount;

  /// Whether the NZB contains PAR2 recovery files (`kabuk:hasPar2`).
  final bool hasPar2;

  /// Whether the NZB contains RAR archives (`kabuk:hasRar`).
  final bool hasRar;

  /// Detected MIME type of the content (`kabuk:contentType`).
  final String? contentType;
}

// ---------------------------------------------------------------------------
// Extension methods
// ---------------------------------------------------------------------------

/// Convenience methods for working with Usenet entities in the knowledge store.
extension KnowledgeStoreUsenetExtension on KnowledgeStore {
  // ── Indexer CRUD ──────────────────────────────────────────────────────────

  /// Creates a new `UsenetIndexer` entity and returns its URI.
  Future<String> createUsenetIndexer({
    required String name,
    required String baseUrl,
    required String apiKeyRef,
    bool enabled = true,
    List<String> capabilities = const [],
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('UsenetIndexer');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.kabukUsenetIndexer,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      await ctx.set(uri, NS.schemaUrl, baseUrl);
      await ctx.set(uri, NS.kabukApiKeyRef, apiKeyRef);
      await ctx.set(uri, NS.kabukEnabled, enabled.toString());
      if (capabilities.isNotEmpty) {
        await ctx.set(uri, NS.kabukCapabilities, capabilities.join(','));
      }
      await ctx.set(
        uri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );
      return uri;
    });
  }

  /// Updates mutable fields of an existing `UsenetIndexer` entity.
  Future<void> updateUsenetIndexer(
    String uri, {
    String? name,
    String? baseUrl,
    String? apiKeyRef,
    bool? enabled,
    List<String>? capabilities,
    DateTime? lastSync,
  }) {
    return mutate((ctx) async {
      if (name != null) await ctx.set(uri, NS.schemaName, name);
      if (baseUrl != null) await ctx.set(uri, NS.schemaUrl, baseUrl);
      if (apiKeyRef != null) {
        await ctx.set(uri, NS.kabukApiKeyRef, apiKeyRef);
      }
      if (enabled != null) {
        await ctx.set(uri, NS.kabukEnabled, enabled.toString());
      }
      if (capabilities != null) {
        await ctx.set(uri, NS.kabukCapabilities, capabilities.join(','));
      }
      if (lastSync != null) {
        await ctx.set(uri, NS.kabukLastSync, lastSync.toIso8601String());
      }
    });
  }

  /// Deletes a `UsenetIndexer` entity by [uri].
  Future<void> deleteUsenetIndexer(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }

  /// Lists `UsenetIndexer` entities, optionally filtered by [enabled] state.
  Future<List<UsenetIndexerData>> queryUsenetIndexers({
    bool? enabled,
  }) async {
    var builder = query()
        .where(NS.rdfType, equals: NS.kabukUsenetIndexer)
        .orderBy(NS.schemaName);

    if (enabled != null) {
      builder = builder.where(NS.kabukEnabled, equals: enabled.toString());
    }

    final typeTriples = await builder.execute();
    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    return [
      for (final uri in uris)
        if (allTriples[uri] case final triples? when triples.isNotEmpty)
          UsenetIndexerData.fromTriples(uri, triples),
    ];
  }

  /// Retrieves a single `UsenetIndexer` by [uri], or `null` if not found.
  Future<UsenetIndexerData?> getUsenetIndexer(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return UsenetIndexerData.fromTriples(uri, triples);
  }

  // ── Provider CRUD ─────────────────────────────────────────────────────────

  /// Creates a new `UsenetProvider` entity and returns its URI.
  Future<String> createUsenetProvider({
    required String name,
    required String host,
    required int port,
    required String username,
    required String passwordRef,
    int connections = 10,
    int priority = 0,
    bool ssl = true,
    bool enabled = true,
    int? retentionDays,
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('UsenetProvider');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.kabukUsenetProvider,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      await ctx.set(uri, NS.kabukHost, host);
      await ctx.set(uri, NS.kabukPort, port.toString());
      await ctx.set(uri, NS.kabukUsername, username);
      await ctx.set(uri, NS.kabukPasswordRef, passwordRef);
      await ctx.set(uri, NS.kabukConnections, connections.toString());
      await ctx.set(uri, NS.kabukPriority, priority.toString());
      await ctx.set(uri, NS.kabukSsl, ssl.toString());
      await ctx.set(uri, NS.kabukEnabled, enabled.toString());
      if (retentionDays != null) {
        await ctx.set(uri, NS.kabukRetentionDays, retentionDays.toString());
      }
      await ctx.set(
        uri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );
      return uri;
    });
  }

  /// Updates mutable fields of an existing `UsenetProvider` entity.
  Future<void> updateUsenetProvider(
    String uri, {
    String? name,
    String? host,
    int? port,
    String? username,
    String? passwordRef,
    int? connections,
    int? priority,
    bool? ssl,
    bool? enabled,
    int? retentionDays,
  }) {
    return mutate((ctx) async {
      if (name != null) await ctx.set(uri, NS.schemaName, name);
      if (host != null) await ctx.set(uri, NS.kabukHost, host);
      if (port != null) await ctx.set(uri, NS.kabukPort, port.toString());
      if (username != null) await ctx.set(uri, NS.kabukUsername, username);
      if (passwordRef != null) {
        await ctx.set(uri, NS.kabukPasswordRef, passwordRef);
      }
      if (connections != null) {
        await ctx.set(uri, NS.kabukConnections, connections.toString());
      }
      if (priority != null) {
        await ctx.set(uri, NS.kabukPriority, priority.toString());
      }
      if (ssl != null) await ctx.set(uri, NS.kabukSsl, ssl.toString());
      if (enabled != null) {
        await ctx.set(uri, NS.kabukEnabled, enabled.toString());
      }
      if (retentionDays != null) {
        await ctx.set(uri, NS.kabukRetentionDays, retentionDays.toString());
      }
    });
  }

  /// Deletes a `UsenetProvider` entity by [uri].
  Future<void> deleteUsenetProvider(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }

  /// Lists `UsenetProvider` entities, optionally filtered by [enabled] state.
  Future<List<UsenetProviderData>> queryUsenetProviders({
    bool? enabled,
  }) async {
    var builder = query()
        .where(NS.rdfType, equals: NS.kabukUsenetProvider)
        .orderBy(NS.schemaName);

    if (enabled != null) {
      builder = builder.where(NS.kabukEnabled, equals: enabled.toString());
    }

    final typeTriples = await builder.execute();
    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    return [
      for (final uri in uris)
        if (allTriples[uri] case final triples? when triples.isNotEmpty)
          UsenetProviderData.fromTriples(uri, triples),
    ];
  }

  /// Retrieves a single `UsenetProvider` by [uri], or `null` if not found.
  Future<UsenetProviderData?> getUsenetProvider(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return UsenetProviderData.fromTriples(uri, triples);
  }

  // ── Release CRUD ──────────────────────────────────────────────────────────

  /// Creates a new `UsenetRelease` entity and returns its URI.
  Future<String> createUsenetRelease({
    required String title,
    required String indexerRef,
    required String nzbUrl,
    required int sizeBytes,
    required DateTime publishedAt,
    required String category,
    String? group,
    String? poster,
    String? description,
    String? imdbId,
    String? tvdbId,
    List<String> attributes = const [],
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('UsenetRelease');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.kabukUsenetRelease,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, title);
      await ctx.set(
        uri,
        NS.kabukIndexerRef,
        indexerRef,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.kabukNzbUrl, nzbUrl);
      await ctx.set(uri, NS.kabukSizeBytes, sizeBytes.toString());
      await ctx.set(
        uri,
        NS.schemaDatePublished,
        publishedAt.toIso8601String(),
      );
      await ctx.set(uri, NS.kabukUsenetCategory, category);
      if (group != null) await ctx.set(uri, NS.kabukNewsgroup, group);
      if (poster != null) await ctx.set(uri, NS.kabukPoster, poster);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      if (imdbId != null) await ctx.set(uri, NS.kabukImdbId, imdbId);
      if (tvdbId != null) await ctx.set(uri, NS.kabukTvdbId, tvdbId);
      if (attributes.isNotEmpty) {
        await ctx.set(uri, NS.kabukUsenetAttributes, attributes.join(','));
      }
      return uri;
    });
  }

  /// Lists `UsenetRelease` entities with optional filters.
  ///
  /// [category] — filter by Usenet category.
  /// [indexerRef] — filter by source indexer URI.
  /// [limit] — maximum number of results (default 50).
  Future<List<UsenetReleaseData>> queryUsenetReleases({
    String? category,
    String? indexerRef,
    int limit = 50,
  }) async {
    var builder = query()
        .where(NS.rdfType, equals: NS.kabukUsenetRelease)
        .orderBy(NS.schemaDatePublished, descending: true)
        .limit(limit);

    if (category != null) {
      builder = builder.where(NS.kabukUsenetCategory, equals: category);
    }
    if (indexerRef != null) {
      builder = builder.where(NS.kabukIndexerRef, equals: indexerRef);
    }

    final typeTriples = await builder.execute();
    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    return [
      for (final uri in uris)
        if (allTriples[uri] case final triples? when triples.isNotEmpty)
          UsenetReleaseData.fromTriples(uri, triples),
    ];
  }

  /// Retrieves a single `UsenetRelease` by [uri], or `null` if not found.
  Future<UsenetReleaseData?> getUsenetRelease(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return UsenetReleaseData.fromTriples(uri, triples);
  }

  // ── NZB File CRUD ─────────────────────────────────────────────────────────

  /// Creates a new `NzbFile` entity and returns its URI.
  Future<String> createNzbFile({
    required String title,
    required String releaseRef,
    required int totalBytes,
    required int fileCount,
    required int segmentCount,
    bool hasPar2 = false,
    bool hasRar = false,
    String? contentType,
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('NzbFile');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.kabukNzbFile,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, title);
      await ctx.set(
        uri,
        NS.kabukReleaseRef,
        releaseRef,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.kabukTotalBytes, totalBytes.toString());
      await ctx.set(uri, NS.kabukFileCount, fileCount.toString());
      await ctx.set(uri, NS.kabukSegmentCount, segmentCount.toString());
      await ctx.set(uri, NS.kabukHasPar2, hasPar2.toString());
      await ctx.set(uri, NS.kabukHasRar, hasRar.toString());
      if (contentType != null) {
        await ctx.set(uri, NS.kabukContentType, contentType);
      }
      return uri;
    });
  }

  /// Retrieves a single `NzbFile` by [uri], or `null` if not found.
  Future<NzbFileData?> getNzbFile(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return NzbFileData.fromTriples(uri, triples);
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

DateTime? _tryParseDateTime(String? value) =>
    value == null ? null : DateTime.tryParse(value);
