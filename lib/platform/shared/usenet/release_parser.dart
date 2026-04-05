/// Parses Usenet/scene release names to extract quality metadata.
///
/// Supports standard scene naming conventions:
/// `Show.Name.S01E02.1080p.BluRay.x264-GROUP`
/// `Movie.2024.2160p.UHD.BluRay.HDR.DV.DTS-HD.MA.7.1-GROUP`
library;

import 'package:meta/meta.dart';

/// Parsed quality information from a release name.
@immutable
class ReleaseQuality {
  /// Creates a [ReleaseQuality] with the given field values.
  const ReleaseQuality({
    this.resolution,
    this.source,
    this.codec,
    this.hdr,
    this.audio,
    this.language,
    this.subtitles,
    this.group,
    this.isProper = false,
    this.isRepack = false,
  });

  /// Video resolution (e.g., '2160p', '1080p', '720p', '480p').
  final String? resolution;

  /// Source (e.g., 'BluRay', 'WEB-DL', 'WEBRip', 'HDTV', 'Remux').
  final String? source;

  /// Video codec (e.g., 'x264', 'x265', 'HEVC', 'AV1').
  final String? codec;

  /// HDR type (e.g., 'HDR', 'HDR10', 'HDR10+', 'DV' for Dolby Vision).
  final String? hdr;

  /// Audio format (e.g., 'DTS-HD MA 7.1', 'Atmos', 'AAC', 'FLAC').
  final String? audio;

  /// Primary language (e.g., 'English', 'Multi', 'German').
  final String? language;

  /// Subtitle info (e.g., 'English', 'Multi').
  final String? subtitles;

  /// Release group name.
  final String? group;

  /// Whether this is a PROPER release (fixes issues in original).
  final bool isProper;

  /// Whether this is a REPACK (re-release).
  final bool isRepack;

  /// Quality score for ranking (higher = better).
  int get score {
    var s = 0;
    // Resolution
    switch (resolution) {
      case '2160p':
        s += 400;
      case '1080p':
        s += 300;
      case '720p':
        s += 200;
      case '480p':
        s += 100;
      default:
        s += 50;
    }
    // Source
    switch (source?.toLowerCase()) {
      case 'remux':
        s += 50;
      case 'bluray':
        s += 40;
      case 'web-dl':
        s += 35;
      case 'webrip':
        s += 30;
      case 'hdtv':
        s += 20;
      case 'dvdrip':
        s += 10;
      default:
        break;
    }
    // HDR bonus
    if (hdr != null) s += 25;
    // Codec preference (HEVC/x265 = smaller + same quality)
    if (codec?.toLowerCase() == 'x265' || codec?.toLowerCase() == 'hevc') {
      s += 15;
    }
    if (codec?.toLowerCase() == 'av1') s += 20;
    // PROPER/REPACK bonus
    if (isProper) s += 10;
    if (isRepack) s += 5;
    return s;
  }

  /// Human-readable label like "1080p · BluRay · x265 · HDR".
  String get label {
    final parts = <String>[];
    if (resolution != null) parts.add(resolution!);
    if (source != null) parts.add(source!);
    if (codec != null) parts.add(codec!);
    if (hdr != null) parts.add(hdr!);
    if (audio != null) parts.add(audio!);
    return parts.isEmpty ? 'Unknown' : parts.join(' · ');
  }

  @override
  String toString() => 'ReleaseQuality($label, score=$score)';
}

/// Parses scene release names into structured quality metadata.
class ReleaseParser {
  /// Creates a [ReleaseParser].
  const ReleaseParser();

  /// Parse a release name and extract quality info.
  ReleaseQuality parse(String releaseName) {
    final name = releaseName.replaceAll('.', ' ').replaceAll('_', ' ');

    return ReleaseQuality(
      resolution: _matchResolution(name),
      source: _matchSource(name),
      codec: _matchCodec(name),
      hdr: _matchHdr(name),
      audio: _matchAudio(name),
      language: _matchLanguage(name),
      subtitles: _matchSubtitles(name),
      group: _matchGroup(releaseName),
      isProper: RegExp(r'\bPROPER\b', caseSensitive: false).hasMatch(name),
      isRepack: RegExp(r'\bREPACK\b', caseSensitive: false).hasMatch(name),
    );
  }

  String? _matchResolution(String name) {
    final m = RegExp(
      r'\b(2160p|1080p|720p|480p|4K|UHD)\b',
      caseSensitive: false,
    ).firstMatch(name);
    if (m == null) return null;
    final val = m.group(1)!;
    if (val.toUpperCase() == '4K' || val.toUpperCase() == 'UHD') return '2160p';
    return val.toLowerCase().replaceFirstMapped(
      RegExp(r'^(\d)'),
      (m) => m.group(1)!,
    );
  }

  String? _matchSource(String name) {
    final patterns = {
      r'\bRemux\b': 'Remux',
      r'\bBlu[- ]?Ray\b': 'BluRay',
      r'\bWEB[- ]?DL\b': 'WEB-DL',
      r'\bWEB[- ]?Rip\b': 'WEBRip',
      r'\bWEB\b': 'WEB-DL',
      r'\bHDTV\b': 'HDTV',
      r'\bDVDRip\b': 'DVDRip',
      r'\bBDRip\b': 'BDRip',
      r'\bBRRip\b': 'BRRip',
    };
    for (final entry in patterns.entries) {
      if (RegExp(entry.key, caseSensitive: false).hasMatch(name)) {
        return entry.value;
      }
    }
    return null;
  }

  String? _matchCodec(String name) {
    final patterns = {
      r'\bx265\b': 'x265',
      r'\bHEVC\b': 'HEVC',
      r'\bH\.?265\b': 'x265',
      r'\bx264\b': 'x264',
      r'\bH\.?264\b': 'x264',
      r'\bAVC\b': 'x264',
      r'\bAV1\b': 'AV1',
      r'\bXviD\b': 'XviD',
      r'\bDivX\b': 'DivX',
      r'\bVP9\b': 'VP9',
    };
    for (final entry in patterns.entries) {
      if (RegExp(entry.key, caseSensitive: false).hasMatch(name)) {
        return entry.value;
      }
    }
    return null;
  }

  String? _matchHdr(String name) {
    final patterns = {
      r'\bDolby ?Vision\b|\bDV\b': 'DV',
      r'\bHDR10\+\b|\bHDR10Plus\b': 'HDR10+',
      r'\bHDR10\b': 'HDR10',
      r'\bHDR\b': 'HDR',
      r'\bHLG\b': 'HLG',
      r'\bSDR\b': 'SDR',
    };
    for (final entry in patterns.entries) {
      if (RegExp(entry.key, caseSensitive: false).hasMatch(name)) {
        return entry.value;
      }
    }
    return null;
  }

  String? _matchAudio(String name) {
    final patterns = {
      r'\bAtmos\b': 'Atmos',
      r'\bDTS[- ]?HD[. ]?MA[. ]?7[. ]1\b': 'DTS-HD MA 7.1',
      r'\bDTS[- ]?HD[. ]?MA[. ]?5[. ]1\b': 'DTS-HD MA 5.1',
      r'\bDTS[- ]?HD[. ]?MA\b': 'DTS-HD MA',
      r'\bDTS[- ]?X\b': 'DTS:X',
      r'\bDTS\b': 'DTS',
      r'\bTrueHD\b': 'TrueHD',
      r'\bDD\+?\s?5[. ]1\b|\bDDP?\s?5[. ]1\b': 'DD+ 5.1',
      r'\bDDP?\b|\bDD\+\b': 'DD+',
      r'\bEAC3\b': 'EAC3',
      r'\bAAC\b': 'AAC',
      r'\bFLAC\b': 'FLAC',
      r'\bMP3\b': 'MP3',
    };
    for (final entry in patterns.entries) {
      if (RegExp(entry.key, caseSensitive: false).hasMatch(name)) {
        return entry.value;
      }
    }
    return null;
  }

  String? _matchLanguage(String name) {
    if (RegExp(r'\bMULTi\b', caseSensitive: false).hasMatch(name)) {
      return 'Multi';
    }
    if (RegExp(r'\bDual[. ]?Audio\b', caseSensitive: false).hasMatch(name)) {
      return 'Dual Audio';
    }
    if (RegExp(r'\bGerman\b|\bDeutsch\b', caseSensitive: false)
        .hasMatch(name)) {
      return 'German';
    }
    if (RegExp(r'\bFrench\b', caseSensitive: false).hasMatch(name)) {
      return 'French';
    }
    if (RegExp(r'\bSpanish\b', caseSensitive: false).hasMatch(name)) {
      return 'Spanish';
    }
    if (RegExp(r'\bJapanese\b', caseSensitive: false).hasMatch(name)) {
      return 'Japanese';
    }
    if (RegExp(r'\bKorean\b', caseSensitive: false).hasMatch(name)) {
      return 'Korean';
    }
    if (RegExp(r'\bChinese\b', caseSensitive: false).hasMatch(name)) {
      return 'Chinese';
    }
    return null; // Assume English if not specified
  }

  String? _matchSubtitles(String name) {
    if (RegExp(r'\bMulti[. ]?Subs?\b', caseSensitive: false).hasMatch(name)) {
      return 'Multi';
    }
    if (RegExp(r'\bSubs?\b', caseSensitive: false).hasMatch(name)) {
      return 'English';
    }
    return null;
  }

  String? _matchGroup(String releaseName) {
    final m = RegExp(r'-([A-Za-z0-9]+)(?:\[.*\])?$').firstMatch(releaseName);
    return m?.group(1);
  }
}
