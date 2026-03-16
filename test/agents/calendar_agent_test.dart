import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/domains/calendar_agent.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late CalendarAgent agent;
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
    registerFallbackValue(fakeMutationAction);
  });

  setUp(() {
    agent = CalendarAgent();
    bundle = createMockAgentContext();
  });

  // ---------------------------------------------------------------------------
  // Agent metadata
  // ---------------------------------------------------------------------------

  group('CalendarAgent metadata', () {
    test('name is "calendar"', () {
      expect(agent.name, 'calendar');
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
          'create_event',
          'list_events',
          'search_events',
          'update_event',
          'set_reminder',
          'delete_event',
          'get_event',
        ]),
      );
    });

    test('requires knowledgeRead, knowledgeWrite, and llmCall', () {
      expect(
        agent.requiredCapabilities,
        containsAll([
          AgentCapability.knowledgeRead,
          AgentCapability.knowledgeWrite,
          AgentCapability.llmCall,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // process() — LLM paths
  // ---------------------------------------------------------------------------

  group('process() with TextLlmResponse', () {
    test('returns text response from LLM', () async {
      stubLlmStreamText(bundle.llm, 'Here are your events!');

      final message = AgentMessage.user(
        id: 'msg-1',
        timestamp: DateTime.now(),
        content: 'Show my calendar',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, 'Here are your events!');
      verify(() => bundle.llm.stream(any())).called(1);
    });
  });

  group('process() with ErrorLlmResponse', () {
    test('returns error response', () async {
      stubLlmStreamError(bundle.llm, 'Rate limited');

      final message = AgentMessage.user(
        id: 'msg-2',
        timestamp: DateTime.now(),
        content: 'Create event',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      await expectLater(
        (response as StreamingAgentResponse).events,
        emitsError(isA<LlmStreamException>()),
      );
    });
  });

  group('process() with empty content', () {
    test('returns prompt for non-user message', () async {
      final message = AgentMessage.toolCall(
        id: 'msg-3',
        timestamp: DateTime.now(),
        toolName: 'create_event',
        arguments: {},
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<TextAgentResponse>());
      expect((response as TextAgentResponse).content, contains('calendar'));
      verifyNever(() => bundle.llm.stream(any()));
    });
  });

  // ---------------------------------------------------------------------------
  // create_event tool
  // ---------------------------------------------------------------------------

  group('create_event tool', () {
    test('creates event with required fields', () async {
      bundle.knowledge.onMutate = <T>(action) async {
        return await action(FakeMutationContext());
      };

      // Stub getEntity for the re-read after creation
      when(() => bundle.knowledge.getEntity(any())).thenAnswer(
        (_) async => [
          const Triple(
            subject: 'kabuk:Event/test-uuid',
            predicate: NS.schemaName,
            objectValue: 'Team Standup',
            objectType: ObjectType.string,
          ),
          const Triple(
            subject: 'kabuk:Event/test-uuid',
            predicate: NS.schemaStartDate,
            objectValue: '2025-01-15T10:00:00',
            objectType: ObjectType.string,
          ),
        ],
      );

      final tool = agent.tools.firstWhere((t) => t.name == 'create_event');
      final result = await tool.execute({
        'title': 'Team Standup',
        'startDate': '2025-01-15T10:00:00',
      }, bundle.context);

      // create_event returns a compound result with text + widget
      expect(result, isA<CompoundToolResult>());
      final compound = result as CompoundToolResult;
      expect(compound.results.length, 2);
      expect(compound.results[0], isA<TextToolResult>());
      expect(
        (compound.results[0] as TextToolResult).content,
        contains('Team Standup'),
      );
      expect(compound.results[1], isA<WidgetToolResult>());
      expect(bundle.knowledge.mutateCallCount, 1);
    });

    test('requires title parameter', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'create_event');
      expect(tool.parameters['required'], containsAll(['title', 'startDate']));
    });
  });

  // ---------------------------------------------------------------------------
  // list_events tool
  // ---------------------------------------------------------------------------

  group('list_events tool', () {
    test('returns "No events found" when store is empty', () async {
      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(() => mockQb.object(any())).thenReturn(mockQb);
      when(() => mockQb.limit(any())).thenReturn(mockQb);
      when(mockQb.execute).thenAnswer((_) async => <Triple>[]);

      final tool = agent.tools.firstWhere((t) => t.name == 'list_events');
      final result = await tool.execute({}, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('No events'));
    });

    test('returns formatted events when found', () async {
      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(() => mockQb.object(any())).thenReturn(mockQb);
      when(() => mockQb.limit(any())).thenReturn(mockQb);
      when(mockQb.execute).thenAnswer(
        (_) async => [
          const Triple(
            subject: 'kabuk:Event/1',
            predicate: NS.rdfType,
            objectValue: NS.schemaEvent,
            objectType: ObjectType.uri,
          ),
        ],
      );

      when(() => bundle.knowledge.getEntities(any())).thenAnswer(
        (_) async => {
          'kabuk:Event/1': [
            const Triple(
              subject: 'kabuk:Event/1',
              predicate: NS.schemaName,
              objectValue: 'Meeting',
              objectType: ObjectType.string,
            ),
            const Triple(
              subject: 'kabuk:Event/1',
              predicate: NS.schemaStartDate,
              objectValue: '2025-01-15T10:00:00',
              objectType: ObjectType.string,
            ),
          ],
        },
      );

      final tool = agent.tools.firstWhere((t) => t.name == 'list_events');
      final result = await tool.execute({}, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('Meeting'));
    });
  });

  // ---------------------------------------------------------------------------
  // search_events tool
  // ---------------------------------------------------------------------------

  group('search_events tool', () {
    test('returns error for empty query', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'search_events');
      final result = await tool.execute({'query': ''}, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });

    test('returns "No events found" when no matches', () async {
      when(
        () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
      ).thenAnswer((_) async => <Triple>[]);

      when(
        () => bundle.knowledge.getEntities(any()),
      ).thenAnswer((_) async => <String, List<Triple>>{});

      final tool = agent.tools.firstWhere((t) => t.name == 'search_events');
      final result = await tool.execute({'query': 'meeting'}, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('No events'));
    });

    test('filters results to Event type only', () async {
      when(
        () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
      ).thenAnswer(
        (_) async => [
          const Triple(
            subject: 'kabuk:Event/1',
            predicate: NS.schemaName,
            objectValue: 'Meeting',
            objectType: ObjectType.string,
          ),
          const Triple(
            subject: 'kabuk:Note/2',
            predicate: NS.schemaName,
            objectValue: 'Note about meeting',
            objectType: ObjectType.string,
          ),
        ],
      );

      when(() => bundle.knowledge.getEntities(any())).thenAnswer(
        (_) async => {
          'kabuk:Event/1': [
            const Triple(
              subject: 'kabuk:Event/1',
              predicate: NS.rdfType,
              objectValue: NS.schemaEvent,
              objectType: ObjectType.uri,
            ),
            const Triple(
              subject: 'kabuk:Event/1',
              predicate: NS.schemaName,
              objectValue: 'Meeting',
              objectType: ObjectType.string,
            ),
          ],
          'kabuk:Note/2': [
            const Triple(
              subject: 'kabuk:Note/2',
              predicate: NS.rdfType,
              objectValue: NS.schemaNote,
              objectType: ObjectType.uri,
            ),
          ],
        },
      );

      final tool = agent.tools.firstWhere((t) => t.name == 'search_events');
      final result = await tool.execute({'query': 'meeting'}, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      // Should only include the Event, not the Note.
      expect(text, contains('Meeting'));
    });
  });

  // ---------------------------------------------------------------------------
  // get_event tool
  // ---------------------------------------------------------------------------

  group('get_event tool', () {
    test('returns error for missing uri', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'get_event');
      final result = await tool.execute({'uri': ''}, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });

    test('returns compound result with widget for valid event', () async {
      when(() => bundle.knowledge.getEntity(any())).thenAnswer(
        (_) async => [
          const Triple(
            subject: 'kabuk:Event/1',
            predicate: NS.schemaName,
            objectValue: 'Team Standup',
            objectType: ObjectType.string,
          ),
          const Triple(
            subject: 'kabuk:Event/1',
            predicate: NS.schemaStartDate,
            objectValue: '2025-01-15T10:00:00',
            objectType: ObjectType.string,
          ),
        ],
      );

      final tool = agent.tools.firstWhere((t) => t.name == 'get_event');
      final result = await tool.execute({
        'uri': 'kabuk:Event/1',
      }, bundle.context);

      expect(result, isA<CompoundToolResult>());
      final compound = result as CompoundToolResult;
      expect(compound.results.any((r) => r is WidgetToolResult), isTrue);
      final widgetResult = compound.results.whereType<WidgetToolResult>().first;
      expect(widgetResult.library, 'kabuk:calendar');
      expect(widgetResult.widget, 'EventCard');
    });

    test('returns error when event not found', () async {
      when(
        () => bundle.knowledge.getEntity(any()),
      ).thenAnswer((_) async => <Triple>[]);

      final tool = agent.tools.firstWhere((t) => t.name == 'get_event');
      final result = await tool.execute({
        'uri': 'kabuk:Event/nonexistent',
      }, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });
  });

  // ---------------------------------------------------------------------------
  // delete_event tool
  // ---------------------------------------------------------------------------

  group('delete_event tool', () {
    test('returns error for missing uri', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'delete_event');
      final result = await tool.execute({'uri': ''}, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });

    test('deletes event and returns confirmation', () async {
      when(() => bundle.knowledge.getEntity(any())).thenAnswer(
        (_) async => [
          const Triple(
            subject: 'kabuk:Event/1',
            predicate: NS.schemaName,
            objectValue: 'Old Event',
            objectType: ObjectType.string,
          ),
        ],
      );

      bundle.knowledge.onMutate = <T>(action) async {
        return await action(FakeMutationContext());
      };

      final tool = agent.tools.firstWhere((t) => t.name == 'delete_event');
      final result = await tool.execute({
        'uri': 'kabuk:Event/1',
      }, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('delete'));
    });
  });

  // ---------------------------------------------------------------------------
  // Tool schema validation
  // ---------------------------------------------------------------------------

  group('tool schemas', () {
    test('create_event requires title and startDate', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'create_event');
      expect(tool.parameters['required'], containsAll(['title', 'startDate']));
    });

    test('search_events requires query', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'search_events');
      expect(tool.parameters['required'], contains('query'));
    });

    test('update_event requires uri', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'update_event');
      expect(tool.parameters['required'], contains('uri'));
    });

    test('set_reminder requires uri and reminderDate', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'set_reminder');
      expect(tool.parameters['required'], containsAll(['uri', 'reminderDate']));
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

  // ---------------------------------------------------------------------------
  // process() — error handling
  // ---------------------------------------------------------------------------

  group('process() error handling', () {
    test('returns error when LLM throws', () async {
      when(
        () => bundle.llm.stream(any()),
      ).thenThrow(Exception('Connection failed'));

      final message = AgentMessage.user(
        id: 'msg-err',
        timestamp: DateTime.now(),
        content: 'Create an event',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      await expectLater(
        (response as StreamingAgentResponse).events,
        emitsError(isA<Exception>()),
      );
    });
  });
}
