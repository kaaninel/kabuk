import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/domains/contact_agent.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late ContactAgent agent;
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
    registerFallbackValue(fakeMutationAction);
  });

  setUp(() {
    agent = ContactAgent();
    bundle = createMockAgentContext();
  });

  // ---------------------------------------------------------------------------
  // Agent metadata
  // ---------------------------------------------------------------------------

  group('ContactAgent metadata', () {
    test('name is "contacts"', () {
      expect(agent.name, 'contacts');
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
          'create_contact',
          'list_contacts',
          'search_contacts',
          'get_contact',
          'update_contact',
          'delete_contact',
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
      stubLlmStreamText(bundle.llm, 'I can help with contacts!');

      final message = AgentMessage.user(
        id: 'msg-1',
        timestamp: DateTime.now(),
        content: 'Show my contacts',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, 'I can help with contacts!');
      verify(() => bundle.llm.stream(any())).called(1);
    });
  });

  group('process() with ErrorLlmResponse', () {
    test('returns error response', () async {
      stubLlmStreamError(bundle.llm, 'API error');

      final message = AgentMessage.user(
        id: 'msg-2',
        timestamp: DateTime.now(),
        content: 'Add a contact',
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
        toolName: 'create_contact',
        arguments: {},
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<TextAgentResponse>());
      expect((response as TextAgentResponse).content, contains('contacts'));
      verifyNever(() => bundle.llm.stream(any()));
    });
  });

  // ---------------------------------------------------------------------------
  // create_contact tool
  // ---------------------------------------------------------------------------

  group('create_contact tool', () {
    test('creates contact with name', () async {
      bundle.knowledge.onMutate = <T>(action) async {
        return await action(FakeMutationContext());
      };

      when(() => bundle.knowledge.getEntity(any())).thenAnswer(
        (_) async => [
          const Triple(
            subject: 'kabuk:Person/test-uuid',
            predicate: NS.schemaName,
            objectValue: 'Alice Smith',
            objectType: ObjectType.string,
          ),
        ],
      );

      final tool = agent.tools.firstWhere((t) => t.name == 'create_contact');
      final result = await tool.execute({
        'name': 'Alice Smith',
      }, bundle.context);

      expect(result, isA<CompoundToolResult>());
      final compound = result as CompoundToolResult;
      expect(compound.results.any((r) => r is TextToolResult), isTrue);
      expect(compound.results.any((r) => r is WidgetToolResult), isTrue);

      final widgetResult = compound.results.whereType<WidgetToolResult>().first;
      expect(widgetResult.library, 'kabuk:contacts');
      expect(widgetResult.widget, 'ContactCard');
      expect(bundle.knowledge.mutateCallCount, 1);
    });

    test('requires name parameter', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'create_contact');
      expect(tool.parameters['required'], contains('name'));
    });
  });

  // ---------------------------------------------------------------------------
  // list_contacts tool
  // ---------------------------------------------------------------------------

  group('list_contacts tool', () {
    test('returns "No contacts" when store is empty', () async {
      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(() => mockQb.object(any())).thenReturn(mockQb);
      when(() => mockQb.limit(any())).thenReturn(mockQb);
      when(mockQb.execute).thenAnswer((_) async => <Triple>[]);

      final tool = agent.tools.firstWhere((t) => t.name == 'list_contacts');
      final result = await tool.execute({}, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('No contacts'));
    });

    test('returns formatted contacts when found', () async {
      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(() => mockQb.object(any())).thenReturn(mockQb);
      when(() => mockQb.limit(any())).thenReturn(mockQb);
      when(mockQb.execute).thenAnswer(
        (_) async => [
          const Triple(
            subject: 'kabuk:Person/1',
            predicate: NS.rdfType,
            objectValue: NS.schemaPerson,
            objectType: ObjectType.uri,
          ),
        ],
      );

      when(() => bundle.knowledge.getEntities(any())).thenAnswer(
        (_) async => {
          'kabuk:Person/1': [
            const Triple(
              subject: 'kabuk:Person/1',
              predicate: NS.schemaName,
              objectValue: 'Bob',
              objectType: ObjectType.string,
            ),
            const Triple(
              subject: 'kabuk:Person/1',
              predicate: NS.schemaEmail,
              objectValue: 'bob@example.com',
              objectType: ObjectType.string,
            ),
          ],
        },
      );

      final tool = agent.tools.firstWhere((t) => t.name == 'list_contacts');
      final result = await tool.execute({}, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('Bob'));
    });
  });

  // ---------------------------------------------------------------------------
  // search_contacts tool
  // ---------------------------------------------------------------------------

  group('search_contacts tool', () {
    test('returns error for empty query', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'search_contacts');
      final result = await tool.execute({'query': ''}, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });

    test('returns "No contacts found" when no matches', () async {
      when(
        () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
      ).thenAnswer((_) async => <Triple>[]);

      when(
        () => bundle.knowledge.getEntities(any()),
      ).thenAnswer((_) async => <String, List<Triple>>{});

      final tool = agent.tools.firstWhere((t) => t.name == 'search_contacts');
      final result = await tool.execute({'query': 'alice'}, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('No contacts'));
    });
  });

  // ---------------------------------------------------------------------------
  // get_contact tool
  // ---------------------------------------------------------------------------

  group('get_contact tool', () {
    test('returns error for missing uri', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'get_contact');
      final result = await tool.execute({'uri': ''}, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });

    test('returns compound result with ContactCard widget', () async {
      when(() => bundle.knowledge.getEntity(any())).thenAnswer(
        (_) async => [
          const Triple(
            subject: 'kabuk:Person/1',
            predicate: NS.schemaName,
            objectValue: 'Alice',
            objectType: ObjectType.string,
          ),
          const Triple(
            subject: 'kabuk:Person/1',
            predicate: NS.schemaEmail,
            objectValue: 'alice@test.com',
            objectType: ObjectType.string,
          ),
        ],
      );

      final tool = agent.tools.firstWhere((t) => t.name == 'get_contact');
      final result = await tool.execute({
        'uri': 'kabuk:Person/1',
      }, bundle.context);

      expect(result, isA<CompoundToolResult>());
      final compound = result as CompoundToolResult;
      final widgetResult = compound.results.whereType<WidgetToolResult>().first;
      expect(widgetResult.library, 'kabuk:contacts');
      expect(widgetResult.widget, 'ContactCard');
    });

    test('returns error when contact not found', () async {
      when(
        () => bundle.knowledge.getEntity(any()),
      ).thenAnswer((_) async => <Triple>[]);

      final tool = agent.tools.firstWhere((t) => t.name == 'get_contact');
      final result = await tool.execute({
        'uri': 'kabuk:Person/nonexistent',
      }, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });
  });

  // ---------------------------------------------------------------------------
  // delete_contact tool
  // ---------------------------------------------------------------------------

  group('delete_contact tool', () {
    test('returns error for missing uri', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'delete_contact');
      final result = await tool.execute({'uri': ''}, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });

    test('deletes contact and returns confirmation', () async {
      when(() => bundle.knowledge.getEntity(any())).thenAnswer(
        (_) async => [
          const Triple(
            subject: 'kabuk:Person/1',
            predicate: NS.schemaName,
            objectValue: 'Bob',
            objectType: ObjectType.string,
          ),
        ],
      );

      bundle.knowledge.onMutate = <T>(action) async {
        return await action(FakeMutationContext());
      };

      final tool = agent.tools.firstWhere((t) => t.name == 'delete_contact');
      final result = await tool.execute({
        'uri': 'kabuk:Person/1',
      }, bundle.context);

      expect(result, isA<TextToolResult>());
      expect(
        (result as TextToolResult).content.toLowerCase(),
        contains('delete'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Tool schema validation
  // ---------------------------------------------------------------------------

  group('tool schemas', () {
    test('create_contact requires name', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'create_contact');
      expect(tool.parameters['required'], contains('name'));
    });

    test('search_contacts requires query', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'search_contacts');
      expect(tool.parameters['required'], contains('query'));
    });

    test('get_contact requires uri', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'get_contact');
      expect(tool.parameters['required'], contains('uri'));
    });

    test('update_contact requires uri', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'update_contact');
      expect(tool.parameters['required'], contains('uri'));
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
      ).thenThrow(Exception('Network error'));

      final message = AgentMessage.user(
        id: 'msg-err',
        timestamp: DateTime.now(),
        content: 'Find Alice',
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
