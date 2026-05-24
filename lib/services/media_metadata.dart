/// Media metadata service — abstract interface for TV/movie metadata lookup.
///
/// Provides search, detail retrieval, and season/episode browsing for
/// TV series and movies. Implementations may use TMDB, TVDB, or other
/// metadata APIs.
///
/// Platform implementations live in `lib/platform/`.
/// Agents access this only through `AgentContext`.
library;

import 'package:kabuk/config/result.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// The type of media content.
enum MediaType {
  /// A feature film.
  movie,

  /// A television series.
  tvSeries,
}

/// Predefined image size tiers for poster/backdrop URLs.
enum MediaImageSize {
  /// Small thumbnail (~185px wide).
  small,

  /// Medium display (~342px wide).
  medium,

  /// Large display (~500px wide).
  large,

  /// Original resolution.
  original,
}

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// A single result from a multi-search query.
@immutable
class MediaSearchResult {
  /// Creates a [MediaSearchResult].
  const MediaSearchResult({
    required this.id,
    required this.title,
    required this.mediaType,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseYear,
    this.voteAverage,
    this.voteCount,
    this.genreIds = const [],
    this.popularity,
    this.imdbId,
  });

  /// Provider-specific numeric identifier.
  final int id;

  /// Localised display title.
  final String title;

  /// Whether this result is a movie or TV series.
  final MediaType mediaType;

  /// Original-language title, if different from [title].
  final String? originalTitle;

  /// Short plot summary.
  final String? overview;

  /// Relative path to the poster image (use [MediaMetadataService.imageUrl]).
  final String? posterPath;

  /// Relative path to the backdrop image (use [MediaMetadataService.imageUrl]).
  final String? backdropPath;

  /// Year of first release or first air date.
  final int? releaseYear;

  /// Average user rating (0–10 scale).
  final double? voteAverage;

  /// Total number of user votes.
  final int? voteCount;

  /// Provider-specific genre identifiers.
  final List<int> genreIds;

  /// Provider-computed popularity score.
  final double? popularity;

  /// IMDb identifier (e.g. `tt1375666`), when available.
  final String? imdbId;

  @override
  String toString() => 'MediaSearchResult(id: $id, title: $title, '
      'mediaType: $mediaType)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaSearchResult &&
          id == other.id &&
          mediaType == other.mediaType;

  @override
  int get hashCode => Object.hash(id, mediaType);
}

/// Detailed information about a TV series.
@immutable
class TvSeriesDetail {
  /// Creates a [TvSeriesDetail].
  const TvSeriesDetail({
    required this.id,
    required this.name,
    this.originalName,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.firstAirDate,
    this.lastAirDate,
    this.status,
    this.numberOfSeasons = 0,
    this.numberOfEpisodes = 0,
    this.seasons = const [],
    this.genres = const [],
    this.networks = const [],
    this.voteAverage,
    this.externalIds,
    this.homepage,
  });

  /// Provider-specific numeric identifier.
  final int id;

  /// Localised series name.
  final String name;

  /// Original-language series name, if different from [name].
  final String? originalName;

  /// Short plot summary.
  final String? overview;

  /// Relative path to the poster image.
  final String? posterPath;

  /// Relative path to the backdrop image.
  final String? backdropPath;

  /// Date the first episode aired.
  final DateTime? firstAirDate;

  /// Date the most recent episode aired.
  final DateTime? lastAirDate;

  /// Series status — e.g. `"Returning Series"`, `"Ended"`, `"Canceled"`.
  final String? status;

  /// Total number of seasons.
  final int numberOfSeasons;

  /// Total number of episodes across all seasons.
  final int numberOfEpisodes;

  /// Summary information for each season.
  final List<TvSeasonSummary> seasons;

  /// Human-readable genre names.
  final List<String> genres;

  /// Human-readable network names.
  final List<String> networks;

  /// Average user rating (0–10 scale).
  final double? voteAverage;

  /// External identifiers (IMDB, TVDB, etc.).
  final ExternalIds? externalIds;

  /// Official homepage URL.
  final String? homepage;

  @override
  String toString() => 'TvSeriesDetail(id: $id, name: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TvSeriesDetail && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Summary information about a single season within a TV series.
@immutable
class TvSeasonSummary {
  /// Creates a [TvSeasonSummary].
  const TvSeasonSummary({
    required this.id,
    required this.seasonNumber,
    this.name,
    this.overview,
    this.posterPath,
    this.airDate,
    this.episodeCount = 0,
  });

  /// Provider-specific season identifier.
  final int id;

  /// Season number (0 for specials).
  final int seasonNumber;

  /// Display name (e.g. `"Season 1"` or `"Specials"`).
  final String? name;

  /// Season overview / description.
  final String? overview;

  /// Relative path to the season poster image.
  final String? posterPath;

  /// Air date of the season premiere.
  final DateTime? airDate;

  /// Number of episodes in this season.
  final int episodeCount;

  @override
  String toString() => 'TvSeasonSummary(id: $id, season: $seasonNumber)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TvSeasonSummary && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Full detail for a season including all episodes.
@immutable
class TvSeasonDetail {
  /// Creates a [TvSeasonDetail].
  const TvSeasonDetail({
    required this.id,
    required this.seasonNumber,
    this.name,
    this.overview,
    this.posterPath,
    this.airDate,
    this.episodes = const [],
  });

  /// Provider-specific season identifier.
  final int id;

  /// Season number (0 for specials).
  final int seasonNumber;

  /// Display name.
  final String? name;

  /// Season overview / description.
  final String? overview;

  /// Relative path to the season poster image.
  final String? posterPath;

  /// Air date of the season premiere.
  final DateTime? airDate;

  /// All episodes in this season.
  final List<TvEpisode> episodes;

  @override
  String toString() =>
      'TvSeasonDetail(id: $id, season: $seasonNumber, '
      'episodes: ${episodes.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TvSeasonDetail && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A single TV episode.
@immutable
class TvEpisode {
  /// Creates a [TvEpisode].
  const TvEpisode({
    required this.id,
    required this.episodeNumber,
    required this.seasonNumber,
    this.name,
    this.overview,
    this.stillPath,
    this.airDate,
    this.voteAverage,
    this.runtime,
  });

  /// Provider-specific episode identifier.
  final int id;

  /// Episode number within its season.
  final int episodeNumber;

  /// Season number this episode belongs to.
  final int seasonNumber;

  /// Episode title.
  final String? name;

  /// Short plot summary.
  final String? overview;

  /// Relative path to an episode still / screenshot image.
  final String? stillPath;

  /// Original air date.
  final DateTime? airDate;

  /// Average user rating (0–10 scale).
  final double? voteAverage;

  /// Runtime in minutes.
  final int? runtime;

  /// Formats as `SxxExx` (e.g. `S01E05`).
  String get episodeCode =>
      'S${seasonNumber.toString().padLeft(2, '0')}'
      'E${episodeNumber.toString().padLeft(2, '0')}';

  @override
  String toString() => 'TvEpisode(id: $id, $episodeCode, name: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TvEpisode && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Detailed information about a movie.
@immutable
class MovieDetail {
  /// Creates a [MovieDetail].
  const MovieDetail({
    required this.id,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.runtime,
    this.genres = const [],
    this.voteAverage,
    this.externalIds,
    this.homepage,
    this.tagline,
    this.budget,
    this.revenue,
  });

  /// Provider-specific numeric identifier.
  final int id;

  /// Localised display title.
  final String title;

  /// Original-language title, if different from [title].
  final String? originalTitle;

  /// Short plot summary.
  final String? overview;

  /// Relative path to the poster image.
  final String? posterPath;

  /// Relative path to the backdrop image.
  final String? backdropPath;

  /// Theatrical release date.
  final DateTime? releaseDate;

  /// Runtime in minutes.
  final int? runtime;

  /// Human-readable genre names.
  final List<String> genres;

  /// Average user rating (0–10 scale).
  final double? voteAverage;

  /// External identifiers (IMDB, etc.).
  final ExternalIds? externalIds;

  /// Official homepage URL.
  final String? homepage;

  /// Marketing tagline.
  final String? tagline;

  /// Production budget in US dollars.
  final int? budget;

  /// Worldwide box-office revenue in US dollars.
  final int? revenue;

  @override
  String toString() => 'MovieDetail(id: $id, title: $title)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MovieDetail && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Cross-platform external identifiers for a media item.
@immutable
class ExternalIds {
  /// Creates an [ExternalIds] collection.
  const ExternalIds({
    this.imdbId,
    this.tvdbId,
    this.tvrageId,
    this.facebookId,
    this.instagramId,
    this.twitterId,
  });

  /// IMDb identifier (e.g. `tt1234567`).
  final String? imdbId;

  /// TheTVDB numeric identifier.
  final int? tvdbId;

  /// TVRage numeric identifier (legacy).
  final int? tvrageId;

  /// Facebook page or profile identifier.
  final String? facebookId;

  /// Instagram handle.
  final String? instagramId;

  /// Twitter / X handle.
  final String? twitterId;

  @override
  String toString() => 'ExternalIds(imdb: $imdbId, tvdb: $tvdbId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExternalIds &&
          imdbId == other.imdbId &&
          tvdbId == other.tvdbId;

  @override
  int get hashCode => Object.hash(imdbId, tvdbId);
}

// ---------------------------------------------------------------------------
// Service interface
// ---------------------------------------------------------------------------

/// Abstract interface for media metadata lookup.
///
/// Provides multi-search across movies and TV series, detail retrieval
/// with external IDs, and season/episode browsing. Implementations may
/// use TMDB, TVDB, or other metadata providers.
///
/// Agents interact with this service exclusively through `AgentContext`.
abstract interface class MediaMetadataService {
  /// Multi-search for both TV series and movies.
  ///
  /// Returns a paginated list of results matching [query]. Use [page]
  /// for pagination (1-based).
  Future<Result<List<MediaSearchResult>>> search(String query, {int page});

  /// Gets detailed TV series info including season summaries.
  ///
  /// The returned [TvSeriesDetail.seasons] contains [TvSeasonSummary]
  /// entries — use [getTvSeason] for full episode listings.
  Future<Result<TvSeriesDetail>> getTvSeries(int id);

  /// Gets full season detail with all episodes.
  ///
  /// [seriesId] is the TV series identifier; [seasonNumber] is
  /// zero-based (0 = specials, 1 = season 1, etc.).
  Future<Result<TvSeasonDetail>> getTvSeason(int seriesId, int seasonNumber);

  /// Gets detailed movie info.
  Future<Result<MovieDetail>> getMovie(int id);

  /// Builds a full image URL from a relative [path].
  ///
  /// Relative paths are returned in data class fields like
  /// [MediaSearchResult.posterPath]. Pass them here to get an
  /// absolute URL suitable for display.
  String imageUrl(String path, {MediaImageSize size = MediaImageSize.medium});
}
