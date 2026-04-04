/// Concrete [UsenetService] implementation wiring together all Usenet
/// subsystems: Newznab indexer search, NNTP connection pooling, NZB
/// parsing, streaming pipeline, and cache management.
///
/// Lazily creates its subsystems ([NntpConnectionPool], [StreamCache],
/// [StreamServer]) on first use and delegates credential access to the
/// [VaultService] via stored vault-hash references (`passwordRef`,
/// `apiKeyRef`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/types/usenet.dart';
import 'package:kabuk/services/mesh.dart';
import 'package:kabuk/services/usenet.dart';
import 'package:kabuk/services/vault.dart';

import 'newznab_client.dart';
import 'nntp_client.dart';
import 'nntp_pool.dart';
import 'nzb_parser.dart' as nzb_parser;
import 'stream_cache.dart';
import 'stream_pipeline.dart';
import 'stream_server.dart';

/// Shared (cross-platform) implementation of [UsenetService].
///
/// Orchestrates indexer management (CRUD via [KnowledgeStore], search via
/// [NewznabClient]), provider management (CRUD via [KnowledgeStore],
/// connections via [NntpConnectionPool]), NZB parsing, streaming via
/// [StreamPipeline] + [StreamServer], download via [StreamPipeline], and
/// cache management via [StreamCache].
class UsenetServiceImpl implements UsenetService {
  /// Creates a [UsenetServiceImpl].
  ///
  /// [cachePath] defaults to `'usenet_cache'` and is passed to
  /// [StreamCache] on first use.
  UsenetServiceImpl({
    required KnowledgeStore store,
    required VaultService vault,
    required MeshService mesh,
    String? cachePath,
  })  : _store = store,
        _vault = vault,
        _mesh = mesh,
        _cachePath = cachePath ?? 'usenet_cache';

  final KnowledgeStore _store;
  final VaultService _vault;
  final MeshService _mesh;
  final String _cachePath;

  // -- Lazy subsystems -------------------------------------------------------

  NntpConnectionPool? _pool;
  StreamCache? _cache;
  StreamServer? _server;
  bool _cacheInitialized = false;

  /// The NNTP connection pool, created lazily.
  NntpConnectionPool get _ensurePool => _pool ??= NntpConnectionPool();

  /// The segment/file cache, created lazily.
  StreamCache get _ensureCache => _cache ??= StreamCache(basePath: _cachePath);

  /// The local HTTP streaming server, created lazily.
  StreamServer get _ensureServer => _server ??= StreamServer();

  /// NZB parser instance (stateless, const-constructible).
  static const nzb_parser.NzbParser _nzbParser = nzb_parser.NzbParser();

  /// Active streaming pipelines keyed by session ID.
  final Map<String, StreamPipeline> _pipelines = {};

  // ---------------------------------------------------------------------------
  // Indexer management
  // ---------------------------------------------------------------------------

  @override
  Future<Result<UsenetIndexer>> addIndexer(UsenetIndexer indexer) async {
    try {
      final uri = await _store.createUsenetIndexer(
        name: indexer.name,
        baseUrl: indexer.baseUrl,
        apiKeyRef: indexer.apiKeyRef,
        enabled: indexer.enabled,
        capabilities: indexer.capabilities,
      );

      return Result.success(UsenetIndexer(
        id: uri,
        name: indexer.name,
        baseUrl: indexer.baseUrl,
        apiKeyRef: indexer.apiKeyRef,
        enabled: indexer.enabled,
        capabilities: indexer.capabilities,
      ));
    } catch (e, st) {
      dev.log('addIndexer failed', error: e, stackTrace: st);
      return Result.failure(
        UsenetIndexerError(indexer.id, 'Failed to add indexer: $e'),
      );
    }
  }

  @override
  Future<Result<void>> removeIndexer(String indexerId) async {
    try {
      // Look up the indexer to get its vault reference before deleting.
      final data = await _store.getUsenetIndexer(indexerId);
      if (data == null) {
        return Result.failure(
          UsenetIndexerError(indexerId, 'Indexer not found'),
        );
      }

      // Remove the API key from the vault.
      if (data.apiKeyRef != null && data.apiKeyRef!.isNotEmpty) {
        await _vault.delete(data.apiKeyRef!);
      }

      // Delete the entity from the knowledge store.
      await _store.deleteUsenetIndexer(indexerId);
      return const Result.success(null);
    } catch (e, st) {
      dev.log('removeIndexer failed', error: e, stackTrace: st);
      return Result.failure(
        UsenetIndexerError(indexerId, 'Failed to remove indexer: $e'),
      );
    }
  }

  @override
  Future<List<UsenetIndexer>> getIndexers() async {
    try {
      final data = await _store.queryUsenetIndexers();
      return data.map(_indexerFromData).toList();
    } catch (e, st) {
      dev.log('getIndexers failed', error: e, stackTrace: st);
      return const [];
    }
  }

  @override
  Future<Result<bool>> testIndexer(String indexerId) async {
    try {
      final data = await _store.getUsenetIndexer(indexerId);
      if (data == null) {
        return Result.failure(
          UsenetIndexerError(indexerId, 'Indexer not found'),
        );
      }

      final apiKey = await _resolveVaultSecret(data.apiKeyRef);
      if (apiKey == null) {
        return Result.failure(
          UsenetIndexerError(indexerId, 'API key not found in vault'),
        );
      }

      final client = NewznabClient(
        baseUrl: data.baseUrl ?? '',
        apiKey: apiKey,
      );

      try {
        await client.capabilities();
        return const Result.success(true);
      } on NewznabException catch (e) {
        return Result.failure(
          UsenetIndexerError(indexerId, 'Test failed: ${e.message}'),
        );
      }
    } catch (e, st) {
      dev.log('testIndexer failed', error: e, stackTrace: st);
      return Result.failure(
        UsenetIndexerError(indexerId, 'Test failed: $e'),
      );
    }
  }

  @override
  Future<Result<bool>> testIndexerDirect({
    required String baseUrl,
    required String apiKey,
  }) async {
    try {
      final client = NewznabClient(baseUrl: baseUrl, apiKey: apiKey);
      await client.capabilities();
      return const Result.success(true);
    } on NewznabException catch (e) {
      return Result.failure(
        UsenetIndexerError('direct', 'Test failed: ${e.message}'),
      );
    } catch (e, st) {
      dev.log('testIndexerDirect failed', error: e, stackTrace: st);
      return Result.failure(
        UsenetIndexerError('direct', 'Test failed: $e'),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Provider management
  // ---------------------------------------------------------------------------

  @override
  Future<Result<UsenetProvider>> addProvider(UsenetProvider provider) async {
    try {
      final uri = await _store.createUsenetProvider(
        name: provider.name,
        host: provider.host,
        port: provider.port,
        username: provider.username,
        passwordRef: provider.passwordRef,
        connections: provider.connections,
        priority: provider.priority,
        ssl: provider.ssl,
        enabled: provider.enabled,
        retentionDays:
            provider.retentionDays > 0 ? provider.retentionDays : null,
      );

      // Register in the pool if the provider is enabled.
      if (provider.enabled) {
        await _addProviderToPool(
          uri: uri,
          provider: provider,
          passwordRef: provider.passwordRef,
        );
      }

      return Result.success(UsenetProvider(
        id: uri,
        name: provider.name,
        host: provider.host,
        port: provider.port,
        username: provider.username,
        passwordRef: provider.passwordRef,
        connections: provider.connections,
        priority: provider.priority,
        ssl: provider.ssl,
        enabled: provider.enabled,
        retentionDays: provider.retentionDays,
      ));
    } catch (e, st) {
      dev.log('addProvider failed', error: e, stackTrace: st);
      return Result.failure(
        UsenetProviderError(provider.id, 'Failed to add provider: $e'),
      );
    }
  }

  @override
  Future<Result<void>> removeProvider(String providerId) async {
    try {
      final data = await _store.getUsenetProvider(providerId);
      if (data == null) {
        return Result.failure(
          UsenetProviderError(providerId, 'Provider not found'),
        );
      }

      // Remove from the NNTP pool.
      await _ensurePool.removeProvider(providerId);

      // Remove the password from the vault.
      if (data.passwordRef != null && data.passwordRef!.isNotEmpty) {
        await _vault.delete(data.passwordRef!);
      }

      // Delete from the knowledge store.
      await _store.deleteUsenetProvider(providerId);
      return const Result.success(null);
    } catch (e, st) {
      dev.log('removeProvider failed', error: e, stackTrace: st);
      return Result.failure(
        UsenetProviderError(providerId, 'Failed to remove provider: $e'),
      );
    }
  }

  @override
  Future<List<UsenetProvider>> getProviders() async {
    try {
      final data = await _store.queryUsenetProviders();
      return data.map(_providerFromData).toList();
    } catch (e, st) {
      dev.log('getProviders failed', error: e, stackTrace: st);
      return const [];
    }
  }

  @override
  Future<Result<bool>> testProvider(String providerId) async {
    try {
      final data = await _store.getUsenetProvider(providerId);
      if (data == null) {
        return Result.failure(
          UsenetProviderError(providerId, 'Provider not found'),
        );
      }

      final password = await _resolveVaultSecret(data.passwordRef);
      if (password == null) {
        return Result.failure(
          UsenetProviderError(providerId, 'Password not found in vault'),
        );
      }

      final client = NntpClient(
        host: data.host ?? '',
        port: data.port ?? (data.ssl ? 563 : 119),
        ssl: data.ssl,
      );

      try {
        await client.connect();
        await client.authenticate(data.username ?? '', password);
        await client.quit();
        client.dispose();
        return const Result.success(true);
      } catch (e) {
        client.dispose();
        final msg = e is NntpException ? e.message : '$e';
        return Result.failure(
          UsenetProviderError(providerId, 'Test failed: $msg'),
        );
      }
    } catch (e, st) {
      dev.log('testProvider failed', error: e, stackTrace: st);
      return Result.failure(
        UsenetProviderError(providerId, 'Test failed: $e'),
      );
    }
  }

  @override
  Future<Result<bool>> testProviderDirect({
    required String host,
    required int port,
    required bool ssl,
    required String username,
    required String password,
  }) async {
    final client = NntpClient(host: host, port: port, ssl: ssl);
    try {
      await client.connect();
      await client.authenticate(username, password);
      await client.quit();
      client.dispose();
      return const Result.success(true);
    } catch (e) {
      client.dispose();
      final msg = e is NntpException ? e.message : '$e';
      return Result.failure(
        UsenetProviderError('direct', 'Test failed: $msg'),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  @override
  Future<Result<List<UsenetRelease>>> search(
    String query, {
    List<String>? indexerIds,
    UsenetCategory? category,
    int? minSizeBytes,
    int? maxSizeBytes,
    int? limit,
  }) async {
    try {
      final allIndexers = await _store.queryUsenetIndexers();

      // Filter to requested indexer IDs or use all enabled.
      final indexers = indexerIds != null
          ? allIndexers
              .where((i) => indexerIds.contains(i.uri) && i.enabled)
              .toList()
          : allIndexers.where((i) => i.enabled).toList();

      if (indexers.isEmpty) {
        return const Result.failure(
          UsenetConnectionFailed(
            'No enabled indexers configured. Add indexers in Settings.',
          ),
        );
      }

      // Search every indexer concurrently.
      final futures = indexers.map(
        (indexer) => _searchSingleIndexer(indexer, query, category, limit),
      );
      final batches = await Future.wait(futures);

      var results = batches.expand((list) => list).toList();

      // Apply size filters.
      if (minSizeBytes != null) {
        results = results.where((r) => r.sizeBytes >= minSizeBytes).toList();
      }
      if (maxSizeBytes != null) {
        results = results.where((r) => r.sizeBytes <= maxSizeBytes).toList();
      }

      // Deduplicate by normalised title.
      final seen = <String>{};
      final deduped = <UsenetRelease>[];
      for (final release in results) {
        if (seen.add(release.title.toLowerCase())) {
          deduped.add(release);
        }
      }

      // Apply result limit.
      final output = limit != null && deduped.length > limit
          ? deduped.sublist(0, limit)
          : deduped;

      return Result.success(output);
    } catch (e, st) {
      dev.log('search failed', error: e, stackTrace: st);
      return Result.failure(UsenetConnectionFailed('Search failed: $e'));
    }
  }

  // ---------------------------------------------------------------------------
  // NZB operations
  // ---------------------------------------------------------------------------

  @override
  Future<Result<NzbFile>> fetchNzb(String url) async {
    try {
      final response = await _mesh.get(Uri.parse(url));
      if (response.statusCode != 200) {
        return Result.failure(
          UsenetNzbParseFailed(
            'HTTP ${response.statusCode} fetching NZB from $url',
          ),
        );
      }
      return parseNzb(response.body);
    } catch (e, st) {
      dev.log('fetchNzb failed', error: e, stackTrace: st);
      return Result.failure(UsenetNzbParseFailed('Fetch failed: $e'));
    }
  }

  @override
  Result<NzbFile> parseNzb(String content) {
    try {
      final doc = _nzbParser.parse(content);
      return Result.success(_nzbFileFromDocument(doc));
    } on FormatException catch (e) {
      return Result.failure(UsenetNzbParseFailed(e.message));
    } catch (e) {
      return Result.failure(UsenetNzbParseFailed('$e'));
    }
  }

  // ---------------------------------------------------------------------------
  // Streaming
  // ---------------------------------------------------------------------------

  @override
  Future<Result<StreamSession>> startStream(NzbFile nzb) async {
    try {
      await _ensureProvidersInPool();
      await _initCacheOnce();

      // Convert to parser-layer types for the pipeline.
      final doc = _documentFromNzbFile(nzb);

      final pipeline = StreamPipeline(
        pool: _ensurePool,
        cache: _ensureCache,
      );

      await pipeline.start(doc);

      final sessionId = 'stream_${DateTime.now().millisecondsSinceEpoch}';

      final session = await _ensureServer.addSession(
        sessionId: sessionId,
        title: nzb.title,
        pipeline: pipeline,
      );

      _pipelines[sessionId] = pipeline;

      return Result.success(session);
    } catch (e, st) {
      dev.log('startStream failed', error: e, stackTrace: st);
      return Result.failure(
        UsenetStreamError('', 'Failed to start stream: $e'),
      );
    }
  }

  @override
  Future<Result<void>> stopStream(String sessionId) async {
    try {
      _pipelines.remove(sessionId);
      await _ensureServer.removeSession(sessionId);
      return const Result.success(null);
    } catch (e, st) {
      dev.log('stopStream failed', error: e, stackTrace: st);
      return Result.failure(
        UsenetStreamError(sessionId, 'Failed to stop stream: $e'),
      );
    }
  }

  @override
  Future<List<StreamSession>> getActiveStreams() async {
    try {
      return _ensureServer.activeSessions;
    } catch (e, st) {
      dev.log('getActiveStreams failed', error: e, stackTrace: st);
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------------

  @override
  Stream<DownloadProgress> downloadContent(
    NzbFile nzb, {
    required String outputName,
  }) async* {
    final totalSegments =
        nzb.files.fold<int>(0, (sum, f) => sum + f.segments.length);

    try {
      await _ensureProvidersInPool();
      await _initCacheOnce();

      final doc = _documentFromNzbFile(nzb);

      final pipeline = StreamPipeline(
        pool: _ensurePool,
        cache: _ensureCache,
      );

      yield DownloadProgress(
        bytesDownloaded: 0,
        totalBytes: nzb.totalBytes,
        state: DownloadState.downloading,
        segmentsFetched: 0,
        totalSegments: totalSegments,
      );

      await pipeline.start(doc);

      await for (final event in pipeline.events) {
        switch (event) {
          case StreamPipelineProgress(
              :final bytesDownloaded,
              :final totalBytes,
              :final segmentsFetched,
              :final totalSegments,
            ):
            yield DownloadProgress(
              bytesDownloaded: bytesDownloaded,
              totalBytes: totalBytes,
              state: DownloadState.downloading,
              segmentsFetched: segmentsFetched,
              totalSegments: totalSegments,
            );

          case StreamPipelineDone():
            yield DownloadProgress(
              bytesDownloaded: nzb.totalBytes,
              totalBytes: nzb.totalBytes,
              state: DownloadState.postProcessing,
              segmentsFetched: totalSegments,
              totalSegments: totalSegments,
            );

            await pipeline.saveContent(outputName);

            yield DownloadProgress(
              bytesDownloaded: nzb.totalBytes,
              totalBytes: nzb.totalBytes,
              state: DownloadState.completed,
              segmentsFetched: totalSegments,
              totalSegments: totalSegments,
            );
            await pipeline.dispose();
            return;

          case StreamPipelineError(:final message, :final fatal):
            if (fatal) {
              yield DownloadProgress(
                bytesDownloaded: 0,
                totalBytes: nzb.totalBytes,
                state: DownloadState.failed,
                currentFile: message,
              );
              await pipeline.dispose();
              return;
            }

          case StreamPipelineBuffering() ||
               StreamPipelineReady() ||
               StreamPipelineSeek():
            // Informational events — no user-facing progress change.
            break;
        }
      }
    } catch (e, st) {
      dev.log('downloadContent failed', error: e, stackTrace: st);
      yield DownloadProgress(
        bytesDownloaded: 0,
        totalBytes: nzb.totalBytes,
        state: DownloadState.failed,
        currentFile: '$e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Cache management
  // ---------------------------------------------------------------------------

  @override
  Future<int> getCacheSize() async {
    try {
      await _initCacheOnce();
      final stats = await _ensureCache.getStats();
      return stats.totalBytes;
    } catch (e, st) {
      dev.log('getCacheSize failed', error: e, stackTrace: st);
      return 0;
    }
  }

  @override
  Future<void> clearCache() async {
    try {
      await _initCacheOnce();
      await _ensureCache.clear();
    } catch (e, st) {
      dev.log('clearCache failed', error: e, stackTrace: st);
    }
  }

  @override
  Future<void> setCacheLimit(int bytes) async {
    try {
      await _initCacheOnce();
      await _ensureCache.setMaxSize(bytes);
    } catch (e, st) {
      dev.log('setCacheLimit failed', error: e, stackTrace: st);
    }
  }

  // ---------------------------------------------------------------------------
  // Private — vault helper
  // ---------------------------------------------------------------------------

  /// Resolves a vault hash reference to its plaintext UTF-8 value.
  ///
  /// Returns `null` when [ref] is null/empty or the vault entry is missing.
  Future<String?> _resolveVaultSecret(String? ref) async {
    if (ref == null || ref.isEmpty) return null;
    final result = await _vault.retrieve(ref);
    return switch (result) {
      Success(:final value) => utf8.decode(value),
      Failure() => null,
    };
  }

  @override
  Future<String?> resolveSecret(String? vaultRef) => _resolveVaultSecret(vaultRef);

  // ---------------------------------------------------------------------------
  // Private — pool bootstrap
  // ---------------------------------------------------------------------------

  /// Registers all enabled providers in the [NntpConnectionPool] that are
  /// not already present.
  Future<void> _ensureProvidersInPool() async {
    final allProviders = await _store.queryUsenetProviders();
    final providers = allProviders.where((p) => p.enabled).toList();
    for (final p in providers) {
      try {
        final password = await _resolveVaultSecret(p.passwordRef);
        if (password == null) continue;

        await _ensurePool.addProvider(ProviderConfig(
          id: p.uri,
          name: p.name ?? '',
          host: p.host ?? '',
          port: p.port ?? (p.ssl ? 563 : 119),
          username: p.username ?? '',
          password: password,
          connections: p.connections,
          priority: p.priority,
          ssl: p.ssl,
          retentionDays: p.retentionDays ?? 0,
        ));
      } on StateError {
        // Already registered — skip.
      } catch (e) {
        dev.log('Failed to load provider ${p.uri} into pool: $e');
      }
    }
  }

  /// Adds a single provider to the pool using its vault-stored password.
  Future<void> _addProviderToPool({
    required String uri,
    required UsenetProvider provider,
    required String passwordRef,
  }) async {
    final password = await _resolveVaultSecret(passwordRef);
    if (password == null) return;

    try {
      await _ensurePool.addProvider(ProviderConfig(
        id: uri,
        name: provider.name,
        host: provider.host,
        port: provider.port,
        username: provider.username,
        password: password,
        connections: provider.connections,
        priority: provider.priority,
        ssl: provider.ssl,
        retentionDays: provider.retentionDays,
      ));
    } on StateError {
      // Already registered — skip.
    }
  }

  /// Initialises the [StreamCache] once. Subsequent calls are a no-op.
  Future<void> _initCacheOnce() async {
    if (_cacheInitialized) return;
    await _ensureCache.initialize();
    _cacheInitialized = true;
  }

  // ---------------------------------------------------------------------------
  // Private — search helper
  // ---------------------------------------------------------------------------

  /// Queries a single indexer and returns [UsenetRelease] objects.
  Future<List<UsenetRelease>> _searchSingleIndexer(
    UsenetIndexerData indexer,
    String query,
    UsenetCategory? category,
    int? limit,
  ) async {
    try {
      final apiKey = await _resolveVaultSecret(indexer.apiKeyRef);
      if (apiKey == null) {
        dev.log(
          'API key not found in vault for indexer ${indexer.uri} '
          '(ref: ${indexer.apiKeyRef})',
        );
        return const [];
      }

      final client = NewznabClient(
        baseUrl: indexer.baseUrl ?? '',
        apiKey: apiKey,
      );

      final result = await client.search(
        query,
        categories:
            category != null ? _categoryToNewznabIds(category) : null,
        limit: limit ?? 100,
      );

      return result.items
          .map((item) => _releaseFromNewznabItem(item, indexer.uri))
          .toList();
    } on NewznabException catch (e) {
      dev.log('Search on ${indexer.uri} failed: ${e.message}');
      return const [];
    } catch (e) {
      dev.log('Search on ${indexer.uri} failed: $e');
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Private — type conversions (knowledge store ↔ service layer)
  // ---------------------------------------------------------------------------

  /// Converts knowledge-store [UsenetIndexerData] to service-layer
  /// [UsenetIndexer].
  UsenetIndexer _indexerFromData(UsenetIndexerData d) => UsenetIndexer(
        id: d.uri,
        name: d.name ?? '',
        baseUrl: d.baseUrl ?? '',
        apiKeyRef: d.apiKeyRef ?? '',
        enabled: d.enabled,
        capabilities: d.capabilities,
      );

  /// Converts knowledge-store [UsenetProviderData] to service-layer
  /// [UsenetProvider].
  UsenetProvider _providerFromData(UsenetProviderData d) => UsenetProvider(
        id: d.uri,
        name: d.name ?? '',
        host: d.host ?? '',
        port: d.port ?? 563,
        username: d.username ?? '',
        passwordRef: d.passwordRef ?? '',
        connections: d.connections,
        priority: d.priority,
        ssl: d.ssl,
        enabled: d.enabled,
        retentionDays: d.retentionDays ?? 0,
      );

  // ---------------------------------------------------------------------------
  // Private — type conversions (Newznab ↔ service layer)
  // ---------------------------------------------------------------------------

  /// Converts a [NewznabItem] to a service-layer [UsenetRelease].
  UsenetRelease _releaseFromNewznabItem(NewznabItem item, String indexerId) =>
      UsenetRelease(
        id: item.guid,
        title: item.title,
        indexerId: indexerId,
        nzbUrl: item.nzbUrl,
        sizeBytes: item.sizeBytes,
        publishedAt: item.publishedAt,
        category: _newznabIdToCategory(item.categoryId),
        group: item.group,
        poster: item.poster,
        description: item.description,
        imdbId: item.imdbId,
        tvdbId: item.tvdbId,
        attributes: item.attributes,
      );

  /// Maps a [UsenetCategory] to the corresponding Newznab category IDs.
  static List<int> _categoryToNewznabIds(UsenetCategory c) => switch (c) {
        UsenetCategory.movies => [NewznabCategoryId.movies],
        UsenetCategory.tvShows => [NewznabCategoryId.tv],
        UsenetCategory.music => [NewznabCategoryId.audio],
        UsenetCategory.games => [NewznabCategoryId.console],
        UsenetCategory.software => [NewznabCategoryId.pc],
        UsenetCategory.books => [NewznabCategoryId.books],
        UsenetCategory.audio => [NewznabCategoryId.audio],
        UsenetCategory.other => [NewznabCategoryId.other],
      };

  /// Maps a Newznab numeric category ID back to [UsenetCategory].
  static UsenetCategory _newznabIdToCategory(int? id) {
    if (id == null) return UsenetCategory.other;
    final major = (id ~/ 1000) * 1000;
    return switch (major) {
      NewznabCategoryId.movies => UsenetCategory.movies,
      NewznabCategoryId.tv => UsenetCategory.tvShows,
      NewznabCategoryId.audio => UsenetCategory.music,
      NewznabCategoryId.console => UsenetCategory.games,
      NewznabCategoryId.pc => UsenetCategory.software,
      NewznabCategoryId.books => UsenetCategory.books,
      _ => UsenetCategory.other,
    };
  }

  // ---------------------------------------------------------------------------
  // Private — type conversions (NZB parser ↔ service layer)
  // ---------------------------------------------------------------------------

  /// Converts an [nzb_parser.NzbDocument] to the service-layer [NzbFile].
  NzbFile _nzbFileFromDocument(nzb_parser.NzbDocument doc) => NzbFile(
        title: doc.title ?? 'Untitled',
        files: doc.files.map(_fileEntryFromParser).toList(),
        totalBytes: doc.totalBytes,
        metadata: doc.metadata,
      );

  /// Converts an [nzb_parser.NzbFileEntry] to the service-layer
  /// [NzbFileEntry].
  NzbFileEntry _fileEntryFromParser(nzb_parser.NzbFileEntry e) =>
      NzbFileEntry(
        filename: e.filename,
        bytes: e.totalBytes,
        segments: e.segments.map(_segmentFromParser).toList(),
        subject: e.subject,
        isPar2: e.isPar2,
        isRar: e.isRar,
      );

  /// Converts an [nzb_parser.NzbSegment] to the service-layer [NzbSegment].
  NzbSegment _segmentFromParser(nzb_parser.NzbSegment s) => NzbSegment(
        number: s.number,
        messageId: s.messageId,
        bytes: s.bytes,
      );

  /// Converts a service-layer [NzbFile] back to an [nzb_parser.NzbDocument]
  /// for consumption by [StreamPipeline].
  nzb_parser.NzbDocument _documentFromNzbFile(NzbFile nzb) =>
      nzb_parser.NzbDocument(
        title: nzb.title,
        metadata: nzb.metadata,
        files: nzb.files.map(_parserEntryFromFile).toList(),
      );

  /// Converts a service-layer [NzbFileEntry] back to
  /// [nzb_parser.NzbFileEntry].
  nzb_parser.NzbFileEntry _parserEntryFromFile(NzbFileEntry e) =>
      nzb_parser.NzbFileEntry(
        subject: e.subject,
        segments: e.segments.map(_parserSegmentFromSegment).toList(),
      );

  /// Converts a service-layer [NzbSegment] back to [nzb_parser.NzbSegment].
  nzb_parser.NzbSegment _parserSegmentFromSegment(NzbSegment s) =>
      nzb_parser.NzbSegment(
        number: s.number,
        messageId: s.messageId,
        bytes: s.bytes,
      );
}
