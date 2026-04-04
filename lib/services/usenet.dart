/// Usenet service — abstract interface for Usenet indexer, provider,
/// and NNTP streaming operations.
///
/// Defines [UsenetService] which manages indexers (Newznab-compatible search
/// APIs), providers (NNTP servers), NZB parsing, article streaming, and
/// download orchestration. All credentials are stored as vault references —
/// the service never exposes raw API keys or passwords.
///
/// Platform implementations live in `lib/platform/`.
/// Agents access this only through `AgentContext`.
library;

import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Content category for Usenet releases.
enum UsenetCategory {
  /// Feature films and other movie content.
  movies,

  /// Television series and episodes.
  tvShows,

  /// Music albums, singles, and compilations.
  music,

  /// Video games and related content.
  games,

  /// Desktop and mobile software.
  software,

  /// E-books, audiobooks, and comics.
  books,

  /// Audio content not classified as music (podcasts, radio, etc.).
  audio,

  /// Content that does not fit any other category.
  other,
}

/// State of an active streaming session.
enum StreamState {
  /// Initial buffering before playback can begin.
  buffering,

  /// Actively playing content.
  playing,

  /// Playback paused by the user.
  paused,

  /// Seeking to a new position in the stream.
  seeking,

  /// Session stopped — no further data will be served.
  stopped,

  /// An unrecoverable error occurred during streaming.
  error,
}

/// State of a content download.
enum DownloadState {
  /// Waiting in the download queue.
  queued,

  /// Actively fetching articles from providers.
  downloading,

  /// Download complete; running par2 repair and/or archive extraction.
  postProcessing,

  /// All processing finished successfully.
  completed,

  /// The download failed and cannot continue.
  failed,

  /// The download was paused by the user.
  paused,
}

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

/// A Newznab-compatible Usenet indexer.
///
/// Indexers provide search APIs for discovering releases. The [apiKeyRef]
/// is a vault reference (content hash) — the actual API key is never held
/// in memory outside of the vault.
@immutable
class UsenetIndexer {
  /// Creates a [UsenetIndexer].
  const UsenetIndexer({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKeyRef,
    required this.enabled,
    this.capabilities = const [],
  });

  /// Unique identifier for this indexer configuration.
  final String id;

  /// Human-readable display name.
  final String name;

  /// Base URL of the Newznab API (e.g. `https://indexer.example/api`).
  final String baseUrl;

  /// Vault reference (content hash) pointing to the stored API key.
  final String apiKeyRef;

  /// Whether this indexer is active and should be included in searches.
  final bool enabled;

  /// Newznab capability categories supported by this indexer.
  final List<String> capabilities;

  @override
  String toString() => 'UsenetIndexer(id: $id, name: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is UsenetIndexer && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// An NNTP Usenet provider (news server).
///
/// Providers supply the actual article data over NNTP. The [passwordRef]
/// is a vault reference — the raw password never leaves the vault.
@immutable
class UsenetProvider {
  /// Creates a [UsenetProvider].
  const UsenetProvider({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.passwordRef,
    required this.connections,
    required this.priority,
    required this.ssl,
    required this.enabled,
    this.retentionDays = 0,
  });

  /// Unique identifier for this provider configuration.
  final String id;

  /// Human-readable display name.
  final String name;

  /// NNTP server hostname.
  final String host;

  /// NNTP server port (typically 119 or 563 for SSL).
  final int port;

  /// Account username for authentication.
  final String username;

  /// Vault reference (content hash) pointing to the stored password.
  final String passwordRef;

  /// Maximum number of concurrent NNTP connections to open.
  final int connections;

  /// Priority order — lower values are preferred. Providers with the same
  /// priority are used in parallel; higher-priority (lower number) providers
  /// are tried first for fill operations.
  final int priority;

  /// Whether to use SSL/TLS for the NNTP connection.
  final bool ssl;

  /// Whether this provider is active and available for use.
  final bool enabled;

  /// Server retention in days. `0` means unknown or unlimited.
  final int retentionDays;

  @override
  String toString() => 'UsenetProvider(id: $id, name: $name, host: $host)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is UsenetProvider && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A release (NZB) found via an indexer search.
@immutable
class UsenetRelease {
  /// Creates a [UsenetRelease].
  const UsenetRelease({
    required this.id,
    required this.title,
    required this.indexerId,
    required this.nzbUrl,
    required this.sizeBytes,
    required this.publishedAt,
    this.category = UsenetCategory.other,
    this.group,
    this.poster,
    this.description,
    this.imdbId,
    this.tvdbId,
    this.attributes = const {},
  });

  /// Unique identifier for this release (typically from the indexer).
  final String id;

  /// Release title as returned by the indexer.
  final String title;

  /// The [UsenetIndexer.id] that returned this release.
  final String indexerId;

  /// URL to download the NZB file for this release.
  final String nzbUrl;

  /// Total size of the release in bytes.
  final int sizeBytes;

  /// When the release was posted to Usenet.
  final DateTime publishedAt;

  /// Content category.
  final UsenetCategory category;

  /// The Usenet newsgroup this release was posted to.
  final String? group;

  /// The poster (uploader) name or email.
  final String? poster;

  /// Optional description or additional information.
  final String? description;

  /// IMDb identifier (e.g. `tt1234567`) for movie/TV releases.
  final String? imdbId;

  /// TheTVDB identifier for TV show releases.
  final String? tvdbId;

  /// Additional Newznab attributes (e.g. `resolution`, `codec`, `season`).
  final Map<String, String> attributes;

  @override
  String toString() => 'UsenetRelease(id: $id, title: $title)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is UsenetRelease && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A parsed NZB file describing the segments needed to reconstruct content.
@immutable
class NzbFile {
  /// Creates an [NzbFile].
  const NzbFile({
    required this.title,
    required this.files,
    required this.totalBytes,
    this.metadata = const {},
  });

  /// The title or name of the NZB collection.
  final String title;

  /// The individual file entries contained in this NZB.
  final List<NzbFileEntry> files;

  /// Total size in bytes across all file entries.
  final int totalBytes;

  /// Metadata from the NZB `<head>` section (e.g. `password`, `category`).
  final Map<String, String> metadata;

  @override
  String toString() =>
      'NzbFile(title: $title, files: ${files.length}, totalBytes: $totalBytes)';
}

/// A single file entry within an NZB.
@immutable
class NzbFileEntry {
  /// Creates an [NzbFileEntry].
  const NzbFileEntry({
    required this.filename,
    required this.bytes,
    required this.segments,
    required this.subject,
    this.isPar2 = false,
    this.isRar = false,
  });

  /// The decoded filename of this file.
  final String filename;

  /// Size of this file in bytes.
  final int bytes;

  /// The NNTP segments that make up this file.
  final List<NzbSegment> segments;

  /// The raw subject line from the Usenet post.
  final String subject;

  /// Whether this file is a PAR2 parity/repair file.
  final bool isPar2;

  /// Whether this file is a RAR archive part.
  final bool isRar;

  @override
  String toString() => 'NzbFileEntry(filename: $filename, bytes: $bytes)';
}

/// A single NNTP article segment within an NZB file entry.
@immutable
class NzbSegment {
  /// Creates an [NzbSegment].
  const NzbSegment({
    required this.number,
    required this.messageId,
    required this.bytes,
  });

  /// Segment number (1-based ordering within the parent file).
  final int number;

  /// The NNTP Message-ID used to retrieve this segment.
  final String messageId;

  /// Size of this segment in bytes.
  final int bytes;

  @override
  String toString() => 'NzbSegment(number: $number, messageId: $messageId)';
}

/// An active streaming session serving content over a local HTTP URL.
@immutable
class StreamSession {
  /// Creates a [StreamSession].
  const StreamSession({
    required this.id,
    required this.nzbTitle,
    required this.localUrl,
    required this.bytesStreamed,
    required this.totalBytes,
    required this.state,
  });

  /// Unique identifier for this streaming session.
  final String id;

  /// Title of the NZB content being streamed.
  final String nzbTitle;

  /// Localhost URL where the content is being served (e.g.
  /// `http://127.0.0.1:PORT/stream/ID`).
  final String localUrl;

  /// Number of bytes already streamed to the client.
  final int bytesStreamed;

  /// Total size of the content in bytes.
  final int totalBytes;

  /// Current state of the streaming session.
  final StreamState state;

  @override
  String toString() =>
      'StreamSession(id: $id, nzbTitle: $nzbTitle, state: $state)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is StreamSession && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Progress information for an active download operation.
@immutable
class DownloadProgress {
  /// Creates a [DownloadProgress].
  const DownloadProgress({
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.state,
    this.currentFile,
    this.segmentsFetched = 0,
    this.totalSegments = 0,
  });

  /// Number of bytes downloaded so far.
  final int bytesDownloaded;

  /// Total expected size in bytes.
  final int totalBytes;

  /// Current download state.
  final DownloadState state;

  /// The filename currently being downloaded, if any.
  final String? currentFile;

  /// Number of NNTP segments successfully fetched.
  final int segmentsFetched;

  /// Total number of segments to fetch.
  final int totalSegments;

  @override
  String toString() =>
      'DownloadProgress(state: $state, '
      '$bytesDownloaded/$totalBytes bytes, '
      '$segmentsFetched/$totalSegments segments)';
}

// ---------------------------------------------------------------------------
// Service interface
// ---------------------------------------------------------------------------

/// Abstract interface for Usenet operations.
///
/// Manages indexers (Newznab search APIs), NNTP providers (news servers),
/// NZB parsing, article streaming, and content download. All credential
/// storage is delegated to the vault service — this service only holds
/// vault references, never raw secrets.
///
/// Agents interact with this service exclusively through `AgentContext`.
abstract interface class UsenetService {
  // -------------------------------------------------------------------------
  // Indexer management
  // -------------------------------------------------------------------------

  /// Registers a new indexer and returns it with a generated [UsenetIndexer.id].
  ///
  /// The [indexer] should have all fields populated except [UsenetIndexer.id],
  /// which will be assigned by the implementation. The API key must already
  /// be stored in the vault; [UsenetIndexer.apiKeyRef] must point to it.
  Future<Result<UsenetIndexer>> addIndexer(UsenetIndexer indexer);

  /// Removes the indexer identified by [indexerId].
  ///
  /// Returns [Failure] with [UsenetIndexerError] if no indexer with
  /// that ID exists.
  Future<Result<void>> removeIndexer(String indexerId);

  /// Returns all configured indexers.
  Future<List<UsenetIndexer>> getIndexers();

  /// Resolves a vault reference to the actual API key or password string.
  ///
  /// Returns `null` if the reference cannot be resolved (e.g. the vault
  /// entry was deleted or the reference is invalid).
  Future<String?> resolveSecret(String? vaultRef);

  /// Tests connectivity and authentication for the indexer at [indexerId].
  ///
  /// Returns `true` if the indexer responded successfully, or [Failure]
  /// with a descriptive [UsenetError] on failure.
  Future<Result<bool>> testIndexer(String indexerId);

  /// Tests an indexer connection without saving it first.
  ///
  /// Useful in the "Add Indexer" flow where the indexer has not yet been
  /// persisted. Connects to the Newznab endpoint at [baseUrl] with the
  /// given [apiKey] and queries capabilities.
  Future<Result<bool>> testIndexerDirect({
    required String baseUrl,
    required String apiKey,
  });

  // -------------------------------------------------------------------------
  // Provider management
  // -------------------------------------------------------------------------

  /// Registers a new NNTP provider and returns it with a generated
  /// [UsenetProvider.id].
  ///
  /// The password must already be stored in the vault;
  /// [UsenetProvider.passwordRef] must point to it.
  Future<Result<UsenetProvider>> addProvider(UsenetProvider provider);

  /// Removes the provider identified by [providerId].
  ///
  /// Returns [Failure] with [UsenetProviderError] if no provider
  /// with that ID exists.
  Future<Result<void>> removeProvider(String providerId);

  /// Returns all configured NNTP providers.
  Future<List<UsenetProvider>> getProviders();

  /// Tests connectivity and authentication for the provider at [providerId].
  ///
  /// Returns `true` if the server accepted the credentials, or [Failure]
  /// with a descriptive [UsenetError] on failure.
  Future<Result<bool>> testProvider(String providerId);

  /// Tests a provider connection without saving it first.
  ///
  /// Useful in the "Add Provider" flow where the provider has not yet been
  /// persisted. Connects to the NNTP server at [host]:[port] with the
  /// given [username] and [password].
  Future<Result<bool>> testProviderDirect({
    required String host,
    required int port,
    required bool ssl,
    required String username,
    required String password,
  });

  // -------------------------------------------------------------------------
  // Search
  // -------------------------------------------------------------------------

  /// Searches configured indexers for releases matching [query].
  ///
  /// - [indexerIds]: If provided, search only these indexers. Defaults to
  ///   all enabled indexers.
  /// - [category]: Filter results to a specific content category.
  /// - [minSizeBytes] / [maxSizeBytes]: Filter by release size.
  /// - [limit]: Maximum number of results to return.
  ///
  /// Results are aggregated from all queried indexers and deduplicated
  /// by title when possible.
  Future<Result<List<UsenetRelease>>> search(
    String query, {
    List<String>? indexerIds,
    UsenetCategory? category,
    int? minSizeBytes,
    int? maxSizeBytes,
    int? limit,
  });

  // -------------------------------------------------------------------------
  // NZB operations
  // -------------------------------------------------------------------------

  /// Fetches an NZB file from [url] and parses it.
  ///
  /// Returns the parsed [NzbFile] structure. The URL is typically
  /// [UsenetRelease.nzbUrl] obtained from a search result.
  Future<Result<NzbFile>> fetchNzb(String url);

  /// Parses an NZB from a raw XML [content] string.
  ///
  /// Useful when the NZB data is already available locally (e.g. from
  /// the vault or a drag-and-drop operation).
  Result<NzbFile> parseNzb(String content);

  // -------------------------------------------------------------------------
  // Streaming
  // -------------------------------------------------------------------------

  /// Starts a streaming session for the given [nzb].
  ///
  /// Launches a local HTTP server (if not already running) and begins
  /// fetching articles from configured providers. Returns a
  /// [StreamSession] whose [StreamSession.localUrl] can be passed to
  /// a media player.
  ///
  /// Progress updates are available via the returned session's state
  /// or by calling [getActiveStreams].
  Future<Result<StreamSession>> startStream(NzbFile nzb);

  /// Stops the streaming session identified by [sessionId].
  ///
  /// Releases all provider connections and stops the local HTTP handler
  /// for this session. Returns [Failure] if the session does not exist.
  Future<Result<void>> stopStream(String sessionId);

  /// Returns all currently active streaming sessions.
  Future<List<StreamSession>> getActiveStreams();

  // -------------------------------------------------------------------------
  // Download
  // -------------------------------------------------------------------------

  /// Downloads the content described by [nzb] to persistent storage.
  ///
  /// Unlike streaming, this fetches all articles, assembles files,
  /// runs par2 repair if needed, and extracts archives. Progress is
  /// reported through the returned [Stream].
  ///
  /// - [outputName]: Desired name for the output file or directory.
  ///
  /// The final [DownloadProgress] event will have
  /// [DownloadProgress.state] equal to [DownloadState.completed] or
  /// [DownloadState.failed].
  Stream<DownloadProgress> downloadContent(
    NzbFile nzb, {
    required String outputName,
  });

  // -------------------------------------------------------------------------
  // Cache management
  // -------------------------------------------------------------------------

  /// Returns the current cache size in bytes.
  ///
  /// The cache stores recently fetched articles and assembled segments
  /// to speed up repeated access and seeking during streaming.
  Future<int> getCacheSize();

  /// Clears all cached articles and assembled segments.
  Future<void> clearCache();

  /// Sets the maximum cache size in bytes.
  ///
  /// When the cache exceeds this limit, the oldest entries are evicted
  /// using an LRU strategy. A value of `0` disables the cache.
  Future<void> setCacheLimit(int bytes);
}
