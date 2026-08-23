import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/services/trace_exporter.dart';

void main() {
  TraceEntry user(String c) => TraceEntry(role: 'user', content: c);
  TraceEntry agent(String c) => TraceEntry(role: 'agent', content: c);
  TraceEntry toolCall(String name, [Map<String, dynamic>? args]) =>
      TraceEntry(
        role: 'tool_call',
        content: 'Calling $name…',
        toolName: name,
        toolArgs: args ?? const {},
      );
  TraceEntry toolResult(String c) =>
      TraceEntry(role: 'tool_result', content: c);

  group('TraceExporter.buildMessages', () {
    test('maps user and agent messages to roles', () {
      final messages = TraceExporter.buildMessages([
        user('hello'),
        agent('hi there'),
      ]);

      expect(messages, [
        {'role': 'user', 'content': 'hello'},
        {'role': 'assistant', 'content': 'hi there'},
      ]);
    });

    test('preserves system messages', () {
      final messages = TraceExporter.buildMessages([
        const TraceEntry(role: 'system', content: 'You are Kabuk.'),
        user('hello'),
      ]);

      expect(messages.first['role'], 'system');
      expect(messages.first['content'], 'You are Kabuk.');
    });

    test('collapses tool calls into assistant tool_calls + tool results',
        () {
      final messages = TraceExporter.buildMessages([
        user('search #flutter'),
        toolCall('search_nostr_hashtag', {'hashtags': ['flutter']}),
        toolResult('Found 3 posts.'),
        agent('Here are the posts.'),
      ]);

      expect(messages, hasLength(4));
      expect(messages[0]['role'], 'user');
      expect(messages[1]['role'], 'assistant');
      expect(messages[1]['tool_calls'], hasLength(1));
      final call = (messages[1]['tool_calls'] as List).first
          as Map<String, dynamic>;
      expect(call['type'], 'function');
      expect(
        (call['function'] as Map<String, dynamic>)['name'],
        'search_nostr_hashtag',
      );
      expect(messages[2]['role'], 'tool');
      expect(messages[2]['tool_call_id'], call['id']);
      expect(messages[2]['content'], 'Found 3 posts.');
      expect(messages[3]['role'], 'assistant');
      expect(messages[3]['content'], 'Here are the posts.');
    });

    test('pairs multiple sequential tool calls', () {
      final messages = TraceExporter.buildMessages([
        user('plan trip'),
        toolCall('search_local', {'query': 'museums'}),
        toolResult('2 results'),
        toolCall('search_local', {'query': 'restaurants'}),
        toolResult('5 results'),
        agent('Done.'),
      ]);

      final toolCalls = messages
          .where((m) => m['role'] == 'assistant' && m.containsKey('tool_calls'))
          .toList();
      expect(toolCalls, hasLength(2));
      expect(
        ((toolCalls[1]['tool_calls'] as List).first
            as Map<String, dynamic>)['id'],
        'call_1',
      );
    });

    test('drops tool results that have no preceding tool call', () {
      final messages = TraceExporter.buildMessages([
        user('hi'),
        toolResult('orphan'),
        agent('ok'),
      ]);

      expect(messages.where((m) => m['role'] == 'tool'), isEmpty);
    });
  });

  test('ShareGPT line is JSON with exactly a messages array', () {
    final line = jsonEncode({
      'messages': [
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'hello'},
      ],
    });
    final decoded = jsonDecode(line) as Map<String, dynamic>;
    expect(decoded.keys, ['messages']);
    expect(decoded['messages'], hasLength(2));
  });
}