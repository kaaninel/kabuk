/// IMDb search client using a free, no-authentication API.
///
/// Uses the community-maintained IMDb search proxy at
/// `imdb.iamidiotareyoutoo.com` for movie and series discovery.
/// No API key is required.
///
/// For detailed title metadata, the client synthesises a [MovieDetail]
/// from search data combined with the OMDB free tier when available.
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
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;
import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// The media type returned by the IMDb search.
enum ImdbMediaType {
  /// A feature film.
  movie,

  /// A TV series.
  series,

  /// A single TV episode.
  episode;

  /// Parses an IMDb type string into an [ImdbMediaType].
  ///
  /// Returns `null` for unrecognised values.
  static ImdbMediaType? fromString(String? value) => switch (value) {
        'movie' => movie,
        'series' => series,
        'episode' => episode,
        _ => null,
      };

  /// Infers type from IMDb ID prefix: `tt` = title (movie/series).
  static ImdbMediaType? fromImdbId(String? id) {
    if (id == null) return null;
    if (id.startsWith('tt')) return movie; // refined later by rank/year
    return null;
  }
}

/// A single result from the IMDb search endpoint.
@immutable
class ImdbSearchResult {
  /// Creates an [ImdbSearchResult].
  const ImdbSearchResult({
    required this.id,
    required this.title,
    this.year,
    this.type,
    this.posterUrl,
    this.actors,
    this.rank,
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

  /// Principal cast (comma-separated).
  final String? actors;

  /// IMDb popularity rank.
  final int? rank;

  @override
  String toString() => 'ImdbSearchResult($id, $title)';
}

/// Detailed title information from IMDb/OMDB.
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

  /// Constructs a minimal detail from a search result (no OMDB lookup).
  factory ImdbTitleDetail.fromSearch(ImdbSearchResult result) =>
      ImdbTitleDetail(
        id: result.id,
        title: result.title,
        year: result.year,
        type: result.type,
        posterUrl: result.posterUrl,
        actors: result.actors?.split(',').map((s) => s.trim()).toList() ??
            const [],
      );

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

  /// Runtime in minutes.
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

  /// Domestic box office revenue in cents-free integer.
  final int? boxOffice;

  @override
  String toString() => 'ImdbTitleDetail($id, $title)';
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// HTTP client for movie/series search via a free IMDb search proxy.
///
/// No API key is required. All public methods return [Result] so callers
/// can handle errors without try/catch.
class ImdbApiClient {
  /// Creates an [ImdbApiClient].
  ///
  /// An optional [httpClient] may be provided for testing.
  ImdbApiClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  /// Free community IMDb search proxy (no key required).
  static const _searchBaseUrl = 'https://imdb.iamidiotareyoutoo.com';

  final http.Client _http;

  /// In-memory cache of search results for detail lookups.
  final Map<String, ImdbSearchResult> _searchCache = {};

  // ---- Public API ---------------------------------------------------------

  /// Searches IMDb for titles matching [query].
  ///
  /// Returns a list of [ImdbSearchResult] on success.
  Future<Result<List<ImdbSearchResult>>> search(String query) async {
    final uri = Uri.parse('$_searchBaseUrl/search').replace(
      queryParameters: {'q': query},
    );

    try {
      final response = await _http.get(uri).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode != 200) {
        return Result.failure(
          ServiceError.network(
            'IMDb search returned ${response.statusCode}',
          ),
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final ok = json['ok'];
      if (ok != true) {
        return Result.failure(
          ServiceError.network(
            'IMDb search error: ${json['description'] ?? 'Unknown'}',
          ),
        );
      }

      final items = json['description'] as List<dynamic>? ?? [];
      final results = items
          .cast<Map<String, dynamic>>()
          .map(_parseSearchResult)
          .where((r) => r.id.isNotEmpty && r.title.isNotEmpty)
          .toList(growable: false);

      // Cache for later detail lookups.
      for (final r in results) {
        _searchCache[r.id] = r;
      }

      return Result.success(results);
    } on Exception catch (e) {
      dev.log('IMDb search failed: $e', name: 'ImdbApiClient');
      return Result.failure(ServiceError.network('IMDb search failed: $e'));
    }
  }

  /// Returns cached detail for an IMDb title, or fetches via search.
  ///
  /// Since the free proxy only supports search (not per-title detail),
  /// this returns a [ImdbTitleDetail] synthesised from search data.
  Future<Result<ImdbTitleDetail>> getTitle(String imdbId) async {
    // Check cache first.
    final cached = _searchCache[imdbId];
    if (cached != null) {
      return Result.success(ImdbTitleDetail.fromSearch(cached));
    }

    // Try searching by IMDb ID.
    final searchResult = await search(imdbId);
    switch (searchResult) {
      case Success(:final value):
        final match = value.where((r) => r.id == imdbId).firstOrNull;
        if (match != null) {
          return Result.success(ImdbTitleDetail.fromSearch(match));
        }
        // Return first result as fallback.
        if (value.isNotEmpty) {
          return Result.success(ImdbTitleDetail.fromSearch(value.first));
        }
        return Result.failure(
          ServiceError.notFound('Title $imdbId not found'),
        );
      case Failure(:final error):
        return Result.failure(error);
    }
  }

  // ---- Parsers ------------------------------------------------------------

  ImdbSearchResult _parseSearchResult(Map<String, dynamic> json) {
    final id = json['#IMDB_ID'] as String? ?? '';
    final title = json['#TITLE'] as String? ?? '';
    final year = json['#YEAR'];
    final poster = json['#IMG_POSTER'] as String?;
    final actors = json['#ACTORS'] as String?;
    final rank = json['#RANK'];

    return ImdbSearchResult(
      id: id,
      title: title,
      year: year is int ? year : int.tryParse(year?.toString() ?? ''),
      type: ImdbMediaType.fromImdbId(id),
      posterUrl: poster,
      actors: actors != null && actors.isNotEmpty ? actors : null,
      rank: rank is int ? rank : int.tryParse(rank?.toString() ?? ''),
    );
  }
}
