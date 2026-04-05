/// Pure Dart RAR archive extractor with streaming support.
///
/// Parses RAR4 and RAR5 archive formats, optimized for streaming
/// extraction of Store-method (uncompressed) archives commonly
/// found in Usenet binary posts. Compressed entries are detected
/// and passed through without decompression.
///
/// Usage:
///
/// ```dart
/// final extractor = RarExtractor();
/// await for (final event in extractor.extract(byteStream)) {
///   switch (event) {
///     case RarFileStart(:final filename):
///       print('Extracting: $filename');
///     case RarFileData(:final data):
///       sink.add(data);
///     case RarFileEnd(:final checksumValid):
///       print('Valid: $checksumValid');
///     case RarProgress(:final bytesProcessed):
///       print('$bytesProcessed bytes');
///     case RarError(:final message):
///       print('Error: $message');
///     case RarPasswordRequired():
///       print('Password needed');
///   }
/// }
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// RarVersion
// ---------------------------------------------------------------------------

/// RAR archive format version.
enum RarVersion {
  /// RAR 4.x format (legacy, header type 0x72–0x7B).
  rar4,

  /// RAR 5.x format (modern, vint-based headers).
  rar5,
}

// ---------------------------------------------------------------------------
// RarFileInfo
// ---------------------------------------------------------------------------

/// Metadata for a single file entry within a RAR archive.
@immutable
class RarFileInfo {
  /// Creates a [RarFileInfo].
  const RarFileInfo({
    required this.filename,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.compressionMethod,
    this.modifiedAt,
    this.crc32,
    this.isDirectory = false,
  });

  /// Original filename (may include path separators).
  final String filename;

  /// Compressed size in bytes.
  final int compressedSize;

  /// Uncompressed size in bytes.
  final int uncompressedSize;

  /// Human-readable compression method name.
  ///
  /// One of: `"Store"`, `"Fastest"`, `"Fast"`, `"Normal"`, `"Good"`,
  /// `"Best"`, or `"Unknown(N)"` for unrecognised values.
  final String compressionMethod;

  /// Last modification timestamp, if available.
  final DateTime? modifiedAt;

  /// CRC32 checksum of the uncompressed data, if available.
  final int? crc32;

  /// Whether this entry represents a directory.
  final bool isDirectory;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RarFileInfo &&
          filename == other.filename &&
          compressedSize == other.compressedSize &&
          uncompressedSize == other.uncompressedSize;

  @override
  int get hashCode => Object.hash(filename, compressedSize, uncompressedSize);

  @override
  String toString() =>
      'RarFileInfo($filename, $compressedSize/$uncompressedSize B, '
      '$compressionMethod)';
}

// ---------------------------------------------------------------------------
// RarArchiveInfo
// ---------------------------------------------------------------------------

/// High-level metadata about a RAR archive, obtained from header inspection.
@immutable
class RarArchiveInfo {
  /// Creates a [RarArchiveInfo].
  const RarArchiveInfo({
    required this.version,
    required this.isMultiVolume,
    required this.isFirstVolume,
    required this.isSolid,
    required this.isEncrypted,
    this.files = const [],
  });

  /// Detected RAR format version.
  final RarVersion version;

  /// Whether the archive is part of a multi-volume set.
  final bool isMultiVolume;

  /// Whether this is the first volume in a multi-volume set.
  final bool isFirstVolume;

  /// Whether the archive uses solid compression.
  final bool isSolid;

  /// Whether the archive headers or data are encrypted.
  final bool isEncrypted;

  /// File entries discovered during header inspection.
  final List<RarFileInfo> files;

  @override
  String toString() =>
      'RarArchiveInfo($version, ${files.length} files, '
      'multi=$isMultiVolume, solid=$isSolid, encrypted=$isEncrypted)';
}

// ---------------------------------------------------------------------------
// RarExtractEvent
// ---------------------------------------------------------------------------

/// Events emitted during streaming RAR extraction.
///
/// Use exhaustive pattern matching to handle all event types:
///
/// ```dart
/// switch (event) {
///   case RarFileStart():        // new file started
///   case RarFileData():         // chunk of extracted data
///   case RarFileEnd():          // file complete
///   case RarProgress():         // progress update
///   case RarError():            // extraction error
///   case RarPasswordRequired(): // password needed
/// }
/// ```
sealed class RarExtractEvent {
  const RarExtractEvent();
}

/// Emitted when extraction of a new file begins.
final class RarFileStart extends RarExtractEvent {
  /// Creates a [RarFileStart] event.
  const RarFileStart({
    required this.filename,
    this.uncompressedSize,
    this.compressionMethod,
  });

  /// Name of the file being extracted.
  final String filename;

  /// Expected uncompressed size in bytes, if known.
  final int? uncompressedSize;

  /// Compression method used (e.g. `"Store"`, `"Normal"`).
  final String? compressionMethod;

  @override
  String toString() =>
      'RarFileStart($filename, ${uncompressedSize ?? '?'} B, '
      '${compressionMethod ?? 'unknown'})';
}

/// Emitted with a chunk of extracted file data.
///
/// For Store-method files (no compression), [data] contains the raw
/// uncompressed bytes. For compressed files, [data] contains the raw
/// compressed bytes — the consumer must decompress externally.
final class RarFileData extends RarExtractEvent {
  /// Creates a [RarFileData] event.
  const RarFileData(this.data);

  /// Chunk of file data bytes.
  final Uint8List data;

  @override
  String toString() => 'RarFileData(${data.length} B)';
}

/// Emitted when extraction of a file is complete.
final class RarFileEnd extends RarExtractEvent {
  /// Creates a [RarFileEnd] event.
  const RarFileEnd({
    required this.filename,
    required this.checksumValid,
  });

  /// Name of the completed file.
  final String filename;

  /// Whether the CRC32 checksum matched.
  ///
  /// `true` when the CRC matches or when no CRC was available to compare.
  /// `false` when the CRC was present and did not match, indicating
  /// possible corruption. Always `false` for compressed data passed
  /// through without decompression.
  final bool checksumValid;

  @override
  String toString() =>
      'RarFileEnd($filename, checksumValid=$checksumValid)';
}

/// Periodic progress update during extraction.
final class RarProgress extends RarExtractEvent {
  /// Creates a [RarProgress] event.
  const RarProgress({
    required this.bytesProcessed,
    this.totalBytes,
    this.currentFile,
  });

  /// Number of input bytes consumed so far.
  final int bytesProcessed;

  /// Total expected input size in bytes, if known.
  final int? totalBytes;

  /// Name of the file currently being extracted, if any.
  final String? currentFile;

  @override
  String toString() =>
      'RarProgress($bytesProcessed/${totalBytes ?? '?'} B, $currentFile)';
}

/// Emitted when a recoverable or fatal error is encountered.
final class RarError extends RarExtractEvent {
  /// Creates a [RarError] event.
  const RarError({
    required this.message,
    required this.recoverable,
  });

  /// Human-readable error description.
  final String message;

  /// Whether extraction can continue past this error.
  final bool recoverable;

  @override
  String toString() => 'RarError($message, recoverable=$recoverable)';
}

/// Emitted when the archive is password-protected.
final class RarPasswordRequired extends RarExtractEvent {
  /// Creates a [RarPasswordRequired] event.
  const RarPasswordRequired();

  @override
  String toString() => 'RarPasswordRequired()';
}

// ---------------------------------------------------------------------------
// CRC32 (private)
// ---------------------------------------------------------------------------

/// CRC32 (ISO 3309) calculator for checksum validation.
class _Crc32 {
  _Crc32._();

  static const int _polynomial = 0xEDB88320;

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

  /// Computes CRC32 over [data] from [start] to [end] (exclusive).
  ///
  /// Optionally continues from a previous [crc] for incremental use.
  static int compute(List<int> data, int start, int end, [int crc = 0]) {
    var c = crc ^ 0xFFFFFFFF;
    for (var i = start; i < end; i++) {
      c = _table[(c ^ data[i]) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

// ---------------------------------------------------------------------------
// Constants (private)
// ---------------------------------------------------------------------------

/// RAR5 magic signature: `Rar!\x1a\x07\x01\x00` (8 bytes).
const _rar5Magic = <int>[0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00];

/// RAR4 magic signature: `Rar!\x1a\x07\x00` (7 bytes).
const _rar4Magic = <int>[0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00];

// RAR5 header types.
const _rar5MainArchive = 1;
const _rar5File = 2;
const _rar5Service = 3;
const _rar5Encryption = 4;
const _rar5EndOfArchive = 5;

// RAR5 common header flags.
const _rar5FlagExtraArea = 0x0001;
const _rar5FlagDataArea = 0x0002;
const _rar5FlagContinuedPrev = 0x0008;
const _rar5FlagContinuedNext = 0x0010;

// RAR5 main archive flags.
const _rar5ArchiveVolume = 0x0001;
const _rar5ArchiveVolumeNumber = 0x0002;
const _rar5ArchiveSolid = 0x0004;

// RAR5 file header flags.
const _rar5FileDirectory = 0x0001;
const _rar5FileTimePresent = 0x0002;
const _rar5FileCrcPresent = 0x0004;

// RAR4 header types.
const _rar4Main = 0x73;
const _rar4File = 0x74;
const _rar4EndOfArchive = 0x7B;

// RAR4 main archive flags.
const _rar4ArchiveVolume = 0x0001;
const _rar4ArchiveSolid = 0x0008;
const _rar4ArchiveNewNaming = 0x0010;
const _rar4ArchiveEncryptedHeaders = 0x0080;
const _rar4ArchiveFirstVolume = 0x0100;

// RAR4 file header flags.
const _rar4FileContinuedPrev = 0x0001;
const _rar4FileContinuedNext = 0x0002;
const _rar4FileEncrypted = 0x0004;
const _rar4FileHighSize = 0x0100;
const _rar4FileUnicode = 0x0200;
const _rar4FileLargeBlock = 0x8000;

/// RAR4 method byte → human-readable name.
const _rar4MethodNames = <int, String>{
  0x30: 'Store',
  0x31: 'Fastest',
  0x32: 'Fast',
  0x33: 'Normal',
  0x34: 'Good',
  0x35: 'Best',
};

/// RAR5 method index → human-readable name.
const _rar5MethodNames = <int, String>{
  0: 'Store',
  1: 'Fastest',
  2: 'Fast',
  3: 'Normal',
  4: 'Good',
  5: 'Best',
};

/// Progress events are emitted at most once per this interval.
const _progressInterval = 256 * 1024; // 256 KiB

// ---------------------------------------------------------------------------
// Parser state machine
// ---------------------------------------------------------------------------

enum _State {
  awaitingMagic,
  parsingHeaders,
  readingFileData,
  skippingData,
  awaitingNextVolume,
  complete,
  error,
}

// ---------------------------------------------------------------------------
// _RarParser — stateful streaming parser
// ---------------------------------------------------------------------------

/// Internal parser that consumes raw bytes and produces [RarExtractEvent]s.
///
/// Maintains an accumulation buffer for partial header data while
/// optimising the Store-method hot path to avoid unnecessary copies.
class _RarParser {
  _RarParser({this.inspectOnly = false});

  /// When `true`, headers are parsed for metadata but file data areas
  /// are skipped rather than emitted as [RarFileData] events.
  final bool inspectOnly;

  // -- Buffer ---------------------------------------------------------------

  Uint8List _buf = Uint8List(0);
  int _pos = 0;

  int get _available => _buf.length - _pos;

  /// Appends [data] to the internal buffer, compacting consumed bytes.
  void _feed(List<int> data) {
    if (_pos >= _buf.length) {
      _buf = data is Uint8List ? data : Uint8List.fromList(data);
      _pos = 0;
    } else {
      final remaining = _buf.length - _pos;
      final newBuf = Uint8List(remaining + data.length);
      newBuf.setRange(0, remaining, _buf, _pos);
      newBuf.setRange(remaining, remaining + data.length, data);
      _buf = newBuf;
      _pos = 0;
    }
  }

  // -- Binary readers -------------------------------------------------------

  int _readUint8() => _buf[_pos++];

  int _readUint16LE() {
    final v = _buf[_pos] | (_buf[_pos + 1] << 8);
    _pos += 2;
    return v;
  }

  int _readUint32LE() {
    final v = _buf[_pos] |
        (_buf[_pos + 1] << 8) |
        (_buf[_pos + 2] << 16) |
        (_buf[_pos + 3] << 24);
    _pos += 4;
    return v & 0xFFFFFFFF;
  }

  /// Reads a RAR5 variable-length integer, or `null` if insufficient data.
  int? _tryReadVint() {
    var value = 0;
    var shift = 0;
    var i = _pos;
    while (i < _buf.length) {
      final b = _buf[i];
      value |= (b & 0x7F) << shift;
      shift += 7;
      i++;
      if (b & 0x80 == 0) {
        _pos = i;
        return value;
      }
      if (shift >= 63) {
        _pos = i;
        return value;
      }
    }
    return null;
  }

  /// Reads a RAR5 vint without bounds checking (caller guarantees data).
  int _readVint() {
    var value = 0;
    var shift = 0;
    while (true) {
      final b = _buf[_pos++];
      value |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) return value;
      shift += 7;
      if (shift >= 63) return value;
    }
  }

  // -- Parser state ---------------------------------------------------------

  _State _state = _State.awaitingMagic;
  RarVersion? _version;

  // Current file tracking.
  String? _currentFile;
  int _fileDataRemaining = 0;
  bool _isStoreMethod = true;
  int _fileCrc = 0;
  int? _expectedCrc;
  bool _fileContinuedInNext = false;

  // Data to skip (non-file data areas).
  int _skipDataRemaining = 0;

  // Archive-level metadata.
  bool _isMultiVolume = false;
  bool _isFirstVolume = true;
  bool _isSolid = false;
  bool _isEncrypted = false;
  final _fileInfos = <RarFileInfo>[];

  // Progress tracking.
  int _bytesProcessed = 0;
  int _lastProgressAt = 0;

  // -- Public interface -----------------------------------------------------

  /// Processes a chunk of input bytes and returns resulting events.
  List<RarExtractEvent> processChunk(List<int> chunk) {
    final events = <RarExtractEvent>[];
    _bytesProcessed += chunk.length;

    // Hot path: reading file data with no buffered header bytes.
    if (_state == _State.readingFileData && _pos >= _buf.length) {
      _processFileDataDirect(events, chunk);
      if (_state == _State.readingFileData) {
        _emitProgressIfNeeded(events);
        return events;
      }
      // File ended mid-chunk; leftover bytes are now in _buf.
    } else {
      _feed(chunk);
    }

    _drain(events);
    _emitProgressIfNeeded(events);
    return events;
  }

  /// Signals end of the current input stream and returns final events.
  List<RarExtractEvent> finalize() {
    final events = <RarExtractEvent>[];

    if (_state == _State.readingFileData && _currentFile != null) {
      if (_fileContinuedInNext) {
        _state = _State.awaitingNextVolume;
      } else {
        events.add(
          RarError(
            message: 'Unexpected end of stream while reading '
                '"$_currentFile" ($_fileDataRemaining bytes remaining)',
            recoverable: false,
          ),
        );
        events.add(
          RarFileEnd(filename: _currentFile!, checksumValid: false),
        );
        _currentFile = null;
        _state = _State.complete;
      }
    }

    return events;
  }

  /// Resets buffer and parse state for the next volume in a multi-volume
  /// archive while preserving file-continuation tracking.
  void prepareNextVolume() {
    _state = _State.awaitingMagic;
    _buf = Uint8List(0);
    _pos = 0;
  }

  /// Returns archive metadata collected so far.
  RarArchiveInfo get archiveInfo => RarArchiveInfo(
        version: _version ?? RarVersion.rar5,
        isMultiVolume: _isMultiVolume,
        isFirstVolume: _isFirstVolume,
        isSolid: _isSolid,
        isEncrypted: _isEncrypted,
        files: List<RarFileInfo>.unmodifiable(_fileInfos),
      );

  // -- Processing loop ------------------------------------------------------

  /// Drains as much data from the buffer as possible, emitting events.
  void _drain(List<RarExtractEvent> events) {
    var iterations = 0;
    while (iterations++ < 10000) {
      switch (_state) {
        case _State.awaitingMagic:
          if (!_tryParseMagic(events)) return;
        case _State.parsingHeaders:
          if (!_tryParseHeader(events)) return;
        case _State.readingFileData:
          if (!_tryReadFileData(events)) return;
        case _State.skippingData:
          if (!_trySkipData()) return;
        case _State.awaitingNextVolume:
        case _State.complete:
        case _State.error:
          return;
      }
    }
  }

  // -- Magic detection ------------------------------------------------------

  bool _tryParseMagic(List<RarExtractEvent> events) {
    if (_available < 8) return false;

    if (_matchesBuf(_pos, _rar5Magic)) {
      _version = RarVersion.rar5;
      _pos += _rar5Magic.length;
      _state = _State.parsingHeaders;
      return true;
    }

    if (_matchesBuf(_pos, _rar4Magic)) {
      _version = RarVersion.rar4;
      _pos += _rar4Magic.length;
      _state = _State.parsingHeaders;
      return true;
    }

    events.add(
      const RarError(
        message: 'Not a valid RAR archive (magic signature not found)',
        recoverable: false,
      ),
    );
    _state = _State.error;
    return false;
  }

  bool _matchesBuf(int offset, List<int> sig) {
    if (offset + sig.length > _buf.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (_buf[offset + i] != sig[i]) return false;
    }
    return true;
  }

  // -- Header dispatch ------------------------------------------------------

  bool _tryParseHeader(List<RarExtractEvent> events) {
    return _version == RarVersion.rar5
        ? _tryParseRar5Header(events)
        : _tryParseRar4Header(events);
  }

  // -- RAR5 header parsing --------------------------------------------------

  bool _tryParseRar5Header(List<RarExtractEvent> events) {
    // Minimum RAR5 header: CRC(4) + size(1) + type(1) + flags(1) = 7.
    if (_available < 7) return false;

    final savedPos = _pos;

    // Header CRC32 (4 bytes, LE).
    final headerCrc = _readUint32LE();

    // Header size vint — bytes counted from *after* this vint.
    final sizeVintStart = _pos;
    final headerSize = _tryReadVint();
    if (headerSize == null) {
      _pos = savedPos;
      return false;
    }

    // headerSize measures from here to end of header (type + flags + fields).
    final headerBodyStart = _pos;
    if (headerBodyStart + headerSize > _buf.length) {
      _pos = savedPos;
      return false;
    }

    // Verify CRC (covers size vint + body).
    final actualCrc = _Crc32.compute(
      _buf,
      sizeVintStart,
      headerBodyStart + headerSize,
    );
    if (actualCrc != headerCrc) {
      events.add(
        const RarError(
          message: 'RAR5 header CRC mismatch',
          recoverable: true,
        ),
      );
    }

    // Parse header body fields — safe because we verified size above.
    final headerType = _readVint();
    final headerFlags = _readVint();

    if (headerFlags & _rar5FlagExtraArea != 0) {
      _readVint(); // extra area size (skipped to end anyway)
    }

    var dataAreaSize = 0;
    if (headerFlags & _rar5FlagDataArea != 0) {
      dataAreaSize = _readVint();
    }

    final continuedFromPrev = headerFlags & _rar5FlagContinuedPrev != 0;
    final continuedInNext = headerFlags & _rar5FlagContinuedNext != 0;

    // Type-specific parsing.
    switch (headerType) {
      case _rar5MainArchive:
        _parseRar5MainHeader();
        if (_isEncrypted) events.add(const RarPasswordRequired());
      case _rar5File:
        _parseRar5FileHeader(
          events,
          dataAreaSize,
          continuedFromPrev,
          continuedInNext,
        );
      case _rar5Service:
        break; // skip service headers
      case _rar5Encryption:
        _isEncrypted = true;
        events.add(const RarPasswordRequired());
      case _rar5EndOfArchive:
        _state = _State.complete;
    }

    // Advance past the full header body.
    _pos = headerBodyStart + headerSize;

    // Handle data area that follows the header.
    if (dataAreaSize > 0 && _state == _State.readingFileData) {
      // File data — _fileDataRemaining was set by _parseRar5FileHeader.
      // Nothing more to do; _drain will enter readingFileData.
    } else if (dataAreaSize > 0) {
      // Non-file data area (service blocks, encrypted payloads).
      _skipDataRemaining = dataAreaSize;
      _state = _State.skippingData;
    }

    return true;
  }

  void _parseRar5MainHeader() {
    final archiveFlags = _readVint();
    _isMultiVolume = archiveFlags & _rar5ArchiveVolume != 0;
    _isSolid = archiveFlags & _rar5ArchiveSolid != 0;
    if (archiveFlags & _rar5ArchiveVolumeNumber != 0) {
      final volumeNumber = _readVint();
      _isFirstVolume = volumeNumber == 0;
    }
  }

  void _parseRar5FileHeader(
    List<RarExtractEvent> events,
    int dataAreaSize,
    bool continuedFromPrev,
    bool continuedInNext,
  ) {
    final fileFlags = _readVint();
    final unpackedSize = _readVint();
    _readVint(); // attributes

    DateTime? modifiedAt;
    if (fileFlags & _rar5FileTimePresent != 0) {
      final mtime = _readUint32LE();
      modifiedAt =
          DateTime.fromMillisecondsSinceEpoch(mtime * 1000, isUtc: true);
    }

    int? dataCrc;
    if (fileFlags & _rar5FileCrcPresent != 0) {
      dataCrc = _readUint32LE();
    }

    final compressionInfo = _readVint();
    // Bits 7-9: compression method (0 = Store, 1-5 = compressed).
    final method = (compressionInfo >> 7) & 0x07;
    final methodName = _rar5MethodNames[method] ?? 'Unknown($method)';
    final isStore = method == 0;

    _readVint(); // host OS

    final nameLength = _readVint();
    final nameStart = _pos;
    final nameEnd = nameStart + nameLength;

    String filename;
    try {
      filename = utf8.decode(
        Uint8List.sublistView(_buf, nameStart, nameEnd),
      );
    } catch (_) {
      filename = String.fromCharCodes(_buf, nameStart, nameEnd);
    }
    _pos = nameEnd;

    final isDirectory = fileFlags & _rar5FileDirectory != 0;

    _fileInfos.add(
      RarFileInfo(
        filename: filename,
        compressedSize: dataAreaSize,
        uncompressedSize: unpackedSize,
        compressionMethod: methodName,
        modifiedAt: modifiedAt,
        crc32: dataCrc,
        isDirectory: isDirectory,
      ),
    );

    if (inspectOnly) return;

    if (!continuedFromPrev) {
      _currentFile = filename;
      _fileCrc = 0;
      _expectedCrc = dataCrc;
      _isStoreMethod = isStore;
      _fileContinuedInNext = continuedInNext;

      events.add(
        RarFileStart(
          filename: filename,
          uncompressedSize: isDirectory ? null : unpackedSize,
          compressionMethod: methodName,
        ),
      );
    } else {
      _fileContinuedInNext = continuedInNext;
    }

    if (isDirectory || dataAreaSize == 0) {
      if (!continuedFromPrev && !continuedInNext) {
        events.add(RarFileEnd(filename: filename, checksumValid: true));
        _currentFile = null;
      }
      return;
    }

    _fileDataRemaining = dataAreaSize;
    _state = _State.readingFileData;
  }

  // -- RAR4 header parsing --------------------------------------------------

  bool _tryParseRar4Header(List<RarExtractEvent> events) {
    // Minimum RAR4 header: CRC(2) + TYPE(1) + FLAGS(2) + SIZE(2) = 7.
    if (_available < 7) return false;

    final savedPos = _pos;

    final headCrc = _readUint16LE();
    final headType = _readUint8();
    final headFlags = _readUint16LE();
    final headSize = _readUint16LE();

    // Check if the full header (as declared by HEAD_SIZE) is available.
    if (savedPos + headSize > _buf.length) {
      _pos = savedPos;
      return false;
    }

    // Verify CRC (covers HEAD_TYPE through end of header).
    final actualCrc =
        _Crc32.compute(_buf, savedPos + 2, savedPos + headSize) & 0xFFFF;
    if (actualCrc != headCrc && headType != 0x72) {
      events.add(
        const RarError(
          message: 'RAR4 header CRC mismatch',
          recoverable: true,
        ),
      );
    }

    var dataAreaSize = 0;

    switch (headType) {
      case _rar4Main:
        _parseRar4MainHeader(headFlags);
        if (_isEncrypted) events.add(const RarPasswordRequired());
      case _rar4File:
        dataAreaSize = _parseRar4FileHeader(events, headFlags);
      case _rar4EndOfArchive:
        _state = _State.complete;
      default:
        // Unknown header — if LONG_BLOCK flag is set there may be data.
        if (headFlags & _rar4FileLargeBlock != 0 && _available >= 4) {
          dataAreaSize = _readUint32LE();
        }
    }

    // Advance past the header.
    _pos = savedPos + headSize;

    // Handle data area following the header.
    if (dataAreaSize > 0 && _state == _State.readingFileData) {
      _fileDataRemaining = dataAreaSize;
    } else if (dataAreaSize > 0) {
      _skipDataRemaining = dataAreaSize;
      _state = _State.skippingData;
    }

    return true;
  }

  void _parseRar4MainHeader(int headFlags) {
    _isMultiVolume = headFlags & _rar4ArchiveVolume != 0;
    _isSolid = headFlags & _rar4ArchiveSolid != 0;
    _isEncrypted = headFlags & _rar4ArchiveEncryptedHeaders != 0;

    if (headFlags & _rar4ArchiveVolume != 0 &&
        headFlags & _rar4ArchiveNewNaming != 0) {
      _isFirstVolume = headFlags & _rar4ArchiveFirstVolume != 0;
    }
  }

  int _parseRar4FileHeader(List<RarExtractEvent> events, int headFlags) {
    final packSizeLow = _readUint32LE();
    final unpSizeLow = _readUint32LE();
    _readUint8(); // host OS
    final fileCrc = _readUint32LE();
    final ftime = _readUint32LE();
    _readUint8(); // min unpack version
    final method = _readUint8();
    final nameSize = _readUint16LE();
    final attr = _readUint32LE();

    var packSize = packSizeLow;
    var unpSize = unpSizeLow;
    if (headFlags & _rar4FileHighSize != 0) {
      final highPack = _readUint32LE();
      final highUnp = _readUint32LE();
      packSize = packSizeLow | (highPack << 32);
      unpSize = unpSizeLow | (highUnp << 32);
    }

    // Read filename.
    final nameBytes = Uint8List.sublistView(_buf, _pos, _pos + nameSize);
    _pos += nameSize;

    String filename;
    if (headFlags & _rar4FileUnicode != 0) {
      // Unicode name: null-terminated ASCII prefix, then encoded UTF-16.
      final nullPos = nameBytes.indexOf(0);
      if (nullPos >= 0) {
        filename = String.fromCharCodes(nameBytes, 0, nullPos);
      } else {
        filename = String.fromCharCodes(nameBytes);
      }
    } else {
      filename = String.fromCharCodes(nameBytes);
    }

    final methodName =
        _rar4MethodNames[method] ?? 'Unknown(0x${method.toRadixString(16)})';
    final isStore = method == 0x30;
    final isDirectory = attr & 0x10 != 0;
    final isFileEncrypted = headFlags & _rar4FileEncrypted != 0;
    final continuedFromPrev = headFlags & _rar4FileContinuedPrev != 0;
    final continuedInNext = headFlags & _rar4FileContinuedNext != 0;
    final modifiedAt = _dosDateTime(ftime);

    _fileInfos.add(
      RarFileInfo(
        filename: filename,
        compressedSize: packSize,
        uncompressedSize: unpSize,
        compressionMethod: methodName,
        modifiedAt: modifiedAt,
        crc32: fileCrc,
        isDirectory: isDirectory,
      ),
    );

    if (inspectOnly) return packSize;

    if (isFileEncrypted) {
      events.add(const RarPasswordRequired());
      return packSize; // caller will skip encrypted data
    }

    if (!continuedFromPrev) {
      _currentFile = filename;
      _fileCrc = 0;
      _expectedCrc = fileCrc;
      _isStoreMethod = isStore;
      _fileContinuedInNext = continuedInNext;

      events.add(
        RarFileStart(
          filename: filename,
          uncompressedSize: isDirectory ? null : unpSize,
          compressionMethod: methodName,
        ),
      );
    } else {
      _fileContinuedInNext = continuedInNext;
    }

    if (isDirectory || packSize == 0) {
      if (!continuedFromPrev && !continuedInNext) {
        events.add(RarFileEnd(filename: filename, checksumValid: true));
        _currentFile = null;
      }
      return 0;
    }

    _state = _State.readingFileData;
    return packSize;
  }

  // -- File data reading ----------------------------------------------------

  /// Reads file data from the internal buffer.
  bool _tryReadFileData(List<RarExtractEvent> events) {
    if (_fileDataRemaining == 0) {
      _emitFileEnd(events);
      return true;
    }

    if (_available == 0) return false;

    final toRead =
        _available < _fileDataRemaining ? _available : _fileDataRemaining;
    final data = Uint8List.sublistView(_buf, _pos, _pos + toRead);
    _pos += toRead;
    _fileDataRemaining -= toRead;

    events.add(RarFileData(data));

    if (_isStoreMethod) {
      _fileCrc = _Crc32.compute(data, 0, data.length, _fileCrc);
    }

    if (_fileDataRemaining == 0) {
      _emitFileEnd(events);
    }

    return true;
  }

  /// Hot-path: processes file data directly from an incoming chunk without
  /// copying into the accumulation buffer.
  void _processFileDataDirect(List<RarExtractEvent> events, List<int> chunk) {
    final toRead =
        chunk.length < _fileDataRemaining ? chunk.length : _fileDataRemaining;

    if (toRead > 0) {
      final Uint8List data;
      if (chunk is Uint8List) {
        data = toRead == chunk.length
            ? chunk
            : Uint8List.sublistView(chunk, 0, toRead);
      } else {
        data = Uint8List.fromList(
          toRead == chunk.length ? chunk : chunk.sublist(0, toRead),
        );
      }

      events.add(RarFileData(data));

      if (_isStoreMethod) {
        _fileCrc = _Crc32.compute(data, 0, data.length, _fileCrc);
      }

      _fileDataRemaining -= toRead;
    }

    if (_fileDataRemaining == 0) {
      _emitFileEnd(events);
    }

    // Buffer any remaining bytes for subsequent header parsing.
    if (toRead < chunk.length) {
      if (chunk is Uint8List) {
        _feed(Uint8List.sublistView(chunk, toRead));
      } else {
        _feed(chunk.sublist(toRead));
      }
    }
  }

  // -- Data skipping --------------------------------------------------------

  bool _trySkipData() {
    if (_available == 0 && _skipDataRemaining > 0) return false;

    final skip =
        _available < _skipDataRemaining ? _available : _skipDataRemaining;
    _pos += skip;
    _skipDataRemaining -= skip;

    if (_skipDataRemaining == 0) {
      _state = _State.parsingHeaders;
      return true;
    }

    return false;
  }

  // -- File end / CRC validation --------------------------------------------

  void _emitFileEnd(List<RarExtractEvent> events) {
    if (_currentFile == null) {
      _state = _State.parsingHeaders;
      return;
    }

    if (_fileContinuedInNext) {
      // File continues in next volume — do not emit FileEnd yet.
      _state = _State.awaitingNextVolume;
      return;
    }

    bool checksumValid;
    if (!_isStoreMethod) {
      // CRC is over uncompressed data; we passed through raw compressed
      // bytes, so comparison is meaningless.
      checksumValid = false;
    } else if (_expectedCrc != null) {
      checksumValid = _fileCrc == _expectedCrc;
    } else {
      checksumValid = true; // no CRC to compare
    }

    events.add(RarFileEnd(filename: _currentFile!, checksumValid: checksumValid));
    _currentFile = null;
    _state = _State.parsingHeaders;
  }

  // -- Progress -------------------------------------------------------------

  void _emitProgressIfNeeded(List<RarExtractEvent> events) {
    if (_bytesProcessed - _lastProgressAt >= _progressInterval) {
      _lastProgressAt = _bytesProcessed;
      events.add(
        RarProgress(
          bytesProcessed: _bytesProcessed,
          currentFile: _currentFile,
        ),
      );
    }
  }

  // -- Helpers --------------------------------------------------------------

  /// Parses an MS-DOS date/time packed `uint32` into a [DateTime].
  static DateTime? _dosDateTime(int ftime) {
    if (ftime == 0) return null;
    final second = (ftime & 0x1F) * 2;
    final minute = (ftime >> 5) & 0x3F;
    final hour = (ftime >> 11) & 0x1F;
    final day = (ftime >> 16) & 0x1F;
    final month = (ftime >> 21) & 0x0F;
    final year = ((ftime >> 25) & 0x7F) + 1980;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day, hour, minute, second);
  }
}

// ---------------------------------------------------------------------------
// RarExtractor — public API
// ---------------------------------------------------------------------------

/// Pure Dart RAR archive extractor with streaming support.
///
/// Optimised for the Usenet use case where most archives use the Store
/// method (no compression). Store-method files are passed through with
/// near-zero overhead — just header parsing and CRC validation.
///
/// Compressed entries (method ≠ Store) are detected and their raw bytes
/// are emitted as [RarFileData] events. The [RarFileStart.compressionMethod]
/// field indicates which method was used so consumers can decide whether
/// to apply external decompression.
///
/// ```dart
/// final extractor = RarExtractor();
///
/// // Single archive
/// await for (final event in extractor.extract(byteStream)) { ... }
///
/// // Multi-volume
/// await for (final event in extractor.extractMultiVolume(volumes)) { ... }
///
/// // Quick inspection
/// final info = await extractor.inspect(headerBytes);
/// print(info.files.map((f) => f.filename));
/// ```
class RarExtractor {
  /// Creates a [RarExtractor].
  const RarExtractor();

  /// Returns `true` if [bytes] begins with a valid RAR magic signature.
  ///
  /// Checks for both RAR5 (8-byte) and RAR4 (7-byte) signatures.
  static bool isRarArchive(List<int> bytes) {
    if (bytes.length >= _rar5Magic.length &&
        _matchesBytes(bytes, 0, _rar5Magic)) {
      return true;
    }
    if (bytes.length >= _rar4Magic.length &&
        _matchesBytes(bytes, 0, _rar4Magic)) {
      return true;
    }
    return false;
  }

  /// Streams extraction events from an archive byte stream.
  ///
  /// Reads the archive from [archiveStream], parsing headers and emitting
  /// [RarExtractEvent]s as data becomes available. For Store-method files,
  /// data chunks are emitted with minimal buffering.
  ///
  /// The returned stream can be cancelled via its [StreamSubscription].
  Stream<RarExtractEvent> extract(Stream<List<int>> archiveStream) async* {
    final parser = _RarParser();

    await for (final chunk in archiveStream) {
      final events = parser.processChunk(chunk);
      for (final event in events) {
        yield event;
      }
    }

    final finalEvents = parser.finalize();
    for (final event in finalEvents) {
      yield event;
    }
  }

  /// Streams extraction events from a multi-volume RAR archive.
  ///
  /// Each entry in [volumes] is a byte stream for one volume, ordered
  /// sequentially (`.part01.rar`, `.part02.rar`, … or `.rar`, `.r00`,
  /// `.r01`, …). Files spanning volume boundaries are handled
  /// transparently — data events flow continuously across volumes.
  Stream<RarExtractEvent> extractMultiVolume(
    List<Stream<List<int>>> volumes,
  ) async* {
    if (volumes.isEmpty) return;

    final parser = _RarParser();

    for (var i = 0; i < volumes.length; i++) {
      if (i > 0) {
        parser.prepareNextVolume();
      }

      await for (final chunk in volumes[i]) {
        final events = parser.processChunk(chunk);
        for (final event in events) {
          yield event;
        }
      }

      final volumeEndEvents = parser.finalize();
      for (final event in volumeEndEvents) {
        yield event;
      }
    }
  }

  /// Inspects the archive headers without performing full extraction.
  ///
  /// Parses as many headers as possible from [headerBytes] and returns
  /// an [RarArchiveInfo] containing format version, flags, and a list
  /// of discovered file entries. File data areas are skipped.
  ///
  /// Provide enough bytes to cover all headers (typically the first few
  /// hundred KiB of the archive). Headers interleaved with large data
  /// areas may not all be reachable.
  Future<RarArchiveInfo> inspect(List<int> headerBytes) async {
    final parser = _RarParser(inspectOnly: true);
    parser.processChunk(headerBytes);
    return parser.archiveInfo;
  }
}

// ---------------------------------------------------------------------------
// Top-level helper
// ---------------------------------------------------------------------------

/// Checks if [data] starting at [offset] matches [signature].
bool _matchesBytes(List<int> data, int offset, List<int> signature) {
  if (offset + signature.length > data.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (data[offset + i] != signature[i]) return false;
  }
  return true;
}
