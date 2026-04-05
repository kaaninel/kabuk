/// TVDB API v4 client for TV series metadata.
///
/// Primarily used as a secondary/fallback metadata source alongside TMDB.
/// Specializes in TV data with detailed episode and season information.
/// TVDB IDs are used by Newznab indexers for TV search
/// (`?t=tvsearch&tvdbid=X`), making this client essential for matching
/// releases to metadata.
///
/// See: https://thetvdb.github.io/v4-api/
///
/// ```dart
/// final client = TvdbClient(apiKey: 'your-tvdb-v4-key');
/// final results = await client.search('Breaking Bad');
/// switch (results) {
///   case Success(:final value):
///     for (final r in value) print('${r.name} (${r.year})');
///   case Failure(:final error):
///     print('Search failed: $error');
/// }
/// ```
library;

import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;
import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// The type of a TVDB entity returned in search results.
enum TvdbEntityType {
  /// A TV series.
  series,

  /// A movie.
  movie,

  /// A person (actor, director, etc.).
  person,

  /// A company (network, studio, etc.).
  company;

  /// Parses a TVDB API type string into a [TvdbEntityType].
  ///
  /// Returns `null` for unrecognised values.
  static TvdbEntityType? fromString(String? value) => switch (value) {
        'series' => series,
        'movie' => movie,
        'person' => person,
        'company' => company,
        _ => null,
      };
}

/// A single result from the TVDB search endpoint.
@immutable
class TvdbSearchResult {
  /// Creates a [TvdbSearchResult].
  const TvdbSearchResult({
    required this.tvdbId,
    required this.name,
    this.overview,
    this.year,
    this.type,
    this.imageUrl,
    this.status,
    this.network,
    this.aliases = const [],
  });

  /// TVDB numeric identifier (string from the API, stored as-is).
  final String tvdbId;

  /// Primary display name.
  final String name;

  /// Synopsis or plot summary.
  final String? overview;

  /// First-aired year, if available.
  final String? year;

  /// The entity type (series, movie, etc.).
  final TvdbEntityType? type;

  /// URL for the primary artwork thumbnail.
  final String? imageUrl;

  /// Airing status (e.g. `Continuing`, `Ended`).
  final String? status;

  /// Primary network or streaming service.
  final String? network;

  /// Alternative names for this entity.
  final List<String> aliases;

  @override
  String toString() => 'TvdbSearchResult($tvdbId, $name)';
}

/// Detailed information about a TV series from TVDB.
@immutable
class TvdbSeries {
  /// Creates a [TvdbSeries].
  const TvdbSeries({
    required this.id,
    required this.name,
    this.overview,
    this.image,
    this.firstAired,
    this.lastAired,
    this.status,
    this.originalLanguage,
    this.genres = const [],
    this.networks = const [],
    this.seasons = const [],
    this.aliases = const [],
  });

  /// TVDB numeric series identifier.
  final int id;

  /// Primary display name.
  final String name;

  /// Plot summary.
  final String? overview;

  /// URL for the primary series artwork.
  final String? image;

  /// First-aired date (ISO 8601 date string).
  final String? firstAired;

  /// Most recent episode air date (ISO 8601 date string).
  final String? lastAired;

  /// Airing status (e.g. `Continuing`, `Ended`).
  final String? status;

  /// Original language code (e.g. `eng`).
  final String? originalLanguage;

  /// Genre tags.
  final List<String> genres;

  /// Networks or streaming services that carry this series.
  final List<String> networks;

  /// Seasons belonging to this series.
  final List<TvdbSeason> seasons;

  /// Alternative names for this series.
  final List<String> aliases;

  @override
  String toString() => 'TvdbSeries($id, $name)';
}

/// A season within a TVDB series.
@immutable
class TvdbSeason {
  /// Creates a [TvdbSeason].
  const TvdbSeason({
    required this.id,
    required this.number,
    this.type,
    this.image,
    this.episodes = const [],
  });

  /// TVDB season identifier.
  final int id;

  /// Season number (0 for specials).
  final int number;

  /// Season type (e.g. `official`, `dvd`, `absolute`).
  final String? type;

  /// URL for the season artwork.
  final String? image;

  /// Episodes within this season (populated when fetched with extended data).
  final List<TvdbEpisode> episodes;

  @override
  String toString() => 'TvdbSeason($id, S$number)';
}

/// A single TV episode from TVDB.
@immutable
class TvdbEpisode {
  /// Creates a [TvdbEpisode].
  const TvdbEpisode({
    required this.id,
    required this.name,
    this.overview,
    this.number,
    this.seasonNumber,
    this.aired,
    this.runtime,
    this.image,
    this.isMovie,
  });

  /// TVDB episode identifier.
  final int id;

  /// Episode title.
  final String name;

  /// Episode synopsis.
  final String? overview;

  /// Episode number within its season.
  final int? number;

  /// Season number this episode belongs to.
  final int? seasonNumber;

  /// Air date (ISO 8601 date string).
  final String? aired;

  /// Runtime in minutes.
  final int? runtime;

  /// URL for the episode still/thumbnail.
  final String? image;

  /// Whether this episode is feature-length / a movie.
  final bool? isMovie;

  @override
  String toString() => 'TvdbEpisode($id, S${seasonNumber}E$number $name)';
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Error thrown for TVDB API failures.
///
/// Contains an optional HTTP [statusCode] when the error originates from
/// a non-200 response, and a human-readable [message].
@immutable
class TvdbException implements Exception {
  /// Creates a [TvdbException].
  const TvdbException({this.statusCode, required this.message});

  /// The HTTP status code, if the failure was an HTTP error.
  final int? statusCode;

  /// A human-readable description of the error.
  final String message;

  @override
  String toString() => statusCode != null
      ? 'TvdbException($statusCode: $message)'
      : 'TvdbException($message)';
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// HTTP client for the TVDB API v4.
///
/// Handles authentication (bearer token lifecycle), search, and detail
/// lookups for series, seasons, and episodes. All public methods return
/// [Result] so callers can handle errors without try/catch.
///
/// The token is obtained lazily on the first request and cached for 25 days
/// (the API issues tokens valid for ~30 days). If a request returns 401
/// the client re-authenticates once before propagating the error.
///
/// ```dart
/// final client = TvdbClient(apiKey: 'your-tvdb-v4-key');
///
/// // Search
/// final results = await client.search('Breaking Bad');
///
/// // Series detail
/// final series = await client.getSeries(81189);
///
/// // Season episodes
/// final episodes = await client.getSeriesEpisodes(81189, 1);
/// ```
class TvdbClient {
  /// Creates a [TvdbClient] with the given [apiKey].
  ///
  /// An optional [httpClient] may be provided for testing; when omitted a
  /// default [http.Client] is created internally.
  TvdbClient({required String apiKey, http.Client? httpClient})
      : _apiKey = apiKey,
        _http = httpClient ?? http.Client();

  static const _baseUrl = 'https://api4.thetvdb.com';
  static const _logName = 'TvdbClient';

  final String _apiKey;
  final http.Client _http;
  String? _token;
  DateTime? _tokenExpiry;

  // ---- Public API ---------------------------------------------------------

  /// Searches TVDB for series or movies matching [query].
  ///
  /// Optionally restrict results to a [type] (e.g. `series` or `movie`).
  /// Returns a list of [TvdbSearchResult] on success.
  ///
  /// ```dart
  /// final results = await client.search('Severance', type: 'series');
  /// ```
  Future<Result<List<TvdbSearchResult>>> search(
    String query, {
    String? type,
    int? limit,
  }) async {
    final params = <String, String>{
      'query': query,
      'type': ?type,
      'limit': ?limit?.toString(),
    };
    return _safeRequest(() async {
      final data = await _get('/v4/search', params);
      final items = data as List<dynamic>? ?? [];
      return items
          .cast<Map<String, dynamic>>()
          .map(_parseSearchResult)
          .toList(growable: false);
    });
  }

  /// Fetches extended details for the series with the given TVDB [id].
  ///
  /// Returns a [TvdbSeries] with seasons (but without full episode lists —
  /// use [getSeriesEpisodes] for per-season episode data).
  Future<Result<TvdbSeries>> getSeries(int id) => _safeRequest(() async {
        final data = await _get('/v4/series/$id/extended', {});
        return _parseSeries(data as Map<String, dynamic>);
      });

  /// Fetches episodes for [seriesId] in the given [seasonNumber].
  ///
  /// Uses the default episode ordering. Returns an empty list when the
  /// season does not exist.
  Future<Result<List<TvdbEpisode>>> getSeriesEpisodes(
    int seriesId,
    int seasonNumber,
  ) =>
      _safeRequest(() async {
        final data = await _get('/v4/series/$seriesId/episodes/default', {
          'season': seasonNumber.toString(),
        });
        final json = data as Map<String, dynamic>? ?? {};
        final episodeList = json['episodes'] as List<dynamic>? ?? [];
        return episodeList
            .cast<Map<String, dynamic>>()
            .map(_parseEpisode)
            .toList(growable: false);
      });

  /// Fetches extended details for a single episode by TVDB [id].
  Future<Result<TvdbEpisode>> getEpisode(int id) => _safeRequest(() async {
        final data = await _get('/v4/episodes/$id/extended', {});
        return _parseEpisode(data as Map<String, dynamic>);
      });

  /// Fetches extended details for a single season by TVDB [id].
  ///
  /// The returned [TvdbSeason] includes its episode list.
  Future<Result<TvdbSeason>> getSeason(int id) => _safeRequest(() async {
        final data = await _get('/v4/seasons/$id/extended', {});
        return _parseSeasonExtended(data as Map<String, dynamic>);
      });

  // ---- Authentication -----------------------------------------------------

  /// Authenticates with the TVDB v4 API and caches the bearer token.
  ///
  /// Called automatically before any request; callers do not need to invoke
  /// this directly. The token is refreshed 5 days before its ~30-day expiry.
  Future<void> _ensureAuthenticated() async {
    if (_token != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return;
    }
    final uri = Uri.parse('$_baseUrl/v4/login');
    final response = await _http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'apikey': _apiKey}),
    );
    if (response.statusCode != 200) {
      throw TvdbException(
        statusCode: response.statusCode,
        message: 'Authentication failed: HTTP ${response.statusCode}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final tokenData = body['data'] as Map<String, dynamic>?;
    final token = tokenData?['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const TvdbException(message: 'No token in authentication response');
    }
    _token = token;
    // Refresh well before the ~30-day expiry.
    _tokenExpiry = DateTime.now().add(const Duration(days: 25));
    dev.log('Authenticated with TVDB', name: _logName);
  }

  // ---- Internals ----------------------------------------------------------

  /// Headers included on every authenticated request.
  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': ?(_token != null ? 'Bearer $_token' : null),
      };

  /// Performs a GET request to [path] with [queryParams].
  ///
  /// Authenticates lazily, retries once on 401 (token expiry).
  /// Returns the `data` field from the JSON envelope.
  Future<dynamic> _get(String path, Map<String, String> queryParams) async {
    await _ensureAuthenticated();
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: queryParams);

    var response = await _http.get(uri, headers: _headers);

    // Retry once on 401 in case the token expired between checks.
    if (response.statusCode == 401) {
      _token = null;
      _tokenExpiry = null;
      await _ensureAuthenticated();
      response = await _http.get(uri, headers: _headers);
    }

    if (response.statusCode != 200) {
      throw TvdbException(
        statusCode: response.statusCode,
        message: 'HTTP ${response.statusCode} for $path',
      );
    }

    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw const TvdbException(message: 'Unexpected response format');
    }
    return json['data'];
  }

  /// Wraps an async operation in error handling, returning a [Result].
  Future<Result<T>> _safeRequest<T>(Future<T> Function() operation) async {
    try {
      return Result.success(await operation());
    } on TvdbException catch (e) {
      dev.log('TVDB API error: $e', name: _logName);
      return switch (e.statusCode) {
        404 => Result.failure(ServiceError.notFound(e.message)),
        401 || 403 => Result.failure(
            ServiceError.permissionDenied(e.message),
          ),
        _ => Result.failure(ServiceError.network(e.message)),
      };
    } on FormatException catch (e, st) {
      dev.log('TVDB parse error: $e', name: _logName, stackTrace: st);
      return Result.failure(
        ServiceError.unknown('Failed to parse TVDB response', e, st),
      );
    } on http.ClientException catch (e, st) {
      dev.log('HTTP error: $e', name: _logName, stackTrace: st);
      return Result.failure(ServiceError.network(e.message));
    } on Exception catch (e, st) {
      dev.log('Unexpected error: $e', name: _logName, stackTrace: st);
      return Result.failure(ServiceError.unknown(e.toString(), e, st));
    }
  }

  // ---- Parsers ------------------------------------------------------------

  TvdbSearchResult _parseSearchResult(Map<String, dynamic> json) {
    final aliasesRaw = json['aliases'] as List<dynamic>? ?? [];
    return TvdbSearchResult(
      tvdbId: json['tvdb_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name'] as String? ??
          json['translations']?['eng'] as String? ??
          '',
      overview: json['overview'] as String? ??
          json['overviews']?['eng'] as String?,
      year: json['year'] as String?,
      type: TvdbEntityType.fromString(json['type'] as String?),
      imageUrl: json['image_url'] as String? ?? json['thumbnail'] as String?,
      status: json['status'] as String?,
      network: json['network'] as String?,
      aliases: aliasesRaw
          .map((a) => a is String ? a : (a as Map<String, dynamic>?)?['name'])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  TvdbSeries _parseSeries(Map<String, dynamic> json) {
    final seasonsRaw = json['seasons'] as List<dynamic>? ?? [];
    final genresRaw = json['genres'] as List<dynamic>? ?? [];
    final networksRaw = json['networks'] as List<dynamic>? ?? [];
    final aliasesRaw = json['aliases'] as List<dynamic>? ?? [];
    final statusJson = json['status'] as Map<String, dynamic>?;

    return TvdbSeries(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      overview: json['overview'] as String?,
      image: json['image'] as String?,
      firstAired: json['firstAired'] as String?,
      lastAired: json['lastAired'] as String?,
      status: statusJson?['name'] as String? ?? json['status'] as String?,
      originalLanguage: json['originalLanguage'] as String?,
      genres: genresRaw
          .map((g) => (g as Map<String, dynamic>?)?['name'])
          .whereType<String>()
          .toList(growable: false),
      networks: networksRaw
          .map((n) => (n as Map<String, dynamic>?)?['name'])
          .whereType<String>()
          .toList(growable: false),
      seasons: seasonsRaw
          .map((s) => _parseSeason(s as Map<String, dynamic>))
          .toList(growable: false),
      aliases: aliasesRaw
          .map((a) => (a as Map<String, dynamic>?)?['name'])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  TvdbSeason _parseSeason(Map<String, dynamic> json) => TvdbSeason(
        id: json['id'] as int? ?? 0,
        number: json['number'] as int? ?? 0,
        type: (json['type'] as Map<String, dynamic>?)?['name'] as String? ??
            json['type'] as String?,
        image: json['image'] as String?,
      );

  TvdbSeason _parseSeasonExtended(Map<String, dynamic> json) {
    final episodesRaw = json['episodes'] as List<dynamic>? ?? [];
    return TvdbSeason(
      id: json['id'] as int? ?? 0,
      number: json['number'] as int? ?? 0,
      type: (json['type'] as Map<String, dynamic>?)?['name'] as String? ??
          json['type'] as String?,
      image: json['image'] as String?,
      episodes: episodesRaw
          .map((e) => _parseEpisode(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  TvdbEpisode _parseEpisode(Map<String, dynamic> json) => TvdbEpisode(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        overview: json['overview'] as String?,
        number: json['number'] as int?,
        seasonNumber: json['seasonNumber'] as int?,
        aired: json['aired'] as String?,
        runtime: json['runtime'] as int?,
        image: json['image'] as String?,
        isMovie: json['isMovie'] as bool?,
      );
}
