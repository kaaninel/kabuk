/// Contact agent — manages contact entities in the knowledge store.
///
/// Provides tools for creating, reading, updating, searching, and
/// deleting contacts. Contacts are stored as `schema:Person` entities
/// with Schema.org predicates (name, email, telephone, etc.).
library;

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/memory.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart';

/// Agent for managing contact information.
class ContactAgent extends BaseAgent with AgentMemoryMixin {
  @override
  String get name => 'contacts';

  @override
  String get description =>
      'Manages contacts — create, search, view, update, and delete.';

  @override
  String get systemPrompt => '''
You are the Contacts agent for Kabuk. You manage the user's contacts, stored
as schema:Person entities in the knowledge store.

Capabilities:
• Create contacts with name, email, phone, and notes/description
• List all contacts alphabetically
• Search contacts by name, email, phone, or any detail
• View complete contact details
• Update any contact field
• Delete contacts permanently

Usage Guidelines:
• When creating a contact, at minimum a name is required. Encourage the user
to add email or phone if they have it.
• When listing contacts, show name and one key detail (email or phone)
• When the user mentions a person by name, search for them first before
asking for more details
• After any modification, confirm what changed
• If multiple contacts match a search, list them and ask which one the user means
• Be conversational — "Added John Smith to your contacts" is better than
"Contact created successfully"
''';

  @override
  List<AgentTool> get tools => [
    AgentTool(
      name: 'create_contact',
      description: 'Create a new contact in the knowledge store.',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Full name of the contact.',
          },
          'givenName': {'type': 'string', 'description': 'First/given name.'},
          'familyName': {'type': 'string', 'description': 'Last/family name.'},
          'email': {'type': 'string', 'description': 'Email address.'},
          'telephone': {'type': 'string', 'description': 'Phone number.'},
          'description': {
            'type': 'string',
            'description': 'Notes about the contact.',
          },
        },
        'required': ['name'],
      },
      execute: _createContact,
    ),
    AgentTool(
      name: 'list_contacts',
      description: 'List all contacts.',
      parameters: {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description': 'Maximum contacts to return (default 20).',
          },
        },
      },
      execute: _listContacts,
    ),
    AgentTool(
      name: 'search_contacts',
      description: 'Search contacts by keyword.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Search term to match against contact details.',
          },
        },
        'required': ['query'],
      },
      execute: _searchContacts,
    ),
    AgentTool(
      name: 'get_contact',
      description: 'Get full details of a contact.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {
            'type': 'string',
            'description': 'The entity URI of the contact.',
          },
        },
        'required': ['uri'],
      },
      execute: _getContact,
    ),
    AgentTool(
      name: 'update_contact',
      description: 'Update an existing contact.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {
            'type': 'string',
            'description': 'The entity URI of the contact to update.',
          },
          'name': {'type': 'string', 'description': 'New full name.'},
          'email': {'type': 'string', 'description': 'New email.'},
          'telephone': {'type': 'string', 'description': 'New phone.'},
          'description': {'type': 'string', 'description': 'New notes.'},
        },
        'required': ['uri'],
      },
      execute: _updateContact,
    ),
    AgentTool(
      name: 'delete_contact',
      description: 'Delete a contact.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {
            'type': 'string',
            'description': 'The entity URI of the contact to delete.',
          },
        },
        'required': ['uri'],
      },
      execute: _deleteContact,
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
        'What would you like to do with your contacts?',
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

  Future<ToolResult> _createContact(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final fullName = args['name'] as String? ?? 'Unknown';
    final givenName = args['givenName'] as String?;
    final familyName = args['familyName'] as String?;
    final email = args['email'] as String?;
    final telephone = args['telephone'] as String?;
    final description = args['description'] as String?;

    late final String entityUri;

    await context.knowledge.mutate((ctx) async {
      entityUri = ctx.create('Person');
      await ctx.set(entityUri, NS.rdfType, NS.schemaPerson);
      await ctx.set(entityUri, NS.schemaName, fullName);
      await ctx.set(
        entityUri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );

      if (givenName != null) {
        await ctx.set(entityUri, NS.schemaGivenName, givenName);
      }
      if (familyName != null) {
        await ctx.set(entityUri, NS.schemaFamilyName, familyName);
      }
      if (email != null) {
        await ctx.set(entityUri, NS.schemaEmail, email);
      }
      if (telephone != null) {
        await ctx.set(entityUri, NS.schemaTelephone, telephone);
      }
      if (description != null) {
        await ctx.set(entityUri, NS.schemaDescription, description);
      }
    });

    return ToolResult.compound([
      ToolResult.text('Created contact "$fullName"\nURI: $entityUri'),
      ToolResult.widget(
        library: 'kabuk:contacts',
        widget: 'ContactCard',
        bindings: {
          'name': fullName,
          'email': email ?? '',
          'initial': fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
        },
      ),
    ]);
  }

  Future<ToolResult> _listContacts(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final limit = (args['limit'] as int?) ?? 20;

    final triples = await context.knowledge
        .query()
        .predicate(NS.rdfType)
        .object(NS.schemaPerson)
        .limit(limit)
        .execute();

    if (triples.isEmpty) {
      return const ToolResult.text('No contacts found.');
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
      final email = entity
          .where((t) => t.predicate == NS.schemaEmail)
          .firstOrNull
          ?.objectValue;
      final phone = entity
          .where((t) => t.predicate == NS.schemaTelephone)
          .firstOrNull
          ?.objectValue;

      final details = [?email, ?phone].join(' · ');

      lines.add(
        '- **${name ?? 'Unknown'}**${details.isNotEmpty ? ' ($details)' : ''}\n'
        '  URI: `${triple.subject}`',
      );
    }

    return ToolResult.text(
      'Found ${triples.length} contact(s):\n${lines.join('\n')}',
    );
  }

  Future<ToolResult> _searchContacts(
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
      final isPerson = entity.any(
        (t) => t.predicate == NS.rdfType && t.objectValue == NS.schemaPerson,
      );
      if (!isPerson) continue;

      final name = entity
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue;
      lines.add('- **${name ?? 'Unknown'}** — `$subject`');
    }

    if (lines.isEmpty) {
      return ToolResult.text('No contacts matching "$query".');
    }

    return ToolResult.text(
      'Found ${lines.length} contact(s):\n${lines.join('\n')}',
    );
  }

  Future<ToolResult> _getContact(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final uri = args['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      return const ToolResult.error('Contact URI is required.');
    }

    final entity = await context.knowledge.getEntity(uri);
    if (entity.isEmpty) {
      return ToolResult.error('Contact not found: $uri');
    }

    String? field(String predicate) =>
        entity.where((t) => t.predicate == predicate).firstOrNull?.objectValue;

    final name = field(NS.schemaName) ?? 'Unknown';
    final given = field(NS.schemaGivenName);
    final family = field(NS.schemaFamilyName);
    final email = field(NS.schemaEmail);
    final phone = field(NS.schemaTelephone);
    final desc = field(NS.schemaDescription);
    final created = field(NS.schemaDateCreated);

    final parts = <String>[
      '# $name',
      if (given != null || family != null)
        'Name: ${[given, family].nonNulls.join(' ')}',
      if (email != null) 'Email: $email',
      if (phone != null) 'Phone: $phone',
      if (desc != null) 'Notes: $desc',
      if (created != null) 'Added: $created',
    ];

    return ToolResult.compound([
      ToolResult.text(parts.join('\n')),
      ToolResult.widget(
        library: 'kabuk:contacts',
        widget: 'ContactCard',
        bindings: {
          'name': name,
          'email': email ?? '',
          'initial': name.isNotEmpty ? name[0].toUpperCase() : '?',
        },
      ),
    ]);
  }

  Future<ToolResult> _updateContact(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final uri = args['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      return const ToolResult.error('Contact URI is required.');
    }

    final entity = await context.knowledge.getEntity(uri);
    if (entity.isEmpty) {
      return ToolResult.error('Contact not found: $uri');
    }

    final fields = <String, String>{
      if (args['name'] case final String v) NS.schemaName: v,
      if (args['email'] case final String v) NS.schemaEmail: v,
      if (args['telephone'] case final String v) NS.schemaTelephone: v,
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
    final name = _tripleValue(updated, NS.schemaName) ?? 'Unknown';
    final email = _tripleValue(updated, NS.schemaEmail) ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return ToolResult.compound([
      ToolResult.text('Updated ${fields.length} field(s) on contact: $uri'),
      ToolResult.widget(
        library: 'kabuk:contacts',
        widget: 'ContactCard',
        bindings: {'name': name, 'email': email, 'initial': initial},
      ),
    ]);
  }

  Future<ToolResult> _deleteContact(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final uri = args['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      return const ToolResult.error('Contact URI is required.');
    }

    final entity = await context.knowledge.getEntity(uri);
    if (entity.isEmpty) {
      return ToolResult.error('Contact not found: $uri');
    }

    await context.knowledge.mutate((ctx) async {
      await ctx.remove(subject: uri);
    });

    return ToolResult.text('Contact deleted: $uri');
  }

  /// Extract the first object value for [predicate] from [triples].
  String? _tripleValue(List<Triple> triples, String predicate) =>
      triples.where((t) => t.predicate == predicate).firstOrNull?.objectValue;
}
