/// Reusable utilities for Nostr stream operations.
///
/// Eliminates the duplicated Completer + Timer + StreamSubscription
/// pattern used across agents, providers, and widgets for collecting
/// Nostr events with a timeout.
library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:kabuk/services/nostr.dart';

/// Collects events from a Nostr [stream] until either:
/// - The stream completes (relay sends EOSE / EOF),
/// - [timeout] elapses (default 8 seconds), or
/// - [limit] events have been collected (if non-null).
///
/// Events can optionally be filtered by [where]. Only events passing
/// the predicate are collected; non-matching events are silently dropped.
///
/// Errors on the stream are logged but do not fail the collection.
///
/// ```dart
/// final events = await collectNostrEvents(
///   nostr.searchByHashtag(['bitcoin'], limit: 20),
///   where: (e) => e.kind == NostrKind.textNote,
///   timeout: Duration(seconds: 8),
/// );
/// ```
Future<List<NostrEvent>> collectNostrEvents(
  Stream<NostrEvent> stream, {
  int? limit,
  Duration timeout = const Duration(seconds: 8),
  bool Function(NostrEvent)? where,
}) async {
  final events = <NostrEvent>[];
  final completer = Completer<void>();

  Timer? timer;
  StreamSubscription<NostrEvent>? subscription;

  void finish() {
    timer?.cancel();
    subscription?.cancel();
    if (!completer.isCompleted) completer.complete();
  }

  timer = Timer(timeout, finish);

  subscription = stream.listen(
    (event) {
      if (where != null && !where(event)) return;
      events.add(event);
      if (limit != null && events.length >= limit) {
        finish();
      }
    },
    onDone: finish,
    onError: (Object e) {
      dev.log('Nostr stream error: $e', name: 'NostrUtils', error: e);
      finish();
    },
  );

  await completer.future;
  return events;
}

/// Processes events from a Nostr [stream] using an async [onEvent]
/// callback, completing after [timeout] or stream completion.
///
/// Unlike [collectNostrEvents], this variant does not collect events
/// into a list. Instead, each event is processed by [onEvent] as it
/// arrives. The returned [Future] resolves to the number of events
/// processed.
///
/// Use this when the listener needs to perform I/O (e.g., dedup
/// against the knowledge store) per event.
Future<int> processNostrEvents(
  Stream<NostrEvent> stream, {
  required Future<void> Function(NostrEvent event) onEvent,
  Duration timeout = const Duration(seconds: 8),
  bool Function(NostrEvent)? where,
  int? limit,
}) async {
  var count = 0;
  final completer = Completer<void>();

  Timer? timer;
  StreamSubscription<NostrEvent>? subscription;

  void finish() {
    timer?.cancel();
    subscription?.cancel();
    if (!completer.isCompleted) completer.complete();
  }

  timer = Timer(timeout, finish);

  subscription = stream.listen(
    (event) async {
      if (where != null && !where(event)) return;
      await onEvent(event);
      count++;
      if (limit != null && count >= limit) {
        finish();
      }
    },
    onDone: finish,
    onError: (Object e) {
      dev.log('Nostr stream error: $e', name: 'NostrUtils', error: e);
      finish();
    },
  );

  await completer.future;
  return count;
}
