/// System agent — handles system-level queries and device information.
///
/// Responds to questions about the app, its capabilities, settings,
/// and provides general help. This is the fallback agent when no
/// domain-specific agent matches.
library;

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/memory.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/agents/privacy_filter.dart';
import 'package:kabuk/agents/tiered_llm.dart';
import 'package:kabuk/config/constants.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart';

/// Agent for system queries, help, and settings.
class SystemAgent extends BaseAgent with AgentMemoryMixin {
  @override
  String get name => 'system';

  @override
  String get description =>
      'Handles system queries, help, settings, and general conversation.';

  @override
  String get systemPrompt =>
      '''
You are the System agent for Kabuk — the go-to agent for understanding and
navigating the Kabuk OS shell.

Your Responsibilities:
• Answer questions about what Kabuk is and what it can do
• Explain how features work (knowledge store, agents, feeds, identity, etc.)
• Help users get started and discover capabilities they haven't tried
• Handle general conversation, greetings, and questions that don't fit other agents
• Provide system information (version, registered agents, data stats)
• Search the user's knowledge store when they ask general questions

Key Facts to Share When Relevant:
• Kabuk ${AppConstants.appVersion} is an agent-centric personal OS that replaces
traditional app grids with a chat-first interface
• All data is private, encrypted, stored locally — never leaves the device
without consent
• Everything works offline; cloud/network features are optional additions
• Data is stored as RDF triples using Schema.org vocabulary — this means all
data types (notes, events, contacts, articles, files) live in one unified store
• Users can manage notes, calendar events, contacts, RSS/Reddit feeds, files,
and their Nostr identity — all through chat
• The knowledge store can be searched across all data types at once

Personality:
• You ARE Kabuk when talking to the user — speak in first person ("I can help
you with...", "I store your data locally...")
• Be warm, approachable, and genuinely helpful
• When a user asks what you can do, give concrete examples rather than abstract descriptions
• If a user seems new, proactively suggest things to try
''';

  @override
  List<AgentTool> get tools => [
    AgentTool(
      name: 'get_system_info',
      description: 'Get information about the Kabuk system.',
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
      },
      execute: _getSystemInfo,
    ),
    AgentTool(
      name: 'search_knowledge',
      description: 'Search the knowledge store for information.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'The search query.'},
        },
        'required': ['query'],
      },
      execute: _searchKnowledge,
    ),
    AgentTool(
      name: 'create_note',
      description: 'Create a quick note in the knowledge store.',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'Note title.'},
          'content': {
            'type': 'string',
            'description': 'Note content/body text.',
          },
        },
        'required': ['title', 'content'],
      },
      execute: _createNote,
    ),
    AgentTool(
      name: 'get_privacy_status',
      description:
          'Get the current privacy filter settings, including '
          'the privacy level, whether the filter is enabled, '
          'and which LLM tiers are available.',
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
      },
      execute: _getPrivacyStatus,
    ),
    AgentTool(
      name: 'set_privacy_level',
      description:
          'Change the privacy level for remote LLM requests. '
          'Levels: none, light, standard, maximum.',
      parameters: {
        'type': 'object',
        'properties': {
          'level': {
            'type': 'string',
            'description': 'Privacy level: none, light, standard, or maximum.',
            'enum': ['none', 'light', 'standard', 'maximum'],
          },
        },
        'required': ['level'],
      },
      execute: _setPrivacyLevel,
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
      return const AgentResponse.text('How can I help you?');
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
      temperature: 0.7,
    );
  }

  Future<ToolResult> _getSystemInfo(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final agentList = context.runtime.agents
        .map((a) => '  - ${a.name}: ${a.description}')
        .join('\n');

    return ToolResult.text('''
**Kabuk ${AppConstants.appVersion}**
Agent-centric personal OS shell.

Registered agents:
$agentList

Features:
- Chat with AI agents
- Knowledge store (RDF triples)
- Dynamic UI via Remote Flutter Widgets
- Offline-first, privacy-focused
''');
  }

  Future<ToolResult> _searchKnowledge(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final query = args['query'] as String? ?? '';
    if (query.isEmpty) {
      return const ToolResult.error('Search query cannot be empty.');
    }

    final results = await context.knowledge.search(query);
    if (results.isEmpty) {
      return ToolResult.text('No results found for "$query".');
    }

    final lines = results
        .take(10)
        .map((t) {
          return '- **${t.predicate}**: ${t.objectValue}';
        })
        .join('\n');

    return ToolResult.text('Found ${results.length} results:\n$lines');
  }

  Future<ToolResult> _createNote(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final title = args['title'] as String? ?? 'Untitled';
    final content = args['content'] as String? ?? '';

    await context.knowledge.mutate((ctx) async {
      final uri = ctx.create('Note');
      await ctx.set(uri, NS.rdfType, NS.schemaNote, objectType: ObjectType.uri);
      await ctx.set(uri, NS.schemaName, title);
      await ctx.set(uri, NS.schemaText, content);
      final now = DateTime.now().toIso8601String();
      await ctx.set(uri, NS.schemaDateCreated, now);
      await ctx.set(uri, NS.schemaDateModified, now);
    });

    return ToolResult.text('Note "$title" created.');
  }

  Future<ToolResult> _getPrivacyStatus(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final privacyLevel = context.privacyLevel;
    final llm = context.llm;

    final tierInfo = StringBuffer();
    if (llm is TieredLlmService) {
      final availability = llm.tierAvailability;
      tierInfo.writeln('\n**LLM Tiers:**');
      for (final entry in availability.entries) {
        final status = entry.value ? '✅ Available' : '❌ Not configured';
        final desc = switch (entry.key) {
          LlmTier.base => 'Base (on-device, always available)',
          LlmTier.standard => 'Standard (medium model)',
          LlmTier.advanced => 'Advanced (cloud API)',
        };
        tierInfo.writeln('  - $desc: $status');
      }
      tierInfo.writeln(
        '\n**Privacy filter:** '
        '${llm.config.enablePrivacyFilter ? "Enabled ✅" : "Disabled ❌"}',
      );
    } else {
      tierInfo.writeln('\n*Tiered LLM not active — using single LLM service.*');
    }

    final levelDesc = switch (privacyLevel) {
      PrivacyLevel.none => 'None — No filtering (local only).',
      PrivacyLevel.light => 'Light — Strips obvious PII (emails, phones).',
      PrivacyLevel.standard =>
        'Standard — Replaces all PII with placeholders. (Recommended)',
      PrivacyLevel.maximum =>
        'Maximum — Aggressively strips all identifying info.',
    };

    return ToolResult.text('''
**Privacy Status**

Privacy level: **$levelDesc**
$tierInfo
Your data is encrypted at rest and never leaves the device without your consent.
When using cloud AI services, the on-device model automatically removes personal
information from your messages before sending them.
''');
  }

  Future<ToolResult> _setPrivacyLevel(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final levelName = args['level'] as String? ?? 'standard';
    final level = PrivacyLevel.values
        .where((l) => l.name == levelName)
        .firstOrNull;

    if (level == null) {
      return ToolResult.error(
        'Unknown privacy level "$levelName". Use: none, light, standard, or maximum.',
      );
    }

    return ToolResult.text(
      'I can\'t change settings directly. '
      'To change your privacy level to **${level.name}**, go to **Settings > Privacy**.\n\n'
      '${switch (level) {
        PrivacyLevel.none => "\u26a0\ufe0f Warning: This level sends personal information to cloud APIs without filtering.",
        PrivacyLevel.light => "This level filters basic PII like emails and phone numbers.",
        PrivacyLevel.standard => "This level replaces all personal information with safe placeholders before sending to cloud APIs.",
        PrivacyLevel.maximum => "This level aggressively strips all potentially identifying information.",
      }}',
    );
  }
}
