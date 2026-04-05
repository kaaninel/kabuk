/// SoundCloud content plugin for Kabuk.
///
/// Adapts the SoundCloud public API (v2) into [ContentItem] objects.
/// Uses client-ID auto-discovery from the SoundCloud homepage — no
/// API key configuration is required.
library;

import 'dart:convert';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show IconData;
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/plugins/context.dart';
import 'package:kabuk/plugins/plugin.dart';
import 'package:meta/meta.dart';

/// A [ContentPlugin] that fetches tracks from SoundCloud.
///
/// The SoundCloud public API requires a `client_id` query parameter.
/// This plugin discovers the ID automatically by scraping the
/// SoundCloud homepage for cross-origin script URLs and extracting
/// the `client_id` value from one of those scripts.
///
/// If discovery fails (e.g. SoundCloud changes their page structure),
/// the plugin gracefully returns empty results from all methods rather
/// than crashing.
@immutable
class SoundCloudPlugin implements ContentPlugin {
  /// Creates a [SoundCloudPlugin].
  const SoundCloudPlugin();

  @override
  String get id => 'soundcloud';

  @override
  String get name => 'SoundCloud';

  @override
  String get description =>
      'Search and stream tracks from SoundCloud using the public API.';

  @override
  String get version => '1.0.0';

  @override
  IconData get iconData => Icons.music_note_outlined;

  @override
  PluginCategory get category => PluginCategory.music;

  @override
  Set<ContentCapability> get capabilities => const {
        ContentCapability.search,
        ContentCapability.channel,
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
    _clientId = null;
    await _discoverClientId();
  }

  @override
  Future<void> dispose() async {
    _clientId = null;
    _context = null;
  }

  // ---------------------------------------------------------------------------
  // URL handling
  // ---------------------------------------------------------------------------

  @override
  bool canHandleUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host == 'soundcloud.com' ||
        uri.host.endsWith('.soundcloud.com');
  }

  @override
  Future<ResolvedContent> resolveUrl(String url) async {
    final ctx = _context;
    if (ctx == null || _clientId == null) return const ResolvedNotHandled();

    try {
      final resolveUri = Uri.parse(
        'https://api-v2.soundcloud.com/resolve'
        '?url=${Uri.encodeComponent(url)}'
        '&client_id=$_clientId',
      );
      final response = await ctx.httpClient.get(resolveUri);
      if (response.statusCode != 200) return const ResolvedNotHandled();

      final data = json.decode(response.body) as Map<String, dynamic>;
      final kind = data['kind'] as String?;

      if (kind == 'track') {
        return ResolvedContentItem(_trackToContentItem(data));
      }

      if (kind == 'user') {
        return ResolvedChannel(
          entityUri: 'soundcloud:user:${data['id']}',
          title: (data['username'] as String?) ?? 'Unknown',
          imageUrl: data['avatar_url'] as String?,
        );
      }

      // Playlist / other entity — treat as channel.
      if (kind == 'playlist') {
        return ResolvedChannel(
          entityUri: 'soundcloud:playlist:${data['id']}',
          title: (data['title'] as String?) ?? 'Playlist',
          imageUrl: data['artwork_url'] as String?,
        );
      }

      return const ResolvedNotHandled();
    } catch (e) {
      _context?.log('resolveUrl failed', error: e.toString());
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
    if (ctx == null || _clientId == null) return const [];

    try {
      final uri = Uri.parse(
        'https://api-v2.soundcloud.com/search/tracks'
        '?q=${Uri.encodeComponent(query)}'
        '&limit=$perPage'
        '&offset=${page * perPage}'
        '&client_id=$_clientId',
      );
      final response = await ctx.httpClient.get(uri);
      if (response.statusCode != 200) return const [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final collection = data['collection'] as List<dynamic>? ?? [];

      return collection
          .whereType<Map<String, dynamic>>()
          .map(_trackToContentItem)
          .toList();
    } catch (e) {
      _context?.log('search failed', error: e.toString());
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Channel (user tracks)
  // ---------------------------------------------------------------------------

  @override
  Future<List<ContentItem>> fetchChannel(
    String entityId, {
    int page = 0,
    int perPage = 20,
  }) async {
    final ctx = _context;
    if (ctx == null || _clientId == null) return const [];

    try {
      final uri = Uri.parse(
        'https://api-v2.soundcloud.com/users/$entityId/tracks'
        '?limit=$perPage'
        '&offset=${page * perPage}'
        '&client_id=$_clientId',
      );
      final response = await ctx.httpClient.get(uri);
      if (response.statusCode != 200) return const [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final collection = data['collection'] as List<dynamic>? ?? [];

      return collection
          .whereType<Map<String, dynamic>>()
          .map(_trackToContentItem)
          .toList();
    } catch (e) {
      _context?.log('fetchChannel failed', error: e.toString());
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Trending — not supported
  // ---------------------------------------------------------------------------

  @override
  Future<List<ContentItem>> fetchTrending({
    int page = 0,
    int perPage = 20,
  }) {
    throw UnsupportedError(
      'SoundCloud trending is not available via the public API.',
    );
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Mutable context reference — set during [initialize], cleared on
  /// [dispose]. Not part of the public API.
  static PluginContext? _context;

  /// Discovered client ID, cached in memory.
  static String? _clientId;

  /// Attempts to discover the SoundCloud `client_id` from the homepage.
  ///
  /// 1. Fetches `https://soundcloud.com`.
  /// 2. Extracts `<script crossorigin src="...">` URLs.
  /// 3. Fetches each script until a `client_id:"<value>"` match is found.
  Future<void> _discoverClientId() async {
    final ctx = _context;
    if (ctx == null) return;

    try {
      final homeResponse = await ctx.httpClient.get(
        Uri.parse('https://soundcloud.com'),
      );
      if (homeResponse.statusCode != 200) {
        ctx.log('client_id discovery: homepage returned '
            '${homeResponse.statusCode}');
        return;
      }

      final scriptPattern =
          RegExp(r'<script[^>]+crossorigin[^>]+src="([^"]+)"');
      final scriptUrls = scriptPattern
          .allMatches(homeResponse.body)
          .map((m) => m.group(1))
          .whereType<String>()
          .toList();

      for (final scriptUrl in scriptUrls.reversed) {
        try {
          final scriptResponse =
              await ctx.httpClient.get(Uri.parse(scriptUrl));
          if (scriptResponse.statusCode != 200) continue;

          final idPattern = RegExp(r'client_id:"([a-zA-Z0-9]+)"');
          final match = idPattern.firstMatch(scriptResponse.body);
          if (match != null) {
            _clientId = match.group(1);
            ctx.log('Discovered SoundCloud client_id');
            return;
          }
        } catch (_) {
          // Try next script.
        }
      }

      ctx.log('client_id discovery: no client_id found in scripts');
    } catch (e) {
      ctx.log('client_id discovery failed', error: e.toString());
    }
  }

  /// Converts a SoundCloud track JSON object into a [ContentItem].
  ContentItem _trackToContentItem(Map<String, dynamic> track) {
    final user = track['user'] as Map<String, dynamic>? ?? {};
    final durationMs = track['duration'] as int?;
    final artworkUrl = track['artwork_url'] as String?;
    final highResArtwork = artworkUrl?.replaceAll('-large', '-t500x500');

    final streamUrl = track['stream_url'] as String?;
    final qualifiedStreamUrl =
        (streamUrl != null && _clientId != null)
            ? '$streamUrl?client_id=$_clientId'
            : null;

    DateTime? publishedAt;
    final createdAt = track['created_at'] as String?;
    if (createdAt != null) {
      publishedAt = DateTime.tryParse(createdAt);
    }

    final tagList = track['tag_list'] as String? ?? '';
    final tags = tagList.isEmpty
        ? <String>[]
        : tagList.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    final genre = track['genre'] as String?;
    if (genre != null && genre.isNotEmpty && !tags.contains(genre)) {
      tags.insert(0, genre);
    }

    return ContentItem(
      sourcePluginId: id,
      externalId: '${track['id']}',
      contentType: ContentType.audio,
      title: (track['title'] as String?) ?? 'Untitled',
      description: track['description'] as String?,
      url: track['permalink_url'] as String?,
      thumbnailUrl: artworkUrl,
      publishedAt: publishedAt,
      author: ContentAuthor(
        name: user['username'] as String?,
        avatarUrl: user['avatar_url'] as String?,
        url: user['permalink_url'] as String?,
      ),
      metadata: AudioMeta(
        duration: durationMs != null
            ? Duration(milliseconds: durationMs)
            : null,
        artist: user['username'] as String?,
        streamUrl: qualifiedStreamUrl,
        artworkUrl: highResArtwork,
      ),
      tags: tags,
      extra: {
        if (track['playback_count'] != null)
          'playbackCount': '${track['playback_count']}',
        if (genre != null && genre.isNotEmpty) 'genre': genre,
        'scId': '${track['id']}',
      },
    );
  }
}
