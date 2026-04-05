/// Device sync service — pairing, identity sharing, and knowledge replication.
///
/// Manages device-to-device pairing via QR codes and synchronizes the
/// knowledge store between paired devices that share the same Nostr identity.
/// Platform implementations provide the concrete behavior.
/// Agents access this only through `AgentContext`.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Device info
// ---------------------------------------------------------------------------

/// Information about this device, used in pairing and sync.
@immutable
class DeviceInfo {
  /// Creates a [DeviceInfo].
  const DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.publicKeyHex,
    this.syncPort = 5400,
  });

  /// Unique 16-character hex identifier for this device.
  final String deviceId;

  /// Human-readable device name (e.g. "Alice's iPhone").
  final String deviceName;

  /// Hex-encoded Nostr public key of the identity on this device.
  final String publicKeyHex;

  /// Port the sync HTTP server listens on.
  final int syncPort;
}

// ---------------------------------------------------------------------------
// Pairing payload
// ---------------------------------------------------------------------------

/// The data exchanged during device pairing via QR code.
///
/// Extends the contact exchange format with device-specific fields.
/// The payload is compact enough for a QR code (~300 bytes).
@immutable
class DevicePairingPayload {
  /// Creates a [DevicePairingPayload].
  const DevicePairingPayload({
    required this.deviceId,
    required this.deviceName,
    required this.publicKeyHex,
    required this.pairingCode,
    required this.pairingExpiry,
    this.syncPort = 5400,
  });

  /// Decodes a [DevicePairingPayload] from its JSON string representation.
  ///
  /// Returns `null` if the string is not valid pairing JSON or the
  /// version/type is unsupported.
  static DevicePairingPayload? tryParse(String raw) {
    try {
      final jsonStr = raw.startsWith('kabuk:pair?')
          ? _decodeUriScheme(raw)
          : raw;
      if (jsonStr == null) return null;

      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final version = map['v'] as int?;
      if (version == null || version > 1) return null;
      if (map['type'] != 'device-pair') return null;

      final deviceId = map['did'] as String?;
      final pubKeyHex = map['hex'] as String?;
      final code = map['code'] as String?;
      final expiryMs = map['exp'] as int?;
      if (deviceId == null || pubKeyHex == null || code == null) return null;

      return DevicePairingPayload(
        deviceId: deviceId,
        deviceName: (map['name'] as String?) ?? 'Unknown Device',
        publicKeyHex: pubKeyHex,
        pairingCode: code,
        pairingExpiry: expiryMs != null
            ? DateTime.fromMillisecondsSinceEpoch(expiryMs)
            : DateTime.now().add(const Duration(minutes: 10)),
        syncPort: (map['port'] as int?) ?? 5400,
      );
    } on Object {
      return null;
    }
  }

  /// Unique identifier of the device offering to pair.
  final String deviceId;

  /// Human-readable name of the device.
  final String deviceName;

  /// Hex-encoded public key of the identity on this device.
  final String publicKeyHex;

  /// Short alphanumeric code for manual verification.
  final String pairingCode;

  /// When this pairing offer expires.
  final DateTime pairingExpiry;

  /// Sync HTTP port.
  final int syncPort;

  /// Whether this pairing offer has expired.
  bool get isExpired => DateTime.now().isAfter(pairingExpiry);

  /// Encodes this payload to a compact JSON string suitable for QR codes.
  String encode() {
    return jsonEncode({
      'v': 1,
      'type': 'device-pair',
      'did': deviceId,
      'name': deviceName,
      'hex': publicKeyHex,
      'code': pairingCode,
      'exp': pairingExpiry.millisecondsSinceEpoch,
      'port': syncPort,
    });
  }

  /// Encodes as a `kabuk:pair?data=...` URI for QR display.
  String encodeAsUri() {
    final data = base64Url.encode(utf8.encode(encode()));
    return 'kabuk:pair?data=$data';
  }

  static String? _decodeUriScheme(String uri) {
    try {
      final qmark = uri.indexOf('?');
      if (qmark < 0) return null;
      final params = Uri.splitQueryString(uri.substring(qmark + 1));
      final data = params['data'];
      if (data == null) return null;
      return utf8.decode(base64Url.decode(data));
    } on Object {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Sync state
// ---------------------------------------------------------------------------

/// The current state of sync with a paired device.
enum SyncStatus {
  /// No sync in progress, idle.
  idle,

  /// Currently discovering the peer on the network.
  discovering,

  /// Sync in progress — exchanging data.
  syncing,

  /// Last sync completed successfully.
  synced,

  /// Last sync failed.
  failed,
}

/// A snapshot of the sync state with a specific paired device.
@immutable
class DeviceSyncState {
  /// Creates a [DeviceSyncState].
  const DeviceSyncState({
    required this.remoteDeviceId,
    this.status = SyncStatus.idle,
    this.lastSyncAt,
    this.lastError,
    this.triplesExchanged = 0,
  });

  /// The remote device this state relates to.
  final String remoteDeviceId;

  /// Current sync status.
  final SyncStatus status;

  /// When the last successful sync completed.
  final DateTime? lastSyncAt;

  /// Error message from the last failed sync, if any.
  final String? lastError;

  /// Number of triples exchanged in the last sync.
  final int triplesExchanged;
}

// ---------------------------------------------------------------------------
// Service interface
// ---------------------------------------------------------------------------

/// Abstract interface for device pairing and knowledge sync.
///
/// Manages the full lifecycle: device identification, QR-based pairing,
/// local network discovery of paired devices, and bidirectional
/// knowledge store synchronization.
abstract interface class DeviceSyncService {
  /// Get information about this device.
  Future<DeviceInfo> getDeviceInfo();

  /// Set a custom name for this device.
  Future<void> setDeviceName(String name);

  // -------------------------------------------------------------------------
  // Pairing
  // -------------------------------------------------------------------------

  /// Generate a time-limited pairing payload for display as QR code.
  ///
  /// The payload includes this device's ID, the current identity's
  /// public key, and a short verification code. Valid for ~10 minutes.
  Future<DevicePairingPayload> generatePairingPayload();

  /// Confirm a pairing with a remote device.
  ///
  /// Validates the payload, stores the pairing in the database,
  /// and returns the pairing token for mutual authentication.
  Future<String> confirmPairing(DevicePairingPayload remotePayload);

  /// Remove a device pairing.
  Future<void> removePairing(String remoteDeviceId);

  /// List all paired devices for the current identity.
  Future<List<PairedDevice>> listPairedDevices();

  /// Watch paired devices reactively.
  Stream<List<PairedDevice>> watchPairedDevices();

  // -------------------------------------------------------------------------
  // Sync
  // -------------------------------------------------------------------------

  /// Start the sync service (HTTP server + peer discovery).
  ///
  /// Call this at app startup. Listens for incoming sync requests
  /// from paired devices and periodically syncs with discovered peers.
  Future<void> startSync();

  /// Stop the sync service.
  Future<void> stopSync();

  /// Trigger an immediate sync with a specific paired device.
  ///
  /// Returns the number of triples exchanged (sent + received).
  Future<int> syncWithDevice(String remoteDeviceId);

  /// Trigger sync with all reachable paired devices.
  Future<void> syncAll();

  /// Watch the sync state for a specific device.
  Stream<DeviceSyncState> watchSyncState(String remoteDeviceId);
}

/// A paired device with its current status.
@immutable
class PairedDevice {
  /// Creates a [PairedDevice].
  const PairedDevice({
    required this.deviceId,
    required this.deviceName,
    required this.sharedPublicKeyHex,
    this.lastSeenAt,
    this.lastSyncAt,
    this.isOnline = false,
    this.isVerified = false,
  });

  /// Unique device identifier.
  final String deviceId;

  /// Human-readable device name.
  final String deviceName;

  /// The shared Nostr identity public key (hex).
  final String sharedPublicKeyHex;

  /// When this device was last seen on the network.
  final DateTime? lastSeenAt;

  /// When the last successful sync completed.
  final DateTime? lastSyncAt;

  /// Whether this device is currently reachable.
  final bool isOnline;

  /// Whether this pairing has been mutually verified.
  final bool isVerified;
}
