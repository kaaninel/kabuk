/// Router agent — dispatches user messages to domain-specific agents.
///
/// The router acts as the front door for all user interactions. It
/// examines the user's message, determines which domain agent is best
/// suited to handle it, and delegates accordingly. If no specialized
/// agent matches, the router handles the message itself.
library;

import 'dart:developer' as dev;

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/agents/prompts.dart';
import 'package:kabuk/agents/tiered_llm.dart';

/// The router agent that dispatches messages to domain agents.
///
/// Registration order matters for fallback: agents registered later
/// take priority when multiple agents match a query. The router
/// always resolves to itself as last resort.
class RouterAgent extends BaseAgent {
  @override
  String get name => 'router';

  @override
  String get description => 'Routes user messages to the best domain agent.';

  @override
  String get systemPrompt =>
      '''
${KabukPrompts.kabukIdentity}

You are the Router — the front door for all user interactions in Kabuk. Your
primary job is to understand the user's intent and either:
1. Route to the best specialized domain agent using the "route_to_agent" tool, OR
2. Respond directly when the request is general conversation, a simple question,
or doesn't match any domain agent.

Routing Guidelines:
• Match the user's intent to the most relevant agent. Look at the semantic meaning,
not just keywords.
• If the user mentions notes, writing things down, or saving text → route to "notes"
• If the user mentions events, calendar, schedule, meetings, reminders → route to "calendar"
• If the user mentions people, contacts, phone numbers, emails → route to "contacts"
• If the user mentions RSS, feeds, subreddits, articles, news → route to "feeds"
• If the user wants to discover, explore, search Nostr, find trending topics, hashtags,
or subscribe to topics → route to "discover"
• If the user mentions DMs, direct messages, chat, conversation, messaging, group chats,
channels, or media sharing → route to "messaging"
• If the user mentions files, photos, documents, media → route to "files"
• If the user wants to find or search across all their data → route to "search"
• If the user mentions Nostr, identity, public key, relays, social → route to "identity"
• If the user mentions Usenet indexers, providers, NNTP servers, or NZB configuration → route to "feeds"
• If the user wants to search Usenet, stream content, or play NZB files → route to "discover"
• If the request is about Kabuk itself, settings, help, or general chat → route to "system"
• For greetings, casual conversation, general knowledge questions, or anything that
doesn't fit a domain agent, respond directly yourself.

When responding directly:
• You ARE Kabuk. Speak in first person as the user's personal AI assistant.
• Be warm, helpful, and concise.
• If the user seems lost, briefly explain what you can help with.
• You can answer general knowledge questions, have casual conversation, and help
the user understand what Kabuk can do.

Available agents and their capabilities will be provided below. Use the
"route_to_agent" tool to delegate to a specialized agent with the agent name
and a brief reason for choosing it.
''';

  @override
  List<AgentTool> get tools => [
    AgentTool(
      name: 'route_to_agent',
      description: 'Route the user message to a specialized domain agent.',
      parameters: {
        'type': 'object',
        'properties': {
          'agent_name': {
            'type': 'string',
            'description': 'The name of the agent to route to.',
          },
          'reason': {
            'type': 'string',
            'description': 'Brief reason for choosing this agent.',
          },
        },
        'required': ['agent_name'],
      },
      execute: _routeToAgent,
    ),
    AgentTool(
      name: 'list_agents',
      description: 'List all available agents and their capabilities.',
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
      },
      execute: _listAgents,
    ),
  ];

  @override
  Set<AgentCapability> get requiredCapabilities => {
    AgentCapability.llmCall,
    AgentCapability.knowledgeRead,
    AgentCapability.agentInvoke,
  };

  // ---------------------------------------------------------------------------
  // Keyword-based intent patterns for pre-LLM routing
  // ---------------------------------------------------------------------------

  /// Maps regex patterns to agent names for fast intent matching.
  ///
  /// These allow common requests to be routed correctly even when no LLM
  /// is configured, or when the LLM is too weak to route reliably.
  static final _intentPatterns = <(RegExp, String)>[
    // Feed / RSS / Reddit intents.
    (
      RegExp(
        r'(subscribe|follow|add|unsubscribe|remove)\b.*\b(r/\w+|subreddit|reddit|rss|feed|atom)',
        caseSensitive: false,
      ),
      'feeds',
    ),
    (RegExp(r'\br/\w+', caseSensitive: false), 'feeds'),
    (
      RegExp(r'(refresh|fetch|update)\b.*\bfeed', caseSensitive: false),
      'feeds',
    ),
    (
      RegExp(
        r'(list|show|my)\b.*\b(feed|subscription|article)',
        caseSensitive: false,
      ),
      'feeds',
    ),
    // Note intents.
    (
      RegExp(
        r'(create|write|save|new|edit|delete)\b.*\bnote',
        caseSensitive: false,
      ),
      'notes',
    ),
    (
      RegExp(r'(list|show|search|find)\b.*\bnotes?', caseSensitive: false),
      'notes',
    ),
    // Web search / page-read intents.
    (
      RegExp(
        r'(search|look up|find|google|browse|check)\b.*\b(web|online|internet|site|website|page|article|news|url)',
        caseSensitive: false,
      ),
      'web',
    ),
    (
      RegExp(
        r'(what|who|when|where|how|why)\b.*\b(on the web|online|in the news|right now|today)',
        caseSensitive: false,
      ),
      'web',
    ),
    (
      RegExp(
        r'(read|summarize|open|fetch)\b.*\b(url|page|article|link)',
        caseSensitive: false,
      ),
      'web',
    ),
    // Calendar intents.
    (
      RegExp(
        r'(create|schedule|add|cancel|delete)\b.*\b(event|meeting|appointment|reminder|calendar)',
        caseSensitive: false,
      ),
      'calendar',
    ),
    (
      RegExp(
        r'(list|show|upcoming|today|tomorrow|agenda)',
        caseSensitive: false,
      ),
      'calendar',
    ),
    // Contact intents.
    (
      RegExp(
        r'(add|create|find|search|list|show)\b.*\b(contact|person|people)',
        caseSensitive: false,
      ),
      'contacts',
    ),
    // Search intents.
    (
      RegExp(
        r'(search|find|look\s*up)\b.*\b(knowledge|store|everything|all)',
        caseSensitive: false,
      ),
      'search',
    ),
    // Discovery / content discovery intents.
    (
      RegExp(
        r'(discover|trending|popular|explore|what.s\s*(new|popular|trending))',
        caseSensitive: false,
      ),
      'discover',
    ),
    (
      RegExp(
        r'(search|find)\b.*\b(nostr|hashtag|topic|content|posts)',
        caseSensitive: false,
      ),
      'discover',
    ),
    (
      RegExp(
        r'(subscribe|follow)\b.*\b(topic|hashtag|#\w+)',
        caseSensitive: false,
      ),
      'discover',
    ),
    (RegExp(r'#\w+', caseSensitive: false), 'discover'),
    (
      RegExp(r'(saved?\s*search|save\s*this\s*search)', caseSensitive: false),
      'discover',
    ),
    // Identity intents.
    (
      RegExp(
        r'(identity|keypair|key\s*pair|public\s*key|nostr|npub)',
        caseSensitive: false,
      ),
      'identity',
    ),
    // Usenet intents — route to feeds for indexer/provider management.
    (
      RegExp(
        r'(add|remove|configure|setup|list|show)\b.*\b(indexer|provider|usenet|nzb|nntp|news\s*server)',
        caseSensitive: false,
      ),
      'feeds',
    ),
    // Usenet intents — route to discover for search/stream.
    (
      RegExp(
        r'(search|find|stream|watch|play|download)\b.*\b(usenet|nzb|usenet\s*content)',
        caseSensitive: false,
      ),
      'discover',
    ),
    (RegExp(r'\bnzb:', caseSensitive: false), 'discover'),
    (RegExp(r'\busenet:', caseSensitive: false), 'discover'),
    // File intents.
    (
      RegExp(
        r'(file|photo|image|video|media|gallery|camera)',
        caseSensitive: false,
      ),
      'files',
    ),
  ];

  /// Attempts to match user input against keyword patterns.
  ///
  /// Returns the agent name if a strong match is found, null otherwise.
  String? _matchIntent(String content) {
    for (final (pattern, agentName) in _intentPatterns) {
      if (pattern.hasMatch(content)) {
        // Only route if the agent is actually registered.
        return agentName;
      }
    }
    return null;
  }

  @override
  Future<AgentResponse> process(
    AgentMessage message,
    AgentContext context,
  ) async {
    // For user messages, try to route or answer directly.
    final content = switch (message) {
      UserMessage(:final content) => content,
      SystemMessage(:final content) => content,
      _ => '',
    };

    if (content.isEmpty) {
      return const AgentResponse.text('I didn\'t receive a message.');
    }

    // ---- Fast path: keyword-based intent matching ----
    // This handles common, unambiguous requests without needing the LLM.
    final matchedAgent = _matchIntent(content);
    if (matchedAgent != null) {
      final agent = context.runtime.getAgent(matchedAgent);
      if (agent != null) {
        try {
          final result = await agent.process(message, context);
          return result.withAgentName(agent.name);
        } on Object catch (e, st) {
          dev.log(
            'Agent ${agent.name} failed on fast-path dispatch',
            error: e,
            stackTrace: st,
            name: 'RouterAgent',
          );
          return AgentResponse.error(
            'The ${agent.name} agent encountered an error. Please try again.',
          );
        }
      }
    }

    // ---- LLM path: ask the model to decide ----
    // Build the list of available agents for the LLM.
    final availableAgents = context.runtime.agents
        .where((a) => a.name != 'router')
        .map((a) => '- ${a.name}: ${a.description}')
        .join('\n');

    final agentContext = availableAgents.isEmpty
        ? 'No specialized agents are registered yet.'
        : 'Available agents:\n$availableAgents';

    // Build conversation messages from history when available.
    final llmMessages = <LlmMessage>[
      if (message case UserMessage(:final history?)) ...history,
      LlmMessage.user(content),
    ];

    // Use the base-tier LLM for routing decisions.
    // The router only needs to classify intent — a small on-device
    // model handles this well without needing a remote API call.
    final fullPrompt = buildSystemPrompt(includeIdentity: false);
    try {
      final response = await context.llm.complete(
        LlmRequest(
          systemPrompt: '$fullPrompt\n\n$agentContext',
          messages: llmMessages,
          tools: tools.map((t) => t.toFunctionSchema()).toList(),
          temperature: 0.3,
          model: 'tier:${LlmTier.base.name}',
        ),
      );

      return switch (response) {
        TextLlmResponse(:final content) => _handleTextFallback(
          content,
          message,
          context,
        ),
        ToolCallsLlmResponse(:final calls) => _handleToolCalls(
          calls,
          message,
          context,
        ),
        ErrorLlmResponse(:final message) => AgentResponse.error(message),
      };
    } on Object catch (e, st) {
      dev.log(
        'LLM routing failed',
        error: e,
        stackTrace: st,
        name: 'RouterAgent',
      );
      return const AgentResponse.error(
        'I encountered an error processing your request. Please try again.',
      );
    }
  }

  /// Handles the case where the LLM returns text instead of calling
  /// `route_to_agent`. Attempts keyword-based re-matching on the original
  /// user content, then falls back to the system agent, and only returns
  /// raw LLM text as a last resort.
  Future<AgentResponse> _handleTextFallback(
    String llmText,
    AgentMessage originalMessage,
    AgentContext context,
  ) async {
    // Extract user content for keyword re-matching.
    final userContent = switch (originalMessage) {
      UserMessage(:final content) => content,
      SystemMessage(:final content) => content,
      _ => '',
    };

    // Try keyword-based re-matching on the original user content.
    if (userContent.isNotEmpty) {
      final matched = _matchIntent(userContent);
      if (matched != null) {
        final agent = context.runtime.getAgent(matched);
        if (agent != null) {
          try {
            final result = await agent.process(originalMessage, context);
            return result.withAgentName(agent.name);
          } on Object catch (e, st) {
            dev.log(
              'Agent ${agent.name} failed on text-fallback dispatch',
              error: e,
              stackTrace: st,
              name: 'RouterAgent',
            );
          }
        }
      }
    }

    // Fall back to the system agent as a catch-all — it has
    // search_knowledge, create_note, and general capabilities.
    final systemAgent = context.runtime.getAgent('system');
    if (systemAgent != null) {
      try {
        final systemResponse = await systemAgent.process(
          originalMessage,
          context,
        );
        // Only use system agent response if it's not an error.
        if (systemResponse is! ErrorAgentResponse) {
          return systemResponse.withAgentName(systemAgent.name);
        }
      } on Object catch (e, st) {
        dev.log(
          'System agent fallback failed',
          error: e,
          stackTrace: st,
          name: 'RouterAgent',
        );
      }
    }

    // Last resort: return the LLM's direct text response.
    return AgentResponse.text(llmText);
  }

  Future<AgentResponse> _handleToolCalls(
    List<LlmToolCall> calls,
    AgentMessage originalMessage,
    AgentContext context,
  ) async {
    for (final call in calls) {
      if (call.name == 'route_to_agent') {
        final agentName = call.arguments['agent_name'] as String? ?? '';
        final agent = context.runtime.getAgent(agentName);
        if (agent != null) {
          try {
            final result = await agent.process(originalMessage, context);
            return result.withAgentName(agent.name);
          } on Object catch (e, st) {
            dev.log(
              'Agent ${agent.name} failed on tool-call dispatch',
              error: e,
              stackTrace: st,
              name: 'RouterAgent',
            );
            return AgentResponse.error(
              'The ${agent.name} agent encountered an error. Please try again.',
            );
          }
        }
        return AgentResponse.error('Agent "$agentName" not found.');
      }
      if (call.name == 'list_agents') {
        final result = await _listAgents({}, context);
        return switch (result) {
          TextToolResult(:final content) => AgentResponse.text(content),
          _ => const AgentResponse.text('No agents available.'),
        };
      }
    }
    return const AgentResponse.text('I\'m not sure how to help with that.');
  }

  Future<ToolResult> _routeToAgent(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final agentName = args['agent_name'] as String? ?? '';
    if (context.runtime.getAgent(agentName) == null) {
      return ToolResult.error('Agent "$agentName" not found.');
    }
    return ToolResult.text('Routing to $agentName');
  }

  Future<ToolResult> _listAgents(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final agents = context.runtime.agents;
    if (agents.isEmpty) {
      return const ToolResult.text('No agents registered.');
    }
    final lines = agents
        .map((a) => '• **${a.name}**: ${a.description}')
        .join('\n');
    return ToolResult.text('Available agents:\n$lines');
  }
}
