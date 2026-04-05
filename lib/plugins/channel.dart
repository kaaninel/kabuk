/// Unified channel model.
///
/// A channel represents an entity and its associated content — a subreddit,
/// a YouTube channel, a website, a user profile, etc. Channels provide a
/// consistent way to display any entity + content feed regardless of source.
library;

import 'package:meta/meta.dart';

/// The type of entity backing a channel.
enum ChannelEntityType {
  /// A website or web page.
  website,

  /// An individual person or user profile.
  person,

  /// A company, group, or organisation.
  organization,

  /// A Reddit subreddit.
  subreddit,

  /// A 4chan board.
  board,

  /// A YouTube channel or similar video feed.
  videoChannel,

  /// A podcast feed.
  podcast,

  /// A music artist or band.
  musicArtist,

  /// A generic topic or hashtag.
  topic,

  /// Anything that doesn't fit the above categories.
  custom,
}

/// A unified channel combining an entity identity with its content source.
///
/// Channels decouple _what_ is being displayed (entity identity, avatar,
/// description) from _where_ the content comes from (a plugin, the
/// knowledge store, or both). This allows a single page widget to render
/// any feed — Reddit, YouTube, RSS, or local — with the same layout.
@immutable
class Channel {
  /// Creates a [Channel].
  const Channel({
    required this.entityUri,
    required this.entityType,
    required this.title,
    this.description,
    this.imageUrl,
    this.bannerUrl,
    this.sourcePluginId,
    this.externalEntityId,
    this.metadata = const {},
  });

  /// Knowledge store URI for the entity.
  final String entityUri;

  /// What kind of entity this channel represents.
  final ChannelEntityType entityType;

  /// Display title.
  final String title;

  /// Short description or bio.
  final String? description;

  /// Avatar or icon image URL.
  final String? imageUrl;

  /// Banner/header image URL.
  final String? bannerUrl;

  /// Which plugin provides this channel's content (null = knowledge store
  /// query).
  final String? sourcePluginId;

  /// Plugin-specific entity ID for fetching content.
  final String? externalEntityId;

  /// Additional metadata key-values (subscriber count, post count, etc.).
  final Map<String, String> metadata;

  @override
  String toString() => 'Channel($title, type: $entityType)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Channel &&
          entityUri == other.entityUri &&
          entityType == other.entityType;

  @override
  int get hashCode => Object.hash(entityUri, entityType);
}
