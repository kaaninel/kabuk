import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/platform/shared/usenet/rar_extractor.dart';

// ---------------------------------------------------------------------------
// Helpers — build minimal valid RAR archives in memory
// ---------------------------------------------------------------------------

/// Builds a RAR5 vint encoding of [value].
Uint8List _vint(int value) {
  final bytes = <int>[];
  var v = value;
  while (v > 0x7F) {
    bytes.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  bytes.add(v & 0x7F);
  return Uint8List.fromList(bytes);
}

/// Writes a uint32-LE into 4 bytes.
Uint8List _uint32LE(int value) {
  final b = ByteData(4)..setUint32(0, value, Endian.little);
  return b.buffer.asUint8List();
}

/// Writes a uint16-LE into 2 bytes.
Uint8List _uint16LE(int value) {
  final b = ByteData(2)..setUint16(0, value, Endian.little);
  return b.buffer.asUint8List();
}

/// CRC32 matching the private _Crc32 in rar_extractor.dart.
int _crc32(List<int> data, [int crc = 0]) {
  const polynomial = 0xEDB88320;
  final table = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var j = 0; j < 8; j++) {
      c = (c & 1 == 1) ? (c >> 1) ^ polynomial : c >> 1;
    }
    table[i] = c;
  }
  var c = crc ^ 0xFFFFFFFF;
  for (final b in data) {
    c = table[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// RAR5 magic bytes.
final _rar5Magic = Uint8List.fromList(
  [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00],
);

/// RAR4 magic bytes.
final _rar4Magic = Uint8List.fromList(
  [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00],
);

/// Builds a minimal RAR5 archive with a single Store-method file.
Uint8List _buildRar5StoreArchive(String filename, Uint8List fileData) {
  final nameBytes = Uint8List.fromList(filename.codeUnits);
  final dataCrc = _crc32(fileData);

  // --- File header body ---
  // type=2, flags=0x0002 (data area present)
  // We also set file flags for time and CRC.
  final fileFlags = _vint(0x0004); // CRC present
  final unpackedSize = _vint(fileData.length);
  final attributes = _vint(0);
  final crcBytes = _uint32LE(dataCrc);
  // compressionInfo: version=0, solid=0, method=0 (Store), dict=0 → 0x0000
  final compressionInfo = _vint(0);
  final hostOs = _vint(0); // Windows
  final nameLen = _vint(nameBytes.length);

  final fileSpecific = BytesBuilder()
    ..add(fileFlags)
    ..add(unpackedSize)
    ..add(attributes)
    ..add(crcBytes)
    ..add(compressionInfo)
    ..add(hostOs)
    ..add(nameLen)
    ..add(nameBytes);
  final fileSpecificBytes = fileSpecific.takeBytes();

  final headerType = _vint(2); // File header
  final headerFlags = _vint(0x0002); // data area present
  final dataAreaSize = _vint(fileData.length);

  final headerBody = BytesBuilder()
    ..add(headerType)
    ..add(headerFlags)
    ..add(dataAreaSize)
    ..add(fileSpecificBytes);
  final headerBodyBytes = headerBody.takeBytes();

  final headerSize = _vint(headerBodyBytes.length);

  // CRC covers headerSize vint + headerBody.
  final crcInput = BytesBuilder()
    ..add(headerSize)
    ..add(headerBodyBytes);
  final crcInputBytes = crcInput.takeBytes();
  final headerCrc = _uint32LE(_crc32(crcInputBytes));

  // --- Main archive header ---
  final mainArchiveFlags = _vint(0); // no special flags
  final mainType = _vint(1);
  final mainHeaderFlags = _vint(0);
  final mainBody = BytesBuilder()
    ..add(mainType)
    ..add(mainHeaderFlags)
    ..add(mainArchiveFlags);
  final mainBodyBytes = mainBody.takeBytes();
  final mainSize = _vint(mainBodyBytes.length);
  final mainCrcInput = BytesBuilder()
    ..add(mainSize)
    ..add(mainBodyBytes);
  final mainCrcBytes = mainCrcInput.takeBytes();
  final mainCrc = _uint32LE(_crc32(mainCrcBytes));

  // --- End of archive header ---
  final endType = _vint(5);
  final endFlags = _vint(0);
  final endBody = BytesBuilder()
    ..add(endType)
    ..add(endFlags);
  final endBodyBytes = endBody.takeBytes();
  final endSize = _vint(endBodyBytes.length);
  final endCrcInput = BytesBuilder()
    ..add(endSize)
    ..add(endBodyBytes);
  final endCrcBytes = endCrcInput.takeBytes();
  final endCrc = _uint32LE(_crc32(endCrcBytes));

  // --- Assemble archive ---
  final archive = BytesBuilder()
    // Magic
    ..add(_rar5Magic)
    // Main header
    ..add(mainCrc)
    ..add(mainSize)
    ..add(mainBodyBytes)
    // File header
    ..add(headerCrc)
    ..add(headerSize)
    ..add(headerBodyBytes)
    // File data
    ..add(fileData)
    // End header
    ..add(endCrc)
    ..add(endSize)
    ..add(endBodyBytes);

  return archive.takeBytes();
}

/// Builds a minimal RAR4 archive with a single Store-method file.
Uint8List _buildRar4StoreArchive(String filename, Uint8List fileData) {
  final nameBytes = Uint8List.fromList(filename.codeUnits);
  final dataCrc = _crc32(fileData);

  // --- Main archive header (type 0x73) ---
  // HEAD_CRC(2) + HEAD_TYPE(1) + HEAD_FLAGS(2) + HEAD_SIZE(2) + reserved(6)
  final mainHeader = BytesBuilder()
    ..add([0x00, 0x00]) // placeholder CRC
    ..add([0x73]) // type
    ..add(_uint16LE(0x0000)) // flags
    ..add(_uint16LE(13)) // header size = 7 + 6
    ..add([0, 0]) // reserved1
    ..add([0, 0, 0, 0]); // reserved2
  final mainBytes = mainHeader.takeBytes();
  // Compute CRC over bytes 2..end.
  final mainCrc = _crc32(mainBytes.sublist(2)) & 0xFFFF;
  mainBytes[0] = mainCrc & 0xFF;
  mainBytes[1] = (mainCrc >> 8) & 0xFF;

  // --- File header (type 0x74) ---
  // Standard: CRC(2)+TYPE(1)+FLAGS(2)+SIZE(2) = 7
  // File fields: PACK(4)+UNP(4)+OS(1)+CRC(4)+FTIME(4)+VER(1)+METHOD(1)+NAME_SIZE(2)+ATTR(4) = 25
  // + NAME
  final headSize = 7 + 25 + nameBytes.length;
  final fileHeader = BytesBuilder()
    ..add([0x00, 0x00]) // placeholder CRC
    ..add([0x74]) // type
    ..add(_uint16LE(0x8000)) // flags: LONG_BLOCK
    ..add(_uint16LE(headSize))
    ..add(_uint32LE(fileData.length)) // PACK_SIZE
    ..add(_uint32LE(fileData.length)) // UNP_SIZE
    ..add([0x00]) // HOST_OS
    ..add(_uint32LE(dataCrc)) // FILE_CRC
    ..add(_uint32LE(0)) // FTIME
    ..add([0x1D]) // UNP_VER (2.9)
    ..add([0x30]) // METHOD: Store
    ..add(_uint16LE(nameBytes.length))
    ..add(_uint32LE(0x20)) // ATTR: archive
    ..add(nameBytes);
  final fileBytes = fileHeader.takeBytes();
  final fileCrc = _crc32(fileBytes.sublist(2)) & 0xFFFF;
  fileBytes[0] = fileCrc & 0xFF;
  fileBytes[1] = (fileCrc >> 8) & 0xFF;

  // --- End of archive header (type 0x7B) ---
  final endHeader = BytesBuilder()
    ..add([0x00, 0x00]) // placeholder CRC
    ..add([0x7B]) // type
    ..add(_uint16LE(0x4000)) // flags
    ..add(_uint16LE(7)); // size = 7
  final endBytes = endHeader.takeBytes();
  final endCrc = _crc32(endBytes.sublist(2)) & 0xFFFF;
  endBytes[0] = endCrc & 0xFF;
  endBytes[1] = (endCrc >> 8) & 0xFF;

  // --- Assemble ---
  final archive = BytesBuilder()
    ..add(_rar4Magic)
    ..add(mainBytes)
    ..add(fileBytes)
    ..add(fileData)
    ..add(endBytes);

  return archive.takeBytes();
}

Stream<List<int>> _streamFromBytes(Uint8List data, {int chunkSize = 64}) {
  return Stream<List<int>>.fromIterable(
    Iterable<List<int>>.generate(
      (data.length + chunkSize - 1) ~/ chunkSize,
      (i) {
        final start = i * chunkSize;
        final end =
            start + chunkSize > data.length ? data.length : start + chunkSize;
        return Uint8List.sublistView(data, start, end);
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RarExtractor.isRarArchive', () {
    test('detects RAR5 magic', () {
      expect(RarExtractor.isRarArchive(_rar5Magic), isTrue);
    });

    test('detects RAR4 magic', () {
      expect(RarExtractor.isRarArchive(_rar4Magic), isTrue);
    });

    test('rejects too-short input', () {
      expect(RarExtractor.isRarArchive([0x52, 0x61]), isFalse);
    });

    test('rejects non-RAR data', () {
      expect(
        RarExtractor.isRarArchive(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
        isFalse,
      );
    });
  });

  group('RAR5 Store extraction', () {
    test('extracts a single file with valid CRC', () async {
      final fileData = Uint8List.fromList(
        List<int>.generate(256, (i) => i & 0xFF),
      );
      final archive = _buildRar5StoreArchive('test.bin', fileData);

      final extractor = RarExtractor();
      final events = await extractor
          .extract(_streamFromBytes(archive, chunkSize: 32))
          .toList();

      // Expect: FileStart, one or more FileData, FileEnd, possibly Progress.
      final starts =
          events.whereType<RarFileStart>().toList();
      final dataEvents =
          events.whereType<RarFileData>().toList();
      final ends =
          events.whereType<RarFileEnd>().toList();

      expect(starts, hasLength(1));
      expect(starts.first.filename, 'test.bin');
      expect(starts.first.compressionMethod, 'Store');
      expect(starts.first.uncompressedSize, fileData.length);

      // Reassemble data.
      final builder = BytesBuilder();
      for (final d in dataEvents) {
        builder.add(d.data);
      }
      expect(builder.takeBytes(), fileData);

      expect(ends, hasLength(1));
      expect(ends.first.filename, 'test.bin');
      expect(ends.first.checksumValid, isTrue);
    });

    test('handles single-byte chunks', () async {
      final fileData = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final archive = _buildRar5StoreArchive('tiny.dat', fileData);

      final events = await const RarExtractor()
          .extract(_streamFromBytes(archive, chunkSize: 1))
          .toList();

      final dataEvents = events.whereType<RarFileData>().toList();
      final builder = BytesBuilder();
      for (final d in dataEvents) {
        builder.add(d.data);
      }
      expect(builder.takeBytes(), fileData);
    });

    test('whole archive in one chunk', () async {
      final fileData = Uint8List.fromList([1, 2, 3]);
      final archive = _buildRar5StoreArchive('one.bin', fileData);

      final events = await const RarExtractor()
          .extract(Stream<List<int>>.value(archive))
          .toList();

      expect(events.whereType<RarFileStart>(), hasLength(1));
      expect(events.whereType<RarFileEnd>(), hasLength(1));

      final builder = BytesBuilder();
      for (final d in events.whereType<RarFileData>()) {
        builder.add(d.data);
      }
      expect(builder.takeBytes(), fileData);
    });
  });

  group('RAR4 Store extraction', () {
    test('extracts a single file with valid CRC', () async {
      final fileData = Uint8List.fromList(
        List<int>.generate(128, (i) => (i * 7) & 0xFF),
      );
      final archive = _buildRar4StoreArchive('legacy.bin', fileData);

      final events = await const RarExtractor()
          .extract(_streamFromBytes(archive, chunkSize: 48))
          .toList();

      final starts = events.whereType<RarFileStart>().toList();
      final ends = events.whereType<RarFileEnd>().toList();
      final dataEvents = events.whereType<RarFileData>().toList();

      expect(starts, hasLength(1));
      expect(starts.first.filename, 'legacy.bin');
      expect(starts.first.compressionMethod, 'Store');

      final builder = BytesBuilder();
      for (final d in dataEvents) {
        builder.add(d.data);
      }
      expect(builder.takeBytes(), fileData);

      expect(ends, hasLength(1));
      expect(ends.first.checksumValid, isTrue);
    });
  });

  group('inspect', () {
    test('returns archive info without extracting data', () async {
      final fileData = Uint8List.fromList([10, 20, 30]);
      final archive = _buildRar5StoreArchive('info.txt', fileData);

      final info = await const RarExtractor().inspect(archive);

      expect(info.version, RarVersion.rar5);
      expect(info.isMultiVolume, isFalse);
      expect(info.isSolid, isFalse);
      expect(info.isEncrypted, isFalse);
      expect(info.files, hasLength(1));
      expect(info.files.first.filename, 'info.txt');
      expect(info.files.first.compressionMethod, 'Store');
      expect(info.files.first.uncompressedSize, 3);
    });
  });

  group('error handling', () {
    test('emits error for invalid magic', () async {
      final garbage = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);

      final events = await const RarExtractor()
          .extract(Stream<List<int>>.value(garbage))
          .toList();

      expect(events.whereType<RarError>(), isNotEmpty);
      expect(events.whereType<RarError>().first.recoverable, isFalse);
    });

    test('emits error on truncated stream', () async {
      final fileData = Uint8List.fromList(List<int>.filled(100, 0xAA));
      final archive = _buildRar5StoreArchive('trunc.bin', fileData);

      // Truncate to cut off file data mid-stream.
      final truncated = Uint8List.sublistView(archive, 0, archive.length - 50);

      final events = await const RarExtractor()
          .extract(Stream<List<int>>.value(truncated))
          .toList();

      final errors = events.whereType<RarError>().toList();
      expect(errors, isNotEmpty);
    });
  });

  group('multi-volume', () {
    test('extractMultiVolume processes multiple streams', () async {
      // Simulate two volumes each containing a complete small archive.
      // In practice volumes share a single logical file, but this tests
      // the stream-chaining plumbing.
      final data1 = Uint8List.fromList([1, 2, 3]);
      final data2 = Uint8List.fromList([4, 5, 6]);

      final vol1 = _buildRar5StoreArchive('file1.bin', data1);
      final vol2 = _buildRar5StoreArchive('file2.bin', data2);

      final events = await const RarExtractor()
          .extractMultiVolume([
            Stream<List<int>>.value(vol1),
            Stream<List<int>>.value(vol2),
          ])
          .toList();

      final starts = events.whereType<RarFileStart>().toList();
      expect(starts.length, greaterThanOrEqualTo(2));
      expect(starts[0].filename, 'file1.bin');
      expect(starts[1].filename, 'file2.bin');
    });
  });
}
