/// Usenet source resolver and streaming orchestrator.
///
/// Provides Netflix/YouTube-like automatic source selection:
/// - [UsenetResolver] ranks NZB results against user quality preferences
/// - [StreamOrchestrator] tries sources in ranked order with automatic fallback
///
/// Users see entities (movies, shows) — not NZB file details.
library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:kabuk/config/result.dart';
import 'package:kabuk/knowledge/types/streaming_prefs.dart';
import 'package:kabuk/platform/shared/usenet/release_parser.dart';
import 'package:kabuk/services/usenet.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// ResolvedSource — a ranked NZB candidate
// ---------------------------------------------------------------------------

/// A Usenet release that has been parsed and scored against user preferences.
@immutable
class ResolvedSource {
  /// Creates a [ResolvedSource].
  const ResolvedSource({
    required this.release,
    required this.quality,
    required this.score,
    required this.matchDetails,
  });

  /// The original search result.
  final UsenetRelease release;

  /// Parsed quality metadata from the release title.
  final ReleaseQuality quality;

  /// Composite score (higher = better match to user preferences).
  final int score;

  /// Human-readable explanation of why this score was assigned.
  final String matchDetails;

  /// Short label for UI display (e.g., "1080p · BluRay · x265").
  String get label => quality.label;

  /// File size in human-readable format.
  String get sizeLabel {
    final mb = release.sizeBytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(0)} MB';
  }

  @override
  String toString() => 'ResolvedSource($label, score=$score, ${sizeLabel})';
}

// ---------------------------------------------------------------------------
// UsenetResolver — scores & ranks NZB results against preferences
// ---------------------------------------------------------------------------

/// Searches Usenet indexers for an entity and ranks results against the
/// user's [StreamingPrefs].
///
/// Usage:
/// ```dart
/// final resolver = UsenetResolver(usenetService: service);
/// final sources = await resolver.resolveMovie(
///   imdbId: 'tt1234567',
///   title: 'Dune',
///   prefs: prefs,
/// );
/// // sources[0] is the best match
/// ```
class UsenetResolver {
  /// Creates a [UsenetResolver].
  const UsenetResolver({required UsenetService usenetService})
      : _usenet = usenetService;

  final UsenetService _usenet;
  static final _parser = ReleaseParser();

  /// Resolves movie sources by IMDB ID and/or title.
  ///
  /// Searches using [imdbId] when available (most accurate), falling back
  /// to [title] + [year] text search.
  Future<List<ResolvedSource>> resolveMovie({
    String? imdbId,
    String? title,
    int? year,
    required StreamingPrefs prefs,
  }) async {
    final results = await _searchForMovie(
      imdbId: imdbId,
      title: title,
      year: year,
    );
    return _rankResults(results, prefs);
  }

  /// Resolves TV episode sources by TVDB ID or title + season + episode.
  Future<List<ResolvedSource>> resolveTvEpisode({
    int? tvdbId,
    String? seriesTitle,
    int? season,
    int? episode,
    required StreamingPrefs prefs,
  }) async {
    final results = await _searchForTv(
      tvdbId: tvdbId,
      seriesTitle: seriesTitle,
      season: season,
      episode: episode,
    );
    return _rankResults(results, prefs);
  }

  /// Resolves sources for a generic query (non-entity search).
  Future<List<ResolvedSource>> resolveQuery({
    required String query,
    required StreamingPrefs prefs,
    UsenetCategory? category,
  }) async {
    final result = await _usenet.search(
      query,
      category: category,
      limit: 50,
    );
    final releases = switch (result) {
      Success(:final value) => value,
      Failure() => <UsenetRelease>[],
    };
    return _rankResults(releases, prefs);
  }

  // ── Search helpers ──────────────────────────────────────────────────────

  Future<List<UsenetRelease>> _searchForMovie({
    String? imdbId,
    String? title,
    int? year,
  }) async {
    final results = <UsenetRelease>[];

    // Prefer IMDB ID search (most accurate).
    if (imdbId != null && imdbId.isNotEmpty) {
      final res = await _usenet.searchMovie(imdbId: imdbId, limit: 50);
      if (res case Success(:final value)) {
        results.addAll(value);
      }
    }

    // Supplement with title search if few results or no IMDB ID.
    if (results.length < 5 && title != null && title.isNotEmpty) {
      final query = year != null ? '$title $year' : title;
      final res = await _usenet.search(
        query,
        category: UsenetCategory.movies,
        limit: 30,
      );
      if (res case Success(:final value)) {
        final existingIds = results.map((r) => r.id).toSet();
        results.addAll(value.where((r) => !existingIds.contains(r.id)));
      }
    }

    return results;
  }

  Future<List<UsenetRelease>> _searchForTv({
    int? tvdbId,
    String? seriesTitle,
    int? season,
    int? episode,
  }) async {
    final results = <UsenetRelease>[];

    // Prefer TVDB ID search.
    if (tvdbId != null) {
      final res = await _usenet.searchTv(
        tvdbId: tvdbId,
        season: season,
        episode: episode,
        limit: 50,
      );
      if (res case Success(:final value)) {
        results.addAll(value);
      }
    }

    // Supplement with title search.
    if (results.length < 5 && seriesTitle != null && seriesTitle.isNotEmpty) {
      final query = StringBuffer(seriesTitle);
      if (season != null) {
        query.write(' S${season.toString().padLeft(2, '0')}');
        if (episode != null) {
          query.write('E${episode.toString().padLeft(2, '0')}');
        }
      }
      final res = await _usenet.search(
        query.toString(),
        category: UsenetCategory.tvShows,
        limit: 30,
      );
      if (res case Success(:final value)) {
        final existingIds = results.map((r) => r.id).toSet();
        results.addAll(value.where((r) => !existingIds.contains(r.id)));
      }
    }

    return results;
  }

  // ── Scoring ─────────────────────────────────────────────────────────────

  List<ResolvedSource> _rankResults(
    List<UsenetRelease> releases,
    StreamingPrefs prefs,
  ) {
    final scored = <ResolvedSource>[];

    for (final release in releases) {
      final quality = _parser.parse(release.title);
      final result = _scoreRelease(release, quality, prefs);
      if (result != null) scored.add(result);
    }

    // Sort by score descending (best first).
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  /// Scores a release against user preferences. Returns `null` if the
  /// release should be excluded (e.g., wrong language).
  ResolvedSource? _scoreRelease(
    UsenetRelease release,
    ReleaseQuality quality,
    StreamingPrefs prefs,
  ) {
    var score = 0;
    final details = StringBuffer();

    // ── Language filter (mandatory) ──
    if (prefs.language != 'any' && prefs.language.isNotEmpty) {
      final lang = quality.language?.toLowerCase() ?? '';
      final prefLang = prefs.language.toLowerCase();
      if (lang.isNotEmpty &&
          lang != 'multi' &&
          lang != 'dual audio' &&
          !lang.contains(prefLang)) {
        // Wrong language — exclude entirely.
        return null;
      }
      if (lang.contains(prefLang) || lang == 'multi' || lang == 'dual audio') {
        score += 100;
        details.write('Language match. ');
      }
    }

    // ── Resolution scoring ──
    if (prefs.resolution != PreferredResolution.any) {
      final prefRes = prefs.resolution.label;
      if (quality.resolution == prefRes) {
        score += 500; // Exact match — highest priority.
        details.write('Exact resolution. ');
      } else {
        // Partial credit based on proximity.
        final resOrder = ['480p', '720p', '1080p', '2160p'];
        final prefIdx = resOrder.indexOf(prefRes);
        final qualIdx = resOrder.indexOf(quality.resolution ?? '');
        if (prefIdx >= 0 && qualIdx >= 0) {
          final distance = (prefIdx - qualIdx).abs();
          score += (400 - distance * 100).clamp(0, 400);
          if (qualIdx > prefIdx) {
            // Higher than preferred — small bonus (user gets better quality).
            score += 20;
            details.write('Higher res available. ');
          }
        } else {
          score += 100; // Unknown resolution — neutral.
        }
      }
    } else {
      // 'any' resolution — use raw quality score.
      score += quality.score;
      details.write('Best available. ');
    }

    // ── Source scoring ──
    if (prefs.source != 'any') {
      if (quality.source?.toLowerCase() == prefs.source.toLowerCase()) {
        score += 80;
        details.write('Source match. ');
      }
    } else {
      // Bonus for better sources.
      switch (quality.source?.toLowerCase()) {
        case 'remux':
          score += 50;
        case 'bluray':
          score += 40;
        case 'web-dl':
          score += 35;
        case 'webrip':
          score += 30;
        case 'hdtv':
          score += 20;
        default:
          break;
      }
    }

    // ── Codec scoring ──
    if (prefs.codec != 'any') {
      if (quality.codec?.toLowerCase() == prefs.codec.toLowerCase()) {
        score += 50;
        details.write('Codec match. ');
      }
    } else {
      if (quality.codec?.toLowerCase() == 'av1') score += 20;
      if (quality.codec?.toLowerCase() == 'x265' ||
          quality.codec?.toLowerCase() == 'hevc') score += 15;
    }

    // ── HDR scoring ──
    switch (prefs.hdr) {
      case HdrPreference.required:
        if (quality.hdr == null) return null; // Exclude SDR.
        score += 80;
        details.write('HDR required. ');
      case HdrPreference.preferred:
        if (quality.hdr != null) {
          score += 60;
          details.write('HDR preferred. ');
        }
      case HdrPreference.none:
        if (quality.hdr != null) {
          score -= 30; // Penalize HDR when user wants SDR.
        }
      case HdrPreference.any:
        if (quality.hdr != null) score += 25; // Minor bonus.
    }

    // ── Audio scoring ──
    if (prefs.audio != 'any') {
      if (quality.audio != null &&
          quality.audio!.toLowerCase().contains(prefs.audio.toLowerCase())) {
        score += 40;
        details.write('Audio match. ');
      }
    }

    // ── Size filtering ──
    if (prefs.maxFileSizeMb > 0) {
      final sizeMb = release.sizeBytes / (1024 * 1024);
      if (sizeMb > prefs.maxFileSizeMb) {
        return null; // Too large — exclude.
      }
      // Bonus for reasonable size (not too small = likely bad quality).
      if (sizeMb > 500) score += 10;
    }

    // ── PROPER/REPACK bonus ──
    if (quality.isProper) score += 15;
    if (quality.isRepack) score += 10;

    // ── Recency bonus (newer posts more likely to be complete) ──
    final age = DateTime.now().difference(release.publishedAt).inDays;
    if (age < 30) score += 20;
    else if (age < 90) score += 10;

    return ResolvedSource(
      release: release,
      quality: quality,
      score: score,
      matchDetails: details.toString().trim(),
    );
  }
}

// ---------------------------------------------------------------------------
// StreamOrchestrator — automatic fallback streaming
// ---------------------------------------------------------------------------

/// Events emitted by [StreamOrchestrator] during the streaming process.
sealed class OrchestratorEvent {
  const OrchestratorEvent();
}

/// Searching indexers for sources.
class OrchestratorResolving extends OrchestratorEvent {
  const OrchestratorResolving({required this.entity});
  final String entity;
}

/// Sources found and ranked.
class OrchestratorSourcesFound extends OrchestratorEvent {
  const OrchestratorSourcesFound({
    required this.sources,
    required this.selected,
  });
  final List<ResolvedSource> sources;
  final ResolvedSource selected;
}

/// Fetching and parsing the NZB file.
class OrchestratorFetchingNzb extends OrchestratorEvent {
  const OrchestratorFetchingNzb({required this.source});
  final ResolvedSource source;
}

/// Pipeline is buffering/downloading.
class OrchestratorBuffering extends OrchestratorEvent {
  const OrchestratorBuffering({
    required this.source,
    required this.percent,
  });
  final ResolvedSource source;
  final double percent;
}

/// Stream is ready and playing.
class OrchestratorPlaying extends OrchestratorEvent {
  const OrchestratorPlaying({
    required this.session,
    required this.source,
    required this.allSources,
  });
  final StreamSession session;
  final ResolvedSource source;
  final List<ResolvedSource> allSources;
}

/// Current source failed, trying the next one.
class OrchestratorRetrying extends OrchestratorEvent {
  const OrchestratorRetrying({
    required this.failedSource,
    required this.reason,
    required this.nextSource,
    required this.attempt,
    required this.maxAttempts,
  });
  final ResolvedSource failedSource;
  final String reason;
  final ResolvedSource nextSource;
  final int attempt;
  final int maxAttempts;
}

/// All sources exhausted or fatal error.
class OrchestratorFailed extends OrchestratorEvent {
  const OrchestratorFailed({
    required this.message,
    required this.triedCount,
  });
  final String message;
  final int triedCount;
}

/// Orchestrates streaming with automatic source selection and fallback.
///
/// Takes an entity (movie, TV episode, or query) and:
/// 1. Resolves available NZB sources ranked by user preferences
/// 2. Tries the best source first
/// 3. On failure, automatically falls back to the next-best source
/// 4. Emits [OrchestratorEvent]s for the UI to display progress
class StreamOrchestrator {
  /// Creates a [StreamOrchestrator].
  StreamOrchestrator({
    required UsenetService usenetService,
    required UsenetResolver resolver,
  })  : _usenet = usenetService,
        _resolver = resolver;

  final UsenetService _usenet;
  final UsenetResolver _resolver;

  final _eventController = StreamController<OrchestratorEvent>.broadcast();

  /// Stream of orchestrator events for UI binding.
  Stream<OrchestratorEvent> get events => _eventController.stream;

  StreamSession? _activeSession;
  List<ResolvedSource> _resolvedSources = [];
  ResolvedSource? _activeSource;
  bool _disposed = false;

  /// The currently active stream session, if any.
  StreamSession? get activeSession => _activeSession;

  /// The currently active resolved source.
  ResolvedSource? get activeSource => _activeSource;

  /// All resolved sources (for quality picker).
  List<ResolvedSource> get allSources => List.unmodifiable(_resolvedSources);

  /// Starts streaming a movie entity.
  Future<void> playMovie({
    String? imdbId,
    String? title,
    int? year,
    required StreamingPrefs prefs,
  }) async {
    final entityLabel = title ?? imdbId ?? 'movie';
    _emit(OrchestratorResolving(entity: entityLabel));

    final sources = await _resolver.resolveMovie(
      imdbId: imdbId,
      title: title,
      year: year,
      prefs: prefs,
    );

    await _playFromSources(sources, prefs, entityLabel);
  }

  /// Starts streaming a TV episode.
  Future<void> playTvEpisode({
    int? tvdbId,
    String? seriesTitle,
    int? season,
    int? episode,
    required StreamingPrefs prefs,
  }) async {
    final entityLabel = seriesTitle != null
        ? '$seriesTitle S${season?.toString().padLeft(2, '0') ?? '??'}'
            'E${episode?.toString().padLeft(2, '0') ?? '??'}'
        : 'episode';
    _emit(OrchestratorResolving(entity: entityLabel));

    final sources = await _resolver.resolveTvEpisode(
      tvdbId: tvdbId,
      seriesTitle: seriesTitle,
      season: season,
      episode: episode,
      prefs: prefs,
    );

    await _playFromSources(sources, prefs, entityLabel);
  }

  /// Starts streaming from a generic query.
  Future<void> playQuery({
    required String query,
    required StreamingPrefs prefs,
    UsenetCategory? category,
  }) async {
    _emit(OrchestratorResolving(entity: query));

    final sources = await _resolver.resolveQuery(
      query: query,
      prefs: prefs,
      category: category,
    );

    await _playFromSources(sources, prefs, query);
  }

  /// Switches to a specific source (user picked from quality menu).
  Future<void> switchSource(
    ResolvedSource source,
    StreamingPrefs prefs,
  ) async {
    // Stop current stream.
    await stop();

    _emit(OrchestratorFetchingNzb(source: source));
    await _trySource(source);
  }

  /// Stops the current stream.
  Future<void> stop() async {
    if (_activeSession != null) {
      try {
        await _usenet.stopStream(_activeSession!.id);
      } catch (e) {
        dev.log('StreamOrchestrator: error stopping stream: $e');
      }
      _activeSession = null;
      _activeSource = null;
    }
  }

  /// Disposes the orchestrator and stops any active stream.
  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _eventController.close();
  }

  // ── Internal ────────────────────────────────────────────────────────────

  Future<void> _playFromSources(
    List<ResolvedSource> sources,
    StreamingPrefs prefs,
    String entityLabel,
  ) async {
    if (_disposed) return;

    if (sources.isEmpty) {
      _emit(const OrchestratorFailed(
        message: 'No sources found. Try broadening your quality preferences.',
        triedCount: 0,
      ));
      return;
    }

    _resolvedSources = sources;
    final maxRetries = prefs.maxRetries.clamp(1, sources.length);

    _emit(OrchestratorSourcesFound(
      sources: sources,
      selected: sources.first,
    ));

    for (var i = 0; i < maxRetries && i < sources.length; i++) {
      if (_disposed) return;

      final source = sources[i];
      _emit(OrchestratorFetchingNzb(source: source));

      final success = await _trySource(source);
      if (success) {
        _emit(OrchestratorPlaying(
          session: _activeSession!,
          source: source,
          allSources: sources,
        ));
        return;
      }

      // Failed — try next if available.
      if (i + 1 < maxRetries && i + 1 < sources.length) {
        _emit(OrchestratorRetrying(
          failedSource: source,
          reason: 'Stream failed to start',
          nextSource: sources[i + 1],
          attempt: i + 2,
          maxAttempts: maxRetries,
        ));
      }
    }

    if (_activeSession == null) {
      _emit(OrchestratorFailed(
        message: 'All sources failed after trying '
            '${maxRetries.clamp(0, sources.length)} options.',
        triedCount: maxRetries.clamp(0, sources.length),
      ));
    }
  }

  /// Attempts to stream from [source]. Returns `true` on success.
  Future<bool> _trySource(ResolvedSource source) async {
    try {
      // 1. Fetch NZB file.
      dev.log('StreamOrchestrator: fetching NZB for "${source.label}" '
          '(${source.sizeLabel})');

      final nzbResult = await _usenet.fetchNzb(source.release.nzbUrl);

      final nzb = switch (nzbResult) {
        Success(:final value) => value,
        Failure(:final error) => () {
          dev.log('StreamOrchestrator: NZB fetch failed: $error');
          return null;
        }(),
      };
      if (nzb == null) return false;

      // 2. Start streaming pipeline.
      _emit(OrchestratorBuffering(source: source, percent: 0));

      final sessionResult = await _usenet.startStream(nzb);
      final session = switch (sessionResult) {
        Success(:final value) => value,
        Failure(:final error) => () {
          dev.log('StreamOrchestrator: stream start failed: $error');
          return null;
        }(),
      };
      if (session == null) return false;

      _activeSession = session;
      _activeSource = source;
      return true;
    } catch (e) {
      dev.log('StreamOrchestrator: unexpected error: $e');
      return false;
    }
  }

  void _emit(OrchestratorEvent event) {
    if (!_disposed && !_eventController.isClosed) {
      _eventController.add(event);
    }
  }
}
