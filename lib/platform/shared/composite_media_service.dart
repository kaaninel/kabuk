/// Composite media metadata service — always-available search via free APIs,
/// enhanced with TMDB when an API key is configured.
///
/// **Free tier (no API key):** TVmaze for TV series, IMDbAPI.dev for movies.
/// **Enhanced tier:** TMDB for all media with fallback to the free sources.
///
/// The service uses synthetic IDs to route detail requests to the correct
/// backend:
///   - Positive IDs → TMDB (or free-source fallback)
///   - Negative IDs → TVmaze (negate to recover the real ID)
///   - Hash-based IDs → IMDbAPI (stored in an internal lookup map)
library;

import 'dart:developer' as dev;

import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/platform/shared/imdbapi_client.dart';
import 'package:kabuk/platform/shared/tmdb_client.dart';
import 'package:kabuk/platform/shared/tvmaze_client.dart';
import 'package:kabuk/services/media_metadata.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Source tracking
// ---------------------------------------------------------------------------

/// Identifies the backend that produced a given synthetic ID.
enum _Source { tmdb, tvmaze, imdbapi }

/// Maps a synthetic ID back to its source and original identifier.
@immutable
class _IdMapping {
  const _IdMapping(this.source, {this.tvMazeId, this.imdbId, this.title});

  final _Source source;

  /// Original TVmaze show ID (only when [source] is [_Source.tvmaze]).
  final int? tvMazeId;

  /// Original IMDb ID string (only when [source] is [_Source.imdbapi]).
  final String? imdbId;

  /// Title stored for fallback lookups.
  final String? title;
}

// ---------------------------------------------------------------------------
// CompositeMediaService
// ---------------------------------------------------------------------------

/// A [MediaMetadataService] that combines free APIs (TVmaze + IMDbAPI.dev)
/// with optional TMDB enhancement.
///
/// Search results from all available backends are merged and deduplicated.
/// Detail requests are routed to the correct backend based on synthetic ID
/// ranges established during search.
class CompositeMediaService implements MediaMetadataService {
  /// Creates a [CompositeMediaService].
  ///
  /// - [tmdb]: Optional TMDB client — only available when the user has
  ///   configured an API key.
  /// - [tvMaze]: TVmaze client (always available, no key needed).
  /// - [imdbApi]: IMDbAPI.dev client (always available, no key needed).
  CompositeMediaService({
    TmdbClient? tmdb,
    TvMazeClient? tvMaze,
    ImdbApiClient? imdbApi,
  })  : _tmdb = tmdb,
        _tvMaze = tvMaze ?? TvMazeClient(),
        _imdbApi = imdbApi ?? ImdbApiClient();

  final TmdbClient? _tmdb;
  final TvMazeClient? _tvMaze;
  final ImdbApiClient? _imdbApi;

  /// Whether the TMDB enhanced tier is available.
  bool get hasTmdb => _tmdb != null;

  /// Synthetic-ID → source mapping built during searches.
  final Map<int, _IdMapping> _idMap = {};

  // -------------------------------------------------------------------------
  // MediaMetadataService — search
  // -------------------------------------------------------------------------

  @override
  Future<Result<List<MediaSearchResult>>> search(
    String query, {
    int page = 1,
  }) async {
    try {
      // Launch all available searches in parallel.
      final futures = <String, Future<Object>>{};

      if (_tvMaze != null) {
        futures['tvmaze'] = _tvMaze.searchShows(query);
      }
      if (_imdbApi != null) {
        futures['imdb'] = _imdbApi.search(query);
      }
      if (_tmdb != null) {
        futures['tmdb'] = _tmdb.search(query, page: page);
      }

      final results = await Future.wait(
        futures.values,
        eagerError: false,
      );

      final keys = futures.keys.toList();
      final merged = <MediaSearchResult>[];

      // Collect TMDB results first (best quality).
      if (keys.contains('tmdb')) {
        final idx = keys.indexOf('tmdb');
        final raw = results[idx];
        if (raw is Result<List<MediaSearchResult>>) {
          switch (raw) {
            case Success(:final value):
              for (final r in value) {
                _idMap[r.id] = _IdMapping(_Source.tmdb, title: r.title);
                merged.add(r);
              }
            case Failure(:final error):
              dev.log(
                'TMDB search failed, falling back to free sources: $error',
                name: 'CompositeMediaService',
              );
          }
        }
      }

      // Build a set of (normalised title, year) pairs for deduplication.
      final seen = <String>{};
      for (final r in merged) {
        seen.add(_dedupeKey(r.title, r.releaseYear));
      }

      // Merge TVmaze TV results that aren't already covered by TMDB.
      if (keys.contains('tvmaze')) {
        final idx = keys.indexOf('tvmaze');
        final raw = results[idx];
        if (raw is Result<List<TvMazeShow>>) {
          switch (raw) {
            case Success(:final value):
              for (final show in value) {
                final converted = _tvMazeShowToSearchResult(show);
                final key =
                    _dedupeKey(converted.title, converted.releaseYear);
                if (!seen.contains(key)) {
                  seen.add(key);
                  _idMap[converted.id] = _IdMapping(
                    _Source.tvmaze,
                    tvMazeId: show.id,
                    title: show.name,
                  );
                  merged.add(converted);
                }
              }
            case Failure(:final error):
              dev.log(
                'TVmaze search failed: $error',
                name: 'CompositeMediaService',
              );
          }
        }
      }

      // Merge IMDbAPI movie results that aren't already covered.
      if (keys.contains('imdb')) {
        final idx = keys.indexOf('imdb');
        final raw = results[idx];
        if (raw is Result<List<ImdbSearchResult>>) {
          switch (raw) {
            case Success(:final value):
              for (final item in value) {
                final converted = _imdbResultToSearchResult(item);
                final key =
                    _dedupeKey(converted.title, converted.releaseYear);
                if (!seen.contains(key)) {
                  seen.add(key);
                  _idMap[converted.id] = _IdMapping(
                    _Source.imdbapi,
                    imdbId: item.id,
                    title: item.title,
                  );
                  merged.add(converted);
                }
              }
            case Failure(:final error):
              dev.log(
                'IMDbAPI search failed: $error',
                name: 'CompositeMediaService',
              );
          }
        }
      }

      return Result.success(merged);
    } on Exception catch (e, st) {
      dev.log(
        'Composite search failed: $e',
        name: 'CompositeMediaService',
        error: e,
        stackTrace: st,
      );
      return Result.failure(ServiceError.network('Search failed: $e'));
    }
  }

  // -------------------------------------------------------------------------
  // MediaMetadataService — getTvSeries
  // -------------------------------------------------------------------------

  @override
  Future<Result<TvSeriesDetail>> getTvSeries(int id) async {
    final mapping = _idMap[id];

    // Negative IDs are always TVmaze.
    if (id < 0) {
      final tvMazeId = mapping?.tvMazeId ?? -id;
      return _getTvSeriesFromTvMaze(tvMazeId);
    }

    // Positive ID with TMDB available → prefer TMDB.
    if (_tmdb != null) {
      final result = await _tmdb.getTvSeries(id);
      if (result.isSuccess) return result;

      // TMDB failed — try TVmaze fallback if we have a mapping.
      if (mapping?.tvMazeId != null) {
        dev.log(
          'TMDB getTvSeries($id) failed, falling back to TVmaze',
          name: 'CompositeMediaService',
        );
        return _getTvSeriesFromTvMaze(mapping!.tvMazeId!);
      }
      return result;
    }

    // No TMDB — try TVmaze via stored mapping.
    if (mapping?.tvMazeId != null) {
      return _getTvSeriesFromTvMaze(mapping!.tvMazeId!);
    }

    return const Result.failure(
      ServiceError.notFound('TV series not found (no TMDB key configured)'),
    );
  }

  // -------------------------------------------------------------------------
  // MediaMetadataService — getTvSeason
  // -------------------------------------------------------------------------

  @override
  Future<Result<TvSeasonDetail>> getTvSeason(
    int seriesId,
    int seasonNumber,
  ) async {
    final mapping = _idMap[seriesId];

    // Negative IDs are always TVmaze.
    if (seriesId < 0) {
      final tvMazeId = mapping?.tvMazeId ?? -seriesId;
      return _getTvSeasonFromTvMaze(tvMazeId, seasonNumber);
    }

    // Positive ID with TMDB available → prefer TMDB.
    if (_tmdb != null) {
      final result = await _tmdb.getTvSeason(seriesId, seasonNumber);
      if (result.isSuccess) return result;

      // TMDB failed — try TVmaze fallback.
      if (mapping?.tvMazeId != null) {
        dev.log(
          'TMDB getTvSeason($seriesId, $seasonNumber) failed, '
          'falling back to TVmaze',
          name: 'CompositeMediaService',
        );
        return _getTvSeasonFromTvMaze(mapping!.tvMazeId!, seasonNumber);
      }
      return result;
    }

    // No TMDB — try TVmaze.
    if (mapping?.tvMazeId != null) {
      return _getTvSeasonFromTvMaze(mapping!.tvMazeId!, seasonNumber);
    }

    return const Result.failure(
      ServiceError.notFound('TV season not found (no TMDB key configured)'),
    );
  }

  // -------------------------------------------------------------------------
  // MediaMetadataService — getMovie
  // -------------------------------------------------------------------------

  @override
  Future<Result<MovieDetail>> getMovie(int id) async {
    final mapping = _idMap[id];

    // Positive ID with TMDB available → prefer TMDB.
    if (id > 0 && _tmdb != null) {
      final result = await _tmdb.getMovie(id);
      if (result.isSuccess) return result;

      // TMDB failed — try IMDbAPI fallback.
      if (mapping?.imdbId != null) {
        dev.log(
          'TMDB getMovie($id) failed, falling back to IMDbAPI',
          name: 'CompositeMediaService',
        );
        return _getMovieFromImdb(mapping!.imdbId!);
      }
      return result;
    }

    // No TMDB or non-positive ID — try IMDbAPI via stored mapping.
    if (mapping?.imdbId != null) {
      return _getMovieFromImdb(mapping!.imdbId!);
    }

    // If TMDB is available but we have no IMDb mapping, try TMDB anyway.
    if (_tmdb != null && id > 0) {
      return _tmdb.getMovie(id);
    }

    return const Result.failure(
      ServiceError.notFound('Movie not found'),
    );
  }

  // -------------------------------------------------------------------------
  // MediaMetadataService — imageUrl
  // -------------------------------------------------------------------------

  @override
  String imageUrl(String path, {MediaImageSize size = MediaImageSize.medium}) {
    // Already an absolute URL (TVmaze / IMDbAPI).
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    // TMDB relative path (starts with '/').
    if (path.startsWith('/') && _tmdb != null) {
      return _tmdb.imageUrl(path, size: size);
    }

    // Fallback: use TmdbImageHelper for TMDB-style paths even without a
    // client instance.
    if (path.startsWith('/')) {
      return TmdbImageHelper.url(path, size: size) ?? path;
    }

    // Unknown format — return as-is.
    return path;
  }

  // -------------------------------------------------------------------------
  // TVmaze helpers
  // -------------------------------------------------------------------------

  Future<Result<TvSeriesDetail>> _getTvSeriesFromTvMaze(int showId) async {
    if (_tvMaze == null) {
      return const Result.failure(
        ServiceError.notFound('TVmaze client not available'),
      );
    }

    try {
      final showResult = await _tvMaze.getShow(showId);
      final seasonsResult = await _tvMaze.getSeasons(showId);

      switch (showResult) {
        case Failure(:final error):
          return Result.failure(error);
        case Success(value: final show):
          switch (seasonsResult) {
            case Failure(:final error):
              return Result.failure(error);
            case Success(value: final seasons):
              return Result.success(_tvMazeShowToDetail(show, seasons));
          }
      }
    } on Exception catch (e, st) {
      dev.log(
        'TVmaze getTvSeries($showId) failed: $e',
        name: 'CompositeMediaService',
        error: e,
        stackTrace: st,
      );
      return Result.failure(ServiceError.network('TVmaze lookup failed: $e'));
    }
  }

  Future<Result<TvSeasonDetail>> _getTvSeasonFromTvMaze(
    int showId,
    int seasonNumber,
  ) async {
    if (_tvMaze == null) {
      return const Result.failure(
        ServiceError.notFound('TVmaze client not available'),
      );
    }

    try {
      final seasonsResult = await _tvMaze.getSeasons(showId);
      switch (seasonsResult) {
        case Failure(:final error):
          return Result.failure(error);
        case Success(:final value):
          final match = value.where((s) => s.number == seasonNumber);
          if (match.isEmpty) {
            return Result.failure(
              ServiceError.notFound(
                'Season $seasonNumber not found on TVmaze',
              ),
            );
          }

          final season = match.first;
          final episodesResult = await _tvMaze.getSeasonEpisodes(season.id);
          switch (episodesResult) {
            case Failure(:final error):
              return Result.failure(error);
            case Success(:final value):
              return Result.success(
                TvSeasonDetail(
                  id: season.id,
                  seasonNumber: season.number,
                  name: 'Season ${season.number}',
                  posterPath: season.imageUrl,
                  airDate: DateTime.tryParse(season.premiereDate ?? ''),
                  episodes: value
                      .map(_tvMazeEpisodeToEpisode)
                      .toList(growable: false),
                ),
              );
          }
      }
    } on Exception catch (e, st) {
      dev.log(
        'TVmaze getTvSeason($showId, $seasonNumber) failed: $e',
        name: 'CompositeMediaService',
        error: e,
        stackTrace: st,
      );
      return Result.failure(
        ServiceError.network('TVmaze season lookup failed: $e'),
      );
    }
  }

  // -------------------------------------------------------------------------
  // IMDbAPI helpers
  // -------------------------------------------------------------------------

  Future<Result<MovieDetail>> _getMovieFromImdb(String imdbId) async {
    if (_imdbApi == null) {
      return const Result.failure(
        ServiceError.notFound('IMDbAPI client not available'),
      );
    }

    try {
      final result = await _imdbApi.getTitle(imdbId);
      switch (result) {
        case Success(:final value):
          return Result.success(_imdbDetailToMovieDetail(value));
        case Failure(:final error):
          return Result.failure(error);
      }
    } on Exception catch (e, st) {
      dev.log(
        'IMDbAPI getTitle($imdbId) failed: $e',
        name: 'CompositeMediaService',
        error: e,
        stackTrace: st,
      );
      return Result.failure(
        ServiceError.network('IMDbAPI lookup failed: $e'),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Conversion helpers
  // -------------------------------------------------------------------------

  /// Converts a [TvMazeShow] to a [MediaSearchResult].
  MediaSearchResult _tvMazeShowToSearchResult(TvMazeShow show) {
    // Use negated TVmaze ID as synthetic ID.
    final syntheticId = -show.id;
    return MediaSearchResult(
      id: syntheticId,
      title: show.name,
      mediaType: MediaType.tvSeries,
      overview: show.summary,
      posterPath: show.imageUrl,
      releaseYear: DateTime.tryParse(show.premiered ?? '')?.year,
      voteAverage: show.rating,
    );
  }

  /// Converts an [ImdbSearchResult] to a [MediaSearchResult].
  MediaSearchResult _imdbResultToSearchResult(ImdbSearchResult item) {
    // Use hash of IMDb ID as synthetic ID, ensuring it's positive.
    final syntheticId = item.id.hashCode.abs();
    return MediaSearchResult(
      id: syntheticId,
      title: item.title,
      mediaType: item.type == ImdbMediaType.series
          ? MediaType.tvSeries
          : MediaType.movie,
      posterPath: item.posterUrl,
      releaseYear: item.year,
    );
  }

  /// Converts a [TvMazeShow] and its seasons to a [TvSeriesDetail].
  TvSeriesDetail _tvMazeShowToDetail(
    TvMazeShow show,
    List<TvMazeSeason> seasons,
  ) {
    final totalEpisodes = seasons.fold<int>(
      0,
      (sum, s) => sum + (s.episodeOrder ?? 0),
    );

    return TvSeriesDetail(
      id: -show.id,
      name: show.name,
      overview: show.summary,
      posterPath: show.imageUrl,
      backdropPath: show.imageOriginalUrl,
      firstAirDate: DateTime.tryParse(show.premiered ?? ''),
      status: show.status,
      numberOfSeasons: seasons.length,
      numberOfEpisodes: totalEpisodes,
      seasons: seasons.map(_tvMazeSeasonToSummary).toList(growable: false),
      genres: show.genres,
      networks: show.networkName != null ? [show.networkName!] : const [],
      voteAverage: show.rating,
      externalIds: ExternalIds(
        imdbId: show.externals.imdb,
        tvdbId: show.externals.thetvdb,
      ),
    );
  }

  /// Converts a [TvMazeSeason] to a [TvSeasonSummary].
  TvSeasonSummary _tvMazeSeasonToSummary(TvMazeSeason season) {
    return TvSeasonSummary(
      id: season.id,
      seasonNumber: season.number,
      name: 'Season ${season.number}',
      posterPath: season.imageUrl,
      airDate: DateTime.tryParse(season.premiereDate ?? ''),
      episodeCount: season.episodeOrder ?? 0,
    );
  }

  /// Converts a [TvMazeEpisode] to a [TvEpisode].
  TvEpisode _tvMazeEpisodeToEpisode(TvMazeEpisode ep) {
    return TvEpisode(
      id: ep.id,
      episodeNumber: ep.number ?? 0,
      seasonNumber: ep.season ?? 0,
      name: ep.name,
      overview: ep.summary,
      stillPath: ep.imageUrl,
      airDate: DateTime.tryParse(ep.airdate ?? ''),
      runtime: ep.runtime,
    );
  }

  /// Converts an [ImdbTitleDetail] to a [MovieDetail].
  MovieDetail _imdbDetailToMovieDetail(ImdbTitleDetail detail) {
    return MovieDetail(
      id: detail.id.hashCode.abs(),
      title: detail.title,
      overview: detail.plot,
      posterPath: detail.posterUrl,
      releaseDate: detail.year != null
          ? DateTime(detail.year!)
          : null,
      runtime: detail.runtimeMinutes,
      genres: detail.genres,
      voteAverage: detail.rating,
      externalIds: ExternalIds(imdbId: detail.id),
    );
  }

  // -------------------------------------------------------------------------
  // Deduplication
  // -------------------------------------------------------------------------

  /// Builds a normalised key for title+year deduplication.
  static String _dedupeKey(String title, int? year) {
    final normalised = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return '$normalised:${year ?? ''}';
  }
}
