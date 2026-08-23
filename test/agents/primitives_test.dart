import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/primitives.dart';
import 'package:kabuk/plugins/content_item.dart';

void main() {
  group('PrimitiveCatalog', () {
    test('covers every ContentType', () {
      expect(primitiveForType(ContentType.video).id, 'video_card');
      expect(primitiveForType(ContentType.image).id, 'image_card');
      expect(primitiveForType(ContentType.audio).id, 'audio_card');
      expect(primitiveForType(ContentType.article).id, 'article_card');
      expect(primitiveForType(ContentType.document).id, 'document_card');
      expect(primitiveForType(ContentType.profile).id, 'profile_card');
      expect(primitiveForType(ContentType.channel).id, 'channel_card');
      // Unknown/other falls back to generic.
      expect(primitiveForType(ContentType.mixed).id, 'generic_card');
    });

    test('every spec declares a schema with required fields', () {
      for (final spec in kabukPrimitiveCatalog) {
        expect(spec.schema, contains('required'));
        expect(spec.schema['required'], contains('title'));
      }
    });

    test('buildPrimitivePrompt lists the primitives', () {
      final prompt = buildPrimitivePrompt();
      expect(prompt, contains('video_card'));
      expect(prompt, contains('article_card'));
      expect(prompt, contains('you never author UI'));
    });
  });

  group('contentItemFromMap', () {
    test('builds a video item with metadata', () {
      final item = contentItemFromMap({
        'contentType': 'video',
        'externalId': 'vid-1',
        'title': 'Intro to Kabuk',
        'url': 'https://example.com/v.mp4',
        'thumbnailUrl': 'https://example.com/t.jpg',
        'durationSeconds': 120,
        'resolution': '1080p',
        'streamUrl': 'https://example.com/stream.mp4',
        'author': 'Alice',
        'publishedAt': '2026-01-01T00:00:00Z',
        'source': 'youtube',
      });

      expect(item, isNotNull);
      expect(item!.contentType, ContentType.video);
      expect(item.metadata, isA<VideoMeta>());
      final meta = item.metadata! as VideoMeta;
      expect(meta.duration, const Duration(seconds: 120));
      expect(meta.resolution, '1080p');
      expect(meta.streamUrl, 'https://example.com/stream.mp4');
      expect(item.author?.name, 'Alice');
      expect(item.extra['source'], 'youtube');
      expect(item.publishedAt, DateTime.parse('2026-01-01T00:00:00Z'));
    });

    test('builds an article item with body', () {
      final item = contentItemFromMap({
        'contentType': 'article',
        'externalId': 'art-1',
        'title': 'Post',
        'body': 'Full body',
        'readTimeMinutes': 4,
      });

      expect(item, isNotNull);
      expect(item!.metadata, isA<ArticleMeta>());
      final meta = item.metadata! as ArticleMeta;
      expect(meta.body, 'Full body');
      expect(meta.readTimeMinutes, 4);
    });

    test('builds an audio item', () {
      final item = contentItemFromMap({
        'contentType': 'audio',
        'externalId': 'a-1',
        'title': 'Track',
        'artist': 'Artist',
        'durationSeconds': 300,
      });

      expect(item, isNotNull);
      expect(item!.metadata, isA<AudioMeta>());
      final meta = item.metadata! as AudioMeta;
      expect(meta.artist, 'Artist');
      expect(meta.duration, const Duration(seconds: 300));
    });

    test('returns null when title is missing', () {
      expect(
        contentItemFromMap({'contentType': 'video', 'externalId': 'x'}),
        isNull,
      );
    });

    test('falls back to url for externalId', () {
      final item = contentItemFromMap({
        'contentType': 'article',
        'title': 'No id',
        'url': 'https://example.com/a',
      });
      expect(item, isNotNull);
      expect(item!.externalId, 'https://example.com/a');
    });

    test('falls back to the given plugin id', () {
      final item = contentItemFromMap(
        {'contentType': 'article', 'title': 'X'},
        fallbackPluginId: 'wikipedia',
      );
      expect(item, isNotNull);
      expect(item!.sourcePluginId, 'wikipedia');
    });
  });

  group('contentItemFromParts', () {
    test('builds a typed item from parts', () {
      final item = contentItemFromParts(
        sourcePluginId: 'usenet',
        externalId: 'rel-1',
        contentType: ContentType.video,
        title: 'Movie 2026',
        description: '1080p · 4 GB',
        url: 'https://indexer/nzb/1',
        author: 'poster',
        publishedAt: DateTime.utc(2026, 1, 1),
      );

      expect(item.contentType, ContentType.video);
      expect(item.sourcePluginId, 'usenet');
      expect(item.author?.name, 'poster');
      expect(item.publishedAt, DateTime.utc(2026, 1, 1));
    });
  });
}