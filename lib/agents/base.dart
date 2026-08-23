/// Base agent class and tool definitions.
///
/// All agents extend [BaseAgent] and declare their tools as [AgentTool]
/// objects. Agents are stateless — all persistent state lives in the
/// knowledge store. Each agent declares the capabilities it requires
/// and provides tools that the system can invoke.
library;

import 'dart:developer' as dev;

import 'package:kabuk/agents/channels.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/agents/observation.dart';
import 'package:kabuk/agents/prompts.dart';
import 'package:kabuk/agents/tiered_llm.dart';
import 'package:kabuk/plugins/channel.dart';
import 'package:kabuk/plugins/content_item.dart';

/// A tool that an agent can execute.
///
/// Each tool has a name, description, JSON Schema parameters,
/// and an execute function. Tools are the primary way agents
/// interact with the knowledge store and services.
class AgentTool {
  /// Creates an [AgentTool] with the given [name], [description],
  /// [parameters] JSON Schema, and [execute] function.
  const AgentTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });

  /// Machine-readable tool name (e.g., `'create_note'`).
  final String name;

  /// Human-readable description of what this tool does.
  final String description;

  /// JSON Schema describing the tool's parameters.
  final Map<String, dynamic> parameters;

  /// The function to execute when this tool is called.
  ///
  /// Receives the parsed arguments and the `AgentContext` for accessing
  /// the knowledge store and services.
  final Future<ToolResult> Function(
    Map<String, dynamic> args,
    AgentContext context,
  )
  execute;

  /// Converts this tool to JSON Schema format for LLM function calling.
  Map<String, dynamic> toFunctionSchema() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

/// The result of executing a tool.
///
/// Uses sealed classes so consumers can exhaustively match over
/// all possible result types: text, error, widget, raw widget,
/// mutation, or compound.
sealed class ToolResult {
  /// Creates a [ToolResult].
  const ToolResult();

  /// A plain text response.
  const factory ToolResult.text(String content) = TextToolResult;

  /// An error result.
  const factory ToolResult.error(String message) = ErrorToolResult;

  /// An RFW widget template to render, referencing a registered
  /// widget library and widget name.
  const factory ToolResult.widget({
    required String library,
    required String widget,
    Map<String, dynamic> bindings,
    Map<String, dynamic>? data,
  }) = WidgetToolResult;

  /// A raw RFW template string with inline data bindings.
  const factory ToolResult.rawWidget({
    required String source,
    required Map<String, dynamic> data,
  }) = RawWidgetToolResult;

  /// Knowledge store mutations — triples to add and/or remove.
  const factory ToolResult.mutation({
    List<Map<String, dynamic>> added,
    List<Map<String, dynamic>> removed,
  }) = MutationToolResult;

  /// Multiple results combined into one.
  const factory ToolResult.compound(List<ToolResult> results) =
      CompoundToolResult;

  /// An agent-populated channel: typed content items bound to a channel
  /// identity. The system draws the items using existing UI primitives
  /// (`contentCardFor` / `ViewerRouter`) — the agent never authors UI.
  const factory ToolResult.channel({
    required Channel channel,
    required List<ContentItem> items,
    String? summary,
  }) = ChannelToolResult;

  /// Serialize this result to JSON for LLM context or persistence.
  Map<String, dynamic> toJson();
}

/// A plain text tool result.
final class TextToolResult extends ToolResult {
  /// Creates a [TextToolResult] with the given [content].
  const TextToolResult(this.content);

  /// The text content.
  final String content;

  @override
  Map<String, dynamic> toJson() => {'type': 'text', 'content': content};
}

/// An error tool result.
final class ErrorToolResult extends ToolResult {
  /// Creates an [ErrorToolResult] with the given error [message].
  const ErrorToolResult(this.message);

  /// The error message.
  final String message;

  @override
  Map<String, dynamic> toJson() => {'type': 'error', 'message': message};
}

/// An RFW widget tool result referencing a registered widget.
final class WidgetToolResult extends ToolResult {
  /// Creates a [WidgetToolResult] referencing [library] and [widget]
  /// with optional [bindings] and [data].
  const WidgetToolResult({
    required this.library,
    required this.widget,
    this.bindings = const {},
    this.data,
  });

  /// The widget library namespace (e.g., `'kabuk.widgets'`).
  final String library;

  /// The widget name within the library (e.g., `'NoteCard'`).
  final String widget;

  /// Data bindings mapping DynamicContent keys to values.
  final Map<String, dynamic> bindings;

  /// Additional data to pass to the widget, if any.
  final Map<String, dynamic>? data;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'widget',
    'library': library,
    'widget': widget,
    'bindings': bindings,
    if (data != null) 'data': data,
  };
}

/// A raw RFW template string with inline data.
final class RawWidgetToolResult extends ToolResult {
  /// Creates a [RawWidgetToolResult] with the given RFW [source]
  /// template and [data] bindings.
  const RawWidgetToolResult({required this.source, required this.data});

  /// The raw RFW template source text.
  final String source;

  /// Data bindings for the template.
  final Map<String, dynamic> data;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'raw_widget',
    'source': source,
    'data': data,
  };
}

/// A tool result representing knowledge store mutations.
final class MutationToolResult extends ToolResult {
  /// Creates a [MutationToolResult] with lists of [added] and [removed]
  /// triples (each as a JSON map with `subject`, `predicate`, `object`).
  const MutationToolResult({this.added = const [], this.removed = const []});

  /// Triples that were added to the knowledge store.
  final List<Map<String, dynamic>> added;

  /// Triples that were removed from the knowledge store.
  final List<Map<String, dynamic>> removed;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'mutation',
    'added': added,
    'removed': removed,
  };
}

/// Multiple tool results combined into a single result.
final class CompoundToolResult extends ToolResult {
  /// Creates a [CompoundToolResult] combining multiple [results].
  const CompoundToolResult(this.results);

  /// The individual tool results.
  final List<ToolResult> results;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'compound',
    'results': results.map((r) => r.toJson()).toList(),
  };
}

/// An agent-populated channel.
///
/// Carries a [Channel] identity plus the typed [ContentItem]s the agent
/// produced for it. The runtime populates the active channel session and
/// the OS draws the items with existing primitives.
final class ChannelToolResult extends ToolResult {
  /// Creates a [ChannelToolResult].
  const ChannelToolResult({
    required this.channel,
    required this.items,
    this.summary,
  });

  /// The channel identity (uri, type, title, artwork).
  final Channel channel;

  /// Typed content items produced for the channel.
  final List<ContentItem> items;

  /// Optional one-line summary the agent wrote about the results.
  final String? summary;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'channel',
    'channelUri': channel.entityUri,
    'title': channel.title,
    'entityType': channel.entityType.name,
    'items': items.map(_contentItemToJson).toList(),
    if (summary != null) 'summary': summary,
  };
}

/// Compact JSON serialization of a [ContentItem] for the tool result wire
/// format (isolate boundary + message persistence).
Map<String, dynamic> _contentItemToJson(ContentItem item) => {
  'sourcePluginId': item.sourcePluginId,
  'externalId': item.externalId,
  'contentType': item.contentType.name,
  'title': item.title,
  if (item.description != null) 'description': item.description,
  if (item.url != null) 'url': item.url,
  if (item.thumbnailUrl != null) 'thumbnailUrl': item.thumbnailUrl,
  if (item.author?.name != null) 'author': item.author!.name,
  if (item.publishedAt != null)
    'publishedAt': item.publishedAt!.toIso8601String(),
  'tags': item.tags,
  'extra': item.extra,
};

/// Capabilities that an agent can request.
///
/// The system checks these against the agent's permissions before
/// granting access to the corresponding service.
enum AgentCapability {
  /// Read from the knowledge store.
  knowledgeRead,

  /// Write to the knowledge store.
  knowledgeWrite,

  /// Read secrets from the vault.
  vaultRead,

  /// Write secrets to the vault.
  vaultWrite,

  /// Capture media (camera, microphone).
  mediaCapture,

  /// Play back media (audio, video).
  mediaPlayback,

  /// Connect to the mesh network.
  meshConnect,

  /// Send data over the mesh network.
  meshSend,

  /// Send notifications.
  notifySend,

  /// Sign data using the user's key.
  authSign,

  /// Make LLM API calls.
  llmCall,

  /// Invoke other agents.
  agentInvoke,
}

/// Base class for all agents.
///
/// Agents are stateless — all persistent state lives in the knowledge store.
/// Each agent declares its tools and the capabilities it requires.
/// Subclasses must implement [name], [description], [systemPrompt],
/// [tools], [requiredCapabilities], and [process].
abstract class BaseAgent {
  /// Machine-readable agent name (e.g., `'weather'`, `'notes'`).
  String get name;

  /// Human-readable description of what this agent does.
  String get description;

  /// System prompt used when this agent interacts with the LLM.
  String get systemPrompt;

  /// Builds the full system prompt by combining the shared Kabuk identity
  /// context, this agent's [systemPrompt], behavioral guidelines, and
  /// the current date/time.
  ///
  /// Agents should use this in their [process] method when calling the LLM
  /// instead of using [systemPrompt] directly. Override [includeIdentity]
  /// to `false` if the agent already includes identity context (e.g. the
  /// router agent).
  String buildSystemPrompt({bool includeIdentity = true}) =>
      KabukPrompts.buildFullPrompt(
        agentPrompt: systemPrompt,
        includeIdentity: includeIdentity,
      );

  /// Tools this agent provides for the LLM to invoke.
  List<AgentTool> get tools;

  /// Capabilities this agent requires from the system.
  Set<AgentCapability> get requiredCapabilities;

  /// Process a message from the user or another agent.
  ///
  /// This is the main entry point. The agent may query the knowledge
  /// store, invoke tools, call the LLM, or delegate to other agents
  /// via [context].
  Future<AgentResponse> process(AgentMessage message, AgentContext context);

  /// Execute a tool and notify the context's tool callbacks.
  ///
  /// Domain agents should call this instead of `tool.execute()` directly
  /// so that tool calls and results are surfaced to the UI.
  Future<ToolResult> executeTool(
    AgentTool tool,
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    context.onToolCall?.call(tool.name, args);
    final result = await tool.execute(args, context);

    // Channel results are applied as a side-effect at execution time: the
    // active channel session is populated and an observation is published
    // so the OS surfaces can redraw and the perception layer can record it.
    if (result is ChannelToolResult) {
      context.channels?.populate(
        ChannelSession(
          channel: result.channel,
          items: result.items,
          summary: result.summary,
          agentName: name,
        ),
      );
      context.observation?.publish(
        ChannelPopulatedEvent(
          channelUri: result.channel.entityUri,
          title: result.channel.title,
          itemCount: result.items.length,
          agentName: name,
          summary: result.summary,
        ),
      );
    }

    context.onToolResult?.call(tool.name, result);
    return result;
  }

  /// Convenience helper that sends an [LlmRequest], dispatches tool calls
  /// through [completeToolCallLoop], and wraps everything in a try/catch
  /// so that network errors, LLM failures, or unexpected exceptions are
  /// returned as [AgentResponse.error] instead of propagating.
  ///
  /// Most domain agents can simplify their `process()` to:
  /// ```dart
  /// return processLlmRequest(
  ///   context: context,
  ///   messages: llmMessages,
  ///   systemPrompt: prompt,
  ///   temperature: 0.5,
  ///   tier: LlmTier.standard,
  /// );
  /// ```
  ///
  /// When [tier] is specified, the request is tagged with
  /// `model: 'tier:{tierName}'` so the [TieredLlmService] can route
  /// it to the appropriate backend. If omitted, the default tier
  /// (base) is used.
  Future<AgentResponse> processLlmRequest({
    required AgentContext context,
    required List<LlmMessage> messages,
    required String systemPrompt,
    double? temperature,
    LlmTier? tier,
  }) async {
    try {
      final modelHint = tier != null ? 'tier:${tier.name}' : null;
      final request = LlmRequest(
        systemPrompt: systemPrompt,
        messages: messages,
        tools: tools.map((t) => t.toFunctionSchema()).toList(),
        temperature: temperature,
        model: modelHint,
      );

      // Use streaming so the UI can show tokens as they arrive.
      // Tool calls are handled internally: if the LLM emits tool-call
      // events, they are executed and a new streaming re-prompt is
      // chained, all within the same output stream.
      final stream = _streamWithToolHandling(
        context: context,
        request: request,
        messages: messages,
      );
      return AgentResponse.streaming(stream);
    } on LlmStreamException catch (e) {
      return AgentResponse.error(e.message);
    } on Object catch (e, st) {
      dev.log('$name agent error: $e', name: 'Agent', error: e, stackTrace: st);
      return AgentResponse.error(
        'The $name agent encountered an error. Please try again.',
      );
    }
  }

  /// Wraps context.llm.stream with automatic tool-call handling.
  ///
  /// Text deltas are yielded immediately for real-time UI. Tool-call
  /// events are collected; after the stream ends, the tools are executed,
  /// results are appended to the conversation, and a new streaming
  /// re-prompt is chained — recursively up to [maxDepth] rounds.
  Stream<LlmStreamEvent> _streamWithToolHandling({
    required AgentContext context,
    required LlmRequest request,
    required List<LlmMessage> messages,
    int depth = 0,
    int maxDepth = 3,
  }) async* {
    final toolCalls = <LlmToolCall>[];
    final textBuffer = StringBuffer();

    await for (final event in context.llm.stream(request)) {
      switch (event) {
        case TextDeltaEvent(:final text):
          textBuffer.write(text);
          yield event;
        case ToolCallEvent(:final call):
          toolCalls.add(call);
        case UsageEvent():
          yield event;
        case DoneEvent():
          break; // Handled below after tool processing.
      }
    }

    // No tool calls — we're done.
    if (toolCalls.isEmpty || depth >= maxDepth) {
      yield const LlmStreamEvent.done();
      return;
    }

    // Execute tool calls.
    final toolResultMessages = <LlmMessage>[];
    for (final call in toolCalls) {
      final tool = tools.where((t) => t.name == call.name).firstOrNull;
      if (tool == null) {
        toolResultMessages.add(
          LlmMessage.toolResult(
            callId: call.id,
            content: 'Error: Unknown tool "${call.name}"',
          ),
        );
        continue;
      }

      final result = await executeTool(tool, call.arguments, context);

      final resultContent = switch (result) {
        TextToolResult(:final content) => content,
        ErrorToolResult(:final message) => 'Error: $message',
        WidgetToolResult() => 'Widget rendered successfully.',
        RawWidgetToolResult() => 'Widget rendered successfully.',
        ChannelToolResult(:final channel, :final items) =>
          'Channel populated: ${items.length} items for '
              '"${channel.title}".',
        MutationToolResult(:final added, :final removed) =>
          'Mutation applied: ${added.length} triples added, '
              '${removed.length} removed.',
        CompoundToolResult(:final results) =>
          results
              .map(
                (r) => switch (r) {
                  TextToolResult(:final content) => content,
                  ErrorToolResult(:final message) => 'Error: $message',
                  _ => 'Done.',
                },
              )
              .join('\n'),
      };

      toolResultMessages.add(
        LlmMessage.toolResult(callId: call.id, content: resultContent),
      );
    }

    // Build updated conversation for re-prompt.
    final updatedMessages = [
      ...messages,
      LlmMessage.assistant(textBuffer.toString(), toolCalls: toolCalls),
      ...toolResultMessages,
    ];

    final newRequest = LlmRequest(
      systemPrompt: request.systemPrompt,
      messages: updatedMessages,
      tools: request.tools,
      temperature: request.temperature,
      model: request.model,
    );

    // Chain next round of streaming (with tool handling).
    yield* _streamWithToolHandling(
      context: context,
      request: newRequest,
      messages: updatedMessages,
      depth: depth + 1,
      maxDepth: maxDepth,
    );
  }

  /// Execute tool calls and re-prompt the LLM to synthesize a response.
  ///
  /// Implements the standard function-calling loop:
  /// 1. Execute each requested tool
  /// 2. Build tool result messages
  /// 3. Re-prompt the LLM with conversation + tool results (streaming)
  /// 4. If the LLM requests more tools, recurse (up to [maxDepth])
  /// 5. Return the LLM's final streamed response
  Future<AgentResponse> completeToolCallLoop({
    required List<LlmMessage> messages,
    required List<LlmToolCall> toolCalls,
    required AgentContext context,
    String? systemPrompt,
    double? temperature,
    int depth = 0,
    int maxDepth = 3,
  }) async {
    if (depth >= maxDepth) {
      return const AgentResponse.text('Max tool call depth reached.');
    }

    // Execute all requested tools.
    final toolResultMessages = <LlmMessage>[];
    ToolResult? widgetResult; // Track any widget result for the response.

    for (final call in toolCalls) {
      final tool = tools.where((t) => t.name == call.name).firstOrNull;
      if (tool == null) {
        toolResultMessages.add(
          LlmMessage.toolResult(
            callId: call.id,
            content: 'Error: Unknown tool "${call.name}"',
          ),
        );
        continue;
      }

      final result = await executeTool(tool, call.arguments, context);

      // Track widget results.
      if (result is WidgetToolResult || result is RawWidgetToolResult) {
        widgetResult = result;
      } else if (result is CompoundToolResult) {
        for (final r in result.results) {
          if (r is WidgetToolResult || r is RawWidgetToolResult) {
            widgetResult = r;
          }
        }
      }

      // Serialize result for the LLM.
      final resultContent = switch (result) {
        TextToolResult(:final content) => content,
        ErrorToolResult(:final message) => 'Error: $message',
        WidgetToolResult() => 'Widget rendered successfully.',
        RawWidgetToolResult() => 'Widget rendered successfully.',
        ChannelToolResult(:final channel, :final items) =>
          'Channel populated: ${items.length} items for '
              '"${channel.title}".',
        MutationToolResult(:final added, :final removed) =>
          'Mutation applied: ${added.length} triples added, '
              '${removed.length} removed.',
        CompoundToolResult(:final results) =>
          results
              .map(
                (r) => switch (r) {
                  TextToolResult(:final content) => content,
                  ErrorToolResult(:final message) => 'Error: $message',
                  _ => 'Done.',
                },
              )
              .join('\n'),
      };

      toolResultMessages.add(
        LlmMessage.toolResult(callId: call.id, content: resultContent),
      );
    }

    // Build the updated message list:
    // [original messages] + [assistant message with tool calls] + [tool results]
    final updatedMessages = [
      ...messages,
      LlmMessage.assistant('', toolCalls: toolCalls),
      ...toolResultMessages,
    ];

    // Re-prompt the LLM using streaming with tool handling so tokens
    // appear in real-time and further tool calls are processed.
    final request = LlmRequest(
      systemPrompt: systemPrompt ?? this.systemPrompt,
      messages: updatedMessages,
      tools: tools.map((t) => t.toFunctionSchema()).toList(),
      temperature: temperature,
    );

    final stream = _streamWithToolHandling(
      context: context,
      request: request,
      messages: updatedMessages,
      depth: depth,
      maxDepth: maxDepth,
    );
    if (widgetResult != null) {
      return AgentResponse.widget(
        content: '', // Content will be streamed.
        widgetResult: widgetResult,
      );
    }
    return AgentResponse.streaming(stream);
  }

  /// Handle an event from an RFW widget owned by this agent.
  ///
  /// Override this to respond to user interactions with widgets
  /// rendered by this agent's tool results.
  Future<AgentResponse> handleWidgetEvent({
    required String widgetName,
    required String eventName,
    required Map<String, dynamic> params,
    required AgentContext context,
  }) async {
    return AgentResponse.text('Event not handled: $eventName');
  }
}
