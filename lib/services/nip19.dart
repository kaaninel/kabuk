/// NIP-19: bech32-encoded entities (npub, nsec, note, nprofile, nevent, naddr).
///
/// Encodes and decodes Nostr identifiers into human-readable, shareable
/// bech32 strings. Simple entities (npub, nsec, note) are plain bech32.
/// Compound entities (nprofile, nevent, naddr) use TLV (type-length-value)
/// encoding before bech32-encoding.
///
/// Reference: https://github.com/nostr-protocol/nips/blob/master/19.md
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:bech32/bech32.dart';

// ---------------------------------------------------------------------------
// Bit-conversion helper (required for bech32 5-bit ↔ 8-bit conversion)
// ---------------------------------------------------------------------------

/// Converts a list of values with [from]-bit groups to [to]-bit groups.
///
/// Used to convert between 8-bit bytes and the 5-bit words that bech32 uses.
/// When [pad] is true, incomplete final groups are zero-padded.
List<int> convertBits(List<int> data, int from, int to, {bool pad = true}) {
  var acc = 0;
  var bits = 0;
  final result = <int>[];
  final maxv = (1 << to) - 1;

  for (final value in data) {
    if (value < 0 || (value >> from) != 0) {
      throw FormatException('Invalid value $value for $from-bit group');
    }
    acc = (acc << from) | value;
    bits += from;
    while (bits >= to) {
      bits -= to;
      result.add((acc >> bits) & maxv);
    }
  }

  if (pad) {
    if (bits > 0) {
      result.add((acc << (to - bits)) & maxv);
    }
  } else if (bits >= from || ((acc << (to - bits)) & maxv) != 0) {
    throw const FormatException('Excess padding bits in bech32 decode');
  }

  return result;
}

// ---------------------------------------------------------------------------
// Public API — Encode
// ---------------------------------------------------------------------------

/// Encodes a 32-byte public key (hex) as an `npub1…` bech32 string.
String npubEncode(String pubkeyHex) =>
    _encodeSimple('npub', _hexToBytes(pubkeyHex));

/// Encodes a 32-byte private key (hex) as an `nsec1…` bech32 string.
String nsecEncode(String privkeyHex) =>
    _encodeSimple('nsec', _hexToBytes(privkeyHex));

/// Encodes a 32-byte event ID (hex) as a `note1…` bech32 string.
String noteEncode(String eventIdHex) =>
    _encodeSimple('note', _hexToBytes(eventIdHex));

/// Encodes a public key and optional relay hints as an `nprofile1…` string.
///
/// [pubkeyHex] is the 32-byte public key in hex.
/// [relays] are optional relay URLs for routing.
String nprofileEncode(String pubkeyHex, {List<String> relays = const []}) {
  final tlv = <int>[];
  _writeTlv(tlv, 0, _hexToBytes(pubkeyHex));
  for (final relay in relays) {
    _writeTlv(tlv, 1, Uint8List.fromList(utf8.encode(relay)));
  }
  return _encodeSimple('nprofile', Uint8List.fromList(tlv));
}

/// Encodes an event reference as an `nevent1…` string.
///
/// [eventIdHex] is the event ID in hex. [relays] are optional hint relays.
/// [authorPubkeyHex] is the event author's public key (optional but useful).
/// [kind] is the event kind (optional).
String neventEncode(
  String eventIdHex, {
  List<String> relays = const [],
  String? authorPubkeyHex,
  int? kind,
}) {
  final tlv = <int>[];
  _writeTlv(tlv, 0, _hexToBytes(eventIdHex));
  for (final relay in relays) {
    _writeTlv(tlv, 1, Uint8List.fromList(utf8.encode(relay)));
  }
  if (authorPubkeyHex != null) {
    _writeTlv(tlv, 2, _hexToBytes(authorPubkeyHex));
  }
  if (kind != null) {
    _writeTlv(tlv, 3, _intToBytes4(kind));
  }
  return _encodeSimple('nevent', Uint8List.fromList(tlv));
}

/// Encodes a parameterized replaceable event address as an `naddr1…` string.
///
/// [identifier] is the `d` tag value. [authorPubkeyHex] is the author's
/// pubkey. [kind] is the event kind (e.g. 30023 for long-form content).
/// [relays] are optional hint relays.
String naddrEncode(
  String identifier, {
  required String authorPubkeyHex,
  required int kind,
  List<String> relays = const [],
}) {
  final tlv = <int>[];
  _writeTlv(tlv, 0, Uint8List.fromList(utf8.encode(identifier)));
  for (final relay in relays) {
    _writeTlv(tlv, 1, Uint8List.fromList(utf8.encode(relay)));
  }
  _writeTlv(tlv, 2, _hexToBytes(authorPubkeyHex));
  _writeTlv(tlv, 3, _intToBytes4(kind));
  return _encodeSimple('naddr', Uint8List.fromList(tlv));
}

// ---------------------------------------------------------------------------
// Public API — Decode
// ---------------------------------------------------------------------------

/// Decodes any NIP-19 bech32-encoded entity.
///
/// Returns one of:
/// - [Nip19Npub]
/// - [Nip19Nsec]
/// - [Nip19Note]
/// - [Nip19Nprofile]
/// - [Nip19Nevent]
/// - [Nip19Naddr]
///
/// Throws [FormatException] if the input is not a valid NIP-19 string.
Nip19Entity nip19Decode(String encoded) {
  final lower = encoded.toLowerCase();
  final Bech32 bech32Result;
  try {
    // NIP-19 allows up to 5000 chars for TLV types.
    bech32Result = const Bech32Codec().decode(lower, 5000);
  } on Exception catch (e) {
    throw FormatException('Invalid bech32: $e', encoded);
  }

  final hrp = bech32Result.hrp;
  final data5bit = bech32Result.data;
  final Uint8List bytes;
  try {
    final converted = convertBits(data5bit, 5, 8, pad: false);
    bytes = Uint8List.fromList(converted);
  } on Exception catch (e) {
    throw FormatException('Bit conversion failed: $e', encoded);
  }

  return switch (hrp) {
    'npub' => Nip19Npub(pubkeyHex: _bytesToHex(bytes)),
    'nsec' => Nip19Nsec(privkeyHex: _bytesToHex(bytes)),
    'note' => Nip19Note(eventIdHex: _bytesToHex(bytes)),
    'nprofile' => _decodeNprofile(bytes),
    'nevent' => _decodeNevent(bytes),
    'naddr' => _decodeNaddr(bytes),
    _ => throw FormatException('Unknown NIP-19 prefix: $hrp', encoded),
  };
}

/// Convenience: tries [nip19Decode] and returns `null` on error.
Nip19Entity? tryNip19Decode(String encoded) {
  try {
    return nip19Decode(encoded);
  } on Object {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Entity types
// ---------------------------------------------------------------------------

/// Base class for all decoded NIP-19 entities.
sealed class Nip19Entity {
  const Nip19Entity();
}

/// Decoded `npub1…` — a public key.
final class Nip19Npub extends Nip19Entity {
  /// Creates a [Nip19Npub].
  const Nip19Npub({required this.pubkeyHex});

  /// The 32-byte public key in hex.
  final String pubkeyHex;

  /// Re-encodes to `npub1…` string.
  String encode() => npubEncode(pubkeyHex);

  @override
  String toString() => 'Nip19Npub(${pubkeyHex.substring(0, 8)}...)';
}

/// Decoded `nsec1…` — a private key.
final class Nip19Nsec extends Nip19Entity {
  /// Creates a [Nip19Nsec].
  const Nip19Nsec({required this.privkeyHex});

  /// The 32-byte private key in hex.
  final String privkeyHex;

  /// Re-encodes to `nsec1…` string.
  String encode() => nsecEncode(privkeyHex);
}

/// Decoded `note1…` — an event ID.
final class Nip19Note extends Nip19Entity {
  /// Creates a [Nip19Note].
  const Nip19Note({required this.eventIdHex});

  /// The 32-byte event ID in hex.
  final String eventIdHex;

  /// Re-encodes to `note1…` string.
  String encode() => noteEncode(eventIdHex);

  @override
  String toString() => 'Nip19Note(${eventIdHex.substring(0, 8)}...)';
}

/// Decoded `nprofile1…` — a profile with optional relay hints.
final class Nip19Nprofile extends Nip19Entity {
  /// Creates a [Nip19Nprofile].
  const Nip19Nprofile({required this.pubkeyHex, this.relays = const []});

  /// The author's public key in hex.
  final String pubkeyHex;

  /// Relay hints for locating this profile.
  final List<String> relays;

  /// Re-encodes to `nprofile1…` string.
  String encode() => nprofileEncode(pubkeyHex, relays: relays);

  @override
  String toString() => 'Nip19Nprofile(${pubkeyHex.substring(0, 8)}...)';
}

/// Decoded `nevent1…` — an event reference with optional relay hints.
final class Nip19Nevent extends Nip19Entity {
  /// Creates a [Nip19Nevent].
  const Nip19Nevent({
    required this.eventIdHex,
    this.relays = const [],
    this.authorPubkeyHex,
    this.kind,
  });

  /// The event ID in hex.
  final String eventIdHex;

  /// Relay hints for locating this event.
  final List<String> relays;

  /// The event author's public key (if included).
  final String? authorPubkeyHex;

  /// The event kind (if included).
  final int? kind;

  /// Re-encodes to `nevent1…` string.
  String encode() => neventEncode(
    eventIdHex,
    relays: relays,
    authorPubkeyHex: authorPubkeyHex,
    kind: kind,
  );

  @override
  String toString() => 'Nip19Nevent(${eventIdHex.substring(0, 8)}...)';
}

/// Decoded `naddr1…` — a parameterized replaceable event address.
final class Nip19Naddr extends Nip19Entity {
  /// Creates a [Nip19Naddr].
  const Nip19Naddr({
    required this.identifier,
    required this.authorPubkeyHex,
    required this.kind,
    this.relays = const [],
  });

  /// The `d` tag value identifying this specific replaceable event.
  final String identifier;

  /// The author's public key in hex.
  final String authorPubkeyHex;

  /// The event kind (e.g. 30023 for long-form content).
  final int kind;

  /// Relay hints.
  final List<String> relays;

  /// Re-encodes to `naddr1…` string.
  String encode() => naddrEncode(
    identifier,
    authorPubkeyHex: authorPubkeyHex,
    kind: kind,
    relays: relays,
  );

  @override
  String toString() =>
      'Nip19Naddr(kind: $kind, d: $identifier, '
      'author: ${authorPubkeyHex.substring(0, 8)}...)';
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

String _encodeSimple(String hrp, Uint8List bytes) {
  final data5bit = convertBits(bytes, 8, 5, pad: true);
  return const Bech32Codec().encode(Bech32(hrp, data5bit));
}

void _writeTlv(List<int> out, int type, Uint8List value) {
  out.add(type);
  out.add(value.length);
  out.addAll(value);
}

Nip19Nprofile _decodeNprofile(Uint8List bytes) {
  String? pubkeyHex;
  final relays = <String>[];

  var i = 0;
  while (i + 1 < bytes.length) {
    final type = bytes[i];
    final len = bytes[i + 1];
    i += 2;
    if (i + len > bytes.length) break;
    final value = bytes.sublist(i, i + len);
    i += len;

    if (type == 0 && value.length == 32) {
      pubkeyHex = _bytesToHex(value);
    } else if (type == 1) {
      relays.add(utf8.decode(value));
    }
  }

  if (pubkeyHex == null) {
    throw const FormatException('nprofile missing pubkey TLV-0');
  }
  return Nip19Nprofile(pubkeyHex: pubkeyHex, relays: relays);
}

Nip19Nevent _decodeNevent(Uint8List bytes) {
  String? eventIdHex;
  final relays = <String>[];
  String? authorPubkeyHex;
  int? kind;

  var i = 0;
  while (i + 1 < bytes.length) {
    final type = bytes[i];
    final len = bytes[i + 1];
    i += 2;
    if (i + len > bytes.length) break;
    final value = bytes.sublist(i, i + len);
    i += len;

    switch (type) {
      case 0:
        if (value.length == 32) eventIdHex = _bytesToHex(value);
      case 1:
        relays.add(utf8.decode(value));
      case 2:
        if (value.length == 32) authorPubkeyHex = _bytesToHex(value);
      case 3:
        if (value.length == 4) kind = _bytesToInt4(value);
    }
  }

  if (eventIdHex == null) {
    throw const FormatException('nevent missing event id TLV-0');
  }
  return Nip19Nevent(
    eventIdHex: eventIdHex,
    relays: relays,
    authorPubkeyHex: authorPubkeyHex,
    kind: kind,
  );
}

Nip19Naddr _decodeNaddr(Uint8List bytes) {
  String? identifier;
  String? authorPubkeyHex;
  int? kind;
  final relays = <String>[];

  var i = 0;
  while (i + 1 < bytes.length) {
    final type = bytes[i];
    final len = bytes[i + 1];
    i += 2;
    if (i + len > bytes.length) break;
    final value = bytes.sublist(i, i + len);
    i += len;

    switch (type) {
      case 0:
        identifier = utf8.decode(value);
      case 1:
        relays.add(utf8.decode(value));
      case 2:
        if (value.length == 32) authorPubkeyHex = _bytesToHex(value);
      case 3:
        if (value.length == 4) kind = _bytesToInt4(value);
    }
  }

  if (identifier == null || authorPubkeyHex == null || kind == null) {
    throw const FormatException(
      'naddr missing required TLV fields (d, author, kind)',
    );
  }
  return Nip19Naddr(
    identifier: identifier,
    authorPubkeyHex: authorPubkeyHex,
    kind: kind,
    relays: relays,
  );
}

String _bytesToHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final b in bytes) {
    buffer.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

Uint8List _hexToBytes(String hex) {
  if (hex.length % 2 != 0) {
    throw FormatException('Odd-length hex string', hex);
  }
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < hex.length; i += 2) {
    result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return result;
}

Uint8List _intToBytes4(int value) {
  return Uint8List(4)..buffer.asByteData().setUint32(0, value);
}

int _bytesToInt4(Uint8List bytes) {
  return ByteData.sublistView(bytes).getUint32(0);
}
