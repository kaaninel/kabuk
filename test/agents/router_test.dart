import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/domains/router.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

/// A minimal agent for testing routing.
class _FakeAgent extends BaseAgent {
  _FakeAgent({required this.fakeName, required this.fakeDescription});

  final String fakeName;
  final String fakeDescription;

  @override
  String get name => fakeName;

  @override
  String get description => fakeDescription;

  @override
  String get systemPrompt => 'Fake agent prompt.';

  @override
  List<AgentTool> get tools => [];

  @override
  Set<AgentCapability> get requiredCapabilities => {};

  AgentResponse? stubbedResponse;

  @override
  Future<AgentResponse> process(
    AgentMessage message,
    AgentContext context,
  ) async {
    return stubbedResponse ?? const AgentResponse.text('Fake response');
  }
}

void main() {
  late RouterAgent router;
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
  });

  setUp(() {
    router = RouterAgent();
    bundle = createMockAgentContext();
  });

  // ---------------------------------------------------------------------------
  // Agent metadata
  // ---------------------------------------------------------------------------

  group('RouterAgent metadata', () {
    test('name is "router"', () {
      expect(router.name, 'router');
    });

    test('description is non-empty', () {
      expect(router.description, isNotEmpty);
    });

    test('systemPrompt is non-empty', () {
      expect(router.systemPrompt, isNotEmpty);
    });

    test('declares route_to_agent and list_agents tools', () {
      final toolNames = router.tools.map((t) => t.name).toList();
      expect(toolNames, containsAll(['route_to_agent', 'list_agents']));
    });

    test('requires llmCall, knowledgeRead, and agentInvoke capabilities', () {
      expect(
        router.requiredCapabilities,
        containsAll([
          AgentCapability.llmCall,
          AgentCapability.knowledgeRead,
          AgentCapability.agentInvoke,
        ]),
      );
    });

    test('route_to_agent tool schema has agent_name as required', () {
      final tool = router.tools.firstWhere((t) => t.name == 'route_to_agent');
      expect(tool.parameters['required'], contains('agent_name'));
      final props = tool.parameters['properties'] as Map<String, dynamic>;
      expect(props, contains('agent_name'));
      expect(props, contains('reason'));
    });

    test('list_agents tool schema has empty properties', () {
      final tool = router.tools.firstWhere((t) => t.name == 'list_agents');
      final props = tool.parameters['properties'] as Map<String, dynamic>;
      expect(props, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // process() — LLM returns text directly
  // ---------------------------------------------------------------------------

  group('process() with TextLlmResponse', () {
    test('returns text when LLM answers directly', () async {
      when(() => bundle.runtime.agents).thenReturn([]);
      when(() => bundle.llm.complete(any())).thenAnswer(
        (_) async => const LlmResponse.text('Hello! How can I help?'),
      );

      final message = AgentMessage.user(
        id: 'msg-1',
        timestamp: DateTime.now(),
        content: 'Hello',
      );

      final response = await router.process(message, bundle.context);

      expect(response, isA<TextAgentResponse>());
      expect((response as TextAgentResponse).content, 'Hello! How can I help?');
      verify(() => bundle.llm.complete(any())).called(1);
    });

    test('passes available agent descriptions in system prompt', () async {
      final fakeAgent = _FakeAgent(
        fakeName: 'notes',
        fakeDescription: 'Manages notes.',
      );
      when(() => bundle.runtime.agents).thenReturn([fakeAgent]);
      when(
        () => bundle.llm.complete(any()),
      ).thenAnswer((_) async => const LlmResponse.text('Got it.'));

      final message = AgentMessage.user(
        id: 'msg-2',
        timestamp: DateTime.now(),
        content: 'What can you do?',
      );

      await router.process(message, bundle.context);

      final captured = verify(() => bundle.llm.complete(captureAny())).captured;
      final request = captured.first as LlmRequest;
      expect(request.systemPrompt, contains('notes'));
      expect(request.systemPrompt, contains('Manages notes'));
    });
  });

  // ---------------------------------------------------------------------------
  // process() — LLM returns error
  // ---------------------------------------------------------------------------

  group('process() with ErrorLlmResponse', () {
    test('returns error response', () async {
      when(() => bundle.runtime.agents).thenReturn([]);
      when(
        () => bundle.llm.complete(any()),
      ).thenAnswer((_) async => const LlmResponse.error('Service unavailable'));

      final message = AgentMessage.user(
        id: 'msg-3',
        timestamp: DateTime.now(),
        content: 'Help me',
      );

      final response = await router.process(message, bundle.context);

      expect(response, isA<ErrorAgentResponse>());
      expect((response as ErrorAgentResponse).message, 'Service unavailable');
    });
  });

  // ---------------------------------------------------------------------------
  // process() — empty content
  // ---------------------------------------------------------------------------

  group('process() with empty content', () {
    test('returns prompt message for non-user messages', () async {
      final message = AgentMessage.toolCall(
        id: 'msg-4',
        timestamp: DateTime.now(),
        toolName: 'something',
        arguments: {},
      );

      final response = await router.process(message, bundle.context);

      expect(response, isA<TextAgentResponse>());
      expect(
        (response as TextAgentResponse).content,
        contains("didn't receive"),
      );
      verifyNever(() => bundle.llm.complete(any()));
    });
  });

  // ---------------------------------------------------------------------------
  // process() — LLM requests route_to_agent
  // ---------------------------------------------------------------------------

  group('route_to_agent tool call', () {
    test('delegates to target agent when found', () async {
      final fakeAgent = _FakeAgent(
        fakeName: 'notes',
        fakeDescription: 'Manages notes.',
      );
      fakeAgent.stubbedResponse = const AgentResponse.text('Note created!');

      when(() => bundle.runtime.agents).thenReturn([fakeAgent]);
      when(() => bundle.runtime.getAgent('notes')).thenReturn(fakeAgent);
      when(() => bundle.llm.complete(any())).thenAnswer(
        (_) async => const LlmResponse.toolCalls(null, [
          LlmToolCall(
            id: 'call-1',
            name: 'route_to_agent',
            arguments: {'agent_name': 'notes', 'reason': 'user wants notes'},
          ),
        ]),
      );

      final message = AgentMessage.user(
        id: 'msg-5',
        timestamp: DateTime.now(),
        content: 'Create a note',
      );

      final response = await router.process(message, bundle.context);

      expect(response, isA<TextAgentResponse>());
      expect((response as TextAgentResponse).content, 'Note created!');
    });

    test('returns error when target agent not found', () async {
      when(() => bundle.runtime.agents).thenReturn([]);
      when(() => bundle.runtime.getAgent('weather')).thenReturn(null);
      when(() => bundle.llm.complete(any())).thenAnswer(
        (_) async => const LlmResponse.toolCalls(null, [
          LlmToolCall(
            id: 'call-2',
            name: 'route_to_agent',
            arguments: {'agent_name': 'weather'},
          ),
        ]),
      );

      final message = AgentMessage.user(
        id: 'msg-6',
        timestamp: DateTime.now(),
        content: 'What is the weather?',
      );

      final response = await router.process(message, bundle.context);

      expect(response, isA<ErrorAgentResponse>());
      expect((response as ErrorAgentResponse).message, contains('weather'));
      expect(response.message, contains('not found'));
    });
  });

  // ---------------------------------------------------------------------------
  // process() — LLM requests list_agents
  // ---------------------------------------------------------------------------

  group('list_agents tool call', () {
    test('returns list of all registered agents', () async {
      final fakeNote = _FakeAgent(
        fakeName: 'notes',
        fakeDescription: 'Manages notes.',
      );
      final fakeSearch = _FakeAgent(
        fakeName: 'search',
        fakeDescription: 'Searches everything.',
      );

      when(() => bundle.runtime.agents).thenReturn([fakeNote, fakeSearch]);
      when(() => bundle.llm.complete(any())).thenAnswer(
        (_) async => const LlmResponse.toolCalls(null, [
          LlmToolCall(id: 'call-3', name: 'list_agents', arguments: {}),
        ]),
      );

      final message = AgentMessage.user(
        id: 'msg-7',
        timestamp: DateTime.now(),
        content: 'What agents are available?',
      );

      final response = await router.process(message, bundle.context);

      expect(response, isA<TextAgentResponse>());
      final text = (response as TextAgentResponse).content;
      expect(text, contains('notes'));
      expect(text, contains('search'));
    });

    test('returns "No agents registered" when none exist', () async {
      when(() => bundle.runtime.agents).thenReturn([]);
      when(() => bundle.llm.complete(any())).thenAnswer(
        (_) async => const LlmResponse.toolCalls(null, [
          LlmToolCall(id: 'call-4', name: 'list_agents', arguments: {}),
        ]),
      );

      final message = AgentMessage.user(
        id: 'msg-8',
        timestamp: DateTime.now(),
        content: 'List agents',
      );

      final response = await router.process(message, bundle.context);

      expect(response, isA<TextAgentResponse>());
      final text = (response as TextAgentResponse).content;
      expect(text, contains('No agents'));
    });
  });

  // ---------------------------------------------------------------------------
  // process() — LLM tool schemas passed to LLM
  // ---------------------------------------------------------------------------

  group('LLM request construction', () {
    test('includes tool schemas in LLM request', () async {
      when(() => bundle.runtime.agents).thenReturn([]);
      when(
        () => bundle.llm.complete(any()),
      ).thenAnswer((_) async => const LlmResponse.text('Sure'));

      final message = AgentMessage.user(
        id: 'msg-9',
        timestamp: DateTime.now(),
        content: 'Hello',
      );

      await router.process(message, bundle.context);

      final captured = verify(() => bundle.llm.complete(captureAny())).captured;
      final request = captured.first as LlmRequest;
      expect(request.tools, isNotNull);
      expect(request.tools!.length, router.tools.length);

      final toolNames = request.tools!.map(
        (t) => (t['function'] as Map<String, dynamic>)['name'],
      );
      expect(toolNames, contains('route_to_agent'));
      expect(toolNames, contains('list_agents'));
    });

    test('sets temperature to 0.3', () async {
      when(() => bundle.runtime.agents).thenReturn([]);
      when(
        () => bundle.llm.complete(any()),
      ).thenAnswer((_) async => const LlmResponse.text('hi'));

      final message = AgentMessage.user(
        id: 'msg-10',
        timestamp: DateTime.now(),
        content: 'hi',
      );

      await router.process(message, bundle.context);

      final captured = verify(() => bundle.llm.complete(captureAny())).captured;
      final request = captured.first as LlmRequest;
      expect(request.temperature, 0.3);
    });

    test('includes user message history when available', () async {
      when(() => bundle.runtime.agents).thenReturn([]);
      when(
        () => bundle.llm.complete(any()),
      ).thenAnswer((_) async => const LlmResponse.text('ok'));

      final history = [
        const LlmMessage.user('previous question'),
        const LlmMessage.assistant('previous answer'),
      ];

      final message = AgentMessage.user(
        id: 'msg-11',
        timestamp: DateTime.now(),
        content: 'follow up',
        history: history,
      );

      await router.process(message, bundle.context);

      final captured = verify(() => bundle.llm.complete(captureAny())).captured;
      final request = captured.first as LlmRequest;
      // 2 from history + 1 new user message
      expect(request.messages.length, 3);
    });
  });

  // ---------------------------------------------------------------------------
  // _routeToAgent tool standalone execution
  // ---------------------------------------------------------------------------

  group('route_to_agent tool execute()', () {
    test('returns text when agent exists', () async {
      final fakeAgent = _FakeAgent(
        fakeName: 'notes',
        fakeDescription: 'Manages notes.',
      );
      when(() => bundle.runtime.getAgent('notes')).thenReturn(fakeAgent);

      final tool = router.tools.firstWhere((t) => t.name == 'route_to_agent');
      final result = await tool.execute({
        'agent_name': 'notes',
      }, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('notes'));
    });

    test('returns error when agent not found', () async {
      when(() => bundle.runtime.getAgent('unknown')).thenReturn(null);

      final tool = router.tools.firstWhere((t) => t.name == 'route_to_agent');
      final result = await tool.execute({
        'agent_name': 'unknown',
      }, bundle.context);

      expect(result, isA<ErrorToolResult>());
      expect((result as ErrorToolResult).message, contains('not found'));
    });
  });

  // ---------------------------------------------------------------------------
  // _listAgents tool standalone execution
  // ---------------------------------------------------------------------------

  group('list_agents tool execute()', () {
    test('returns formatted list of agents', () async {
      final agents = [
        _FakeAgent(fakeName: 'notes', fakeDescription: 'Notes agent'),
        _FakeAgent(fakeName: 'search', fakeDescription: 'Search agent'),
      ];
      when(() => bundle.runtime.agents).thenReturn(agents);

      final tool = router.tools.firstWhere((t) => t.name == 'list_agents');
      final result = await tool.execute({}, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('notes'));
      expect(text, contains('search'));
      expect(text, contains('Notes agent'));
      expect(text, contains('Search agent'));
    });

    test('returns "No agents registered" when empty', () async {
      when(() => bundle.runtime.agents).thenReturn([]);

      final tool = router.tools.firstWhere((t) => t.name == 'list_agents');
      final result = await tool.execute({}, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('No agents'));
    });
  });
}
