/// Mesh service — networking, sync, and peer discovery.
///
/// Platform implementations provide the concrete behavior.
/// Agents access this only through `AgentContext`.
library;

/// Abstract interface for networking and device-to-device sync.
///
/// The mesh service handles HTTP requests, peer discovery on the local
/// network, and opportunistic sync of knowledge store data between
/// the user's devices.
abstract interface class MeshService {
  /// Send an HTTP GET request to [url] with optional [headers].
  Future<MeshResponse> get(Uri url, {Map<String, String>? headers});

  /// Send an HTTP POST request to [url] with a [body] and optional [headers].
  Future<MeshResponse> post(
    Uri url, {
    Object? body,
    Map<String, String>? headers,
  });

  /// Discover peers on the local network.
  Stream<MeshPeer> discoverPeers();

  /// Whether the device currently has network connectivity.
  Future<bool> get isConnected;
}

/// A response from an HTTP request.
class MeshResponse {
  /// Creates a [MeshResponse] with the given [statusCode], [body], and [headers].
  const MeshResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  /// The HTTP status code.
  final int statusCode;

  /// The response body as a string.
  final String body;

  /// Response headers.
  final Map<String, String> headers;
}

/// A peer discovered on the local network.
class MeshPeer {
  /// Creates a [MeshPeer] with the given [id], [name], and [address].
  const MeshPeer({required this.id, required this.name, required this.address});

  /// Unique identifier for this peer.
  final String id;

  /// Human-readable name of the peer.
  final String name;

  /// Network address of the peer.
  final Uri address;
}
