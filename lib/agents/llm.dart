/// LLM service — abstraction over LLM providers.
///
/// Provides a unified interface for interacting with language models
/// from various providers (OpenAI, Anthropic, Ollama, local).
/// All LLM calls from agents must go through [LlmService] for
/// abstraction, cost tracking, and retry logic.
library;

/// Abstraction over LLM providers (OpenAI, Anthropic, Ollama, local).
///
/// Agents never call LLM APIs directly — they always go through
/// this interface, which handles provider selection, rate limiting,
/// retries, and cost tracking.
abstract interface class LlmService {
  /// Send a completion request and receive a full response.
  Future<LlmResponse> complete(LlmRequest request);

  /// Stream a completion response as events (text deltas, tool calls).
  ///
  /// Yields [LlmStreamEvent]s that can be text deltas, complete tool calls,
  /// or a done signal. This allows streaming text to the UI while still
  /// receiving tool call information from the LLM.
  Stream<LlmStreamEvent> stream(LlmRequest request);

  /// Count tokens in [text] (approximate).
  ///
  /// Useful for truncating context to fit within model limits.
  int countTokens(String text);
}

/// A request to the LLM.
///
/// Encapsulates all parameters needed for a completion or streaming call.
class LlmRequest {
  /// Creates an [LlmRequest] with the given parameters.
  const LlmRequest({
    required this.messages,
    this.tools,
    this.model,
    this.temperature,
    this.maxTokens,
    this.systemPrompt,
  });

  /// The conversation history as a list of [LlmMessage]s.
  final List<LlmMessage> messages;

  /// JSON Schema tool definitions for function calling.
  final List<Map<String, dynamic>>? tools;

  /// The model identifier (e.g., `'claude-3-opus'`, `'gpt-4o'`).
  /// If `null`, the service picks a default.
  final String? model;

  /// Sampling temperature (0.0 = deterministic, 1.0+ = creative).
  final double? temperature;

  /// Maximum number of tokens to generate.
  final int? maxTokens;

  /// System prompt prepended to the conversation.
  final String? systemPrompt;
}

/// A message in an LLM conversation.
///
/// Uses sealed classes for exhaustive pattern matching over
/// the four roles: system, user, assistant, and tool result.
sealed class LlmMessage {
  /// Creates an [LlmMessage].
  const LlmMessage();

  /// A system-level instruction message.
  const factory LlmMessage.system(String content) = SystemLlmMessage;

  /// A message from the user.
  const factory LlmMessage.user(String content) = UserLlmMessage;

  /// A message from the assistant, optionally including tool calls.
  const factory LlmMessage.assistant(
    String content, {
    List<LlmToolCall>? toolCalls,
  }) = AssistantLlmMessage;

  /// The result of a tool call, sent back to the assistant.
  const factory LlmMessage.toolResult({
    required String callId,
    required String content,
  }) = ToolResultLlmMessage;

  /// Serialize this message to JSON for API calls.
  Map<String, dynamic> toJson();
}

/// A system-level instruction message.
final class SystemLlmMessage extends LlmMessage {
  /// Creates a [SystemLlmMessage] with the given [content].
  const SystemLlmMessage(this.content);

  /// The system instruction content.
  final String content;

  @override
  Map<String, dynamic> toJson() => {'role': 'system', 'content': content};
}

/// A message from the user.
final class UserLlmMessage extends LlmMessage {
  /// Creates a [UserLlmMessage] with the given [content].
  const UserLlmMessage(this.content);

  /// The user message content.
  final String content;

  @override
  Map<String, dynamic> toJson() => {'role': 'user', 'content': content};
}

/// A message from the assistant, optionally including tool calls.
final class AssistantLlmMessage extends LlmMessage {
  /// Creates an [AssistantLlmMessage] with the given [content]
  /// and optional [toolCalls].
  const AssistantLlmMessage(this.content, {this.toolCalls});

  /// The assistant's text response.
  final String content;

  /// Tool calls the assistant wants to make, if any.
  final List<LlmToolCall>? toolCalls;

  @override
  Map<String, dynamic> toJson() => {
    'role': 'assistant',
    'content': content,
    if (toolCalls != null)
      'tool_calls': toolCalls!.map((tc) => tc.toJson()).toList(),
  };
}

/// The result of a tool call, sent back to the assistant.
final class ToolResultLlmMessage extends LlmMessage {
  /// Creates a [ToolResultLlmMessage] with the given [callId] and [content].
  const ToolResultLlmMessage({required this.callId, required this.content});

  /// The ID of the tool call this result corresponds to.
  final String callId;

  /// The serialized result content.
  final String content;

  @override
  Map<String, dynamic> toJson() => {
    'role': 'tool',
    'tool_call_id': callId,
    'content': content,
  };
}

/// An LLM tool call requested by the assistant.
class LlmToolCall {
  /// Creates an [LlmToolCall] with the given [id], [name], and [arguments].
  const LlmToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// Unique identifier for this tool call.
  final String id;

  /// The name of the tool to invoke.
  final String name;

  /// Parsed arguments for the tool.
  final Map<String, dynamic> arguments;

  /// Serialize this tool call to JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': arguments},
  };
}

/// Token usage reported by the LLM provider for a completion request.
///
/// Tracks prompt, completion, and total token counts to enable
/// cost calculation and budget tracking.
class LlmUsage {
  /// Creates an [LlmUsage] record.
  const LlmUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    required this.model,
    required this.provider,
  });

  /// Number of tokens in the prompt (input).
  final int promptTokens;

  /// Number of tokens in the completion (output).
  final int completionTokens;

  /// Total tokens consumed (prompt + completion).
  final int totalTokens;

  /// Model identifier as returned by the provider.
  final String model;

  /// The provider this usage belongs to.
  final LlmProvider provider;

  @override
  String toString() =>
      'LlmUsage(prompt: $promptTokens, completion: $completionTokens, '
      'total: $totalTokens, model: $model)';
}

/// A response from the LLM.
///
/// Uses sealed classes for exhaustive pattern matching over
/// the three possible outcomes: text, tool calls, or error.
sealed class LlmResponse {
  /// Creates an [LlmResponse].
  const LlmResponse();

  /// A plain text response.
  const factory LlmResponse.text(String content, {LlmUsage? usage}) =
      TextLlmResponse;

  /// A response requesting tool calls, with optional accompanying text.
  const factory LlmResponse.toolCalls(
    String? content,
    List<LlmToolCall> calls, {
    LlmUsage? usage,
  }) = ToolCallsLlmResponse;

  /// An error response.
  const factory LlmResponse.error(String message) = ErrorLlmResponse;
}

/// A plain text LLM response.
final class TextLlmResponse extends LlmResponse {
  /// Creates a [TextLlmResponse] with the given [content] and optional [usage].
  const TextLlmResponse(this.content, {this.usage});

  /// The text content of the response.
  final String content;

  /// Token usage for this response, or `null` if not reported by the provider.
  final LlmUsage? usage;
}

/// An LLM response requesting one or more tool calls.
final class ToolCallsLlmResponse extends LlmResponse {
  /// Creates a [ToolCallsLlmResponse] with optional [content], [calls], and [usage].
  const ToolCallsLlmResponse(this.content, this.calls, {this.usage});

  /// Optional text content accompanying the tool calls.
  final String? content;

  /// The tool calls requested by the LLM.
  final List<LlmToolCall> calls;

  /// Token usage for this response, or `null` if not reported by the provider.
  final LlmUsage? usage;
}

/// An error LLM response.
final class ErrorLlmResponse extends LlmResponse {
  /// Creates an [ErrorLlmResponse] with the given error [message].
  const ErrorLlmResponse(this.message);

  /// The error message.
  final String message;
}

/// Exception thrown when an LLM streaming request fails.
class LlmStreamException implements Exception {
  /// Creates an [LlmStreamException] with the given [message].
  const LlmStreamException(this.message);

  /// A human-readable description of the error.
  final String message;

  @override
  String toString() => 'LlmStreamException: $message';
}

/// An event emitted during an LLM streaming response.
///
/// Streaming responses yield a sequence of events: zero or more
/// [TextDeltaEvent]s interleaved with [ToolCallEvent]s, terminated
/// by a [DoneEvent]. A [UsageEvent] may be emitted before [DoneEvent]
/// for providers that report token counts in the stream. Consumers
/// pattern-match to handle each type.
sealed class LlmStreamEvent {
  /// Creates an [LlmStreamEvent].
  const LlmStreamEvent();

  /// A text content delta.
  const factory LlmStreamEvent.textDelta(String text) = TextDeltaEvent;

  /// A completed tool call parsed from streaming deltas.
  const factory LlmStreamEvent.toolCall(LlmToolCall call) = ToolCallEvent;

  /// Token usage for the completed streaming response.
  const factory LlmStreamEvent.usage(LlmUsage usage) = UsageEvent;

  /// Signals the stream is complete.
  const factory LlmStreamEvent.done() = DoneEvent;
}

/// A text delta streamed from the LLM.
final class TextDeltaEvent extends LlmStreamEvent {
  /// Creates a [TextDeltaEvent] with the given [text].
  const TextDeltaEvent(this.text);

  /// The text fragment.
  final String text;
}

/// A complete tool call parsed from accumulated streaming deltas.
final class ToolCallEvent extends LlmStreamEvent {
  /// Creates a [ToolCallEvent] with the given [call].
  const ToolCallEvent(this.call);

  /// The completed tool call.
  final LlmToolCall call;
}

/// Token usage emitted before the stream closes.
///
/// Providers that support streaming usage (e.g. OpenAI with
/// `stream_options.include_usage`) emit this event so cost tracking
/// works equally for streaming and blocking completions.
final class UsageEvent extends LlmStreamEvent {
  /// Creates a [UsageEvent] with the given [usage].
  const UsageEvent(this.usage);

  /// The token usage for the completed streaming response.
  final LlmUsage usage;
}

/// Signals the end of the streaming response.
final class DoneEvent extends LlmStreamEvent {
  /// Creates a [DoneEvent].
  const DoneEvent();
}

/// Available LLM providers.
enum LlmProvider {
  /// Anthropic (Claude models).
  anthropic,

  /// OpenAI (GPT models).
  openai,

  /// Ollama (local model server).
  ollama,

  /// Local on-device model.
  local,
}
