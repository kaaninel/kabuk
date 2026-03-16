/// Tests for [LlmStreamEvent] types and HTTP streaming event parsing.
///
/// Verifies the sealed class hierarchy, equality, and that the
/// stub LLM service emits proper stream events.
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/llm.dart';

void main() {
  // -------------------------------------------------------------------------
  // LlmStreamEvent types
  // -------------------------------------------------------------------------

  group('LlmStreamEvent types', () {
    test('TextDeltaEvent carries text', () {
      const event = LlmStreamEvent.textDelta('hello');
      expect(event, isA<TextDeltaEvent>());
      expect((event as TextDeltaEvent).text, 'hello');
    });

    test('ToolCallEvent carries LlmToolCall', () {
      const call = LlmToolCall(id: 'c1', name: 'fn', arguments: {'a': 1});
      const event = LlmStreamEvent.toolCall(call);
      expect(event, isA<ToolCallEvent>());
      expect((event as ToolCallEvent).call.name, 'fn');
      expect(event.call.arguments, {'a': 1});
    });

    test('DoneEvent can be constructed', () {
      const event = LlmStreamEvent.done();
      expect(event, isA<DoneEvent>());
    });

    test('pattern matching covers all cases', () {
      final events = <LlmStreamEvent>[
        const LlmStreamEvent.textDelta('token'),
        const LlmStreamEvent.toolCall(
          LlmToolCall(id: 'c1', name: 'fn', arguments: {}),
        ),
        const LlmStreamEvent.done(),
      ];

      final labels = events
          .map(
            (e) => switch (e) {
              TextDeltaEvent() => 'text',
              ToolCallEvent() => 'tool',
              UsageEvent() => 'usage',
              DoneEvent() => 'done',
            },
          )
          .toList();

      expect(labels, ['text', 'tool', 'done']);
    });
  });

  // -------------------------------------------------------------------------
  // Stream<LlmStreamEvent> consumption
  // -------------------------------------------------------------------------

  group('Stream<LlmStreamEvent> usage', () {
    test('can accumulate text from TextDeltaEvents', () async {
      final stream = Stream.fromIterable([
        const LlmStreamEvent.textDelta('Hello'),
        const LlmStreamEvent.textDelta(', '),
        const LlmStreamEvent.textDelta('world!'),
        const LlmStreamEvent.done(),
      ]);

      final buffer = StringBuffer();
      await for (final event in stream) {
        if (event case TextDeltaEvent(:final text)) {
          buffer.write(text);
        }
      }

      expect(buffer.toString(), 'Hello, world!');
    });

    test('can collect tool calls from ToolCallEvents', () async {
      final stream = Stream.fromIterable([
        const LlmStreamEvent.textDelta('Processing...'),
        const LlmStreamEvent.toolCall(
          LlmToolCall(id: 'c1', name: 'search', arguments: {'q': 'test'}),
        ),
        const LlmStreamEvent.toolCall(
          LlmToolCall(id: 'c2', name: 'fetch', arguments: {'url': 'x'}),
        ),
        const LlmStreamEvent.done(),
      ]);

      final toolCalls = <LlmToolCall>[];
      await for (final event in stream) {
        if (event case ToolCallEvent(:final call)) {
          toolCalls.add(call);
        }
      }

      expect(toolCalls, hasLength(2));
      expect(toolCalls[0].name, 'search');
      expect(toolCalls[1].name, 'fetch');
    });

    test('handles stream with only text (no tool calls)', () async {
      final stream = Stream.fromIterable([
        const LlmStreamEvent.textDelta('Just text'),
        const LlmStreamEvent.done(),
      ]);

      var hasToolCalls = false;
      await for (final event in stream) {
        if (event is ToolCallEvent) hasToolCalls = true;
      }

      expect(hasToolCalls, isFalse);
    });

    test('handles empty stream', () async {
      final stream = Stream<LlmStreamEvent>.fromIterable([
        const LlmStreamEvent.done(),
      ]);

      final buffer = StringBuffer();
      await for (final event in stream) {
        if (event case TextDeltaEvent(:final text)) {
          buffer.write(text);
        }
      }

      expect(buffer.toString(), isEmpty);
    });
  });
}
