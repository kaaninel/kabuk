import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/agents/subagent.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
  });

  setUp(() {
    bundle = createMockAgentContext();
  });

  test('tool metadata declares name, description and task param', () {
    expect(kDelegateToSubagentTool.name, 'delegate_to_subagent');
    expect(kDelegateToSubagentTool.description, contains('remote'));
    final properties =
        kDelegateToSubagentTool.parameters['properties'] as Map<String, dynamic>;
    expect(properties, contains('task'));
    expect(kDelegateToSubagentTool.parameters['required'], ['task']);
  });

  test('returns the remote model answer as a text result', () async {
    when(
      () => bundle.llm.complete(any()),
    ).thenAnswer((_) async => const TextLlmResponse('The remote answer.'));

    final result = await kDelegateToSubagentTool.execute(
      {'task': 'explain quantum entanglement simply'},
      bundle.context,
    );

    expect(result, isA<TextToolResult>());
    expect((result as TextToolResult).content, 'The remote answer.');
    // The advanced tier on a non-tiered mock resolves to the same LLM.
    verify(() => bundle.llm.complete(any())).called(1);
  });

  test('passes a system prompt and temperature through', () async {
    when(
      () => bundle.llm.complete(any()),
    ).thenAnswer((_) async => const TextLlmResponse('ok'));

    await kDelegateToSubagentTool.execute({
      'task': 'draft a reply',
      'system': 'You are a polite assistant',
      'temperature': 0.2,
    }, bundle.context);

    final captured = verify(
      () => bundle.llm.complete(captureAny()),
    ).captured.single as LlmRequest;
    expect(captured.messages, hasLength(2));
    expect(captured.messages.first, isA<SystemLlmMessage>());
    expect((captured.messages.first as SystemLlmMessage).content,
        'You are a polite assistant');
    expect(captured.temperature, 0.2);
    expect(captured.maxTokens, 2048);
  });

  test('surfaces remote errors', () async {
    when(
      () => bundle.llm.complete(any()),
    ).thenAnswer((_) async => const ErrorLlmResponse('upstream down'));

    final result = await kDelegateToSubagentTool.execute(
      {'task': 'do something'},
      bundle.context,
    );

    expect(result, isA<ErrorToolResult>());
    expect((result as ErrorToolResult).message, contains('upstream down'));
  });

  test('requires a task', () async {
    final result = await kDelegateToSubagentTool.execute({}, bundle.context);
    expect(result, isA<ErrorToolResult>());
    verifyNever(() => bundle.llm.complete(any()));
  });

  test('system agent exposes the delegation tool', () {
    final agent = SystemAgent();
    final toolNames = agent.tools.map((t) => t.name).toList();
    expect(toolNames, contains('delegate_to_subagent'));
  });
}

class SystemAgent extends BaseAgent {
  @override
  String get name => 'system';

  @override
  String get description => 'test';

  @override
  String get systemPrompt => 'test';

  @override
  List<AgentTool> get tools => [kDelegateToSubagentTool];

  @override
  Set<AgentCapability> get requiredCapabilities => const {};

  @override
  Future<AgentResponse> process(AgentMessage message, AgentContext context) async =>
      const AgentResponse.text('ok');
}