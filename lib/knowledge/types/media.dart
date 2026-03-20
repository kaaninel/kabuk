/// Schema.org MediaObject type helpers for the Kabuk knowledge store.
///
/// Provides [MediaData] for structured access to media entities
/// (image, video, audio), plus [KnowledgeStoreMediaExtension]
/// convenience methods on [KnowledgeStore].
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

/// The kind of media object.
enum MediaType {
  /// An image (`schema:ImageObject`).
  image,

  /// A video (`schema:VideoObject`).
  video,

  /// An audio recording (`schema:AudioObject`).
  audio,

  /// A generic media object (`schema:MediaObject`).
  other,
}

/// Immutable representation of a Schema.org MediaObject entity.
///
/// Covers `ImageObject`, `VideoObject`, and `AudioObject` subtypes.
/// All fields are extracted from the underlying RDF triples.
/// Use [MediaData.fromTriples] to construct from raw store data,
/// or the [KnowledgeStoreMediaExtension] helpers for high-level access.
@immutable
class MediaData {
  /// Creates a [MediaData] with the given field values.
  const MediaData({
    required this.uri,
    required this.type,
    this.name,
    this.contentUrl,
    this.encodingFormat,
    this.contentSize,
    this.width,
    this.height,
    this.duration,
    this.thumbnail,
  });

  /// Constructs a [MediaData] from a subject [uri] and its [triples].
  ///
  /// The [type] is inferred from the `rdf:type` triple, defaulting
  /// to [MediaType.other] when no specific subtype is found.
  factory MediaData.fromTriples(String uri, List<Triple> triples) {
    return MediaData(
      uri: uri,
      type: _resolveMediaType(triples),
      name: triples
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue,
      contentUrl: triples
          .where((t) => t.predicate == NS.schemaContentUrl)
          .firstOrNull
          ?.objectValue,
      encodingFormat: triples
          .where((t) => t.predicate == NS.schemaEncodingFormat)
          .firstOrNull
          ?.objectValue,
      contentSize: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.schemaContentSize)
            .firstOrNull
            ?.objectValue,
      ),
      width: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.schemaWidth)
            .firstOrNull
            ?.objectValue,
      ),
      height: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.schemaHeight)
            .firstOrNull
            ?.objectValue,
      ),
      duration: triples
          .where((t) => t.predicate == NS.schemaDuration)
          .firstOrNull
          ?.objectValue,
      thumbnail: triples
          .where((t) => t.predicate == NS.schemaThumbnail)
          .firstOrNull
          ?.objectValue,
    );
  }

  /// The entity URI (e.g. `kabuk:MediaObject/<uuid>`).
  final String uri;

  /// The media subtype (image, video, audio, or generic).
  final MediaType type;

  /// The display name (`schema:name`).
  final String? name;

  /// URL to the actual content (`schema:contentUrl`).
  final String? contentUrl;

  /// MIME type of the content (`schema:encodingFormat`).
  final String? encodingFormat;

  /// File size in bytes (`schema:contentSize`).
  final int? contentSize;

  /// Width in pixels (`schema:width`), for images and videos.
  final int? width;

  /// Height in pixels (`schema:height`), for images and videos.
  final int? height;

  /// ISO 8601 duration string (`schema:duration`), for audio/video.
  final String? duration;

  /// Thumbnail URL (`schema:thumbnail`).
  final String? thumbnail;

  /// Returns the Schema.org type URI for this media's [type].
  String get schemaTypeUri => _mediaTypeToUri(type);

  static int? _tryParseInt(String? value) =>
      value == null ? null : int.tryParse(value);

  static MediaType _resolveMediaType(List<Triple> triples) {
    final typeValues = triples
        .where((t) => t.predicate == NS.rdfType)
        .map((t) => t.objectValue)
        .toSet();

    if (typeValues.contains(NS.schemaImageObject)) return MediaType.image;
    if (typeValues.contains(NS.schemaVideoObject)) return MediaType.video;
    if (typeValues.contains(NS.schemaAudioObject)) return MediaType.audio;
    return MediaType.other;
  }
}

/// Maps a [MediaType] to its Schema.org type URI.
String _mediaTypeToUri(MediaType type) => switch (type) {
  MediaType.image => NS.schemaImageObject,
  MediaType.video => NS.schemaVideoObject,
  MediaType.audio => NS.schemaAudioObject,
  MediaType.other => NS.schemaMediaObject,
};

/// Convenience methods for working with media entities in the knowledge store.
extension KnowledgeStoreMediaExtension on KnowledgeStore {
  /// Creates a new media entity and returns its URI.
  ///
  /// The entity is typed according to [type] (e.g. `schema:ImageObject`).
  /// Numeric fields ([contentSize], [width], [height]) are stored as
  /// integer literals.
  Future<String> createMediaObject({
    required String name,
    required MediaType type,
    required String contentUrl,
    String? encodingFormat,
    int? contentSize,
    int? width,
    int? height,
    String? duration,
    String? thumbnail,
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('MediaObject');
      final typeUri = _mediaTypeToUri(type);
      await ctx.set(uri, NS.rdfType, typeUri, objectType: ObjectType.uri);
      await ctx.set(uri, NS.schemaName, name);
      await ctx.set(uri, NS.schemaContentUrl, contentUrl);
      if (encodingFormat != null) {
        await ctx.set(uri, NS.schemaEncodingFormat, encodingFormat);
      }
      if (contentSize != null) {
        await ctx.set(
          uri,
          NS.schemaContentSize,
          contentSize,
          objectType: ObjectType.integer,
        );
      }
      if (width != null) {
        await ctx.set(
          uri,
          NS.schemaWidth,
          width,
          objectType: ObjectType.integer,
        );
      }
      if (height != null) {
        await ctx.set(
          uri,
          NS.schemaHeight,
          height,
          objectType: ObjectType.integer,
        );
      }
      if (duration != null) {
        await ctx.set(uri, NS.schemaDuration, duration);
      }
      if (thumbnail != null) {
        await ctx.set(uri, NS.schemaThumbnail, thumbnail);
      }
      return uri;
    });
  }

  /// Retrieves a single media entity by [uri], or `null` if not found.
  Future<MediaData?> getMediaData(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return MediaData.fromTriples(uri, triples);
  }

  /// Updates mutable fields of an existing media entity.
  ///
  /// Only non-null parameters are written; others are left unchanged.
  Future<void> updateMediaObject(
    String uri, {
    String? name,
    String? contentUrl,
    String? encodingFormat,
    int? width,
    int? height,
  }) {
    return mutate((ctx) async {
      if (name != null) await ctx.set(uri, NS.schemaName, name);
      if (contentUrl != null) {
        await ctx.set(uri, NS.schemaContentUrl, contentUrl);
      }
      if (encodingFormat != null) {
        await ctx.set(uri, NS.schemaEncodingFormat, encodingFormat);
      }
      if (width != null) {
        await ctx.set(
          uri,
          NS.schemaWidth,
          width,
          objectType: ObjectType.integer,
        );
      }
      if (height != null) {
        await ctx.set(
          uri,
          NS.schemaHeight,
          height,
          objectType: ObjectType.integer,
        );
      }
    });
  }

  /// Deletes a media entity and all its triples.
  Future<void> deleteMediaObject(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }

  /// Lists media entities, optionally filtered by [type].
  ///
  /// Returns at most [limit] results ordered by name.
  Future<List<MediaData>> listMedia({int limit = 20, MediaType? type}) async {
    final typeUri = type != null ? _mediaTypeToUri(type) : NS.schemaMediaObject;

    // When filtering by a specific subtype, query that type directly.
    // When no filter, query all media subtypes.
    final List<String> uris;
    if (type != null) {
      final typeTriples = await query()
          .where(NS.rdfType, equals: typeUri)
          .orderBy(NS.schemaName)
          .limit(limit)
          .execute();
      uris = typeTriples.map((t) => t.subject).toSet().toList();
    } else {
      // Gather subjects for every media subtype.
      final allUris = <String>{};
      for (final subtype in [
        NS.schemaMediaObject,
        NS.schemaImageObject,
        NS.schemaVideoObject,
        NS.schemaAudioObject,
      ]) {
        final triples = await query()
            .where(NS.rdfType, equals: subtype)
            .execute();
        allUris.addAll(triples.map((t) => t.subject));
      }
      uris = allUris.take(limit).toList();
    }

    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    final media = <MediaData>[];
    for (final uri in uris) {
      final triples = allTriples[uri];
      if (triples != null && triples.isNotEmpty) {
        media.add(MediaData.fromTriples(uri, triples));
      }
    }
    return media;
  }
}
