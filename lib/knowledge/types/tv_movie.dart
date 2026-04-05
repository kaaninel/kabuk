/// Schema.org TV/Movie type helpers for the Kabuk knowledge store.
///
/// Provides data classes and [KnowledgeStore] extension methods for
/// TV series, seasons, episodes, and movies. Maps TMDB/TVDB metadata
/// to Schema.org types stored as RDF triples.
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// TvSeriesData
// ---------------------------------------------------------------------------

/// Immutable representation of a `schema:TVSeries` entity.
///
/// A television series with metadata sourced from TMDB/TVDB.
@immutable
class TvSeriesData {
  /// Creates a [TvSeriesData] with the given field values.
  const TvSeriesData({
    required this.uri,
    required this.name,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.firstAirDate,
    this.lastAirDate,
    this.status,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.genres = const [],
    this.networks = const [],
    this.voteAverage,
    this.tmdbId,
    this.tvdbId,
    this.imdbId,
  });

  /// Constructs a [TvSeriesData] from a subject [uri] and its [triples].
  factory TvSeriesData.fromTriples(String uri, List<Triple> triples) {
    final genresRaw = triples
        .where((t) => t.predicate == NS.schemaGenre)
        .map((t) => t.objectValue)
        .toList();

    final networksRaw = triples
        .where((t) => t.predicate == NS.kabukNetwork)
        .map((t) => t.objectValue)
        .toList();

    return TvSeriesData(
      uri: uri,
      name: triples
              .where((t) => t.predicate == NS.schemaName)
              .firstOrNull
              ?.objectValue ??
          '',
      overview: triples
          .where((t) => t.predicate == NS.kabukOverview)
          .firstOrNull
          ?.objectValue,
      posterPath: triples
          .where((t) => t.predicate == NS.kabukPosterPath)
          .firstOrNull
          ?.objectValue,
      backdropPath: triples
          .where((t) => t.predicate == NS.kabukBackdropPath)
          .firstOrNull
          ?.objectValue,
      firstAirDate: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaStartDate)
            .firstOrNull
            ?.objectValue,
      ),
      lastAirDate: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaEndDate)
            .firstOrNull
            ?.objectValue,
      ),
      status: triples
          .where((t) => t.predicate == NS.kabukMediaStatus)
          .firstOrNull
          ?.objectValue,
      numberOfSeasons: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.schemaNumberOfSeasons)
            .firstOrNull
            ?.objectValue,
      ),
      numberOfEpisodes: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.schemaNumberOfEpisodes)
            .firstOrNull
            ?.objectValue,
      ),
      genres: genresRaw,
      networks: networksRaw,
      voteAverage: _tryParseDouble(
        triples
            .where((t) => t.predicate == NS.kabukVoteAverage)
            .firstOrNull
            ?.objectValue,
      ),
      tmdbId: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.kabukTmdbId)
            .firstOrNull
            ?.objectValue,
      ),
      tvdbId: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.kabukTvdbId)
            .firstOrNull
            ?.objectValue,
      ),
      imdbId: triples
          .where((t) => t.predicate == NS.kabukImdbId)
          .firstOrNull
          ?.objectValue,
    );
  }

  /// The entity URI in the knowledge store.
  final String uri;

  /// Display name of the series (`schema:name`).
  final String name;

  /// Plot summary (`kabuk:overview`).
  final String? overview;

  /// TMDB poster image path (`kabuk:posterPath`).
  final String? posterPath;

  /// TMDB backdrop image path (`kabuk:backdropPath`).
  final String? backdropPath;

  /// When the series first aired (`schema:startDate`).
  final DateTime? firstAirDate;

  /// When the series last aired (`schema:endDate`).
  final DateTime? lastAirDate;

  /// Production status e.g. "Returning Series", "Ended" (`kabuk:mediaStatus`).
  final String? status;

  /// Total number of seasons (`schema:numberOfSeasons`).
  final int? numberOfSeasons;

  /// Total number of episodes (`schema:numberOfEpisodes`).
  final int? numberOfEpisodes;

  /// Genre strings (`schema:genre`).
  final List<String> genres;

  /// Broadcast network names (`kabuk:network`).
  final List<String> networks;

  /// Average user rating (`kabuk:voteAverage`).
  final double? voteAverage;

  /// TMDB identifier (`kabuk:tmdbId`).
  final int? tmdbId;

  /// TVDB identifier (`kabuk:tvdbId`).
  final int? tvdbId;

  /// IMDB identifier (`kabuk:imdbId`).
  final String? imdbId;
}

// ---------------------------------------------------------------------------
// TvSeasonData
// ---------------------------------------------------------------------------

/// Immutable representation of a `schema:TVSeason` entity.
///
/// A single season within a TV series.
@immutable
class TvSeasonData {
  /// Creates a [TvSeasonData] with the given field values.
  const TvSeasonData({
    required this.uri,
    required this.name,
    this.seasonNumber,
    this.overview,
    this.posterPath,
    this.airDate,
    this.numberOfEpisodes,
    this.seriesUri,
    this.voteAverage,
    this.tmdbId,
  });

  /// Constructs a [TvSeasonData] from a subject [uri] and its [triples].
  factory TvSeasonData.fromTriples(String uri, List<Triple> triples) {
    return TvSeasonData(
      uri: uri,
      name: triples
              .where((t) => t.predicate == NS.schemaName)
              .firstOrNull
              ?.objectValue ??
          '',
      seasonNumber: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.schemaSeasonNumber)
            .firstOrNull
            ?.objectValue,
      ),
      overview: triples
          .where((t) => t.predicate == NS.kabukOverview)
          .firstOrNull
          ?.objectValue,
      posterPath: triples
          .where((t) => t.predicate == NS.kabukPosterPath)
          .firstOrNull
          ?.objectValue,
      airDate: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.kabukAirDate)
            .firstOrNull
            ?.objectValue,
      ),
      numberOfEpisodes: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.schemaNumberOfEpisodes)
            .firstOrNull
            ?.objectValue,
      ),
      seriesUri: triples
          .where((t) => t.predicate == NS.schemaPartOfSeries)
          .firstOrNull
          ?.objectValue,
      voteAverage: _tryParseDouble(
        triples
            .where((t) => t.predicate == NS.kabukVoteAverage)
            .firstOrNull
            ?.objectValue,
      ),
      tmdbId: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.kabukTmdbId)
            .firstOrNull
            ?.objectValue,
      ),
    );
  }

  /// The entity URI in the knowledge store.
  final String uri;

  /// Display name of the season (`schema:name`).
  final String name;

  /// Season number within the series (`schema:seasonNumber`).
  final int? seasonNumber;

  /// Plot summary (`kabuk:overview`).
  final String? overview;

  /// TMDB poster image path (`kabuk:posterPath`).
  final String? posterPath;

  /// When the season first aired (`kabuk:airDate`).
  final DateTime? airDate;

  /// Number of episodes in this season (`schema:numberOfEpisodes`).
  final int? numberOfEpisodes;

  /// URI of the parent `TVSeries` entity (`schema:partOfSeries`).
  final String? seriesUri;

  /// Average user rating (`kabuk:voteAverage`).
  final double? voteAverage;

  /// TMDB identifier (`kabuk:tmdbId`).
  final int? tmdbId;
}

// ---------------------------------------------------------------------------
// TvEpisodeData
// ---------------------------------------------------------------------------

/// Immutable representation of a `schema:TVEpisode` entity.
///
/// A single episode within a TV season.
@immutable
class TvEpisodeData {
  /// Creates a [TvEpisodeData] with the given field values.
  const TvEpisodeData({
    required this.uri,
    required this.name,
    this.episodeNumber,
    this.seasonNumber,
    this.overview,
    this.stillPath,
    this.airDate,
    this.runtime,
    this.seasonUri,
    this.seriesUri,
    this.voteAverage,
    this.tmdbId,
    this.directors = const [],
  });

  /// Constructs a [TvEpisodeData] from a subject [uri] and its [triples].
  factory TvEpisodeData.fromTriples(String uri, List<Triple> triples) {
    return TvEpisodeData(
      uri: uri,
      name: triples
              .where((t) => t.predicate == NS.schemaName)
              .firstOrNull
              ?.objectValue ??
          '',
      episodeNumber: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.schemaEpisodeNumber)
            .firstOrNull
            ?.objectValue,
      ),
      seasonNumber: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.schemaSeasonNumber)
            .firstOrNull
            ?.objectValue,
      ),
      overview: triples
          .where((t) => t.predicate == NS.kabukOverview)
          .firstOrNull
          ?.objectValue,
      stillPath: triples
          .where((t) => t.predicate == NS.kabukStillPath)
          .firstOrNull
          ?.objectValue,
      airDate: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.kabukAirDate)
            .firstOrNull
            ?.objectValue,
      ),
      runtime: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.kabukRuntime)
            .firstOrNull
            ?.objectValue,
      ),
      seasonUri: triples
          .where((t) => t.predicate == NS.schemaPartOfSeason)
          .firstOrNull
          ?.objectValue,
      seriesUri: triples
          .where((t) => t.predicate == NS.schemaPartOfSeries)
          .firstOrNull
          ?.objectValue,
      voteAverage: _tryParseDouble(
        triples
            .where((t) => t.predicate == NS.kabukVoteAverage)
            .firstOrNull
            ?.objectValue,
      ),
      tmdbId: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.kabukTmdbId)
            .firstOrNull
            ?.objectValue,
      ),
      directors: triples
          .where((t) => t.predicate == NS.schemaDirector)
          .map((t) => t.objectValue)
          .toList(),
    );
  }

  /// The entity URI in the knowledge store.
  final String uri;

  /// Display name of the episode (`schema:name`).
  final String name;

  /// Episode number within the season (`schema:episodeNumber`).
  final int? episodeNumber;

  /// Season number of the parent season (`schema:seasonNumber`).
  final int? seasonNumber;

  /// Plot summary (`kabuk:overview`).
  final String? overview;

  /// TMDB still image path (`kabuk:stillPath`).
  final String? stillPath;

  /// When the episode aired (`kabuk:airDate`).
  final DateTime? airDate;

  /// Runtime in minutes (`kabuk:runtime`).
  final int? runtime;

  /// URI of the parent `TVSeason` entity (`schema:partOfSeason`).
  final String? seasonUri;

  /// URI of the parent `TVSeries` entity (`schema:partOfSeries`).
  final String? seriesUri;

  /// Average user rating (`kabuk:voteAverage`).
  final double? voteAverage;

  /// TMDB identifier (`kabuk:tmdbId`).
  final int? tmdbId;

  /// Director names (`schema:director`).
  final List<String> directors;
}

// ---------------------------------------------------------------------------
// MovieData
// ---------------------------------------------------------------------------

/// Immutable representation of a `schema:Movie` entity.
///
/// A movie with metadata sourced from TMDB.
@immutable
class MovieData {
  /// Creates a [MovieData] with the given field values.
  const MovieData({
    required this.uri,
    required this.name,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.runtime,
    this.genres = const [],
    this.directors = const [],
    this.actors = const [],
    this.productionCompanies = const [],
    this.countryOfOrigin,
    this.voteAverage,
    this.tmdbId,
    this.imdbId,
  });

  /// Constructs a [MovieData] from a subject [uri] and its [triples].
  factory MovieData.fromTriples(String uri, List<Triple> triples) {
    return MovieData(
      uri: uri,
      name: triples
              .where((t) => t.predicate == NS.schemaName)
              .firstOrNull
              ?.objectValue ??
          '',
      overview: triples
          .where((t) => t.predicate == NS.kabukOverview)
          .firstOrNull
          ?.objectValue,
      posterPath: triples
          .where((t) => t.predicate == NS.kabukPosterPath)
          .firstOrNull
          ?.objectValue,
      backdropPath: triples
          .where((t) => t.predicate == NS.kabukBackdropPath)
          .firstOrNull
          ?.objectValue,
      releaseDate: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaDatePublished)
            .firstOrNull
            ?.objectValue,
      ),
      runtime: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.kabukRuntime)
            .firstOrNull
            ?.objectValue,
      ),
      genres: triples
          .where((t) => t.predicate == NS.schemaGenre)
          .map((t) => t.objectValue)
          .toList(),
      directors: triples
          .where((t) => t.predicate == NS.schemaDirector)
          .map((t) => t.objectValue)
          .toList(),
      actors: triples
          .where((t) => t.predicate == NS.schemaActor)
          .map((t) => t.objectValue)
          .toList(),
      productionCompanies: triples
          .where((t) => t.predicate == NS.schemaProductionCompany)
          .map((t) => t.objectValue)
          .toList(),
      countryOfOrigin: triples
          .where((t) => t.predicate == NS.schemaCountryOfOrigin)
          .firstOrNull
          ?.objectValue,
      voteAverage: _tryParseDouble(
        triples
            .where((t) => t.predicate == NS.kabukVoteAverage)
            .firstOrNull
            ?.objectValue,
      ),
      tmdbId: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.kabukTmdbId)
            .firstOrNull
            ?.objectValue,
      ),
      imdbId: triples
          .where((t) => t.predicate == NS.kabukImdbId)
          .firstOrNull
          ?.objectValue,
    );
  }

  /// The entity URI in the knowledge store.
  final String uri;

  /// Display name of the movie (`schema:name`).
  final String name;

  /// Plot summary (`kabuk:overview`).
  final String? overview;

  /// TMDB poster image path (`kabuk:posterPath`).
  final String? posterPath;

  /// TMDB backdrop image path (`kabuk:backdropPath`).
  final String? backdropPath;

  /// Theatrical release date (`schema:datePublished`).
  final DateTime? releaseDate;

  /// Runtime in minutes (`kabuk:runtime`).
  final int? runtime;

  /// Genre strings (`schema:genre`).
  final List<String> genres;

  /// Director names (`schema:director`).
  final List<String> directors;

  /// Actor names (`schema:actor`).
  final List<String> actors;

  /// Production company names (`schema:productionCompany`).
  final List<String> productionCompanies;

  /// Country of origin (`schema:countryOfOrigin`).
  final String? countryOfOrigin;

  /// Average user rating (`kabuk:voteAverage`).
  final double? voteAverage;

  /// TMDB identifier (`kabuk:tmdbId`).
  final int? tmdbId;

  /// IMDB identifier (`kabuk:imdbId`).
  final String? imdbId;
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

DateTime? _tryParseDateTime(String? value) =>
    value == null ? null : DateTime.tryParse(value);

int? _tryParseInt(String? value) =>
    value == null ? null : int.tryParse(value);

double? _tryParseDouble(String? value) =>
    value == null ? null : double.tryParse(value);

// ---------------------------------------------------------------------------
// Extension methods
// ---------------------------------------------------------------------------

/// Convenience methods for working with TV/Movie entities in the knowledge
/// store.
extension KnowledgeStoreTvMovieExtension on KnowledgeStore {
  // ── TV Series CRUD ────────────────────────────────────────────────────────

  /// Creates a new `TVSeries` entity and returns its URI.
  ///
  /// If [tmdbId] is provided the URI is deterministic
  /// (`kabuk:media:tv:{tmdbId}`), enabling upsert-like behavior.
  Future<String> createTvSeries({
    required String name,
    String? overview,
    String? posterPath,
    String? backdropPath,
    DateTime? firstAirDate,
    DateTime? lastAirDate,
    String? status,
    int? numberOfSeasons,
    int? numberOfEpisodes,
    List<String> genres = const [],
    List<String> networks = const [],
    double? voteAverage,
    int? tmdbId,
    int? tvdbId,
    String? imdbId,
  }) {
    return mutate((ctx) async {
      final uri =
          tmdbId != null ? 'kabuk:media:tv:$tmdbId' : ctx.create('TVSeries');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.schemaTVSeries,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      if (overview != null) {
        await ctx.set(uri, NS.kabukOverview, overview);
      }
      if (posterPath != null) {
        await ctx.set(uri, NS.kabukPosterPath, posterPath);
      }
      if (backdropPath != null) {
        await ctx.set(uri, NS.kabukBackdropPath, backdropPath);
      }
      if (firstAirDate != null) {
        await ctx.set(
          uri,
          NS.schemaStartDate,
          firstAirDate.toIso8601String(),
        );
      }
      if (lastAirDate != null) {
        await ctx.set(uri, NS.schemaEndDate, lastAirDate.toIso8601String());
      }
      if (status != null) {
        await ctx.set(uri, NS.kabukMediaStatus, status);
      }
      if (numberOfSeasons != null) {
        await ctx.set(
          uri,
          NS.schemaNumberOfSeasons,
          numberOfSeasons.toString(),
        );
      }
      if (numberOfEpisodes != null) {
        await ctx.set(
          uri,
          NS.schemaNumberOfEpisodes,
          numberOfEpisodes.toString(),
        );
      }
      // Remove existing multi-value predicates before re-adding.
      await ctx.remove(subject: uri, predicate: NS.schemaGenre);
      for (final genre in genres) {
        await ctx.add(uri, NS.schemaGenre, genre);
      }
      await ctx.remove(subject: uri, predicate: NS.kabukNetwork);
      for (final network in networks) {
        await ctx.add(uri, NS.kabukNetwork, network);
      }
      if (voteAverage != null) {
        await ctx.set(uri, NS.kabukVoteAverage, voteAverage.toString());
      }
      if (tmdbId != null) {
        await ctx.set(uri, NS.kabukTmdbId, tmdbId.toString());
      }
      if (tvdbId != null) {
        await ctx.set(uri, NS.kabukTvdbId, tvdbId.toString());
      }
      if (imdbId != null) {
        await ctx.set(uri, NS.kabukImdbId, imdbId);
      }
      await ctx.set(
        uri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );
      return uri;
    });
  }

  /// Updates mutable fields of an existing `TVSeries` entity.
  Future<void> updateTvSeries(
    String uri, {
    String? name,
    String? overview,
    String? posterPath,
    String? backdropPath,
    DateTime? lastAirDate,
    String? status,
    int? numberOfSeasons,
    int? numberOfEpisodes,
    List<String>? genres,
    List<String>? networks,
    double? voteAverage,
  }) {
    return mutate((ctx) async {
      if (name != null) await ctx.set(uri, NS.schemaName, name);
      if (overview != null) await ctx.set(uri, NS.kabukOverview, overview);
      if (posterPath != null) {
        await ctx.set(uri, NS.kabukPosterPath, posterPath);
      }
      if (backdropPath != null) {
        await ctx.set(uri, NS.kabukBackdropPath, backdropPath);
      }
      if (lastAirDate != null) {
        await ctx.set(uri, NS.schemaEndDate, lastAirDate.toIso8601String());
      }
      if (status != null) await ctx.set(uri, NS.kabukMediaStatus, status);
      if (numberOfSeasons != null) {
        await ctx.set(
          uri,
          NS.schemaNumberOfSeasons,
          numberOfSeasons.toString(),
        );
      }
      if (numberOfEpisodes != null) {
        await ctx.set(
          uri,
          NS.schemaNumberOfEpisodes,
          numberOfEpisodes.toString(),
        );
      }
      if (genres != null) {
        await ctx.remove(subject: uri, predicate: NS.schemaGenre);
        for (final genre in genres) {
          await ctx.add(uri, NS.schemaGenre, genre);
        }
      }
      if (networks != null) {
        await ctx.remove(subject: uri, predicate: NS.kabukNetwork);
        for (final network in networks) {
          await ctx.add(uri, NS.kabukNetwork, network);
        }
      }
      if (voteAverage != null) {
        await ctx.set(uri, NS.kabukVoteAverage, voteAverage.toString());
      }
    });
  }

  /// Retrieves a single `TVSeries` by [uri], or `null` if not found.
  Future<TvSeriesData?> getTvSeries(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return TvSeriesData.fromTriples(uri, triples);
  }

  /// Deletes a `TVSeries` entity by [uri].
  Future<void> deleteTvSeries(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }

  /// Lists all `TVSeries` entities, ordered by name.
  Future<List<TvSeriesData>> listTvSeries({int limit = 50}) async {
    final typeTriples = await query()
        .where(NS.rdfType, equals: NS.schemaTVSeries)
        .orderBy(NS.schemaName)
        .limit(limit)
        .execute();
    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    return [
      for (final uri in uris)
        if (allTriples[uri] case final triples? when triples.isNotEmpty)
          TvSeriesData.fromTriples(uri, triples),
    ];
  }

  // ── TV Season CRUD ────────────────────────────────────────────────────────

  /// Creates a new `TVSeason` entity and returns its URI.
  ///
  /// If [tmdbId] is provided the URI is deterministic
  /// (`kabuk:media:tv:season:{tmdbId}`).
  Future<String> createTvSeason({
    required String name,
    int? seasonNumber,
    String? overview,
    String? posterPath,
    DateTime? airDate,
    int? numberOfEpisodes,
    String? seriesUri,
    double? voteAverage,
    int? tmdbId,
  }) {
    return mutate((ctx) async {
      final uri = tmdbId != null
          ? 'kabuk:media:tv:season:$tmdbId'
          : ctx.create('TVSeason');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.schemaTVSeason,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      if (seasonNumber != null) {
        await ctx.set(uri, NS.schemaSeasonNumber, seasonNumber.toString());
      }
      if (overview != null) {
        await ctx.set(uri, NS.kabukOverview, overview);
      }
      if (posterPath != null) {
        await ctx.set(uri, NS.kabukPosterPath, posterPath);
      }
      if (airDate != null) {
        await ctx.set(uri, NS.kabukAirDate, airDate.toIso8601String());
      }
      if (numberOfEpisodes != null) {
        await ctx.set(
          uri,
          NS.schemaNumberOfEpisodes,
          numberOfEpisodes.toString(),
        );
      }
      if (seriesUri != null) {
        await ctx.set(
          uri,
          NS.schemaPartOfSeries,
          seriesUri,
          objectType: ObjectType.uri,
        );
      }
      if (voteAverage != null) {
        await ctx.set(uri, NS.kabukVoteAverage, voteAverage.toString());
      }
      if (tmdbId != null) {
        await ctx.set(uri, NS.kabukTmdbId, tmdbId.toString());
      }
      await ctx.set(
        uri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );
      return uri;
    });
  }

  /// Updates mutable fields of an existing `TVSeason` entity.
  Future<void> updateTvSeason(
    String uri, {
    String? name,
    String? overview,
    String? posterPath,
    DateTime? airDate,
    int? numberOfEpisodes,
    double? voteAverage,
  }) {
    return mutate((ctx) async {
      if (name != null) await ctx.set(uri, NS.schemaName, name);
      if (overview != null) await ctx.set(uri, NS.kabukOverview, overview);
      if (posterPath != null) {
        await ctx.set(uri, NS.kabukPosterPath, posterPath);
      }
      if (airDate != null) {
        await ctx.set(uri, NS.kabukAirDate, airDate.toIso8601String());
      }
      if (numberOfEpisodes != null) {
        await ctx.set(
          uri,
          NS.schemaNumberOfEpisodes,
          numberOfEpisodes.toString(),
        );
      }
      if (voteAverage != null) {
        await ctx.set(uri, NS.kabukVoteAverage, voteAverage.toString());
      }
    });
  }

  /// Retrieves a single `TVSeason` by [uri], or `null` if not found.
  Future<TvSeasonData?> getTvSeason(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return TvSeasonData.fromTriples(uri, triples);
  }

  /// Deletes a `TVSeason` entity by [uri].
  Future<void> deleteTvSeason(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }

  /// Lists `TVSeason` entities for a given series, ordered by season number.
  Future<List<TvSeasonData>> listTvSeasons({
    String? seriesUri,
    int limit = 50,
  }) async {
    var builder = query()
        .where(NS.rdfType, equals: NS.schemaTVSeason)
        .orderBy(NS.schemaSeasonNumber)
        .limit(limit);

    if (seriesUri != null) {
      builder = builder.where(NS.schemaPartOfSeries, equals: seriesUri);
    }

    final typeTriples = await builder.execute();
    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    return [
      for (final uri in uris)
        if (allTriples[uri] case final triples? when triples.isNotEmpty)
          TvSeasonData.fromTriples(uri, triples),
    ];
  }

  // ── TV Episode CRUD ───────────────────────────────────────────────────────

  /// Creates a new `TVEpisode` entity and returns its URI.
  ///
  /// If [tmdbId] is provided the URI is deterministic
  /// (`kabuk:media:tv:episode:{tmdbId}`).
  Future<String> createTvEpisode({
    required String name,
    int? episodeNumber,
    int? seasonNumber,
    String? overview,
    String? stillPath,
    DateTime? airDate,
    int? runtime,
    String? seasonUri,
    String? seriesUri,
    double? voteAverage,
    int? tmdbId,
    List<String> directors = const [],
  }) {
    return mutate((ctx) async {
      final uri = tmdbId != null
          ? 'kabuk:media:tv:episode:$tmdbId'
          : ctx.create('TVEpisode');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.schemaTVEpisode,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      if (episodeNumber != null) {
        await ctx.set(uri, NS.schemaEpisodeNumber, episodeNumber.toString());
      }
      if (seasonNumber != null) {
        await ctx.set(uri, NS.schemaSeasonNumber, seasonNumber.toString());
      }
      if (overview != null) {
        await ctx.set(uri, NS.kabukOverview, overview);
      }
      if (stillPath != null) {
        await ctx.set(uri, NS.kabukStillPath, stillPath);
      }
      if (airDate != null) {
        await ctx.set(uri, NS.kabukAirDate, airDate.toIso8601String());
      }
      if (runtime != null) {
        await ctx.set(uri, NS.kabukRuntime, runtime.toString());
      }
      if (seasonUri != null) {
        await ctx.set(
          uri,
          NS.schemaPartOfSeason,
          seasonUri,
          objectType: ObjectType.uri,
        );
      }
      if (seriesUri != null) {
        await ctx.set(
          uri,
          NS.schemaPartOfSeries,
          seriesUri,
          objectType: ObjectType.uri,
        );
      }
      if (voteAverage != null) {
        await ctx.set(uri, NS.kabukVoteAverage, voteAverage.toString());
      }
      if (tmdbId != null) {
        await ctx.set(uri, NS.kabukTmdbId, tmdbId.toString());
      }
      await ctx.remove(subject: uri, predicate: NS.schemaDirector);
      for (final director in directors) {
        await ctx.add(uri, NS.schemaDirector, director);
      }
      await ctx.set(
        uri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );
      return uri;
    });
  }

  /// Updates mutable fields of an existing `TVEpisode` entity.
  Future<void> updateTvEpisode(
    String uri, {
    String? name,
    String? overview,
    String? stillPath,
    DateTime? airDate,
    int? runtime,
    double? voteAverage,
    List<String>? directors,
  }) {
    return mutate((ctx) async {
      if (name != null) await ctx.set(uri, NS.schemaName, name);
      if (overview != null) await ctx.set(uri, NS.kabukOverview, overview);
      if (stillPath != null) await ctx.set(uri, NS.kabukStillPath, stillPath);
      if (airDate != null) {
        await ctx.set(uri, NS.kabukAirDate, airDate.toIso8601String());
      }
      if (runtime != null) {
        await ctx.set(uri, NS.kabukRuntime, runtime.toString());
      }
      if (voteAverage != null) {
        await ctx.set(uri, NS.kabukVoteAverage, voteAverage.toString());
      }
      if (directors != null) {
        await ctx.remove(subject: uri, predicate: NS.schemaDirector);
        for (final director in directors) {
          await ctx.add(uri, NS.schemaDirector, director);
        }
      }
    });
  }

  /// Retrieves a single `TVEpisode` by [uri], or `null` if not found.
  Future<TvEpisodeData?> getTvEpisode(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return TvEpisodeData.fromTriples(uri, triples);
  }

  /// Deletes a `TVEpisode` entity by [uri].
  Future<void> deleteTvEpisode(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }

  /// Lists `TVEpisode` entities, optionally filtered by season or series.
  Future<List<TvEpisodeData>> listTvEpisodes({
    String? seasonUri,
    String? seriesUri,
    int limit = 50,
  }) async {
    var builder = query()
        .where(NS.rdfType, equals: NS.schemaTVEpisode)
        .orderBy(NS.schemaEpisodeNumber)
        .limit(limit);

    if (seasonUri != null) {
      builder = builder.where(NS.schemaPartOfSeason, equals: seasonUri);
    }
    if (seriesUri != null) {
      builder = builder.where(NS.schemaPartOfSeries, equals: seriesUri);
    }

    final typeTriples = await builder.execute();
    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    return [
      for (final uri in uris)
        if (allTriples[uri] case final triples? when triples.isNotEmpty)
          TvEpisodeData.fromTriples(uri, triples),
    ];
  }

  // ── Movie CRUD ────────────────────────────────────────────────────────────

  /// Creates a new `Movie` entity and returns its URI.
  ///
  /// If [tmdbId] is provided the URI is deterministic
  /// (`kabuk:media:movie:{tmdbId}`).
  Future<String> createMovie({
    required String name,
    String? overview,
    String? posterPath,
    String? backdropPath,
    DateTime? releaseDate,
    int? runtime,
    List<String> genres = const [],
    List<String> directors = const [],
    List<String> actors = const [],
    List<String> productionCompanies = const [],
    String? countryOfOrigin,
    double? voteAverage,
    int? tmdbId,
    String? imdbId,
  }) {
    return mutate((ctx) async {
      final uri =
          tmdbId != null ? 'kabuk:media:movie:$tmdbId' : ctx.create('Movie');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.schemaMovie,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      if (overview != null) {
        await ctx.set(uri, NS.kabukOverview, overview);
      }
      if (posterPath != null) {
        await ctx.set(uri, NS.kabukPosterPath, posterPath);
      }
      if (backdropPath != null) {
        await ctx.set(uri, NS.kabukBackdropPath, backdropPath);
      }
      if (releaseDate != null) {
        await ctx.set(
          uri,
          NS.schemaDatePublished,
          releaseDate.toIso8601String(),
        );
      }
      if (runtime != null) {
        await ctx.set(uri, NS.kabukRuntime, runtime.toString());
      }
      await ctx.remove(subject: uri, predicate: NS.schemaGenre);
      for (final genre in genres) {
        await ctx.add(uri, NS.schemaGenre, genre);
      }
      await ctx.remove(subject: uri, predicate: NS.schemaDirector);
      for (final director in directors) {
        await ctx.add(uri, NS.schemaDirector, director);
      }
      await ctx.remove(subject: uri, predicate: NS.schemaActor);
      for (final actor in actors) {
        await ctx.add(uri, NS.schemaActor, actor);
      }
      await ctx.remove(subject: uri, predicate: NS.schemaProductionCompany);
      for (final company in productionCompanies) {
        await ctx.add(uri, NS.schemaProductionCompany, company);
      }
      if (countryOfOrigin != null) {
        await ctx.set(uri, NS.schemaCountryOfOrigin, countryOfOrigin);
      }
      if (voteAverage != null) {
        await ctx.set(uri, NS.kabukVoteAverage, voteAverage.toString());
      }
      if (tmdbId != null) {
        await ctx.set(uri, NS.kabukTmdbId, tmdbId.toString());
      }
      if (imdbId != null) {
        await ctx.set(uri, NS.kabukImdbId, imdbId);
      }
      await ctx.set(
        uri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );
      return uri;
    });
  }

  /// Updates mutable fields of an existing `Movie` entity.
  Future<void> updateMovie(
    String uri, {
    String? name,
    String? overview,
    String? posterPath,
    String? backdropPath,
    int? runtime,
    List<String>? genres,
    List<String>? directors,
    List<String>? actors,
    List<String>? productionCompanies,
    String? countryOfOrigin,
    double? voteAverage,
  }) {
    return mutate((ctx) async {
      if (name != null) await ctx.set(uri, NS.schemaName, name);
      if (overview != null) await ctx.set(uri, NS.kabukOverview, overview);
      if (posterPath != null) {
        await ctx.set(uri, NS.kabukPosterPath, posterPath);
      }
      if (backdropPath != null) {
        await ctx.set(uri, NS.kabukBackdropPath, backdropPath);
      }
      if (runtime != null) {
        await ctx.set(uri, NS.kabukRuntime, runtime.toString());
      }
      if (genres != null) {
        await ctx.remove(subject: uri, predicate: NS.schemaGenre);
        for (final genre in genres) {
          await ctx.add(uri, NS.schemaGenre, genre);
        }
      }
      if (directors != null) {
        await ctx.remove(subject: uri, predicate: NS.schemaDirector);
        for (final director in directors) {
          await ctx.add(uri, NS.schemaDirector, director);
        }
      }
      if (actors != null) {
        await ctx.remove(subject: uri, predicate: NS.schemaActor);
        for (final actor in actors) {
          await ctx.add(uri, NS.schemaActor, actor);
        }
      }
      if (productionCompanies != null) {
        await ctx.remove(subject: uri, predicate: NS.schemaProductionCompany);
        for (final company in productionCompanies) {
          await ctx.add(uri, NS.schemaProductionCompany, company);
        }
      }
      if (countryOfOrigin != null) {
        await ctx.set(uri, NS.schemaCountryOfOrigin, countryOfOrigin);
      }
      if (voteAverage != null) {
        await ctx.set(uri, NS.kabukVoteAverage, voteAverage.toString());
      }
    });
  }

  /// Retrieves a single `Movie` by [uri], or `null` if not found.
  Future<MovieData?> getMovie(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return MovieData.fromTriples(uri, triples);
  }

  /// Deletes a `Movie` entity by [uri].
  Future<void> deleteMovie(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }

  /// Lists all `Movie` entities, ordered by name.
  Future<List<MovieData>> listMovies({int limit = 50}) async {
    final typeTriples = await query()
        .where(NS.rdfType, equals: NS.schemaMovie)
        .orderBy(NS.schemaName)
        .limit(limit)
        .execute();
    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    return [
      for (final uri in uris)
        if (allTriples[uri] case final triples? when triples.isNotEmpty)
          MovieData.fromTriples(uri, triples),
    ];
  }
}
