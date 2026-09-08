/// Reddit content plugin.
///
/// Adapts Reddit's public JSON API into the Kabuk [ContentPlugin]
/// interface. Supports search, subreddit channel feeds, URL resolution,
/// and trending content from r/popular. No API key is required — all
/// requests use the unauthenticated `.json` endpoints.
library;

import 'dart:convert';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show IconData;
import 'package:kabuk/platform/shared/reddit_api.dart';
import 'package:kabuk/plugins/channel.dart';
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/plugins/context.dart';
import 'package:kabuk/plugins/plugin.dart';

/// A [ContentPlugin] for Reddit.
///
/// Uses Reddit's public JSON API (no OAuth) to fetch posts from
/// subreddits, search across all of Reddit, resolve Reddit URLs, and
/// surface trending content from r/popular. Requests go through the shared
/// Reddit API helpers (descriptive User-Agent + host fallback) so a 403 on
/// one host doesn't break the plugin.
///
/// ```dart
/// final plugin = RedditPlugin();
/// await plugin.initialize(context);
/// final items = await plugin.fetchTrending();
/// ```
class RedditPlugin implements ContentPlugin {
  /// Creates a [RedditPlugin].
  RedditPlugin();

  late PluginContext _ctx;

  /// Common HTTP headers for Reddit JSON API requests.
  static const _headers = kRedditHeaders;

  /// Hosts recognised as Reddit domains.
  static const _redditHosts = {
    'reddit.com',
    'www.reddit.com',
    'old.reddit.com',
    'redd.it',
    'i.redd.it',
  };

  // ---------------------------------------------------------------------------
  // ContentPlugin identity
  // ---------------------------------------------------------------------------

  @override
  String get id => 'reddit';

  @override
  String get name => 'Reddit';

  @override
  String get description =>
      'Browse subreddits, search posts, and view trending content from Reddit.';

  @override
  String get version => '1.0.0';

  @override
  IconData get iconData => Icons.forum;

  @override
  PluginCategory get category => PluginCategory.social;

  @override
  Set<ContentCapability> get capabilities => const {
        ContentCapability.search,
        ContentCapability.channel,
        ContentCapability.urlResolve,
        ContentCapability.trending,
      };

  @override
  List<PluginConfigField> get configFields => const [];

  @override
  bool hasCapability(ContentCapability capability) =>
      capabilities.contains(capability);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> initialize(PluginContext context) async {
    _ctx = context;
    _ctx.log('Reddit plugin initialized');
  }

  @override
  Future<void> dispose() async {
    // No resources to release.
  }

  // ---------------------------------------------------------------------------
  // URL handling
  // ---------------------------------------------------------------------------

  @override
  bool canHandleUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    final host = uri.host.toLowerCase();
    return _redditHosts.any(
      (h) => host == h || host.endsWith('.$h'),
    );
  }

  @override
  Future<ResolvedContent> resolveUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return const ResolvedNotHandled();

    final path = uri.path;

    // Match subreddit root: /r/{name} or /r/{name}/
    final subredditPattern = RegExp(r'^/r/([A-Za-z0-9_]+)/?$');
    final subredditMatch = subredditPattern.firstMatch(path);
    if (subredditMatch != null) {
      final sub = subredditMatch.group(1)!;
      return ResolvedChannel(
        entityUri: 'reddit:subreddit:$sub',
        title: 'r/$sub',
        imageUrl: null,
        sourcePluginId: id,
        externalEntityId: sub,
        entityType: ChannelEntityType.subreddit,
      );
    }

    // Match post URL: /r/{sub}/comments/{id}/...
    final postPattern = RegExp(
      r'^/r/([A-Za-z0-9_]+)/comments/([A-Za-z0-9]+)',
    );
    final postMatch = postPattern.firstMatch(path);
    if (postMatch != null) {
      final postId = postMatch.group(2)!;
      // Fetch the single post to build a ContentItem.
      try {
        final response = await fetchRedditJson(
          get: (uri) async {
            final res = await _ctx.httpClient.get(uri, headers: _headers);
            return (statusCode: res.statusCode, body: res.body);
          },
          pathOrUrl: '$path.json?raw_json=1',
        );
        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          // Reddit returns a list of listings for post pages.
          if (json is List && json.isNotEmpty) {
            final listing = json[0] as Map<String, dynamic>;
            final children =
                (listing['data'] as Map<String, dynamic>?)?['children']
                    as List<dynamic>?;
            if (children != null && children.isNotEmpty) {
              final item = _parseChild(children[0] as Map<String, dynamic>);
              if (item != null) return ResolvedContentItem(item);
            }
          }
        }
      } on Object catch (e) {
        _ctx.log('Failed to resolve Reddit post URL', error: e.toString());
      }
      // Fallback: return a minimal item using the ID.
      return ResolvedContentItem(
        ContentItem(
          sourcePluginId: id,
          externalId: postId,
          contentType: ContentType.article,
          title: 'Reddit post $postId',
          url: url,
        ),
      );
    }

    return const ResolvedNotHandled();
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
    final encoded = Uri.encodeComponent(query);
    final url = 'https://www.reddit.com/search.json'
        '?q=$encoded&limit=$perPage&raw_json=1';
    return _fetchListing(url, 'search');
  }

  // ---------------------------------------------------------------------------
  // Channel (subreddit) feed
  // ---------------------------------------------------------------------------

  @override
  Future<List<ContentItem>> fetchChannel(
    String entityId, {
    int page = 0,
    int perPage = 20,
  }) async {
    // entityId is the subreddit name (e.g. "flutter").
    final sub = entityId.replaceFirst(RegExp(r'^r/'), '');
    final url = 'https://www.reddit.com/r/$sub/hot.json'
        '?limit=$perPage&raw_json=1';
    return _fetchListing(url, 'channel:$sub');
  }

  // ---------------------------------------------------------------------------
  // Trending
  // ---------------------------------------------------------------------------

  @override
  Future<List<ContentItem>> fetchTrending({
    int page = 0,
    int perPage = 20,
  }) async {
    final url = 'https://www.reddit.com/r/popular/hot.json'
        '?limit=$perPage&raw_json=1';
    return _fetchListing(url, 'trending');
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Fetches a standard Reddit listing endpoint and converts posts to
  /// [ContentItem] objects. Returns an empty list on error.
  Future<List<ContentItem>> _fetchListing(String url, String label) async {
    try {
      final response = await fetchRedditJson(
        get: (uri) async {
          final res = await _ctx.httpClient.get(uri, headers: _headers);
          return (statusCode: res.statusCode, body: res.body);
        },
        pathOrUrl: url,
      );
      if (response.statusCode != 200) {
        _ctx.log(
          'Reddit $label: HTTP ${response.statusCode}',
          error: 'status ${response.statusCode}',
        );
        return [];
      }

      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return [];

      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return [];

      final children = data['children'] as List<dynamic>? ?? [];
      return children
          .whereType<Map<String, dynamic>>()
          .map(_parseChild)
          .whereType<ContentItem>()
          .toList();
    } on Object catch (e) {
      _ctx.log('Reddit $label fetch failed', error: e.toString());
      return [];
    }
  }

  /// Parses a single Reddit listing child into a [ContentItem].
  ContentItem? _parseChild(Map<String, dynamic> child) {
    final post = child['data'] as Map<String, dynamic>?;
    if (post == null) return null;

    final title = post['title'] as String? ?? 'Untitled';
    final permalink = post['permalink'] as String? ?? '';
    final postUrl = permalink.isNotEmpty
        ? 'https://www.reddit.com$permalink'
        : null;
    final selfText = post['selftext'] as String?;
    final authorName = post['author'] as String?;
    final createdUtc = post['created_utc'] as num?;
    final subreddit = post['subreddit'] as String?;
    final postId = post['id'] as String? ?? permalink;
    final score = post['score'] as int?;
    final numComments = post['num_comments'] as int?;

    // ---- Thumbnail / preview image ----
    String? thumbnailUrl = _cleanThumbnail(post['thumbnail'] as String?);
    thumbnailUrl = _extractPreviewImage(post) ?? thumbnailUrl;

    // ---- Description ----
    final descParts = <String>[];
    if (selfText != null && selfText.isNotEmpty) descParts.add(selfText);
    if (score != null) descParts.add('⬆ $score');
    if (numComments != null) descParts.add('💬 $numComments');
    final description = descParts.isEmpty ? null : descParts.join(' · ');

    // ---- Tags ----
    final tags = <String>[];
    if (subreddit != null) tags.add('r/$subreddit');
    final linkFlair = post['link_flair_text'] as String?;
    if (linkFlair != null) tags.add(linkFlair);

    // ---- Extra metadata ----
    final extra = <String, String>{};
    if (score != null) extra['score'] = score.toString();
    if (numComments != null) extra['comments'] = numComments.toString();
    if (subreddit != null) extra['subreddit'] = subreddit;

    // ---- Content type detection ----
    final contentType = _detectContentType(post);
    final metadata = _buildMetadata(post, contentType);

    // If we found gallery images, prefer the first as thumbnail.
    if (contentType == ContentType.image && metadata is ImageMeta) {
      if (metadata.galleryUrls.isNotEmpty) {
        thumbnailUrl = metadata.galleryUrls.first;
      }
    }

    return ContentItem(
      sourcePluginId: id,
      externalId: postId,
      contentType: contentType,
      title: title,
      description: description,
      url: postUrl,
      thumbnailUrl: thumbnailUrl,
      author: authorName != null
          ? ContentAuthor(
              name: authorName,
              url: 'https://www.reddit.com/user/$authorName',
            )
          : null,
      publishedAt: createdUtc != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (createdUtc * 1000).toInt(),
              isUtc: true,
            )
          : null,
      metadata: metadata,
      tags: tags,
      extra: extra,
    );
  }

  // ---------------------------------------------------------------------------
  // Content type detection
  // ---------------------------------------------------------------------------

  /// Determines the [ContentType] from Reddit post JSON fields.
  static ContentType _detectContentType(Map<String, dynamic> post) {
    final isVideo = post['is_video'] as bool? ?? false;
    final postHint = post['post_hint'] as String? ?? '';
    final isGallery = post['is_gallery'] as bool? ?? false;
    final postUrl = (post['url'] as String? ?? '').toLowerCase();

    // Video posts.
    if (isVideo || postHint == 'hosted:video' || postHint == 'rich:video') {
      return ContentType.video;
    }
    // Check crosspost parent for video.
    final crossposts = post['crosspost_parent_list'] as List<dynamic>?;
    if (crossposts != null && crossposts.isNotEmpty) {
      final parent = crossposts[0] as Map<String, dynamic>;
      if (parent['is_video'] as bool? ?? false) return ContentType.video;
    }
    // External video URLs.
    if (postUrl.contains('v.redd.it') ||
        postUrl.contains('youtube.com') ||
        postUrl.contains('youtu.be') ||
        postUrl.endsWith('.mp4') ||
        postUrl.endsWith('.webm') ||
        postUrl.endsWith('.gifv')) {
      return ContentType.video;
    }

    // Image posts.
    if (postHint == 'image' || isGallery) return ContentType.image;
    if (postUrl.endsWith('.jpg') ||
        postUrl.endsWith('.jpeg') ||
        postUrl.endsWith('.png') ||
        postUrl.endsWith('.gif')) {
      return ContentType.image;
    }

    // Default: article.
    return ContentType.article;
  }

  /// Builds the appropriate [ContentMeta] subclass for [contentType].
  static ContentMeta _buildMetadata(
    Map<String, dynamic> post,
    ContentType contentType,
  ) {
    switch (contentType) {
      case ContentType.video:
        return _buildVideoMeta(post);
      case ContentType.image:
        return _buildImageMeta(post);
      case ContentType.article:
        return ArticleMeta(body: post['selftext'] as String?);
      // Remaining types are not produced by this plugin.
      case ContentType.audio:
      case ContentType.document:
      case ContentType.profile:
      case ContentType.channel:
      case ContentType.mixed:
        return ArticleMeta(body: post['selftext'] as String?);
    }
  }

  /// Extracts video stream URL from post data, including cross-posts.
  static VideoMeta _buildVideoMeta(Map<String, dynamic> post) {
    String? streamUrl;
    String? hlsUrl;

    // Primary media.
    final media = post['media'] as Map<String, dynamic>? ??
        post['secure_media'] as Map<String, dynamic>?;
    final redditVideo = media?['reddit_video'] as Map<String, dynamic>?;
    hlsUrl = (redditVideo?['hls_url'] as String?)?.replaceAll('&amp;', '&');
    streamUrl =
        (redditVideo?['fallback_url'] as String?)?.replaceAll('&amp;', '&');

    // Cross-post parent.
    if (hlsUrl == null && streamUrl == null) {
      final crossposts = post['crosspost_parent_list'] as List<dynamic>?;
      if (crossposts != null && crossposts.isNotEmpty) {
        final parent = crossposts[0] as Map<String, dynamic>;
        final pMedia = parent['media'] as Map<String, dynamic>? ??
            parent['secure_media'] as Map<String, dynamic>?;
        final rv = pMedia?['reddit_video'] as Map<String, dynamic>?;
        hlsUrl = (rv?['hls_url'] as String?)?.replaceAll('&amp;', '&');
        streamUrl =
            (rv?['fallback_url'] as String?)?.replaceAll('&amp;', '&');
      }
    }

    // External video URL fallback.
    if (hlsUrl == null && streamUrl == null) {
      var raw = post['url'] as String? ?? '';
      final lower = raw.toLowerCase();
      if (lower.endsWith('.gifv')) {
        raw = '${raw.substring(0, raw.length - 5)}.mp4';
      }
      if (lower.contains('v.redd.it') &&
          !raw.contains('HLSPlaylist') &&
          !raw.contains('DASHPlaylist') &&
          !raw.contains('DASH_') &&
          !lower.endsWith('.mp4') &&
          !lower.endsWith('.m3u8')) {
        if (raw.endsWith('/')) raw = raw.substring(0, raw.length - 1);
        raw = '$raw/HLSPlaylist.m3u8';
      }
      if (lower.endsWith('.m3u8') || raw.contains('HLSPlaylist')) {
        hlsUrl = raw;
      } else {
        streamUrl = raw;
      }
    }

    return VideoMeta(
      streamUrl: streamUrl,
      hlsUrl: hlsUrl,
    );
  }

  /// Extracts gallery image URLs from Reddit gallery posts.
  static ImageMeta _buildImageMeta(Map<String, dynamic> post) {
    final galleryUrls = <String>[];
    final isGallery = post['is_gallery'] as bool? ?? false;

    if (isGallery) {
      final mediaMetadata =
          post['media_metadata'] as Map<String, dynamic>? ?? {};
      final galleryData = post['gallery_data'] as Map<String, dynamic>?;
      final items = galleryData?['items'] as List<dynamic>?;
      if (items != null) {
        for (final item in items) {
          final mediaId = (item as Map<String, dynamic>)['media_id'] as String?;
          if (mediaId == null) continue;
          final meta = mediaMetadata[mediaId] as Map<String, dynamic>?;
          if (meta == null) continue;
          final source = meta['s'] as Map<String, dynamic>?;
          final rawUrl = source?['u'] as String? ?? source?['gif'] as String?;
          if (rawUrl != null) {
            final cleaned = rawUrl.replaceAll('&amp;', '&');
            final uri = Uri.tryParse(cleaned);
            if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
              galleryUrls.add(cleaned);
            }
          }
        }
      }
    }

    return ImageMeta(galleryUrls: galleryUrls);
  }

  // ---------------------------------------------------------------------------
  // Thumbnail helpers
  // ---------------------------------------------------------------------------

  /// Returns the thumbnail URL if it is a valid image URL, or `null`.
  static String? _cleanThumbnail(String? thumbnail) {
    if (thumbnail == null) return null;
    if (!thumbnail.startsWith('http')) return null;
    const sentinels = {'self', 'default', 'nsfw', 'spoiler'};
    if (sentinels.contains(thumbnail)) return null;
    return thumbnail;
  }

  /// Attempts to extract a high-quality preview image from the post's
  /// `preview.images` field.
  static String? _extractPreviewImage(Map<String, dynamic> post) {
    final preview = post['preview'] as Map<String, dynamic>?;
    if (preview == null) return null;
    final images = preview['images'] as List<dynamic>?;
    if (images == null || images.isEmpty) return null;
    final source =
        (images[0] as Map<String, dynamic>)['source'] as Map<String, dynamic>?;
    if (source == null) return null;
    return (source['url'] as String?)?.replaceAll('&amp;', '&');
  }
}
