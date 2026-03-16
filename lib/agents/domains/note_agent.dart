/// Note agent — full CRUD for notes stored in the knowledge store.
///
/// Provides tools for creating, reading, updating, searching, listing,
/// and deleting notes. Notes are stored as `schema:NoteDigitalDocument`
/// entities with Schema.org predicates.
library;

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/memory.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart';

/// Agent specialized in note management.
///
/// Handles creating, editing, searching, listing, and deleting notes.
/// All notes live in the knowledge store as RDF triples using Schema.org
/// vocabulary. Uses [AgentMemoryMixin] to remember user preferences
/// (e.g. default tags, formatting) across sessions.
class NoteAgent extends BaseAgent with AgentMemoryMixin {
  @override
  String get name => 'notes';

  @override
  String get description =>
      'Manages notes — create, edit, search, list, and delete.';

  @override
  String get systemPrompt => '''
You are the Note agent for Kabuk. You manage the user's notes, which are stored
as schema:NoteDigitalDocument entities in the knowledge store.

Capabilities:
• Create notes with a title, body, and optional tags
• List all notes or filter by tag
• Search notes by keyword (full-text search across title and body)
• Edit a note's title, body, or tags
• Delete notes permanently
• Tag/untag notes for organization

Usage Guidelines:
• Always use the appropriate tool — don't just describe what you would do.
• When creating a note, use the user's words as-is for the body unless they
ask you to rephrase or summarize.
• When listing notes, include the title and a brief preview. If there are many,
mention the total count.
• When the user says "write down", "remember", "save this", or "jot down",
treat it as a note creation request.
• After creating, editing, or deleting, confirm with the note title.
• If no notes are found, suggest creating one.
• Tags help organize notes — suggest relevant tags when creating if the user
hasn't specified any.
''';

  @override
  List<AgentTool> get tools => [
    AgentTool(
      name: 'create_note',
      description:
          'Create a new note in the knowledge store with a title and body.',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'The title of the note.'},
          'body': {
            'type': 'string',
            'description': 'The main content/body of the note.',
          },
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Optional tags for organizing the note.',
          },
        },
        'required': ['title', 'body'],
      },
      execute: _createNote,
    ),
    AgentTool(
      name: 'list_notes',
      description: 'List all notes in the knowledge store.',
      parameters: {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of notes to return (default 20).',
          },
        },
      },
      execute: _listNotes,
    ),
    AgentTool(
      name: 'search_notes',
      description: 'Search for notes matching a keyword.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The search term to find in note titles or body.',
          },
        },
        'required': ['query'],
      },
      execute: _searchNotes,
    ),
    AgentTool(
      name: 'edit_note',
      description: 'Edit an existing note by its entity URI.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {
            'type': 'string',
            'description': 'The entity URI of the note to edit.',
          },
          'title': {
            'type': 'string',
            'description': 'New title (omit to keep unchanged).',
          },
          'body': {
            'type': 'string',
            'description': 'New body text (omit to keep unchanged).',
          },
        },
        'required': ['uri'],
      },
      execute: _editNote,
    ),
    AgentTool(
      name: 'delete_note',
      description: 'Delete a note by its entity URI.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {
            'type': 'string',
            'description': 'The entity URI of the note to delete.',
          },
        },
        'required': ['uri'],
      },
      execute: _deleteNote,
    ),
    AgentTool(
      name: 'get_note',
      description: 'Get full details of a single note by URI.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {
            'type': 'string',
            'description': 'The entity URI of the note.',
          },
        },
        'required': ['uri'],
      },
      execute: _getNote,
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
        'What would you like to do with your notes?',
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
  // Tool implementations
  // ---------------------------------------------------------------------------

  Future<ToolResult> _createNote(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final title = args['title'] as String? ?? 'Untitled';
    final body = args['body'] as String? ?? '';
    final tags = (args['tags'] as List<dynamic>?)?.cast<String>() ?? [];

    late final String entityUri;

    await context.knowledge.mutate((ctx) async {
      entityUri = ctx.create('Note');
      await ctx.set(entityUri, NS.rdfType, NS.schemaNote);
      await ctx.set(entityUri, NS.schemaName, title);
      await ctx.set(entityUri, NS.schemaText, body);
      await ctx.set(
        entityUri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );
      await ctx.set(
        entityUri,
        NS.schemaDateModified,
        DateTime.now().toIso8601String(),
      );
      for (final tag in tags) {
        await ctx.add(entityUri, NS.kabukTag, tag);
      }
    });

    final tagText = tags.isEmpty ? '' : ' (tags: ${tags.join(', ')})';
    return ToolResult.compound([
      ToolResult.text('Created note "$title"$tagText\nURI: $entityUri'),
      ToolResult.widget(
        library: 'kabuk:notes',
        widget: 'NoteCard',
        bindings: {
          'name': title,
          'text': body.length > 100 ? '${body.substring(0, 100)}...' : body,
          'dateCreated': DateTime.now().toIso8601String(),
        },
      ),
    ]);
  }

  Future<ToolResult> _listNotes(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final limit = (args['limit'] as int?) ?? 20;

    final triples = await context.knowledge
        .query()
        .predicate(NS.rdfType)
        .object(NS.schemaNote)
        .limit(limit)
        .execute();

    if (triples.isEmpty) {
      return const ToolResult.text('No notes found.');
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
      final date = entity
          .where((t) => t.predicate == NS.schemaDateCreated)
          .firstOrNull
          ?.objectValue;
      lines.add(
        '- **${name ?? 'Untitled'}** (${date ?? 'undated'})\n'
        '  URI: `${triple.subject}`',
      );
    }

    return ToolResult.text(
      'Found ${triples.length} note(s):\n${lines.join('\n')}',
    );
  }

  Future<ToolResult> _searchNotes(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final query = args['query'] as String? ?? '';
    if (query.isEmpty) {
      return const ToolResult.error('Search query cannot be empty.');
    }

    final results = await context.knowledge.search(query);

    // Filter to notes only.
    final noteSubjects = <String>{};
    for (final triple in results) {
      noteSubjects.add(triple.subject);
    }

    if (noteSubjects.isEmpty) {
      return ToolResult.text('No notes matching "$query".');
    }

    final subjectList = noteSubjects.take(10).toList();
    final entities = await context.knowledge.getEntities(subjectList);

    final lines = <String>[];
    for (final subject in subjectList) {
      final entity = entities[subject] ?? [];
      final isNote = entity.any(
        (t) => t.predicate == NS.rdfType && t.objectValue == NS.schemaNote,
      );
      if (!isNote) continue;

      final name = entity
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue;
      final body = entity
          .where((t) => t.predicate == NS.schemaText)
          .firstOrNull
          ?.objectValue;
      final preview = body != null && body.length > 80
          ? '${body.substring(0, 80)}...'
          : body ?? '';

      lines.add('- **${name ?? 'Untitled'}**: $preview\n  URI: `$subject`');
    }

    if (lines.isEmpty) {
      return ToolResult.text('No notes matching "$query".');
    }

    return ToolResult.text(
      'Found ${lines.length} note(s):\n${lines.join('\n')}',
    );
  }

  Future<ToolResult> _editNote(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final uri = args['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      return const ToolResult.error('Note URI is required.');
    }

    final entity = await context.knowledge.getEntity(uri);
    if (entity.isEmpty) {
      return ToolResult.error('Note not found: $uri');
    }

    final newTitle = args['title'] as String?;
    final newBody = args['body'] as String?;

    final now = DateTime.now().toIso8601String();

    await context.knowledge.mutate((ctx) async {
      if (newTitle != null) {
        await ctx.set(uri, NS.schemaName, newTitle);
      }
      if (newBody != null) {
        await ctx.set(uri, NS.schemaText, newBody);
      }
      await ctx.set(uri, NS.schemaDateModified, now);
    });

    // Re-read to get the current state for the card.
    final updated = await context.knowledge.getEntity(uri);
    final name = _tripleValue(updated, NS.schemaName) ?? 'Untitled';
    final text = _tripleValue(updated, NS.schemaText) ?? '';
    final dateCreated = _tripleValue(updated, NS.schemaDateCreated) ?? now;

    return ToolResult.compound([
      ToolResult.text('Note updated: $uri'),
      ToolResult.widget(
        library: 'kabuk:notes',
        widget: 'NoteCard',
        bindings: {'name': name, 'text': text, 'dateCreated': dateCreated},
      ),
    ]);
  }

  Future<ToolResult> _deleteNote(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final uri = args['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      return const ToolResult.error('Note URI is required.');
    }

    final entity = await context.knowledge.getEntity(uri);
    if (entity.isEmpty) {
      return ToolResult.error('Note not found: $uri');
    }

    await context.knowledge.mutate((ctx) async {
      await ctx.remove(subject: uri);
    });

    return ToolResult.text('Note deleted: $uri');
  }

  Future<ToolResult> _getNote(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final uri = args['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      return const ToolResult.error('Note URI is required.');
    }

    final entity = await context.knowledge.getEntity(uri);
    if (entity.isEmpty) {
      return ToolResult.error('Note not found: $uri');
    }

    final name = entity
        .where((t) => t.predicate == NS.schemaName)
        .firstOrNull
        ?.objectValue;
    final body = entity
        .where((t) => t.predicate == NS.schemaText)
        .firstOrNull
        ?.objectValue;
    final dateCreated = entity
        .where((t) => t.predicate == NS.schemaDateCreated)
        .firstOrNull
        ?.objectValue;
    final dateModified = entity
        .where((t) => t.predicate == NS.schemaDateModified)
        .firstOrNull
        ?.objectValue;
    final tags = entity
        .where((t) => t.predicate == NS.kabukTag)
        .map((t) => t.objectValue)
        .toList();

    final tagLine = tags.isEmpty ? '' : '\nTags: ${tags.join(', ')}';

    return ToolResult.compound([
      ToolResult.text('''
# ${name ?? 'Untitled'}
Created: ${dateCreated ?? 'unknown'}
Modified: ${dateModified ?? 'unknown'}$tagLine

$body
'''),
      ToolResult.widget(
        library: 'kabuk:notes',
        widget: 'NoteDetail',
        bindings: {
          'name': name ?? 'Untitled',
          'text': body ?? '',
          'dateCreated': dateCreated ?? '',
        },
      ),
    ]);
  }

  /// Extract the first object value for [predicate] from [triples].
  String? _tripleValue(List<Triple> triples, String predicate) =>
      triples.where((t) => t.predicate == predicate).firstOrNull?.objectValue;
}
