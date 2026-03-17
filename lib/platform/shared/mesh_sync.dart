/// Kabuk Mesh sync protocol — peer discovery and knowledge-store replication.
///
/// Devices on the same local network announce their presence via UDP
/// multicast (224.0.0.251:5354 — the mDNS address, but using a custom
/// service type `_kabuk._tcp`). When a peer is found, both sides
/// exchange capability messages and optionally replicate changes from
/// the knowledge store.
///
/// Design:
///  - Discovery: UDP multicast announcements every 30 s
///  - Sync: HTTP POST to `http://<peer>:<syncPort>/sync` with a JSON
///    payload of recent [ChangeSet] triples.
///  - No external mDNS or NSD packages are required; the protocol is
///    self-contained for maximum portability.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';

import 'package:kabuk/knowledge/changes.dart' show ChangeSet;
import 'package:kabuk/knowledge/exports.dart' show ChangeSet;
import 'package:kabuk/services/mesh.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// UDP multicast group used for Kabuk peer discovery.
const _kMulticastGroup = '224.0.0.251';

/// Port for Kabuk mesh announcements.
const _kDiscoveryPort = 5399;

/// HTTP port served by each peer for sync payloads.
const _kSyncPort = 5400;

/// How often to broadcast a presence beacon.
const _kBeaconInterval = Duration(seconds: 30);

/// How long a peer is considered alive without a new beacon.
const _kPeerTtl = Duration(seconds: 90);

// ---------------------------------------------------------------------------
// KabukMeshSync
// ---------------------------------------------------------------------------

/// Manages Kabuk-to-Kabuk peer discovery and sync.
///
/// Call [start] to begin broadcasting beacons and listening for peers.
/// Call [stop] to tear everything down. Discovered peers are emitted
/// on [peers].
class KabukMeshSync {
  /// Creates a [KabukMeshSync].
  KabukMeshSync({this.deviceId, this.deviceName});

  /// The unique device identifier (generated if null).
  final String? deviceId;

  /// Human-readable name for this device.
  final String? deviceName;

  final StreamController<MeshPeer> _peerController =
      StreamController<MeshPeer>.broadcast();

  /// Emits each newly discovered or re-announced peer.
  Stream<MeshPeer> get peers => _peerController.stream;

  // Multicast sockets
  RawDatagramSocket? _sendSocket;
  RawDatagramSocket? _recvSocket;

  // Timer for periodic beacons.
  Timer? _beaconTimer;

  // Track seen peers and their last-seen time.
  final Map<String, _PeerRecord> _peers = {};
  Timer? _evictionTimer;

  bool _running = false;

  /// The resolved local device ID.
  late final String _id = deviceId ?? _generateId();

  /// The resolved local device name.
  late final String _name =
      deviceName ?? (Platform.localHostname.isEmpty
      ? 'Kabuk Device'
      : Platform.localHostname);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Start listening for peers and broadcasting presence.
  Future<void> start() async {
    if (_running) return;
    _running = true;

    try {
      // Receive socket joined to multicast group.
      _recvSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _kDiscoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _recvSocket!.joinMulticast(
        InternetAddress(_kMulticastGroup),
      );
      _recvSocket!.listen(_onDatagram);

      // Send socket (outgoing multicast datagrams).
      _sendSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      );
      _sendSocket!.multicastHops = 1;
    } on Object catch (e) {
      dev.log('KabukMeshSync: Failed to open sockets: $e', name: 'MeshSync');
      return;
    }

    // Broad immediately then on timer.
    _broadcastBeacon();
    _beaconTimer = Timer.periodic(_kBeaconInterval, (_) => _broadcastBeacon());

    // Evict stale peers.
    _evictionTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _evictStale(),
    );

    dev.log('KabukMeshSync started (id=$_id)', name: 'MeshSync');
  }

  /// Stop discovery and close sockets.
  Future<void> stop() async {
    _running = false;
    _beaconTimer?.cancel();
    _evictionTimer?.cancel();
    _recvSocket?.close();
    _sendSocket?.close();
    await _peerController.close();
    dev.log('KabukMeshSync stopped', name: 'MeshSync');
  }

  // ---------------------------------------------------------------------------
  // Beacon
  // ---------------------------------------------------------------------------

  void _broadcastBeacon() {
    if (!_running || _sendSocket == null) return;
    final payload = jsonEncode({
      'type': 'kabuk.beacon',
      'id': _id,
      'name': _name,
      'syncPort': _kSyncPort,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    try {
      _sendSocket!.send(
        utf8.encode(payload),
        InternetAddress(_kMulticastGroup),
        _kDiscoveryPort,
      );
    } on Object catch (e) {
      dev.log('KabukMeshSync: Beacon send failed: $e', name: 'MeshSync');
    }
  }

  // ---------------------------------------------------------------------------
  // Receiving
  // ---------------------------------------------------------------------------

  void _onDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _recvSocket?.receive();
    if (datagram == null) return;

    try {
      final message =
          jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      if (message['type'] != 'kabuk.beacon') return;

      final peerId = message['id'] as String?;
      if (peerId == null || peerId == _id) return; // Ignore self.

      final peerName = message['name'] as String? ?? 'Unknown';
      final syncPort = message['syncPort'] as int? ?? _kSyncPort;
      final peerIp = datagram.address.address;
      final peerUri = Uri.parse('http://$peerIp:$syncPort');

      final peer = MeshPeer(id: peerId, name: peerName, address: peerUri);

      final existing = _peers[peerId];
      _peers[peerId] = _PeerRecord(peer: peer, lastSeen: DateTime.now());

      if (existing == null) {
        // New peer — emit to stream.
        _peerController.add(peer);
        dev.log(
          'KabukMeshSync: Discovered peer $peerName ($peerIp)',
          name: 'MeshSync',
        );
      }
    } on Object catch (e) {
      dev.log('KabukMeshSync: Bad datagram: $e', name: 'MeshSync');
    }
  }

  // ---------------------------------------------------------------------------
  // Eviction
  // ---------------------------------------------------------------------------

  void _evictStale() {
    final now = DateTime.now();
    _peers.removeWhere(
      (_, r) => now.difference(r.lastSeen) > _kPeerTtl,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _generateId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// An internal record of a discovered peer with a TTL timestamp.
class _PeerRecord {
  const _PeerRecord({required this.peer, required this.lastSeen});
  final MeshPeer peer;
  final DateTime lastSeen;
}

// ---------------------------------------------------------------------------
// utf8 helper used silently above — re-export the core import
// ---------------------------------------------------------------------------
