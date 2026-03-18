/// Chat service — manages message sending, agent invocation, and streaming.
///
/// This service encapsulates the send/receive pipeline so it can be used
/// from both the main chat view and the pull-up chat sheet overlay.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Maximum number of prior messages to include as conversation context.
const _maxHistoryMessages = 20;

/// Whether the agent is currently processing a message.
final isProcessingProvider = StateProvider<bool>((ref) => false);

/// Text currently being streamed from the agent (shown in real-time).
final streamingTextProvider = StateProvider<String?>((ref) => null);

/// User-visible status of what the AI is currently doing.
///
/// Set during processing to give feedback while the user waits for
/// the first streaming token (e.g. "Thinking…", "Using notes…").
final processingStatusProvider = StateProvider<String?>((ref) => null);

/// Provides the [ChatService] for sending messages and managing conversations.
final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(ref);
});

/// Service managing chat message flows, agent routing, and conversation state.
///
/// Decouples the chat pipeline from the UI so it can be shared between
/// the main chat view and the pull-up chat sheet overlay.
class ChatService {
  /// Creates a [ChatService] with a Riverpod [Ref] for accessing providers.
  ChatService(this._ref);

  final Ref _ref;

  /// Active send operation, if any. Used as a concurrency guard to prevent
  /// overlapping message sends from corrupting state.
  Future<String>? _activeSend;

  /// Tracks conversations that already have a pending title-generation call
  /// to prevent duplicate LLM requests when messages are sent rapidly.
  final Set<String> _pendingTitles = {};

  /// Whether the agent is currently processing a message.
  bool get isProcessing => _ref.read(isProcessingProvider);

  /// Send a user message and get an agent response.
  ///
  /// Creates a new conversation if needed, inserts the user message,
  /// loads conversation history, invokes the router agent, and inserts
  /// the response.
  ///
  /// If a send is already in progress, the call awaits the existing
  /// operation and returns its result instead of starting a new one.
  ///
  /// Returns the agent response content string.
  Future<String> sendMessage(String text) async {
    if (_activeSend != null) return _activeSend!;
    final completer = Completer<String>();
    _activeSend = completer.future;
    try {
      final result = await _doSendMessage(text);
      completer.complete(result);
      return result;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _activeSend = null;
    }
  }

  Future<String> _doSendMessage(String text) async {
    if (text.trim().isEmpty) return '';

    final db = _ref.read(databaseProvider);
    var conversationId = _ref.read(activeConversationProvider);

    // Re-use the single canonical agent conversation rather than creating a
    // new thread for every quick-chat session.  Only create one when none
    // exists yet.
    if (conversationId == null) {
      final all = await db.listConversations();
      final existing = all.where((c) => c.type == 'agent').firstOrNull;
      if (existing != null) {
        conversationId = existing.id;
      } else {
        conversationId = _uuid.v4();
        await db.upsertConversation(
          ConversationsCompanion.insert(
            id: conversationId,
            title: const Value('Kabuk AI'),
            type: const Value('agent'),
          ),
        );
      }
      _ref.read(activeConversationProvider.notifier).state = conversationId;
    }

    // Insert user message — fire-and-forget for optimistic UI.
    final userMsgId = _uuid.v4();
    final userMsgFuture = db.insertMessage(
      MessagesCompanion.insert(
        id: userMsgId,
        conversationId: conversationId,
        role: 'user',
        content: text,
        timestamp: DateTime.now(),
      ),
    );

    // Mark processing immediately — don't wait for DB write.
    _ref.read(isProcessingProvider.notifier).state = true;
    _ref.read(processingStatusProvider.notifier).state = 'Thinking…';

    // Await the user message insert and build history in parallel.
    await userMsgFuture;

    // Load conversation history for context.
    final history = await _buildConversationHistory(conversationId);
    // Capture as non-null local for use in closures below.
    final convId = conversationId;
    try {
      final context = _ref.read(agentContextProvider);
      final runtime = _ref.read(agentRuntimeProvider);

      // Collect DB write futures so we can await them before the final
      // agent response insert, preventing silent failures and ordering issues.
      final pendingWrites = <Future<int>>[];

      // Create a context with tool execution callbacks that insert
      // intermediate tool_call and tool_result messages into the DB.
      final contextWithCallbacks = context.copyWithCallbacks(
        onToolCall: (name, args) {
          // Show which tool the AI is using.
          final label = name
              .replaceAll('_', ' ')
              .replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());
          _ref.read(processingStatusProvider.notifier).state = 'Using $label…';
          pendingWrites.add(
            db.insertMessage(
              MessagesCompanion.insert(
                id: _uuid.v4(),
                conversationId: convId,
                role: 'tool_call',
                content: 'Calling $name…',
                metadata: Value(json.encode({'tool': name, 'args': args})),
                timestamp: DateTime.now(),
              ),
            ),
          );
        },
        onToolResult: (name, result) {
          final content = switch (result) {
            TextToolResult(:final content) =>
              content.length > 200 ? '${content.substring(0, 200)}…' : content,
            ErrorToolResult(:final message) => 'Error: $message',
            WidgetToolResult() => 'Widget rendered.',
            RawWidgetToolResult() => 'Widget rendered.',
            MutationToolResult(:final added, :final removed) =>
              'Mutated: +${added.length} -${removed.length} triples.',
            CompoundToolResult(:final results) => '${results.length} results.',
          };
          pendingWrites.add(
            db.insertMessage(
              MessagesCompanion.insert(
                id: _uuid.v4(),
                conversationId: convId,
                role: 'tool_result',
                content: content,
                metadata: Value(
                  json.encode({
                    'tool': name,
                    'success': result is! ErrorToolResult,
                  }),
                ),
                timestamp: DateTime.now(),
              ),
            ),
          );
        },
      );

      final message = AgentMessage.user(
        id: userMsgId,
        timestamp: DateTime.now(),
        conversationId: conversationId,
        content: text,
        history: history,
      );

      final response = await runtime.invoke(
        'router',
        message,
        contextWithCallbacks,
      );

      // Extract text from the response, handling streaming.
      var responseContent = '';
      String? widgetMetadata;

      if (response is StreamingAgentResponse) {
        // Update status to show we got past routing.
        _ref.read(processingStatusProvider.notifier).state =
            'Generating response…';
        // Streaming: tool calls are handled internally by the agent.
        // We just consume text deltas for real-time display.
        final streamResult = await _handleStream(response.events);
        responseContent = streamResult.text;
      } else {
        responseContent = switch (response) {
          TextAgentResponse(:final content) => content,
          WidgetAgentResponse(:final content) => content,
          ErrorAgentResponse(:final message) => 'Error: $message',
          StreamingAgentResponse() => '', // unreachable
        };

        if (response is WidgetAgentResponse) {
          widgetMetadata = json.encode(response.widgetResult.toJson());
        }
      }

      // Ensure all tool messages are persisted before the final response.
      await Future.wait(pendingWrites);

      // Insert agent response into the database.
      final respondingAgent = response.agentName ?? 'router';
      await db.insertMessage(
        MessagesCompanion.insert(
          id: _uuid.v4(),
          conversationId: conversationId,
          role: 'agent',
          agentName: Value(respondingAgent),
          content: responseContent,
          metadata: Value(widgetMetadata),
          timestamp: DateTime.now(),
        ),
      );

      // Touch the conversation timestamp.
      await (db.update(db.conversations)
            ..where((c) => c.id.equals(conversationId!)))
          .write(ConversationsCompanion(updatedAt: Value(DateTime.now())));

      // Generate a better title for the conversation after the first exchange.
      unawaited(_maybeGenerateTitle(conversationId, text, responseContent));

      return responseContent;
    } catch (e) {
      // Insert error as a system message.
      await db.insertMessage(
        MessagesCompanion.insert(
          id: _uuid.v4(),
          conversationId: conversationId,
          role: 'system',
          content: 'Something went wrong: $e',
          timestamp: DateTime.now(),
        ),
      );
      return 'Error: $e';
    } finally {
      _ref.read(isProcessingProvider.notifier).state = false;
      _ref.read(processingStatusProvider.notifier).state = null;
    }
  }

  /// Create a new conversation (clears active state).
  void createNewConversation() {
    _ref.read(activeConversationProvider.notifier).state = null;
  }

  /// Builds a list of [LlmMessage]s from the conversation history.
  ///
  /// Loads the last [_maxHistoryMessages] messages from the database,
  /// excluding the most recent user message (which is sent separately),
  /// and converts them to [LlmMessage]s for the router agent to use.
  Future<List<LlmMessage>> _buildConversationHistory(
    String conversationId,
  ) async {
    final db = _ref.read(databaseProvider);
    final messages = await db.getMessages(conversationId);

    if (messages.length <= 1) return const [];

    // Exclude the last message (the one we just inserted).
    final prior = messages.length > _maxHistoryMessages + 1
        ? messages.sublist(
            messages.length - _maxHistoryMessages - 1,
            messages.length - 1,
          )
        : messages.sublist(0, messages.length - 1);

    return prior
        .where((m) => m.role == 'user' || m.role == 'agent')
        .map(
          (m) => switch (m.role) {
            'user' => LlmMessage.user(m.content),
            'agent' => LlmMessage.assistant(m.content),
            _ => LlmMessage.user(m.content), // fallback
          },
        )
        .toList();
  }

  /// Handles a [StreamingAgentResponse] by accumulating text deltas and
  /// updating the [streamingTextProvider] in real-time.
  ///
  /// Tool call events are collected and returned alongside the text so that
  /// the caller can execute them via `completeToolCallLoop`.
  /// Catches [LlmStreamException] errors from the stream and appends
  /// the error message to the buffer instead of crashing.
  Future<({String text, List<LlmToolCall> toolCalls})> _handleStream(
    Stream<LlmStreamEvent> events,
  ) async {
    final buffer = StringBuffer();
    final toolCalls = <LlmToolCall>[];
    try {
      await for (final event in events) {
        switch (event) {
          case TextDeltaEvent(:final text):
            // Clear status once real content starts flowing.
            if (buffer.isEmpty) {
              _ref.read(processingStatusProvider.notifier).state = null;
            }
            buffer.write(text);
            _ref.read(streamingTextProvider.notifier).state = buffer.toString();
          case ToolCallEvent(:final call):
            toolCalls.add(call);
          case UsageEvent():
            // Usage events are tracked but don't affect the streamed text.
            break;
          case DoneEvent():
            break;
        }
      }
    } on LlmStreamException catch (e) {
      buffer.write('\n\nError: ${e.message}');
    } catch (e) {
      buffer.write('\n\nUnexpected error: $e');
    }

    _ref.read(streamingTextProvider.notifier).state = null;
    return (text: buffer.toString(), toolCalls: toolCalls);
  }

  /// Deletes a single message by its database ID.
  Future<void> deleteMessage(String messageId) async {
    final db = _ref.read(databaseProvider);
    await (db.delete(db.messages)..where((m) => m.id.equals(messageId))).go();
  }

  /// Generates (or improves) the conversation title after the first exchange.
  ///
  /// This runs as a fire-and-forget task so it doesn't block the chat flow.
  /// Uses the LLM to summarize the first user message and agent response
  /// into a short, descriptive title. Falls back to a text-based heuristic
  /// if no LLM is available.
  Future<void> _maybeGenerateTitle(
    String conversationId,
    String userMessage,
    String agentResponse,
  ) async {
    // Guard against concurrent title generation for the same conversation.
    if (!_pendingTitles.add(conversationId)) return;
    try {
      final db = _ref.read(databaseProvider);

      // Never rename the canonical agent (Kabuk AI) conversation.
      final conv = await db.getConversation(conversationId);
      if (conv?.type == 'agent') return;
      final messages = await db.getMessages(conversationId);
      // Count only user+agent messages (skip tool_call, tool_result, system).
      final mainMessages = messages
          .where((m) => m.role == 'user' || m.role == 'agent')
          .length;
      if (mainMessages > 2) return;

      // Try LLM-based title generation.
      String title;
      try {
        final llm = _ref.read(llmServiceProvider);
        final request = LlmRequest(
          systemPrompt:
              'Generate a short title (max 6 words) for this conversation. '
              'Reply with ONLY the title, no quotes, no punctuation at the end.',
          messages: [
            LlmMessage.user(userMessage),
            LlmMessage.assistant(agentResponse),
          ],
          maxTokens: 20,
          temperature: 0.3,
        );
        final response = await llm.complete(request);
        title = switch (response) {
          TextLlmResponse(:final content) => content.trim(),
          ToolCallsLlmResponse(:final content) => content?.trim() ?? '',
          ErrorLlmResponse() => '',
        };
        // Sanitise: remove wrapping quotes and trailing punctuation.
        if (title.startsWith('"') && title.endsWith('"')) {
          title = title.substring(1, title.length - 1);
        }
        if (title.isEmpty) throw StateError('Empty title');
      } catch (_) {
        // Heuristic fallback: extract first meaningful phrase from user msg.
        title = _heuristicTitle(userMessage);
      }

      // Final fallback if heuristic also returns empty.
      if (title.trim().isEmpty) title = 'Chat ${DateTime.now().toString().substring(0, 16)}';

      // Cap length.
      if (title.length > 60) title = '${title.substring(0, 57)}...';

      await (db.update(db.conversations)
            ..where((c) => c.id.equals(conversationId)))
          .write(ConversationsCompanion(title: Value(title)));
    } catch (_) {
      // Title generation is best-effort; never crash the chat flow.
    } finally {
      _pendingTitles.remove(conversationId);
    }
  }

  /// Heuristic title from user text — first sentence or first N words.
  String _heuristicTitle(String text) {
    // Try first sentence.
    final sentenceEnd = text.indexOf(RegExp(r'[.!?]'));
    if (sentenceEnd > 0 && sentenceEnd < 60) {
      return text.substring(0, sentenceEnd);
    }
    // First 6 words.
    final words = text.split(RegExp(r'\s+'));
    if (words.length <= 6) return text.trim();
    return '${words.take(6).join(' ')}...';
  }
}
