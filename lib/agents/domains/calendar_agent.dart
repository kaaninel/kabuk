/// Calendar agent — manages events and reminders in the knowledge store.
///
/// Provides tools for creating, listing, searching, updating, and deleting
/// calendar events. Events are stored as `schema:Event` entities with
/// Schema.org predicates (startDate, endDate, location, etc.).
library;

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/memory.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart';

/// Agent for managing calendar events and reminders.
///
/// Uses [AgentMemoryMixin] to remember user preferences such as
/// default event duration, preferred reminder times, and timezone.
class CalendarAgent extends BaseAgent with AgentMemoryMixin {
  @override
  String get name => 'calendar';

  @override
  String get description =>
      'Manages calendar events — create, list, search, update, and set reminders.';

  @override
  String get systemPrompt => '''
You are the Calendar agent for Kabuk. You manage the user's calendar events,
stored as schema:Event entities in the knowledge store.

Capabilities:
• Create events with title, start/end dates, location, and description
• List upcoming events (sorted by start date)
• Search events by keyword
• Update event details (title, dates, location, description)
• Set reminders for events
• Delete events permanently

Date Handling:
• Accept natural language dates: "tomorrow at 3pm", "next Monday", "in 2 hours",
"March 15th"
• Convert all dates to ISO 8601 format (e.g., 2026-03-15T15:00:00) for storage
• Use the current date/time provided in this prompt as your reference point
• When the user says a time without a date, assume today if the time hasn't
passed, otherwise tomorrow
• If end time is not specified, default to 1 hour after start time

Usage Guidelines:
• After creating an event, confirm with the title, date, and time
• When listing events, show them chronologically with date, time, and title
• If no upcoming events exist, let the user know and offer to create one
• For reminders, confirm what time the reminder is set for
''';

  @override
  List<AgentTool> get tools => [
    AgentTool(
      name: 'create_event',
      description: 'Create a new calendar event.',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'Event title.'},
          'startDate': {
            'type': 'string',
            'description': 'Start date/time in ISO 8601 format.',
          },
          'endDate': {
            'type': 'string',
            'description': 'End date/time in ISO 8601 format (optional).',
          },
          'location': {'type': 'string', 'description': 'Event location.'},
          'description': {
            'type': 'string',
            'description': 'Event description or notes.',
          },
        },
        'required': ['title', 'startDate'],
      },
      execute: _createEvent,
    ),
    AgentTool(
      name: 'list_events',
      description: 'List upcoming calendar events.',
      parameters: {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description': 'Max events to return (default 20).',
          },
        },
      },
      execute: _listEvents,
    ),
    AgentTool(
      name: 'search_events',
      description: 'Search events by keyword.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Search term.'},
        },
        'required': ['query'],
      },
      execute: _searchEvents,
    ),
    AgentTool(
      name: 'update_event',
      description: 'Update an existing event.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {'type': 'string', 'description': 'Event entity URI.'},
          'title': {'type': 'string', 'description': 'New title.'},
          'startDate': {'type': 'string', 'description': 'New start date.'},
          'endDate': {'type': 'string', 'description': 'New end date.'},
          'location': {'type': 'string', 'description': 'New location.'},
          'description': {'type': 'string', 'description': 'New description.'},
        },
        'required': ['uri'],
      },
      execute: _updateEvent,
    ),
    AgentTool(
      name: 'set_reminder',
      description: 'Set a reminder for an event.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {'type': 'string', 'description': 'Event entity URI.'},
          'reminderDate': {
            'type': 'string',
            'description': 'When to remind, in ISO 8601 format.',
          },
        },
        'required': ['uri', 'reminderDate'],
      },
      execute: _setReminder,
    ),
    AgentTool(
      name: 'delete_event',
      description: 'Delete a calendar event.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {'type': 'string', 'description': 'Event entity URI.'},
        },
        'required': ['uri'],
      },
      execute: _deleteEvent,
    ),
    AgentTool(
      name: 'get_event',
      description: 'Get full details of an event.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {'type': 'string', 'description': 'Event entity URI.'},
        },
        'required': ['uri'],
      },
      execute: _getEvent,
    ),
  ];

  @override
  Set<AgentCapability> get requiredCapabilities => {
    AgentCapability.llmCall,
    AgentCapability.knowledgeRead,
    AgentCapability.knowledgeWrite,
  };

  @override
  Future<AgentResponse> process(
    AgentMessage message,
    AgentContext context,
  ) async {
    final content = switch (message) {
      UserMessage(:final content) => content,
      SystemMessage(:final content) => content,
      _ => '',
    };

    if (content.isEmpty) {
      return const AgentResponse.text(
        'What would you like to do with your calendar?',
      );
    }

    // Include conversation history for multi-turn context.
    final llmMessages = <LlmMessage>[
      if (message case UserMessage(:final history?)) ...history,
      LlmMessage.user(content),
    ];

    final prompt = await buildSystemPromptWithMemory(context);
    return processLlmRequest(
      context: context,
      messages: llmMessages,
      systemPrompt: prompt,
      temperature: 0.5,
    );
  }

  // ---------------------------------------------------------------------------
  // Tool Implementations
  // ---------------------------------------------------------------------------

  Future<ToolResult> _createEvent(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final title = args['title'] as String? ?? 'Untitled Event';
    final startDate = args['startDate'] as String?;
    final endDate = args['endDate'] as String?;
    final location = args['location'] as String?;
    final description = args['description'] as String?;

    if (startDate == null || startDate.isEmpty) {
      return const ToolResult.error('Start date is required.');
    }

    late final String entityUri;

    await context.knowledge.mutate((ctx) async {
      entityUri = ctx.create('Event');
      await ctx.set(entityUri, NS.rdfType, NS.schemaEvent);
      await ctx.set(entityUri, NS.schemaName, title);
      await ctx.set(entityUri, NS.schemaStartDate, startDate);
      await ctx.set(
        entityUri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );

      if (endDate != null) {
        await ctx.set(entityUri, NS.schemaEndDate, endDate);
      }
      if (location != null) {
        await ctx.set(entityUri, NS.schemaLocation, location);
      }
      if (description != null) {
        await ctx.set(entityUri, NS.schemaDescription, description);
      }
    });

    final locationNote = location != null ? ' at $location' : '';
    return ToolResult.compound([
      ToolResult.text(
        'Created event "$title" on $startDate$locationNote\nURI: $entityUri',
      ),
      ToolResult.widget(
        library: 'kabuk:calendar',
        widget: 'EventCard',
        bindings: {
          'name': title,
          'startDate': startDate,
          'endDate': endDate ?? '',
          'location': location ?? '',
        },
      ),
    ]);
  }

  Future<ToolResult> _listEvents(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final limit = (args['limit'] as int?) ?? 20;

    final triples = await context.knowledge
        .query()
        .predicate(NS.rdfType)
        .object(NS.schemaEvent)
        .limit(limit)
        .execute();

    if (triples.isEmpty) {
      return const ToolResult.text('No events found.');
    }

    final subjects = triples.map((t) => t.subject).toList();
    final entities = await context.knowledge.getEntities(subjects);

    final lines = <String>[];
    for (final triple in triples) {
      final entity = entities[triple.subject] ?? [];
      final name = entity
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue;
      final start = entity
          .where((t) => t.predicate == NS.schemaStartDate)
          .firstOrNull
          ?.objectValue;
      final loc = entity
          .where((t) => t.predicate == NS.schemaLocation)
          .firstOrNull
          ?.objectValue;

      final details = [?start, ?loc].join(' · ');

      lines.add(
        '- **${name ?? 'Untitled'}**${details.isNotEmpty ? ' ($details)' : ''}\n'
        '  URI: `${triple.subject}`',
      );
    }

    return ToolResult.text(
      'Found ${triples.length} event(s):\n${lines.join('\n')}',
    );
  }

  Future<ToolResult> _searchEvents(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final query = args['query'] as String? ?? '';
    if (query.isEmpty) {
      return const ToolResult.error('Search query cannot be empty.');
    }

    final results = await context.knowledge.search(query);
    final subjects = <String>{};
    for (final triple in results) {
      subjects.add(triple.subject);
    }

    final subjectList = subjects.take(10).toList();
    final entities = await context.knowledge.getEntities(subjectList);

    final lines = <String>[];
    for (final subject in subjectList) {
      final entity = entities[subject] ?? [];
      final isEvent = entity.any(
        (t) => t.predicate == NS.rdfType && t.objectValue == NS.schemaEvent,
      );
      if (!isEvent) continue;

      final name = entity
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue;
      lines.add('- **${name ?? 'Untitled'}** — `$subject`');
    }

    if (lines.isEmpty) {
      return ToolResult.text('No events matching "$query".');
    }

    return ToolResult.text(
      'Found ${lines.length} event(s):\n${lines.join('\n')}',
    );
  }

  Future<ToolResult> _updateEvent(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final uri = args['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      return const ToolResult.error('Event URI is required.');
    }

    final entity = await context.knowledge.getEntity(uri);
    if (entity.isEmpty) {
      return ToolResult.error('Event not found: $uri');
    }

    final fields = <String, String>{
      if (args['title'] case final String v) NS.schemaName: v,
      if (args['startDate'] case final String v) NS.schemaStartDate: v,
      if (args['endDate'] case final String v) NS.schemaEndDate: v,
      if (args['location'] case final String v) NS.schemaLocation: v,
      if (args['description'] case final String v) NS.schemaDescription: v,
    };

    if (fields.isEmpty) {
      return const ToolResult.error('Nothing to update.');
    }

    await context.knowledge.mutate((ctx) async {
      for (final entry in fields.entries) {
        await ctx.set(uri, entry.key, entry.value);
      }
      await ctx.set(
        uri,
        NS.schemaDateModified,
        DateTime.now().toIso8601String(),
      );
    });

    // Re-read to get the current state for the card.
    final updated = await context.knowledge.getEntity(uri);
    final name = _tripleValue(updated, NS.schemaName) ?? 'Untitled';
    final startDate = _tripleValue(updated, NS.schemaStartDate) ?? '';
    final endDate = _tripleValue(updated, NS.schemaEndDate) ?? '';
    final location = _tripleValue(updated, NS.schemaLocation) ?? '';

    return ToolResult.compound([
      ToolResult.text('Updated ${fields.length} field(s) on event: $uri'),
      ToolResult.widget(
        library: 'kabuk:calendar',
        widget: 'EventCard',
        bindings: {
          'name': name,
          'startDate': startDate,
          'endDate': endDate,
          'location': location,
        },
      ),
    ]);
  }

  Future<ToolResult> _setReminder(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final uri = args['uri'] as String?;
    final reminderDate = args['reminderDate'] as String?;

    if (uri == null || uri.isEmpty) {
      return const ToolResult.error('Event URI is required.');
    }
    if (reminderDate == null || reminderDate.isEmpty) {
      return const ToolResult.error('Reminder date is required.');
    }

    final entity = await context.knowledge.getEntity(uri);
    if (entity.isEmpty) {
      return ToolResult.error('Event not found: $uri');
    }

    await context.knowledge.mutate((ctx) async {
      await ctx.set(uri, NS.kabukReminder, reminderDate);
    });

    // Re-read to get the current state for the card.
    final updated = await context.knowledge.getEntity(uri);
    final name = _tripleValue(updated, NS.schemaName) ?? 'Untitled';
    final startDate = _tripleValue(updated, NS.schemaStartDate) ?? '';
    final endDate = _tripleValue(updated, NS.schemaEndDate) ?? '';
    final location = _tripleValue(updated, NS.schemaLocation) ?? '';

    return ToolResult.compound([
      ToolResult.text('Reminder set for $reminderDate on event: $uri'),
      ToolResult.widget(
        library: 'kabuk:calendar',
        widget: 'EventCard',
        bindings: {
          'name': name,
          'startDate': startDate,
          'endDate': endDate,
          'location': location,
        },
      ),
    ]);
  }

  Future<ToolResult> _deleteEvent(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final uri = args['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      return const ToolResult.error('Event URI is required.');
    }

    final entity = await context.knowledge.getEntity(uri);
    if (entity.isEmpty) {
      return ToolResult.error('Event not found: $uri');
    }

    await context.knowledge.mutate((ctx) async {
      await ctx.remove(subject: uri);
    });

    return ToolResult.text('Event deleted: $uri');
  }

  Future<ToolResult> _getEvent(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final uri = args['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      return const ToolResult.error('Event URI is required.');
    }

    final entity = await context.knowledge.getEntity(uri);
    if (entity.isEmpty) {
      return ToolResult.error('Event not found: $uri');
    }

    String? field(String predicate) =>
        entity.where((t) => t.predicate == predicate).firstOrNull?.objectValue;

    final name = field(NS.schemaName) ?? 'Untitled';
    final start = field(NS.schemaStartDate);
    final end = field(NS.schemaEndDate);
    final location = field(NS.schemaLocation);
    final desc = field(NS.schemaDescription);
    final reminder = field(NS.kabukReminder);
    final created = field(NS.schemaDateCreated);

    final parts = <String>[
      '# $name',
      if (start != null) 'Start: $start',
      if (end != null) 'End: $end',
      if (location != null) 'Location: $location',
      if (desc != null) 'Description: $desc',
      if (reminder != null) 'Reminder: $reminder',
      if (created != null) 'Created: $created',
    ];

    return ToolResult.compound([
      ToolResult.text(parts.join('\n')),
      ToolResult.widget(
        library: 'kabuk:calendar',
        widget: 'EventCard',
        bindings: {
          'name': name,
          'startDate': start ?? '',
          'endDate': end ?? '',
          'location': location ?? '',
        },
      ),
    ]);
  }

  /// Extract the first object value for [predicate] from [triples].
  String? _tripleValue(List<Triple> triples, String predicate) =>
      triples.where((t) => t.predicate == predicate).firstOrNull?.objectValue;
}
