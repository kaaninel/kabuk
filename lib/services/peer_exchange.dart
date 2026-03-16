/// Peer exchange service — contact sharing via QR codes and local discovery.
///
/// Provides a platform-agnostic interface for exchanging identity
/// information between nearby Kabuk users. Supports QR code generation
/// and parsing, with the data payload encoding the user's public
/// identity and optional display metadata.
///
/// The exchange payload is a compact JSON envelope:
/// ```json
/// {
///   "v": 1,
///   "npub": "npub1...",
///   "name": "Alice",
///   "relays": ["wss://relay.damus.io"]
/// }
/// ```
library;

import 'dart:convert';

import 'package:meta/meta.dart';

/// The data exchanged when two Kabuk users share contact information.
///
/// Designed to be compact enough for a QR code while carrying all the
/// information needed to establish a Nostr DM conversation.
@immutable
class PeerExchangePayload {
  /// Creates a [PeerExchangePayload].
  const PeerExchangePayload({
    required this.npub,
    this.name,
    this.publicKeyHex,
    this.relays = const [],
  });

  /// Decodes a [PeerExchangePayload] from its JSON string representation.
  ///
  /// Returns `null` if the string is not valid exchange JSON or the
  /// version is unsupported.
  static PeerExchangePayload? tryParse(String raw) {
    try {
      // Check if it starts with the kabuk: URI scheme for quick detection.
      final jsonStr = raw.startsWith('kabuk:contact?')
          ? _decodeUriScheme(raw)
          : raw;
      if (jsonStr == null) return null;

      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final version = map['v'] as int?;
      if (version == null || version > 1) return null;

      final npub = map['npub'] as String?;
      if (npub == null || npub.isEmpty) return null;

      return PeerExchangePayload(
        npub: npub,
        name: map['name'] as String?,
        publicKeyHex: map['hex'] as String?,
        relays: (map['relays'] as List<dynamic>?)
                ?.cast<String>()
                .toList(growable: false) ??
            const [],
      );
    } on Object {
      return null;
    }
  }

  /// The Nostr npub (bech32-encoded public key) — the core identity.
  final String npub;

  /// Optional human-readable display name.
  final String? name;

  /// Optional hex-encoded public key (convenience, derivable from npub).
  final String? publicKeyHex;

  /// Optional list of preferred relay URLs for reaching this peer.
  final List<String> relays;

  /// Encodes this payload to a compact JSON string suitable for QR codes.
  String encode() {
    final map = <String, dynamic>{
      'v': 1,
      'npub': npub,
    };
    if (name != null && name!.isNotEmpty) map['name'] = name;
    if (publicKeyHex != null) map['hex'] = publicKeyHex;
    if (relays.isNotEmpty) map['relays'] = relays;
    return jsonEncode(map);
  }

  /// Encodes as a `kabuk:contact?data=...` URI for cleaner QR display.
  String encodeAsUri() {
    final data = base64Url.encode(utf8.encode(encode()));
    return 'kabuk:contact?data=$data';
  }

  /// Decodes a `kabuk:contact?data=...` URI to raw JSON.
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
