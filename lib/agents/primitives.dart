/// Primitive catalog — the drawing primitives agents can emit data for.
///
/// Kabuk's UI is drawn from a fixed set of content primitives (cards and
/// viewers). Agents never author UI from scratch; instead they produce
/// typed data conforming to a primitive's schema, and the system draws
/// using [contentCardFor]/[ViewerRouter]. This file is the registry that
/// tells agents which primitives exist and what data each one expects.
library;

import 'package:kabuk/plugins/content_item.dart';

/// A registered drawing primitive.
///
/// Each primitive maps 1:1 to an existing Kabuk card/viewer (see
/// `lib/ui/viewers/content_cards.dart` and `lib/ui/viewers/viewer_router.dart`).
class PrimitiveSpec {
  /// Creates a [PrimitiveSpec].
  const PrimitiveSpec({
    required this.id,
    required this.label,
    required this.description,
    required this.contentType,
    required this.schema,
  });

  /// Machine-readable primitive id (e.g. `'video_card'`).
  final String id;

  /// Human-readable name shown in agent prompts.
  final String label;

  /// What this primitive renders, for the LLM's benefit.
  final String description;

  /// The [ContentType] this primitive renders.
  final ContentType contentType;

  /// JSON Schema describing the data fields this primitive accepts.
  final Map<String, dynamic> schema;
}

/// The full catalog of drawing primitives available to agents.
const List<PrimitiveSpec> kabukPrimitiveCatalog = [
  PrimitiveSpec(
    id: 'video_card',
    label: 'Video card',
    description:
        'A video entry with a thumbnail, play button, duration badge, '
        'title and author. Tapping plays the video.',
    contentType: ContentType.video,
    schema: {
      'type': 'object',
      'required': ['contentType', 'externalId', 'title'],
      'properties': {
        'contentType': {'const': 'video'},
        'title': {'type': 'string'},
        'externalId': {'type': 'string'},
        'description': {'type': 'string'},
        'url': {'type': 'string'},
        'thumbnailUrl': {'type': 'string'},
        'durationSeconds': {'type': 'integer'},
        'resolution': {'type': 'string'},
        'streamUrl': {'type': 'string'},
        'hlsUrl': {'type': 'string'},
        'author': {'type': 'string'},
        'publishedAt': {'type': 'string'},
      },
    },
  ),
  PrimitiveSpec(
    id: 'image_card',
    label: 'Image card',
    description:
        'A single image or gallery with a full-bleed preview and title '
        'overlay. Tapping opens the full-screen image viewer.',
    contentType: ContentType.image,
    schema: {
      'type': 'object',
      'required': ['contentType', 'externalId', 'title'],
      'properties': {
        'contentType': {'const': 'image'},
        'title': {'type': 'string'},
        'externalId': {'type': 'string'},
        'thumbnailUrl': {'type': 'string'},
        'galleryUrls': {'type': 'array', 'items': {'type': 'string'}},
        'width': {'type': 'integer'},
        'height': {'type': 'integer'},
        'author': {'type': 'string'},
      },
    },
  ),
  PrimitiveSpec(
    id: 'audio_card',
    label: 'Audio card',
    description:
        'A track or episode with artwork, title, artist and duration. '
        'Tapping opens the audio player.',
    contentType: ContentType.audio,
    schema: {
      'type': 'object',
      'required': ['contentType', 'externalId', 'title'],
      'properties': {
        'contentType': {'const': 'audio'},
        'title': {'type': 'string'},
        'externalId': {'type': 'string'},
        'artist': {'type': 'string'},
        'album': {'type': 'string'},
        'durationSeconds': {'type': 'integer'},
        'streamUrl': {'type': 'string'},
        'artworkUrl': {'type': 'string'},
        'url': {'type': 'string'},
        'author': {'type': 'string'},
      },
    },
  ),
  PrimitiveSpec(
    id: 'article_card',
    label: 'Article card',
    description:
        'A text article with headline, excerpt, source and date. '
        'Tapping opens the article reader.',
    contentType: ContentType.article,
    schema: {
      'type': 'object',
      'required': ['contentType', 'externalId', 'title'],
      'properties': {
        'contentType': {'const': 'article'},
        'title': {'type': 'string'},
        'externalId': {'type': 'string'},
        'description': {'type': 'string'},
        'url': {'type': 'string'},
        'thumbnailUrl': {'type': 'string'},
        'body': {'type': 'string'},
        'readTimeMinutes': {'type': 'integer'},
        'author': {'type': 'string'},
        'publishedAt': {'type': 'string'},
        'source': {'type': 'string'},
      },
    },
  ),
  PrimitiveSpec(
    id: 'document_card',
    label: 'Document card',
    description: 'A downloadable document such as a PDF or EPUB.',
    contentType: ContentType.document,
    schema: {
      'type': 'object',
      'required': ['contentType', 'externalId', 'title'],
      'properties': {
        'contentType': {'const': 'document'},
        'title': {'type': 'string'},
        'externalId': {'type': 'string'},
        'description': {'type': 'string'},
        'url': {'type': 'string'},
        'thumbnailUrl': {'type': 'string'},
        'mimeType': {'type': 'string'},
        'fileUrl': {'type': 'string'},
        'fileSizeBytes': {'type': 'integer'},
      },
    },
  ),
  PrimitiveSpec(
    id: 'profile_card',
    label: 'Profile card',
    description:
        'A user profile with display name, bio and follower counts.',
    contentType: ContentType.profile,
    schema: {
      'type': 'object',
      'required': ['contentType', 'externalId', 'title'],
      'properties': {
        'contentType': {'const': 'profile'},
        'title': {'type': 'string'},
        'externalId': {'type': 'string'},
        'displayName': {'type': 'string'},
        'bio': {'type': 'string'},
        'thumbnailUrl': {'type': 'string'},
        'followersCount': {'type': 'integer'},
      },
    },
  ),
  PrimitiveSpec(
    id: 'channel_card',
    label: 'Channel card',
    description:
        'A channel or feed identity with subscriber/post counts.',
    contentType: ContentType.channel,
    schema: {
      'type': 'object',
      'required': ['contentType', 'externalId', 'title'],
      'properties': {
        'contentType': {'const': 'channel'},
        'title': {'type': 'string'},
        'externalId': {'type': 'string'},
        'description': {'type': 'string'},
        'thumbnailUrl': {'type': 'string'},
        'subscriberCount': {'type': 'integer'},
        'postCount': {'type': 'integer'},
      },
    },
  ),
  PrimitiveSpec(
    id: 'generic_card',
    label: 'Generic card',
    description:
        'A fallback card used when no other primitive fits. Shows a type '
        'icon, title and description.',
    contentType: ContentType.mixed,
    schema: {
      'type': 'object',
      'required': ['contentType', 'externalId', 'title'],
      'properties': {
        'contentType': {'type': 'string'},
        'title': {'type': 'string'},
        'externalId': {'type': 'string'},
        'description': {'type': 'string'},
        'url': {'type': 'string'},
        'thumbnailUrl': {'type': 'string'},
        'author': {'type': 'string'},
      },
    },
  ),
];

/// Finds the [PrimitiveSpec] for a given [ContentType].
PrimitiveSpec primitiveForType(ContentType type) {
  return kabukPrimitiveCatalog.firstWhere(
    (p) => p.contentType == type,
    orElse: () => kabukPrimitiveCatalog.last,
  );
}

/// Renders the primitive catalog as a prompt fragment so the LLM knows
/// which primitives it can emit data for.
String buildPrimitivePrompt() {
  final buf = StringBuffer()
    ..writeln(
      'You draw content by emitting data for registered UI primitives — '
      'you never author UI yourself. To show content, return one item '
      'map per piece of content. Fields:',
    );
  for (final spec in kabukPrimitiveCatalog) {
    buf
      ..writeln('- ${spec.id} (${spec.label}): ${spec.description}')
      ..writeln('  Schema: ${spec.schema}');
  }
  buf
    ..writeln()
    ..writeln(
      'Every item requires contentType, externalId and title. '
      'publishedAt is an ISO-8601 string. author is the creator name. '
      'Set url to the canonical source URL.',
    );
  return buf.toString();
}

/// Builds a [ContentItem] from a data map produced against a primitive
/// schema. Returns `null` when required fields are missing.
///
/// [fallbackPluginId] is used as the [ContentItem.sourcePluginId] when the
/// map doesn't specify one. [externalId] defaults to the URL when absent.
ContentItem? contentItemFromMap(
  Map<String, dynamic> map, {
  String? fallbackPluginId,
}) {
  final title = (map['title'] as String?)?.trim();
  if (title == null || title.isEmpty) return null;

  final typeName = (map['contentType'] as String?)?.trim();
  final contentType = ContentType.values
      .where((t) => t.name == typeName)
      .firstOrNull ?? ContentType.mixed;

  final externalId = (map['externalId'] as String?)?.trim() ??
      (map['url'] as String?) ??
      'item:${title.hashCode}';

  final authorName = map['author'] as String?;
  final author = authorName != null && authorName.isNotEmpty
      ? ContentAuthor(
          name: authorName,
          url: map['authorUrl'] as String?,
          avatarUrl: map['authorAvatarUrl'] as String?,
        )
      : null;

  final publishedAt = map['publishedAt'] as String?;
  final tags = (map['tags'] as List?)?.map((t) => t.toString()).toList();

  final extra = <String, String>{
    if (map['source'] case final String s) 'source': s,
  };

  final metadata = _metadataFor(contentType, map);

  return ContentItem(
    sourcePluginId: (map['sourcePluginId'] as String?) ?? fallbackPluginId ?? 'agent',
    externalId: externalId,
    contentType: contentType,
    title: title,
    description: map['description'] as String?,
    url: map['url'] as String?,
    thumbnailUrl: map['thumbnailUrl'] as String?,
    author: author,
    publishedAt: publishedAt != null
        ? DateTime.tryParse(publishedAt)
        : null,
    metadata: metadata,
    tags: tags ?? const [],
    extra: extra,
  );
}

/// Builds type-specific [ContentMeta] from a primitive data map.
ContentMeta? _metadataFor(ContentType type, Map<String, dynamic> map) {
  final duration = (map['durationSeconds'] as num?)?.toInt();
  return switch (type) {
    ContentType.video => VideoMeta(
        duration: duration != null ? Duration(seconds: duration) : null,
        resolution: map['resolution'] as String?,
        streamUrl: map['streamUrl'] as String?,
        hlsUrl: map['hlsUrl'] as String?,
      ),
    ContentType.image => ImageMeta(
        width: (map['width'] as num?)?.toInt(),
        height: (map['height'] as num?)?.toInt(),
        galleryUrls:
            (map['galleryUrls'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
      ),
    ContentType.audio => AudioMeta(
        duration: duration != null ? Duration(seconds: duration) : null,
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        streamUrl: map['streamUrl'] as String?,
        artworkUrl: map['artworkUrl'] as String?,
      ),
    ContentType.article => ArticleMeta(
        body: map['body'] as String?,
        readTimeMinutes: (map['readTimeMinutes'] as num?)?.toInt(),
      ),
    ContentType.document => DocumentMeta(
        mimeType: map['mimeType'] as String?,
        fileUrl: map['fileUrl'] as String?,
        fileSize: (map['fileSizeBytes'] as num?)?.toInt(),
      ),
    ContentType.profile => ProfileMeta(
        displayName: map['displayName'] as String?,
        bio: map['bio'] as String?,
        followersCount: (map['followersCount'] as num?)?.toInt(),
      ),
    ContentType.channel => ChannelMeta(
        subscriberCount: (map['subscriberCount'] as num?)?.toInt(),
        postCount: (map['postCount'] as num?)?.toInt(),
        category: map['category'] as String?,
      ),
    ContentType.mixed => null,
  };
}

/// Builds a [ContentItem] from a real search result, e.g. a Nostr event
/// or Usenet release, without going through a data map.
ContentItem contentItemFromParts({
  required String sourcePluginId,
  required String externalId,
  required ContentType contentType,
  required String title,
  String? description,
  String? url,
  String? thumbnailUrl,
  String? author,
  DateTime? publishedAt,
  ContentMeta? metadata,
  Map<String, String> extra = const {},
}) {
  return ContentItem(
    sourcePluginId: sourcePluginId,
    externalId: externalId,
    contentType: contentType,
    title: title,
    description: description,
    url: url,
    thumbnailUrl: thumbnailUrl,
    author: author != null ? ContentAuthor(name: author) : null,
    publishedAt: publishedAt,
    metadata: metadata,
    extra: extra,
  );
}