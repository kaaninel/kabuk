/// Concrete implementation of [DeviceSyncService].
///
/// Handles device identification (persistent device ID), QR-based pairing,
/// and bidirectional knowledge store synchronization over HTTP.
/// Uses the existing [KabukMeshSync] for peer discovery and the
/// [KabukDatabase] for persistence.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:kabuk/platform/shared/mesh_sync.dart';
import 'package:kabuk/services/auth.dart';
import 'package:kabuk/services/device_sync.dart';
import 'package:kabuk/services/mesh.dart';
import 'package:path_provider/path_provider.dart';

/// Shared implementation of [DeviceSyncService].
///
/// Works across all platforms. Uses:
/// - A persistent device ID stored in the app documents directory
/// - [KabukDatabase] for device pair records
/// - [KabukMeshSync] for LAN peer discovery
/// - A lightweight HTTP server for incoming sync requests
/// - An HTTP client for outgoing sync requests
class SharedDeviceSyncService implements DeviceSyncService {
  /// Creates a [SharedDeviceSyncService].
  SharedDeviceSyncService({
    required this.db,
    required this.auth,
    required this.meshSync,
  });

  /// The database for device pair persistence.
  final KabukDatabase db;

  /// Auth service for getting the current identity.
  final AuthService auth;

  /// Mesh sync for peer discovery.
  final KabukMeshSync meshSync;

  // Internal state
  String? _deviceId;
  String? _deviceName;
  HttpServer? _syncServer;
  StreamSubscription<MeshPeer>? _peerSub;
  Timer? _syncTimer;
  final Map<String, DeviceSyncState> _syncStates = {};
  final StreamController<DeviceSyncState> _syncStateController =
      StreamController<DeviceSyncState>.broadcast();

  // Discovered peers on the local network (deviceId → address).
  final Map<String, Uri> _discoveredPeers = {};

  // ---------------------------------------------------------------------------
  // Device identification
  // ---------------------------------------------------------------------------

  @override
  Future<DeviceInfo> getDeviceInfo() async {
    final id = await _ensureDeviceId();
    final name = await _getDeviceName();
    final pubKeyHex = await auth.getPublicKeyHex() ?? '';
    return DeviceInfo(
      deviceId: id,
      deviceName: name,
      publicKeyHex: pubKeyHex,
    );
  }

  @override
  Future<void> setDeviceName(String name) async {
    _deviceName = name;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/device_name.txt');
    await file.writeAsString(name);
  }

  Future<String> _ensureDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/device_id.txt');

    if (await file.exists()) {
      _deviceId = (await file.readAsString()).trim();
      if (_deviceId!.isNotEmpty) return _deviceId!;
    }

    // Generate a new 16-char hex device ID.
    final rng = Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    _deviceId = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await file.writeAsString(_deviceId!);

    dev.log('Generated new device ID: $_deviceId', name: 'DeviceSync');
    return _deviceId!;
  }

  Future<String> _getDeviceName() async {
    if (_deviceName != null) return _deviceName!;

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/device_name.txt');

    if (await file.exists()) {
      _deviceName = (await file.readAsString()).trim();
      if (_deviceName!.isNotEmpty) return _deviceName!;
    }

    // Default: platform hostname or generic name.
    _deviceName = Platform.localHostname.isNotEmpty
        ? Platform.localHostname
        : 'Kabuk Device';
    return _deviceName!;
  }

  // ---------------------------------------------------------------------------
  // Pairing
  // ---------------------------------------------------------------------------

  @override
  Future<DevicePairingPayload> generatePairingPayload() async {
    final info = await getDeviceInfo();

    // Generate a 6-char alphanumeric verification code.
    final rng = Random.secure();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final code = List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();

    return DevicePairingPayload(
      deviceId: info.deviceId,
      deviceName: info.deviceName,
      publicKeyHex: info.publicKeyHex,
      pairingCode: code,
      pairingExpiry: DateTime.now().add(const Duration(minutes: 10)),
      syncPort: info.syncPort,
    );
  }

  @override
  Future<String> confirmPairing(DevicePairingPayload remotePayload) async {
    if (remotePayload.isExpired) {
      throw StateError('Pairing payload has expired');
    }

    final localId = await _ensureDeviceId();
    final localPubKey = await auth.getPublicKeyHex() ?? '';

    // Verify both devices share the same identity.
    if (remotePayload.publicKeyHex != localPubKey) {
      throw StateError(
        'Cannot pair: devices have different identities. '
        'Import the same identity on both devices first.',
      );
    }

    // Generate a pairing token: HMAC(shared_secret, localId + remoteId).
    final sharedSecret = '$localPubKey:${remotePayload.pairingCode}';
    final hmac = Hmac(sha256, utf8.encode(sharedSecret));
    final tokenDigest = hmac.convert(
      utf8.encode('$localId:${remotePayload.deviceId}'),
    );
    final pairingToken = tokenDigest.toString();

    // Store the pairing.
    await db.upsertDevicePair(
      DevicePairsCompanion(
        localDeviceId: Value(localId),
        remoteDeviceId: Value(remotePayload.deviceId),
        remoteName: Value(remotePayload.deviceName),
        sharedPublicKeyHex: Value(localPubKey),
        pairingToken: Value(pairingToken),
        isVerified: const Value(true),
        createdAt: Value(DateTime.now()),
        lastSeenAt: Value(DateTime.now()),
      ),
    );

    dev.log(
      'Paired with device: ${remotePayload.deviceName} (${remotePayload.deviceId})',
      name: 'DeviceSync',
    );

    return pairingToken;
  }

  @override
  Future<void> removePairing(String remoteDeviceId) async {
    final localId = await _ensureDeviceId();
    await db.deleteDevicePair(localId, remoteDeviceId);
    _syncStates.remove(remoteDeviceId);
    dev.log('Removed pairing with device: $remoteDeviceId', name: 'DeviceSync');
  }

  @override
  Future<List<PairedDevice>> listPairedDevices() async {
    final localId = await _ensureDeviceId();
    final pairs = await db.getPairedDevices(localId);
    return pairs.map(_pairToDevice).toList();
  }

  @override
  Stream<List<PairedDevice>> watchPairedDevices() async* {
    final localId = await _ensureDeviceId();
    yield* db.watchPairedDevices(localId).map(
      (pairs) => pairs.map(_pairToDevice).toList(),
    );
  }

  PairedDevice _pairToDevice(DevicePair pair) {
    final isOnline = _discoveredPeers.containsKey(pair.remoteDeviceId);
    return PairedDevice(
      deviceId: pair.remoteDeviceId,
      deviceName: pair.remoteName,
      sharedPublicKeyHex: pair.sharedPublicKeyHex,
      lastSeenAt: pair.lastSeenAt,
      lastSyncAt: pair.lastSyncAt,
      isOnline: isOnline,
      isVerified: pair.isVerified,
    );
  }

  // ---------------------------------------------------------------------------
  // Sync lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> startSync() async {
    if (_syncServer != null) return; // Already running.

    try {
      // Start the HTTP sync server.
      _syncServer = await HttpServer.bind(InternetAddress.anyIPv4, 5400);
      _syncServer!.listen(_handleSyncRequest);
      dev.log('Sync server started on :5400', name: 'DeviceSync');
    } on Object catch (e) {
      dev.log('Failed to start sync server: $e', name: 'DeviceSync');
    }

    // Listen for discovered peers.
    _peerSub = meshSync.peers.listen(_onPeerDiscovered);

    // Periodic auto-sync every 5 minutes.
    _syncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => syncAll(),
    );
  }

  @override
  Future<void> stopSync() async {
    _syncTimer?.cancel();
    await _peerSub?.cancel();
    await _syncServer?.close();
    _syncServer = null;
    dev.log('Sync service stopped', name: 'DeviceSync');
  }

  void _onPeerDiscovered(MeshPeer peer) async {
    _discoveredPeers[peer.id] = peer.address;

    // Check if this is a paired device.
    final localId = await _ensureDeviceId();
    final pair = await db.getDevicePair(localId, peer.id);
    if (pair != null) {
      // Update last-seen and address.
      await db.touchDevicePair(
        localId,
        peer.id,
        address: peer.address.toString(),
      );
      dev.log(
        'Paired device discovered: ${peer.name} at ${peer.address}',
        name: 'DeviceSync',
      );
      // Trigger sync with this device.
      unawaited(_syncWithPeer(peer.id, peer.address));
    }
  }

  // ---------------------------------------------------------------------------
  // Sync protocol
  // ---------------------------------------------------------------------------

  @override
  Future<int> syncWithDevice(String remoteDeviceId) async {
    final address = _discoveredPeers[remoteDeviceId];
    if (address == null) {
      throw StateError('Device $remoteDeviceId is not reachable');
    }
    return _syncWithPeer(remoteDeviceId, address);
  }

  @override
  Future<void> syncAll() async {
    final localId = await _ensureDeviceId();
    final pairs = await db.getPairedDevices(localId);

    for (final pair in pairs) {
      final address = _discoveredPeers[pair.remoteDeviceId];
      if (address != null) {
        try {
          await _syncWithPeer(pair.remoteDeviceId, address);
        } on Object catch (e) {
          dev.log(
            'Sync failed with ${pair.remoteName}: $e',
            name: 'DeviceSync',
          );
        }
      }
    }
  }

  @override
  Stream<DeviceSyncState> watchSyncState(String remoteDeviceId) {
    return _syncStateController.stream.where(
      (s) => s.remoteDeviceId == remoteDeviceId,
    );
  }

  /// Perform a bidirectional sync with a specific peer.
  Future<int> _syncWithPeer(String remoteId, Uri address) async {
    _emitSyncState(remoteId, SyncStatus.syncing);

    try {
      final localId = await _ensureDeviceId();
      final pair = await db.getDevicePair(localId, remoteId);
      if (pair == null) return 0;

      // Step 1: Get our changes since last sync.
      final lastSyncVersion = await _getLastSyncVersion(remoteId);
      final outgoing = await db.getTriplesSince(lastSyncVersion);

      // Step 2: Send our changes and get theirs.
      final client = HttpClient();
      try {
        final syncUri = address.resolve('/sync');
        final request = await client.postUrl(syncUri);
        request.headers.contentType = ContentType.json;

        final payload = {
          'deviceId': localId,
          'pairingToken': pair.pairingToken,
          'sinceVersion': lastSyncVersion,
          'triples': outgoing.map(_tripleToJson).toList(),
        };
        request.write(jsonEncode(payload));

        final response = await request.close();
        if (response.statusCode != 200) {
          final body = await utf8.decodeStream(response);
          throw StateError('Sync failed: ${response.statusCode} $body');
        }

        final responseBody = await utf8.decodeStream(response);
        final responseData = jsonDecode(responseBody) as Map<String, dynamic>;
        final incomingTriples =
            (responseData['triples'] as List<dynamic>?) ?? [];

        // Step 3: Apply incoming triples.
        var applied = 0;
        for (final tripleJson in incomingTriples) {
          final t = tripleJson as Map<String, dynamic>;
          await _applyIncomingTriple(t);
          applied++;
        }

        final total = outgoing.length + applied;

        // Step 4: Update sync state.
        await db.markSynced(localId, remoteId);
        await _setLastSyncVersion(
          remoteId,
          (responseData['maxVersion'] as int?) ?? lastSyncVersion,
        );

        _emitSyncState(
          remoteId,
          SyncStatus.synced,
          triplesExchanged: total,
        );

        dev.log(
          'Sync complete with $remoteId: sent=${outgoing.length}, received=$applied',
          name: 'DeviceSync',
        );
        return total;
      } finally {
        client.close();
      }
    } on Object catch (e) {
      _emitSyncState(remoteId, SyncStatus.failed, error: e.toString());
      rethrow;
    }
  }

  /// Handle an incoming sync request from a paired device.
  Future<void> _handleSyncRequest(HttpRequest request) async {
    if (request.method != 'POST' || request.uri.path != '/sync') {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found');
      await request.response.close();
      return;
    }

    try {
      final body = await utf8.decodeStream(request);
      final data = jsonDecode(body) as Map<String, dynamic>;

      final remoteId = data['deviceId'] as String?;
      final token = data['pairingToken'] as String?;
      final sinceVersion = (data['sinceVersion'] as int?) ?? 0;
      final incomingTriples = (data['triples'] as List<dynamic>?) ?? [];

      if (remoteId == null || token == null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Missing deviceId or pairingToken');
        await request.response.close();
        return;
      }

      // Verify the pairing.
      final localId = await _ensureDeviceId();
      final pair = await db.getDevicePair(localId, remoteId);
      if (pair == null || pair.pairingToken != token) {
        request.response
          ..statusCode = HttpStatus.forbidden
          ..write('Unknown or invalid device');
        await request.response.close();
        return;
      }

      // Apply incoming triples.
      for (final tripleJson in incomingTriples) {
        await _applyIncomingTriple(tripleJson as Map<String, dynamic>);
      }

      // Send our changes.
      final outgoing = await db.getTriplesSince(sinceVersion);
      final maxVersion = await db.getMaxSyncVersion();

      final response = {
        'triples': outgoing.map(_tripleToJson).toList(),
        'maxVersion': maxVersion,
      };

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(response));
      await request.response.close();

      // Update sync timestamps.
      await db.touchDevicePair(
        localId,
        remoteId,
        address: request.connectionInfo?.remoteAddress.address,
      );
      await db.markSynced(localId, remoteId);

      dev.log(
        'Handled sync from $remoteId: received=${incomingTriples.length}, sent=${outgoing.length}',
        name: 'DeviceSync',
      );
    } on Object catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('Sync error: $e');
      await request.response.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Triple serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _tripleToJson(Triple triple) {
    return {
      'subject': triple.subject,
      'predicate': triple.predicate,
      'objectType': triple.objectType,
      'objectUri': triple.objectUri,
      'objectString': triple.objectString,
      'objectInt': triple.objectInt,
      'objectReal': triple.objectReal,
      'graph': triple.graph,
      'syncVersion': triple.syncVersion,
      'updatedAt': triple.updatedAt.millisecondsSinceEpoch,
    };
  }

  Future<void> _applyIncomingTriple(Map<String, dynamic> t) async {
    final subject = t['subject'] as String;
    final predicate = t['predicate'] as String;
    final objectType = t['objectType'] as String;
    final graph = (t['graph'] as String?) ?? 'default';

    // Use insertOrIgnore to avoid duplicates.
    await db.insertTriple(
      TriplesCompanion(
        subject: Value(subject),
        predicate: Value(predicate),
        objectType: Value(objectType),
        objectUri: t['objectUri'] != null
            ? Value(t['objectUri'] as String)
            : const Value.absent(),
        objectString: t['objectString'] != null
            ? Value(t['objectString'] as String)
            : const Value.absent(),
        objectInt: t['objectInt'] != null
            ? Value(t['objectInt'] as int)
            : const Value.absent(),
        objectReal: t['objectReal'] != null
            ? Value((t['objectReal'] as num).toDouble())
            : const Value.absent(),
        graph: Value(graph),
        syncVersion: Value((t['syncVersion'] as int?) ?? 0),
        updatedAt: t['updatedAt'] != null
            ? Value(DateTime.fromMillisecondsSinceEpoch(t['updatedAt'] as int))
            : Value(DateTime.now()),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sync version tracking (per remote device)
  // ---------------------------------------------------------------------------

  Future<int> _getLastSyncVersion(String remoteDeviceId) async {
    final triples = await db.findTriples(
      subject: 'kabuk:sync/$remoteDeviceId',
      predicate: 'kabuk:lastSyncVersion',
    );
    if (triples.isEmpty) return 0;
    return triples.first.objectInt ?? 0;
  }

  Future<void> _setLastSyncVersion(String remoteDeviceId, int version) async {
    await db.deleteTriple(
      subject: 'kabuk:sync/$remoteDeviceId',
      predicate: 'kabuk:lastSyncVersion',
    );
    await db.insertTriple(
      TriplesCompanion(
        subject: Value('kabuk:sync/$remoteDeviceId'),
        predicate: const Value('kabuk:lastSyncVersion'),
        objectType: const Value('integer'),
        objectInt: Value(version),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _emitSyncState(
    String remoteId,
    SyncStatus status, {
    String? error,
    int triplesExchanged = 0,
  }) {
    final state = DeviceSyncState(
      remoteDeviceId: remoteId,
      status: status,
      lastSyncAt: status == SyncStatus.synced ? DateTime.now() : null,
      lastError: error,
      triplesExchanged: triplesExchanged,
    );
    _syncStates[remoteId] = state;
    _syncStateController.add(state);
  }
}
