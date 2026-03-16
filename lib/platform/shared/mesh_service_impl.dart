/// Shared [MeshService] implementation using `package:http`.
///
/// Provides real HTTP GET/POST via the cross-platform `http` package.
/// Peer discovery uses UDP multicast via [KabukMeshSync].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:kabuk/platform/shared/mesh_sync.dart';
import 'package:kabuk/services/mesh.dart';

/// Cross-platform [MeshService] backed by `package:http` and [KabukMeshSync].
///
/// HTTP operations work on all platforms. Peer discovery uses UDP
/// multicast beacons — works on LAN without additional plugins.
class SharedMeshService implements MeshService {
  /// Creates a [SharedMeshService].
  ///
  /// An optional [client] can be injected for testing.
  SharedMeshService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  KabukMeshSync? _meshSync;

  @override
  Future<MeshResponse> get(Uri url, {Map<String, String>? headers}) async {
    final response = await _client.get(url, headers: headers);
    return MeshResponse(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );
  }

  @override
  Future<MeshResponse> post(
    Uri url, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    final String? encodedBody;
    if (body == null) {
      encodedBody = null;
    } else if (body is String) {
      encodedBody = body;
    } else {
      encodedBody = jsonEncode(body);
    }

    final response = await _client.post(
      url,
      headers: headers,
      body: encodedBody,
    );
    return MeshResponse(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );
  }

  @override
  Stream<MeshPeer> discoverPeers() {
    // Start the sync engine lazily and return its peer stream.
    _meshSync ??= KabukMeshSync();
    final sync = _meshSync!;
    // Start in background; errors are swallowed gracefully inside KabukMeshSync.
    unawaited(sync.start());
    return sync.peers;
  }

  @override
  Future<bool> get isConnected async {
    try {
      final result = await InternetAddress.lookup('example.com');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }
}


