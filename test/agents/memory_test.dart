import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/memory.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/mutation.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

/// Minimal agent that uses the memory mixin for testing.
class _TestAgent extends BaseAgent with AgentMemoryMixin {
  @override
  String get name => 'test_agent';

  @override
  String get description => 'A test agent.';

  @override
  String get systemPrompt => 'You are a test agent.';

  @override
  List<AgentTool> get tools => [];

  @override
  Set<AgentCapability> get requiredCapabilities => {};

  @override
  Future<AgentResponse> process(AgentMessage message, AgentContext context) =>
      throw UnimplementedError();
}

void main() {
  late _TestAgent agent;
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
    registerFallbackValue(fakeMutationAction);
  });

  setUp(() {
    agent = _TestAgent();
    bundle = createMockAgentContext();
  });

  // -------------------------------------------------------------------------
  // saveMemory / loadMemory round-trip
  // -------------------------------------------------------------------------

  group('saveMemory + loadMemory', () {
    test('loadMemory returns null when no memory exists', () async {
      when(
        () => bundle.knowledge.getEntity(any()),
      ).thenAnswer((_) async => <Triple>[]);

      final result = await agent.loadMemory(bundle.context, 'some_key');
      expect(result, isNull);
    });

    test('loadMemory returns saved value', () async {
      when(
        () => bundle.knowledge.getEntity('kabuk:AgentMemory/test_agent/pref'),
      ).thenAnswer(
        (_) async => [
          const Triple.string(
            subject: 'kabuk:AgentMemory/test_agent/pref',
            predicate: NS.kabukAgentMemory,
            object: 'dark_theme',
          ),
          const Triple.string(
            subject: 'kabuk:AgentMemory/test_agent/pref',
            predicate: NS.schemaName,
            object: 'pref',
          ),
        ],
      );

      final result = await agent.loadMemory(bundle.context, 'pref');
      expect(result, 'dark_theme');
    });

    test('saveMemory calls mutate', () async {
      // The default MockMutationContext stubs don't return futures,
      // so provide a custom handler that stubs set().
      bundle.knowledge.onMutate =
          <T>(Future<T> Function(MutationContext ctx) action) async {
            final mockCtx = MockMutationContext();
            when(
              () => mockCtx.set(any(), any(), any<dynamic>()),
            ).thenAnswer((_) async {});
            return action(mockCtx);
          };

      await agent.saveMemory(bundle.context, 'key1', 'value1');
      expect(bundle.knowledge.mutateCallCount, 1);
    });
  });

  // -------------------------------------------------------------------------
  // loadAllMemories
  // -------------------------------------------------------------------------

  group('loadAllMemories', () {
    test('returns empty map when no memories exist', () async {
      // MockKnowledgeStore.query() returns a default empty-result builder.
      final result = await agent.loadAllMemories(bundle.context);
      expect(result, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // buildMemoryContext
  // -------------------------------------------------------------------------

  group('buildMemoryContext', () {
    test('returns empty string when no memories', () async {
      // Default MockKnowledgeStore.query() returns empty results.
      final result = await agent.buildMemoryContext(bundle.context);
      expect(result, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // buildSystemPromptWithMemory
  // -------------------------------------------------------------------------

  group('buildSystemPromptWithMemory', () {
    test('returns base prompt when no memories exist', () async {
      // Default MockKnowledgeStore.query() returns empty results.
      final result = await agent.buildSystemPromptWithMemory(bundle.context);
      final base = agent.buildSystemPrompt();
      expect(result, base);
    });

    test('appends memory block when memories exist', () async {
      // Override query() via onQuery callback.
      bundle.knowledge.onQuery = () {
        final qb = MockQueryBuilder();
        when(
          () => qb.where(any(), equals: any(named: 'equals')),
        ).thenReturn(qb);
        when(qb.execute).thenAnswer(
          (_) async => [
            const Triple.uri(
              subject: 'kabuk:AgentMemory/test_agent/color',
              predicate: NS.rdfType,
              object: 'kabuk:AgentMemory',
            ),
          ],
        );
        return qb;
      };

      // getEntities returns the full entity for that subject.
      when(() => bundle.knowledge.getEntities(any())).thenAnswer(
        (_) async => {
          'kabuk:AgentMemory/test_agent/color': [
            const Triple.string(
              subject: 'kabuk:AgentMemory/test_agent/color',
              predicate: NS.schemaName,
              object: 'color',
            ),
            const Triple.string(
              subject: 'kabuk:AgentMemory/test_agent/color',
              predicate: NS.kabukAgentMemory,
              object: 'blue',
            ),
          ],
        },
      );

      final result = await agent.buildSystemPromptWithMemory(bundle.context);
      expect(result, contains('## Agent Memory'));
      expect(result, contains('color'));
      expect(result, contains('blue'));
    });
  });

  // -------------------------------------------------------------------------
  // deleteMemory
  // -------------------------------------------------------------------------

  group('deleteMemory', () {
    test('calls mutate to remove the subject', () async {
      bundle.knowledge.onMutate =
          <T>(Future<T> Function(MutationContext ctx) action) async {
            final mockCtx = MockMutationContext();
            when(
              () => mockCtx.remove(
                subject: any(named: 'subject'),
                predicate: any(named: 'predicate'),
                object: any(named: 'object'),
              ),
            ).thenAnswer((_) async {});
            return action(mockCtx);
          };

      await agent.deleteMemory(bundle.context, 'old_key');
      expect(bundle.knowledge.mutateCallCount, 1);
    });
  });
}
