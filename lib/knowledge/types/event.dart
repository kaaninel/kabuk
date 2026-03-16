/// Schema.org Event type helpers for the Kabuk knowledge store.
///
/// Provides [EventData] for structured access to Event entities, plus
/// [KnowledgeStoreEventExtension] convenience methods on [KnowledgeStore].
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

/// Immutable representation of a Schema.org Event entity.
///
/// All fields are extracted from the underlying RDF triples.
/// Use [EventData.fromTriples] to construct from raw store data,
/// or the [KnowledgeStoreEventExtension] helpers for high-level access.
@immutable
class EventData {
  /// Creates an [EventData] with the given field values.
  const EventData({
    required this.uri,
    this.name,
    this.startDate,
    this.endDate,
    this.location,
    this.description,
    this.organizer,
    this.reminder,
  });

  /// Constructs an [EventData] from a subject [uri] and its [triples].
  ///
  /// Extracts Schema.org properties by matching predicate URIs.
  /// Unknown predicates are silently ignored.
  factory EventData.fromTriples(String uri, List<Triple> triples) {
    return EventData(
      uri: uri,
      name: triples
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue,
      startDate: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaStartDate)
            .firstOrNull
            ?.objectValue,
      ),
      endDate: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaEndDate)
            .firstOrNull
            ?.objectValue,
      ),
      location: triples
          .where((t) => t.predicate == NS.schemaLocation)
          .firstOrNull
          ?.objectValue,
      description: triples
          .where((t) => t.predicate == NS.schemaDescription)
          .firstOrNull
          ?.objectValue,
      organizer: triples
          .where((t) => t.predicate == NS.schemaOrganizer)
          .firstOrNull
          ?.objectValue,
      reminder: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.kabukReminder)
            .firstOrNull
            ?.objectValue,
      ),
    );
  }

  /// The entity URI (e.g. `kabuk:Event/<uuid>`).
  final String uri;

  /// The event name (`schema:name`).
  final String? name;

  /// When the event starts (`schema:startDate`).
  final DateTime? startDate;

  /// When the event ends (`schema:endDate`).
  final DateTime? endDate;

  /// The event location (`schema:location`).
  final String? location;

  /// A free-text description (`schema:description`).
  final String? description;

  /// The organizer URI or name (`schema:organizer`).
  final String? organizer;

  /// An optional reminder timestamp (`kabuk:reminder`).
  final DateTime? reminder;

  static DateTime? _tryParseDateTime(String? value) =>
      value == null ? null : DateTime.tryParse(value);
}

/// Convenience methods for working with Event entities in the knowledge store.
extension KnowledgeStoreEventExtension on KnowledgeStore {
  /// Creates a new Event entity and returns its URI.
  ///
  /// [name] becomes `schema:name`. Date fields are stored as ISO 8601 strings.
  Future<String> createEvent({
    required String name,
    required DateTime startDate,
    DateTime? endDate,
    String? location,
    String? description,
    String? organizer,
    DateTime? reminder,
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('Event');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.schemaEvent,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      await ctx.set(uri, NS.schemaStartDate, startDate.toIso8601String());
      if (endDate != null) {
        await ctx.set(uri, NS.schemaEndDate, endDate.toIso8601String());
      }
      if (location != null) {
        await ctx.set(uri, NS.schemaLocation, location);
      }
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      if (organizer != null) {
        await ctx.set(uri, NS.schemaOrganizer, organizer);
      }
      if (reminder != null) {
        await ctx.set(uri, NS.kabukReminder, reminder.toIso8601String());
      }
      return uri;
    });
  }

  /// Retrieves a single Event by [uri], or `null` if not found.
  Future<EventData?> getEventData(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return EventData.fromTriples(uri, triples);
  }

  /// Lists Event entities ordered by start date (soonest first).
  ///
  /// Returns at most [limit] results.
  Future<List<EventData>> listEvents({int limit = 20}) async {
    final typeTriples = await query()
        .where(NS.rdfType, equals: NS.schemaEvent)
        .orderBy(NS.schemaStartDate)
        .limit(limit)
        .execute();

    final uris = typeTriples.map((t) => t.subject).toSet();
    final events = <EventData>[];
    for (final uri in uris) {
      final triples = await getEntity(uri);
      events.add(EventData.fromTriples(uri, triples));
    }
    return events;
  }
}
