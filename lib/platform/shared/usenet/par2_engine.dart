/// Pure Dart PAR2 (Parity Archive Volume Set v2.0) repair engine.
///
/// Parses PAR2 recovery files, verifies source file integrity using
/// MD5 and CRC32 checksums, and repairs missing or damaged data blocks
/// via Reed-Solomon error correction over GF(2^16).
///
/// PAR2 is the standard parity format for Usenet binary recovery,
/// enabling reconstruction of missing article segments from redundant
/// parity data distributed across multiple recovery volumes.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:meta/meta.dart';

import 'yenc_decoder.dart' show Crc32;

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// A single recovery data slice from a PAR2 volume file.
@immutable
class Par2RecoverySlice {
  /// Creates a recovery slice.
  const Par2RecoverySlice({
    required this.exponent,
    required this.data,
  });

  /// Recovery block exponent — determines the GF(2^16) coefficients
  /// used in the Reed-Solomon linear combination for this slice.
  final int exponent;

  /// Raw recovery block data (block-size bytes).
  final Uint8List data;

  @override
  String toString() =>
      'Par2RecoverySlice(exponent: $exponent, bytes: ${data.length})';
}

/// Describes a source file protected by this PAR2 recovery set.
@immutable
class Par2FileDescription {
  /// Creates a file description.
  const Par2FileDescription({
    required this.fileId,
    required this.filename,
    required this.fileSize,
    required this.md5Hash,
    required this.md5Hash16k,
    required this.blockChecksums,
  });

  /// 16-byte unique file identifier within the recovery set.
  final Uint8List fileId;

  /// Original filename (as stored in the PAR2 file).
  final String filename;

  /// Original file size in bytes.
  final int fileSize;

  /// MD5 digest of the entire file.
  final Uint8List md5Hash;

  /// MD5 digest of the first 16 384 bytes of the file (or entire file
  /// if shorter than 16 KB).
  final Uint8List md5Hash16k;

  /// Per-block checksums. Each entry is a 20-byte blob containing the
  /// 16-byte MD5 hash followed by a 4-byte little-endian CRC32 value.
  final List<Uint8List> blockChecksums;

  @override
  String toString() => 'Par2FileDescription($filename, $fileSize bytes, '
      '${blockChecksums.length} blocks)';
}

/// Parsed metadata from one or more PAR2 files in the same recovery set.
@immutable
class Par2FileInfo {
  /// Creates a PAR2 file info.
  const Par2FileInfo({
    this.creator,
    required this.recoverySetId,
    required this.files,
    required this.blockSize,
    required this.totalBlocks,
    required this.recoveryBlockCount,
    required this.recoverySlices,
  });

  /// Application that created this PAR2 set (may be `null`).
  final String? creator;

  /// 16-byte identifier shared by all packets in this recovery set.
  final Uint8List recoverySetId;

  /// Source files described by this recovery set.
  final List<Par2FileDescription> files;

  /// Block (slice) size in bytes used for recovery calculations.
  final int blockSize;

  /// Total number of data blocks across all source files.
  final int totalBlocks;

  /// Number of recovery blocks available in parsed PAR2 data.
  final int recoveryBlockCount;

  /// Recovery slices parsed from PAR2 volume files.
  final List<Par2RecoverySlice> recoverySlices;

  @override
  String toString() => 'Par2FileInfo(files: ${files.length}, '
      'blockSize: $blockSize, totalBlocks: $totalBlocks, '
      'recovery: $recoveryBlockCount)';
}

/// Integrity status of a single source file after verification.
@immutable
class Par2FileStatus {
  /// Creates a file status.
  const Par2FileStatus({
    required this.filename,
    required this.present,
    required this.intact,
    required this.damagedBlockIndices,
    required this.missingBlockIndices,
  });

  /// Filename as recorded in the PAR2 set.
  final String filename;

  /// Whether the file was found in the provided data.
  final bool present;

  /// Whether every block checksum passed (`false` if [present] is `false`).
  final bool intact;

  /// Indices of blocks whose checksums did not match.
  final List<int> damagedBlockIndices;

  /// Indices of blocks that are absent (file truncated or missing).
  final List<int> missingBlockIndices;

  @override
  String toString() => 'Par2FileStatus($filename, present: $present, '
      'intact: $intact, damaged: ${damagedBlockIndices.length}, '
      'missing: ${missingBlockIndices.length})';
}

/// Result of verifying source files against PAR2 checksums.
@immutable
class Par2VerifyResult {
  /// Creates a verification result.
  const Par2VerifyResult({
    required this.allFilesPresent,
    required this.allFilesIntact,
    required this.fileStatuses,
    required this.missingBlockCount,
    required this.availableRecoveryBlocks,
  });

  /// Whether every source file was found in the provided data.
  final bool allFilesPresent;

  /// Whether every block checksum passed for all files.
  final bool allFilesIntact;

  /// Per-file verification status.
  final List<Par2FileStatus> fileStatuses;

  /// Total number of data blocks that are missing or damaged.
  final int missingBlockCount;

  /// Number of usable recovery blocks.
  final int availableRecoveryBlocks;

  /// Whether there are enough recovery blocks to repair all damage.
  bool get isRepairable => missingBlockCount <= availableRecoveryBlocks;

  @override
  String toString() => 'Par2VerifyResult(intact: $allFilesIntact, '
      'missing: $missingBlockCount, recovery: $availableRecoveryBlocks, '
      'repairable: $isRepairable)';
}

/// Outcome of a PAR2 repair operation.
sealed class Par2RepairResult {
  /// Base constructor.
  const Par2RepairResult();
}

/// Repair succeeded — contains the fully reconstructed file data.
@immutable
final class Par2RepairSuccess extends Par2RepairResult {
  /// Creates a successful repair result.
  const Par2RepairSuccess({required this.repairedFiles});

  /// Map of filename → repaired file bytes for every source file that
  /// required reconstruction.
  final Map<String, Uint8List> repairedFiles;

  @override
  String toString() => 'Par2RepairSuccess(${repairedFiles.length} files)';
}

/// Repair failed — not enough recovery data or internal error.
@immutable
final class Par2RepairFailure extends Par2RepairResult {
  /// Creates a failed repair result.
  const Par2RepairFailure({
    required this.reason,
    required this.missingBlocks,
    required this.availableRecovery,
  });

  /// Human-readable failure description.
  final String reason;

  /// Number of data blocks that need recovery.
  final int missingBlocks;

  /// Number of recovery blocks that were available.
  final int availableRecovery;

  @override
  String toString() => 'Par2RepairFailure($reason, '
      'need: $missingBlocks, have: $availableRecovery)';
}

// ---------------------------------------------------------------------------
// Galois Field GF(2^16)
// ---------------------------------------------------------------------------

/// Arithmetic over GF(2^16) with primitive polynomial x¹⁶+x¹²+x³+x+1.
///
/// All operations use pre-computed log/exp lookup tables (128 KB each)
/// that are lazily initialized on first access.
class _GaloisField {
  _GaloisField._();

  /// Primitive polynomial: x^16 + x^12 + x^3 + x + 1.
  static const int _primitive = 0x1100B;

  /// Number of elements in the field.
  static const int _fieldSize = 65536;

  /// Order of the multiplicative group (field size minus zero).
  static const int _order = _fieldSize - 1;

  /// Lazily built log and exp tables.
  static final (Uint16List, Uint16List) _tables = _buildTables();

  /// Log table: `_logTable[x]` = discrete log base α of `x`.
  static Uint16List get logTable => _tables.$1;

  /// Exp table: `_expTable[i]` = α^i.
  static Uint16List get expTable => _tables.$2;

  static (Uint16List, Uint16List) _buildTables() {
    final log = Uint16List(_fieldSize);
    // +1 entry for convenient wrap-around access.
    final exp = Uint16List(_fieldSize + 1);

    var val = 1;
    for (var i = 0; i < _order; i++) {
      exp[i] = val;
      log[val] = i;
      val <<= 1;
      if (val >= _fieldSize) val ^= _primitive;
    }
    exp[_order] = exp[0]; // wrap-around so index `_order` == index 0

    return (log, exp);
  }

  /// Addition in GF(2^16) is XOR.
  static int add(int a, int b) => a ^ b;

  /// Multiplication via log/exp tables. Returns 0 if either operand is 0.
  static int mul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return expTable[(logTable[a] + logTable[b]) % _order];
  }

  /// Division via log/exp tables. Throws if [b] is zero.
  static int div(int a, int b) {
    if (b == 0) throw ArgumentError('Division by zero in GF(2^16)');
    if (a == 0) return 0;
    final e = logTable[a] - logTable[b];
    return expTable[e < 0 ? e + _order : e];
  }

  /// Exponentiation: `base` raised to [exponent] in GF(2^16).
  static int pow(int base, int exponent) {
    if (base == 0) return 0;
    if (exponent == 0) return 1;
    var e = (logTable[base] * exponent) % _order;
    if (e < 0) e += _order;
    return expTable[e];
  }
}

// ---------------------------------------------------------------------------
// PAR2 packet constants
// ---------------------------------------------------------------------------

/// 8-byte packet magic: `PAR2\0PKT`.
const _packetMagic = <int>[
  0x50, 0x41, 0x52, 0x32, 0x00, 0x50, 0x4B, 0x54
];

/// Minimum packet size (the fixed header).
const _headerSize = 64;

/// Packet type signatures (16 bytes each).
final Uint8List _mainType =
    Uint8List.fromList('PAR 2.0\x00Main\x00\x00\x00\x00'.codeUnits);
final Uint8List _fileDescType =
    Uint8List.fromList('PAR 2.0\x00FileDesc'.codeUnits);
final Uint8List _ifscType =
    Uint8List.fromList('PAR 2.0\x00IFSC\x00\x00\x00\x00'.codeUnits);
final Uint8List _recvSlicType =
    Uint8List.fromList('PAR 2.0\x00RecvSlic'.codeUnits);
final Uint8List _creatorType =
    Uint8List.fromList('PAR 2.0\x00Creator\x00'.codeUnits);

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Returns `true` when [data] starting at [offset] matches [pattern].
bool _bytesMatch(List<int> data, int offset, List<int> pattern) {
  for (var i = 0; i < pattern.length; i++) {
    if (data[offset + i] != pattern[i]) return false;
  }
  return true;
}

/// Element-wise equality of two byte sequences.
bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Reads a little-endian uint64 from [view] at [offset].
///
/// Combines two 32-bit reads to avoid platform issues with `getUint64`.
int _readUint64LE(ByteData view, int offset) {
  final lo = view.getUint32(offset, Endian.little);
  final hi = view.getUint32(offset + 4, Endian.little);
  return (hi << 32) | lo;
}

/// Converts a 16-byte identifier to a hex string for use as a map key.
String _hexId(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Extracts block [blockIndex] from [fileData], zero-padding the last
/// block to [blockSize] bytes if the file is shorter.
Uint8List _extractBlock(List<int> fileData, int blockIndex, int blockSize) {
  final offset = blockIndex * blockSize;
  if (offset >= fileData.length) {
    return Uint8List(blockSize);
  }
  final end = offset + blockSize;
  if (end <= fileData.length) {
    return Uint8List.fromList(fileData.sublist(offset, end));
  }
  // Partial last block — copy available bytes, rest stays zero.
  final block = Uint8List(blockSize);
  for (var i = offset; i < fileData.length; i++) {
    block[i - offset] = fileData[i];
  }
  return block;
}

/// Verifies a single block against its 20-byte checksum entry
/// (16 bytes MD5 + 4 bytes CRC32 little-endian).
bool _verifyBlockChecksum(Uint8List block, Uint8List checksum) {
  // MD5 check.
  final computed = md5.convert(block).bytes;
  for (var i = 0; i < 16; i++) {
    if (computed[i] != checksum[i]) return false;
  }
  // CRC32 check.
  final crc = Crc32.compute(block);
  final stored = checksum[16] |
      (checksum[17] << 8) |
      (checksum[18] << 16) |
      (checksum[19] << 24);
  return crc == stored;
}

// ---------------------------------------------------------------------------
// Internal parsing types
// ---------------------------------------------------------------------------

/// Temporary container used during parsing before IFSC data is merged.
class _RawFileDesc {
  _RawFileDesc({
    required this.fileId,
    required this.filename,
    required this.fileSize,
    required this.md5Hash,
    required this.md5Hash16k,
  });

  final Uint8List fileId;
  final String filename;
  final int fileSize;
  final Uint8List md5Hash;
  final Uint8List md5Hash16k;
}

// ---------------------------------------------------------------------------
// Internal repair message (sent to compute isolate)
// ---------------------------------------------------------------------------

/// Packages all data needed by the repair isolate.
class _RepairMessage {
  _RepairMessage({
    required this.blockSize,
    required this.files,
    required this.availableData,
    required this.recoverySlices,
  });

  final int blockSize;
  final List<Par2FileDescription> files;
  final Map<String, List<int>> availableData;
  final List<Par2RecoverySlice> recoverySlices;
}

// ---------------------------------------------------------------------------
// Par2Engine
// ---------------------------------------------------------------------------

/// PAR2 parity file parser, verifier, and repair engine.
///
/// All methods are instance methods on a stateless engine object.
///
/// ```dart
/// const engine = Par2Engine();
/// final info = engine.parse(par2Bytes);
/// final result = engine.verify(info, {'file.rar': fileBytes});
/// if (engine.canRepair(result)) {
///   final repaired = await engine.repair(info, availableFiles, []);
/// }
/// ```
class Par2Engine {
  /// Creates a [Par2Engine].
  const Par2Engine();

  // -----------------------------------------------------------------------
  // parse
  // -----------------------------------------------------------------------

  /// Parses a PAR2 file and extracts all metadata, file descriptions,
  /// and recovery slices.
  ///
  /// Throws [FormatException] if [par2Data] is not valid PAR2.
  Par2FileInfo parse(List<int> par2Data) {
    final data =
        par2Data is Uint8List ? par2Data : Uint8List.fromList(par2Data);
    if (data.length < _headerSize) {
      throw const FormatException('Data too short for a PAR2 packet');
    }
    final view = ByteData.sublistView(data);

    Uint8List? recoverySetId;
    int? blockSize;
    String? creator;
    final fileDescs = <String, _RawFileDesc>{};
    final ifscData = <String, List<Uint8List>>{};
    final recoverySlices = <Par2RecoverySlice>[];

    var offset = 0;
    while (offset + _headerSize <= data.length) {
      // --- Magic ---
      if (!_bytesMatch(data, offset, _packetMagic)) {
        throw FormatException(
          'Invalid PAR2 packet magic at offset $offset',
        );
      }

      // --- Packet length ---
      final packetLen = _readUint64LE(view, offset + 8);
      if (packetLen < _headerSize) {
        throw FormatException(
          'Packet length $packetLen < header size at offset $offset',
        );
      }
      if (offset + packetLen > data.length) {
        throw FormatException(
          'Packet at offset $offset extends beyond data end',
        );
      }

      // --- Body MD5 verification ---
      final storedMd5 =
          Uint8List.sublistView(data, offset + 16, offset + 32);
      final computedMd5 =
          md5.convert(Uint8List.sublistView(data, offset + 32,
              offset + packetLen)).bytes;
      if (!_bytesEqual(storedMd5, computedMd5)) {
        throw FormatException(
          'Packet MD5 mismatch at offset $offset',
        );
      }

      // --- Recovery Set ID ---
      final setId =
          Uint8List.fromList(data.sublist(offset + 32, offset + 48));
      if (recoverySetId == null) {
        recoverySetId = setId;
      } else if (!_bytesEqual(recoverySetId, setId)) {
        throw FormatException(
          'Mismatched recovery set IDs at offset $offset',
        );
      }

      // --- Dispatch by type ---
      final typeOff = offset + 48;
      final bodyOff = offset + _headerSize;
      final bodyLen = packetLen - _headerSize;

      if (_bytesMatch(data, typeOff, _mainType)) {
        blockSize = _parseMain(view, bodyOff, bodyLen);
      } else if (_bytesMatch(data, typeOff, _fileDescType)) {
        _parseFileDesc(data, view, bodyOff, bodyLen, fileDescs);
      } else if (_bytesMatch(data, typeOff, _ifscType)) {
        _parseIfsc(data, bodyOff, bodyLen, ifscData);
      } else if (_bytesMatch(data, typeOff, _recvSlicType)) {
        _parseRecvSlic(data, view, bodyOff, bodyLen, recoverySlices);
      } else if (_bytesMatch(data, typeOff, _creatorType)) {
        creator = _parseCreator(data, bodyOff, bodyLen);
      }
      // Unknown types are silently ignored per the PAR2 specification.

      offset += packetLen;
    }

    if (recoverySetId == null) {
      throw const FormatException('No valid PAR2 packets found');
    }
    if (blockSize == null || blockSize == 0) {
      throw const FormatException(
        'Missing or zero-length Main packet (no block size)',
      );
    }

    // Merge File Description + IFSC checksum data.
    final files = <Par2FileDescription>[];
    for (final entry in fileDescs.entries) {
      final raw = entry.value;
      files.add(Par2FileDescription(
        fileId: raw.fileId,
        filename: raw.filename,
        fileSize: raw.fileSize,
        md5Hash: raw.md5Hash,
        md5Hash16k: raw.md5Hash16k,
        blockChecksums: ifscData[entry.key] ?? const [],
      ));
    }

    var totalBlocks = 0;
    for (final f in files) {
      totalBlocks += (f.fileSize + blockSize - 1) ~/ blockSize;
    }

    return Par2FileInfo(
      creator: creator,
      recoverySetId: recoverySetId,
      files: files,
      blockSize: blockSize,
      totalBlocks: totalBlocks,
      recoveryBlockCount: recoverySlices.length,
      recoverySlices: recoverySlices,
    );
  }

  // -----------------------------------------------------------------------
  // verify
  // -----------------------------------------------------------------------

  /// Verifies the integrity of [files] against the checksums in [par2].
  ///
  /// [files] maps filename → raw file bytes. Missing files are reported
  /// but do not throw.
  Par2VerifyResult verify(
    Par2FileInfo par2,
    Map<String, List<int>> files,
  ) {
    return _verifyImpl(par2, files);
  }

  // -----------------------------------------------------------------------
  // canRepair
  // -----------------------------------------------------------------------

  /// Returns `true` when [verification] indicates enough recovery data
  /// exists to reconstruct all missing or damaged blocks.
  bool canRepair(Par2VerifyResult verification) => verification.isRepairable;

  // -----------------------------------------------------------------------
  // repair
  // -----------------------------------------------------------------------

  /// Attempts to repair missing or damaged data blocks using
  /// Reed-Solomon error correction.
  ///
  /// [par2] provides block size, file descriptions, and recovery slices.
  /// [availableData] maps filename → file bytes for all files that are at
  /// least partially available. [recoveryBlocks] supplies additional
  /// raw recovery block data beyond what is already in the recovery slices
  /// of [par2] (pass an empty list when all recovery data was parsed into
  /// [par2]).
  ///
  /// The CPU-intensive Reed-Solomon computation runs in a separate isolate.
  Future<Par2RepairResult> repair(
    Par2FileInfo par2,
    Map<String, List<int>> availableData,
    List<List<int>> recoveryBlocks,
  ) {
    return compute(
      _repairInIsolate,
      _RepairMessage(
        blockSize: par2.blockSize,
        files: par2.files,
        availableData: availableData,
        recoverySlices: par2.recoverySlices,
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Private packet parsers
  // -----------------------------------------------------------------------

  /// Main packet → block size.
  static int _parseMain(ByteData view, int bodyOff, int bodyLen) {
    if (bodyLen < 12) {
      throw FormatException(
        'Main packet body too short ($bodyLen bytes)',
      );
    }
    final bs = _readUint64LE(view, bodyOff);
    if (bs <= 0) {
      throw FormatException('Invalid block size: $bs');
    }
    if (bs.isOdd) {
      throw FormatException(
        'Block size must be even for GF(2^16) word processing: $bs',
      );
    }
    return bs;
  }

  /// File Description packet → populates [descs] keyed by hex file-ID.
  static void _parseFileDesc(
    Uint8List data,
    ByteData view,
    int bodyOff,
    int bodyLen,
    Map<String, _RawFileDesc> descs,
  ) {
    // 16 file-ID + 16 MD5 + 16 MD5-16k + 8 length + ≥1 filename byte.
    if (bodyLen < 57) {
      throw FormatException(
        'FileDesc packet body too short ($bodyLen bytes)',
      );
    }
    final fileId =
        Uint8List.fromList(data.sublist(bodyOff, bodyOff + 16));
    final fileMd5 =
        Uint8List.fromList(data.sublist(bodyOff + 16, bodyOff + 32));
    final fileMd5_16k =
        Uint8List.fromList(data.sublist(bodyOff + 32, bodyOff + 48));
    final fileLen = _readUint64LE(view, bodyOff + 48);

    // Filename: null-terminated, padded to 4-byte boundary.
    final nameStart = bodyOff + 56;
    final nameEnd = bodyOff + bodyLen;
    var nameLength = 0;
    for (var i = nameStart; i < nameEnd; i++) {
      if (data[i] == 0) break;
      nameLength++;
    }
    final filename = String.fromCharCodes(
      data.sublist(nameStart, nameStart + nameLength),
    );

    final key = _hexId(fileId);
    descs[key] = _RawFileDesc(
      fileId: fileId,
      filename: filename,
      fileSize: fileLen,
      md5Hash: fileMd5,
      md5Hash16k: fileMd5_16k,
    );
  }

  /// Input File Slice Checksum packet → populates [checksums] keyed by
  /// hex file-ID.
  static void _parseIfsc(
    Uint8List data,
    int bodyOff,
    int bodyLen,
    Map<String, List<Uint8List>> checksums,
  ) {
    if (bodyLen < 16) {
      throw FormatException(
        'IFSC packet body too short ($bodyLen bytes)',
      );
    }
    final fileId = data.sublist(bodyOff, bodyOff + 16);
    final key = _hexId(fileId);

    const pairSize = 20; // 16 MD5 + 4 CRC32
    final pairsStart = bodyOff + 16;
    final pairsLen = bodyLen - 16;
    if (pairsLen % pairSize != 0) {
      throw FormatException(
        'IFSC checksum data length $pairsLen is not a multiple of $pairSize',
      );
    }
    final count = pairsLen ~/ pairSize;
    final pairs = <Uint8List>[];
    for (var i = 0; i < count; i++) {
      final off = pairsStart + i * pairSize;
      pairs.add(Uint8List.fromList(data.sublist(off, off + pairSize)));
    }
    checksums[key] = pairs;
  }

  /// Recovery Slice packet → appends to [slices].
  static void _parseRecvSlic(
    Uint8List data,
    ByteData view,
    int bodyOff,
    int bodyLen,
    List<Par2RecoverySlice> slices,
  ) {
    if (bodyLen < 4) {
      throw FormatException(
        'RecvSlic packet body too short ($bodyLen bytes)',
      );
    }
    final exponent = view.getUint32(bodyOff, Endian.little);
    final recData = Uint8List.fromList(
      data.sublist(bodyOff + 4, bodyOff + bodyLen),
    );
    slices.add(Par2RecoverySlice(exponent: exponent, data: recData));
  }

  /// Creator packet → returns the creator string.
  static String _parseCreator(Uint8List data, int bodyOff, int bodyLen) {
    // Strip trailing nulls.
    var end = bodyOff + bodyLen;
    while (end > bodyOff && data[end - 1] == 0) {
      end--;
    }
    return String.fromCharCodes(data.sublist(bodyOff, end));
  }
}

// ---------------------------------------------------------------------------
// Verification implementation (usable from both instance and isolate)
// ---------------------------------------------------------------------------

/// Stateless verification logic shared between [Par2Engine.verify] and the
/// repair isolate.
Par2VerifyResult _verifyImpl(
  Par2FileInfo par2,
  Map<String, List<int>> files,
) {
  final statuses = <Par2FileStatus>[];
  var totalMissing = 0;

  for (final desc in par2.files) {
    final fileData = files[desc.filename];
    final numBlocks = (desc.fileSize + par2.blockSize - 1) ~/ par2.blockSize;

    if (fileData == null) {
      // Entire file missing.
      statuses.add(Par2FileStatus(
        filename: desc.filename,
        present: false,
        intact: false,
        damagedBlockIndices: const [],
        missingBlockIndices: List<int>.generate(numBlocks, (i) => i),
      ));
      totalMissing += numBlocks;
      continue;
    }

    // File present — verify per-block checksums.
    final damaged = <int>[];
    final missing = <int>[];

    for (var b = 0; b < numBlocks; b++) {
      final blockStart = b * par2.blockSize;
      if (blockStart >= fileData.length) {
        // Block completely beyond available data (truncated file).
        missing.add(b);
        continue;
      }
      if (b < desc.blockChecksums.length) {
        final block = _extractBlock(fileData, b, par2.blockSize);
        if (!_verifyBlockChecksum(block, desc.blockChecksums[b])) {
          damaged.add(b);
        }
      }
    }

    statuses.add(Par2FileStatus(
      filename: desc.filename,
      present: true,
      intact: damaged.isEmpty && missing.isEmpty,
      damagedBlockIndices: damaged,
      missingBlockIndices: missing,
    ));
    totalMissing += damaged.length + missing.length;
  }

  // Deduplicate recovery exponents.
  final seenExponents = <int>{};
  var uniqueRecovery = 0;
  for (final s in par2.recoverySlices) {
    if (seenExponents.add(s.exponent)) uniqueRecovery++;
  }

  final allPresent = statuses.every((s) => s.present);
  final allIntact = statuses.every((s) => s.intact);

  return Par2VerifyResult(
    allFilesPresent: allPresent,
    allFilesIntact: allIntact,
    fileStatuses: statuses,
    missingBlockCount: totalMissing,
    availableRecoveryBlocks: uniqueRecovery,
  );
}

// ---------------------------------------------------------------------------
// Repair implementation (runs inside a compute isolate)
// ---------------------------------------------------------------------------

/// Top-level function invoked by [compute] for CPU-intensive repair.
Par2RepairResult _repairInIsolate(_RepairMessage msg) {
  final blockSize = msg.blockSize;
  final files = msg.files;
  final available = msg.availableData;
  final slices = msg.recoverySlices;

  // --- Build synthetic Par2FileInfo for verification. ---
  final par2 = Par2FileInfo(
    recoverySetId: Uint8List(16),
    files: files,
    blockSize: blockSize,
    totalBlocks: 0, // recomputed below
    recoveryBlockCount: slices.length,
    recoverySlices: slices,
  );

  // Compute true totalBlocks.
  var totalBlocks = 0;
  for (final f in files) {
    totalBlocks += (f.fileSize + blockSize - 1) ~/ blockSize;
  }

  // --- Verify to find missing/damaged blocks. ---
  final verification = _verifyImpl(
    Par2FileInfo(
      recoverySetId: par2.recoverySetId,
      files: files,
      blockSize: blockSize,
      totalBlocks: totalBlocks,
      recoveryBlockCount: slices.length,
      recoverySlices: slices,
    ),
    available,
  );

  if (verification.allFilesIntact) {
    return const Par2RepairSuccess(repairedFiles: {});
  }

  // --- Collect globally-indexed missing block positions. ---
  final globalMissing = <int>[];
  var globalOffset = 0;

  for (final status in verification.fileStatuses) {
    final desc = files.firstWhere((f) => f.filename == status.filename);
    final numBlocks = (desc.fileSize + blockSize - 1) ~/ blockSize;

    if (!status.present) {
      for (var b = 0; b < numBlocks; b++) {
        globalMissing.add(globalOffset + b);
      }
    } else {
      for (final b in status.damagedBlockIndices) {
        globalMissing.add(globalOffset + b);
      }
      for (final b in status.missingBlockIndices) {
        globalMissing.add(globalOffset + b);
      }
    }
    globalOffset += numBlocks;
  }

  if (globalMissing.isEmpty) {
    return const Par2RepairSuccess(repairedFiles: {});
  }

  // --- Select recovery slices with distinct exponents. ---
  final uniqueSlices = <int, Par2RecoverySlice>{};
  for (final s in slices) {
    uniqueSlices.putIfAbsent(s.exponent, () => s);
  }

  final needed = globalMissing.length;
  if (uniqueSlices.length < needed) {
    return Par2RepairFailure(
      reason: 'Not enough recovery blocks '
          '(need $needed, have ${uniqueSlices.length})',
      missingBlocks: needed,
      availableRecovery: uniqueSlices.length,
    );
  }

  // Pick exactly `needed` slices.
  final chosenSlices = uniqueSlices.values.take(needed).toList();

  // --- Build Vandermonde-like matrix A[j][k] = α^(e_j * m_k). ---
  final m = needed;
  final matrix = List.generate(m, (j) {
    final e = chosenSlices[j].exponent;
    return List.generate(m, (k) {
      final idx = globalMissing[k];
      return _GaloisField.pow(2, e * idx); // α = 2 (primitive element)
    });
  });

  // --- Invert the matrix via Gaussian elimination over GF(2^16). ---
  final invMatrix = _invertMatrix(matrix);
  if (invMatrix == null) {
    return Par2RepairFailure(
      reason: 'Recovery matrix is singular — cannot solve',
      missingBlocks: needed,
      availableRecovery: uniqueSlices.length,
    );
  }

  // --- Build data block array (known blocks filled, missing zeroed). ---
  final allBlocks = <Uint8List>[];
  globalOffset = 0;
  for (final desc in files) {
    final numBlocks = (desc.fileSize + blockSize - 1) ~/ blockSize;
    final fileData = available[desc.filename];
    for (var b = 0; b < numBlocks; b++) {
      if (fileData != null) {
        allBlocks.add(_extractBlock(fileData, b, blockSize));
      } else {
        allBlocks.add(Uint8List(blockSize));
      }
    }
  }

  // --- Compute syndromes: S_j = R_{e_j} ⊕ Σ_{known i} α^(e_j·i)·D_i ---
  final wordsPerBlock = blockSize ~/ 2;
  final missingSet = globalMissing.toSet();

  final syndromes = List.generate(m, (_) => Uint16List(wordsPerBlock));

  for (var j = 0; j < m; j++) {
    final e = chosenSlices[j].exponent;
    final recoveryData = chosenSlices[j].data;

    // Start with recovery block words.
    for (var w = 0; w < wordsPerBlock; w++) {
      final off = w * 2;
      syndromes[j][w] = recoveryData[off] | (recoveryData[off + 1] << 8);
    }

    // XOR away contributions from known data blocks.
    for (var i = 0; i < allBlocks.length; i++) {
      if (missingSet.contains(i)) continue;
      final coeff = _GaloisField.pow(2, e * i);
      if (coeff == 0) continue;
      final block = allBlocks[i];
      for (var w = 0; w < wordsPerBlock; w++) {
        final off = w * 2;
        final dw = block[off] | (block[off + 1] << 8);
        syndromes[j][w] ^= _GaloisField.mul(coeff, dw);
      }
    }
  }

  // --- Solve for missing blocks: X_k[w] = Σ_j invA[k][j] · S_j[w] ---
  final recovered = List.generate(m, (_) => Uint8List(blockSize));

  for (var w = 0; w < wordsPerBlock; w++) {
    for (var k = 0; k < m; k++) {
      var val = 0;
      for (var j = 0; j < m; j++) {
        val ^= _GaloisField.mul(invMatrix[k][j], syndromes[j][w]);
      }
      final off = w * 2;
      recovered[k][off] = val & 0xFF;
      recovered[k][off + 1] = (val >> 8) & 0xFF;
    }
  }

  // --- Place recovered blocks back into file data. ---
  for (var k = 0; k < m; k++) {
    allBlocks[globalMissing[k]] = recovered[k];
  }

  // --- Reassemble files that had missing or damaged blocks. ---
  final repairedFiles = <String, Uint8List>{};
  globalOffset = 0;

  for (var fi = 0; fi < files.length; fi++) {
    final desc = files[fi];
    final numBlocks = (desc.fileSize + blockSize - 1) ~/ blockSize;
    final status = verification.fileStatuses[fi];

    if (!status.intact) {
      final out = Uint8List(desc.fileSize);
      var written = 0;
      for (var b = 0; b < numBlocks; b++) {
        final block = allBlocks[globalOffset + b];
        final toCopy =
            (written + blockSize > desc.fileSize)
                ? desc.fileSize - written
                : blockSize;
        out.setRange(written, written + toCopy, block);
        written += toCopy;
      }
      repairedFiles[desc.filename] = out;
    }
    globalOffset += numBlocks;
  }

  return Par2RepairSuccess(repairedFiles: repairedFiles);
}

// ---------------------------------------------------------------------------
// Matrix inversion over GF(2^16)
// ---------------------------------------------------------------------------

/// Inverts an M×M matrix over GF(2^16) using Gaussian elimination with
/// partial pivoting.
///
/// Returns the inverse matrix, or `null` if the matrix is singular.
List<List<int>>? _invertMatrix(List<List<int>> matrix) {
  final m = matrix.length;
  if (m == 0) return const [];

  // Build augmented matrix [A | I].
  final aug = List.generate(m, (i) {
    final row = List<int>.filled(2 * m, 0);
    for (var j = 0; j < m; j++) {
      row[j] = matrix[i][j];
    }
    row[m + i] = 1;
    return row;
  });

  // Forward elimination with partial pivoting.
  for (var col = 0; col < m; col++) {
    // Find a non-zero pivot in this column.
    var pivotRow = -1;
    for (var row = col; row < m; row++) {
      if (aug[row][col] != 0) {
        pivotRow = row;
        break;
      }
    }
    if (pivotRow == -1) return null; // singular

    // Swap pivot row into position.
    if (pivotRow != col) {
      final tmp = aug[col];
      aug[col] = aug[pivotRow];
      aug[pivotRow] = tmp;
    }

    // Scale pivot row so the diagonal entry becomes 1.
    final pivotVal = aug[col][col];
    if (pivotVal != 1) {
      final inv = _GaloisField.div(1, pivotVal);
      for (var j = col; j < 2 * m; j++) {
        aug[col][j] = _GaloisField.mul(aug[col][j], inv);
      }
    }

    // Eliminate all other rows in this column.
    for (var row = 0; row < m; row++) {
      if (row == col) continue;
      final factor = aug[row][col];
      if (factor == 0) continue;
      for (var j = col; j < 2 * m; j++) {
        aug[row][j] =
            _GaloisField.add(aug[row][j], _GaloisField.mul(factor, aug[col][j]));
      }
    }
  }

  // Extract the right half as the inverse.
  return List.generate(m, (i) => aug[i].sublist(m));
}
