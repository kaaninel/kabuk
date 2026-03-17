/// Tests for agent memory pruning logic.
///
/// Verifies that [AgentMemoryMixin._pruneMemories] correctly
/// removes oldest memories when exceeding maxMemories.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/memory.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

/// Minimal agent that uses the memory mixin for testing pruning.
class _PruneTestAgent extends BaseAgent with AgentMemoryMixin {
  @override
  String get name => 'prune_test';

  @override
  String get description => 'Test agent for pruning.';

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
  late _PruneTestAgent agent;
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
    registerFallbackValue(fakeMutationAction);
  });

  setUp(() {
    agent = _PruneTestAgent();
    bundle = createMockAgentContext();
  });

  group('maxMemories constant', () {
    test('is 50', () {
      expect(AgentMemoryMixin.maxMemories, 50);
    });
  });

  group('saveMemory triggers pruning', () {
    test('does not remove memories when under limit', () async {
      // Simulate having 3 memories (well under limit of 50).
      final memoryTriples = List.generate(
        3,
        (i) => Triple.string(
          subject: 'kabuk:AgentMemory/prune_test/key$i',
          predicate: NS.rdfType,
          object: NS.kabukAgentMemory,
        ),
      );

      when(() => bundle.knowledge.getEntity(any())).thenAnswer((_) async => []);

      // Mock the query for listing all memories.
      final qb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => qb;
      when(() => qb.where(any(), equals: any(named: 'equals'))).thenReturn(qb);
      when(qb.execute).thenAnswer((_) async => memoryTriples);

      // For each memory entity, return last modified date.
      for (var i = 0; i < 3; i++) {
        when(
          () =>
              bundle.knowledge.getEntity('kabuk:AgentMemory/prune_test/key$i'),
        ).thenAnswer(
          (_) async => [
            Triple.string(
              subject: 'kabuk:AgentMemory/prune_test/key$i',
              predicate: NS.schemaDateModified,
              object: DateTime.now().toIso8601String(),
            ),
          ],
        );
      }

      await agent.saveMemory(bundle.context, 'test_key', 'test_value');

      // mutate should only be called once (for the save, not for removal).
      expect(bundle.knowledge.mutateCallCount, 1);
    });

    test('removes oldest memories when over limit', () async {
      // Create 52 memory triples (2 over the limit of 50).
      final memoryTriples = List.generate(
        52,
        (i) => Triple.string(
          subject: 'kabuk:AgentMemory/prune_test/key$i',
          predicate: NS.rdfType,
          object: NS.kabukAgentMemory,
        ),
      );

      when(() => bundle.knowledge.getEntity(any())).thenAnswer((_) async => []);

      final qb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => qb;
      when(() => qb.where(any(), equals: any(named: 'equals'))).thenReturn(qb);
      when(qb.execute).thenAnswer((_) async => memoryTriples);

      // Mock getEntities (batch) to return dated entities.
      when(
        () => bundle.knowledge.getEntities(any()),
      ).thenAnswer((_) async {
        final map = <String, List<Triple>>{};
        for (var i = 0; i < 52; i++) {
          final uri = 'kabuk:AgentMemory/prune_test/key$i';
          map[uri] = [
            Triple.string(
              subject: uri,
              predicate: NS.schemaDateModified,
              object: DateTime(2024, 1, 1)
                  .add(Duration(days: i))
                  .toIso8601String(),
            ),
          ];
        }
        return map;
      });

      await agent.saveMemory(bundle.context, 'test_key', 'test_value');

      // 1 call for saving + 1 call for batch removing oldest.
      expect(bundle.knowledge.mutateCallCount, 2);
    });
  });
}
