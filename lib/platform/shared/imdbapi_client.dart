/// IMDbAPI.dev client for movie and series metadata.
///
/// Uses the free, no-authentication-required IMDbAPI.dev REST API (v2).
/// This is a raw API client — it does **not** implement a service interface.
///
/// ```dart
/// final client = ImdbApiClient();
/// final results = await client.search('Inception');
/// switch (results) {
///   case Success(:final value):
///     for (final r in value) print('${r.title} (${r.year})');
///   case Failure(:final error):
///     print('Search failed: $error');
/// }
/// ```
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// The media type returned by the IMDbAPI.
enum ImdbMediaType {
  /// A feature film.
  movie,

  /// A TV series.
  series,

  /// A single TV episode.
  episode;

  /// Parses an IMDbAPI type string into an [ImdbMediaType].
  ///
  /// Returns `null` for unrecognised values.
  static ImdbMediaType? fromString(String? value) => switch (value) {
        'movie' => movie,
        'series' => series,
        'episode' => episode,
        _ => null,
      };
}

/// A single result from the IMDbAPI search endpoint.
@immutable
class ImdbSearchResult {
  /// Creates an [ImdbSearchResult].
  const ImdbSearchResult({
    required this.id,
    required this.title,
    this.year,
    this.type,
    this.posterUrl,
  });

  /// IMDb identifier (e.g. `tt1375666`).
  final String id;

  /// Primary display title.
  final String title;

  /// Release year, if available.
  final int? year;

  /// The media type (movie, series, or episode).
  final ImdbMediaType? type;

  /// URL for the poster image.
  final String? posterUrl;

  @override
  String toString() => 'ImdbSearchResult($id, $title)';
}

/// Detailed title information from the IMDbAPI.
@immutable
class ImdbTitleDetail {
  /// Creates an [ImdbTitleDetail].
  const ImdbTitleDetail({
    required this.id,
    required this.title,
    this.year,
    this.type,
    this.rated,
    this.releasedDate,
    this.runtimeMinutes,
    this.genres = const [],
    this.director,
    this.writers = const [],
    this.actors = const [],
    this.plot,
    this.language,
    this.country,
    this.posterUrl,
    this.rating,
    this.ratingCount,
    this.metascore,
    this.boxOffice,
  });

  /// IMDb identifier (e.g. `tt1375666`).
  final String id;

  /// Primary display title.
  final String title;

  /// Release year, if available.
  final int? year;

  /// The media type (movie, series, or episode).
  final ImdbMediaType? type;

  /// Content rating (e.g. `PG-13`, `R`).
  final String? rated;

  /// Release date, if parseable.
  final DateTime? releasedDate;

  /// Runtime in minutes, parsed from strings like `"148 min"`.
  final int? runtimeMinutes;

  /// Genre tags.
  final List<String> genres;

  /// Director name.
  final String? director;

  /// Writer names.
  final List<String> writers;

  /// Principal cast members.
  final List<String> actors;

  /// Plot synopsis.
  final String? plot;

  /// Primary language.
  final String? language;

  /// Country of origin.
  final String? country;

  /// URL for the poster image.
  final String? posterUrl;

  /// Average user rating (e.g. `8.8`).
  final double? rating;

  /// Number of user ratings.
  final int? ratingCount;

  /// Metacritic score (0–100).
  final int? metascore;

  /// Domestic box office revenue in cents-free integer (e.g. `292576195`).
  final int? boxOffice;

  @override
  String toString() => 'ImdbTitleDetail($id, $title)';
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// HTTP client for the IMDbAPI.dev v2 REST API.
///
/// No API key is required. All public methods return [Result] so callers
/// can handle errors without try/catch.
///
/// ```dart
/// final client = ImdbApiClient();
/// final detail = await client.getTitle('tt1375666');
/// ```
class ImdbApiClient {
  /// Creates an [ImdbApiClient].
  ///
  /// An optional [httpClient] may be provided for testing; when omitted a
  /// default [http.Client] is created internally.
  ImdbApiClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  static const _baseUrl = 'https://api.imdbapi.dev/v2';

  final http.Client _http;

  // ---- Public API ---------------------------------------------------------

  /// Searches IMDb for titles matching [query].
  ///
  /// Returns a list of [ImdbSearchResult] on success.
  ///
  /// ```dart
  /// final results = await client.search('Inception');
  /// ```
  Future<Result<List<ImdbSearchResult>>> search(String query) async {
    final uri = Uri.parse('$_baseUrl/search').replace(
      queryParameters: {'q': query},
    );

    return _get(uri, (json) {
      final items = json['data'] as List<dynamic>? ?? [];
      return items
          .cast<Map<String, dynamic>>()
          .map(_parseSearchResult)
          .toList(growable: false);
    });
  }

  /// Fetches detailed metadata for the title with the given [imdbId].
  ///
  /// The [imdbId] should be a standard IMDb identifier (e.g. `tt1375666`).
  ///
  /// ```dart
  /// final detail = await client.getTitle('tt1375666');
  /// ```
  Future<Result<ImdbTitleDetail>> getTitle(String imdbId) async {
    final uri = Uri.parse('$_baseUrl/title/$imdbId');

    return _get(uri, (json) {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      return _parseTitleDetail(data);
    });
  }

  // ---- HTTP helpers -------------------------------------------------------

  /// Performs a GET request and parses the JSON response with [parse].
  ///
  /// Returns [Result.failure] for HTTP errors, API-level errors (`ok: false`),
  /// JSON decode failures, and unexpected exceptions.
  Future<Result<T>> _get<T>(
    Uri uri,
    T Function(Map<String, dynamic>) parse,
  ) async {
    try {
      final response = await _http.get(uri);

      if (response.statusCode == 404) {
        return Result.failure(
          ServiceError.notFound('IMDbAPI resource: $uri'),
        );
      }

      if (response.statusCode != 200) {
        return Result.failure(
          ServiceError.network(
            'IMDbAPI returned ${response.statusCode}: '
            '${response.reasonPhrase}',
          ),
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      // The API wraps responses in `{"ok": true/false, ...}`.
      final ok = json['ok'];
      if (ok == false) {
        final message =
            json['error'] as String? ?? json['message'] as String? ?? 'Unknown API error';
        return Result.failure(ServiceError.network('IMDbAPI error: $message'));
      }

      return Result.success(parse(json));
    } on http.ClientException catch (e) {
      return Result.failure(ServiceError.network('HTTP error: $e'));
    } on FormatException catch (e) {
      return Result.failure(
        ServiceError.unknown('Failed to parse IMDbAPI response', e),
      );
    } on Exception catch (e, st) {
      return Result.failure(ServiceError.unknown('$e', e, st));
    }
  }

  // ---- Parsers ------------------------------------------------------------

  ImdbSearchResult _parseSearchResult(Map<String, dynamic> json) =>
      ImdbSearchResult(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        year: _toInt(json['year']),
        type: ImdbMediaType.fromString(json['type'] as String?),
        posterUrl: _naString(json['poster'] as String?),
      );

  ImdbTitleDetail _parseTitleDetail(Map<String, dynamic> json) {
    final ratingMap = json['rating'] as Map<String, dynamic>?;

    return ImdbTitleDetail(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      year: _toInt(json['year']),
      type: ImdbMediaType.fromString(json['type'] as String?),
      rated: _naString(json['rated'] as String?),
      releasedDate: _parseDate(json['released'] as String?),
      runtimeMinutes: _parseRuntime(json['runtime'] as String?),
      genres: _toStringList(json['genres']),
      director: _naString(json['director'] as String?),
      writers: _toStringList(json['writers']),
      actors: _toStringList(json['actors']),
      plot: _naString(json['plot'] as String?),
      language: _naString(json['language'] as String?),
      country: _naString(json['country'] as String?),
      posterUrl: _naString(json['poster'] as String?),
      rating: _toDouble(ratingMap?['average']),
      ratingCount: _toInt(ratingMap?['count']),
      metascore: _toInt(json['metascore']),
      boxOffice: _parseBoxOffice(json['boxOffice'] as String?),
    );
  }

  // ---- Value helpers ------------------------------------------------------

  /// Returns `null` when [value] is `null`, empty, or the literal `"N/A"`.
  static String? _naString(String? value) {
    if (value == null || value.isEmpty || value == 'N/A') return null;
    return value;
  }

  /// Safely parses a date string (ISO 8601 `YYYY-MM-DD` or similar).
  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty || value == 'N/A') return null;
    try {
      return DateTime.parse(value);
    } on FormatException {
      return null;
    }
  }

  /// Parses a runtime string like `"148 min"` into an integer `148`.
  static int? _parseRuntime(String? value) {
    if (value == null || value.isEmpty || value == 'N/A') return null;
    final match = RegExp(r'(\d+)').firstMatch(value);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  /// Parses a box-office string like `"$292,576,195"` into `292576195`.
  static int? _parseBoxOffice(String? value) {
    if (value == null || value.isEmpty || value == 'N/A') return null;
    final cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
    return cleaned.isNotEmpty ? int.tryParse(cleaned) : null;
  }

  /// Coerces a JSON value to [int], handling `int`, `double`, and `String`.
  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString());
  }

  /// Coerces a JSON value to [double], handling `int`, `double`, and `String`.
  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// Converts a JSON value to a `List<String>`.
  ///
  /// Handles both `List<dynamic>` (array of strings) and a comma-separated
  /// `String` fallback for maximum API compatibility.
  static List<String> _toStringList(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map((e) => e?.toString())
          .whereType<String>()
          .where((s) => s.isNotEmpty && s != 'N/A')
          .toList(growable: false);
    }
    if (value is String && value.isNotEmpty && value != 'N/A') {
      return value
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }
}
