/// Streaming quality preferences for the Kabuk knowledge store.
///
/// Stores user's default quality preferences for automatic NZB selection.
/// The [UsenetResolver] uses these to rank and filter search results.
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Preferred video resolution for streaming.
enum PreferredResolution {
  /// 4K Ultra HD (2160p).
  uhd4k('2160p'),

  /// Full HD (1080p) — default.
  fullHd('1080p'),

  /// HD (720p).
  hd('720p'),

  /// SD (480p).
  sd('480p'),

  /// Accept any resolution — pick the best available.
  any('any');

  const PreferredResolution(this.label);

  /// Display label (e.g., '1080p').
  final String label;

  /// Parses from stored string, defaulting to [fullHd].
  static PreferredResolution fromString(String? value) => switch (value) {
        '2160p' => uhd4k,
        '1080p' => fullHd,
        '720p' => hd,
        '480p' => sd,
        'any' => any,
        _ => fullHd,
      };
}

/// HDR preference level.
enum HdrPreference {
  /// Only pick HDR content.
  required('required'),

  /// Prefer HDR but accept SDR.
  preferred('preferred'),

  /// No preference — accept anything.
  any('any'),

  /// Prefer SDR (avoid HDR).
  none('none');

  const HdrPreference(this.label);
  final String label;

  static HdrPreference fromString(String? value) => switch (value) {
        'required' => required,
        'preferred' => preferred,
        'none' => none,
        _ => any,
      };
}

// ---------------------------------------------------------------------------
// StreamingPrefs
// ---------------------------------------------------------------------------

/// Immutable user preferences for automatic Usenet source selection.
///
/// Stored as a `kabuk:StreamingPrefs` entity in the knowledge store.
/// A singleton entity — only one instance per profile.
@immutable
class StreamingPrefs {
  /// Creates [StreamingPrefs] with the given field values.
  const StreamingPrefs({
    this.uri = '',
    this.resolution = PreferredResolution.fullHd,
    this.codec = 'any',
    this.source = 'any',
    this.audio = 'any',
    this.language = 'English',
    this.hdr = HdrPreference.any,
    this.maxFileSizeMb = 0,
    this.maxRetries = 5,
  });

  /// Default preferences with sensible values.
  static const defaults = StreamingPrefs();

  /// Knowledge store entity URI.
  final String uri;

  /// Preferred video resolution.
  final PreferredResolution resolution;

  /// Preferred video codec ('x265', 'x264', 'AV1', 'any').
  final String codec;

  /// Preferred release source ('BluRay', 'WEB-DL', 'any').
  final String source;

  /// Preferred audio format ('Atmos', 'DTS-HD MA', 'any').
  final String audio;

  /// Preferred content language ('English', 'Multi', 'German', etc.).
  final String language;

  /// HDR preference level.
  final HdrPreference hdr;

  /// Maximum file size in MB (0 = no limit).
  final int maxFileSizeMb;

  /// Maximum NZB sources to try before giving up.
  final int maxRetries;

  /// Creates a copy with updated fields.
  StreamingPrefs copyWith({
    String? uri,
    PreferredResolution? resolution,
    String? codec,
    String? source,
    String? audio,
    String? language,
    HdrPreference? hdr,
    int? maxFileSizeMb,
    int? maxRetries,
  }) =>
      StreamingPrefs(
        uri: uri ?? this.uri,
        resolution: resolution ?? this.resolution,
        codec: codec ?? this.codec,
        source: source ?? this.source,
        audio: audio ?? this.audio,
        language: language ?? this.language,
        hdr: hdr ?? this.hdr,
        maxFileSizeMb: maxFileSizeMb ?? this.maxFileSizeMb,
        maxRetries: maxRetries ?? this.maxRetries,
      );

  /// Reconstructs from RDF triples.
  factory StreamingPrefs.fromTriples(String uri, List<Triple> triples) {
    String? _val(String predicate) {
      for (final t in triples) {
        if (t.predicate == predicate) return t.objectValue;
      }
      return null;
    }

    return StreamingPrefs(
      uri: uri,
      resolution: PreferredResolution.fromString(_val(NS.kabukPreferredResolution)),
      codec: _val(NS.kabukPreferredCodec) ?? 'any',
      source: _val(NS.kabukPreferredSource) ?? 'any',
      audio: _val(NS.kabukPreferredAudio) ?? 'any',
      language: _val(NS.kabukPreferredLanguage) ?? 'English',
      hdr: HdrPreference.fromString(_val(NS.kabukHdrPreference)),
      maxFileSizeMb: int.tryParse(_val(NS.kabukMaxFileSizeMb) ?? '') ?? 0,
      maxRetries: int.tryParse(_val(NS.kabukMaxRetries) ?? '') ?? 5,
    );
  }

  @override
  String toString() =>
      'StreamingPrefs(${resolution.label}, codec=$codec, lang=$language, '
      'hdr=${hdr.label}, maxSize=${maxFileSizeMb}MB)';
}

// ---------------------------------------------------------------------------
// KnowledgeStore extension
// ---------------------------------------------------------------------------

/// Extension methods for reading/writing [StreamingPrefs] in the knowledge
/// store. Only one instance exists per profile.
extension KnowledgeStoreStreamingPrefsExtension on KnowledgeStore {
  static const _singletonUri = 'kabuk:StreamingPrefs/default';

  /// Retrieves the user's streaming preferences, or [StreamingPrefs.defaults]
  /// if none have been saved yet.
  Future<StreamingPrefs> getStreamingPrefs() async {
    final triples = await getEntity(_singletonUri);
    if (triples.isEmpty) return StreamingPrefs.defaults;
    return StreamingPrefs.fromTriples(_singletonUri, triples);
  }

  /// Saves the user's streaming preferences (upsert).
  Future<void> saveStreamingPrefs(StreamingPrefs prefs) {
    return mutate((ctx) async {
      const uri = _singletonUri;
      await ctx.set(uri, NS.rdfType, NS.kabukStreamingPrefs,
          objectType: ObjectType.uri);
      await ctx.set(
          uri, NS.kabukPreferredResolution, prefs.resolution.label);
      await ctx.set(uri, NS.kabukPreferredCodec, prefs.codec);
      await ctx.set(uri, NS.kabukPreferredSource, prefs.source);
      await ctx.set(uri, NS.kabukPreferredAudio, prefs.audio);
      await ctx.set(uri, NS.kabukPreferredLanguage, prefs.language);
      await ctx.set(uri, NS.kabukHdrPreference, prefs.hdr.label);
      await ctx.set(
          uri, NS.kabukMaxFileSizeMb, prefs.maxFileSizeMb.toString());
      await ctx.set(uri, NS.kabukMaxRetries, prefs.maxRetries.toString());
    });
  }
}
