/// Post-processing pipeline orchestrator for Usenet binary reassembly.
///
/// Takes decoded segment data from an NZB and orchestrates the full
/// pipeline: classify files → verify with PAR2 → repair if needed →
/// extract from RAR if needed → output final content stream.
///
/// The processor works as a streaming pipeline — segments are
/// accumulated as they arrive, and output events are emitted as soon
/// as complete files or extraction results become available.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'nzb_parser.dart';
import 'par2_engine.dart';
import 'rar_extractor.dart';
import 'yenc_decoder.dart';

// ---------------------------------------------------------------------------
// DecodedSegment
// ---------------------------------------------------------------------------

/// A single decoded segment ready for reassembly.
///
/// Produced by the download layer after fetching an NNTP article and
/// running it through [YencDecoder]. The post-processor groups these
/// by [filename] and orders them by [segmentNumber] to reconstruct
/// complete files.
@immutable
class DecodedSegment {
  /// Creates a [DecodedSegment].
  const DecodedSegment({
    required this.filename,
    required this.segmentNumber,
    required this.data,
    required this.checksumValid,
  });

  /// Which NZB file this segment belongs to.
  final String filename;

  /// 1-based segment index within the file.
  final int segmentNumber;

  /// Decoded (yEnc-decoded) segment bytes.
  final Uint8List data;

  /// Whether the yEnc CRC32 checksum was valid for this segment.
  final bool checksumValid;

  @override
  String toString() =>
      'DecodedSegment($filename, #$segmentNumber, ${data.length} B, '
      'crc=$checksumValid)';
}

// ---------------------------------------------------------------------------
// PostProcessEvent
// ---------------------------------------------------------------------------

/// Events emitted by the post-processing pipeline.
///
/// Use exhaustive pattern matching to handle all event types:
///
/// ```dart
/// await for (final event in processor.process(nzb, segments)) {
///   switch (event) {
///     case PostProcessAnalyzing():   ...
///     case PostProcessProgress():    ...
///     case PostProcessFileData():    ...
///     case PostProcessFileComplete():...
///     case PostProcessVerifying():   ...
///     case PostProcessRepairing():   ...
///     case PostProcessExtracting():  ...
///     case PostProcessComplete():    ...
///     case PostProcessError():       ...
///   }
/// }
/// ```
sealed class PostProcessEvent {
  const PostProcessEvent();
}

/// Emitted during the initial file classification and analysis phase.
final class PostProcessAnalyzing extends PostProcessEvent {
  /// Creates a [PostProcessAnalyzing] event.
  const PostProcessAnalyzing({required this.message});

  /// Human-readable description of the current analysis step.
  final String message;

  @override
  String toString() => 'PostProcessAnalyzing($message)';
}

/// Progress update as files are reassembled and processed.
final class PostProcessProgress extends PostProcessEvent {
  /// Creates a [PostProcessProgress] event.
  const PostProcessProgress({
    required this.filesProcessed,
    required this.totalFiles,
    required this.currentFile,
    required this.percent,
  });

  /// Number of files fully reassembled so far.
  final int filesProcessed;

  /// Total number of files expected.
  final int totalFiles;

  /// Name of the file currently being processed.
  final String currentFile;

  /// Overall progress percentage (0.0 – 1.0).
  final double percent;

  @override
  String toString() =>
      'PostProcessProgress($filesProcessed/$totalFiles, '
      '${(percent * 100).toStringAsFixed(1)}%, $currentFile)';
}

/// A chunk of final output file data.
///
/// Multiple [PostProcessFileData] events may be emitted for a single
/// output file (e.g. during RAR extraction). Collect all chunks until
/// the corresponding [PostProcessFileComplete] event arrives.
final class PostProcessFileData extends PostProcessEvent {
  /// Creates a [PostProcessFileData] event.
  const PostProcessFileData({
    required this.filename,
    required this.data,
    this.mimeType,
  });

  /// Output filename.
  final String filename;

  /// Chunk of file data bytes.
  final Uint8List data;

  /// Detected MIME type, if known.
  final String? mimeType;

  @override
  String toString() =>
      'PostProcessFileData($filename, ${data.length} B, $mimeType)';
}

/// Emitted when a single output file has been fully delivered.
final class PostProcessFileComplete extends PostProcessEvent {
  /// Creates a [PostProcessFileComplete] event.
  const PostProcessFileComplete({
    required this.filename,
    required this.totalBytes,
    this.mimeType,
  });

  /// Output filename.
  final String filename;

  /// Total size of the completed file in bytes.
  final int totalBytes;

  /// Detected MIME type, if known.
  final String? mimeType;

  @override
  String toString() =>
      'PostProcessFileComplete($filename, $totalBytes B, $mimeType)';
}

/// Emitted when PAR2 verification begins for a file.
final class PostProcessVerifying extends PostProcessEvent {
  /// Creates a [PostProcessVerifying] event.
  const PostProcessVerifying({required this.filename});

  /// File being verified.
  final String filename;

  @override
  String toString() => 'PostProcessVerifying($filename)';
}

/// Emitted when PAR2 repair is in progress.
final class PostProcessRepairing extends PostProcessEvent {
  /// Creates a [PostProcessRepairing] event.
  const PostProcessRepairing({
    required this.filename,
    required this.missingBlocks,
    required this.recoveryBlocks,
  });

  /// File being repaired.
  final String filename;

  /// Number of data blocks that are missing or damaged.
  final int missingBlocks;

  /// Number of recovery blocks available for repair.
  final int recoveryBlocks;

  @override
  String toString() =>
      'PostProcessRepairing($filename, missing=$missingBlocks, '
      'recovery=$recoveryBlocks)';
}

/// Emitted when RAR extraction begins for a file.
final class PostProcessExtracting extends PostProcessEvent {
  /// Creates a [PostProcessExtracting] event.
  const PostProcessExtracting({required this.filename});

  /// RAR archive part being extracted.
  final String filename;

  @override
  String toString() => 'PostProcessExtracting($filename)';
}

/// Emitted when the entire post-processing pipeline is complete.
final class PostProcessComplete extends PostProcessEvent {
  /// Creates a [PostProcessComplete] event.
  const PostProcessComplete({
    required this.totalFiles,
    required this.totalBytes,
  });

  /// Total number of output files delivered.
  final int totalFiles;

  /// Total bytes across all output files.
  final int totalBytes;

  @override
  String toString() =>
      'PostProcessComplete($totalFiles files, $totalBytes B)';
}

/// Emitted when an error occurs during post-processing.
final class PostProcessError extends PostProcessEvent {
  /// Creates a [PostProcessError] event.
  const PostProcessError({
    required this.message,
    required this.fatal,
  });

  /// Human-readable error description.
  final String message;

  /// Whether the error is fatal (pipeline cannot continue).
  final bool fatal;

  @override
  String toString() => 'PostProcessError($message, fatal=$fatal)';
}

// ---------------------------------------------------------------------------
// PostProcessPlan
// ---------------------------------------------------------------------------

/// Analysis result describing what post-processing steps an NZB requires.
///
/// Produced by [PostProcessor.analyze] without performing any actual
/// processing. Useful for showing the user what will happen before
/// starting the pipeline.
@immutable
class PostProcessPlan {
  /// Creates a [PostProcessPlan].
  const PostProcessPlan({
    required this.contentFiles,
    required this.par2Files,
    required this.rarParts,
    required this.needsRarExtraction,
    required this.hasPar2Recovery,
    this.detectedContentType,
    required this.estimatedContentSize,
    required this.steps,
  });

  /// Main content files (non-PAR2, non-sample, non-NFO).
  final List<NzbFileEntry> contentFiles;

  /// PAR2 parity/recovery files.
  final List<NzbFileEntry> par2Files;

  /// RAR archive parts (subset of [contentFiles] that are RAR volumes).
  final List<NzbFileEntry> rarParts;

  /// Whether content is RAR-archived and requires extraction.
  final bool needsRarExtraction;

  /// Whether PAR2 recovery files are available for verification/repair.
  final bool hasPar2Recovery;

  /// Best-guess content type (e.g. `"video/x-matroska"`), or `null`.
  final String? detectedContentType;

  /// Estimated uncompressed content size in bytes.
  final int estimatedContentSize;

  /// Human-readable list of processing steps that will be performed.
  final List<String> steps;

  @override
  String toString() =>
      'PostProcessPlan(content=${contentFiles.length}, '
      'par2=${par2Files.length}, rar=${rarParts.length}, '
      'extract=$needsRarExtraction, recovery=$hasPar2Recovery, '
      'type=$detectedContentType, '
      'size=$estimatedContentSize)';
}

// ---------------------------------------------------------------------------
// Magic byte detection
// ---------------------------------------------------------------------------

/// Detects the MIME type of a file from its leading magic bytes.
///
/// Returns `null` if the byte sequence is too short or does not match
/// any known signature.
String? detectMimeType(List<int> bytes) {
  if (bytes.length < 4) return null;

  // MKV / WebM: EBML header 0x1A45DFA3
  if (bytes[0] == 0x1A &&
      bytes[1] == 0x45 &&
      bytes[2] == 0xDF &&
      bytes[3] == 0xA3) {
    return 'video/x-matroska';
  }

  // MP4 / MOV: 'ftyp' at offset 4
  if (bytes.length >= 8 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70) {
    return 'video/mp4';
  }

  // AVI: RIFF header
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46) {
    return 'video/avi';
  }

  // MP3: ID3v2 tag
  if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
    return 'audio/mpeg';
  }

  // MP3: MPEG audio sync word
  if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
    return 'audio/mpeg';
  }

  // FLAC: 'fLaC' magic
  if (bytes[0] == 0x66 &&
      bytes[1] == 0x4C &&
      bytes[2] == 0x61 &&
      bytes[3] == 0x43) {
    return 'audio/flac';
  }

  // PDF: '%PDF'
  if (bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46) {
    return 'application/pdf';
  }

  // ZIP: PK header
  if (bytes[0] == 0x50 && bytes[1] == 0x4B) {
    return 'application/zip';
  }

  // RAR5: Rar!\x1a\x07\x01\x00
  if (bytes.length >= 8 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x61 &&
      bytes[2] == 0x72 &&
      bytes[3] == 0x21 &&
      bytes[4] == 0x1A &&
      bytes[5] == 0x07 &&
      bytes[6] == 0x01 &&
      bytes[7] == 0x00) {
    return 'application/x-rar-compressed';
  }

  // RAR4: Rar!\x1a\x07\x00
  if (bytes.length >= 7 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x61 &&
      bytes[2] == 0x72 &&
      bytes[3] == 0x21 &&
      bytes[4] == 0x1A &&
      bytes[5] == 0x07 &&
      bytes[6] == 0x00) {
    return 'application/x-rar-compressed';
  }

  return null;
}

// ---------------------------------------------------------------------------
// PostProcessor
// ---------------------------------------------------------------------------

/// Orchestrates Usenet binary post-processing: segment reassembly,
/// PAR2 verification/repair, RAR extraction, and obfuscation handling.
///
/// ```dart
/// final processor = PostProcessor(
///   yenc: YencDecoder(),
///   par2: Par2Engine(),
///   rar: RarExtractor(),
/// );
///
/// final plan = processor.analyze(nzbDocument);
/// print(plan.steps);
///
/// await for (final event in processor.process(nzbDocument, decodedSegments)) {
///   switch (event) {
///     case PostProcessFileData(:final filename, :final data):
///       sink.add(data);
///     case PostProcessComplete(:final totalFiles):
///       print('Done: $totalFiles files');
///     // ... handle other events
///   }
/// }
/// ```
class PostProcessor {
  /// Creates a [PostProcessor] with the required processing engines.
  PostProcessor({
    required this.yenc,
    required Par2Engine par2,
    required RarExtractor rar,
  })  : _par2 = par2,
        _rar = rar;

  /// The yEnc decoder available for callers that need segment-level
  /// decode access alongside the post-processor.
  final YencDecoder yenc;

  final Par2Engine _par2;
  final RarExtractor _rar;

  /// Regex for detecting obfuscated filenames (8+ hex-character base name).
  static final RegExp _obfuscatedRe = RegExp(r'^[0-9a-fA-F]{8,}\.');

  // -----------------------------------------------------------------------
  // analyze
  // -----------------------------------------------------------------------

  /// Analyzes an [NzbDocument] and returns a [PostProcessPlan] describing
  /// what processing steps are needed without performing any work.
  ///
  /// Use this to preview the pipeline before calling [process].
  PostProcessPlan analyze(NzbDocument nzb) {
    final classification = _classifyFiles(nzb);
    final par2Files = classification.par2Files;
    final rarParts = classification.rarParts;
    final contentFiles = classification.contentFiles;
    final needsRar = rarParts.isNotEmpty;
    final hasPar2 = par2Files.isNotEmpty;

    // Estimate content size from non-PAR2, non-sample file sizes.
    var estimatedSize = 0;
    for (final f in contentFiles) {
      estimatedSize += f.totalBytes;
    }

    // Detect content type from the first content file's extension.
    String? contentType;
    if (contentFiles.isNotEmpty) {
      contentType = contentFiles.first.detectedContentType;
    }

    // Build step list.
    final steps = <String>[
      'Classify ${nzb.files.length} files from NZB',
      'Reassemble segments into ${contentFiles.length} content files',
    ];
    if (hasPar2) {
      steps.add(
        'Verify file integrity using ${par2Files.length} PAR2 files',
      );
      steps.add('Repair damaged files if needed');
    }
    if (needsRar) {
      steps.add(
        'Extract content from ${rarParts.length} RAR volumes',
      );
    } else {
      steps.add(
        'Output ${contentFiles.length} files directly',
      );
    }

    return PostProcessPlan(
      contentFiles: contentFiles,
      par2Files: par2Files,
      rarParts: rarParts,
      needsRarExtraction: needsRar,
      hasPar2Recovery: hasPar2,
      detectedContentType: contentType,
      estimatedContentSize: estimatedSize,
      steps: List.unmodifiable(steps),
    );
  }

  // -----------------------------------------------------------------------
  // process
  // -----------------------------------------------------------------------

  /// Main entry point: runs the full post-processing pipeline.
  ///
  /// [nzb] is the parsed NZB document describing expected files and
  /// segments. [segments] is a stream of already-fetched and yEnc-decoded
  /// segment data.
  ///
  /// Returns a stream of [PostProcessEvent]s. The stream completes after
  /// [PostProcessComplete] is emitted, or after a fatal
  /// [PostProcessError].
  Stream<PostProcessEvent> process(
    NzbDocument nzb,
    Stream<DecodedSegment> segments,
  ) {
    final controller = StreamController<PostProcessEvent>();

    // Run the pipeline asynchronously, forwarding events and errors
    // into the controller. This keeps the public stream clean.
    _runPipeline(nzb, segments, controller).then(
      (_) {
        if (!controller.isClosed) controller.close();
      },
      onError: (Object error, StackTrace stack) {
        if (!controller.isClosed) {
          controller.add(PostProcessError(
            message: 'Unhandled pipeline error: $error',
            fatal: true,
          ));
          controller.close();
        }
      },
    );

    return controller.stream;
  }

  // -----------------------------------------------------------------------
  // Pipeline implementation
  // -----------------------------------------------------------------------

  Future<void> _runPipeline(
    NzbDocument nzb,
    Stream<DecodedSegment> segments,
    StreamController<PostProcessEvent> out,
  ) async {
    // Step 1 — Classify files.
    out.add(const PostProcessAnalyzing(
      message: 'Classifying files from NZB',
    ));
    final classification = _classifyFiles(nzb);
    final plan = analyze(nzb);

    out.add(PostProcessAnalyzing(
      message: 'Found ${plan.contentFiles.length} content files, '
          '${plan.par2Files.length} PAR2 files, '
          '${plan.rarParts.length} RAR parts',
    ));

    // Step 2 — Accumulate segments per file.
    out.add(const PostProcessAnalyzing(
      message: 'Accumulating segments',
    ));

    // Map: filename → (segmentNumber → data).
    final fileSegments = <String, Map<int, Uint8List>>{};
    // Expected segment count per filename.
    final expectedCounts = <String, int>{};
    for (final file in nzb.files) {
      expectedCounts[file.filename] = file.segments.length;
    }

    final totalFiles = classification.contentFiles.length +
        classification.par2Files.length;
    var filesComplete = 0;
    var badChecksumCount = 0;

    await for (final segment in segments) {
      if (out.isClosed) return;

      if (!segment.checksumValid) {
        badChecksumCount++;
      }

      fileSegments
          .putIfAbsent(segment.filename, () => <int, Uint8List>{})
          [segment.segmentNumber] = segment.data;

      // Check if this file is now complete.
      final expected = expectedCounts[segment.filename];
      final accumulated = fileSegments[segment.filename]!;
      if (expected != null && accumulated.length >= expected) {
        filesComplete++;
        final pct = totalFiles > 0 ? filesComplete / totalFiles : 1.0;
        out.add(PostProcessProgress(
          filesProcessed: filesComplete,
          totalFiles: totalFiles,
          currentFile: segment.filename,
          percent: pct,
        ));
      }
    }

    if (out.isClosed) return;

    if (badChecksumCount > 0) {
      out.add(PostProcessError(
        message: '$badChecksumCount segments had invalid checksums',
        fatal: false,
      ));
    }

    // Reassemble files: concatenate segments in order.
    final assembledFiles = <String, Uint8List>{};
    for (final entry in fileSegments.entries) {
      assembledFiles[entry.key] = _reassembleFile(entry.value);
    }

    // Step 3 — PAR2 verification and repair.
    if (classification.par2Files.isNotEmpty) {
      await _par2VerifyAndRepair(
        classification,
        assembledFiles,
        out,
      );
      if (out.isClosed) return;
    }

    // Step 4 — Output content.
    if (classification.rarParts.isNotEmpty) {
      await _extractRar(classification, assembledFiles, nzb, out);
    } else {
      _emitDirectFiles(classification, assembledFiles, nzb, out);
    }

    if (out.isClosed) return;

    // Step 5 — Final summary.
    var totalOutputFiles = 0;
    var totalOutputBytes = 0;
    // Count emitted files by scanning events already sent. Instead,
    // we track these from the emit helpers via a simple counter in
    // the closure. Since we can't retroactively count, we compute
    // from assembled data.
    for (final f in classification.contentFiles) {
      if (!f.isPar2 && !f.isSample && !f.isNfo) {
        final data = assembledFiles[f.filename];
        if (data != null) {
          totalOutputFiles++;
          totalOutputBytes += data.length;
        }
      }
    }

    // For RAR extraction the counts come from the extraction phase,
    // but we've already emitted individual FileComplete events there.
    // Emit a final completion event with best-effort totals.
    out.add(PostProcessComplete(
      totalFiles: totalOutputFiles,
      totalBytes: totalOutputBytes,
    ));
  }

  // -----------------------------------------------------------------------
  // Step 1: File classification
  // -----------------------------------------------------------------------

  _FileClassification _classifyFiles(NzbDocument nzb) {
    final contentFiles = <NzbFileEntry>[];
    final par2Files = <NzbFileEntry>[];
    final rarParts = <NzbFileEntry>[];
    final sampleFiles = <NzbFileEntry>[];
    final nfoFiles = <NzbFileEntry>[];

    for (final file in nzb.files) {
      if (file.isPar2) {
        par2Files.add(file);
      } else if (file.isSample) {
        sampleFiles.add(file);
      } else if (file.isNfo) {
        nfoFiles.add(file);
      } else if (file.isRar) {
        rarParts.add(file);
        contentFiles.add(file);
      } else {
        contentFiles.add(file);
      }
    }

    // Sort RAR parts by natural filename order.
    rarParts.sort();

    return _FileClassification(
      contentFiles: contentFiles,
      par2Files: par2Files,
      rarParts: rarParts,
      sampleFiles: sampleFiles,
      nfoFiles: nfoFiles,
    );
  }

  // -----------------------------------------------------------------------
  // Step 2: Segment reassembly
  // -----------------------------------------------------------------------

  /// Concatenates segment data ordered by segment number into a single
  /// [Uint8List].
  Uint8List _reassembleFile(Map<int, Uint8List> segments) {
    final sorted = segments.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    var totalLen = 0;
    for (final entry in sorted) {
      totalLen += entry.value.length;
    }

    final result = Uint8List(totalLen);
    var offset = 0;
    for (final entry in sorted) {
      result.setRange(offset, offset + entry.value.length, entry.value);
      offset += entry.value.length;
    }

    return result;
  }

  // -----------------------------------------------------------------------
  // Step 3: PAR2 verification and repair
  // -----------------------------------------------------------------------

  Future<void> _par2VerifyAndRepair(
    _FileClassification classification,
    Map<String, Uint8List> assembledFiles,
    StreamController<PostProcessEvent> out,
  ) async {
    // Parse all PAR2 files and merge into a single Par2FileInfo.
    Par2FileInfo? mergedInfo;

    for (final par2Entry in classification.par2Files) {
      final data = assembledFiles[par2Entry.filename];
      if (data == null || data.isEmpty) continue;

      try {
        final info = _par2.parse(data);
        if (mergedInfo == null) {
          mergedInfo = info;
        } else {
          mergedInfo = _mergePar2Info(mergedInfo, info);
        }
      } on FormatException catch (e) {
        out.add(PostProcessError(
          message: 'Failed to parse PAR2 file '
              '${par2Entry.filename}: ${e.message}',
          fatal: false,
        ));
      }
    }

    if (mergedInfo == null) {
      out.add(const PostProcessError(
        message: 'No valid PAR2 files could be parsed',
        fatal: false,
      ));
      return;
    }

    // Build a file data map for verification (content files only).
    final verifyData = <String, List<int>>{};
    for (final desc in mergedInfo.files) {
      // Try to find the assembled data by PAR2 filename.
      final data = _findFileData(desc.filename, assembledFiles);
      if (data != null) {
        verifyData[desc.filename] = data;
      }
    }

    // Verify.
    for (final desc in mergedInfo.files) {
      out.add(PostProcessVerifying(filename: desc.filename));
    }

    final verifyResult = _par2.verify(mergedInfo, verifyData);

    if (verifyResult.allFilesIntact) {
      out.add(const PostProcessAnalyzing(
        message: 'All files passed PAR2 verification',
      ));
      return;
    }

    // Report damage.
    for (final status in verifyResult.fileStatuses) {
      if (!status.intact) {
        out.add(PostProcessError(
          message: '${status.filename}: '
              '${status.damagedBlockIndices.length} damaged blocks, '
              '${status.missingBlockIndices.length} missing blocks',
          fatal: false,
        ));
      }
    }

    // Attempt repair if possible.
    if (!verifyResult.isRepairable) {
      out.add(PostProcessError(
        message: 'Not enough recovery data to repair '
            '(need ${verifyResult.missingBlockCount}, '
            'have ${verifyResult.availableRecoveryBlocks})',
        fatal: true,
      ));
      return;
    }

    for (final status in verifyResult.fileStatuses) {
      if (!status.intact) {
        out.add(PostProcessRepairing(
          filename: status.filename,
          missingBlocks: verifyResult.missingBlockCount,
          recoveryBlocks: verifyResult.availableRecoveryBlocks,
        ));
      }
    }

    try {
      final repairResult = await _par2.repair(
        mergedInfo,
        Map<String, List<int>>.of(verifyData),
        const <List<int>>[],
      );

      switch (repairResult) {
        case Par2RepairSuccess(:final repairedFiles):
          // Replace assembled files with repaired versions.
          for (final entry in repairedFiles.entries) {
            assembledFiles[entry.key] = entry.value;
          }
          out.add(PostProcessAnalyzing(
            message: 'Repaired ${repairedFiles.length} files',
          ));

        case Par2RepairFailure(:final reason):
          out.add(PostProcessError(
            message: 'PAR2 repair failed: $reason',
            fatal: true,
          ));
      }
    } on Exception catch (e) {
      out.add(PostProcessError(
        message: 'PAR2 repair error: $e',
        fatal: true,
      ));
    }
  }

  /// Merges two [Par2FileInfo] instances from the same recovery set,
  /// combining file descriptions and recovery slices.
  Par2FileInfo _mergePar2Info(Par2FileInfo base, Par2FileInfo other) {
    // Combine recovery slices (avoid duplicates by exponent).
    final existingExponents = <int>{};
    for (final s in base.recoverySlices) {
      existingExponents.add(s.exponent);
    }
    final mergedSlices = List<Par2RecoverySlice>.from(base.recoverySlices);
    for (final s in other.recoverySlices) {
      if (!existingExponents.contains(s.exponent)) {
        mergedSlices.add(s);
        existingExponents.add(s.exponent);
      }
    }

    // Combine file descriptions (avoid duplicates by filename).
    final existingFiles = <String>{};
    for (final f in base.files) {
      existingFiles.add(f.filename);
    }
    final mergedFiles = List<Par2FileDescription>.from(base.files);
    for (final f in other.files) {
      if (!existingFiles.contains(f.filename)) {
        mergedFiles.add(f);
        existingFiles.add(f.filename);
      }
    }

    var totalBlocks = 0;
    for (final f in mergedFiles) {
      totalBlocks += (f.fileSize + base.blockSize - 1) ~/ base.blockSize;
    }

    return Par2FileInfo(
      creator: base.creator ?? other.creator,
      recoverySetId: base.recoverySetId,
      files: mergedFiles,
      blockSize: base.blockSize,
      totalBlocks: totalBlocks,
      recoveryBlockCount: mergedSlices.length,
      recoverySlices: mergedSlices,
    );
  }

  /// Finds file data in [assembledFiles] by exact name or case-insensitive
  /// fallback, handling obfuscated filenames.
  Uint8List? _findFileData(
    String targetName,
    Map<String, Uint8List> assembledFiles,
  ) {
    // Exact match.
    if (assembledFiles.containsKey(targetName)) {
      return assembledFiles[targetName];
    }

    // Case-insensitive match.
    final lower = targetName.toLowerCase();
    for (final entry in assembledFiles.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }

    return null;
  }

  // -----------------------------------------------------------------------
  // Step 4a: RAR extraction
  // -----------------------------------------------------------------------

  Future<void> _extractRar(
    _FileClassification classification,
    Map<String, Uint8List> assembledFiles,
    NzbDocument nzb,
    StreamController<PostProcessEvent> out,
  ) async {
    out.add(const PostProcessAnalyzing(
      message: 'Preparing RAR extraction',
    ));

    // Build volume streams in sorted order.
    final volumes = <Stream<List<int>>>[];
    for (final rarEntry in classification.rarParts) {
      final data = assembledFiles[rarEntry.filename];
      if (data == null) {
        out.add(PostProcessError(
          message: 'Missing RAR volume: ${rarEntry.filename}',
          fatal: false,
        ));
        continue;
      }
      out.add(PostProcessExtracting(filename: rarEntry.filename));
      volumes.add(Stream.value(data));
    }

    if (volumes.isEmpty) {
      out.add(const PostProcessError(
        message: 'No RAR volumes available for extraction',
        fatal: true,
      ));
      return;
    }

    // Extract.
    String? currentFilename;
    var currentFileBytes = 0;
    var totalOutputFiles = 0;
    var totalOutputBytes = 0;

    try {
      final extractStream = volumes.length == 1
          ? _rar.extract(volumes.first)
          : _rar.extractMultiVolume(volumes);

      await for (final event in extractStream) {
        if (out.isClosed) return;

        switch (event) {
          case RarFileStart(:final filename):
            currentFilename = filename;
            currentFileBytes = 0;
            // Detect MIME type lazily on first data chunk.

          case RarFileData(:final data):
            String? mime;
            if (currentFileBytes == 0 && data.isNotEmpty) {
              mime = detectMimeType(data);
            }
            final emitName = _resolveFilename(
              currentFilename ?? 'unknown',
              data.isNotEmpty && currentFileBytes == 0 ? data : null,
              nzb,
            );
            out.add(PostProcessFileData(
              filename: emitName,
              data: data,
              mimeType: mime,
            ));
            currentFileBytes += data.length;

          case RarFileEnd(:final filename, :final checksumValid):
            final emitName = _resolveFilename(filename, null, nzb);
            final mime = _mimeFromExtension(emitName);
            out.add(PostProcessFileComplete(
              filename: emitName,
              totalBytes: currentFileBytes,
              mimeType: mime,
            ));
            if (!checksumValid) {
              out.add(PostProcessError(
                message: 'CRC mismatch for extracted file: $emitName',
                fatal: false,
              ));
            }
            totalOutputFiles++;
            totalOutputBytes += currentFileBytes;
            currentFilename = null;
            currentFileBytes = 0;

          case RarProgress():
            // Ignore progress events from the RAR extractor; we emit
            // our own PostProcessProgress events.
            break;

          case RarError(:final message, :final recoverable):
            out.add(PostProcessError(
              message: 'RAR extraction error: $message',
              fatal: !recoverable,
            ));
            if (!recoverable) return;

          case RarPasswordRequired():
            out.add(const PostProcessError(
              message: 'RAR archive is password-protected',
              fatal: true,
            ));
            return;
        }
      }
    } on Exception catch (e) {
      out.add(PostProcessError(
        message: 'RAR extraction failed: $e',
        fatal: true,
      ));
      return;
    }

    // Override the completion summary with RAR-extracted totals.
    if (!out.isClosed) {
      out.add(PostProcessComplete(
        totalFiles: totalOutputFiles,
        totalBytes: totalOutputBytes,
      ));
    }
  }

  // -----------------------------------------------------------------------
  // Step 4b: Direct file passthrough
  // -----------------------------------------------------------------------

  void _emitDirectFiles(
    _FileClassification classification,
    Map<String, Uint8List> assembledFiles,
    NzbDocument nzb,
    StreamController<PostProcessEvent> out,
  ) {
    for (final file in classification.contentFiles) {
      if (out.isClosed) return;

      final data = assembledFiles[file.filename];
      if (data == null) {
        out.add(PostProcessError(
          message: 'Missing data for file: ${file.filename}',
          fatal: false,
        ));
        continue;
      }

      final resolvedName = _resolveFilename(file.filename, data, nzb);
      final mime = detectMimeType(data) ?? _mimeFromExtension(resolvedName);

      out.add(PostProcessFileData(
        filename: resolvedName,
        data: data,
        mimeType: mime,
      ));

      out.add(PostProcessFileComplete(
        filename: resolvedName,
        totalBytes: data.length,
        mimeType: mime,
      ));
    }
  }

  // -----------------------------------------------------------------------
  // Step 5: Obfuscation handling
  // -----------------------------------------------------------------------

  /// Resolves a potentially obfuscated filename using NZB metadata and
  /// magic byte detection.
  ///
  /// If [filename] looks obfuscated (hex-hash base name), attempts to
  /// derive a meaningful name from the NZB title and file magic bytes.
  String _resolveFilename(
    String filename,
    Uint8List? data,
    NzbDocument nzb,
  ) {
    if (!_obfuscatedRe.hasMatch(filename)) return filename;

    // Try to derive a name from the NZB title.
    final baseName = nzb.title ?? 'content';
    final sanitized = baseName.replaceAll(RegExp(r'[^\w\s\-.]'), '').trim();

    // Detect extension from magic bytes.
    if (data != null && data.length >= 8) {
      final mime = detectMimeType(data);
      final ext = _extensionFromMime(mime);
      if (ext != null) {
        return '$sanitized$ext';
      }
    }

    // Fall back to the original extension if present.
    final dot = filename.lastIndexOf('.');
    if (dot != -1 && dot < filename.length - 1) {
      return '$sanitized${filename.substring(dot)}';
    }

    return sanitized.isEmpty ? filename : sanitized;
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  /// Maps a MIME type to a file extension (with leading dot).
  static String? _extensionFromMime(String? mime) => switch (mime) {
        'video/x-matroska' => '.mkv',
        'video/mp4' => '.mp4',
        'video/avi' => '.avi',
        'audio/mpeg' => '.mp3',
        'audio/flac' => '.flac',
        'application/pdf' => '.pdf',
        'application/zip' => '.zip',
        'application/x-rar-compressed' => '.rar',
        _ => null,
      };

  /// Common extension → MIME type lookup.
  static String? _mimeFromExtension(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot == -1 || dot == filename.length - 1) return null;
    return switch (filename.substring(dot + 1).toLowerCase()) {
      'mkv' => 'video/x-matroska',
      'mp4' || 'm4v' => 'video/mp4',
      'avi' => 'video/avi',
      'wmv' => 'video/x-ms-wmv',
      'mp3' => 'audio/mpeg',
      'flac' => 'audio/flac',
      'pdf' => 'application/pdf',
      'zip' => 'application/zip',
      'rar' => 'application/x-rar-compressed',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'srt' => 'application/x-subrip',
      'nfo' => 'text/x-nfo',
      'txt' => 'text/plain',
      _ => null,
    };
  }
}

// ---------------------------------------------------------------------------
// Internal classification result
// ---------------------------------------------------------------------------

/// Groups NZB files by their role in the post-processing pipeline.
@immutable
class _FileClassification {
  const _FileClassification({
    required this.contentFiles,
    required this.par2Files,
    required this.rarParts,
    required this.sampleFiles,
    required this.nfoFiles,
  });

  final List<NzbFileEntry> contentFiles;
  final List<NzbFileEntry> par2Files;
  final List<NzbFileEntry> rarParts;
  final List<NzbFileEntry> sampleFiles;
  final List<NzbFileEntry> nfoFiles;
}
