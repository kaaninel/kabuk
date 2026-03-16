import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/domains/system_agent.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late SystemAgent agent;
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
    registerFallbackValue(fakeMutationAction);
  });

  setUp(() {
    agent = SystemAgent();
    bundle = createMockAgentContext();
  });

  // ---------------------------------------------------------------------------
  // Agent metadata
  // ---------------------------------------------------------------------------

  group('SystemAgent metadata', () {
    test('name is "system"', () {
      expect(agent.name, 'system');
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
        containsAll(['get_system_info', 'search_knowledge', 'create_note']),
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
  // process() — LLM returns text
  // ---------------------------------------------------------------------------

  group('process() with TextLlmResponse', () {
    test('returns text response from LLM', () async {
      stubLlmStreamText(bundle.llm, 'Hello! I am Kabuk.');

      final message = AgentMessage.user(
        id: 'msg-1',
        timestamp: DateTime.now(),
        content: 'What are you?',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, 'Hello! I am Kabuk.');
      verify(() => bundle.llm.stream(any())).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // process() — LLM returns error
  // ---------------------------------------------------------------------------

  group('process() with ErrorLlmResponse', () {
    test('returns error response', () async {
      stubLlmStreamError(bundle.llm, 'Service unavailable');

      final message = AgentMessage.user(
        id: 'msg-2',
        timestamp: DateTime.now(),
        content: 'Help me',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      await expectLater(
        (response as StreamingAgentResponse).events,
        emitsError(isA<LlmStreamException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // process() — empty content
  // ---------------------------------------------------------------------------

  group('process() with empty content', () {
    test('returns prompt for non-user message', () async {
      final message = AgentMessage.toolCall(
        id: 'msg-3',
        timestamp: DateTime.now(),
        toolName: 'get_system_info',
        arguments: {},
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<TextAgentResponse>());
      expect((response as TextAgentResponse).content, 'How can I help you?');
      verifyNever(() => bundle.llm.stream(any()));
    });
  });

  // ---------------------------------------------------------------------------
  // get_system_info tool
  // ---------------------------------------------------------------------------

  group('get_system_info tool', () {
    test('returns system info including agent list', () async {
      final dummyAgent = _DummyAgent(
        agentName: 'notes',
        agentDescription: 'Note agent',
      );
      when(() => bundle.runtime.agents).thenReturn([dummyAgent]);

      final tool = agent.tools.firstWhere((t) => t.name == 'get_system_info');
      final result = await tool.execute({}, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('Kabuk'));
      expect(text, contains('notes'));
      expect(text, contains('Note agent'));
    });
  });

  // ---------------------------------------------------------------------------
  // search_knowledge tool
  // ---------------------------------------------------------------------------

  group('search_knowledge tool', () {
    test('returns error for empty query', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'search_knowledge');
      final result = await tool.execute({'query': ''}, bundle.context);

      expect(result, isA<ErrorToolResult>());
      expect((result as ErrorToolResult).message, contains('empty'));
    });

    test('returns "No results" when store is empty', () async {
      when(
        () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
      ).thenAnswer((_) async => <Triple>[]);

      final tool = agent.tools.firstWhere((t) => t.name == 'search_knowledge');
      final result = await tool.execute({'query': 'something'}, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('No results'));
    });

    test('returns formatted results when triples found', () async {
      final triples = [
        const Triple(
          subject: 'kabuk:Note/abc',
          predicate: 'schema:name',
          objectValue: 'Test Note',
          objectType: ObjectType.string,
        ),
      ];

      when(
        () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
      ).thenAnswer((_) async => triples);

      final tool = agent.tools.firstWhere((t) => t.name == 'search_knowledge');
      final result = await tool.execute({'query': 'test'}, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('Found 1 results'));
      expect(text, contains('Test Note'));
    });
  });

  // ---------------------------------------------------------------------------
  // create_note tool
  // ---------------------------------------------------------------------------

  group('create_note tool', () {
    test('creates note and returns confirmation', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'create_note');
      final result = await tool.execute({
        'title': 'My Note',
        'content': 'Body text',
      }, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('My Note'));
      expect(result.content, contains('created'));
      expect(bundle.knowledge.mutateCallCount, 1);
    });

    test('uses default title when not provided', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'create_note');
      final result = await tool.execute({
        'content': 'no title',
      }, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('Untitled'));
    });
  });

  // ---------------------------------------------------------------------------
  // Tool schema validation
  // ---------------------------------------------------------------------------

  group('tool schemas', () {
    test('search_knowledge requires query parameter', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'search_knowledge');
      expect(tool.parameters['required'], contains('query'));
    });

    test('create_note requires title and content', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'create_note');
      expect(tool.parameters['required'], containsAll(['title', 'content']));
    });

    test('get_system_info has no required params', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'get_system_info');
      expect(tool.parameters.containsKey('required'), isFalse);
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
  // process() — LLM exception is caught
  // ---------------------------------------------------------------------------

  group('process() error handling', () {
    test('returns error when LLM throws', () async {
      when(
        () => bundle.llm.stream(any()),
      ).thenThrow(Exception('Connection failed'));

      final message = AgentMessage.user(
        id: 'msg-err',
        timestamp: DateTime.now(),
        content: 'hello',
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

// Helper dummy agent for system info tests.
class _DummyAgent extends BaseAgent {
  _DummyAgent({required this.agentName, required this.agentDescription});

  final String agentName;
  final String agentDescription;

  @override
  String get name => agentName;

  @override
  String get description => agentDescription;

  @override
  String get systemPrompt => '';

  @override
  List<AgentTool> get tools => [];

  @override
  Set<AgentCapability> get requiredCapabilities => {};

  @override
  Future<AgentResponse> process(AgentMessage message, dynamic context) async =>
      const AgentResponse.text('');
}
