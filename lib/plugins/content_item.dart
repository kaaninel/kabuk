/// Unified content representation for the plugin system.
///
/// [ContentItem] is the universal content type that all plugins produce.
/// It maps directly to knowledge store triples using Schema.org vocabulary.
/// Each item carries a [ContentType], optional [ContentMeta] for
/// type-specific data, and enough information for the explore view to
/// render a card without additional queries.
library;

import 'package:meta/meta.dart';

/// The broad category of a piece of content.
enum ContentType {
  /// A video (YouTube, Vimeo, direct MP4, etc.).
  video,

  /// A single image or photo gallery.
  image,

  /// An audio track, podcast episode, or music stream.
  audio,

  /// A text article or blog post.
  article,

  /// A downloadable document (PDF, EPUB, etc.).
  document,

  /// A user profile on a social platform.
  profile,

  /// A channel, feed, or subscription endpoint.
  channel,

  /// Content that doesn't fit a single category.
  mixed,
}

/// The author or creator of a content item.
@immutable
class ContentAuthor {
  /// Creates a [ContentAuthor].
  const ContentAuthor({this.name, this.url, this.avatarUrl});

  /// Display name of the author.
  final String? name;

  /// URL of the author's profile page.
  final String? url;

  /// URL of the author's avatar image.
  final String? avatarUrl;

  @override
  String toString() => 'ContentAuthor(name: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContentAuthor &&
          name == other.name &&
          url == other.url &&
          avatarUrl == other.avatarUrl;

  @override
  int get hashCode => Object.hash(name, url, avatarUrl);
}

// ---------------------------------------------------------------------------
// Content metadata hierarchy
// ---------------------------------------------------------------------------

/// Type-specific metadata attached to a [ContentItem].
///
/// Use exhaustive pattern matching to handle all subtypes:
/// ```dart
/// switch (meta) {
///   case VideoMeta(:final duration) => ...,
///   case ImageMeta(:final width) => ...,
///   case AudioMeta(:final artist) => ...,
///   case ArticleMeta(:final body) => ...,
///   case DocumentMeta(:final mimeType) => ...,
///   case ProfileMeta(:final displayName) => ...,
///   case ChannelMeta(:final subscriberCount) => ...,
/// }
/// ```
sealed class ContentMeta {
  /// Base constructor for metadata subclasses.
  const ContentMeta();
}

/// Metadata for video content.
@immutable
class VideoMeta extends ContentMeta {
  /// Creates a [VideoMeta].
  const VideoMeta({
    this.duration,
    this.resolution,
    this.streamUrl,
    this.hlsUrl,
    this.qualities = const [],
  });

  /// Total duration of the video.
  final Duration? duration;

  /// Display resolution string (e.g. `"1920x1080"`).
  final String? resolution;

  /// Direct MP4/WebM stream URL.
  final String? streamUrl;

  /// HLS manifest URL for adaptive streaming.
  final String? hlsUrl;

  /// Available quality variants for the video.
  final List<VideoQuality> qualities;
}

/// A single quality variant for a video stream.
@immutable
class VideoQuality {
  /// Creates a [VideoQuality].
  const VideoQuality({
    required this.label,
    required this.url,
    this.width,
    this.height,
  });

  /// Human-readable quality label (e.g. `"1080p"`, `"720p"`).
  final String label;

  /// Direct URL for this quality variant.
  final String url;

  /// Frame width in pixels.
  final int? width;

  /// Frame height in pixels.
  final int? height;

  @override
  String toString() => 'VideoQuality($label)';
}

/// Metadata for image content.
@immutable
class ImageMeta extends ContentMeta {
  /// Creates an [ImageMeta].
  const ImageMeta({this.width, this.height, this.galleryUrls = const []});

  /// Image width in pixels.
  final int? width;

  /// Image height in pixels.
  final int? height;

  /// URLs for additional images in a gallery set.
  final List<String> galleryUrls;
}

/// Metadata for audio content.
@immutable
class AudioMeta extends ContentMeta {
  /// Creates an [AudioMeta].
  const AudioMeta({
    this.duration,
    this.artist,
    this.album,
    this.streamUrl,
    this.artworkUrl,
  });

  /// Total duration of the audio track.
  final Duration? duration;

  /// Artist or performer name.
  final String? artist;

  /// Album or collection name.
  final String? album;

  /// Direct audio stream URL.
  final String? streamUrl;

  /// URL of the album artwork or episode cover.
  final String? artworkUrl;
}

/// Metadata for article content.
@immutable
class ArticleMeta extends ContentMeta {
  /// Creates an [ArticleMeta].
  const ArticleMeta({
    this.body,
    this.bodyHtml,
    this.readTimeMinutes,
    this.wordCount,
  });

  /// Plain-text body of the article.
  final String? body;

  /// HTML body of the article for rich rendering.
  final String? bodyHtml;

  /// Estimated reading time in minutes.
  final int? readTimeMinutes;

  /// Total word count.
  final int? wordCount;
}

/// Metadata for downloadable documents.
@immutable
class DocumentMeta extends ContentMeta {
  /// Creates a [DocumentMeta].
  const DocumentMeta({
    this.mimeType,
    this.fileUrl,
    this.pageCount,
    this.fileSize,
  });

  /// MIME type of the document (e.g. `"application/pdf"`).
  final String? mimeType;

  /// Direct download URL for the file.
  final String? fileUrl;

  /// Number of pages in the document.
  final int? pageCount;

  /// File size in bytes.
  final int? fileSize;
}

/// Metadata for a user profile.
@immutable
class ProfileMeta extends ContentMeta {
  /// Creates a [ProfileMeta].
  const ProfileMeta({
    this.displayName,
    this.bio,
    this.followersCount,
    this.followingCount,
    this.postsCount,
  });

  /// The profile's display name.
  final String? displayName;

  /// Biography or about text.
  final String? bio;

  /// Number of followers.
  final int? followersCount;

  /// Number of accounts being followed.
  final int? followingCount;

  /// Total number of posts.
  final int? postsCount;
}

/// Metadata for a channel or feed.
@immutable
class ChannelMeta extends ContentMeta {
  /// Creates a [ChannelMeta].
  const ChannelMeta({
    this.subscriberCount,
    this.postCount,
    this.category,
  });

  /// Number of subscribers.
  final int? subscriberCount;

  /// Total number of posts in the channel.
  final int? postCount;

  /// Channel category or topic label.
  final String? category;
}

// ---------------------------------------------------------------------------
// ContentItem
// ---------------------------------------------------------------------------

/// A unified content item produced by a content plugin.
///
/// Every piece of external content — regardless of source — is normalised
/// into a [ContentItem] before entering the knowledge store. The
/// [sourcePluginId] and [externalId] pair uniquely identifies the item
/// across the system, enabling deduplication and provenance tracking.
///
/// Type-specific details live in [metadata], which is a subtype of
/// [ContentMeta] matching the [contentType].
@immutable
class ContentItem {
  /// Creates a [ContentItem].
  const ContentItem({
    required this.sourcePluginId,
    required this.externalId,
    required this.contentType,
    required this.title,
    this.description,
    this.url,
    this.thumbnailUrl,
    this.author,
    this.publishedAt,
    this.metadata,
    this.tags = const [],
    this.extra = const {},
  });

  /// Identifier of the plugin that produced this item.
  final String sourcePluginId;

  /// Platform-specific identifier for the content (e.g. YouTube video ID).
  final String externalId;

  /// Broad category of this content.
  final ContentType contentType;

  /// Human-readable title.
  final String title;

  /// Optional summary or description.
  final String? description;

  /// Canonical URL of the content on its source platform.
  final String? url;

  /// URL of a thumbnail image for preview cards.
  final String? thumbnailUrl;

  /// Author or creator of the content.
  final ContentAuthor? author;

  /// Original publication timestamp.
  final DateTime? publishedAt;

  /// Type-specific metadata (video duration, article body, etc.).
  final ContentMeta? metadata;

  /// Free-form tags for categorisation and search.
  final List<String> tags;

  /// Plugin-specific key-value pairs not covered by standard fields.
  final Map<String, String> extra;

  @override
  String toString() =>
      'ContentItem(plugin: $sourcePluginId, id: $externalId, title: $title)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContentItem &&
          sourcePluginId == other.sourcePluginId &&
          externalId == other.externalId;

  @override
  int get hashCode => Object.hash(sourcePluginId, externalId);
}
