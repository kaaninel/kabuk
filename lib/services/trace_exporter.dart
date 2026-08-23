/// Conversation trace export — turn agent conversations into finetuning data.
///
/// Kabuk's on-device model (MiniCPM5 1B) is trained by the user over time.
/// This exporter replays real conversations into ShareGPT/OpenAI-format
/// JSONL (one conversation per line, `{"messages": [...]}`) so they can be
/// fed into a larger model for distillation/RL and later finetuned back
/// into the 1B. Tool calls are preserved in the OpenAI function-calling
/// message format.
library;

import 'dart:convert';
import 'dart:io';

import 'package:kabuk/knowledge/database.dart';
import 'package:path_provider/path_provider.dart';

/// A single message in a conversation trace.
///
/// Lightweight and DB-independent so the format builder is pure and
/// testable; maps 1:1 to the stored chat [Message] rows.
class TraceEntry {
  /// Creates a [TraceEntry].
  const TraceEntry({
    required this.role,
    required this.content,
    this.agentName,
    this.toolName,
    this.toolArgs,
    this.timestamp,
  });

  /// Role: `user`, `agent`, `system`, `tool_call`, or `tool_result`.
  final String role;

  /// Message text content.
  final String content;

  /// The agent that produced this message (agent/tool messages).
  final String? agentName;

  /// Tool name for `tool_call`/`tool_result` entries.
  final String? toolName;

  /// Parsed tool arguments for `tool_call` entries.
  final Map<String, dynamic>? toolArgs;

  /// When the message occurred.
  final DateTime? timestamp;

  /// Maps a stored chat [Message] row to a [TraceEntry].
  factory TraceEntry.fromMessage(Message message) {
    Map<String, dynamic>? metadata;
    try {
      final raw = message.metadata;
      if (raw != null && raw.isNotEmpty) {
        metadata = jsonDecode(raw) as Map<String, dynamic>;
      }
    } on Object {
      metadata = null;
    }

    return TraceEntry(
      role: message.role,
      content: message.content,
      agentName: message.agentName,
      toolName: metadata?['tool'] as String?,
      toolArgs: metadata?['args'] as Map<String, dynamic>?,
      timestamp: message.timestamp,
    );
  }
}

/// Exports agent conversations to finetuning-ready JSONL.
class TraceExporter {
  /// Creates a [TraceExporter] backed by [db].
  TraceExporter({required this.db});

  /// The chat database to read conversations from.
  final KabukDatabase db;

  /// Builds an OpenAI-format messages array from [entries].
  ///
  /// - `user`/`agent`/`system` → user/assistant/system roles.
  /// - `tool_call` → assistant message with a `tool_calls` entry.
  /// - `tool_result` → `tool` role message referencing the prior call.
  ///
  /// Returns a list of message maps ready to be embedded in
  /// `{"messages": [...]}`. Pure function — no DB access — so it can be
  /// unit-tested without a database.
  static List<Map<String, dynamic>> buildMessages(List<TraceEntry> entries) {
    final messages = <Map<String, dynamic>>[];
    final pendingCalls = <Map<String, dynamic>>[];
    var callCounter = 0;

    for (final entry in entries) {
      switch (entry.role) {
        case 'user':
          messages.add({'role': 'user', 'content': entry.content});
        case 'agent':
          messages.add({'role': 'assistant', 'content': entry.content});
        case 'system':
          messages.add({'role': 'system', 'content': entry.content});
        case 'tool_call':
          final id = 'call_${callCounter++}';
          pendingCalls.add({
            'id': id,
            'type': 'function',
            'function': {
              'name': entry.toolName ?? 'tool',
              'arguments': entry.toolArgs ?? <String, dynamic>{},
            },
          });
        case 'tool_result':
          if (pendingCalls.isNotEmpty) {
            final call = pendingCalls.removeAt(0);
            messages.add({
              'role': 'assistant',
              'content': '',
              'tool_calls': [call],
            });
            messages.add({
              'role': 'tool',
              'tool_call_id': call['id'],
              'content': entry.content,
            });
          }
      }
    }
    return messages;
  }

  /// Builds one ShareGPT JSONL line for a conversation.
  ///
  /// Returns `null` if the conversation has no user/agent content worth
  /// training on.
  Future<String?> exportConversation(String conversationId) async {
    final rows = await db.getMessages(conversationId);
    final entries = rows.map(TraceEntry.fromMessage).toList();
    final messages = buildMessages(entries);
    if (messages.isEmpty) return null;
    return jsonEncode({'messages': messages});
  }

  /// Exports every agent conversation into one JSONL document (one line
  /// per conversation).
  Future<String> exportAll() async {
    final conversations = await db.listConversations();
    final buffer = StringBuffer();
    for (final conv in conversations.where((c) => c.type == 'agent')) {
      final line = await exportConversation(conv.id);
      if (line != null) {
        buffer.writeln(line);
      }
    }
    return buffer.toString();
  }

  /// Writes [content] into the app's `traces/` directory and returns the
  /// resulting [File].
  Future<File> writeTrace(String content, String name) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/traces');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$name');
    await file.writeAsString(content, flush: true);
    return file;
  }
}