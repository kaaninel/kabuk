/// Unified media metadata content plugin for TV shows and movies.
///
/// Combines free APIs (TVmaze, IMDbAPI.dev) with optional TMDB
/// enhancement into a single [ContentPlugin] that searches, resolves
/// URLs, and produces [ContentItem] objects with [ContentType.video].
///
/// **Free tier (no API key):** TVmaze for TV series, IMDbAPI.dev for
/// movies. **Enhanced tier:** When a TMDB API key is configured, TMDB
/// results are merged in as well.
///
/// ```dart
/// final plugin = MediaPlugin();
/// await plugin.initialize(context);
/// final results = await plugin.search('Breaking Bad');
/// ```
library;

import 'dart:convert';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show IconData;
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/plugins/context.dart';
import 'package:kabuk/plugins/plugin.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _tvMazeBase = 'https://api.tvmaze.com';
const _imdbApiBase = 'https://api.imdbapi.dev/v2';
const _tmdbBase = 'https://api.themoviedb.org';
const _tmdbImageBase = 'https://image.tmdb.org/t/p/w342';
const _pluginId = 'media';


/// Regex for stripping HTML tags from TVmaze summary fields.
final RegExp _htmlTagRegex = RegExp(r'<[^>]*>');

// ---------------------------------------------------------------------------
// URL patterns
// ---------------------------------------------------------------------------

/// Matches IMDb title URLs like `https://www.imdb.com/title/tt1234567/`.
final RegExp _imdbUrlPattern = RegExp(
  r'https?://(?:www\.)?imdb\.com/title/(tt\d+)',
);

/// Matches TMDB URLs like `https://www.themoviedb.org/movie/550` or
/// `https://www.themoviedb.org/tv/1396`.
final RegExp _tmdbUrlPattern = RegExp(
  r'https?://(?:www\.)?themoviedb\.org/(movie|tv)/(\d+)',
);

/// Matches TVmaze URLs like `https://www.tvmaze.com/shows/1/under-the-dome`.
final RegExp _tvMazeUrlPattern = RegExp(
  r'https?://(?:www\.)?tvmaze\.com/shows/(\d+)',
);

// ---------------------------------------------------------------------------
// MediaPlugin
// ---------------------------------------------------------------------------

/// Content plugin that searches TV and movie metadata from TVmaze,
/// IMDbAPI.dev, and optionally TMDB.
///
/// All results are normalised into [ContentItem] instances with
/// [ContentType.video]. The plugin stores source-specific identifiers
/// in [ContentItem.extra] (`tvmazeId`, `imdbId`, `tmdbId`) for
/// downstream consumers that need to call the underlying APIs directly.
@immutable
class MediaPlugin implements ContentPlugin {
  /// Creates a [MediaPlugin].
  const MediaPlugin();

  @override
  String get id => _pluginId;

  @override
  String get name => 'TV & Movies';

  @override
  String get description =>
      'Search TV shows and movies via TVmaze, IMDbAPI, and optional TMDB.';

  @override
  String get version => '1.0.0';

  @override
  IconData get iconData => Icons.movie_outlined;

  @override
  PluginCategory get category => PluginCategory.media;

  @override
  Set<ContentCapability> get capabilities => const {
        ContentCapability.search,
        ContentCapability.urlResolve,
      };

  @override
  bool hasCapability(ContentCapability capability) =>
      capabilities.contains(capability);

  @override
  List<PluginConfigField> get configFields => const [
        PluginConfigField(
          key: 'tmdb_api_key',
          label: 'TMDB API Key',
          description:
              'Optional v3 API key from themoviedb.org. Enables richer '
              'search results and movie metadata.',
          type: PluginConfigFieldType.text,
          secret: true,
        ),
      ];

  @override
  Future<void> initialize(PluginContext context) async {
    _context = context;
    context.log('MediaPlugin initialized');
  }

  @override
  Future<void> dispose() async {
    _context = null;
  }

  // -----------------------------------------------------------------------
  // URL handling
  // -----------------------------------------------------------------------

  @override
  bool canHandleUrl(String url) =>
      _imdbUrlPattern.hasMatch(url) ||
      _tmdbUrlPattern.hasMatch(url) ||
      _tvMazeUrlPattern.hasMatch(url);

  @override
  Future<ResolvedContent> resolveUrl(String url) async {
    // Try IMDb URL.
    final imdbMatch = _imdbUrlPattern.firstMatch(url);
    if (imdbMatch != null) {
      final imdbId = imdbMatch.group(1)!;
      return _resolveImdb(imdbId);
    }

    // Try TMDB URL.
    final tmdbMatch = _tmdbUrlPattern.firstMatch(url);
    if (tmdbMatch != null) {
      final mediaType = tmdbMatch.group(1)!; // 'movie' or 'tv'
      final tmdbId = tmdbMatch.group(2)!;
      return _resolveTmdb(tmdbId, mediaType);
    }

    // Try TVmaze URL.
    final tvMazeMatch = _tvMazeUrlPattern.firstMatch(url);
    if (tvMazeMatch != null) {
      final showId = tvMazeMatch.group(1)!;
      return _resolveTvMaze(showId);
    }

    return const ResolvedNotHandled();
  }

  // -----------------------------------------------------------------------
  // Search
  // -----------------------------------------------------------------------

  @override
  Future<List<ContentItem>> search(
    String query, {
    int page = 0,
    int perPage = 20,
  }) async {
    if (query.trim().isEmpty) return const [];

    final futures = <String, Future<List<ContentItem>>>{
      'tvmaze': _searchTvMaze(query),
      'imdb': _searchImdb(query),
    };

    final tmdbKey = _context?.getConfig('tmdb_api_key');
    if (tmdbKey != null && tmdbKey.isNotEmpty) {
      futures['tmdb'] = _searchTmdb(query, tmdbKey);
    }

    final results = await Future.wait(
      futures.values,
      eagerError: false,
    );

    final keys = futures.keys.toList();
    final merged = <ContentItem>[];
    final seen = <String>{};

    for (var i = 0; i < keys.length; i++) {
      final items = results[i];
      for (final item in items) {
        final key = _dedupeKey(item.title, item.publishedAt?.year);
        if (seen.add(key)) {
          merged.add(item);
        }
      }
    }

    return merged;
  }

  // -----------------------------------------------------------------------
  // Unsupported capabilities
  // -----------------------------------------------------------------------

  @override
  Future<List<ContentItem>> fetchChannel(
    String entityId, {
    int page = 0,
    int perPage = 20,
  }) {
    throw UnsupportedError('MediaPlugin does not support channel feeds');
  }

  @override
  Future<List<ContentItem>> fetchTrending({
    int page = 0,
    int perPage = 20,
  }) {
    throw UnsupportedError('MediaPlugin does not support trending');
  }

  // =======================================================================
  // Private — context reference (set during initialize)
  // =======================================================================

  /// Stored context reference.
  ///
  /// This field is intentionally non-final so that [initialize] can set it.
  /// The class is conceptually immutable after initialisation; this is an
  /// implementation detail hidden from consumers.
  // ignore: use of non-final field in @immutable class — required by the
  // ContentPlugin lifecycle where initialize() injects the context after
  // construction.
  static PluginContext? _context;

  // We override initialize to store the context for use in instance methods.
  // The static field is acceptable because only one MediaPlugin instance
  // exists per plugin registry.

  // =======================================================================
  // Private — TVmaze search
  // =======================================================================

  Future<List<ContentItem>> _searchTvMaze(String query) async {
    final ctx = _context;
    if (ctx == null) return const [];

    try {
      final uri = Uri.parse('$_tvMazeBase/search/shows')
          .replace(queryParameters: {'q': query});
      final response = await ctx.httpClient.get(uri);

      if (response.statusCode != 200) {
        ctx.log(
          'TVmaze search returned ${response.statusCode}',
          error: response.body,
        );
        return const [];
      }

      final items = jsonDecode(response.body) as List<dynamic>;
      return items
          .cast<Map<String, dynamic>>()
          .map(_tvMazeEntryToContentItem)
          .toList(growable: false);
    } on Exception catch (e) {
      ctx.log('TVmaze search failed', error: e.toString());
      return const [];
    }
  }

  // =======================================================================
  // Private — IMDbAPI search
  // =======================================================================

  Future<List<ContentItem>> _searchImdb(String query) async {
    final ctx = _context;
    if (ctx == null) return const [];

    try {
      final uri = Uri.parse('$_imdbApiBase/search')
          .replace(queryParameters: {'q': query});
      final response = await ctx.httpClient.get(uri);

      if (response.statusCode != 200) {
        ctx.log(
          'IMDbAPI search returned ${response.statusCode}',
          error: response.body,
        );
        return const [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final ok = json['ok'];
      if (ok == false) {
        ctx.log(
          'IMDbAPI returned error',
          error: json['error']?.toString() ?? 'unknown',
        );
        return const [];
      }

      final data = json['data'] as List<dynamic>? ?? [];
      return data
          .cast<Map<String, dynamic>>()
          .map(_imdbSearchResultToContentItem)
          .toList(growable: false);
    } on Exception catch (e) {
      ctx.log('IMDbAPI search failed', error: e.toString());
      return const [];
    }
  }

  // =======================================================================
  // Private — TMDB search
  // =======================================================================

  Future<List<ContentItem>> _searchTmdb(String query, String apiKey) async {
    final ctx = _context;
    if (ctx == null) return const [];

    try {
      final uri = Uri.parse('$_tmdbBase/3/search/multi').replace(
        queryParameters: {
          'api_key': apiKey,
          'query': query,
          'language': 'en-US',
        },
      );
      final response = await ctx.httpClient.get(uri);

      if (response.statusCode != 200) {
        ctx.log(
          'TMDB search returned ${response.statusCode}',
          error: response.body,
        );
        return const [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final results = json['results'] as List<dynamic>? ?? [];
      return results
          .cast<Map<String, dynamic>>()
          .where((r) {
            final type = r['media_type'] as String?;
            return type == 'movie' || type == 'tv';
          })
          .map(_tmdbResultToContentItem)
          .toList(growable: false);
    } on Exception catch (e) {
      ctx.log('TMDB search failed', error: e.toString());
      return const [];
    }
  }

  // =======================================================================
  // Private — URL resolvers
  // =======================================================================

  Future<ResolvedContent> _resolveImdb(String imdbId) async {
    final ctx = _context;
    if (ctx == null) return const ResolvedNotHandled();

    try {
      final uri = Uri.parse('$_imdbApiBase/title/$imdbId');
      final response = await ctx.httpClient.get(uri);

      if (response.statusCode != 200) {
        ctx.log(
          'IMDbAPI title lookup returned ${response.statusCode}',
          error: response.body,
        );
        return const ResolvedNotHandled();
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['ok'] == false) return const ResolvedNotHandled();

      final data = json['data'] as Map<String, dynamic>? ?? json;
      return ResolvedContentItem(_imdbDetailToContentItem(data));
    } on Exception catch (e) {
      ctx.log('IMDb URL resolve failed', error: e.toString());
      return const ResolvedNotHandled();
    }
  }

  Future<ResolvedContent> _resolveTmdb(String tmdbId, String mediaType) async {
    final ctx = _context;
    if (ctx == null) return const ResolvedNotHandled();

    final apiKey = ctx.getConfig('tmdb_api_key');
    if (apiKey == null || apiKey.isEmpty) {
      ctx.log('TMDB URL resolve skipped — no API key configured');
      return const ResolvedNotHandled();
    }

    try {
      final path = mediaType == 'movie'
          ? '/3/movie/$tmdbId'
          : '/3/tv/$tmdbId';
      final uri = Uri.parse('$_tmdbBase$path').replace(
        queryParameters: {
          'api_key': apiKey,
          'language': 'en-US',
        },
      );
      final response = await ctx.httpClient.get(uri);

      if (response.statusCode != 200) {
        ctx.log(
          'TMDB detail lookup returned ${response.statusCode}',
          error: response.body,
        );
        return const ResolvedNotHandled();
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return ResolvedContentItem(
        _tmdbDetailToContentItem(json, mediaType),
      );
    } on Exception catch (e) {
      ctx.log('TMDB URL resolve failed', error: e.toString());
      return const ResolvedNotHandled();
    }
  }

  Future<ResolvedContent> _resolveTvMaze(String showId) async {
    final ctx = _context;
    if (ctx == null) return const ResolvedNotHandled();

    try {
      final uri = Uri.parse('$_tvMazeBase/shows/$showId');
      final response = await ctx.httpClient.get(uri);

      if (response.statusCode != 200) {
        ctx.log(
          'TVmaze show lookup returned ${response.statusCode}',
          error: response.body,
        );
        return const ResolvedNotHandled();
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return ResolvedContentItem(_tvMazeShowToContentItem(json));
    } on Exception catch (e) {
      ctx.log('TVmaze URL resolve failed', error: e.toString());
      return const ResolvedNotHandled();
    }
  }

  // =======================================================================
  // Private — JSON → ContentItem converters
  // =======================================================================

  /// Converts a TVmaze search entry `{score, show: {...}}` to a
  /// [ContentItem].
  ContentItem _tvMazeEntryToContentItem(Map<String, dynamic> entry) {
    final show = entry['show'] as Map<String, dynamic>? ?? {};
    return _tvMazeShowToContentItem(show);
  }

  /// Converts a raw TVmaze show JSON object to a [ContentItem].
  ContentItem _tvMazeShowToContentItem(Map<String, dynamic> show) {
    final showId = show['id'] as int? ?? 0;
    final imageJson = show['image'] as Map<String, dynamic>?;
    final ratingJson = show['rating'] as Map<String, dynamic>?;
    final networkJson = show['network'] as Map<String, dynamic>?;
    final externalsJson = show['externals'] as Map<String, dynamic>?;
    final genresRaw = show['genres'] as List<dynamic>? ?? [];
    final runtime = _toInt(show['runtime']);

    return ContentItem(
      sourcePluginId: _pluginId,
      externalId: 'tvmaze:$showId',
      contentType: ContentType.video,
      title: show['name'] as String? ?? '',
      description: _stripHtml(show['summary'] as String?),
      url: 'https://www.tvmaze.com/shows/$showId',
      thumbnailUrl: imageJson?['medium'] as String? ??
          imageJson?['original'] as String?,
      publishedAt: _parseDate(show['premiered'] as String?),
      metadata: VideoMeta(
        duration: runtime != null
            ? Duration(minutes: runtime)
            : null,
      ),
      tags: genresRaw.whereType<String>().toList(growable: false),
      extra: <String, String>{
        'tvmazeId': showId.toString(),
        'type': 'tv',
        if (externalsJson?['imdb'] != null)
          'imdbId': externalsJson!['imdb'] as String,
        if (ratingJson?['average'] != null)
          'rating': ratingJson!['average'].toString(),
        if (show['status'] != null)
          'status': show['status'] as String,
        if (networkJson?['name'] != null)
          'network': networkJson!['name'] as String,
      },
    );
  }

  /// Converts an IMDbAPI search result to a [ContentItem].
  ContentItem _imdbSearchResultToContentItem(Map<String, dynamic> json) {
    final imdbId = json['id'] as String? ?? '';
    final typeStr = json['type'] as String?;
    final mediaType = typeStr == 'series' ? 'tv' : 'movie';

    return ContentItem(
      sourcePluginId: _pluginId,
      externalId: 'imdb:$imdbId',
      contentType: ContentType.video,
      title: json['title'] as String? ?? '',
      thumbnailUrl: _naString(json['poster'] as String?),
      publishedAt: _yearToDate(json['year']),
      metadata: const VideoMeta(),
      tags: const [],
      extra: <String, String>{
        'imdbId': imdbId,
        'type': mediaType,
      },
    );
  }

  /// Converts an IMDbAPI title detail response to a [ContentItem].
  ContentItem _imdbDetailToContentItem(Map<String, dynamic> json) {
    final imdbId = json['id'] as String? ?? '';
    final typeStr = json['type'] as String?;
    final mediaType = typeStr == 'series' ? 'tv' : 'movie';
    final ratingMap = json['rating'] as Map<String, dynamic>?;
    final runtimeMinutes = _parseRuntime(json['runtime'] as String?);
    final genres = _toStringList(json['genres']);

    return ContentItem(
      sourcePluginId: _pluginId,
      externalId: 'imdb:$imdbId',
      contentType: ContentType.video,
      title: json['title'] as String? ?? '',
      description: _naString(json['plot'] as String?),
      url: 'https://www.imdb.com/title/$imdbId/',
      thumbnailUrl: _naString(json['poster'] as String?),
      publishedAt: _parseDate(json['released'] as String?) ??
          _yearToDate(json['year']),
      metadata: VideoMeta(
        duration: runtimeMinutes != null
            ? Duration(minutes: runtimeMinutes)
            : null,
      ),
      tags: genres,
      extra: <String, String>{
        'imdbId': imdbId,
        'type': mediaType,
        if (_toDouble(ratingMap?['average']) != null)
          'rating': _toDouble(ratingMap!['average'])!.toString(),
      },
    );
  }

  /// Converts a TMDB search result to a [ContentItem].
  ContentItem _tmdbResultToContentItem(Map<String, dynamic> json) {
    final isMovie = json['media_type'] == 'movie';
    final tmdbId = json['id'] as int? ?? 0;
    final title =
        (isMovie ? json['title'] : json['name']) as String? ?? '';
    final dateStr =
        (isMovie ? json['release_date'] : json['first_air_date']) as String?;
    final posterPath = json['poster_path'] as String?;
    final voteAvg = _toDouble(json['vote_average']);

    return ContentItem(
      sourcePluginId: _pluginId,
      externalId: 'tmdb:$tmdbId',
      contentType: ContentType.video,
      title: title,
      description: json['overview'] as String?,
      url: isMovie
          ? 'https://www.themoviedb.org/movie/$tmdbId'
          : 'https://www.themoviedb.org/tv/$tmdbId',
      thumbnailUrl:
          posterPath != null ? '$_tmdbImageBase$posterPath' : null,
      publishedAt: _parseDate(dateStr),
      metadata: const VideoMeta(),
      tags: const [],
      extra: <String, String>{
        'tmdbId': tmdbId.toString(),
        'type': isMovie ? 'movie' : 'tv',
        if (voteAvg != null) 'rating': voteAvg.toString(),
      },
    );
  }

  /// Converts a TMDB detail response (movie or tv) to a [ContentItem].
  ContentItem _tmdbDetailToContentItem(
    Map<String, dynamic> json,
    String mediaType,
  ) {
    final isMovie = mediaType == 'movie';
    final tmdbId = json['id'] as int? ?? 0;
    final title =
        (isMovie ? json['title'] : json['name']) as String? ?? '';
    final overview = json['overview'] as String?;
    final dateStr =
        (isMovie ? json['release_date'] : json['first_air_date']) as String?;
    final posterPath = json['poster_path'] as String?;
    final voteAvg = _toDouble(json['vote_average']);
    final runtime = isMovie ? _toInt(json['runtime']) : null;
    final genres = (json['genres'] as List<dynamic>?)
            ?.map((g) => (g as Map<String, dynamic>)['name'] as String)
            .toList(growable: false) ??
        const <String>[];
    final networks = !isMovie
        ? (json['networks'] as List<dynamic>?)
                ?.map((n) => (n as Map<String, dynamic>)['name'] as String)
                .toList(growable: false) ??
            const <String>[]
        : const <String>[];
    final externalIds = json['external_ids'] as Map<String, dynamic>?;
    final status = json['status'] as String?;

    return ContentItem(
      sourcePluginId: _pluginId,
      externalId: 'tmdb:$tmdbId',
      contentType: ContentType.video,
      title: title,
      description: overview,
      url: isMovie
          ? 'https://www.themoviedb.org/movie/$tmdbId'
          : 'https://www.themoviedb.org/tv/$tmdbId',
      thumbnailUrl:
          posterPath != null ? '$_tmdbImageBase$posterPath' : null,
      publishedAt: _parseDate(dateStr),
      metadata: VideoMeta(
        duration: runtime != null ? Duration(minutes: runtime) : null,
      ),
      tags: genres,
      extra: <String, String>{
        'tmdbId': tmdbId.toString(),
        'type': isMovie ? 'movie' : 'tv',
        if (voteAvg != null) 'rating': voteAvg.toString(),
        ?status: status,
        if (networks.isNotEmpty) 'network': networks.first,
        if (externalIds?['imdb_id'] != null)
          'imdbId': externalIds!['imdb_id'] as String,
      },
    );
  }

  // =======================================================================
  // Private — value helpers
  // =======================================================================

  /// Builds a normalised key for title + year deduplication.
  static String _dedupeKey(String title, int? year) {
    final normalised =
        title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return '$normalised:${year ?? ''}';
  }

  /// Strips HTML tags from a string, returning `null` for empty results.
  static String? _stripHtml(String? html) {
    if (html == null || html.isEmpty) return null;
    final text = html.replaceAll(_htmlTagRegex, '').trim();
    return text.isEmpty ? null : text;
  }

  /// Returns `null` when [value] is `null`, empty, or the literal `"N/A"`.
  static String? _naString(String? value) {
    if (value == null || value.isEmpty || value == 'N/A') return null;
    return value;
  }

  /// Safely parses a date string (ISO 8601 `YYYY-MM-DD` or similar).
  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty || value == 'N/A') return null;
    return DateTime.tryParse(value);
  }

  /// Converts a year value (int, double, or String) into a Jan 1 DateTime.
  static DateTime? _yearToDate(dynamic value) {
    final year = _toInt(value);
    if (year == null) return null;
    return DateTime(year);
  }

  /// Parses a runtime string like `"148 min"` into an integer.
  static int? _parseRuntime(String? value) {
    if (value == null || value.isEmpty || value == 'N/A') return null;
    final match = RegExp(r'(\d+)').firstMatch(value);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  /// Coerces a JSON value to [int].
  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString());
  }

  /// Coerces a JSON value to [double].
  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// Converts a JSON value to a `List<String>`.
  ///
  /// Handles both `List<dynamic>` and comma-separated `String`.
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
