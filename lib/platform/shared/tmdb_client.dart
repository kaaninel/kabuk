/// TMDB v3 API client — implements [MediaMetadataService] using
/// The Movie Database.
///
/// Requires a valid TMDB API key (v3 auth). Pass the key via the
/// constructor; it is sent as the `api_key` query parameter on every
/// request.
///
/// ```dart
/// final tmdb = TmdbClient(apiKey: 'YOUR_TMDB_V3_KEY');
/// final results = await tmdb.search('Breaking Bad');
/// ```
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/services/media_metadata.dart';

// ---------------------------------------------------------------------------
// Image helper
// ---------------------------------------------------------------------------

/// Static helper for building TMDB image URLs without a service instance.
///
/// Useful in UI code where you have a relative path from a data class
/// but don't want to thread the [MediaMetadataService] through.
class TmdbImageHelper {
  TmdbImageHelper._();

  static const _imageBase = 'https://image.tmdb.org/t/p';

  /// Builds a full TMDB image URL from a relative [path].
  ///
  /// Returns `null` when [path] is `null`. If [path] is already an absolute
  /// URL (e.g. from TVmaze or IMDbAPI), it is returned unchanged.
  static String? url(
    String? path, {
    MediaImageSize size = MediaImageSize.medium,
  }) {
    if (path == null) return null;
    // Already an absolute URL — return as-is.
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$_imageBase/${_sizeString(size)}$path';
  }

  static String _sizeString(MediaImageSize size) => switch (size) {
        MediaImageSize.small => 'w185',
        MediaImageSize.medium => 'w342',
        MediaImageSize.large => 'w500',
        MediaImageSize.original => 'original',
      };
}

// ---------------------------------------------------------------------------
// TMDB client
// ---------------------------------------------------------------------------

/// [MediaMetadataService] implementation backed by the TMDB v3 REST API.
///
/// All HTTP calls use `package:http` so the client can be injected for
/// testing. Image URLs are constructed using the TMDB CDN base path.
class TmdbClient implements MediaMetadataService {
  /// Creates a [TmdbClient].
  ///
  /// - [apiKey]: TMDB v3 API key.
  /// - [httpClient]: Optional HTTP client for testing / custom transport.
  /// - [language]: ISO 639-1 language code for localised results.
  TmdbClient({
    required String apiKey,
    http.Client? httpClient,
    this.language = 'en-US',
  })  : _apiKey = apiKey,
        _http = httpClient ?? http.Client();

  static const _baseUrl = 'https://api.themoviedb.org';
  static const _imageBase = 'https://image.tmdb.org/t/p';

  final String _apiKey;
  final http.Client _http;

  /// ISO 639-1 language code sent with every request.
  final String language;

  // -------------------------------------------------------------------------
  // MediaMetadataService — imageUrl
  // -------------------------------------------------------------------------

  @override
  String imageUrl(String path, {MediaImageSize size = MediaImageSize.medium}) {
    final sizeStr = TmdbImageHelper._sizeString(size);
    return '$_imageBase/$sizeStr$path';
  }

  // -------------------------------------------------------------------------
  // MediaMetadataService — search
  // -------------------------------------------------------------------------

  @override
  Future<Result<List<MediaSearchResult>>> search(
    String query, {
    int page = 1,
  }) async {
    final uri = _uri('/3/search/multi', {
      'query': query,
      'page': page.toString(),
    });

    return _get(uri, (json) {
      final results = json['results'] as List<dynamic>? ?? [];
      return results
          .where((r) {
            final type = r['media_type'] as String?;
            return type == 'movie' || type == 'tv';
          })
          .map(_parseSearchResult)
          .toList(growable: false);
    });
  }

  // -------------------------------------------------------------------------
  // MediaMetadataService — getTvSeries
  // -------------------------------------------------------------------------

  @override
  Future<Result<TvSeriesDetail>> getTvSeries(int id) async {
    final uri = _uri('/3/tv/$id', {
      'append_to_response': 'external_ids',
    });

    return _get(uri, _parseTvSeriesDetail);
  }

  // -------------------------------------------------------------------------
  // MediaMetadataService — getTvSeason
  // -------------------------------------------------------------------------

  @override
  Future<Result<TvSeasonDetail>> getTvSeason(
    int seriesId,
    int seasonNumber,
  ) async {
    final uri = _uri('/3/tv/$seriesId/season/$seasonNumber');

    return _get(uri, _parseTvSeasonDetail);
  }

  // -------------------------------------------------------------------------
  // MediaMetadataService — getMovie
  // -------------------------------------------------------------------------

  @override
  Future<Result<MovieDetail>> getMovie(int id) async {
    final uri = _uri('/3/movie/$id', {
      'append_to_response': 'external_ids',
    });

    return _get(uri, _parseMovieDetail);
  }

  // -------------------------------------------------------------------------
  // HTTP helpers
  // -------------------------------------------------------------------------

  /// Builds a [Uri] with the shared API key and language parameters.
  Uri _uri(String path, [Map<String, String>? extra]) {
    final params = <String, String>{
      'api_key': _apiKey,
      'language': language,
      ...?extra,
    };
    return Uri.parse('$_baseUrl$path').replace(queryParameters: params);
  }

  /// Performs a GET request and parses the JSON response with [parse].
  ///
  /// Returns [Result.failure] for HTTP errors, JSON decode failures, and
  /// unexpected exceptions.
  Future<Result<T>> _get<T>(Uri uri, T Function(Map<String, dynamic>) parse) async {
    try {
      final response = await _http.get(uri);

      if (response.statusCode == 404) {
        return Result.failure(
          ServiceError.notFound('TMDB resource: $uri'),
        );
      }

      if (response.statusCode != 200) {
        return Result.failure(
          ServiceError.network(
            'TMDB API returned ${response.statusCode}: '
            '${response.reasonPhrase}',
          ),
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return Result.success(parse(json));
    } on http.ClientException catch (e) {
      return Result.failure(ServiceError.network('HTTP error: $e'));
    } on FormatException catch (e) {
      return Result.failure(
        ServiceError.unknown('Failed to parse TMDB response', e),
      );
    } on Exception catch (e, st) {
      return Result.failure(ServiceError.unknown('$e', e, st));
    }
  }

  // -------------------------------------------------------------------------
  // JSON → Data class parsers
  // -------------------------------------------------------------------------

  MediaSearchResult _parseSearchResult(dynamic raw) {
    final json = raw as Map<String, dynamic>;
    final type = json['media_type'] as String;
    final isMovie = type == 'movie';

    final title =
        (isMovie ? json['title'] : json['name']) as String? ?? '';
    final originalTitle =
        (isMovie ? json['original_title'] : json['original_name']) as String?;
    final dateStr =
        (isMovie ? json['release_date'] : json['first_air_date']) as String?;

    return MediaSearchResult(
      id: json['id'] as int,
      title: title,
      mediaType: isMovie ? MediaType.movie : MediaType.tvSeries,
      originalTitle: originalTitle,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseYear: _parseYear(dateStr),
      voteAverage: _toDouble(json['vote_average']),
      voteCount: json['vote_count'] as int?,
      genreIds: (json['genre_ids'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList(growable: false) ??
          const [],
      popularity: _toDouble(json['popularity']),
    );
  }

  TvSeriesDetail _parseTvSeriesDetail(Map<String, dynamic> json) {
    return TvSeriesDetail(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      originalName: json['original_name'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      firstAirDate: _parseDate(json['first_air_date'] as String?),
      lastAirDate: _parseDate(json['last_air_date'] as String?),
      status: json['status'] as String?,
      numberOfSeasons: json['number_of_seasons'] as int? ?? 0,
      numberOfEpisodes: json['number_of_episodes'] as int? ?? 0,
      seasons: (json['seasons'] as List<dynamic>?)
              ?.map(_parseSeasonSummary)
              .toList(growable: false) ??
          const [],
      genres: (json['genres'] as List<dynamic>?)
              ?.map((g) => (g as Map<String, dynamic>)['name'] as String)
              .toList(growable: false) ??
          const [],
      networks: (json['networks'] as List<dynamic>?)
              ?.map((n) => (n as Map<String, dynamic>)['name'] as String)
              .toList(growable: false) ??
          const [],
      voteAverage: _toDouble(json['vote_average']),
      externalIds: json['external_ids'] != null
          ? _parseExternalIds(json['external_ids'] as Map<String, dynamic>)
          : null,
      homepage: json['homepage'] as String?,
    );
  }

  TvSeasonSummary _parseSeasonSummary(dynamic raw) {
    final json = raw as Map<String, dynamic>;
    return TvSeasonSummary(
      id: json['id'] as int,
      seasonNumber: json['season_number'] as int,
      name: json['name'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      airDate: _parseDate(json['air_date'] as String?),
      episodeCount: json['episode_count'] as int? ?? 0,
    );
  }

  TvSeasonDetail _parseTvSeasonDetail(Map<String, dynamic> json) {
    return TvSeasonDetail(
      id: json['id'] as int,
      seasonNumber: json['season_number'] as int,
      name: json['name'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      airDate: _parseDate(json['air_date'] as String?),
      episodes: (json['episodes'] as List<dynamic>?)
              ?.map(_parseEpisode)
              .toList(growable: false) ??
          const [],
    );
  }

  TvEpisode _parseEpisode(dynamic raw) {
    final json = raw as Map<String, dynamic>;
    return TvEpisode(
      id: json['id'] as int,
      episodeNumber: json['episode_number'] as int,
      seasonNumber: json['season_number'] as int,
      name: json['name'] as String?,
      overview: json['overview'] as String?,
      stillPath: json['still_path'] as String?,
      airDate: _parseDate(json['air_date'] as String?),
      voteAverage: _toDouble(json['vote_average']),
      runtime: json['runtime'] as int?,
    );
  }

  MovieDetail _parseMovieDetail(Map<String, dynamic> json) {
    return MovieDetail(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      originalTitle: json['original_title'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate: _parseDate(json['release_date'] as String?),
      runtime: json['runtime'] as int?,
      genres: (json['genres'] as List<dynamic>?)
              ?.map((g) => (g as Map<String, dynamic>)['name'] as String)
              .toList(growable: false) ??
          const [],
      voteAverage: _toDouble(json['vote_average']),
      externalIds: json['external_ids'] != null
          ? _parseExternalIds(json['external_ids'] as Map<String, dynamic>)
          : null,
      homepage: json['homepage'] as String?,
      tagline: json['tagline'] as String?,
      budget: json['budget'] as int?,
      revenue: json['revenue'] as int?,
    );
  }

  ExternalIds _parseExternalIds(Map<String, dynamic> json) {
    return ExternalIds(
      imdbId: json['imdb_id'] as String?,
      tvdbId: json['tvdb_id'] as int?,
      tvrageId: json['tvrage_id'] as int?,
      facebookId: json['facebook_id'] as String?,
      instagramId: json['instagram_id'] as String?,
      twitterId: json['twitter_id'] as String?,
    );
  }

  // -------------------------------------------------------------------------
  // Value helpers
  // -------------------------------------------------------------------------

  /// Safely parses a `YYYY-MM-DD` date string.
  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } on FormatException {
      return null;
    }
  }

  /// Extracts the four-digit year from a `YYYY-MM-DD` string.
  static int? _parseYear(String? value) {
    if (value == null || value.length < 4) return null;
    return int.tryParse(value.substring(0, 4));
  }

  /// Coerces a JSON number to [double], handling both `int` and `double`.
  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
