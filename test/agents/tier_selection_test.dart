/// Tests for the LLM tier selection feature in [BaseAgent.processLlmRequest].
///
/// Verifies that the tier parameter correctly sets the model hint
/// on [LlmRequest] so that [TieredLlmService] can route to the
/// appropriate backend.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/agents/tiered_llm.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

/// Minimal agent for testing processLlmRequest tier behavior.
class _TierTestAgent extends BaseAgent {
  @override
  String get name => 'tier_test';

  @override
  String get description => 'Test agent for tier selection.';

  @override
  String get systemPrompt => 'Test prompt.';

  @override
  List<AgentTool> get tools => [];

  @override
  Set<AgentCapability> get requiredCapabilities => {};

  @override
  Future<AgentResponse> process(AgentMessage message, AgentContext context) =>
      throw UnimplementedError();
}

void main() {
  late _TierTestAgent agent;
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
    registerFallbackValue(fakeMutationAction);
  });

  setUp(() {
    agent = _TierTestAgent();
    bundle = createMockAgentContext();
  });

  // ---------------------------------------------------------------------------
  // Tier selection
  // ---------------------------------------------------------------------------

  group('processLlmRequest tier parameter', () {
    test('sets model to tier:base when base tier specified', () async {
      stubLlmStreamText(bundle.llm, 'OK');

      final result = await agent.processLlmRequest(
        context: bundle.context,
        messages: [const LlmMessage.user('Hello')],
        systemPrompt: 'Test',
        tier: LlmTier.base,
      );
      await collectStreamingText(result);

      final captured = verify(() => bundle.llm.stream(captureAny())).captured;
      final request = captured.first as LlmRequest;
      expect(request.model, 'tier:base');
    });

    test('sets model to tier:standard when standard tier specified', () async {
      stubLlmStreamText(bundle.llm, 'OK');

      final result = await agent.processLlmRequest(
        context: bundle.context,
        messages: [const LlmMessage.user('Hello')],
        systemPrompt: 'Test',
        tier: LlmTier.standard,
      );
      await collectStreamingText(result);

      final captured = verify(() => bundle.llm.stream(captureAny())).captured;
      final request = captured.first as LlmRequest;
      expect(request.model, 'tier:standard');
    });

    test('sets model to tier:advanced when advanced tier specified', () async {
      stubLlmStreamText(bundle.llm, 'OK');

      final result = await agent.processLlmRequest(
        context: bundle.context,
        messages: [const LlmMessage.user('Hello')],
        systemPrompt: 'Test',
        tier: LlmTier.advanced,
      );
      await collectStreamingText(result);

      final captured = verify(() => bundle.llm.stream(captureAny())).captured;
      final request = captured.first as LlmRequest;
      expect(request.model, 'tier:advanced');
    });

    test('leaves model null when no tier specified', () async {
      stubLlmStreamText(bundle.llm, 'OK');

      final result = await agent.processLlmRequest(
        context: bundle.context,
        messages: [const LlmMessage.user('Hello')],
        systemPrompt: 'Test',
      );
      await collectStreamingText(result);

      final captured = verify(() => bundle.llm.stream(captureAny())).captured;
      final request = captured.first as LlmRequest;
      expect(request.model, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // processLlmRequest error handling
  // ---------------------------------------------------------------------------

  group('processLlmRequest error handling', () {
    test('returns error response on LLM failure', () async {
      stubLlmStreamError(bundle.llm, 'Service unavailable');

      final result = await agent.processLlmRequest(
        context: bundle.context,
        messages: [const LlmMessage.user('Hello')],
        systemPrompt: 'Test',
      );

      expect(result, isA<StreamingAgentResponse>());
      await expectLater(
        (result as StreamingAgentResponse).events,
        emitsError(isA<LlmStreamException>()),
      );
    });

    test('catches exceptions and returns error response', () async {
      when(
        () => bundle.llm.stream(any()),
      ).thenThrow(Exception('Network error'));

      final result = await agent.processLlmRequest(
        context: bundle.context,
        messages: [const LlmMessage.user('Hello')],
        systemPrompt: 'Test',
      );

      expect(result, isA<StreamingAgentResponse>());
      await expectLater(
        (result as StreamingAgentResponse).events,
        emitsError(isA<Exception>()),
      );
    });
  });
}
