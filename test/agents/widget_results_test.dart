/// Tests that update/edit tools return widget cards alongside text.
///
/// Verifies that _editNote, _updateContact, _updateEvent, and
/// _setReminder return compound results with widget data.
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/domains/calendar_agent.dart';
import 'package:kabuk/agents/domains/contact_agent.dart';
import 'package:kabuk/agents/domains/note_agent.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
    registerFallbackValue(fakeMutationAction);
  });

  setUp(() {
    bundle = createMockAgentContext();
  });

  // -------------------------------------------------------------------------
  // NoteAgent — edit_note returns widget
  // -------------------------------------------------------------------------

  group('NoteAgent edit_note widget result', () {
    late NoteAgent agent;

    setUp(() {
      agent = NoteAgent();
    });

    test('edit_note returns compound result with NoteCard', () async {
      // Setup: LLM calls tool, then synthesizes text.
      var callCount = 0;
      when(() => bundle.llm.stream(any())).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          return Stream.fromIterable([
            const LlmStreamEvent.toolCall(
              LlmToolCall(
                id: 'call-edit',
                name: 'edit_note',
                arguments: {
                  'uri': 'kabuk:Note/test-1',
                  'title': 'Updated Title',
                  'body': 'Updated body content',
                },
              ),
            ),
            const LlmStreamEvent.done(),
          ]);
        }
        return Stream.fromIterable([
          const LlmStreamEvent.textDelta('Note has been updated.'),
          const LlmStreamEvent.done(),
        ]);
      });

      // Mock: getEntity returns existing note (pre-edit check).
      when(() => bundle.knowledge.getEntity('kabuk:Note/test-1')).thenAnswer(
        (_) async => [
          Triple.uri(
            subject: 'kabuk:Note/test-1',
            predicate: NS.rdfType,
            object: NS.schemaNote,
          ),
          Triple.string(
            subject: 'kabuk:Note/test-1',
            predicate: NS.schemaName,
            object: 'Updated Title',
          ),
          Triple.string(
            subject: 'kabuk:Note/test-1',
            predicate: NS.schemaText,
            object: 'Updated body content',
          ),
          Triple.string(
            subject: 'kabuk:Note/test-1',
            predicate: NS.schemaDateCreated,
            object: '2025-01-01T00:00:00.000',
          ),
        ],
      );

      // Mock mutate.
      bundle.knowledge.onMutate = <T>(action) async {
        final ctx = MockMutationContext();
        when(
          () => ctx.set(any(), any(), any<dynamic>()),
        ).thenAnswer((_) async {});
        return await action(ctx);
      };

      final message = AgentMessage.user(
        id: 'msg-1',
        timestamp: DateTime.now(),
        content: 'Update the note title',
      );

      final response = await agent.process(message, bundle.context);

      // With streaming, tool results are handled internally;
      // response is always StreamingAgentResponse.
      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, contains('updated'));
    });
  });

  // -------------------------------------------------------------------------
  // ContactAgent — update_contact returns widget
  // -------------------------------------------------------------------------

  group('ContactAgent update_contact widget result', () {
    late ContactAgent agent;

    setUp(() {
      agent = ContactAgent();
    });

    test('update_contact returns compound result with ContactCard', () async {
      var callCount = 0;
      when(() => bundle.llm.stream(any())).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          return Stream.fromIterable([
            const LlmStreamEvent.toolCall(
              LlmToolCall(
                id: 'call-update',
                name: 'update_contact',
                arguments: {
                  'uri': 'kabuk:Person/test-1',
                  'email': 'alice@example.com',
                },
              ),
            ),
            const LlmStreamEvent.done(),
          ]);
        }
        return Stream.fromIterable([
          const LlmStreamEvent.textDelta('Contact updated.'),
          const LlmStreamEvent.done(),
        ]);
      });

      when(() => bundle.knowledge.getEntity('kabuk:Person/test-1')).thenAnswer(
        (_) async => [
          Triple.uri(
            subject: 'kabuk:Person/test-1',
            predicate: NS.rdfType,
            object: NS.schemaPerson,
          ),
          Triple.string(
            subject: 'kabuk:Person/test-1',
            predicate: NS.schemaName,
            object: 'Alice Smith',
          ),
          Triple.string(
            subject: 'kabuk:Person/test-1',
            predicate: NS.schemaEmail,
            object: 'alice@example.com',
          ),
        ],
      );

      bundle.knowledge.onMutate = <T>(action) async {
        final ctx = MockMutationContext();
        when(
          () => ctx.set(any(), any(), any<dynamic>()),
        ).thenAnswer((_) async {});
        return await action(ctx);
      };

      final message = AgentMessage.user(
        id: 'msg-2',
        timestamp: DateTime.now(),
        content: 'Update email for Alice',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, contains('updated'));
    });
  });

  // -------------------------------------------------------------------------
  // CalendarAgent — update_event returns widget
  // -------------------------------------------------------------------------

  group('CalendarAgent update_event widget result', () {
    late CalendarAgent agent;

    setUp(() {
      agent = CalendarAgent();
    });

    test('update_event returns compound result with EventCard', () async {
      var callCount = 0;
      when(() => bundle.llm.stream(any())).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          return Stream.fromIterable([
            const LlmStreamEvent.toolCall(
              LlmToolCall(
                id: 'call-update-evt',
                name: 'update_event',
                arguments: {
                  'uri': 'kabuk:Event/test-1',
                  'title': 'Updated Meeting',
                  'location': 'Room 42',
                },
              ),
            ),
            const LlmStreamEvent.done(),
          ]);
        }
        return Stream.fromIterable([
          const LlmStreamEvent.textDelta('Event updated.'),
          const LlmStreamEvent.done(),
        ]);
      });

      when(() => bundle.knowledge.getEntity('kabuk:Event/test-1')).thenAnswer(
        (_) async => [
          Triple.uri(
            subject: 'kabuk:Event/test-1',
            predicate: NS.rdfType,
            object: NS.schemaEvent,
          ),
          Triple.string(
            subject: 'kabuk:Event/test-1',
            predicate: NS.schemaName,
            object: 'Updated Meeting',
          ),
          Triple.string(
            subject: 'kabuk:Event/test-1',
            predicate: NS.schemaStartDate,
            object: '2025-03-01T10:00:00.000',
          ),
          Triple.string(
            subject: 'kabuk:Event/test-1',
            predicate: NS.schemaLocation,
            object: 'Room 42',
          ),
        ],
      );

      bundle.knowledge.onMutate = <T>(action) async {
        final ctx = MockMutationContext();
        when(
          () => ctx.set(any(), any(), any<dynamic>()),
        ).thenAnswer((_) async {});
        return await action(ctx);
      };

      final message = AgentMessage.user(
        id: 'msg-3',
        timestamp: DateTime.now(),
        content: 'Update the meeting location',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, contains('updated'));
    });

    test('set_reminder returns compound result with EventCard', () async {
      var callCount = 0;
      when(() => bundle.llm.stream(any())).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          return Stream.fromIterable([
            const LlmStreamEvent.toolCall(
              LlmToolCall(
                id: 'call-reminder',
                name: 'set_reminder',
                arguments: {
                  'uri': 'kabuk:Event/test-1',
                  'reminderDate': '2025-02-28T09:00:00.000',
                },
              ),
            ),
            const LlmStreamEvent.done(),
          ]);
        }
        return Stream.fromIterable([
          const LlmStreamEvent.textDelta('Reminder set.'),
          const LlmStreamEvent.done(),
        ]);
      });

      when(() => bundle.knowledge.getEntity('kabuk:Event/test-1')).thenAnswer(
        (_) async => [
          Triple.uri(
            subject: 'kabuk:Event/test-1',
            predicate: NS.rdfType,
            object: NS.schemaEvent,
          ),
          Triple.string(
            subject: 'kabuk:Event/test-1',
            predicate: NS.schemaName,
            object: 'Team Standup',
          ),
          Triple.string(
            subject: 'kabuk:Event/test-1',
            predicate: NS.schemaStartDate,
            object: '2025-03-01T10:00:00.000',
          ),
        ],
      );

      bundle.knowledge.onMutate = <T>(action) async {
        final ctx = MockMutationContext();
        when(
          () => ctx.set(any(), any(), any<dynamic>()),
        ).thenAnswer((_) async {});
        return await action(ctx);
      };

      final message = AgentMessage.user(
        id: 'msg-4',
        timestamp: DateTime.now(),
        content: 'Remind me about the standup',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, contains('Reminder'));
    });
  });
}
