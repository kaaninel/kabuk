import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/observation.dart';
import 'package:kabuk/plugins/channel.dart';
import 'package:kabuk/plugins/content_item.dart';

void main() {
  group('ObservationBus', () {
    test('delivers published events to subscribers', () async {
      final bus = ObservationBus();
      final received = <ObservationEvent>[];
      final sub = bus.stream.listen(received.add);

      bus.publish(
        ChannelResolvedEvent(
          source: 'https://example.com',
          channelUri: 'kabuk:web/example-com',
          title: 'Example',
        ),
      );
      bus.publish(
        ChannelViewedEvent(
          channelUri: 'kabuk:web/example-com',
          title: 'Example',
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(2));
      expect(received[0], isA<ChannelResolvedEvent>());
      expect(received[1], isA<ChannelViewedEvent>());
      await sub.cancel();
      bus.dispose();
    });

    test('does not deliver after dispose', () async {
      final bus = ObservationBus();
      final received = <ObservationEvent>[];
      final sub = bus.stream.listen(received.add);
      bus.dispose();

      bus.publish(
        ChannelResolvedEvent(
          source: 'x',
          channelUri: 'c',
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
      await sub.cancel();
    });
  });

  group('ObservationEvent kinds', () {
    test('reports stable kind strings', () {
      expect(
        ChannelResolvedEvent(source: 's', channelUri: 'c').kind,
        'channel_resolved',
      );
      expect(
        ChannelPopulatedEvent(
          channelUri: 'c',
          title: 't',
          itemCount: 3,
        ).kind,
        'channel_populated',
      );
      expect(
        ChannelViewedEvent(channelUri: 'c', title: 't').kind,
        'channel_viewed',
      );
      expect(
        ItemOpenedEvent(channelUri: 'c', itemTitle: 'i').kind,
        'item_opened',
      );
    });

    test('captures an occurredAt timestamp lazily', () {
      final event = ChannelResolvedEvent(source: 's', channelUri: 'c');
      expect(event.occurredAt.isBefore(DateTime.now().add(const Duration(seconds: 1))), isTrue);
      expect(event.occurredAt.isUtc, isTrue);
    });

    test('carries payload fields', () {
      final populated = ChannelPopulatedEvent(
        channelUri: 'kabuk:usenet/movie',
        title: 'Movie',
        itemCount: 5,
        agentName: 'discover',
        summary: 'Found 5 releases',
      );
      expect(populated.channelUri, 'kabuk:usenet/movie');
      expect(populated.itemCount, 5);
      expect(populated.agentName, 'discover');
      expect(populated.summary, 'Found 5 releases');

      final opened = ItemOpenedEvent(
        channelUri: 'c',
        itemTitle: 'A video',
        itemUrl: 'https://x/v',
        contentType: ContentType.video,
      );
      expect(opened.itemTitle, 'A video');
      expect(opened.contentType, ContentType.video);
    });
  });

  group('ChannelResolvedEvent entity type', () {
    test('carries the entity type when provided', () {
      final event = ChannelResolvedEvent(
        source: 'r/nostr',
        channelUri: 'kabuk:reddit/r-nostr',
        title: 'r/nostr',
        entityType: ChannelEntityType.subreddit,
      );
      expect(event.entityType, ChannelEntityType.subreddit);
    });
  });
}