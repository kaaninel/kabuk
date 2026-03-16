import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/domains/note_agent.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late NoteAgent agent;
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
    registerFallbackValue(fakeMutationAction);
  });

  setUp(() {
    agent = NoteAgent();
    bundle = createMockAgentContext();
  });

  // -------------------------------------------------------------------------
  // Agent metadata
  // -------------------------------------------------------------------------

  group('NoteAgent metadata', () {
    test('name is "notes"', () {
      expect(agent.name, 'notes');
    });

    test('description is non-empty', () {
      expect(agent.description, isNotEmpty);
    });

    test('systemPrompt is non-empty', () {
      expect(agent.systemPrompt, isNotEmpty);
    });

    test('declares expected tools', () {
      final toolNames = agent.tools.map((t) => t.name).toList();
      expect(
        toolNames,
        containsAll([
          'create_note',
          'list_notes',
          'search_notes',
          'edit_note',
          'delete_note',
          'get_note',
        ]),
      );
    });

    test(
      'requires knowledgeRead, knowledgeWrite, and llmCall capabilities',
      () {
        expect(
          agent.requiredCapabilities,
          containsAll([
            AgentCapability.knowledgeRead,
            AgentCapability.knowledgeWrite,
            AgentCapability.llmCall,
          ]),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // process() — LLM returns text
  // -------------------------------------------------------------------------

  group('process() with TextLlmResponse', () {
    test('returns text response from LLM', () async {
      stubLlmStreamText(bundle.llm, 'Here are your notes!');

      final message = AgentMessage.user(
        id: 'msg-1',
        timestamp: DateTime.now(),
        content: 'Show my notes',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, 'Here are your notes!');
      verify(() => bundle.llm.stream(any())).called(1);
    });
  });

  // -------------------------------------------------------------------------
  // process() — LLM returns error
  // -------------------------------------------------------------------------

  group('process() with ErrorLlmResponse', () {
    test('returns error response', () async {
      stubLlmStreamError(bundle.llm, 'Rate limited');

      final message = AgentMessage.user(
        id: 'msg-2',
        timestamp: DateTime.now(),
        content: 'Create a note',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      await expectLater(
        (response as StreamingAgentResponse).events,
        emitsError(isA<LlmStreamException>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // process() — empty content
  // -------------------------------------------------------------------------

  group('process() with empty content', () {
    test('returns prompt message for ToolCallMessage', () async {
      final message = AgentMessage.toolCall(
        id: 'msg-3',
        timestamp: DateTime.now(),
        toolName: 'create_note',
        arguments: {},
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<TextAgentResponse>());
      expect((response as TextAgentResponse).content, contains('notes'));
      // LLM should NOT be called when content is empty
      verifyNever(() => bundle.llm.stream(any()));
    });
  });

  // -------------------------------------------------------------------------
  // process() — LLM returns ToolCallsLlmResponse (create_note)
  // -------------------------------------------------------------------------

  group('process() with ToolCallsLlmResponse', () {
    test('executes create_note tool and returns result', () async {
      var callCount = 0;
      // Arrange: first LLM call requests a tool; second returns synthesis.
      when(() => bundle.llm.stream(any())).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          return Stream.fromIterable([
            const LlmStreamEvent.toolCall(
              LlmToolCall(
                id: 'call-1',
                name: 'create_note',
                arguments: {
                  'title': 'My Test Note',
                  'body': 'This is the body',
                  'tags': ['test', 'demo'],
                },
              ),
            ),
            const LlmStreamEvent.done(),
          ]);
        }
        return Stream.fromIterable([
          const LlmStreamEvent.textDelta(
            'Created note "My Test Note" with tags test, demo.',
          ),
          const LlmStreamEvent.done(),
        ]);
      });

      // Arrange: mutate should capture the callback and invoke it
      bundle.knowledge.onMutate = <T>(action) async {
        return await action(FakeMutationContext());
      };

      final message = AgentMessage.user(
        id: 'msg-4',
        timestamp: DateTime.now(),
        content: 'Create a note called My Test Note',
      );

      final response = await agent.process(message, bundle.context);

      // With streaming, tool calls are handled internally.
      // The response is StreamingAgentResponse wrapping the re-prompt text.
      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, contains('My Test Note'));

      // LLM called twice: once for tool dispatch, once for synthesis.
      verify(() => bundle.llm.stream(any())).called(2);
    });

    test('handles unknown tool name gracefully', () async {
      var callCount = 0;
      when(() => bundle.llm.stream(any())).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          return Stream.fromIterable([
            const LlmStreamEvent.toolCall(
              LlmToolCall(
                id: 'call-2',
                name: 'nonexistent_tool',
                arguments: {},
              ),
            ),
            const LlmStreamEvent.done(),
          ]);
        }
        return Stream.fromIterable([
          const LlmStreamEvent.textDelta(
            'Unknown tool "nonexistent_tool" was requested.',
          ),
          const LlmStreamEvent.done(),
        ]);
      });

      final message = AgentMessage.user(
        id: 'msg-5',
        timestamp: DateTime.now(),
        content: 'Do something weird',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, contains('Unknown tool'));
    });
  });

  // -------------------------------------------------------------------------
  // process() — list_notes tool
  // -------------------------------------------------------------------------

  group('list_notes tool', () {
    test('returns "No notes found" when store is empty', () async {
      var callCount = 0;
      when(() => bundle.llm.stream(any())).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          return Stream.fromIterable([
            const LlmStreamEvent.toolCall(
              LlmToolCall(id: 'call-list', name: 'list_notes', arguments: {}),
            ),
            const LlmStreamEvent.done(),
          ]);
        }
        return Stream.fromIterable([
          const LlmStreamEvent.textDelta(
            'No notes found. You can create one if you like.',
          ),
          const LlmStreamEvent.done(),
        ]);
      });

      // Return a mock QueryBuilder that returns empty results
      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(
        () => mockQb.where(any(), equals: any(named: 'equals')),
      ).thenReturn(mockQb);
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(() => mockQb.object(any())).thenReturn(mockQb);
      when(() => mockQb.limit(any())).thenReturn(mockQb);
      when(mockQb.execute).thenAnswer((_) async => <Triple>[]);

      final message = AgentMessage.user(
        id: 'msg-6',
        timestamp: DateTime.now(),
        content: 'List my notes',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, contains('No notes found'));
    });
  });

  // -------------------------------------------------------------------------
  // Tool schema validation
  // -------------------------------------------------------------------------

  group('tool schemas', () {
    test('create_note has required title and body parameters', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'create_note');
      final params = tool.parameters;
      expect(params['required'], containsAll(['title', 'body']));
      final props = params['properties'] as Map<String, dynamic>;
      expect(props, contains('title'));
      expect(props, contains('body'));
      expect(props, contains('tags'));
    });

    test('search_notes requires query parameter', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'search_notes');
      expect(tool.parameters['required'], contains('query'));
    });

    test('toFunctionSchema produces valid structure', () {
      final tool = agent.tools.first;
      final schema = tool.toFunctionSchema();
      expect(schema['type'], 'function');
      final fn = schema['function'] as Map<String, dynamic>;
      expect(fn, contains('name'));
      expect(fn, contains('description'));
      expect(fn, contains('parameters'));
    });
  });
}
