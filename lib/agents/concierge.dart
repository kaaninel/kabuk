/// Concierge — turns OS observations into a perception memory for agents.
///
/// Subscribes to the [ObservationBus] once at startup and records every
/// observation into the knowledge store as RDF triples. This is the
/// substrate that lets the agent recall what the user has been doing
/// ("what did I look at last?"), without the mechanical subsystems having
/// to know anything about agents.
///
/// Cheap rule-based proactive behavior can be layered on top of the same
/// stream (see the TODO in [Concierge._handle]) without changing the
/// emission side.
library;

import 'dart:async';
import 'dart:convert';

import 'package:kabuk/agents/observation.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';

/// Listens to OS observations and persists them to the knowledge store.
class Concierge {
  /// Creates a [Concierge] that records observations from [bus] into [store].
  Concierge({required KnowledgeStore store, required ObservationBus bus})
    : _store = store,
      _bus = bus {
    _subscription = bus.stream.listen(_handle);
  }

  final KnowledgeStore _store;
  final ObservationBus _bus;
  StreamSubscription<ObservationEvent>? _subscription;

  /// The store observations are recorded into.
  KnowledgeStore get store => _store;

  /// The observation bus being consumed.
  ObservationBus get bus => _bus;

  Future<void> _handle(ObservationEvent event) async {
    try {
      await recordObservation(_store, event);
    } on Object {
      // Perception memory is best-effort — a failed record must never
      // break the surface that published the observation.
    }
  }

  /// Persists a single [event] as a `kabuk:Observation` entity.
  static Future<void> recordObservation(
    KnowledgeStore store,
    ObservationEvent event,
  ) async {
    final now = event.occurredAt.toIso8601String();
    final payload = switch (event) {
      ChannelResolvedEvent(
        :final source,
        :final channelUri,
        :final title,
      ) => <String, dynamic>{
          'source': source,
          'channelUri': channelUri,
          if (title != null) 'title': title,
        },
      ChannelPopulatedEvent(
        :final channelUri,
        :final title,
        :final itemCount,
        :final agentName,
        :final summary,
      ) => <String, dynamic>{
          'channelUri': channelUri,
          'title': title,
          'itemCount': itemCount,
          if (agentName != null) 'agentName': agentName,
          if (summary != null) 'summary': summary,
        },
      ChannelViewedEvent(:final channelUri, :final title) =>
        <String, dynamic>{'channelUri': channelUri, 'title': title},
      ItemOpenedEvent(
        :final channelUri,
        :final itemTitle,
        :final itemUrl,
      ) => <String, dynamic>{
          'channelUri': channelUri,
          'itemTitle': itemTitle,
          if (itemUrl != null) 'itemUrl': itemUrl,
        },
    };

    await store.mutate((ctx) async {
      final uri = ctx.create('Observation');
      await ctx.set(uri, NS.rdfType, NS.kabukObservation);
      await ctx.set(uri, NS.kabukObservationType, event.kind);
      await ctx.set(uri, NS.kabukObservationData, jsonEncode(payload));
      await ctx.set(uri, NS.schemaDateCreated, now);
    });
  }

  /// Stops consuming observations.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}