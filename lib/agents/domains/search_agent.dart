/// Search agent — universal search across all entity types.
///
/// Provides tools for full-text search, type-filtered search, listing
/// recently modified entities, and counting entities by type. Search
/// results include entity URI, type, name, and a preview snippet.
library;

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/memory.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart' show Triple;

/// Agent specialized in universal search across the knowledge store.
///
/// Handles full-text search, type-filtered search, recent-entity listing,
/// and entity counting. Uses [AgentMemoryMixin] to remember frequent
/// search patterns and preferred result formats.
class SearchAgent extends BaseAgent with AgentMemoryMixin {
  @override
  String get name => 'search';

  @override
  String get description =>
      'Universal search across all entity types in the knowledge store.';

  @override
  String get systemPrompt => '''
You are the Search agent for Kabuk. You provide universal search across the
user's entire knowledge store — notes, events, contacts, articles, files,
and any other entity type.

Capabilities:
• Full-text search across all entity types simultaneously
• Type-filtered search (e.g., search only notes, only contacts)
• List recently created or modified entities
• Count entities by type for an overview of stored data

Supported entity types for filtering:
• Note — notes and documents
• Event — calendar events
• Person — contacts
• Article — feed articles
• MediaObject — files and media
• DataFeed — feed subscriptions

Usage Guidelines:
• Default to universal search unless the user specifies a type
• Present results clearly: show the entity type icon/label, name, and a
brief preview of content
• Group results by type when multiple types appear
• If no results found, suggest broadening the search or checking spelling
• For "show me everything" or "what do I have" requests, use the count tool
to give an overview, then offer to drill down
• Keep result summaries brief — the user can ask for details on specific items
''';

  @override
  List<AgentTool> get tools => [
    AgentTool(
      name: 'search',
      description:
          'Universal full-text search across all entity types in the '
          'knowledge store.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The search query string.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of results to return (default 10).',
          },
        },
        'required': ['query'],
      },
      execute: _search,
    ),
    AgentTool(
      name: 'search_by_type',
      description: 'Search entities filtered by a specific rdf:type.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The search query string.',
          },
          'entity_type': {
            'type': 'string',
            'description':
                'The RDF type URI to filter by '
                '(e.g. "https://schema.org/Note").',
          },
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of results to return (default 10).',
          },
        },
        'required': ['query', 'entity_type'],
      },
      execute: _searchByType,
    ),
    AgentTool(
      name: 'recent',
      description:
          'List recently created or modified entities across all types.',
      parameters: {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description':
                'Maximum number of recent entities to return (default 10).',
          },
        },
      },
      execute: _recent,
    ),
    AgentTool(
      name: 'count_entities',
      description: 'Count entities by their rdf:type.',
      parameters: {
        'type': 'object',
        'properties': {
          'entity_type': {
            'type': 'string',
            'description':
                'The RDF type URI to count. If omitted, counts all '
                'typed entities grouped by type.',
          },
        },
      },
      execute: _countEntities,
    ),
  ];

  @override
  Set<AgentCapability> get requiredCapabilities => {
    AgentCapability.llmCall,
    AgentCapability.knowledgeRead,
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
      return const AgentResponse.text('What would you like to search for?');
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

  /// Universal full-text search across all entities.
  Future<ToolResult> _search(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final query = args['query'] as String? ?? '';
    if (query.isEmpty) {
      return const ToolResult.error('Search query cannot be empty.');
    }
    final limit = (args['limit'] as int?) ?? 10;

    final results = await context.knowledge.search(query, limit: limit);

    if (results.isEmpty) {
      return ToolResult.text('No results found for "$query".');
    }

    // Deduplicate by subject URI and build result lines.
    final seen = <String>{};
    final uniqueSubjects = <String>[];

    for (final triple in results) {
      if (seen.add(triple.subject)) {
        uniqueSubjects.add(triple.subject);
      }
    }

    final entities = await context.knowledge.getEntities(uniqueSubjects);
    final lines = <String>[];

    for (final subject in uniqueSubjects) {
      final entity = entities[subject] ?? [];
      final summary = _summarizeEntity(subject, entity);
      lines.add(summary);
    }

    return ToolResult.text(
      'Found ${lines.length} result(s) for "$query":\n${lines.join('\n')}',
    );
  }

  /// Search filtered to a specific rdf:type.
  Future<ToolResult> _searchByType(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final query = args['query'] as String? ?? '';
    if (query.isEmpty) {
      return const ToolResult.error('Search query cannot be empty.');
    }
    final entityType = args['entity_type'] as String? ?? '';
    if (entityType.isEmpty) {
      return const ToolResult.error('Entity type is required.');
    }
    final limit = (args['limit'] as int?) ?? 10;

    final results = await context.knowledge.search(query, limit: limit * 3);

    if (results.isEmpty) {
      return ToolResult.text('No results found for "$query".');
    }

    // Filter to subjects that match the requested type.
    final seen = <String>{};
    final uniqueSubjects = <String>[];

    for (final triple in results) {
      if (seen.add(triple.subject)) {
        uniqueSubjects.add(triple.subject);
      }
    }

    final entities = await context.knowledge.getEntities(uniqueSubjects);
    final lines = <String>[];

    for (final subject in uniqueSubjects) {
      if (lines.length >= limit) break;

      final entity = entities[subject] ?? [];
      final isMatch = entity.any(
        (t) => t.predicate == NS.rdfType && t.objectValue == entityType,
      );
      if (!isMatch) continue;

      final summary = _summarizeEntity(subject, entity);
      lines.add(summary);
    }

    if (lines.isEmpty) {
      final typeName = entityType.split('/').last;
      return ToolResult.text('No $typeName entities found matching "$query".');
    }

    final typeName = entityType.split('/').last;
    return ToolResult.text(
      'Found ${lines.length} $typeName result(s) for "$query":\n'
      '${lines.join('\n')}',
    );
  }

  /// Lists recently created or modified entities.
  Future<ToolResult> _recent(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final limit = (args['limit'] as int?) ?? 10;

    // Query entities by dateModified, falling back to dateCreated.
    final modifiedTriples = await context.knowledge
        .query()
        .predicate(NS.schemaDateModified)
        .orderBy(NS.schemaDateModified, descending: true)
        .limit(limit)
        .execute();

    // If we don't have enough from dateModified, also check dateCreated.
    final createdTriples = await context.knowledge
        .query()
        .predicate(NS.schemaDateCreated)
        .orderBy(NS.schemaDateCreated, descending: true)
        .limit(limit)
        .execute();

    // Merge and deduplicate, preferring modified timestamps.
    final seen = <String>{};
    final allTriples = [...modifiedTriples, ...createdTriples];
    final uniqueSubjects = <String>[];

    for (final triple in allTriples) {
      if (seen.add(triple.subject) && uniqueSubjects.length < limit) {
        uniqueSubjects.add(triple.subject);
      }
    }

    final entities = await context.knowledge.getEntities(uniqueSubjects);
    final lines = <String>[];

    for (final subject in uniqueSubjects) {
      final entity = entities[subject] ?? [];
      final summary = _summarizeEntity(subject, entity);
      lines.add(summary);
    }

    if (lines.isEmpty) {
      return const ToolResult.text('No recent entities found.');
    }

    return ToolResult.text(
      'Recent entities (${lines.length}):\n${lines.join('\n')}',
    );
  }

  /// Counts entities by their rdf:type.
  Future<ToolResult> _countEntities(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final entityType = args['entity_type'] as String?;

    if (entityType != null && entityType.isNotEmpty) {
      // Count a specific type.
      final count = await context.knowledge
          .query()
          .predicate(NS.rdfType)
          .object(entityType)
          .count();

      final typeName = entityType.split('/').last;
      return ToolResult.text('$typeName entities: $count');
    }

    // Count all known types.
    final typeTriples = await context.knowledge
        .query()
        .predicate(NS.rdfType)
        .execute();

    final typeCounts = <String, int>{};
    for (final triple in typeTriples) {
      final type = triple.objectValue;
      typeCounts[type] = (typeCounts[type] ?? 0) + 1;
    }

    if (typeCounts.isEmpty) {
      return const ToolResult.text('No entities found in the knowledge store.');
    }

    // Sort by count descending.
    final sorted = typeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final lines = sorted.map((e) {
      final typeName = e.key.split('/').last;
      return '- **$typeName**: ${e.value}';
    });

    return ToolResult.text('Entity counts by type:\n${lines.join('\n')}');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Formats an entity as a summary line with URI, type, name, and preview.
  String _summarizeEntity(String uri, List<Triple> entity) {
    final rdfType = entity
        .where((t) => t.predicate == NS.rdfType)
        .firstOrNull
        ?.objectValue;
    final name = entity
        .where((t) => t.predicate == NS.schemaName)
        .firstOrNull
        ?.objectValue;
    final text = entity
        .where((t) => t.predicate == NS.schemaText)
        .firstOrNull
        ?.objectValue;
    final description = entity
        .where((t) => t.predicate == NS.schemaDescription)
        .firstOrNull
        ?.objectValue;

    final typeName = rdfType != null ? rdfType.split('/').last : 'Unknown';
    final displayName = name ?? 'Untitled';

    // Build a short preview from text or description.
    final previewSource = text ?? description ?? '';
    final preview = previewSource.length > 80
        ? '${previewSource.substring(0, 80)}...'
        : previewSource;
    final previewLine = preview.isNotEmpty ? '\n  Preview: $preview' : '';

    return '- **$displayName** [$typeName]\n'
        '  URI: `$uri`$previewLine';
  }
}
