import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/concierge.dart';
import 'package:kabuk/agents/observation.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart';

import '../helpers/mocks.dart';

/// A [FakeMutationContext] that records every triple it writes.
class _CapturingContext extends FakeMutationContext {
  final List<({String s, String p, dynamic o})> triples = [];

  @override
  Future<void> set(
    String subject,
    String predicate,
    dynamic object, {
    ObjectType? objectType,
    String? graph,
  }) async {
    triples.add((s: subject, p: predicate, o: object));
  }

  @override
  Future<void> add(
    String subject,
    String predicate,
    dynamic object, {
    ObjectType? objectType,
    String? graph,
  }) async {
    triples.add((s: subject, p: predicate, o: object));
  }
}

void main() {
  late MockKnowledgeStore store;
  late ObservationBus bus;
  late _CapturingContext ctx;

  setUp(() {
    store = MockKnowledgeStore();
    bus = ObservationBus();
    ctx = _CapturingContext();
    store.onMutate = <T>(action) => action(ctx);
  });

  test('records a ChannelViewedEvent as observation triples', () async {
    final concierge = Concierge(store: store, bus: bus);

    bus.publish(
      ChannelViewedEvent(channelUri: 'kabuk:web/x', title: 'X channel'),
    );
    await pumpEventQueue();
    concierge.dispose();

    expect(ctx.triples, isNotEmpty);
    final byPredicate = {
      for (final t in ctx.triples) t.p: t.o,
    };
    expect(byPredicate[NS.rdfType], NS.kabukObservation);
    expect(byPredicate[NS.kabukObservationType], 'channel_viewed');
    expect(byPredicate[NS.schemaDateCreated], isNotNull);

    final data = jsonDecode(byPredicate[NS.kabukObservationData] as String)
        as Map<String, dynamic>;
    expect(data['channelUri'], 'kabuk:web/x');
    expect(data['title'], 'X channel');
  });

  test('records a ChannelPopulatedEvent payload', () async {
    final concierge = Concierge(store: store, bus: bus);

    bus.publish(
      ChannelPopulatedEvent(
        channelUri: 'kabuk:usenet/movie',
        title: 'Movie',
        itemCount: 4,
        agentName: 'discover',
      ),
    );
    await pumpEventQueue();
    concierge.dispose();

    final byPredicate = {
      for (final t in ctx.triples) t.p: t.o,
    };
    expect(byPredicate[NS.kabukObservationType], 'channel_populated');
    final data = jsonDecode(byPredicate[NS.kabukObservationData] as String)
        as Map<String, dynamic>;
    expect(data['itemCount'], 4);
    expect(data['agentName'], 'discover');
  });

  test('records an ItemOpenedEvent', () async {
    final concierge = Concierge(store: store, bus: bus);

    bus.publish(
      ItemOpenedEvent(
        channelUri: 'c',
        itemTitle: 'A video',
        itemUrl: 'https://x/v',
      ),
    );
    await pumpEventQueue();
    concierge.dispose();

    final byPredicate = {
      for (final t in ctx.triples) t.p: t.o,
    };
    expect(byPredicate[NS.kabukObservationType], 'item_opened');
    final data = jsonDecode(byPredicate[NS.kabukObservationData] as String)
        as Map<String, dynamic>;
    expect(data['itemTitle'], 'A video');
    expect(data['itemUrl'], 'https://x/v');
  });

  test('never throws when the store write fails', () async {
    store.onMutate = <T>(action) => throw StateError('db down');
    final concierge = Concierge(store: store, bus: bus);

    // Should not throw even though the store errors.
    bus.publish(
      ChannelViewedEvent(channelUri: 'c', title: 'T'),
    );
    await pumpEventQueue();
    concierge.dispose();
  });
}