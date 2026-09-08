/// Reddit feed source implementation.
///
/// Fetches posts from public subreddits using Reddit's JSON API.
/// No authentication is required for public subreddit listings.
/// Uses [MeshService] for HTTP requests and the shared Reddit API helpers
/// (descriptive User-Agent + host fallback) from `reddit_api.dart`.
library;

import 'dart:convert';

import 'package:kabuk/platform/shared/reddit_api.dart';
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
  /// on subsequent calls for incremental pagination. Tries `api.reddit.com`,
  /// `old.reddit.com`, and `www.reddit.com` in order so a 403 on one host
  /// doesn't kill the feed.
  Future<({List<FeedItem> items, String? nextCursor})> fetchPage(
    String url, {
    String? afterCursor,
  }) async {
    final response = await fetchRedditJson(
      get: (uri) async {
        final res = await _mesh.get(uri, headers: kRedditHeaders);
        return (statusCode: res.statusCode, body: res.body);
      },
      pathOrUrl: url,
      after: afterCursor,
    );

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

    // Build description from selftext. Store the full text so article
    // detail view doesn't need to re-fetch from the Reddit HTML page.
    final descParts = <String>[];
    if (selfText != null && selfText.isNotEmpty) {
      descParts.add(selfText);
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
            final cleaned = rawUrl.replaceAll('&amp;', '&');
            final uri = Uri.tryParse(cleaned);
            if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
              galleryImages.add(cleaned);
            }
          }
        }
      }
    }

    // If we have gallery images, use the first gallery image as the main image
    // (full quality from media_metadata source) instead of the lower-quality
    // preview thumbnail. Remove it from the gallery list to avoid duplication.
    if (galleryImages.isNotEmpty) {
      imageUrl = galleryImages.removeAt(0);
    }

    // Extract video URL for video posts.
    // Reddit hosted videos have `is_video: true` with both:
    //   - `media.reddit_video.hls_url`      → HLS (M3U8, preferred on iOS)
    //   - `media.reddit_video.fallback_url`  → DASH MP4 (lacks byte-range headers)
    // iOS AVPlayer requires proper Content-Length / byte-range support, so we
    // prefer the HLS stream which is natively supported.
    // Some posts use `secure_media` instead of `media`, so check both.
    String? videoUrl;
    final isVideo = post['is_video'] as bool? ?? false;
    if (isVideo) {
      final media = post['media'] as Map<String, dynamic>? ??
          post['secure_media'] as Map<String, dynamic>?;
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
    // Check crosspost parent for video data.
    if (videoUrl == null) {
      final crossposts = post['crosspost_parent_list'] as List<dynamic>?;
      if (crossposts != null && crossposts.isNotEmpty) {
        final parent = crossposts[0] as Map<String, dynamic>;
        final parentIsVideo = parent['is_video'] as bool? ?? false;
        if (parentIsVideo) {
          final pMedia = parent['media'] as Map<String, dynamic>? ??
              parent['secure_media'] as Map<String, dynamic>?;
          final rv = pMedia?['reddit_video'] as Map<String, dynamic>?;
          final hlsUrl = rv?['hls_url'] as String?;
          if (hlsUrl != null) {
            videoUrl = hlsUrl.replaceAll('&amp;', '&');
          } else {
            final fallback = rv?['fallback_url'] as String?;
            if (fallback != null) {
              videoUrl = fallback.replaceAll('&amp;', '&');
            }
          }
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
        // Bare v.redd.it URLs are landing pages, not direct video files.
        // Append HLS playlist path to make them playable.
        if (raw.toLowerCase().contains('v.redd.it') &&
            !raw.contains('HLSPlaylist') &&
            !raw.contains('DASHPlaylist') &&
            !raw.contains('DASH_') &&
            !raw.toLowerCase().endsWith('.mp4') &&
            !raw.toLowerCase().endsWith('.m3u8')) {
          // Strip trailing slash if present.
          if (raw.endsWith('/')) raw = raw.substring(0, raw.length - 1);
          raw = '$raw/HLSPlaylist.m3u8';
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
      final response = await fetchRedditJson(
        get: (uri) async {
          final res = await _mesh.get(uri, headers: kRedditHeaders);
          return (statusCode: res.statusCode, body: res.body);
        },
        pathOrUrl: url,
      );
      final json = jsonDecode(response.body);
      return json is Map<String, dynamic> && json.containsKey('data');
    } on Object {
      return false;
    }
  }
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
