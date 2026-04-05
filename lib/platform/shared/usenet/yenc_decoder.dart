/// Pure Dart yEnc binary decoder for Usenet articles.
///
/// Implements the yEnc v1.3 specification for decoding single-part
/// and multi-part encoded binary articles. Includes a built-in CRC32
/// implementation for checksum validation.
///
/// yEnc is the de-facto standard encoding for binary files on Usenet,
/// offering ~1–2 % overhead compared to ~33 % for Base64/UUEncode.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// Parsed `=ybegin` header fields.
@immutable
class YencHeader {
  /// Creates a [YencHeader].
  const YencHeader({
    required this.size,
    required this.name,
    required this.line,
    this.part,
    this.total,
  });

  /// Expected decoded file size in bytes.
  final int size;

  /// Original filename.
  final String name;

  /// Encoded line length.
  final int line;

  /// Part number (multi-part only).
  final int? part;

  /// Total number of parts (multi-part only).
  final int? total;

  @override
  String toString() =>
      'YencHeader(size: $size, name: $name, line: $line, '
      'part: $part, total: $total)';
}

/// Parsed `=ypart` header fields.
@immutable
class YencPartHeader {
  /// Creates a [YencPartHeader].
  const YencPartHeader({
    required this.begin,
    required this.end,
  });

  /// Byte offset start (1-based per yEnc spec).
  final int begin;

  /// Byte offset end (inclusive).
  final int end;

  @override
  String toString() => 'YencPartHeader(begin: $begin, end: $end)';
}

/// Parsed `=yend` trailer fields.
@immutable
class YencTrailer {
  /// Creates a [YencTrailer].
  const YencTrailer({
    required this.size,
    this.crc32,
    this.pcrc32,
    this.part,
  });

  /// Actual decoded size reported by the encoder.
  final int size;

  /// CRC32 checksum of this part's decoded data (hex in the trailer).
  final int? crc32;

  /// CRC32 of the entire reassembled file (present on the final part).
  final int? pcrc32;

  /// Part number (multi-part only).
  final int? part;

  @override
  String toString() =>
      'YencTrailer(size: $size, crc32: ${crc32 != null ? '0x${crc32!.toRadixString(16)}' : null}, '
      'pcrc32: ${pcrc32 != null ? '0x${pcrc32!.toRadixString(16)}' : null}, '
      'part: $part)';
}

/// Complete result of a yEnc decode operation.
@immutable
class YencResult {
  /// Creates a [YencResult].
  const YencResult({
    required this.data,
    required this.header,
    required this.trailer,
    this.partHeader,
    required this.checksumValid,
  });

  /// Decoded binary payload.
  final Uint8List data;

  /// Parsed `=ybegin` header.
  final YencHeader header;

  /// Parsed `=ypart` header (present for multi-part articles).
  final YencPartHeader? partHeader;

  /// Parsed `=yend` trailer.
  final YencTrailer trailer;

  /// Whether the CRC32 in the trailer matched the computed checksum.
  ///
  /// `true` when the trailer contains a CRC and it matches, or when
  /// the trailer omits the CRC entirely (nothing to compare).
  final bool checksumValid;

  @override
  String toString() =>
      'YencResult(name: ${header.name}, size: ${data.length}, '
      'checksumValid: $checksumValid)';
}

// ---------------------------------------------------------------------------
// CRC32
// ---------------------------------------------------------------------------

/// CRC32 (ISO 3309 / ITU-T V.42) calculator with a pre-computed lookup table.
///
/// Used internally by [YencDecoder] to validate checksums.
class Crc32 {
  Crc32._();

  /// Standard CRC32 polynomial (reversed representation).
  static const int _polynomial = 0xEDB88320;

  /// Pre-computed lookup table (256 entries).
  static final Uint32List _table = _buildTable();

  static Uint32List _buildTable() {
    final table = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      var crc = i;
      for (var j = 0; j < 8; j++) {
        if (crc & 1 == 1) {
          crc = (crc >> 1) ^ _polynomial;
        } else {
          crc = crc >> 1;
        }
      }
      table[i] = crc;
    }
    return table;
  }

  /// Computes the CRC32 of [data].
  ///
  /// Optionally pass a previous [crc] to continue an incremental
  /// calculation (e.g. across multiple parts).
  static int compute(Uint8List data, [int crc = 0]) {
    var c = crc ^ 0xFFFFFFFF;
    for (var i = 0; i < data.length; i++) {
      c = _table[(c ^ data[i]) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

// ---------------------------------------------------------------------------
// Decoder
// ---------------------------------------------------------------------------

/// ASCII constants used during parsing.
const int _cr = 0x0D; // \r
const int _lf = 0x0A; // \n
const int _equals = 0x3D; // =

/// yEnc binary decoder supporting single-part and multi-part articles.
///
/// ```dart
/// final decoder = YencDecoder();
/// final result = decoder.decode(rawBytes);
/// print(result.header.name); // original filename
/// print(result.checksumValid); // CRC32 match
/// ```
class YencDecoder {
  /// Creates a [YencDecoder].
  const YencDecoder();

  // ---- public API ---------------------------------------------------------

  /// Returns `true` if [data] appears to contain a yEnc-encoded payload.
  ///
  /// Performs a fast scan for the `=ybegin ` marker without fully parsing.
  static bool isYencEncoded(List<int> data) {
    final marker = _asciiBytes('=ybegin ');
    if (data.length < marker.length) return false;
    // Scan for marker at the start of any line.
    outer:
    for (var i = 0; i <= data.length - marker.length; i++) {
      if (i == 0 || (i >= 1 && data[i - 1] == _lf)) {
        for (var j = 0; j < marker.length; j++) {
          if (data[i + j] != marker[j]) continue outer;
        }
        return true;
      }
    }
    return false;
  }

  /// Decodes a single-part yEnc-encoded article body.
  ///
  /// Throws [FormatException] if the data is malformed or missing
  /// required headers.
  YencResult decode(List<int> rawArticleBody) =>
      _decode(rawArticleBody, requirePart: false);

  /// Decodes one part of a multi-part yEnc-encoded article.
  ///
  /// Throws [FormatException] if the `=ypart` header is missing or
  /// the data is otherwise malformed.
  YencResult decodePart(List<int> rawArticleBody) =>
      _decode(rawArticleBody, requirePart: true);

  // ---- internal -----------------------------------------------------------

  YencResult _decode(List<int> raw, {required bool requirePart}) {
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);

    // -- locate =ybegin ---------------------------------------------------
    final beginLineStart = _findLineStart(bytes, '=ybegin ');
    if (beginLineStart == -1) {
      throw const FormatException('Missing =ybegin header');
    }
    final beginLineEnd = _findLineEnd(bytes, beginLineStart);
    final header = _parseBeginLine(bytes, beginLineStart, beginLineEnd);

    // -- locate =ypart (optional / required for multi-part) ----------------
    var bodyStart = beginLineEnd;
    YencPartHeader? partHeader;
    final partLineStart = _findLineStart(bytes, '=ypart ', bodyStart);
    if (partLineStart != -1 && partLineStart == bodyStart) {
      final partLineEnd = _findLineEnd(bytes, partLineStart);
      partHeader = _parsePartLine(bytes, partLineStart, partLineEnd);
      bodyStart = partLineEnd;
    }
    if (requirePart && partHeader == null) {
      throw const FormatException(
        'Multi-part decode requested but =ypart header is missing',
      );
    }

    // -- locate =yend -----------------------------------------------------
    final endLineStart = _findLineStart(bytes, '=yend ', bodyStart);
    if (endLineStart == -1) {
      throw const FormatException('Missing =yend trailer');
    }
    final endLineEnd = _findLineEnd(bytes, endLineStart);
    final trailer = _parseEndLine(bytes, endLineStart, endLineEnd);

    // -- decode body bytes ------------------------------------------------
    final bodyEnd = endLineStart;
    final decoded = _decodeBody(bytes, bodyStart, bodyEnd);

    // -- CRC32 validation -------------------------------------------------
    final checksumValid = _validateCrc(decoded, trailer, partHeader != null);

    return YencResult(
      data: decoded,
      header: header,
      partHeader: partHeader,
      trailer: trailer,
      checksumValid: checksumValid,
    );
  }

  // ---- header parsing -----------------------------------------------------

  /// Parses the `=ybegin` line into a [YencHeader].
  YencHeader _parseBeginLine(Uint8List bytes, int start, int end) {
    final line = _latin1Decode(bytes, start, end);
    final size = _requiredInt(line, 'size');
    final lineLen = _requiredInt(line, 'line');
    final name = _requiredString(line, 'name');
    final part = _optionalInt(line, 'part');
    final total = _optionalInt(line, 'total');
    return YencHeader(
      size: size,
      name: name,
      line: lineLen,
      part: part,
      total: total,
    );
  }

  /// Parses the `=ypart` line into a [YencPartHeader].
  YencPartHeader _parsePartLine(Uint8List bytes, int start, int end) {
    final line = _latin1Decode(bytes, start, end);
    final begin = _requiredInt(line, 'begin');
    final endVal = _requiredInt(line, 'end');
    return YencPartHeader(begin: begin, end: endVal);
  }

  /// Parses the `=yend` line into a [YencTrailer].
  YencTrailer _parseEndLine(Uint8List bytes, int start, int end) {
    final line = _latin1Decode(bytes, start, end);
    final size = _requiredInt(line, 'size');
    final crc32 = _optionalHex(line, 'crc32');
    final pcrc32 = _optionalHex(line, 'pcrc32');
    final part = _optionalInt(line, 'part');
    return YencTrailer(size: size, crc32: crc32, pcrc32: pcrc32, part: part);
  }

  // ---- body decoding ------------------------------------------------------

  /// Decodes the yEnc payload between [start] and [end].
  Uint8List _decodeBody(Uint8List bytes, int start, int end) {
    final builder = BytesBuilder(copy: false);
    // Pre-allocate a buffer; worst case is same length as input.
    final buffer = Uint8List(end - start);
    var bufLen = 0;
    var i = start;

    while (i < end) {
      final b = bytes[i];

      // Skip \r and \n — they are line separators, not data.
      if (b == _cr || b == _lf) {
        i++;
        continue;
      }

      if (b == _equals) {
        // Escape sequence: next byte minus 106 (42 + 64) mod 256.
        i++;
        if (i >= end) {
          throw const FormatException(
            'Unexpected end of data after escape character',
          );
        }
        buffer[bufLen++] = (bytes[i] - 106) & 0xFF;
      } else {
        buffer[bufLen++] = (b - 42) & 0xFF;
      }
      i++;
    }

    // Return a correctly-sized view.
    if (bufLen == buffer.length) return buffer;
    builder.add(Uint8List.sublistView(buffer, 0, bufLen));
    return builder.takeBytes();
  }

  // ---- CRC validation -----------------------------------------------------

  bool _validateCrc(Uint8List decoded, YencTrailer trailer, bool isMultiPart) {
    // For multi-part articles the per-part CRC is in `crc32`;
    // for single-part articles it may be in `crc32` or `pcrc32`.
    final expected = isMultiPart
        ? (trailer.crc32 ?? trailer.pcrc32)
        : (trailer.pcrc32 ?? trailer.crc32);
    if (expected == null) return true; // no checksum to compare
    return Crc32.compute(decoded) == expected;
  }

  // ---- low-level helpers --------------------------------------------------

  /// Returns the byte offset of the first line starting with [prefix]
  /// at or after [from], or `-1` if not found.
  static int _findLineStart(Uint8List bytes, String prefix, [int from = 0]) {
    final p = _asciiBytes(prefix);
    outer:
    for (var i = from; i <= bytes.length - p.length; i++) {
      if (i == 0 || bytes[i - 1] == _lf) {
        for (var j = 0; j < p.length; j++) {
          if (bytes[i + j] != p[j]) continue outer;
        }
        return i;
      }
    }
    return -1;
  }

  /// Returns the byte offset just past the `\r\n` (or `\n`, or EOF)
  /// that terminates the line starting at [start].
  static int _findLineEnd(Uint8List bytes, int start) {
    for (var i = start; i < bytes.length; i++) {
      if (bytes[i] == _lf) return i + 1;
    }
    return bytes.length;
  }

  /// Decodes a byte range to a Latin-1 string, trimming trailing `\r\n`.
  static String _latin1Decode(Uint8List bytes, int start, int end) {
    var e = end;
    while (e > start && (bytes[e - 1] == _cr || bytes[e - 1] == _lf)) {
      e--;
    }
    return String.fromCharCodes(bytes, start, e);
  }

  /// Extracts a required integer keyword value from a header [line].
  static int _requiredInt(String line, String key) {
    final value = _optionalInt(line, key);
    if (value == null) {
      throw FormatException('Missing required keyword "$key" in: $line');
    }
    return value;
  }

  /// Extracts an optional integer keyword value from a header [line].
  static int? _optionalInt(String line, String key) {
    final value = _extractValue(line, key);
    if (value == null) return null;
    return int.tryParse(value);
  }

  /// Extracts an optional hexadecimal keyword value from a header [line].
  static int? _optionalHex(String line, String key) {
    final value = _extractValue(line, key);
    if (value == null) return null;
    return int.tryParse(value, radix: 16);
  }

  /// Extracts the required `name=` value, which extends to end of line
  /// (the name may contain spaces and `=` characters).
  static String _requiredString(String line, String key) {
    final tag = ' $key=';
    final idx = line.indexOf(tag);
    if (idx == -1) {
      throw FormatException('Missing required keyword "$key" in: $line');
    }
    return line.substring(idx + tag.length);
  }

  /// Extracts the raw value for [key] from a yEnc header/trailer [line].
  ///
  /// Keywords are space-separated `key=value` pairs. The value runs
  /// until the next space-then-keyword or end of line.
  static String? _extractValue(String line, String key) {
    final tag = ' $key=';
    final idx = line.indexOf(tag);
    if (idx == -1) return null;
    final valueStart = idx + tag.length;
    // Value extends to the next ` keyword=` or end of string.
    final nextSpace = line.indexOf(' ', valueStart);
    if (nextSpace == -1) return line.substring(valueStart);
    return line.substring(valueStart, nextSpace);
  }

  /// Converts an ASCII string to bytes (for marker scanning).
  static Uint8List _asciiBytes(String s) =>
      Uint8List.fromList(s.codeUnits);
}
