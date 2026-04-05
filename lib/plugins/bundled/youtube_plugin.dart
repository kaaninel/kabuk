/// YouTube content plugin backed by Invidious / Piped public APIs.
///
/// Fetches videos, channels, and trending content from YouTube without
/// requiring an API key. An optional YouTube Data API v3 key can be
/// configured but is not used in the current implementation — the free
/// Invidious REST API is the default backend with Piped as a fallback.
library;

import 'dart:convert';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show IconData;
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/plugins/context.dart';
import 'package:kabuk/plugins/plugin.dart';
import 'package:meta/meta.dart';

/// Default Invidious instance used when the user has not configured one.
const _kDefaultInstance = 'https://vid.puffyan.us';

/// Piped API base URL used as a fallback when Invidious is unavailable.
const _kPipedApi = 'https://pipedapi.kavin.rocks';

/// Hosts recognised as YouTube domains.
const _kYouTubeHosts = {
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
  'youtu.be',
};

/// RegExp that extracts a YouTube video ID from common URL shapes.
final _videoIdPattern = RegExp(
  r'(?:youtu\.be/|youtube\.com/(?:watch\?.*v=|embed/|v/|shorts/))([A-Za-z0-9_-]{11})',
);

/// RegExp that extracts a channel identifier from a YouTube URL.
///
/// Matches `/channel/UC…`, `/c/name`, and `/@handle` paths.
final _channelPattern = RegExp(
  r'youtube\.com/(?:channel/([A-Za-z0-9_-]+)|c/([A-Za-z0-9_-]+)|@([A-Za-z0-9_.-]+))',
);

// ---------------------------------------------------------------------------
// YouTubePlugin
// ---------------------------------------------------------------------------

/// Content plugin that provides YouTube video search, channel feeds,
/// trending content, and URL resolution via the Invidious REST API.
///
/// When the configured Invidious instance is unreachable the plugin
/// automatically falls back to the Piped public API.
@immutable
class YouTubePlugin implements ContentPlugin {
  /// Creates a [YouTubePlugin].
  const YouTubePlugin();

  // -- identity -------------------------------------------------------------

  @override
  String get id => 'youtube';

  @override
  String get name => 'YouTube';

  @override
  String get description =>
      'Search, browse channels, and discover trending videos from YouTube.';

  @override
  String get version => '1.0.0';

  @override
  IconData get iconData => Icons.play_circle_outline;

  @override
  PluginCategory get category => PluginCategory.media;

  @override
  Set<ContentCapability> get capabilities => const {
    ContentCapability.search,
    ContentCapability.channel,
    ContentCapability.urlResolve,
    ContentCapability.trending,
  };

  @override
  bool hasCapability(ContentCapability capability) =>
      capabilities.contains(capability);

  @override
  List<PluginConfigField> get configFields => const [
    PluginConfigField(
      key: 'invidious_instance',
      label: 'Invidious instance',
      description: 'Base URL of the Invidious instance to use.',
      type: PluginConfigFieldType.text,
      defaultValue: _kDefaultInstance,
    ),
    PluginConfigField(
      key: 'youtube_api_key',
      label: 'YouTube Data API v3 key',
      description: 'Optional API key for higher rate limits.',
      type: PluginConfigFieldType.password,
      secret: true,
    ),
  ];

  // -- state ----------------------------------------------------------------

  /// Plugin context set during [initialize].
  ///
  /// Access is gated by [_ctx] which throws if used before init.
  // ignore: immutable — context is set once and never mutated afterwards.
  static PluginContext? _context;

  PluginContext get _ctx {
    final c = _context;
    if (c == null) {
      throw StateError('YouTubePlugin has not been initialized.');
    }
    return c;
  }

  /// Resolved Invidious base URL (no trailing slash).
  String get _instance {
    final configured = _ctx.getConfig('invidious_instance');
    final raw = (configured == null || configured.isEmpty)
        ? _kDefaultInstance
        : configured;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  // -- lifecycle ------------------------------------------------------------

  @override
  Future<void> initialize(PluginContext context) async {
    _context = context;
    context.log('YouTubePlugin initialized (instance: $_instance)');
  }

  @override
  Future<void> dispose() async {
    _context = null;
  }

  // -- URL handling ---------------------------------------------------------

  @override
  bool canHandleUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    final host = uri.host.toLowerCase();
    return _kYouTubeHosts.any(
      (yt) => host == yt || host.endsWith('.$yt'),
    );
  }

  @override
  Future<ResolvedContent> resolveUrl(String url) async {
    // Try video ID first.
    final videoMatch = _videoIdPattern.firstMatch(url);
    if (videoMatch != null) {
      final videoId = videoMatch.group(1)!;
      final item = await _fetchVideoDetail(videoId);
      if (item != null) return ResolvedContentItem(item);
    }

    // Try channel / handle URL.
    final channelMatch = _channelPattern.firstMatch(url);
    if (channelMatch != null) {
      final channelId =
          channelMatch.group(1) ??
          channelMatch.group(2) ??
          channelMatch.group(3);
      if (channelId != null) {
        final channel = await _resolveChannel(channelId);
        if (channel != null) return channel;
      }
    }

    return const ResolvedNotHandled();
  }

  // -- search ---------------------------------------------------------------

  @override
  Future<List<ContentItem>> search(
    String query, {
    int page = 0,
    int perPage = 20,
  }) async {
    // Invidious pages are 1-based.
    final ivPage = page + 1;

    final json = await _getJson(
      '$_instance/api/v1/search?q=${Uri.encodeQueryComponent(query)}'
      '&page=$ivPage&type=video',
    );

    if (json != null && json is List) {
      return [
        for (final item in json)
          if (item is Map<String, dynamic>) _mapSearchResult(item),
      ];
    }

    // Fallback: Piped search.
    _ctx.log('Invidious search failed, falling back to Piped');
    final piped = await _getJson(
      '$_kPipedApi/search?q=${Uri.encodeQueryComponent(query)}&filter=videos',
    );
    if (piped is Map<String, dynamic>) {
      final items = piped['items'];
      if (items is List) {
        return [
          for (final item in items)
            if (item is Map<String, dynamic>) _mapPipedResult(item),
        ];
      }
    }

    return const [];
  }

  // -- channel --------------------------------------------------------------

  @override
  Future<List<ContentItem>> fetchChannel(
    String entityId, {
    int page = 0,
    int perPage = 20,
  }) async {
    final ivPage = page + 1;
    final json = await _getJson(
      '$_instance/api/v1/channels/$entityId/videos?page=$ivPage',
    );

    if (json is Map<String, dynamic>) {
      final videos = json['videos'];
      if (videos is List) {
        return [
          for (final v in videos)
            if (v is Map<String, dynamic>) _mapSearchResult(v),
        ];
      }
    }

    // Fallback: Piped channel.
    _ctx.log('Invidious channel fetch failed, falling back to Piped');
    final piped = await _getJson('$_kPipedApi/channel/$entityId');
    if (piped is Map<String, dynamic>) {
      final items = piped['relatedStreams'];
      if (items is List) {
        return [
          for (final item in items)
            if (item is Map<String, dynamic>) _mapPipedResult(item),
        ];
      }
    }

    return const [];
  }

  // -- trending -------------------------------------------------------------

  @override
  Future<List<ContentItem>> fetchTrending({
    int page = 0,
    int perPage = 20,
  }) async {
    final json = await _getJson('$_instance/api/v1/trending');

    if (json != null && json is List) {
      return [
        for (final item in json)
          if (item is Map<String, dynamic>) _mapSearchResult(item),
      ];
    }

    // Fallback: Piped trending.
    _ctx.log('Invidious trending failed, falling back to Piped');
    final piped = await _getJson('$_kPipedApi/trending?region=US');
    if (piped is List) {
      return [
        for (final item in piped)
          if (item is Map<String, dynamic>) _mapPipedResult(item),
      ];
    }

    return const [];
  }

  // -- private helpers: networking ------------------------------------------

  /// GET [url] and decode JSON, returning `null` on any failure.
  Future<Object?> _getJson(String url) async {
    try {
      final response = await _ctx.httpClient.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      _ctx.log(
        'HTTP ${response.statusCode} from $url',
        error: response.reasonPhrase,
      );
    } catch (e) {
      _ctx.log('Request failed: $url', error: e.toString());
    }
    return null;
  }

  // -- private helpers: video detail ----------------------------------------

  /// Fetch full video details from Invidious (or Piped fallback) and
  /// return a [ContentItem] with a populated [VideoMeta].
  Future<ContentItem?> _fetchVideoDetail(String videoId) async {
    final json = await _getJson('$_instance/api/v1/videos/$videoId');
    if (json is Map<String, dynamic>) {
      return _mapVideoDetail(json);
    }

    // Fallback: Piped streams endpoint.
    _ctx.log('Invidious video detail failed, falling back to Piped');
    final piped = await _getJson('$_kPipedApi/streams/$videoId');
    if (piped is Map<String, dynamic>) {
      return _mapPipedVideoDetail(piped, videoId);
    }

    return null;
  }

  /// Resolve a channel identifier to a [ResolvedChannel].
  Future<ResolvedChannel?> _resolveChannel(String channelId) async {
    // Handle @username by searching Invidious.
    final path = channelId.startsWith('@')
        ? '/api/v1/channels/$channelId'
        : '/api/v1/channels/$channelId';

    final json = await _getJson('$_instance$path');
    if (json is Map<String, dynamic>) {
      final name = json['author'] as String? ?? channelId;
      final authorId = json['authorId'] as String? ?? channelId;
      final thumbs = json['authorThumbnails'];
      String? imageUrl;
      if (thumbs is List && thumbs.isNotEmpty) {
        final best = thumbs.last;
        if (best is Map<String, dynamic>) {
          imageUrl = best['url'] as String?;
        }
      }
      return ResolvedChannel(
        entityUri: 'youtube:channel:$authorId',
        title: name,
        imageUrl: imageUrl,
      );
    }
    return null;
  }

  // -- private helpers: Invidious mapping -----------------------------------

  /// Map an Invidious search / trending / channel-videos result to a
  /// [ContentItem].
  ContentItem _mapSearchResult(Map<String, dynamic> json) {
    final videoId = json['videoId'] as String? ?? '';
    final lengthSeconds = _toInt(json['lengthSeconds']);
    final viewCount = _toInt(json['viewCount']);

    return ContentItem(
      sourcePluginId: id,
      externalId: videoId,
      contentType: ContentType.video,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      url: 'https://www.youtube.com/watch?v=$videoId',
      thumbnailUrl: _bestThumbnail(json) ??
          'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      author: ContentAuthor(
        name: json['author'] as String?,
        url: '$_instance/channel/${json['authorId'] ?? ''}',
      ),
      metadata: VideoMeta(
        duration: lengthSeconds != null
            ? Duration(seconds: lengthSeconds)
            : null,
        streamUrl: '$_instance/latest_version?id=$videoId&itag=18',
      ),
      tags: _extractKeywords(json),
      extra: {
        'videoId': videoId,
        if (viewCount != null) 'viewCount': viewCount.toString(),
        if (json['authorId'] != null)
          'channelId': json['authorId'] as String,
        if (json['publishedText'] != null)
          'publishedText': json['publishedText'] as String,
      },
    );
  }

  /// Map a full Invidious video-detail response to a [ContentItem] with
  /// rich [VideoMeta] including quality variants.
  ContentItem _mapVideoDetail(Map<String, dynamic> json) {
    final videoId = json['videoId'] as String? ?? '';
    final lengthSeconds = _toInt(json['lengthSeconds']);
    final viewCount = _toInt(json['viewCount']);
    final likeCount = _toInt(json['likeCount']);

    // Build quality list from formatStreams.
    final qualities = <VideoQuality>[];
    String? bestStreamUrl;

    final formatStreams = json['formatStreams'];
    if (formatStreams is List) {
      for (final fmt in formatStreams) {
        if (fmt is! Map<String, dynamic>) continue;
        final url = fmt['url'] as String?;
        final label = fmt['qualityLabel'] as String? ??
            fmt['quality'] as String? ??
            'unknown';
        if (url != null) {
          qualities.add(
            VideoQuality(
              label: label,
              url: url,
              width: _toInt(fmt['width']),
              height: _toInt(fmt['height']),
            ),
          );
          // Prefer the highest-resolution MP4.
          bestStreamUrl ??= url;
        }
      }
    }

    // Fall back to adaptive formats if no format streams.
    if (bestStreamUrl == null) {
      final adaptive = json['adaptiveFormats'];
      if (adaptive is List) {
        for (final fmt in adaptive) {
          if (fmt is! Map<String, dynamic>) continue;
          final url = fmt['url'] as String?;
          final mime = fmt['type'] as String? ?? '';
          if (url != null && mime.startsWith('video/')) {
            final label = fmt['qualityLabel'] as String? ??
                fmt['quality'] as String? ??
                'unknown';
            qualities.add(
              VideoQuality(
                label: label,
                url: url,
                width: _toInt(fmt['width']),
                height: _toInt(fmt['height']),
              ),
            );
            bestStreamUrl ??= url;
          }
        }
      }
    }

    // Ultimate fallback for streamUrl.
    bestStreamUrl ??= '$_instance/latest_version?id=$videoId&itag=18';

    final hlsUrl = json['hlsUrl'] as String?;

    // Timestamp handling.
    DateTime? published;
    final publishedEpoch = _toInt(json['published']);
    if (publishedEpoch != null) {
      published = DateTime.fromMillisecondsSinceEpoch(
        publishedEpoch * 1000,
        isUtc: true,
      );
    }

    return ContentItem(
      sourcePluginId: id,
      externalId: videoId,
      contentType: ContentType.video,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      url: 'https://www.youtube.com/watch?v=$videoId',
      thumbnailUrl: _bestThumbnail(json) ??
          'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      publishedAt: published,
      author: ContentAuthor(
        name: json['author'] as String?,
        url: '$_instance/channel/${json['authorId'] ?? ''}',
        avatarUrl: _authorThumbnail(json),
      ),
      metadata: VideoMeta(
        duration: lengthSeconds != null
            ? Duration(seconds: lengthSeconds)
            : null,
        streamUrl: bestStreamUrl,
        hlsUrl: hlsUrl,
        qualities: qualities,
      ),
      tags: _extractKeywords(json),
      extra: {
        'videoId': videoId,
        if (viewCount != null) 'viewCount': viewCount.toString(),
        if (likeCount != null) 'likeCount': likeCount.toString(),
        if (json['authorId'] != null)
          'channelId': json['authorId'] as String,
      },
    );
  }

  // -- private helpers: Piped mapping ---------------------------------------

  /// Map a Piped search result item to a [ContentItem].
  ContentItem _mapPipedResult(Map<String, dynamic> json) {
    final url = json['url'] as String? ?? '';
    final videoId = _extractVideoIdFromPath(url);
    final durationSeconds = _toInt(json['duration']);

    return ContentItem(
      sourcePluginId: id,
      externalId: videoId,
      contentType: ContentType.video,
      title: json['title'] as String? ?? '',
      description: json['shortDescription'] as String?,
      url: 'https://www.youtube.com/watch?v=$videoId',
      thumbnailUrl: json['thumbnail'] as String? ??
          'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      author: ContentAuthor(
        name: json['uploaderName'] as String?,
        url: json['uploaderUrl'] != null
            ? 'https://www.youtube.com${json['uploaderUrl']}'
            : null,
        avatarUrl: json['uploaderAvatar'] as String?,
      ),
      metadata: VideoMeta(
        duration: durationSeconds != null
            ? Duration(seconds: durationSeconds)
            : null,
        streamUrl: '$_instance/latest_version?id=$videoId&itag=18',
      ),
      extra: {
        'videoId': videoId,
        if (json['views'] != null) 'viewCount': json['views'].toString(),
        if (json['uploaderUrl'] != null)
          'channelId': _extractChannelIdFromPath(
            json['uploaderUrl'] as String,
          ),
      },
    );
  }

  /// Map a Piped `/streams/{id}` response to a [ContentItem].
  ContentItem _mapPipedVideoDetail(
    Map<String, dynamic> json,
    String videoId,
  ) {
    final durationSeconds = _toInt(json['duration']);
    final qualities = <VideoQuality>[];
    String? bestStreamUrl;

    final videoStreams = json['videoStreams'];
    if (videoStreams is List) {
      for (final s in videoStreams) {
        if (s is! Map<String, dynamic>) continue;
        final url = s['url'] as String?;
        final quality = s['quality'] as String? ?? 'unknown';
        if (url != null) {
          qualities.add(
            VideoQuality(
              label: quality,
              url: url,
              width: _toInt(s['width']),
              height: _toInt(s['height']),
            ),
          );
          bestStreamUrl ??= url;
        }
      }
    }

    bestStreamUrl ??= '$_instance/latest_version?id=$videoId&itag=18';

    final hlsUrl = json['hls'] as String?;

    // Timestamp.
    DateTime? published;
    final uploadDate = json['uploadDate'] as String?;
    if (uploadDate != null) {
      published = DateTime.tryParse(uploadDate);
    }

    return ContentItem(
      sourcePluginId: id,
      externalId: videoId,
      contentType: ContentType.video,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      url: 'https://www.youtube.com/watch?v=$videoId',
      thumbnailUrl: json['thumbnailUrl'] as String? ??
          'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      publishedAt: published,
      author: ContentAuthor(
        name: json['uploader'] as String?,
        url: json['uploaderUrl'] != null
            ? 'https://www.youtube.com${json['uploaderUrl']}'
            : null,
        avatarUrl: json['uploaderAvatar'] as String?,
      ),
      metadata: VideoMeta(
        duration: durationSeconds != null
            ? Duration(seconds: durationSeconds)
            : null,
        streamUrl: bestStreamUrl,
        hlsUrl: hlsUrl,
        qualities: qualities,
      ),
      extra: {
        'videoId': videoId,
        if (json['views'] != null) 'viewCount': json['views'].toString(),
        if (json['likes'] != null) 'likeCount': json['likes'].toString(),
        if (json['uploaderUrl'] != null)
          'channelId': _extractChannelIdFromPath(
            json['uploaderUrl'] as String,
          ),
      },
    );
  }

  // -- private helpers: utilities -------------------------------------------

  /// Pick the highest-quality thumbnail URL from an Invidious result.
  String? _bestThumbnail(Map<String, dynamic> json) {
    final thumbs = json['videoThumbnails'];
    if (thumbs is! List || thumbs.isEmpty) return null;
    // Thumbnails are ordered smallest→largest; take the last.
    final best = thumbs.last;
    if (best is Map<String, dynamic>) {
      return best['url'] as String?;
    }
    return null;
  }

  /// Extract the author thumbnail from an Invidious video detail.
  String? _authorThumbnail(Map<String, dynamic> json) {
    final thumbs = json['authorThumbnails'];
    if (thumbs is! List || thumbs.isEmpty) return null;
    final best = thumbs.last;
    if (best is Map<String, dynamic>) {
      return best['url'] as String?;
    }
    return null;
  }

  /// Extract keywords from the `keywords` field.
  List<String> _extractKeywords(Map<String, dynamic> json) {
    final kw = json['keywords'];
    if (kw is List) {
      return [for (final k in kw) if (k is String) k];
    }
    return const [];
  }

  /// Safely convert a value to [int], handling both int and String.
  static int? _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Extract a video ID from a relative or absolute path like
  /// `/watch?v=abc123` or full URL.
  static String _extractVideoIdFromPath(String path) {
    final match = _videoIdPattern.firstMatch(path);
    if (match != null) return match.group(1)!;
    // Piped gives paths like `/watch?v=ID`.
    final uri = Uri.tryParse('https://youtube.com$path');
    return uri?.queryParameters['v'] ?? path;
  }

  /// Extract a channel ID from a Piped uploader path like `/channel/UCxxx`.
  static String _extractChannelIdFromPath(String path) {
    final parts = path.split('/');
    // Expected: /channel/UCxxx
    if (parts.length >= 3 && parts[1] == 'channel') return parts[2];
    return path;
  }
}
