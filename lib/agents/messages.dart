/// Agent message types — sealed classes for all message exchanges.
///
/// Messages flow between users, agents, and the system using a typed
/// protocol. Sealed classes enable exhaustive pattern matching at
/// every boundary.
library;

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/llm.dart';

/// Messages exchanged between users, agents, and the system.
///
/// Every message has a unique [id], a [timestamp], and an optional
/// [conversationId] linking it to a conversation thread.
sealed class AgentMessage {
  /// Creates an [AgentMessage] with the given [id], [timestamp],
  /// and optional [conversationId].
  const AgentMessage({
    required this.id,
    required this.timestamp,
    this.conversationId,
  });

  /// Unique identifier for this message.
  final String id;

  /// When this message was created.
  final DateTime timestamp;

  /// The conversation this message belongs to, if any.
  final String? conversationId;

  /// A message from the user.
  const factory AgentMessage.user({
    required String id,
    required DateTime timestamp,
    String? conversationId,
    required String content,
    List<LlmMessage>? history,
  }) = UserMessage;

  /// A response from an agent.
  const factory AgentMessage.agentResponse({
    required String id,
    required DateTime timestamp,
    String? conversationId,
    required String agentName,
    required String content,
    ToolResult? widgetResult,
  }) = AgentResponseMessage;

  /// A tool invocation request.
  const factory AgentMessage.toolCall({
    required String id,
    required DateTime timestamp,
    String? conversationId,
    required String toolName,
    required Map<String, dynamic> arguments,
  }) = ToolCallMessage;

  /// The result of a tool invocation.
  const factory AgentMessage.toolResult({
    required String id,
    required DateTime timestamp,
    String? conversationId,
    required String callId,
    required ToolResult result,
  }) = ToolResultMessage;

  /// A system notification or control message.
  const factory AgentMessage.system({
    required String id,
    required DateTime timestamp,
    String? conversationId,
    required String content,
  }) = SystemMessage;
}

/// A message from the user containing free-form text.
final class UserMessage extends AgentMessage {
  /// Creates a [UserMessage] with the given [content] and optional [history].
  const UserMessage({
    required super.id,
    required super.timestamp,
    super.conversationId,
    required this.content,
    this.history,
  });

  /// The user's message text.
  final String content;

  /// Prior conversation messages for context, if available.
  ///
  /// Populated by the chat service from the DB so agents can include
  /// conversation history when making LLM calls.
  final List<LlmMessage>? history;
}

/// A response from an agent, with optional widget result.
final class AgentResponseMessage extends AgentMessage {
  /// Creates an [AgentResponseMessage] from [agentName] with [content]
  /// and an optional [widgetResult] for rich UI rendering.
  const AgentResponseMessage({
    required super.id,
    required super.timestamp,
    super.conversationId,
    required this.agentName,
    required this.content,
    this.widgetResult,
  });

  /// The name of the agent that produced this response.
  final String agentName;

  /// The text content of the response.
  final String content;

  /// An optional RFW widget result to render alongside the text.
  final ToolResult? widgetResult;
}

/// A tool invocation message.
final class ToolCallMessage extends AgentMessage {
  /// Creates a [ToolCallMessage] invoking [toolName] with [arguments].
  const ToolCallMessage({
    required super.id,
    required super.timestamp,
    super.conversationId,
    required this.toolName,
    required this.arguments,
  });

  /// The name of the tool to invoke.
  final String toolName;

  /// The arguments to pass to the tool.
  final Map<String, dynamic> arguments;
}

/// The result of a tool invocation.
final class ToolResultMessage extends AgentMessage {
  /// Creates a [ToolResultMessage] for the tool call identified by [callId].
  const ToolResultMessage({
    required super.id,
    required super.timestamp,
    super.conversationId,
    required this.callId,
    required this.result,
  });

  /// The ID of the tool call this result corresponds to.
  final String callId;

  /// The result of the tool execution.
  final ToolResult result;
}

/// A system notification or control message.
final class SystemMessage extends AgentMessage {
  /// Creates a [SystemMessage] with the given [content].
  const SystemMessage({
    required super.id,
    required super.timestamp,
    super.conversationId,
    required this.content,
  });

  /// The system message content.
  final String content;
}

/// A response from an agent, which may include text, widgets, errors,
/// or a token stream.
///
/// Uses sealed classes for exhaustive pattern matching.
sealed class AgentResponse {
  /// Creates an [AgentResponse].
  const AgentResponse({this.agentName});

  /// The name of the agent that produced this response.
  ///
  /// Set by the router when dispatching to domain agents so the
  /// presentation layer can show the correct sender.
  final String? agentName;

  /// A plain text response.
  const factory AgentResponse.text(String content, {String? agentName}) =
      TextAgentResponse;

  /// A response with text and an accompanying RFW widget.
  const factory AgentResponse.widget({
    required String content,
    required ToolResult widgetResult,
    String? agentName,
  }) = WidgetAgentResponse;

  /// An error response.
  const factory AgentResponse.error(String message, {String? agentName}) =
      ErrorAgentResponse;

  /// A streaming response delivering events (text deltas and tool calls).
  const factory AgentResponse.streaming(
    Stream<LlmStreamEvent> events, {
    String? agentName,
  }) = StreamingAgentResponse;

  /// Returns a copy of this response tagged with the given [name].
  AgentResponse withAgentName(String name) => switch (this) {
    TextAgentResponse(:final content) => AgentResponse.text(
      content,
      agentName: name,
    ),
    WidgetAgentResponse(:final content, :final widgetResult) =>
      AgentResponse.widget(
        content: content,
        widgetResult: widgetResult,
        agentName: name,
      ),
    ErrorAgentResponse(:final message) => AgentResponse.error(
      message,
      agentName: name,
    ),
    StreamingAgentResponse(:final events) => AgentResponse.streaming(
      events,
      agentName: name,
    ),
  };
}

/// A plain text agent response.
final class TextAgentResponse extends AgentResponse {
  /// Creates a [TextAgentResponse] with the given [content].
  const TextAgentResponse(this.content, {super.agentName});

  /// The text content.
  final String content;
}

/// A response containing both text and an RFW widget.
final class WidgetAgentResponse extends AgentResponse {
  /// Creates a [WidgetAgentResponse] with [content] and a [widgetResult].
  const WidgetAgentResponse({
    required this.content,
    required this.widgetResult,
    super.agentName,
  });

  /// The text content accompanying the widget.
  final String content;

  /// The RFW widget result to render.
  final ToolResult widgetResult;
}

/// An error agent response.
final class ErrorAgentResponse extends AgentResponse {
  /// Creates an [ErrorAgentResponse] with the given error [message].
  const ErrorAgentResponse(this.message, {super.agentName});

  /// The error message.
  final String message;
}

/// A streaming agent response that delivers events incrementally.
final class StreamingAgentResponse extends AgentResponse {
  /// Creates a [StreamingAgentResponse] with the given [events] stream.
  const StreamingAgentResponse(this.events, {super.agentName});

  /// A stream of [LlmStreamEvent]s as they are generated.
  final Stream<LlmStreamEvent> events;
}
