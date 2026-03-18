/// Reddit feed source implementation.
///
/// Fetches posts from public subreddits using Reddit's JSON API.
/// No authentication is required for public subreddit listings.
/// Uses [MeshService] for HTTP requests.
library;

import 'dart:convert';

import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/mesh.dart';

/// [FeedSource] implementation for Reddit subreddit feeds.
///
/// Supports URLs in the forms:
/// - `https://www.reddit.com/r/flutter/.json`
/// - `https://reddit.com/r/flutter`
/// - `r/flutter`
/// - `/r/flutter`
/// - Just the subreddit name: `flutter`
class RedditFeedSource implements FeedSource {
  /// Creates a [RedditFeedSource] with the given [mesh] service for HTTP.
  RedditFeedSource({required MeshService mesh}) : _mesh = mesh;

  final MeshService _mesh;

  /// Browser-like User-Agent to avoid Reddit blocking API requests.
  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  @override
  FeedSourceType get type => FeedSourceType.reddit;

  @override
  Future<List<FeedItem>> fetch(String url) async {
    final result = await fetchPage(url);
    return result.items;
  }

  /// Fetches a page of posts, optionally starting after [afterCursor].
  ///
  /// Returns the parsed feed items and an optional nextCursor to pass
  /// on subsequent calls for incremental pagination.
  Future<({List<FeedItem> items, String? nextCursor})> fetchPage(
    String url, {
    String? afterCursor,
  }) async {
    var jsonUrl = _toJsonUrl(url);
    if (afterCursor != null && afterCursor.isNotEmpty) {
      final separator = jsonUrl.contains('?') ? '&' : '?';
      jsonUrl = '$jsonUrl${separator}after=$afterCursor';
    }

    final response = await _mesh.get(
      Uri.parse(jsonUrl),
      headers: {
        'Accept': 'application/json',
        'User-Agent': _userAgent,
        'Cookie': 'over18=1',
      },
    );

    if (response.statusCode != 200) {
      throw RedditFetchException(
        'HTTP ${response.statusCode} fetching $jsonUrl',
      );
    }

    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw const RedditParseException('Unexpected response format');
    }

    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw const RedditParseException('No "data" field in response');
    }

    final children = data['children'] as List<dynamic>? ?? [];
    final nextCursor = data['after'] as String?;

    final items = children
        .whereType<Map<String, dynamic>>()
        .map(_parsePost)
        .where((item) => item != null)
        .cast<FeedItem>()
        .toList();

    return (items: items, nextCursor: nextCursor);
  }

  FeedItem? _parsePost(Map<String, dynamic> child) {
    final post = child['data'] as Map<String, dynamic>?;
    if (post == null) return null;

    final title = post['title'] as String? ?? 'Untitled';
    final permalink = post['permalink'] as String? ?? '';
    final url = 'https://www.reddit.com/$permalink';
    final selfText = post['selftext'] as String?;
    final author = post['author'] as String?;
    final createdUtc = post['created_utc'] as num?;
    final thumbnail = post['thumbnail'] as String?;
    final subreddit = post['subreddit'] as String?;
    final linkFlair = post['link_flair_text'] as String?;
    final id = post['id'] as String?;
    final score = post['score'] as int?;
    final numComments = post['num_comments'] as int?;

    // Build description from selftext or meta info.
    final descParts = <String>[];
    if (selfText != null && selfText.isNotEmpty) {
      descParts.add(
        selfText.length > 500 ? '${selfText.substring(0, 500)}...' : selfText,
      );
    }
    if (score != null) descParts.add('⬆ $score');
    if (numComments != null) descParts.add('💬 $numComments');
    final description = descParts.isEmpty ? null : descParts.join(' · ');

    // Thumbnail: skip non-image sentinel values.
    String? imageUrl;
    if (thumbnail != null &&
        thumbnail.startsWith('http') &&
        thumbnail != 'self' &&
        thumbnail != 'default' &&
        thumbnail != 'nsfw' &&
        thumbnail != 'spoiler') {
      imageUrl = thumbnail;
    }

    // Try to get higher quality preview image.
    final preview = post['preview'] as Map<String, dynamic>?;
    if (preview != null) {
      final images = preview['images'] as List<dynamic>?;
      if (images != null && images.isNotEmpty) {
        final source =
            (images[0] as Map<String, dynamic>)['source']
                as Map<String, dynamic>?;
        if (source != null) {
          final previewUrl = (source['url'] as String?)?.replaceAll(
            '&amp;',
            '&',
          );
          if (previewUrl != null) imageUrl = previewUrl;
        }
      }
    }

    // Extract gallery images from Reddit gallery posts.
    // Gallery posts have `is_gallery: true` and a `gallery_data` field
    // with an ordered list of media IDs, plus `media_metadata` with image URLs.
    final galleryImages = <String>[];
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
          // `s` holds the source image; prefer it over `p` (previews).
          final source = meta['s'] as Map<String, dynamic>?;
          final rawUrl = source?['u'] as String? ?? source?['gif'] as String?;
          if (rawUrl != null) {
            galleryImages.add(rawUrl.replaceAll('&amp;', '&'));
          }
        }
      }
    }

    // If we have gallery images, use the first as the main image.
    if (galleryImages.isNotEmpty && imageUrl == null) {
      imageUrl = galleryImages.first;
    }

    // Extract video URL for video posts.
    // Reddit hosted videos have `is_video: true` with both:
    //   - `media.reddit_video.hls_url`      → HLS (M3U8, preferred on iOS)
    //   - `media.reddit_video.fallback_url`  → DASH MP4 (lacks byte-range headers)
    // iOS AVPlayer requires proper Content-Length / byte-range support, so we
    // prefer the HLS stream which is natively supported.
    String? videoUrl;
    final isVideo = post['is_video'] as bool? ?? false;
    if (isVideo) {
      final media = post['media'] as Map<String, dynamic>?;
      final redditVideo = media?['reddit_video'] as Map<String, dynamic>?;
      // Prefer HLS for iOS compatibility.
      final hlsUrl = redditVideo?['hls_url'] as String?;
      if (hlsUrl != null) {
        videoUrl = hlsUrl.replaceAll('&amp;', '&');
      } else {
        final fallback = redditVideo?['fallback_url'] as String?;
        if (fallback != null) {
          videoUrl = fallback.replaceAll('&amp;', '&');
        }
      }
    }
    // Also check `post['url']` for external video hosts.
    if (videoUrl == null) {
      final postUrl = (post['url'] as String? ?? '').toLowerCase();
      if (postUrl.contains('v.redd.it') ||
          postUrl.contains('youtube.com') ||
          postUrl.contains('youtu.be') ||
          postUrl.endsWith('.mp4') ||
          postUrl.endsWith('.webm') ||
          postUrl.endsWith('.gifv')) {
        var raw = post['url'] as String? ?? '';
        // Convert Imgur .gifv → .mp4 for playback.
        if (raw.toLowerCase().endsWith('.gifv')) {
          raw = '${raw.substring(0, raw.length - 5)}.mp4';
        }
        videoUrl = raw;
      }
    }

    final categories = <String>[];
    if (subreddit != null) categories.add('r/$subreddit');
    if (linkFlair != null) categories.add(linkFlair);

    return FeedItem(
      title: title,
      url: url,
      description: description,
      author: author,
      imageUrl: imageUrl,
      videoUrl: videoUrl,
      datePublished: createdUtc != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (createdUtc * 1000).toInt(),
              isUtc: true,
            )
          : null,
      identifier: id ?? url,
      categories: categories,
      galleryImages: galleryImages,
    );
  }

  @override
  Future<bool> validate(String url) async {
    try {
      final jsonUrl = _toJsonUrl(url);
      final response = await _mesh.get(
        Uri.parse(jsonUrl),
        headers: {
          'Accept': 'application/json',
          'User-Agent': _userAgent,
          'Cookie': 'over18=1',
        },
      );
      if (response.statusCode != 200) return false;
      final json = jsonDecode(response.body);
      return json is Map<String, dynamic> && json.containsKey('data');
    } on Object {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // URL normalization
  // ---------------------------------------------------------------------------

  /// Converts various Reddit URL forms to the JSON API URL.
  static String _toJsonUrl(String input) {
    var url = input.trim();

    // If it already is a fully-formed JSON endpoint (with or without query
    // params), return it as-is to avoid double-transforming sort URLs like
    // /r/flutter/new.json?limit=50&raw_json=1.
    if (url.contains('.json')) {
      if (!url.startsWith('http')) url = 'https://www.reddit.com/$url';
      return url;
    }

    // Strip full Reddit URLs down to the path.
    if (url.startsWith('http')) {
      final uri = Uri.parse(url);
      url = uri.path;
    }

    // Handle "r/subreddit" or "/r/subreddit".
    if (url.startsWith('r/') || url.startsWith('/r/')) {
      if (!url.startsWith('/')) url = '/$url';
    } else {
      // Bare subreddit name (e.g., "flutter").
      url = '/r/$url';
    }

    // Remove trailing slash.
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);

    return 'https://www.reddit.com$url/hot.json?limit=50&raw_json=1';
  }
}

/// Exception thrown when Reddit API returns an error.
class RedditFetchException implements Exception {
  /// Creates a [RedditFetchException] with a [message].
  const RedditFetchException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'RedditFetchException: $message';
}

/// Exception thrown when Reddit API response cannot be parsed.
class RedditParseException implements Exception {
  /// Creates a [RedditParseException] with a [message].
  const RedditParseException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'RedditParseException: $message';
}
