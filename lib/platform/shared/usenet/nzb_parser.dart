/// NZB XML parser for Usenet binary posts.
///
/// Parses NZB files (XML format) that describe multi-part binary posts on
/// Usenet. Produces an [NzbDocument] containing metadata, file entries, and
/// segment information needed to reassemble downloads.
///
/// See: https://sabnzbd.org/wiki/extra/nzb-spec
library;

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

// ---------------------------------------------------------------------------
// NzbSegment
// ---------------------------------------------------------------------------

/// A single NNTP article segment within an [NzbFileEntry].
@immutable
class NzbSegment implements Comparable<NzbSegment> {
  /// Creates an [NzbSegment].
  const NzbSegment({
    required this.number,
    required this.messageId,
    required this.bytes,
  });

  /// 1-based segment number indicating download order.
  final int number;

  /// Article message-ID (without angle brackets).
  final String messageId;

  /// Size of this segment in bytes.
  final int bytes;

  @override
  int compareTo(NzbSegment other) => number.compareTo(other.number);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NzbSegment &&
          number == other.number &&
          messageId == other.messageId &&
          bytes == other.bytes;

  @override
  int get hashCode => Object.hash(number, messageId, bytes);

  @override
  String toString() => 'NzbSegment(#$number, $bytes B, $messageId)';
}

// ---------------------------------------------------------------------------
// NzbFileEntry
// ---------------------------------------------------------------------------

/// Regex for extracting a quoted filename from a Usenet subject line.
///
/// Matches the last `"filename.ext"` occurrence in the subject.
final RegExp _quotedFilenameRe = RegExp(r'"([^"]+\.[a-zA-Z0-9]+)"');

/// Regex for yEnc-style `name=filename` in subject lines.
final RegExp _yencNameRe = RegExp(r'name=(\S+)');

/// Regex for filenames with common Usenet extensions anywhere in the subject.
final RegExp _extensionRe = RegExp(
  r'(\S+\.(?:mkv|avi|mp4|rar|r\d{2}|par2|nfo|srt|nzb|zip|7z|flac|mp3|wmv|iso|img))',
  caseSensitive: false,
);

/// Regex for `(part/total)` patterns common in multi-part posts.
final RegExp _partTotalRe = RegExp(r'\((\d+)/(\d+)\)');

/// Regex for `hex$hex` obfuscation patterns (e.g. `a1b2c3$d4e5f6@domain`).
final RegExp _hexDollarHexRe = RegExp(
  r'[a-f0-9]{8,}\$[a-f0-9]{8,}',
  caseSensitive: false,
);

/// Regex for detecting obfuscated (hex-hash) filenames.
///
/// Matches a filename whose base name is 8+ hex characters.
final RegExp _obfuscatedRe = RegExp(r'^[0-9a-fA-F]{8,}\.');

/// Regex for PAR2 recovery files (`.par2` or `.vol*+*.par2`).
final RegExp _par2Re = RegExp(r'\.(vol\d+[\+\-]\d+\.)?par2$', caseSensitive: false);

/// Regex for RAR archive parts.
///
/// Matches `.rar`, `.r00`–`.r99`, `.s00`–`.s99`, and `.partNN.rar`.
final RegExp _rarRe = RegExp(
  r'\.(rar|r\d{2}|s\d{2}|part\d+\.rar)$',
  caseSensitive: false,
);

/// Regex for NFO info files.
final RegExp _nfoRe = RegExp(r'\.nfo$', caseSensitive: false);

/// Common file-extension → MIME type mappings for Usenet content.
const Map<String, String> _mimeTypes = {
  'rar': 'application/x-rar-compressed',
  'zip': 'application/zip',
  '7z': 'application/x-7z-compressed',
  'par2': 'application/x-par2',
  'nfo': 'text/x-nfo',
  'nzb': 'application/x-nzb',
  'sfv': 'text/x-sfv',
  'mkv': 'video/x-matroska',
  'avi': 'video/x-msvideo',
  'mp4': 'video/mp4',
  'wmv': 'video/x-ms-wmv',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'txt': 'text/plain',
  'srt': 'application/x-subrip',
  'sub': 'text/x-sub',
  'idx': 'application/x-idx',
  'mp3': 'audio/mpeg',
  'flac': 'audio/flac',
};

/// A single file entry inside an NZB document.
///
/// Each entry corresponds to a `<file>` element and contains the subject
/// line, poster, newsgroups, and an ordered list of [NzbSegment]s.
@immutable
class NzbFileEntry implements Comparable<NzbFileEntry> {
  /// Creates an [NzbFileEntry].
  const NzbFileEntry({
    required this.subject,
    this.poster,
    this.date,
    this.groups = const [],
    this.segments = const [],
  });

  /// Subject line of the Usenet post.
  final String subject;

  /// Poster email / identifier, if present.
  final String? poster;

  /// Unix timestamp of the post, if present.
  final int? date;

  /// Newsgroups this file was posted to.
  final List<String> groups;

  /// Ordered list of article segments comprising this file.
  final List<NzbSegment> segments;

  // -- Derived properties ---------------------------------------------------

  /// Filename extracted from [subject].
  ///
  /// Uses a multi-step extraction strategy to produce a human-readable name
  /// even when Usenet posts are obfuscated:
  ///
  /// 1. Quoted filename: `"movie.part01.rar"`
  /// 2. yEnc-style: `name=movie.mkv`
  /// 3. Known extension anywhere in the subject
  /// 4. Cleaned subject when a `(part/total)` pattern is present
  /// 5. Heuristic cleanup of hex-obfuscated subjects
  /// 6. Generated name from segment info and size heuristics
  String get filename {
    // 1. Try quoted filename: "movie.part01.rar"
    final quotedMatch = _quotedFilenameRe.firstMatch(subject);
    if (quotedMatch != null) return quotedMatch.group(1)!;

    // 2. Try yEnc-style: name=movie.mkv
    final yencMatch = _yencNameRe.firstMatch(subject);
    if (yencMatch != null) return yencMatch.group(1)!;

    // 3. Try filename with a known extension anywhere in the subject.
    final extMatch = _extensionRe.firstMatch(subject);
    if (extMatch != null) return extMatch.group(1)!;

    // 4. Try (part/total) pattern and clean up surrounding noise.
    final partMatch = _partTotalRe.firstMatch(subject);
    if (partMatch != null) {
      final cleaned = subject
          .replaceAll(RegExp(r'<[^>]+>'), '') // remove <message-ids>
          .replaceAll(
            RegExp(r'[a-f0-9]{32,}', caseSensitive: false),
            '',
          ) // remove long hex strings
          .replaceAll(RegExp(r'\$'), '') // remove $ separators
          .replaceAll(RegExp(r'\s+'), ' ') // normalize whitespace
          .trim();
      if (cleaned.length > 3) return cleaned;
    }

    // 5. Try to clean up an obfuscated subject (hex$hex@domain patterns).
    final cleaned = subject
        .replaceAll(_hexDollarHexRe, '') // hex$hex patterns
        .replaceAll(RegExp(r'@[\w.]+'), '') // @domain parts
        .replaceAll(RegExp(r'[<>]'), '') // angle brackets
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.length > 3) return cleaned;

    // 6. Final fallback: generate a name from segment info.
    final ext = _guessExtensionFromSize();
    return 'File ${segments.isNotEmpty ? segments.first.number : 0}$ext';
  }

  /// Guesses a file extension from [totalBytes] using size heuristics.
  String _guessExtensionFromSize() {
    final total = totalBytes;
    if (total > 100 * 1024 * 1024) return '.mkv'; // >100 MB → likely video
    if (total > 10 * 1024 * 1024) return '.rar'; // >10 MB → likely archive
    if (total < 100 * 1024) return '.nfo'; // <100 KB → likely NFO
    return '';
  }

  /// Total size in bytes (sum of all segment sizes).
  int get totalBytes {
    var sum = 0;
    for (final s in segments) {
      sum += s.bytes;
    }
    return sum;
  }

  /// Whether the filename appears obfuscated (hex-hash base name).
  bool get isObfuscated => _obfuscatedRe.hasMatch(filename);

  /// Whether this is a PAR2 recovery file.
  bool get isPar2 => _par2Re.hasMatch(filename);

  /// Whether this is a RAR archive part.
  bool get isRar => _rarRe.hasMatch(filename);

  /// Whether this is an NFO info file.
  bool get isNfo => _nfoRe.hasMatch(filename);

  /// Whether the filename contains "sample" (case-insensitive).
  bool get isSample => filename.toLowerCase().contains('sample');

  /// Best-guess MIME type based on the filename extension, or `null`.
  String? get detectedContentType {
    final dot = filename.lastIndexOf('.');
    if (dot == -1 || dot == filename.length - 1) return null;
    final ext = filename.substring(dot + 1).toLowerCase();
    return _mimeTypes[ext];
  }

  // -- Natural sort ---------------------------------------------------------

  /// Comparison key used for natural (numeric-aware) sorting.
  static List<Object> _naturalSortKey(String s) {
    final parts = <Object>[];
    final re = RegExp(r'(\d+)|(\D+)');
    for (final m in re.allMatches(s.toLowerCase())) {
      if (m.group(1) != null) {
        parts.add(int.parse(m.group(1)!));
      } else {
        parts.add(m.group(2)!);
      }
    }
    return parts;
  }

  @override
  int compareTo(NzbFileEntry other) {
    final a = _naturalSortKey(filename);
    final b = _naturalSortKey(other.filename);
    for (var i = 0; i < a.length && i < b.length; i++) {
      final av = a[i];
      final bv = b[i];
      if (av is int && bv is int) {
        final c = av.compareTo(bv);
        if (c != 0) return c;
      } else if (av is String && bv is String) {
        final c = av.compareTo(bv);
        if (c != 0) return c;
      } else {
        // int before string
        return av is int ? -1 : 1;
      }
    }
    return a.length.compareTo(b.length);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NzbFileEntry &&
          subject == other.subject &&
          poster == other.poster &&
          date == other.date;

  @override
  int get hashCode => Object.hash(subject, poster, date);

  @override
  String toString() =>
      'NzbFileEntry($filename, ${segments.length} segments, $totalBytes B)';
}

// ---------------------------------------------------------------------------
// NzbDocument
// ---------------------------------------------------------------------------

/// A parsed NZB document containing metadata and file entries.
///
/// Provides convenience getters for filtering files by type (RAR, PAR2, etc.)
/// and computing aggregate statistics.
@immutable
class NzbDocument {
  /// Creates an [NzbDocument].
  const NzbDocument({
    this.title,
    this.category,
    this.metadata = const {},
    this.files = const [],
  });

  /// Title from `<meta type="title">`, if present.
  final String? title;

  /// Category from `<meta type="category">`, if present.
  final String? category;

  /// All `<meta>` key/value pairs from the `<head>` section.
  final Map<String, String> metadata;

  /// Parsed file entries, sorted by filename (natural order).
  final List<NzbFileEntry> files;

  // -- Aggregate statistics -------------------------------------------------

  /// Total size in bytes across every segment in every file.
  int get totalBytes {
    var sum = 0;
    for (final f in files) {
      sum += f.totalBytes;
    }
    return sum;
  }

  /// Total number of segments across all files.
  int get totalSegments {
    var sum = 0;
    for (final f in files) {
      sum += f.segments.length;
    }
    return sum;
  }

  // -- File type filters ----------------------------------------------------

  /// Files that are **not** PAR2 recovery files.
  List<NzbFileEntry> get contentFiles =>
      files.where((f) => !f.isPar2).toList(growable: false);

  /// Only PAR2 recovery files.
  List<NzbFileEntry> get par2Files =>
      files.where((f) => f.isPar2).toList(growable: false);

  /// Only RAR archive parts.
  List<NzbFileEntry> get rarFiles =>
      files.where((f) => f.isRar).toList(growable: false);

  /// Whether any file is a RAR archive part.
  bool get hasRar => files.any((f) => f.isRar);

  /// Whether any PAR2 recovery files are present.
  bool get hasPar2 => files.any((f) => f.isPar2);

  @override
  String toString() =>
      'NzbDocument(${title ?? 'untitled'}, ${files.length} files, '
      '$totalSegments segments, $totalBytes B)';
}

// ---------------------------------------------------------------------------
// NzbParser
// ---------------------------------------------------------------------------

/// NZB namespace URI used in well-formed NZB files.
const String _nzbNamespace = 'http://www.newzbin.com/DTD/2003/nzb';

/// Parses NZB XML documents into [NzbDocument] instances.
///
/// Handles both namespace-qualified and unqualified NZB elements, various
/// character encodings, and gracefully degrades when optional fields are
/// missing.
///
/// ```dart
/// final parser = NzbParser();
/// final doc = parser.parse(xmlString);
/// print(doc.title);
/// print(doc.files.length);
/// ```
class NzbParser {
  /// Creates an [NzbParser].
  const NzbParser();

  /// Parses an NZB XML string into an [NzbDocument].
  ///
  /// Throws [FormatException] if the XML is malformed or does not contain
  /// a recognisable `<nzb>` root element.
  NzbDocument parse(String xmlContent) {
    final XmlDocument xmlDoc;
    try {
      xmlDoc = XmlDocument.parse(xmlContent);
    } on XmlException catch (e) {
      throw FormatException('Invalid NZB XML: ${e.message}');
    }

    final root = xmlDoc.rootElement;
    if (root.localName != 'nzb') {
      throw FormatException(
        'Expected <nzb> root element, found <${root.localName}>',
      );
    }

    return _parseNzbRoot(root);
  }

  /// Parses NZB content from raw bytes, handling character encoding.
  ///
  /// Attempts UTF-8 first; falls back to Latin-1 (ISO 8859-1) which is
  /// common in older NZB files. Throws [FormatException] on invalid content.
  NzbDocument parseBytes(List<int> bytes) {
    String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      // Fall back to Latin-1 (ISO 8859-1), common in legacy NZB files.
      content = latin1.decode(bytes);
    }
    return parse(content);
  }

  // -- Internal parsing -----------------------------------------------------

  /// Resolves an element by [localName] in either the NZB namespace or no
  /// namespace (for lenient parsing of non-conforming files).
  Iterable<XmlElement> _findElements(XmlElement parent, String localName) {
    final namespaced = parent.findElements(localName, namespace: _nzbNamespace);
    if (namespaced.isNotEmpty) return namespaced;
    return parent.findElements(localName);
  }

  /// Parses the `<nzb>` root element.
  NzbDocument _parseNzbRoot(XmlElement root) {
    final metadata = <String, String>{};
    String? title;
    String? category;

    // Parse <head><meta type="...">...</meta></head>
    for (final head in _findElements(root, 'head')) {
      for (final meta in _findElements(head, 'meta')) {
        final type = meta.getAttribute('type');
        final value = meta.innerText.trim();
        if (type != null && value.isNotEmpty) {
          metadata[type] = value;
          if (type == 'title') title = value;
          if (type == 'category') category = value;
        }
      }
    }

    // Parse <file> entries.
    final files = <NzbFileEntry>[];
    for (final fileEl in _findElements(root, 'file')) {
      files.add(_parseFile(fileEl));
    }

    // Sort files by filename using natural sort order.
    files.sort();

    return NzbDocument(
      title: title,
      category: category,
      metadata: Map.unmodifiable(metadata),
      files: List.unmodifiable(files),
    );
  }

  /// Parses a single `<file>` element.
  NzbFileEntry _parseFile(XmlElement el) {
    final subject = el.getAttribute('subject') ?? '';
    final poster = el.getAttribute('poster');
    final dateStr = el.getAttribute('date');
    final date = dateStr != null ? int.tryParse(dateStr) : null;

    // Collect <group> text nodes.
    final groups = <String>[];
    for (final groupsEl in _findElements(el, 'groups')) {
      for (final groupEl in _findElements(groupsEl, 'group')) {
        final name = groupEl.innerText.trim();
        if (name.isNotEmpty) groups.add(name);
      }
    }

    // Collect and sort <segment> entries.
    final segments = <NzbSegment>[];
    for (final segsEl in _findElements(el, 'segments')) {
      for (final segEl in _findElements(segsEl, 'segment')) {
        final segment = _parseSegment(segEl);
        if (segment != null) segments.add(segment);
      }
    }
    segments.sort();

    return NzbFileEntry(
      subject: subject,
      poster: poster,
      date: date,
      groups: List.unmodifiable(groups),
      segments: List.unmodifiable(segments),
    );
  }

  /// Parses a single `<segment>` element, returning `null` on malformed data.
  NzbSegment? _parseSegment(XmlElement el) {
    final numberStr = el.getAttribute('number');
    final bytesStr = el.getAttribute('bytes');
    final messageId = el.innerText.trim();

    if (numberStr == null || messageId.isEmpty) return null;

    final number = int.tryParse(numberStr);
    final bytes = int.tryParse(bytesStr ?? '0') ?? 0;

    if (number == null) return null;

    return NzbSegment(
      number: number,
      messageId: messageId,
      bytes: bytes,
    );
  }
}
