/// Perception layer — observations streamed from the OS to the agent.
///
/// The bidirectional agent-OS channel has two halves. This is the
/// perception half: the mechanical subsystems (omnibar, channel surface,
/// viewers) publish what is happening so agents can perceive and act.
/// The action half (`ToolResult.channel`) lets agents populate channels
/// that the OS draws with existing primitives.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/plugins/channel.dart';
import 'package:kabuk/plugins/content_item.dart';

/// A single observation of OS/user activity.
///
/// Use exhaustive pattern matching:
/// ```dart
/// switch (event) {
///   case ChannelResolvedEvent(:final source) => ...,
///   case ChannelPopulatedEvent(:final channelUri) => ...,
///   case ChannelViewedEvent(:final channelUri) => ...,
///   case ItemOpenedEvent(:final itemTitle) => ...,
/// }
/// ```
sealed class ObservationEvent {
  /// Creates an [ObservationEvent].
  ObservationEvent();

  /// Timestamp of when the observation occurred (lazily captured on first
  /// access so the events remain const-constructible).
  late final DateTime occurredAt = DateTime.now().toUtc();

  /// Stable machine-readable kind of this observation.
  String get kind => switch (this) {
    ChannelResolvedEvent() => 'channel_resolved',
    ChannelPopulatedEvent() => 'channel_populated',
    ChannelViewedEvent() => 'channel_viewed',
    ItemOpenedEvent() => 'item_opened',
  };
}

/// The user typed a URL/query and the system resolved (found or created)
/// a channel for it.
final class ChannelResolvedEvent extends ObservationEvent {
  /// Creates a [ChannelResolvedEvent].
  ChannelResolvedEvent({
    required this.source,
    required this.channelUri,
    this.title,
    this.entityType,
  });

  /// The URL or query the user entered.
  final String source;

  /// URI of the resolved channel.
  final String channelUri;

  /// Display title of the channel, if known.
  final String? title;

  /// What kind of entity the channel represents.
  final ChannelEntityType? entityType;
}

/// An agent populated a channel with typed content items.
final class ChannelPopulatedEvent extends ObservationEvent {
  /// Creates a [ChannelPopulatedEvent].
  ChannelPopulatedEvent({
    required this.channelUri,
    required this.title,
    required this.itemCount,
    this.agentName,
    this.summary,
  });

  /// URI of the populated channel.
  final String channelUri;

  /// Display title of the channel.
  final String title;

  /// Number of items the agent produced.
  final int itemCount;

  /// Which agent populated the channel.
  final String? agentName;

  /// Optional one-line summary the agent wrote.
  final String? summary;
}

/// The user opened/viewed a channel surface.
final class ChannelViewedEvent extends ObservationEvent {
  /// Creates a [ChannelViewedEvent].
  ChannelViewedEvent({required this.channelUri, required this.title});

  /// URI of the viewed channel.
  final String channelUri;

  /// Display title of the channel.
  final String title;
}

/// The user opened a specific content item from a channel.
final class ItemOpenedEvent extends ObservationEvent {
  /// Creates an [ItemOpenedEvent].
  ItemOpenedEvent({
    required this.channelUri,
    required this.itemTitle,
    this.itemUrl,
    this.contentType,
  });

  /// URI of the channel the item belongs to.
  final String channelUri;

  /// Title of the opened item.
  final String itemTitle;

  /// Canonical URL of the item.
  final String? itemUrl;

  /// Content type of the item, when known.
  final ContentType? contentType;
}

/// A broadcast bus that the OS uses to publish [ObservationEvent]s.
///
/// The [Concierge] and proactive agents subscribe to this stream. Events
/// are also recorded to the knowledge store so agents can later recall
/// what the user has been looking at.
class ObservationBus {
  final StreamController<ObservationEvent> _controller =
      StreamController<ObservationEvent>.broadcast();

  /// Publish an [event] to all subscribers.
  void publish(ObservationEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// Stream of all observations published since subscription.
  Stream<ObservationEvent> get stream => _controller.stream;

  /// Close the bus and drop all subscribers.
  void dispose() => _controller.close();
}

/// The single [ObservationBus] used across the app.
///
/// Subsystems publish via `ref.read(observationBusProvider).publish(...)`.
/// The [Concierge] subscribes once at startup.
final observationBusProvider = Provider<ObservationBus>((ref) {
  final bus = ObservationBus();
  ref.onDispose(bus.dispose);
  return bus;
});