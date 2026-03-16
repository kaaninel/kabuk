# Virtual OS Layer Design

## Philosophy

Just as Flutter doesn't replace Skia/Impeller on each platform but provides a consistent abstraction that maps down to native capabilities, Kabuk's Virtual OS layer abstracts every platform capability behind clean Dart interfaces. Business logic and agents never touch platform APIs directly — they use these interfaces. Implementations live in `lib/platform/` and use platform channels to bridge to native code.

This means "mesh networking" isn't raw WireGuard — it's a `MeshService` interface that uses whatever transport is available. "Filesystem" isn't `dart:io` — it's `VaultService` with encryption, tagging, and content-addressing. "Crypto" isn't a platform keychain call — it's `AuthService` with a unified API across Android Keystore, Secure Enclave, and OS keychains.

The Virtual OS layer is the backbone that makes Kabuk truly platform-agnostic. Agents, the knowledge store, and the UI all depend on these interfaces — never on platform specifics. Swapping the entire platform underneath requires only new implementations of these interfaces, registered via Riverpod providers.

---

## Service Architecture

### Design Principles

1. **Interface in `lib/services/`, implementation in `lib/platform/`** — The interface defines the contract. The implementation fulfills it per platform. Business logic imports only the interface.
2. **Riverpod providers for all services** — Every service is exposed as a Riverpod provider. Swap implementations by overriding the provider (useful for testing, platform switching, and capability degradation).
3. **No platform imports outside `lib/platform/`** — `dart:io`, `dart:html`, `dart:ffi`, Flutter platform channels — none of these may appear outside `lib/platform/`.
4. **Async by default** — All service methods return `Future` or `Stream`. No synchronous I/O. This ensures consistent behavior across platforms and prevents UI jank.
5. **Graceful degradation** — If a capability is unavailable on the current platform, the service must return a clear `ServiceError.notSupported` or provide a no-op implementation — never crash.
6. **Feature detection** — Services expose `isSupported` flags and `capabilities` getters for optional features. Agents and UI check capabilities before attempting operations.
7. **Agents access services only through `AgentContext`** — Never import service providers directly in agent code. The `AgentContext` bundles all available services and enforces access control.

### Provider Registration Pattern

```dart
/// Interface — lives in lib/services/vault.dart
abstract class VaultService {
  Future<void> write(
    String path,
    Uint8List data, {
    Map<String, String>? metadata,
  });
  Future<Uint8List> read(String path);
  Stream<VaultChange> watch(String path);
  // ...
}

/// Provider — lives in lib/services/vault.dart
final vaultServiceProvider = Provider<VaultService>((ref) {
  if (Platform.isAndroid) return AndroidVaultService(ref);
  if (Platform.isIOS) return IosVaultService(ref);
  return DesktopVaultService(ref);
});

/// In tests — override with mock
final container = ProviderContainer(
  overrides: [
    vaultServiceProvider.overrideWithValue(MockVaultService()),
  ],
);
```

### Service Lifecycle

All services follow a consistent lifecycle:

```dart
/// Mixin for services that require initialization and cleanup.
mixin ServiceLifecycle {
  /// Called once when the service is first accessed.
  Future<void> initialize();

  /// Called when the app is shutting down or the service
  /// is being replaced.
  Future<void> dispose();

  /// Whether the service has been initialized.
  bool get isInitialized;
}
```

Services are lazily initialized on first access and disposed when the app shuts down. The `ServiceRegistry` (a Riverpod provider) manages the lifecycle of all services:

```dart
final serviceRegistryProvider =
    Provider<ServiceRegistry>((ref) {
  return ServiceRegistry(ref);
});

class ServiceRegistry {
  ServiceRegistry(this._ref);
  final Ref _ref;

  Future<void> initializeAll() async {
    await Future.wait([
      _ref.read(authServiceProvider).initialize(),
      _ref.read(vaultServiceProvider).initialize(),
      _ref.read(meshServiceProvider).initialize(),
      _ref.read(mediaServiceProvider).initialize(),
      _ref.read(notificationServiceProvider).initialize(),
      _ref.read(presentationServiceProvider).initialize(),
    ]);
  }

  Future<void> disposeAll() async {
    await Future.wait([
      _ref.read(presentationServiceProvider).dispose(),
      _ref.read(notificationServiceProvider).dispose(),
      _ref.read(mediaServiceProvider).dispose(),
      _ref.read(meshServiceProvider).dispose(),
      _ref.read(vaultServiceProvider).dispose(),
      _ref.read(authServiceProvider).dispose(),
    ]);
  }
}
```

---

## Service Specifications

### 1. VaultService — Encrypted Filesystem

**Purpose:** Secure, tag-based file storage with encryption at rest. Replaces traditional filesystem access with a content-addressed, metadata-rich storage layer. Every piece of user data — notes, photos, audio, documents — flows through VaultService.

**Design Rationale:**
- Content-addressing (SHA-256 hashing) provides deduplication and integrity verification for free.
- Tag-based organization maps naturally to the RDF knowledge store — tags are just triples.
- Encryption is on by default. Agents must explicitly opt out (e.g., for cached thumbnails).
- Streaming support enables handling large files without loading everything into memory.

#### Interface

```dart
/// Encrypted, content-addressed file storage.
///
/// All user data is stored through VaultService. Files are
/// content-addressed by SHA-256 hash, enabling deduplication
/// and integrity verification. Encryption is on by default.
abstract class VaultService with ServiceLifecycle {
  // ── Core CRUD ──────────────────────────────────────────

  /// Store data and return its vault entry.
  ///
  /// The returned [VaultEntry.hash] is the content-addressed
  /// identifier used for all subsequent operations.
  Future<ServiceResult<VaultEntry>> store(
    Uint8List data, {
    required String name,
    String? mimeType,
    Map<String, String>? metadata,
    List<String>? tags,
    bool encrypt = true,
  });

  /// Retrieve raw data by content hash.
  Future<ServiceResult<Uint8List>> retrieve(String hash);

  /// Delete an entry by content hash.
  ///
  /// If other entries reference this hash (deduplication),
  /// only the reference is removed. Actual data is removed
  /// during [compact].
  Future<ServiceResult<void>> delete(String hash);

  // ── Query ──────────────────────────────────────────────

  /// List entries matching the given filters.
  ///
  /// All filters are combined with AND logic. Pass no filters
  /// to list all entries.
  Future<ServiceResult<List<VaultEntry>>> list({
    List<String>? tags,
    String? mimeTypePrefix, // e.g., 'image/', 'video/'
    DateTimeRange? dateRange,
    VaultSortField sortBy = VaultSortField.modifiedAt,
    bool descending = true,
    int? limit,
    int? offset,
  });

  /// Full-text search across entry names and metadata values.
  Future<ServiceResult<List<VaultEntry>>> search(
    String query, {
    int? limit,
  });

  /// Check whether an entry with the given hash exists.
  Future<bool> exists(String hash);

  // ── Streaming ──────────────────────────────────────────

  /// Watch for changes to any vault entries.
  ///
  /// Emits events for creates, updates, and deletes.
  Stream<VaultChange> watchChanges();

  /// Watch for changes to a specific entry.
  Stream<VaultChange> watchEntry(String hash);

  /// Stream retrieve for large files.
  ///
  /// Returns chunks of data. The total size is available in
  /// the entry metadata. Useful for video/audio playback and
  /// large file transfers.
  Stream<Uint8List> streamRetrieve(
    String hash, {
    int chunkSize = 64 * 1024, // 64 KB default
  });

  /// Store data from a stream (for large files).
  Future<ServiceResult<VaultEntry>> storeStream(
    Stream<Uint8List> data, {
    required String name,
    required int totalSize,
    String? mimeType,
    Map<String, String>? metadata,
    List<String>? tags,
    bool encrypt = true,
  });

  // ── Metadata ───────────────────────────────────────────

  /// Get the entry for a given hash without retrieving data.
  Future<ServiceResult<VaultEntry>> getEntry(String hash);

  /// Update metadata for an existing entry.
  Future<ServiceResult<VaultEntry>> updateMetadata(
    String hash,
    Map<String, String> metadata,
  );

  /// Replace tags for an existing entry.
  Future<ServiceResult<VaultEntry>> updateTags(
    String hash,
    List<String> tags,
  );

  /// Add tags without removing existing ones.
  Future<ServiceResult<VaultEntry>> addTags(
    String hash,
    List<String> tags,
  );

  /// Remove specific tags.
  Future<ServiceResult<VaultEntry>> removeTags(
    String hash,
    List<String> tags,
  );

  // ── Space Management ───────────────────────────────────

  /// Get storage statistics.
  Future<ServiceResult<VaultStats>> getStats();

  /// Run garbage collection.
  ///
  /// Removes orphaned data (content no longer referenced by
  /// any entry), expired cache entries, and reclaims space.
  Future<ServiceResult<void>> compact();

  // ── Import / Export ────────────────────────────────────

  /// Import a file from the platform filesystem into the vault.
  ///
  /// Uses platform-specific file pickers (SAF on Android,
  /// UIDocumentPicker on iOS, native file dialog on desktop).
  Future<ServiceResult<VaultEntry>> importFromPlatform(
    String platformPath,
  );

  /// Export a vault entry to the platform filesystem.
  ///
  /// Returns the platform-specific path where the file was
  /// written.
  Future<ServiceResult<String>> exportToPlatform(
    String hash,
    String destinationPath,
  );

  /// Open the platform file picker and import selected files.
  Future<ServiceResult<List<VaultEntry>>> pickAndImport({
    List<String>? allowedMimeTypes,
    bool multiple = false,
  });

  // ── Capabilities ───────────────────────────────────────

  /// Maximum file size supported by this implementation.
  int get maxFileSize;

  /// Whether this implementation supports encryption.
  bool get supportsEncryption;

  /// Whether this implementation supports streaming.
  bool get supportsStreaming;
}
```

#### Platform Mapping

| Operation | Android | iOS | Desktop |
|---|---|---|---|
| Storage location | App-scoped internal storage (`getFilesDir()`) | App sandbox `Documents/` | `~/.kabuk/vault/` (XDG on Linux) |
| Encryption | AES-256-GCM via Android Keystore + Tink | AES-256-GCM via CryptoKit | AES-256-GCM via libsodium |
| Key derivation | Argon2id via Tink | Argon2id via CryptoKit | Argon2id via libsodium |
| Platform file access | Storage Access Framework (SAF) | `UIDocumentPickerViewController` | Native file dialog (GTK/Cocoa/Win32) |
| Thumbnails | `MediaStore` thumbnails / `ThumbnailUtils` | `AVFoundation` / `CGImageSource` | FFmpeg |
| File watching | `FileObserver` | `NSFileCoordinator` / `DispatchSource` | `inotify` (Linux) / `FSEvents` (macOS) / `ReadDirectoryChangesW` (Windows) |
| Content hashing | SHA-256 via `java.security.MessageDigest` | SHA-256 via `CryptoKit` | SHA-256 via `libsodium` |

#### Data Classes

```dart
@freezed
class VaultEntry with _$VaultEntry {
  const factory VaultEntry({
    required String hash,       // Content-addressed SHA-256
    required String name,
    required String mimeType,
    required int size,          // Bytes
    required DateTime createdAt,
    required DateTime modifiedAt,
    required List<String> tags,
    required Map<String, String> metadata,
    required bool encrypted,
  }) = _VaultEntry;

  factory VaultEntry.fromJson(Map<String, dynamic> json) =>
      _$VaultEntryFromJson(json);
}

@freezed
class VaultChange with _$VaultChange {
  const factory VaultChange.created(VaultEntry entry) =
      VaultChangeCreated;
  const factory VaultChange.updated(VaultEntry entry) =
      VaultChangeUpdated;
  const factory VaultChange.deleted(String hash) =
      VaultChangeDeleted;
  const factory VaultChange.metadataUpdated(VaultEntry entry) =
      VaultChangeMetadataUpdated;

  factory VaultChange.fromJson(Map<String, dynamic> json) =>
      _$VaultChangeFromJson(json);
}

@freezed
class VaultStats with _$VaultStats {
  const factory VaultStats({
    required int totalEntries,
    required int totalSizeBytes,
    required int encryptedEntries,
    required int unencryptedEntries,
    required int availableSpaceBytes,
    required Map<String, int> entriesByMimePrefix,
  }) = _VaultStats;

  factory VaultStats.fromJson(Map<String, dynamic> json) =>
      _$VaultStatsFromJson(json);
}

enum VaultSortField {
  name,
  createdAt,
  modifiedAt,
  size,
  mimeType,
}
```

#### Knowledge Store Integration

Every `VaultEntry` is mirrored as an RDF entity in the knowledge store:

```
subject:   kabuk:vault/{hash}
predicate: schema:name        → entry.name
predicate: schema:encodingFormat → entry.mimeType
predicate: schema:contentSize → entry.size
predicate: schema:dateCreated → entry.createdAt
predicate: schema:dateModified → entry.modifiedAt
predicate: kabuk:tag          → entry.tags[i]  (one triple per tag)
predicate: kabuk:encrypted    → entry.encrypted
predicate: kabuk:vaultHash    → entry.hash
```

This allows agents to query vault contents through the standard knowledge store query builder, and RFW widgets can bind to vault data reactively.

---

### 2. MeshService — Connection-Agnostic Networking

**Purpose:** Unified networking that abstracts the transport layer. Works over BLE, WiFi Direct, WebSocket, relay server, or any available connection. Provides both peer-to-peer direct communication and standard HTTP for external API access.

**Design Rationale:**
- Kabuk is offline-first, but when connectivity is available, it should use the best transport automatically.
- Peer-to-peer communication enables device-to-device sync without a central server.
- The relay server is a fallback, not a requirement — it bridges NAT when direct connections fail.
- Message queueing ensures nothing is lost during transport switches or temporary disconnections.

#### Interface

```dart
/// Connection-agnostic networking service.
///
/// Abstracts all network transports behind a single interface.
/// Handles peer discovery, messaging, streaming, and standard
/// HTTP requests. Automatically selects the best available
/// transport and queues messages during disconnections.
abstract class MeshService with ServiceLifecycle {
  // ── Connection Management ──────────────────────────────

  /// Start the mesh service and begin listening for peers.
  @override
  Future<void> initialize();

  /// Shut down all connections and stop discovery.
  @override
  Future<void> shutdown();

  /// Current connection state as a reactive stream.
  Stream<MeshState> get connectionState;

  /// Whether any network transport is currently available.
  bool get isOnline;

  /// The currently active transport.
  MeshTransport get activeTransport;

  /// All currently available transports.
  Set<MeshTransport> get availableTransports;

  // ── Peer Discovery ─────────────────────────────────────

  /// Discover nearby peers within the given timeout.
  ///
  /// Uses the best available discovery mechanism:
  /// BLE advertising, WiFi Direct, mDNS, or relay server.
  Future<ServiceResult<List<MeshPeer>>> discoverPeers({
    Duration timeout = const Duration(seconds: 10),
  });

  /// Continuous peer discovery as a stream.
  ///
  /// Emits peers as they are found or lost. Peers that
  /// disappear emit a [MeshPeer] with [MeshPeer.isAvailable]
  /// set to false.
  Stream<MeshPeer> watchPeers();

  /// Get a previously discovered peer by ID.
  Future<ServiceResult<MeshPeer>> getPeer(String peerId);

  /// Known peers (previously connected).
  Future<ServiceResult<List<MeshPeer>>> knownPeers();

  // ── Messaging ──────────────────────────────────────────

  /// Send a message to a peer.
  ///
  /// Messages are queued if the peer is not currently
  /// reachable and delivered when a connection is
  /// re-established (unless [queueIfOffline] is false).
  Future<ServiceResult<void>> send(
    String peerId,
    Uint8List data, {
    MeshPriority priority = MeshPriority.normal,
    bool queueIfOffline = true,
    Duration? timeout,
  });

  /// Incoming messages from all peers.
  Stream<MeshMessage> get incomingMessages;

  /// Send a message and wait for a response.
  Future<ServiceResult<MeshMessage>> sendAndWait(
    String peerId,
    Uint8List data, {
    Duration timeout = const Duration(seconds: 30),
  });

  // ── Streams (Large Data Transfer) ─────────────────────

  /// Open a bidirectional stream to a peer.
  ///
  /// Used for large file transfers, real-time audio/video,
  /// or any scenario requiring sustained data flow.
  Future<ServiceResult<MeshStream>> openStream(
    String peerId, {
    String? label,
  });

  /// Incoming stream requests from peers.
  Stream<MeshStream> get incomingStreams;

  // ── Relay ──────────────────────────────────────────────

  /// Connect to a relay server for NAT traversal.
  ///
  /// The relay is used as a fallback when direct peer-to-peer
  /// connections are not possible (different networks, no BLE
  /// range, etc.).
  Future<ServiceResult<void>> connectToRelay(
    String relayUrl, {
    String? authToken,
  });

  /// Disconnect from the relay server.
  Future<ServiceResult<void>> disconnectFromRelay();

  /// Whether currently connected to a relay.
  bool get isRelayConnected;

  // ── HTTP (External APIs) ───────────────────────────────

  /// Perform an HTTP GET request.
  ///
  /// For external API access. All HTTP traffic goes through
  /// MeshService so it can be logged, rate-limited, and
  /// controlled by the user.
  Future<ServiceResult<MeshResponse>> httpGet(
    String url, {
    Map<String, String>? headers,
    Duration? timeout,
  });

  /// Perform an HTTP POST request.
  Future<ServiceResult<MeshResponse>> httpPost(
    String url, {
    Map<String, String>? headers,
    Uint8List? body,
    String? contentType,
    Duration? timeout,
  });

  /// Perform an HTTP PUT request.
  Future<ServiceResult<MeshResponse>> httpPut(
    String url, {
    Map<String, String>? headers,
    Uint8List? body,
    String? contentType,
    Duration? timeout,
  });

  /// Perform an HTTP DELETE request.
  Future<ServiceResult<MeshResponse>> httpDelete(
    String url, {
    Map<String, String>? headers,
    Duration? timeout,
  });

  /// Open a WebSocket connection.
  Future<ServiceResult<MeshWebSocket>> openWebSocket(
    String url, {
    Map<String, String>? headers,
  });

  // ── Queue Management ───────────────────────────────────

  /// Number of messages currently queued for delivery.
  Future<int> get queuedMessageCount;

  /// Flush the message queue (attempt delivery now).
  Future<ServiceResult<void>> flushQueue();

  /// Clear the message queue (discard all queued messages).
  Future<ServiceResult<void>> clearQueue();

  // ── Status ─────────────────────────────────────────────

  /// Get a detailed status report.
  Future<ServiceResult<MeshStatus>> getStatus();

  // ── Capabilities ───────────────────────────────────────

  /// Which transports are supported on this platform.
  Set<MeshTransport> get supportedTransports;

  /// Whether peer-to-peer is supported.
  bool get supportsPeerToPeer;

  /// Whether relay connections are supported.
  bool get supportsRelay;
}
```

#### Platform Mapping

| Capability | Android | iOS | Desktop |
|---|---|---|---|
| Nearby peers | Nearby Connections API | MultipeerConnectivity | mDNS + TCP sockets |
| BLE | Android BLE API (`BluetoothLeScanner`) | CoreBluetooth | BlueZ (Linux) / CoreBluetooth (macOS) |
| WiFi Direct | Wi-Fi P2P API (`WifiP2pManager`) | Not available (use MultipeerConnectivity) | Platform-specific |
| WebSocket | OkHttp WebSocket | `URLSessionWebSocketTask` | `dart:io` WebSocket (via platform layer) |
| Relay server | gRPC over HTTP/2 | gRPC over HTTP/2 | gRPC over HTTP/2 |
| HTTP | OkHttp / `HttpURLConnection` | `URLSession` | `dart:io` `HttpClient` (via platform layer) |
| mDNS | `NsdManager` | `NetServiceBrowser` | Avahi (Linux) / Bonjour (macOS) |

#### Data Classes

```dart
@freezed
class MeshPeer with _$MeshPeer {
  const factory MeshPeer({
    required String id,
    required String displayName,
    required bool isAvailable,
    required MeshTransport transport,
    required DateTime lastSeen,
    Map<String, String>? metadata,
  }) = _MeshPeer;

  factory MeshPeer.fromJson(Map<String, dynamic> json) =>
      _$MeshPeerFromJson(json);
}

@freezed
class MeshMessage with _$MeshMessage {
  const factory MeshMessage({
    required String id,
    required String fromPeerId,
    required Uint8List data,
    required DateTime timestamp,
    required MeshTransport transport,
  }) = _MeshMessage;

  factory MeshMessage.fromJson(Map<String, dynamic> json) =>
      _$MeshMessageFromJson(json);
}

@freezed
class MeshResponse with _$MeshResponse {
  const factory MeshResponse({
    required int statusCode,
    required Map<String, String> headers,
    required Uint8List body,
  }) = _MeshResponse;

  factory MeshResponse.fromJson(Map<String, dynamic> json) =>
      _$MeshResponseFromJson(json);
}

@freezed
class MeshStatus with _$MeshStatus {
  const factory MeshStatus({
    required bool isOnline,
    required MeshTransport activeTransport,
    required Set<MeshTransport> availableTransports,
    required int connectedPeerCount,
    required int queuedMessages,
    required bool isRelayConnected,
    String? relayUrl,
  }) = _MeshStatus;

  factory MeshStatus.fromJson(Map<String, dynamic> json) =>
      _$MeshStatusFromJson(json);
}

@freezed
class MeshState with _$MeshState {
  const factory MeshState.disconnected() = MeshDisconnected;
  const factory MeshState.connecting(MeshTransport transport) =
      MeshConnecting;
  const factory MeshState.connected(MeshTransport transport) =
      MeshConnected;
  const factory MeshState.error(ServiceError error) =
      MeshError;

  factory MeshState.fromJson(Map<String, dynamic> json) =>
      _$MeshStateFromJson(json);
}

enum MeshTransport {
  bluetooth,
  wifiDirect,
  webSocket,
  relay,
  none,
}

enum MeshPriority {
  /// For real-time data (audio/video frames, typing indicators).
  realtime,

  /// For normal messages (chat, sync).
  normal,

  /// For bulk transfers (file sync, knowledge store sync).
  background,
}
```

#### Connection Strategy

MeshService follows a cascading fallback strategy for peer connections:

```
1. Check if peer is on local network
   ├── Yes → Use mDNS discovery + direct TCP
   └── No  → Continue

2. Check if BLE is available and peer is nearby
   ├── Yes → Use BLE for discovery, upgrade to WiFi Direct if available
   └── No  → Continue

3. Check if relay server is configured and reachable
   ├── Yes → Connect via relay
   └── No  → Continue

4. Queue message for later delivery
   └── Retry when any transport becomes available
```

Transport selection is automatic but can be influenced by message priority:
- **Realtime** — Prefer lowest-latency transport (WiFi Direct > TCP > WebSocket > Relay)
- **Normal** — Prefer most reliable transport (TCP > WebSocket > Relay > BLE)
- **Background** — Prefer any available transport, optimize for battery

#### Offline Queue

Messages sent while offline are persisted to a Drift-backed queue:

```dart
@freezed
class QueuedMessage with _$QueuedMessage {
  const factory QueuedMessage({
    required String id,
    required String targetPeerId,
    required Uint8List data,
    required MeshPriority priority,
    required DateTime queuedAt,
    required int retryCount,
    DateTime? lastRetryAt,
  }) = _QueuedMessage;
}
```

Queue behavior:
- Messages are persisted immediately on send when offline.
- Queue is flushed automatically when a connection is established.
- Exponential backoff on retry failures (1s, 2s, 4s, 8s, ... capped at 5 min).
- Messages older than 7 days are discarded (configurable).
- Priority ordering: realtime > normal > background.

---

### 3. MediaService — Unified Media Pipeline

**Purpose:** Camera, microphone, playback, and media processing. Provides a unified interface for all media operations, from capture to transcoding.

**Design Rationale:**
- Media is a core agent capability — agents need to capture, analyze, and present media.
- The interface separates capture, playback, and processing into clear concerns.
- All captured media flows through VaultService for storage — MediaService handles the pipeline.
- Permission management is explicit and unified across platforms.

#### Interface

```dart
/// Unified media capture, playback, and processing.
///
/// Handles camera, microphone, media playback, and
/// processing (thumbnails, transcoding, metadata extraction).
/// All captured media is stored via [VaultService].
abstract class MediaService with ServiceLifecycle {
  // ── Camera ─────────────────────────────────────────────

  /// List available cameras.
  Future<ServiceResult<List<CameraInfo>>> availableCameras();

  /// Open a camera for preview and capture.
  ///
  /// Returns a [CameraSession] that provides a preview stream
  /// and capture methods. Only one camera session can be
  /// active at a time.
  Future<ServiceResult<CameraSession>> openCamera({
    CameraPosition position = CameraPosition.back,
    CameraResolution resolution = CameraResolution.high,
  });

  /// Close the active camera session.
  Future<ServiceResult<void>> closeCamera();

  // ── Photo Capture ──────────────────────────────────────

  /// Capture a photo from the active camera session.
  ///
  /// Returns a [MediaCapture] with the vault hash of the
  /// stored image.
  Future<ServiceResult<MediaCapture>> capturePhoto({
    CaptureOptions? options,
  });

  // ── Video Recording ────────────────────────────────────

  /// Start video recording from the active camera session.
  Future<ServiceResult<void>> startVideoRecording({
    CaptureOptions? options,
  });

  /// Stop video recording and return the captured media.
  Future<ServiceResult<MediaCapture>> stopVideoRecording();

  /// Whether video is currently being recorded.
  bool get isRecordingVideo;

  // ── Audio Recording ────────────────────────────────────

  /// Start audio recording from the microphone.
  ///
  /// Does not require an active camera session.
  Future<ServiceResult<void>> startAudioRecording({
    AudioOptions? options,
  });

  /// Stop audio recording and return the captured media.
  Future<ServiceResult<MediaCapture>> stopAudioRecording();

  /// Whether audio is currently being recorded.
  bool get isRecordingAudio;

  /// Audio level stream during recording (0.0 to 1.0).
  Stream<double> get audioLevel;

  // ── Camera Control ─────────────────────────────────────

  /// Get the camera preview as a stream of frames.
  ///
  /// Useful for real-time processing (e.g., barcode scanning,
  /// face detection via agents).
  Stream<CameraFrame> get cameraPreview;

  /// Switch between front and back cameras.
  Future<ServiceResult<void>> switchCamera();

  /// Set flash mode.
  Future<ServiceResult<void>> setFlash(FlashMode mode);

  /// Set zoom level (1.0 = no zoom).
  Future<ServiceResult<void>> setZoom(double zoom);

  /// Set focus point (normalized coordinates 0.0–1.0).
  Future<ServiceResult<void>> setFocusPoint(
    double x,
    double y,
  );

  /// Set exposure compensation.
  Future<ServiceResult<void>> setExposureCompensation(
    double value,
  );

  // ── Playback ───────────────────────────────────────────

  /// Create a media player for a vault entry.
  ///
  /// Supports audio and video playback. The player manages
  /// its own lifecycle — call [MediaPlayer.dispose] when done.
  Future<ServiceResult<MediaPlayer>> createPlayer(
    String vaultHash,
  );

  // ── Processing ─────────────────────────────────────────

  /// Generate a thumbnail for a vault entry.
  ///
  /// Works for images and videos. Returns raw image bytes
  /// (PNG format).
  Future<ServiceResult<Uint8List>> generateThumbnail(
    String vaultHash, {
    int width = 200,
    int height = 200,
    ThumbnailFit fit = ThumbnailFit.cover,
  });

  /// Extract metadata from a media file.
  ///
  /// Returns EXIF data for images, duration/codec info for
  /// audio/video.
  Future<ServiceResult<MediaMetadata>> extractMetadata(
    String vaultHash,
  );

  /// Transcode a media file.
  ///
  /// Returns a new [MediaCapture] stored in the vault.
  /// Progress is reported via the [onProgress] callback.
  Future<ServiceResult<MediaCapture>> transcode(
    String vaultHash,
    TranscodeOptions options, {
    void Function(double progress)? onProgress,
  });

  /// Compress an image.
  Future<ServiceResult<MediaCapture>> compressImage(
    String vaultHash, {
    int quality = 80,
    int? maxWidth,
    int? maxHeight,
  });

  // ── Permissions ────────────────────────────────────────

  /// Check camera permission status.
  Future<PermissionStatus> cameraPermission();

  /// Check microphone permission status.
  Future<PermissionStatus> microphonePermission();

  /// Request camera permission.
  Future<PermissionStatus> requestCameraPermission();

  /// Request microphone permission.
  Future<PermissionStatus> requestMicrophonePermission();

  /// Request both camera and microphone permissions.
  Future<({
    PermissionStatus camera,
    PermissionStatus microphone,
  })> requestAllPermissions();

  // ── Capabilities ───────────────────────────────────────

  /// Whether a camera is available on this device.
  bool get hasCamera;

  /// Whether a microphone is available on this device.
  bool get hasMicrophone;

  /// Whether video recording is supported.
  bool get supportsVideoRecording;

  /// Whether transcoding is supported.
  bool get supportsTranscoding;

  /// Supported image formats for capture.
  List<String> get supportedImageFormats;

  /// Supported video formats for capture.
  List<String> get supportedVideoFormats;

  /// Supported audio formats for recording.
  List<String> get supportedAudioFormats;
}
```

#### Platform Mapping

| Capability | Android | iOS | Desktop |
|---|---|---|---|
| Camera | CameraX (`androidx.camera`) | AVFoundation (`AVCaptureSession`) | Platform camera API / V4L2 (Linux) |
| Photo capture | CameraX `ImageCapture` | `AVCapturePhotoOutput` | Platform-specific |
| Video recording | CameraX `VideoCapture` | `AVCaptureMovieFileOutput` | Platform-specific |
| Audio recording | `AudioRecord` / `MediaRecorder` | `AVAudioRecorder` | miniaudio / platform audio API |
| Video playback | ExoPlayer (`Media3`) | AVPlayer | mpv via FFI / libVLC |
| Audio playback | ExoPlayer (`Media3`) | AVAudioPlayer | miniaudio / mpv |
| Thumbnails | `MediaMetadataRetriever` / `ThumbnailUtils` | `AVAssetImageGenerator` / `CGImageSource` | FFmpeg (`ffmpegthumbnailer`) |
| Metadata extraction | `ExifInterface` / `MediaMetadataRetriever` | `CGImageSource` / `AVURLAsset` | FFprobe / ExifTool |
| Transcoding | `MediaCodec` / `MediaMuxer` | `AVAssetExportSession` | FFmpeg |
| Permissions | `ActivityCompat.requestPermissions` | `AVCaptureDevice.requestAccess` | Not required (desktop) |

#### Data Classes

```dart
@freezed
class CameraInfo with _$CameraInfo {
  const factory CameraInfo({
    required String id,
    required CameraPosition position,
    required double maxZoom,
    required double minZoom,
    required List<FlashMode> supportedFlashModes,
    required List<CameraResolution> supportedResolutions,
  }) = _CameraInfo;

  factory CameraInfo.fromJson(Map<String, dynamic> json) =>
      _$CameraInfoFromJson(json);
}

@freezed
class MediaCapture with _$MediaCapture {
  const factory MediaCapture({
    required String vaultHash,
    required String mimeType,
    required int sizeBytes,
    required DateTime capturedAt,
    MediaMetadata? metadata,
  }) = _MediaCapture;

  factory MediaCapture.fromJson(Map<String, dynamic> json) =>
      _$MediaCaptureFromJson(json);
}

@freezed
class MediaMetadata with _$MediaMetadata {
  const factory MediaMetadata({
    int? width,
    int? height,
    Duration? duration,
    String? codec,
    int? bitrate,
    double? frameRate,
    int? sampleRate,
    int? channels,
    Map<String, String>? exif,
    GeoLocation? location,
  }) = _MediaMetadata;

  factory MediaMetadata.fromJson(Map<String, dynamic> json) =>
      _$MediaMetadataFromJson(json);
}

@freezed
class CaptureOptions with _$CaptureOptions {
  const factory CaptureOptions({
    @Default(CameraResolution.high) CameraResolution resolution,
    @Default(FlashMode.auto) FlashMode flash,
    @Default(1.0) double zoom,
    bool? enableStabilization,
    bool? enableHDR,
  }) = _CaptureOptions;

  factory CaptureOptions.fromJson(Map<String, dynamic> json) =>
      _$CaptureOptionsFromJson(json);
}

@freezed
class AudioOptions with _$AudioOptions {
  const factory AudioOptions({
    @Default(44100) int sampleRate,
    @Default(2) int channels,
    @Default(AudioFormat.aac) AudioFormat format,
    @Default(128000) int bitrate,
  }) = _AudioOptions;

  factory AudioOptions.fromJson(Map<String, dynamic> json) =>
      _$AudioOptionsFromJson(json);
}

@freezed
class TranscodeOptions with _$TranscodeOptions {
  const factory TranscodeOptions({
    required String targetMimeType,
    int? targetBitrate,
    int? maxWidth,
    int? maxHeight,
    int? quality, // 0–100
  }) = _TranscodeOptions;

  factory TranscodeOptions.fromJson(Map<String, dynamic> json) =>
      _$TranscodeOptionsFromJson(json);
}

@freezed
class GeoLocation with _$GeoLocation {
  const factory GeoLocation({
    required double latitude,
    required double longitude,
    double? altitude,
  }) = _GeoLocation;

  factory GeoLocation.fromJson(Map<String, dynamic> json) =>
      _$GeoLocationFromJson(json);
}

enum CameraPosition { front, back, external_ }
enum CameraResolution { low, medium, high, max }
enum FlashMode { off, on, auto, torch }
enum AudioFormat { aac, opus, wav, flac }
enum ThumbnailFit { cover, contain, fill }
enum PermissionStatus { granted, denied, permanentlyDenied, restricted }
```

#### Camera Session

The `CameraSession` is a stateful object returned by `openCamera`:

```dart
/// Active camera session with preview and capture control.
///
/// Dispose when done to release camera resources.
abstract class CameraSession {
  /// Live camera preview as a texture widget.
  Widget get previewWidget;

  /// Raw frame stream for processing.
  Stream<CameraFrame> get frames;

  /// Current camera info.
  CameraInfo get cameraInfo;

  /// Whether the session is active.
  bool get isActive;

  /// Release camera resources.
  Future<void> dispose();
}
```

#### Media Player

```dart
/// Audio/video player with standard transport controls.
abstract class MediaPlayer {
  /// Current playback state.
  Stream<PlaybackState> get state;

  /// Current position in the media.
  Stream<Duration> get position;

  /// Total duration of the media.
  Duration? get duration;

  /// Play from current position.
  Future<void> play();

  /// Pause playback.
  Future<void> pause();

  /// Stop and reset to beginning.
  Future<void> stop();

  /// Seek to a specific position.
  Future<void> seekTo(Duration position);

  /// Set playback speed (1.0 = normal).
  Future<void> setSpeed(double speed);

  /// Set volume (0.0–1.0).
  Future<void> setVolume(double volume);

  /// Whether this player supports video.
  bool get hasVideo;

  /// Video widget (null for audio-only).
  Widget? get videoWidget;

  /// Release player resources.
  Future<void> dispose();
}

enum PlaybackState {
  idle,
  loading,
  playing,
  paused,
  stopped,
  completed,
  error,
}
```

---

### 4. AuthService — Crypto & Key Management

**Purpose:** Key generation, secure storage, signing, verification, encryption primitives, biometric authentication, and device identity. The cryptographic foundation for all of Kabuk's security.

**Design Rationale:**
- All encryption in Kabuk flows through AuthService — VaultService uses it for file encryption, MeshService for transport encryption, the knowledge store for at-rest encryption.
- Keys are stored in hardware-backed secure enclaves when available (Android Keystore, iOS Secure Enclave).
- Biometric gates protect sensitive operations without requiring passwords.
- Device identity enables peer-to-peer authentication in MeshService.

#### Interface

```dart
/// Cryptographic operations and key management.
///
/// Provides key generation, storage (hardware-backed where
/// available), encryption, signing, and biometric
/// authentication. All crypto in Kabuk flows through this
/// service.
abstract class AuthService with ServiceLifecycle {
  // ── Key Management ─────────────────────────────────────

  /// Generate a new key pair.
  ///
  /// Keys are generated using platform-native crypto and
  /// stored in the platform keychain/keystore.
  Future<ServiceResult<KeyPair>> generateKeyPair({
    KeyType type = KeyType.ed25519,
    String? label,
    bool requireBiometric = false,
  });

  /// Generate a symmetric key for encryption.
  Future<ServiceResult<String>> generateSymmetricKey({
    SymmetricKeyType type = SymmetricKeyType.aes256,
    String? label,
    bool requireBiometric = false,
  });

  /// Store a key in the platform keychain.
  ///
  /// If [requireBiometric] is true, the key can only be
  /// retrieved after biometric authentication.
  Future<ServiceResult<void>> storeKey(
    String id,
    Uint8List key, {
    bool requireBiometric = false,
    String? label,
  });

  /// Retrieve a key from the platform keychain.
  ///
  /// May trigger biometric authentication if the key was
  /// stored with [requireBiometric].
  Future<ServiceResult<Uint8List>> retrieveKey(String id);

  /// Delete a key from the platform keychain.
  Future<ServiceResult<void>> deleteKey(String id);

  /// List all stored key IDs.
  Future<ServiceResult<List<KeyInfo>>> listKeys();

  /// Check if a key exists.
  Future<bool> keyExists(String id);

  // ── Encryption ─────────────────────────────────────────

  /// Encrypt data with a symmetric key.
  ///
  /// Uses AES-256-GCM. Returns the ciphertext with the
  /// nonce prepended (nonce || ciphertext || tag).
  Future<ServiceResult<Uint8List>> encrypt(
    Uint8List data,
    Uint8List key,
  );

  /// Decrypt data with a symmetric key.
  Future<ServiceResult<Uint8List>> decrypt(
    Uint8List data,
    Uint8List key,
  );

  /// Encrypt data using a stored key ID.
  ///
  /// Convenience method that retrieves the key and encrypts
  /// in one step.
  Future<ServiceResult<Uint8List>> encryptWithKeyId(
    Uint8List data,
    String keyId,
  );

  /// Decrypt data using a stored key ID.
  Future<ServiceResult<Uint8List>> decryptWithKeyId(
    Uint8List data,
    String keyId,
  );

  /// Derive an encryption key from a passphrase.
  ///
  /// Uses Argon2id with the given (or generated) salt.
  /// Returns a tuple of (derivedKey, salt) so the salt
  /// can be stored for re-derivation.
  Future<ServiceResult<DerivedKey>> deriveKey(
    String passphrase, {
    Uint8List? salt,
  });

  // ── Signing ────────────────────────────────────────────

  /// Sign data with a stored private key.
  Future<ServiceResult<Uint8List>> sign(
    Uint8List data,
    String keyId,
  );

  /// Verify a signature against a public key.
  Future<ServiceResult<bool>> verify(
    Uint8List data,
    Uint8List signature,
    Uint8List publicKey,
  );

  // ── Hashing ────────────────────────────────────────────

  /// Compute SHA-256 hash.
  Future<ServiceResult<Uint8List>> hash(Uint8List data);

  /// Compute SHA-256 hash of a stream (for large files).
  Future<ServiceResult<Uint8List>> hashStream(
    Stream<Uint8List> data,
  );

  /// Compute HMAC-SHA-256.
  Future<ServiceResult<Uint8List>> hmac(
    Uint8List data,
    Uint8List key,
  );

  // ── Tokens ─────────────────────────────────────────────

  /// Create a signed JWT-like token.
  ///
  /// Tokens are signed with the device key and can be
  /// verified by peers who have the device's public key.
  Future<ServiceResult<String>> createToken(
    Map<String, dynamic> claims, {
    Duration? expiry,
  });

  /// Verify and decode a token.
  ///
  /// Returns null if the token is invalid or expired.
  Future<ServiceResult<Map<String, dynamic>?>> verifyToken(
    String token,
  );

  // ── Biometrics ─────────────────────────────────────────

  /// Whether biometric authentication is available.
  Future<ServiceResult<BiometricCapability>> biometricCapability();

  /// Authenticate using biometrics.
  ///
  /// [reason] is shown to the user in the biometric prompt.
  Future<ServiceResult<bool>> authenticateWithBiometric({
    String reason = 'Authenticate to continue',
  });

  // ── Device Identity ────────────────────────────────────

  /// Get the stable device identifier.
  ///
  /// This is a hash derived from the device key pair, not
  /// a hardware identifier. It's stable across app restarts
  /// but changes if the device key is regenerated.
  Future<ServiceResult<String>> getDeviceId();

  /// Get the device's public key for sharing with peers.
  Future<ServiceResult<Uint8List>> getDevicePublicKey();

  // ── Random ─────────────────────────────────────────────

  /// Generate cryptographically secure random bytes.
  Future<ServiceResult<Uint8List>> randomBytes(int length);

  /// Generate a cryptographically secure random UUID v4.
  String generateId();

  // ── Capabilities ───────────────────────────────────────

  /// Whether hardware-backed key storage is available.
  bool get hasHardwareKeyStore;

  /// Whether biometric authentication is available.
  bool get hasBiometrics;

  /// Supported key types.
  List<KeyType> get supportedKeyTypes;

  /// Supported symmetric key types.
  List<SymmetricKeyType> get supportedSymmetricKeyTypes;
}
```

#### Platform Mapping

| Capability | Android | iOS | Desktop |
|---|---|---|---|
| Key storage | Android Keystore (hardware-backed on supported devices) | Secure Enclave (hardware) / Keychain (software fallback) | OS keychain: libsecret (Linux), Keychain (macOS), DPAPI (Windows) |
| Biometrics | BiometricPrompt API (fingerprint, face) | LAContext (Face ID / Touch ID) | Not available — graceful degradation |
| Symmetric encryption | AES-256-GCM via javax.crypto / Tink | AES-256-GCM via CryptoKit | AES-256-GCM via libsodium |
| Asymmetric keys | Ed25519 via Tink / Bouncy Castle | Ed25519 via CryptoKit | Ed25519 via libsodium |
| Key derivation | Argon2id via Tink | Argon2id via CryptoKit / custom | Argon2id via libsodium |
| Signing | Ed25519 via Android Keystore | Ed25519 via Secure Enclave | Ed25519 via libsodium |
| Hashing | SHA-256 via `java.security.MessageDigest` | SHA-256 via CryptoKit | SHA-256 via libsodium |
| Random | `SecureRandom` | `SecRandomCopyBytes` | `/dev/urandom` via libsodium |

#### Data Classes

```dart
@freezed
class KeyPair with _$KeyPair {
  const factory KeyPair({
    required String id,
    required KeyType type,
    required Uint8List publicKey,
    required DateTime createdAt,
    required bool requiresBiometric,
    String? label,
    // Private key is never exposed — stays in secure storage
  }) = _KeyPair;

  factory KeyPair.fromJson(Map<String, dynamic> json) =>
      _$KeyPairFromJson(json);
}

@freezed
class KeyInfo with _$KeyInfo {
  const factory KeyInfo({
    required String id,
    required String type, // 'symmetric', 'ed25519', etc.
    required DateTime createdAt,
    required bool requiresBiometric,
    String? label,
  }) = _KeyInfo;

  factory KeyInfo.fromJson(Map<String, dynamic> json) =>
      _$KeyInfoFromJson(json);
}

@freezed
class DerivedKey with _$DerivedKey {
  const factory DerivedKey({
    required Uint8List key,
    required Uint8List salt,
  }) = _DerivedKey;
}

enum KeyType {
  ed25519,
  x25519, // For Diffie-Hellman key exchange
}

enum SymmetricKeyType {
  aes256,
  chaCha20Poly1305,
}

enum BiometricCapability {
  available,
  notAvailable,
  notEnrolled, // Hardware exists but no biometrics enrolled
  lockedOut,   // Too many failed attempts
}
```

#### Key Hierarchy

Kabuk uses a layered key hierarchy:

```
Device Root Key (Ed25519)
├── Generated on first launch, stored in hardware keychain
├── Used for device identity and peer authentication
│
├── Vault Master Key (AES-256)
│   ├── Derived from user passphrase via Argon2id
│   ├── Encrypts individual file keys
│   │
│   └── Per-File Key (AES-256)
│       └── Randomly generated for each vault entry
│
├── Knowledge Store Key (AES-256)
│   ├── Derived from Vault Master Key
│   └── Encrypts the SQLite database via SQLCipher
│
├── Mesh Session Keys (X25519 → AES-256)
│   ├── Ephemeral, per-peer-session
│   └── Established via Diffie-Hellman key exchange
│
└── Token Signing Key (Ed25519)
    ├── Derived from Device Root Key
    └── Signs auth tokens for relay/peer authentication
```

---

### 5. NotificationService — Unified Notifications

**Purpose:** All notifications — local, push, agent-generated — flow through one pipeline. Agents create notifications to alert users; the service handles display, scheduling, and user interaction.

**Design Rationale:**
- Agents are the primary notification producers. When an agent detects something noteworthy (calendar event, file change, message arrival), it creates a notification.
- Notification actions can route back to agents — tapping a notification can resume a conversation or trigger an agent tool.
- Push notifications are optional and go through the same pipeline as local notifications.

#### Interface

```dart
/// Unified notification pipeline.
///
/// Handles local notifications, scheduled notifications,
/// push messages, and notification events (tap, dismiss,
/// action). Agents produce notifications; this service
/// manages display and user interaction routing.
abstract class NotificationService with ServiceLifecycle {
  // ── Display ────────────────────────────────────────────

  /// Show a notification immediately.
  Future<ServiceResult<void>> show(
    KabukNotification notification,
  );

  /// Update an existing notification.
  Future<ServiceResult<void>> update(
    KabukNotification notification,
  );

  /// Cancel a notification by ID.
  Future<ServiceResult<void>> cancel(String id);

  /// Cancel all active notifications.
  Future<ServiceResult<void>> cancelAll();

  /// Get all currently active notifications.
  Future<ServiceResult<List<KabukNotification>>>
      activeNotifications();

  // ── Scheduling ─────────────────────────────────────────

  /// Schedule a notification for a specific time.
  Future<ServiceResult<void>> schedule(
    KabukNotification notification,
    DateTime when,
  );

  /// Schedule a repeating notification.
  Future<ServiceResult<void>> scheduleRepeating(
    KabukNotification notification,
    RepeatInterval interval,
  );

  /// Cancel a scheduled notification.
  Future<ServiceResult<void>> cancelScheduled(String id);

  /// List all scheduled notifications.
  Future<ServiceResult<List<ScheduledNotification>>>
      scheduledNotifications();

  // ── Channels / Groups ──────────────────────────────────

  /// Create a notification channel (Android) or category (iOS).
  ///
  /// Channels control the importance level, sound, vibration,
  /// and grouping of notifications.
  Future<ServiceResult<void>> createChannel(
    NotificationChannel channel,
  );

  /// Delete a notification channel.
  Future<ServiceResult<void>> deleteChannel(String channelId);

  /// List all notification channels.
  Future<ServiceResult<List<NotificationChannel>>> listChannels();

  // ── Events ─────────────────────────────────────────────

  /// Stream of notification events.
  ///
  /// Emits events when notifications are tapped, dismissed,
  /// or when a notification action is triggered.
  Stream<NotificationEvent> get events;

  /// The notification that launched the app (if any).
  ///
  /// Non-null if the app was opened by tapping a notification.
  Future<NotificationEvent?> get launchEvent;

  // ── Push ───────────────────────────────────────────────

  /// Get the push notification token for this device.
  ///
  /// Returns null if push notifications are not configured
  /// or the platform doesn't support them.
  Future<ServiceResult<String?>> getPushToken();

  /// Stream of push token refreshes.
  Stream<String> get pushTokenRefresh;

  /// Incoming push messages.
  Stream<PushMessage> get pushMessages;

  // ── Permissions ────────────────────────────────────────

  /// Check notification permission status.
  Future<PermissionStatus> permissionStatus();

  /// Request notification permission.
  Future<PermissionStatus> requestPermission();

  // ── Badges ─────────────────────────────────────────────

  /// Set the app badge count (iOS / macOS).
  Future<ServiceResult<void>> setBadgeCount(int count);

  /// Clear the app badge.
  Future<ServiceResult<void>> clearBadge();

  // ── Capabilities ───────────────────────────────────────

  /// Whether push notifications are supported.
  bool get supportsPush;

  /// Whether scheduled notifications are supported.
  bool get supportsScheduling;

  /// Whether notification channels are supported.
  bool get supportsChannels;

  /// Whether badge counts are supported.
  bool get supportsBadges;
}
```

#### Platform Mapping

| Capability | Android | iOS | Desktop |
|---|---|---|---|
| Local notifications | `NotificationManager` / `NotificationCompat` | `UNUserNotificationCenter` | Platform-specific (libnotify on Linux, `NSUserNotificationCenter` on macOS, Toast on Windows) |
| Scheduled notifications | `AlarmManager` / `WorkManager` | `UNCalendarNotificationTrigger` / `UNTimeIntervalNotificationTrigger` | Cron (Linux) / `NSTimer` (macOS) / Task Scheduler (Windows) |
| Channels | `NotificationChannel` (API 26+) | Categories (`UNNotificationCategory`) | Not applicable |
| Push | Firebase Cloud Messaging (FCM) | Apple Push Notification Service (APNs) | Not available — graceful degradation |
| Actions | `NotificationCompat.Action` | `UNNotificationAction` | Platform-specific |
| Badges | `ShortcutBadger` / Launcher API | `UNUserNotificationCenter.setBadgeCount` | Not available (except macOS dock) |
| Permission | `POST_NOTIFICATIONS` (API 33+) | `UNUserNotificationCenter.requestAuthorization` | Not required (Linux/macOS), varies (Windows) |

#### Data Classes

```dart
@freezed
class KabukNotification with _$KabukNotification {
  const factory KabukNotification({
    required String id,
    required String title,
    String? body,
    String? channelId,
    NotificationPriority? priority,
    String? imageHash,  // Vault hash for rich media
    String? iconName,
    List<NotificationAction>? actions,
    Map<String, String>? payload, // Routing data for agents
    String? groupId,
    bool? silent,
    bool? ongoing, // Non-dismissible (e.g., media playback)
  }) = _KabukNotification;

  factory KabukNotification.fromJson(
    Map<String, dynamic> json,
  ) => _$KabukNotificationFromJson(json);
}

@freezed
class NotificationAction with _$NotificationAction {
  const factory NotificationAction({
    required String id,
    required String label,
    String? icon,
    bool? destructive,
    bool? authenticationRequired,
  }) = _NotificationAction;

  factory NotificationAction.fromJson(
    Map<String, dynamic> json,
  ) => _$NotificationActionFromJson(json);
}

@freezed
class NotificationChannel with _$NotificationChannel {
  const factory NotificationChannel({
    required String id,
    required String name,
    String? description,
    @Default(NotificationPriority.normal)
    NotificationPriority priority,
    @Default(true) bool sound,
    @Default(true) bool vibration,
    @Default(true) bool badge,
  }) = _NotificationChannel;

  factory NotificationChannel.fromJson(
    Map<String, dynamic> json,
  ) => _$NotificationChannelFromJson(json);
}

@freezed
class NotificationEvent with _$NotificationEvent {
  const factory NotificationEvent.tapped(
    String notificationId,
    Map<String, String>? payload,
  ) = NotificationTapped;
  const factory NotificationEvent.dismissed(
    String notificationId,
  ) = NotificationDismissed;
  const factory NotificationEvent.actionTriggered(
    String notificationId,
    String actionId,
    Map<String, String>? payload,
  ) = NotificationActionTriggered;

  factory NotificationEvent.fromJson(
    Map<String, dynamic> json,
  ) => _$NotificationEventFromJson(json);
}

@freezed
class ScheduledNotification with _$ScheduledNotification {
  const factory ScheduledNotification({
    required KabukNotification notification,
    required DateTime scheduledAt,
    RepeatInterval? repeatInterval,
  }) = _ScheduledNotification;

  factory ScheduledNotification.fromJson(
    Map<String, dynamic> json,
  ) => _$ScheduledNotificationFromJson(json);
}

@freezed
class PushMessage with _$PushMessage {
  const factory PushMessage({
    required String id,
    required Map<String, String> data,
    String? title,
    String? body,
    DateTime? sentAt,
  }) = _PushMessage;

  factory PushMessage.fromJson(Map<String, dynamic> json) =>
      _$PushMessageFromJson(json);
}

enum NotificationPriority { low, normal, high, urgent }

enum RepeatInterval { hourly, daily, weekly, monthly }
```

#### Agent Integration

Agents create notifications through `AgentContext`:

```dart
Future<ToolResult> _onCalendarReminder(
  AgentContext ctx,
  Map<String, dynamic> args,
) async {
  final event = args['event'] as Map<String, dynamic>;

  await ctx.notifications.show(
    KabukNotification(
      id: 'calendar_${event['id']}',
      title: event['title'] as String,
      body: 'Starting in 15 minutes',
      channelId: 'calendar_reminders',
      priority: NotificationPriority.high,
      actions: [
        const NotificationAction(
          id: 'snooze',
          label: 'Snooze 5 min',
        ),
        const NotificationAction(
          id: 'dismiss',
          label: 'Dismiss',
        ),
      ],
      payload: {
        'agent': 'calendar',
        'action': 'open_event',
        'eventId': event['id'] as String,
      },
    ),
  );

  return ToolResult.success({'status': 'notified'});
}
```

When the user taps the notification, the `payload` is routed back through the Router Agent to the Calendar Agent, which handles the `open_event` action.

---

### 6. PresentationService — Display & Cast

**Purpose:** Managing external displays, casting content, screen information, and window management (desktop). Enables agents to present content on external screens and manage the app's display behavior.

**Design Rationale:**
- Smart display and casting capabilities are a natural extension of agent-driven UI.
- Desktop window management is necessary for a proper shell experience.
- Display information (size, density, brightness) is needed for responsive agent-generated UI.

#### Interface

```dart
/// External display, casting, and window management.
///
/// Handles discovery of external displays, casting content,
/// window management (desktop), and screen information.
abstract class PresentationService with ServiceLifecycle {
  // ── Display Discovery ──────────────────────────────────

  /// Discover available external displays and cast targets.
  Future<ServiceResult<List<ExternalDisplay>>>
      discoverDisplays();

  /// Watch for display connection/disconnection.
  Stream<List<ExternalDisplay>> watchDisplays();

  // ── Casting ────────────────────────────────────────────

  /// Start casting content to an external display.
  ///
  /// Returns a [CastSession] that can be used to update
  /// content or stop casting.
  Future<ServiceResult<CastSession>> startCast(
    String displayId,
    Widget content,
  );

  /// Stop an active cast session.
  Future<ServiceResult<void>> stopCast(String sessionId);

  /// Update the content of an active cast session.
  Future<ServiceResult<void>> updateCastContent(
    String sessionId,
    Widget content,
  );

  /// Get all active cast sessions.
  Future<ServiceResult<List<CastSession>>> activeSessions();

  // ── Window Management (Desktop) ────────────────────────

  /// Get the current window size.
  Future<ServiceResult<({double width, double height})>>
      getWindowSize();

  /// Set the window size.
  Future<ServiceResult<void>> setWindowSize(
    double width,
    double height,
  );

  /// Get the current window position.
  Future<ServiceResult<({double x, double y})>>
      getWindowPosition();

  /// Set the window position.
  Future<ServiceResult<void>> setWindowPosition(
    double x,
    double y,
  );

  /// Whether the window is currently fullscreen.
  Future<ServiceResult<bool>> isFullScreen();

  /// Toggle fullscreen mode.
  Future<ServiceResult<void>> toggleFullScreen();

  /// Minimize the window.
  Future<ServiceResult<void>> minimize();

  /// Maximize/restore the window.
  Future<ServiceResult<void>> maximize();

  /// Whether the window is always on top.
  Future<ServiceResult<bool>> isAlwaysOnTop();

  /// Set always-on-top mode.
  Future<ServiceResult<void>> setAlwaysOnTop(bool value);

  /// Set window title.
  Future<ServiceResult<void>> setWindowTitle(String title);

  // ── Screen Info ────────────────────────────────────────

  /// Get information about the primary screen.
  Future<ServiceResult<ScreenInfo>> getScreenInfo();

  /// Get information about all connected screens.
  Future<ServiceResult<List<ScreenInfo>>> getAllScreens();

  /// Get current screen brightness.
  Future<ServiceResult<double>> getBrightness();

  /// Set screen brightness (0.0–1.0).
  Future<ServiceResult<void>> setBrightness(double value);

  /// Get the current system theme mode.
  Future<ServiceResult<ThemeMode>> getThemeMode();

  /// Watch for system theme changes.
  Stream<ThemeMode> watchThemeMode();

  // ── Capabilities ───────────────────────────────────────

  /// Whether external display casting is supported.
  bool get supportsCasting;

  /// Whether window management is available (desktop).
  bool get supportsWindowManagement;

  /// Whether brightness control is available.
  bool get supportsBrightnessControl;
}
```

#### Platform Mapping

| Capability | Android | iOS | Desktop |
|---|---|---|---|
| Cast discovery | MediaRouter API / Google Cast SDK | AirPlay (limited API) | mDNS discovery |
| Casting | Presentation API / MediaRouter | Not available (system-level AirPlay only) | X11/Wayland secondary window (Linux), NSScreen (macOS) |
| Window size/position | Not applicable (fullscreen app) | Not applicable (fullscreen app) | `gtk_window_*` (Linux), `NSWindow` (macOS), `SetWindowPos` (Windows) |
| Fullscreen | Immersive mode | Not applicable | Platform window manager |
| Screen info | `DisplayManager` | `UIScreen` | `GdkDisplay` (Linux), `NSScreen` (macOS), `EnumDisplayMonitors` (Windows) |
| Brightness | `Settings.System.SCREEN_BRIGHTNESS` | `UIScreen.brightness` | Platform-specific / not available on some |
| Theme mode | `UiModeManager` | `UITraitCollection.userInterfaceStyle` | `GSettings` (Linux), `NSAppearance` (macOS), Registry (Windows) |

#### Data Classes

```dart
@freezed
class ExternalDisplay with _$ExternalDisplay {
  const factory ExternalDisplay({
    required String id,
    required String name,
    required ExternalDisplayType type,
    required int widthPixels,
    required int heightPixels,
    required bool isConnected,
  }) = _ExternalDisplay;

  factory ExternalDisplay.fromJson(
    Map<String, dynamic> json,
  ) => _$ExternalDisplayFromJson(json);
}

@freezed
class CastSession with _$CastSession {
  const factory CastSession({
    required String id,
    required String displayId,
    required String displayName,
    required DateTime startedAt,
    required bool isActive,
  }) = _CastSession;

  factory CastSession.fromJson(Map<String, dynamic> json) =>
      _$CastSessionFromJson(json);
}

@freezed
class ScreenInfo with _$ScreenInfo {
  const factory ScreenInfo({
    required double widthPixels,
    required double heightPixels,
    required double widthDp,
    required double heightDp,
    required double density,
    required double refreshRate,
    required ScreenOrientation orientation,
  }) = _ScreenInfo;

  factory ScreenInfo.fromJson(Map<String, dynamic> json) =>
      _$ScreenInfoFromJson(json);
}

enum ExternalDisplayType {
  hdmi,
  wireless,
  chromecast,
  airplay,
  miracast,
  unknown,
}

enum ScreenOrientation {
  portrait,
  landscapeLeft,
  portraitUpsideDown,
  landscapeRight,
}

enum ThemeMode { light, dark, system }
```

---

## AgentContext — Service Access for Agents

Agents never import service providers directly. Instead, all services are bundled into `AgentContext`, which is passed to every tool execution:

```dart
/// Context provided to agents during tool execution.
///
/// Bundles all available services and knowledge store access.
/// Agents use this as their sole interface to system
/// capabilities.
class AgentContext {
  AgentContext({
    required this.knowledge,
    required this.llm,
    required this.vault,
    required this.mesh,
    required this.media,
    required this.auth,
    required this.notifications,
    required this.presentation,
  });

  /// Knowledge store (RDF triple store).
  final KnowledgeStore knowledge;

  /// LLM service for AI operations.
  final LlmService llm;

  /// Encrypted filesystem.
  final VaultService vault;

  /// Networking (P2P + HTTP).
  final MeshService mesh;

  /// Media capture, playback, and processing.
  final MediaService media;

  /// Crypto, keys, and biometrics.
  final AuthService auth;

  /// Notification pipeline.
  final NotificationService notifications;

  /// External display and window management.
  final PresentationService presentation;
}

/// Provider that creates AgentContext from all service
/// providers.
final agentContextProvider = Provider<AgentContext>((ref) {
  return AgentContext(
    knowledge: ref.watch(knowledgeStoreProvider),
    llm: ref.watch(llmServiceProvider),
    vault: ref.watch(vaultServiceProvider),
    mesh: ref.watch(meshServiceProvider),
    media: ref.watch(mediaServiceProvider),
    auth: ref.watch(authServiceProvider),
    notifications: ref.watch(notificationServiceProvider),
    presentation: ref.watch(presentationServiceProvider),
  );
});
```

---

## Error Handling

All services use sealed result types to avoid exceptions crossing layer boundaries:

```dart
/// Result type for all service operations.
///
/// Use pattern matching to handle success and failure:
/// ```dart
/// final result = await vault.retrieve(hash);
/// switch (result) {
///   case ServiceSuccess(:final value):
///     // Use value
///   case ServiceFailure(:final error):
///     // Handle error
/// }
/// ```
sealed class ServiceResult<T> {
  const factory ServiceResult.success(T value) =
      ServiceSuccess;
  const factory ServiceResult.failure(ServiceError error) =
      ServiceFailure;
}

final class ServiceSuccess<T> implements ServiceResult<T> {
  const ServiceSuccess(this.value);
  final T value;
}

final class ServiceFailure<T> implements ServiceResult<T> {
  const ServiceFailure(this.error);
  final ServiceError error;
}

/// Extension for convenient result handling.
extension ServiceResultX<T> on ServiceResult<T> {
  /// Get value or throw.
  T get valueOrThrow => switch (this) {
    ServiceSuccess(:final value) => value,
    ServiceFailure(:final error) => throw error.toException(),
  };

  /// Get value or return default.
  T valueOr(T defaultValue) => switch (this) {
    ServiceSuccess(:final value) => value,
    ServiceFailure() => defaultValue,
  };

  /// Map the success value.
  ServiceResult<R> map<R>(R Function(T) transform) =>
      switch (this) {
    ServiceSuccess(:final value) =>
      ServiceResult.success(transform(value)),
    ServiceFailure(:final error) =>
      ServiceResult.failure(error),
  };

  /// Whether this is a success.
  bool get isSuccess => this is ServiceSuccess<T>;

  /// Whether this is a failure.
  bool get isFailure => this is ServiceFailure<T>;
}
```

### Error Types

```dart
/// Typed errors for all service operations.
///
/// Each variant carries context about what went wrong.
/// Use pattern matching to handle specific error types.
sealed class ServiceError {
  const factory ServiceError.notSupported(String feature) =
      NotSupportedError;
  const factory ServiceError.permissionDenied(
    String permission,
  ) = PermissionDeniedError;
  const factory ServiceError.notFound(String resource) =
      NotFoundError;
  const factory ServiceError.network(String message, {
    int? statusCode,
  }) = NetworkError;
  const factory ServiceError.encryption(String message) =
      EncryptionError;
  const factory ServiceError.timeout(Duration duration) =
      TimeoutError;
  const factory ServiceError.cancelled() = CancelledError;
  const factory ServiceError.storage(String message) =
      StorageError;
  const factory ServiceError.validation(String message) =
      ValidationError;
  const factory ServiceError.unknown(
    Object error,
    StackTrace stack,
  ) = UnknownError;

  /// Convert to an Exception for contexts that need one.
  Exception toException();

  /// Human-readable error message.
  String get message;
}
```

### Error Handling in Agents

Agents must handle errors gracefully — they never throw:

```dart
Future<ToolResult> _readFile(
  AgentContext ctx,
  Map<String, dynamic> args,
) async {
  final hash = args['hash'] as String;
  final result = await ctx.vault.retrieve(hash);

  return switch (result) {
    ServiceSuccess(:final value) => ToolResult.success({
      'data': base64Encode(value),
      'size': value.length,
    }),
    ServiceFailure(error: NotFoundError(:final resource)) =>
      ToolResult.failure('File not found: $resource'),
    ServiceFailure(
      error: PermissionDeniedError(:final permission),
    ) =>
      ToolResult.failure(
        'Permission denied: $permission',
      ),
    ServiceFailure(:final error) =>
      ToolResult.failure('Failed to read file: ${error.message}'),
  };
}
```

---

## Service Capabilities & Feature Detection

Each service exposes capability flags so agents and UI can adapt:

```dart
/// Aggregated service capabilities for the current platform.
@freezed
class ServiceCapabilities with _$ServiceCapabilities {
  const factory ServiceCapabilities({
    // Vault
    required bool vaultEncryption,
    required bool vaultStreaming,
    required int vaultMaxFileSize,

    // Mesh
    required Set<MeshTransport> meshTransports,
    required bool meshPeerToPeer,
    required bool meshRelay,

    // Media
    required bool mediaCamera,
    required bool mediaMicrophone,
    required bool mediaTranscoding,
    required List<String> mediaImageFormats,
    required List<String> mediaVideoFormats,
    required List<String> mediaAudioFormats,

    // Auth
    required bool authHardwareKeyStore,
    required bool authBiometrics,
    required List<KeyType> authKeyTypes,

    // Notifications
    required bool notificationsPush,
    required bool notificationsScheduling,
    required bool notificationsChannels,

    // Presentation
    required bool presentationCasting,
    required bool presentationWindowManagement,
    required bool presentationBrightnessControl,
  }) = _ServiceCapabilities;

  factory ServiceCapabilities.fromJson(
    Map<String, dynamic> json,
  ) => _$ServiceCapabilitiesFromJson(json);
}

/// Provider that queries all services for their capabilities.
final serviceCapabilitiesProvider =
    FutureProvider<ServiceCapabilities>((ref) async {
  final vault = ref.watch(vaultServiceProvider);
  final mesh = ref.watch(meshServiceProvider);
  final media = ref.watch(mediaServiceProvider);
  final auth = ref.watch(authServiceProvider);
  final notifications = ref.watch(notificationServiceProvider);
  final presentation = ref.watch(presentationServiceProvider);

  return ServiceCapabilities(
    vaultEncryption: vault.supportsEncryption,
    vaultStreaming: vault.supportsStreaming,
    vaultMaxFileSize: vault.maxFileSize,
    meshTransports: mesh.supportedTransports,
    meshPeerToPeer: mesh.supportsPeerToPeer,
    meshRelay: mesh.supportsRelay,
    mediaCamera: media.hasCamera,
    mediaMicrophone: media.hasMicrophone,
    mediaTranscoding: media.supportsTranscoding,
    mediaImageFormats: media.supportedImageFormats,
    mediaVideoFormats: media.supportedVideoFormats,
    mediaAudioFormats: media.supportedAudioFormats,
    authHardwareKeyStore: auth.hasHardwareKeyStore,
    authBiometrics: auth.hasBiometrics,
    authKeyTypes: auth.supportedKeyTypes,
    notificationsPush: notifications.supportsPush,
    notificationsScheduling: notifications.supportsScheduling,
    notificationsChannels: notifications.supportsChannels,
    presentationCasting: presentation.supportsCasting,
    presentationWindowManagement:
        presentation.supportsWindowManagement,
    presentationBrightnessControl:
        presentation.supportsBrightnessControl,
  );
});
```

---

## Testing Strategy

### Mock Implementations

Every service has a corresponding mock for testing:

```dart
// Using mocktail
class MockVaultService extends Mock implements VaultService {}
class MockMeshService extends Mock implements MeshService {}
class MockMediaService extends Mock implements MediaService {}
class MockAuthService extends Mock implements AuthService {}
class MockNotificationService extends Mock
    implements NotificationService {}
class MockPresentationService extends Mock
    implements PresentationService {}
```

### In-Memory Implementations

For integration tests, in-memory implementations provide real behavior without platform dependencies:

```dart
/// In-memory VaultService for integration testing.
///
/// Stores data in a Map. No encryption, no filesystem.
class InMemoryVaultService implements VaultService {
  final _entries = <String, (VaultEntry, Uint8List)>{};
  final _changeController =
      StreamController<VaultChange>.broadcast();

  @override
  Future<ServiceResult<VaultEntry>> store(
    Uint8List data, {
    required String name,
    String? mimeType,
    // ...
  }) async {
    final hash = sha256.convert(data).toString();
    final entry = VaultEntry(
      hash: hash,
      name: name,
      mimeType: mimeType ?? 'application/octet-stream',
      size: data.length,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      tags: tags ?? [],
      metadata: metadata ?? {},
      encrypted: false,
    );
    _entries[hash] = (entry, data);
    _changeController.add(VaultChange.created(entry));
    return ServiceResult.success(entry);
  }

  // ... other methods
}
```

### Testing Pattern

```dart
void main() {
  late MockVaultService mockVault;
  late MockAuthService mockAuth;
  late ProviderContainer container;

  setUp(() {
    mockVault = MockVaultService();
    mockAuth = MockAuthService();
    container = ProviderContainer(
      overrides: [
        vaultServiceProvider.overrideWithValue(mockVault),
        authServiceProvider.overrideWithValue(mockAuth),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('store encrypts data via AuthService', () async {
    final data = Uint8List.fromList([1, 2, 3]);
    final encrypted = Uint8List.fromList([4, 5, 6]);

    when(
      () => mockAuth.encryptWithKeyId(data, 'vault_master'),
    ).thenAnswer(
      (_) async => ServiceResult.success(encrypted),
    );
    when(
      () => mockVault.store(
        any(),
        name: any(named: 'name'),
      ),
    ).thenAnswer(
      (_) async => ServiceResult.success(
        VaultEntry(/* ... */),
      ),
    );

    final vault = container.read(vaultServiceProvider);
    final result = await vault.store(data, name: 'test.txt');

    expect(result.isSuccess, isTrue);
    verify(
      () => mockAuth.encryptWithKeyId(data, 'vault_master'),
    ).called(1);
  });
}
```

---

## Implementation Order

### Phase 1 — Foundation (MVP)

| Task | Priority | Status |
|---|---|---|
| Define all 6 service interfaces as abstract classes in `lib/services/` | P0 | [ ] |
| Define `ServiceResult`, `ServiceError` sealed types | P0 | [ ] |
| Define `ServiceLifecycle` mixin | P0 | [ ] |
| Create Riverpod providers for each service | P0 | [ ] |
| Create `AgentContext` that bundles all services | P0 | [ ] |
| Implement `AuthService` for Android (key management + AES-256-GCM) | P0 | [ ] |
| Implement `VaultService` for Android (core CRUD + encryption via AuthService) | P0 | [ ] |
| Implement `NotificationService` for Android (local notifications) | P1 | [ ] |
| Create mock implementations for all 6 services | P0 | [ ] |
| Create in-memory implementations for integration tests | P1 | [ ] |
| Write unit tests for all service interfaces | P0 | [ ] |

### Phase 2 — Core Features

| Task | Priority | Status |
|---|---|---|
| Implement `MediaService` for Android (camera capture + audio recording) | P0 | [ ] |
| Implement `MeshService` — HTTP client only (external API access) | P0 | [ ] |
| Implement `MeshService` — WebSocket support | P1 | [ ] |
| iOS implementation: `AuthService` | P0 | [ ] |
| iOS implementation: `VaultService` | P0 | [ ] |
| iOS implementation: `NotificationService` | P1 | [ ] |
| Implement `ServiceCapabilities` feature detection system | P1 | [ ] |
| VaultService knowledge store integration (mirror entries as RDF triples) | P1 | [ ] |
| Offline message queue for MeshService (Drift-backed) | P2 | [ ] |

### Phase 3 — Connectivity & Media

| Task | Priority | Status |
|---|---|---|
| `MeshService` peer discovery — Android (Nearby Connections API) | P1 | [ ] |
| `MeshService` peer discovery — iOS (MultipeerConnectivity) | P1 | [ ] |
| `MeshService` relay server support (gRPC) | P2 | [ ] |
| `MediaService` transcoding — Android (MediaCodec) | P2 | [ ] |
| `MediaService` transcoding — iOS (AVAssetExportSession) | P2 | [ ] |
| `MediaService` metadata extraction | P1 | [ ] |
| `PresentationService` screen info (all platforms) | P2 | [ ] |
| `PresentationService` casting — Android (MediaRouter) | P2 | [ ] |
| iOS implementation: `MediaService` | P1 | [ ] |
| Desktop implementations: `AuthService`, `VaultService` | P1 | [ ] |

### Phase 4 — Advanced & Polish

| Task | Priority | Status |
|---|---|---|
| `MeshService` BLE transport — Android | P2 | [ ] |
| `MeshService` BLE transport — iOS | P2 | [ ] |
| `MeshService` WiFi Direct — Android | P3 | [ ] |
| Full offline queue with sync-on-reconnect and conflict resolution | P2 | [ ] |
| `PresentationService` window management — Desktop | P2 | [ ] |
| `PresentationService` multi-window — Desktop | P3 | [ ] |
| Desktop implementations: `MeshService`, `MediaService`, `NotificationService` | P2 | [ ] |
| Desktop implementation: `PresentationService` | P3 | [ ] |
| Performance optimization: caching layers for VaultService | P2 | [ ] |
| Performance optimization: connection pooling for MeshService | P2 | [ ] |
| Security audit: key management, encryption flows | P1 | [ ] |

---

## File Organization

```
lib/
  services/                          — Service interfaces (abstract classes)
    vault.dart                       — VaultService interface + data classes
    mesh.dart                        — MeshService interface + data classes
    media.dart                       — MediaService interface + data classes
    auth.dart                        — AuthService interface + data classes
    notification.dart                — NotificationService interface + data classes
    presentation.dart                — PresentationService interface + data classes
    service_result.dart              — ServiceResult, ServiceError sealed types
    service_lifecycle.dart           — ServiceLifecycle mixin
    service_capabilities.dart        — ServiceCapabilities aggregate

  platform/                          — Platform implementations
    android/
      vault_android.dart             — AndroidVaultService
      mesh_android.dart              — AndroidMeshService
      media_android.dart             — AndroidMediaService
      auth_android.dart              — AndroidAuthService
      notification_android.dart      — AndroidNotificationService
      presentation_android.dart      — AndroidPresentationService
    ios/
      vault_ios.dart                 — IosVaultService
      mesh_ios.dart                  — IosMeshService
      media_ios.dart                 — IosMediaService
      auth_ios.dart                  — IosAuthService
      notification_ios.dart          — IosNotificationService
      presentation_ios.dart          — IosPresentationService
    desktop/
      vault_desktop.dart             — DesktopVaultService
      mesh_desktop.dart              — DesktopMeshService
      media_desktop.dart             — DesktopMediaService
      auth_desktop.dart              — DesktopAuthService
      notification_desktop.dart      — DesktopNotificationService
      presentation_desktop.dart      — DesktopPresentationService
    mock/
      vault_mock.dart                — InMemoryVaultService
      mesh_mock.dart                 — InMemoryMeshService
      media_mock.dart                — InMemoryMediaService
      auth_mock.dart                 — InMemoryAuthService
      notification_mock.dart         — InMemoryNotificationService
      presentation_mock.dart         — InMemoryPresentationService

test/
  services/
    vault_test.dart
    mesh_test.dart
    media_test.dart
    auth_test.dart
    notification_test.dart
    presentation_test.dart
    service_result_test.dart
```

---

## Cross-Service Interactions

Services are designed to be composed. Common interaction patterns:

### VaultService + AuthService
VaultService delegates all cryptographic operations to AuthService. It never implements encryption directly.

```
User stores file → VaultService.store()
  → AuthService.encrypt(data, vaultMasterKey)
  → Write encrypted bytes to platform storage
  → Return VaultEntry with hash
```

### MediaService + VaultService
All captured media is stored through VaultService.

```
User takes photo → MediaService.capturePhoto()
  → Platform captures image bytes
  → VaultService.store(bytes, mimeType: 'image/jpeg')
  → Return MediaCapture with vault hash
```

### MeshService + AuthService
Peer connections are authenticated and encrypted using AuthService.

```
Peer connects → MeshService receives connection
  → AuthService.getDevicePublicKey() for identity
  → X25519 key exchange via AuthService
  → Derive session key via AuthService.deriveKey()
  → All subsequent messages encrypted with session key
```

### NotificationService + Agent Layer
Notifications are produced by agents and routed back to agents on interaction.

```
Agent creates notification → NotificationService.show()
  → User taps notification → NotificationEvent emitted
  → Router Agent receives event payload
  → Routes to originating domain agent
  → Agent handles the action
```

### PresentationService + MediaService
Casting media to external display:

```
Agent decides to cast → PresentationService.discoverDisplays()
  → User selects display
  → PresentationService.startCast(displayId, videoWidget)
  → MediaService.createPlayer(hash) for playback
  → Player video widget rendered on external display
```

---

## Security Considerations

### Threat Model

| Threat | Mitigation |
|---|---|
| Data at rest compromise | All vault entries encrypted by default (AES-256-GCM). Knowledge store encrypted via SQLCipher. Keys in hardware keychain. |
| Network eavesdropping | All MeshService connections use end-to-end encryption. TLS for HTTP. X25519 key exchange for P2P. |
| Key extraction | Keys stored in hardware-backed stores (Android Keystore, Secure Enclave). Never exposed in memory longer than needed. |
| Unauthorized access | Biometric gates for sensitive operations. Capability-based tokens for agent access. |
| Malicious RFW widget | RFW execution is sandboxed. No direct service access from RFW templates — only data bindings. |
| Relay server compromise | Relay only routes encrypted blobs. It never has access to plaintext content or encryption keys. |

### Data Flow Encryption

```
┌──────────────┐     encrypted      ┌──────────────┐
│ Knowledge    │ ←────────────────→ │ SQLCipher DB  │
│ Store        │     (DB-level)     │              │
└──────────────┘                    └──────────────┘

┌──────────────┐     encrypted      ┌──────────────┐
│ VaultService │ ←────────────────→ │ Platform     │
│              │   (per-file key)   │ Storage      │
└──────────────┘                    └──────────────┘

┌──────────────┐     encrypted      ┌──────────────┐
│ MeshService  │ ←────────────────→ │ Network      │
│              │  (session key)     │ Transport    │
└──────────────┘                    └──────────────┘
```

---

## Performance Guidelines

### VaultService
- **Thumbnail cache:** Maintain an unencrypted LRU cache of thumbnails for UI performance. Cache is rebuilable and excluded from backups.
- **Streaming for large files:** Always use `streamRetrieve` / `storeStream` for files > 10 MB.
- **Batch operations:** Collect multiple mutations and write in a single transaction where possible.
- **Content hashing:** Hash incrementally during stream operations, not after buffering the entire file.

### MeshService
- **Connection pooling:** Reuse HTTP connections via keep-alive. Maintain a pool of WebSocket connections to frequently contacted peers.
- **Message batching:** For background priority, batch multiple small messages into a single transport frame.
- **Backpressure:** Use Dart stream backpressure mechanisms to prevent memory issues during large transfers.

### MediaService
- **Lazy thumbnail generation:** Generate thumbnails on first access, not on capture. Cache aggressively.
- **Hardware decoding:** Always prefer hardware video decoding when available (MediaCodec, VideoToolbox).
- **Frame dropping:** For camera preview processing by agents, drop frames if the agent can't keep up. Never buffer unlimited frames.

### AuthService
- **Key caching:** Cache unlocked symmetric keys in memory for the session duration (clear on app background after timeout).
- **Batch crypto:** When encrypting multiple small items, use a single key derivation and multiple encrypt calls.
- **Async crypto:** All crypto operations are async to avoid blocking the UI thread. Heavy operations (Argon2id) run in isolates.

---

## Migration & Versioning

Service interfaces are versioned. When a breaking change is needed:

1. Create a new version of the interface (e.g., `VaultServiceV2`).
2. Implement migration logic in the platform layer.
3. The provider selects the appropriate version based on stored schema version.
4. Old data is migrated lazily (on first access) or eagerly (during app upgrade).

```dart
final vaultServiceProvider = Provider<VaultService>((ref) {
  final version = ref.watch(schemaVersionProvider);
  if (version < 2) {
    return AndroidVaultServiceV1(ref); // Legacy
  }
  return AndroidVaultServiceV2(ref); // Current
});
```

Data migrations are idempotent and resumable — if interrupted, they continue from where they left off on next launch.
