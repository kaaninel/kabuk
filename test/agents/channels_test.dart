import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/channels.dart';
import 'package:kabuk/plugins/channel.dart';
import 'package:kabuk/plugins/content_item.dart';

void main() {
  ContentItem item(String id) => ContentItem(
    sourcePluginId: 'test',
    externalId: id,
    contentType: ContentType.article,
    title: 'Item $id',
  );

  Channel channel(String uri) => Channel(
    entityUri: uri,
    entityType: ChannelEntityType.topic,
    title: 'Channel',
  );

  group('channelUriFor', () {
    test('is stable and deterministic for the same source', () {
      expect(channelUriFor('https://news.ycombinator.com'), 'kabuk:agent/news-ycombinator-com');
      expect(channelUriFor('https://news.ycombinator.com'), channelUriFor('https://news.ycombinator.com'));
    });

    test('honours the prefix', () {
      expect(
        channelUriFor('flutter', prefix: 'nostr'),
        'kabuk:nostr/flutter',
      );
    });

    test('handles empty/edge input', () {
      expect(channelUriFor('https://example.com'), 'kabuk:agent/example-com');
      expect(channelUriFor('r/nostr'), 'kabuk:agent/r-nostr');
    });
  });

  group('ChannelSession', () {
    test('captures populatedAt when omitted', () {
      final before = DateTime.now();
      final session = ChannelSession(channel: channel('c'), items: []);
      expect(session.populatedAt.isBefore(before), isFalse);
      expect(session.populatedAt.isAfter(before.add(const Duration(seconds: -5))), isTrue);
    });

    test('copyWith overrides fields and keeps the rest', () {
      final session = ChannelSession(
        channel: channel('c'),
        items: [item('1')],
        summary: 'sum',
        agentName: 'discover',
        source: 'query',
      );
      final copy = session.copyWith(items: [item('2')]);
      expect(copy.items.single.externalId, '2');
      expect(copy.summary, 'sum');
      expect(copy.agentName, 'discover');
      expect(copy.source, 'query');
      expect(copy.channel, channel('c'));
    });
  });

  group('AgentChannelController', () {
    test('starts empty', () {
      final controller = AgentChannelController();
      expect(controller.current, isNull);
    });

    test('populate sets the active session', () {
      final controller = AgentChannelController();
      final session = ChannelSession(channel: channel('c'), items: [item('1')]);
      controller.populate(session);
      expect(controller.current, session);
      expect(controller.state, session);
    });

    test('populate replaces the previous session', () {
      final controller = AgentChannelController();
      controller.populate(ChannelSession(channel: channel('a'), items: []));
      final second = ChannelSession(channel: channel('b'), items: []);
      controller.populate(second);
      expect(controller.current!.channel.entityUri, 'b');
    });

    test('clear empties the active session', () {
      final controller = AgentChannelController();
      controller.populate(ChannelSession(channel: channel('c'), items: []));
      controller.clear();
      expect(controller.current, isNull);
    });
  });
}