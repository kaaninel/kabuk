/// Bandcamp content plugin for Kabuk.
///
/// Adapts Bandcamp's publicly accessible web pages into [ContentItem]
/// objects. Because Bandcamp has no official public API, this plugin
/// relies on HTML scraping and LD+JSON extraction. The parsing is
/// inherently fragile — any change to Bandcamp's markup may break
/// results. Errors are logged and empty lists returned rather than
/// throwing.
library;

import 'dart:convert';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show IconData;
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/plugins/context.dart';
import 'package:kabuk/plugins/plugin.dart';
import 'package:meta/meta.dart';

/// A [ContentPlugin] that scrapes tracks and albums from Bandcamp.
///
/// Supported operations:
/// - **search** — scrapes `bandcamp.com/search` for tracks and albums.
/// - **urlResolve** — fetches a Bandcamp page and extracts LD+JSON
///   (Schema.org `MusicAlbum` / `MusicRecording`) metadata.
///
/// Channel and trending endpoints are not supported.
@immutable
class BandcampPlugin implements ContentPlugin {
  /// Creates a [BandcampPlugin].
  const BandcampPlugin();

  @override
  String get id => 'bandcamp';

  @override
  String get name => 'Bandcamp';

  @override
  String get description =>
      'Discover tracks and albums from Bandcamp via web scraping.';

  @override
  String get version => '1.0.0';

  @override
  IconData get iconData => Icons.album_outlined;

  @override
  PluginCategory get category => PluginCategory.music;

  @override
  Set<ContentCapability> get capabilities => const {
        ContentCapability.search,
        ContentCapability.urlResolve,
      };

  @override
  List<PluginConfigField> get configFields => const [];

  @override
  bool hasCapability(ContentCapability capability) =>
      capabilities.contains(capability);

  @override
  Future<void> initialize(PluginContext context) async {
    _context = context;
  }

  @override
  Future<void> dispose() async {
    _context = null;
  }

  // ---------------------------------------------------------------------------
  // URL handling
  // ---------------------------------------------------------------------------

  /// Matches `*.bandcamp.com` and `bandcamp.com` URLs.
  @override
  bool canHandleUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host == 'bandcamp.com' || uri.host.endsWith('.bandcamp.com');
  }

  @override
  Future<ResolvedContent> resolveUrl(String url) async {
    final ctx = _context;
    if (ctx == null) return const ResolvedNotHandled();

    try {
      final response = await ctx.httpClient.get(Uri.parse(url));
      if (response.statusCode != 200) return const ResolvedNotHandled();

      final ldJson = _extractLdJson(response.body);
      if (ldJson == null) return const ResolvedNotHandled();

      final type = ldJson['@type'] as String? ?? '';

      if (type == 'MusicRecording') {
        return ResolvedContentItem(_ldJsonTrackToContentItem(ldJson, url));
      }

      if (type == 'MusicAlbum') {
        return ResolvedContentItem(_ldJsonAlbumToContentItem(ldJson, url));
      }

      return const ResolvedNotHandled();
    } catch (e) {
      ctx.log('resolveUrl failed', error: e.toString());
      return const ResolvedNotHandled();
    }
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  @override
  Future<List<ContentItem>> search(
    String query, {
    int page = 0,
    int perPage = 20,
  }) async {
    final ctx = _context;
    if (ctx == null) return const [];

    try {
      // Bandcamp uses 1-based page numbering.
      final pageNum = page + 1;
      final uri = Uri.parse(
        'https://bandcamp.com/search'
        '?q=${Uri.encodeComponent(query)}'
        '&item_type=t'
        '&page=$pageNum',
      );
      final response = await ctx.httpClient.get(uri);
      if (response.statusCode != 200) return const [];

      return _parseSearchResults(response.body);
    } catch (e) {
      _context?.log('search failed', error: e.toString());
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Unsupported capabilities
  // ---------------------------------------------------------------------------

  @override
  Future<List<ContentItem>> fetchChannel(
    String entityId, {
    int page = 0,
    int perPage = 20,
  }) {
    throw UnsupportedError('Bandcamp does not support channel feeds.');
  }

  @override
  Future<List<ContentItem>> fetchTrending({
    int page = 0,
    int perPage = 20,
  }) {
    throw UnsupportedError('Bandcamp does not support trending feeds.');
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Mutable context reference — set during [initialize], cleared on
  /// [dispose]. Not part of the public API.
  static PluginContext? _context;

  // ---- LD+JSON helpers -----------------------------------------------------

  /// Extracts the first `application/ld+json` block from [html].
  ///
  /// Returns the decoded JSON map, or `null` if extraction fails.
  static Map<String, dynamic>? _extractLdJson(String html) {
    final pattern = RegExp(
      r'<script[^>]+type="application/ld\+json"[^>]*>([\s\S]*?)</script>',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(html);
    if (match == null) return null;

    try {
      final decoded = json.decode(match.group(1)!);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is List && decoded.isNotEmpty) {
        return decoded.first as Map<String, dynamic>;
      }
    } catch (_) {
      // Malformed JSON — fall through.
    }
    return null;
  }

  /// Converts a Schema.org `MusicRecording` LD+JSON to a [ContentItem].
  ContentItem _ldJsonTrackToContentItem(
    Map<String, dynamic> ld,
    String pageUrl,
  ) {
    final byArtist = ld['byArtist'] as Map<String, dynamic>?;
    final artistName = byArtist?['name'] as String?;
    final inAlbum = ld['inAlbum'] as Map<String, dynamic>?;
    final albumName = inAlbum?['name'] as String?;
    final imageUrl = _firstImage(ld['image']);
    final durationIso = ld['duration'] as String?;

    return ContentItem(
      sourcePluginId: id,
      externalId: _externalIdFromUrl(pageUrl),
      contentType: ContentType.audio,
      title: (ld['name'] as String?) ?? 'Untitled',
      description: ld['description'] as String?,
      url: pageUrl,
      thumbnailUrl: imageUrl,
      publishedAt: _parseDate(ld['datePublished'] as String?),
      author: ContentAuthor(
        name: artistName,
        url: byArtist?['@id'] as String?,
      ),
      metadata: AudioMeta(
        duration: _parseIsoDuration(durationIso),
        artist: artistName,
        album: albumName,
        artworkUrl: imageUrl,
      ),
      extra: {
        'bandcampUrl': pageUrl,
        'albumTitle': ?albumName,
        if (ld['datePublished'] != null)
          'releaseDate': ld['datePublished'] as String,
      },
    );
  }

  /// Converts a Schema.org `MusicAlbum` LD+JSON to a [ContentItem].
  ContentItem _ldJsonAlbumToContentItem(
    Map<String, dynamic> ld,
    String pageUrl,
  ) {
    final byArtist = ld['byArtist'] as Map<String, dynamic>?;
    final artistName = byArtist?['name'] as String?;
    final imageUrl = _firstImage(ld['image']);

    return ContentItem(
      sourcePluginId: id,
      externalId: _externalIdFromUrl(pageUrl),
      contentType: ContentType.audio,
      title: (ld['name'] as String?) ?? 'Untitled Album',
      description: ld['description'] as String?,
      url: pageUrl,
      thumbnailUrl: imageUrl,
      publishedAt: _parseDate(ld['datePublished'] as String?),
      author: ContentAuthor(
        name: artistName,
        url: byArtist?['@id'] as String?,
      ),
      metadata: AudioMeta(
        artist: artistName,
        artworkUrl: imageUrl,
      ),
      extra: {
        'bandcampUrl': pageUrl,
        if (ld['name'] != null) 'albumTitle': ld['name'] as String,
        if (ld['datePublished'] != null)
          'releaseDate': ld['datePublished'] as String,
      },
    );
  }

  // ---- HTML search result parsing ------------------------------------------

  /// Parses search result HTML from `bandcamp.com/search` into content items.
  List<ContentItem> _parseSearchResults(String html) {
    final results = <ContentItem>[];

    // Each search result lives inside <li class="searchresult ...">
    final resultPattern = RegExp(
      r'<li\s+class="searchresult[^"]*">([\s\S]*?)</li>',
    );

    for (final block in resultPattern.allMatches(html)) {
      try {
        final fragment = block.group(1) ?? '';

        final title = _extractText(fragment, r'class="heading"[^>]*>(.*?)<');
        if (title == null || title.isEmpty) continue;

        final subhead = _extractText(fragment, r'class="subhead"[^>]*>(.*?)<');
        final artist = _parseArtistFromSubhead(subhead);
        final albumTitle = _parseAlbumFromSubhead(subhead);

        final itemUrl =
            _extractAttr(fragment, r'class="itemurl"[^>]*>[^<]*<a[^>]+href="([^"]+)"') ??
            _extractAttr(fragment, r'class="heading"[^>]*>\s*<a[^>]+href="([^"]+)"');

        final artworkUrl =
            _extractAttr(fragment, r'<img[^>]+src="([^"]+)"');

        if (itemUrl == null) continue;

        results.add(
          ContentItem(
            sourcePluginId: id,
            externalId: _externalIdFromUrl(itemUrl),
            contentType: ContentType.audio,
            title: title,
            url: itemUrl,
            thumbnailUrl: artworkUrl,
            author: ContentAuthor(name: artist),
            metadata: AudioMeta(
              artist: artist,
              artworkUrl: artworkUrl,
            ),
            extra: {
              'bandcampUrl': itemUrl,
              'albumTitle': ?albumTitle,
            },
          ),
        );
      } catch (e) {
        _context?.log('Failed to parse search result', error: e.toString());
      }
    }

    return results;
  }

  // ---- Utility helpers -----------------------------------------------------

  /// Extracts the first captured group from [pattern] within [source].
  static String? _extractText(String source, String pattern) {
    final match = RegExp(pattern, caseSensitive: false).firstMatch(source);
    return match?.group(1)?.trim();
  }

  /// Extracts an attribute value via the first captured group of [pattern].
  static String? _extractAttr(String source, String pattern) {
    final match = RegExp(pattern, caseSensitive: false).firstMatch(source);
    return match?.group(1)?.trim();
  }

  /// Extracts the artist name from a Bandcamp search subhead string.
  ///
  /// Subhead format is typically `"by <artist>"` or
  /// `"from <album> by <artist>"`.
  static String? _parseArtistFromSubhead(String? subhead) {
    if (subhead == null) return null;
    final byMatch = RegExp(r'by\s+(.+)', caseSensitive: false)
        .firstMatch(subhead);
    return byMatch?.group(1)?.trim();
  }

  /// Extracts the album name from a Bandcamp search subhead string.
  ///
  /// Returns the album title if the format is `"from <album> by ..."`.
  static String? _parseAlbumFromSubhead(String? subhead) {
    if (subhead == null) return null;
    final fromMatch =
        RegExp(r'from\s+(.+?)\s+by', caseSensitive: false)
            .firstMatch(subhead);
    return fromMatch?.group(1)?.trim();
  }

  /// Derives a stable external ID from a Bandcamp URL.
  ///
  /// Uses the host + path to form a unique key (e.g.
  /// `"artist.bandcamp.com/track/song-title"`).
  static String _externalIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return '${uri.host}${uri.path}';
  }

  /// Resolves the first image URL from a Schema.org `image` field.
  ///
  /// The field may be a plain string, a list of strings, or a list of
  /// `ImageObject` maps.
  static String? _firstImage(Object? imageField) {
    if (imageField is String) return imageField;
    if (imageField is List && imageField.isNotEmpty) {
      final first = imageField.first;
      if (first is String) return first;
      if (first is Map<String, dynamic>) return first['url'] as String?;
    }
    return null;
  }

  /// Parses an ISO 8601 date string (e.g. `"2024-03-15"`) into [DateTime].
  static DateTime? _parseDate(String? value) {
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  /// Parses an ISO 8601 duration string (e.g. `"PT3M45S"`) into [Duration].
  static Duration? _parseIsoDuration(String? value) {
    if (value == null) return null;

    final pattern = RegExp(
      r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(value);
    if (match == null) return null;

    final hours = int.tryParse(match.group(1) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
    final secondsStr = match.group(3);
    final seconds = secondsStr != null ? double.tryParse(secondsStr) ?? 0 : 0;

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds.toInt(),
      milliseconds: ((seconds % 1) * 1000).toInt(),
    );
  }
}
