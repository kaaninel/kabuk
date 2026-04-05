/// TVmaze API client for TV show search and detail retrieval.
///
/// TVmaze is a free, community-driven TV information API that requires
/// no authentication. Provides show search, detail lookups, season
/// listings, and episode data.
///
/// See: https://www.tvmaze.com/api
///
/// ```dart
/// final client = TvMazeClient();
/// final results = await client.searchShows('Breaking Bad');
/// switch (results) {
///   case Success(:final value):
///     for (final show in value) print('${show.name} (${show.status})');
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

/// External IDs for a TVmaze show.
@immutable
class TvMazeExternals {
  /// Creates a [TvMazeExternals].
  const TvMazeExternals({this.tvrage, this.thetvdb, this.imdb});

  /// TVRage numeric identifier.
  final int? tvrage;

  /// TheTVDB numeric identifier.
  final int? thetvdb;

  /// IMDb identifier (e.g. `tt1553656`).
  final String? imdb;

  @override
  String toString() => 'TvMazeExternals(tvrage: $tvrage, '
      'thetvdb: $thetvdb, imdb: $imdb)';
}

/// A TV show from the TVmaze API.
@immutable
class TvMazeShow {
  /// Creates a [TvMazeShow].
  const TvMazeShow({
    required this.id,
    required this.name,
    this.genres = const [],
    this.status,
    this.runtime,
    this.premiered,
    this.ended,
    this.rating,
    this.networkName,
    this.imageUrl,
    this.imageOriginalUrl,
    this.summary,
    this.externals = const TvMazeExternals(),
  });

  /// TVmaze numeric identifier.
  final int id;

  /// Primary display name.
  final String name;

  /// Genre tags (e.g. `Drama`, `Science-Fiction`).
  final List<String> genres;

  /// Airing status (e.g. `Running`, `Ended`).
  final String? status;

  /// Episode runtime in minutes.
  final int? runtime;

  /// Premiere date (ISO 8601 date string).
  final String? premiered;

  /// Final episode date (ISO 8601 date string).
  final String? ended;

  /// Average user rating (0–10 scale).
  final double? rating;

  /// Primary network name (e.g. `CBS`, `HBO`).
  final String? networkName;

  /// Medium-resolution poster image URL.
  final String? imageUrl;

  /// Original-resolution poster image URL.
  final String? imageOriginalUrl;

  /// Plain-text synopsis (HTML tags stripped).
  final String? summary;

  /// External IDs (TVRage, TheTVDB, IMDb).
  final TvMazeExternals externals;

  @override
  String toString() => 'TvMazeShow($id, $name)';
}

/// A season within a TVmaze show.
@immutable
class TvMazeSeason {
  /// Creates a [TvMazeSeason].
  const TvMazeSeason({
    required this.id,
    required this.number,
    this.name,
    this.episodeOrder,
    this.premiereDate,
    this.endDate,
    this.imageUrl,
  });

  /// TVmaze season identifier.
  final int id;

  /// Season number (1-based).
  final int number;

  /// Optional season name.
  final String? name;

  /// Number of episodes in this season.
  final int? episodeOrder;

  /// Premiere date of the first episode (ISO 8601 date string).
  final String? premiereDate;

  /// Air date of the final episode (ISO 8601 date string).
  final String? endDate;

  /// Medium-resolution season artwork URL.
  final String? imageUrl;

  @override
  String toString() => 'TvMazeSeason($id, S$number)';
}

/// A single TV episode from TVmaze.
@immutable
class TvMazeEpisode {
  /// Creates a [TvMazeEpisode].
  const TvMazeEpisode({
    required this.id,
    required this.name,
    this.season,
    this.number,
    this.airdate,
    this.runtime,
    this.rating,
    this.imageUrl,
    this.summary,
  });

  /// TVmaze episode identifier.
  final int id;

  /// Episode title.
  final String name;

  /// Season number this episode belongs to.
  final int? season;

  /// Episode number within its season.
  final int? number;

  /// Air date (ISO 8601 date string).
  final String? airdate;

  /// Runtime in minutes.
  final int? runtime;

  /// Average user rating (0–10 scale).
  final double? rating;

  /// Medium-resolution episode still URL.
  final String? imageUrl;

  /// Plain-text episode synopsis (HTML tags stripped).
  final String? summary;

  @override
  String toString() => 'TvMazeEpisode($id, S${season}E$number $name)';
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Error thrown for TVmaze API failures.
///
/// Contains an optional HTTP [statusCode] when the error originates from
/// a non-2xx response, and a human-readable [message].
@immutable
class TvMazeException implements Exception {
  /// Creates a [TvMazeException].
  const TvMazeException({this.statusCode, required this.message});

  /// The HTTP status code, if the failure was an HTTP error.
  final int? statusCode;

  /// A human-readable description of the error.
  final String message;

  @override
  String toString() => statusCode != null
      ? 'TvMazeException($statusCode: $message)'
      : 'TvMazeException($message)';
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// Regex for stripping HTML tags from summary fields.
final RegExp _htmlTagPattern = RegExp(r'<[^>]*>');

/// HTTP client for the TVmaze API.
///
/// TVmaze is a free API — no API key or authentication is required.
/// All public methods return [Result] so callers can handle errors
/// without try/catch.
///
/// The client respects TVmaze's rate limiting (HTTP 429) and maps it
/// to a [ServiceError.network] with a descriptive message.
///
/// ```dart
/// final client = TvMazeClient();
///
/// // Search
/// final results = await client.searchShows('Severance');
///
/// // Show detail
/// final show = await client.getShow(42);
///
/// // Seasons and episodes
/// final seasons = await client.getSeasons(42);
/// final episodes = await client.getSeasonEpisodes(seasons.first.id);
/// ```
class TvMazeClient {
  /// Creates a [TvMazeClient].
  ///
  /// An optional [httpClient] may be provided for testing; when omitted a
  /// default [http.Client] is created internally.
  TvMazeClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  static const _baseUrl = 'https://api.tvmaze.com';
  static const _logName = 'TvMazeClient';

  final http.Client _http;

  // ---- Public API ---------------------------------------------------------

  /// Searches TVmaze for shows matching [query].
  ///
  /// Returns a list of [TvMazeShow] ordered by relevance score.
  /// An empty query returns an empty list.
  ///
  /// ```dart
  /// final results = await client.searchShows('Breaking Bad');
  /// ```
  Future<Result<List<TvMazeShow>>> searchShows(String query) async {
    if (query.trim().isEmpty) {
      return const Result.success([]);
    }
    return _safeRequest(() async {
      final data = await _get('/search/shows', {'q': query});
      final items = data as List<dynamic>? ?? [];
      return items.cast<Map<String, dynamic>>().map((entry) {
        final showJson = entry['show'] as Map<String, dynamic>? ?? {};
        return _parseShow(showJson);
      }).toList(growable: false);
    });
  }

  /// Fetches detailed information for the show with the given TVmaze [id].
  ///
  /// Returns a [TvMazeShow] with all available metadata.
  Future<Result<TvMazeShow>> getShow(int id) => _safeRequest(() async {
        final data = await _get('/shows/$id', {});
        return _parseShow(data as Map<String, dynamic>);
      });

  /// Fetches all seasons for the show with the given [showId].
  ///
  /// Uses the embedded seasons endpoint for a single HTTP round-trip.
  /// Returns a list of [TvMazeSeason] ordered by season number.
  Future<Result<List<TvMazeSeason>>> getSeasons(int showId) =>
      _safeRequest(() async {
        final data = await _get('/shows/$showId', {'embed': 'seasons'});
        final json = data as Map<String, dynamic>? ?? {};
        final embedded = json['_embedded'] as Map<String, dynamic>? ?? {};
        final seasonsRaw = embedded['seasons'] as List<dynamic>? ?? [];
        return seasonsRaw
            .cast<Map<String, dynamic>>()
            .map(_parseSeason)
            .toList(growable: false);
      });

  /// Fetches all episodes for the season with the given TVmaze [seasonId].
  ///
  /// Returns a list of [TvMazeEpisode] ordered by episode number.
  Future<Result<List<TvMazeEpisode>>> getSeasonEpisodes(int seasonId) =>
      _safeRequest(() async {
        final data = await _get('/seasons/$seasonId/episodes', {});
        final items = data as List<dynamic>? ?? [];
        return items
            .cast<Map<String, dynamic>>()
            .map(_parseEpisode)
            .toList(growable: false);
      });

  // ---- Internals ----------------------------------------------------------

  /// Performs a GET request to [path] with optional [queryParams].
  ///
  /// Returns the decoded JSON body directly (TVmaze has no envelope).
  Future<dynamic> _get(String path, Map<String, String> queryParams) async {
    final uri =
        Uri.parse('$_baseUrl$path').replace(queryParameters: queryParams);
    final response = await _http.get(uri, headers: const {
      'Accept': 'application/json',
    });

    if (response.statusCode == 429) {
      throw const TvMazeException(
        statusCode: 429,
        message: 'TVmaze rate limit exceeded — please retry later',
      );
    }

    if (response.statusCode != 200) {
      throw TvMazeException(
        statusCode: response.statusCode,
        message: 'HTTP ${response.statusCode} for $path',
      );
    }

    return jsonDecode(response.body);
  }

  /// Wraps an async operation in error handling, returning a [Result].
  Future<Result<T>> _safeRequest<T>(Future<T> Function() operation) async {
    try {
      return Result.success(await operation());
    } on TvMazeException catch (e) {
      dev.log('TVmaze API error: $e', name: _logName);
      return switch (e.statusCode) {
        404 => Result.failure(ServiceError.notFound(e.message)),
        429 => Result.failure(ServiceError.network(e.message)),
        _ => Result.failure(ServiceError.network(e.message)),
      };
    } on FormatException catch (e, st) {
      dev.log('TVmaze parse error: $e', name: _logName, stackTrace: st);
      return Result.failure(
        ServiceError.unknown('Failed to parse TVmaze response', e, st),
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

  /// Strips HTML tags from a string, returning `null` for empty results.
  static String? _stripHtml(String? html) {
    if (html == null || html.isEmpty) return null;
    final text = html.replaceAll(_htmlTagPattern, '').trim();
    return text.isEmpty ? null : text;
  }

  /// Safely parses a numeric value that may arrive as int or double.
  static double? _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Safely parses an int that may arrive as int, double, or String.
  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  TvMazeShow _parseShow(Map<String, dynamic> json) {
    final genresRaw = json['genres'] as List<dynamic>? ?? [];
    final ratingJson = json['rating'] as Map<String, dynamic>?;
    final networkJson = json['network'] as Map<String, dynamic>?;
    final imageJson = json['image'] as Map<String, dynamic>?;
    final externalsJson = json['externals'] as Map<String, dynamic>?;

    return TvMazeShow(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      genres: genresRaw.whereType<String>().toList(growable: false),
      status: json['status'] as String?,
      runtime: _parseInt(json['runtime']),
      premiered: json['premiered'] as String?,
      ended: json['ended'] as String?,
      rating: _parseDouble(ratingJson?['average']),
      networkName: networkJson?['name'] as String?,
      imageUrl: imageJson?['medium'] as String?,
      imageOriginalUrl: imageJson?['original'] as String?,
      summary: _stripHtml(json['summary'] as String?),
      externals: TvMazeExternals(
        tvrage: _parseInt(externalsJson?['tvrage']),
        thetvdb: _parseInt(externalsJson?['thetvdb']),
        imdb: externalsJson?['imdb'] as String?,
      ),
    );
  }

  TvMazeSeason _parseSeason(Map<String, dynamic> json) {
    final imageJson = json['image'] as Map<String, dynamic>?;
    return TvMazeSeason(
      id: json['id'] as int? ?? 0,
      number: json['number'] as int? ?? 0,
      name: json['name'] as String?,
      episodeOrder: _parseInt(json['episodeOrder']),
      premiereDate: json['premiereDate'] as String?,
      endDate: json['endDate'] as String?,
      imageUrl: imageJson?['medium'] as String?,
    );
  }

  TvMazeEpisode _parseEpisode(Map<String, dynamic> json) {
    final ratingJson = json['rating'] as Map<String, dynamic>?;
    final imageJson = json['image'] as Map<String, dynamic>?;
    return TvMazeEpisode(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      season: _parseInt(json['season']),
      number: _parseInt(json['number']),
      airdate: json['airdate'] as String?,
      runtime: _parseInt(json['runtime']),
      rating: _parseDouble(ratingJson?['average']),
      imageUrl: imageJson?['medium'] as String?,
      summary: _stripHtml(json['summary'] as String?),
    );
  }
}
