import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/domains/search_agent.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late SearchAgent agent;
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
  });

  setUp(() {
    agent = SearchAgent();
    bundle = createMockAgentContext();
  });

  // ---------------------------------------------------------------------------
  // Agent metadata
  // ---------------------------------------------------------------------------

  group('SearchAgent metadata', () {
    test('name is "search"', () {
      expect(agent.name, 'search');
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
        containsAll(['search', 'search_by_type', 'recent', 'count_entities']),
      );
    });

    test('requires knowledgeRead and llmCall capabilities', () {
      expect(
        agent.requiredCapabilities,
        containsAll([AgentCapability.knowledgeRead, AgentCapability.llmCall]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // process() — LLM returns text
  // ---------------------------------------------------------------------------

  group('process() with TextLlmResponse', () {
    test('returns text response from LLM', () async {
      stubLlmStreamText(bundle.llm, 'I can help you search!');

      final message = AgentMessage.user(
        id: 'msg-1',
        timestamp: DateTime.now(),
        content: 'Find something',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, 'I can help you search!');
    });
  });

  // ---------------------------------------------------------------------------
  // process() — LLM returns error
  // ---------------------------------------------------------------------------

  group('process() with ErrorLlmResponse', () {
    test('returns error response', () async {
      stubLlmStreamError(bundle.llm, 'timeout');

      final message = AgentMessage.user(
        id: 'msg-2',
        timestamp: DateTime.now(),
        content: 'Search for notes',
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
    test('returns prompt when content is empty', () async {
      final message = AgentMessage.toolCall(
        id: 'msg-3',
        timestamp: DateTime.now(),
        toolName: 'search',
        arguments: {},
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<TextAgentResponse>());
      expect((response as TextAgentResponse).content, contains('search'));
      verifyNever(() => bundle.llm.stream(any()));
    });
  });

  // ---------------------------------------------------------------------------
  // search tool
  // ---------------------------------------------------------------------------

  group('search tool', () {
    test('returns error for empty query', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'search');
      final result = await tool.execute({'query': ''}, bundle.context);

      expect(result, isA<ErrorToolResult>());
      expect((result as ErrorToolResult).message, contains('empty'));
    });

    test('returns "No results" when store returns empty', () async {
      when(
        () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
      ).thenAnswer((_) async => <Triple>[]);

      final tool = agent.tools.firstWhere((t) => t.name == 'search');
      final result = await tool.execute({'query': 'xyzzy'}, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('No results'));
    });

    test('returns formatted results when triples found', () async {
      final triples = [
        const Triple(
          subject: 'kabuk:Note/abc',
          predicate: NS.schemaText,
          objectValue: 'Hello world',
          objectType: ObjectType.string,
        ),
      ];

      when(
        () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
      ).thenAnswer((_) async => triples);

      when(() => bundle.knowledge.getEntities(any())).thenAnswer(
        (_) async => {
          'kabuk:Note/abc': [
            const Triple(
              subject: 'kabuk:Note/abc',
              predicate: NS.rdfType,
              objectValue: NS.schemaNote,
              objectType: ObjectType.uri,
            ),
            const Triple(
              subject: 'kabuk:Note/abc',
              predicate: NS.schemaName,
              objectValue: 'Test Note',
              objectType: ObjectType.string,
            ),
            const Triple(
              subject: 'kabuk:Note/abc',
              predicate: NS.schemaText,
              objectValue: 'Hello world',
              objectType: ObjectType.string,
            ),
          ],
        },
      );

      final tool = agent.tools.firstWhere((t) => t.name == 'search');
      final result = await tool.execute({'query': 'hello'}, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('Found'));
      expect(text, contains('Test Note'));
    });

    test('deduplicates results by subject URI', () async {
      final triples = [
        const Triple(
          subject: 'kabuk:Note/abc',
          predicate: NS.schemaText,
          objectValue: 'match 1',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Note/abc',
          predicate: NS.schemaName,
          objectValue: 'match 2',
          objectType: ObjectType.string,
        ),
      ];

      when(
        () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
      ).thenAnswer((_) async => triples);

      when(() => bundle.knowledge.getEntities(any())).thenAnswer(
        (_) async => {
          'kabuk:Note/abc': [
            const Triple(
              subject: 'kabuk:Note/abc',
              predicate: NS.schemaName,
              objectValue: 'Only Note',
              objectType: ObjectType.string,
            ),
          ],
        },
      );

      final tool = agent.tools.firstWhere((t) => t.name == 'search');
      final result = await tool.execute({'query': 'match'}, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('1 result'));
    });

    test('uses default limit of 10', () async {
      when(
        () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
      ).thenAnswer((_) async => <Triple>[]);

      final tool = agent.tools.firstWhere((t) => t.name == 'search');
      await tool.execute({'query': 'test'}, bundle.context);

      verify(() => bundle.knowledge.search('test', limit: 10)).called(1);
    });

    test('respects custom limit', () async {
      when(
        () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
      ).thenAnswer((_) async => <Triple>[]);

      final tool = agent.tools.firstWhere((t) => t.name == 'search');
      await tool.execute({'query': 'test', 'limit': 5}, bundle.context);

      verify(() => bundle.knowledge.search('test', limit: 5)).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // search_by_type tool
  // ---------------------------------------------------------------------------

  group('search_by_type tool', () {
    test('returns error for empty query', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'search_by_type');
      final result = await tool.execute({
        'query': '',
        'entity_type': NS.schemaNote,
      }, bundle.context);

      expect(result, isA<ErrorToolResult>());
      expect((result as ErrorToolResult).message, contains('empty'));
    });

    test('returns error for empty entity_type', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'search_by_type');
      final result = await tool.execute({
        'query': 'hello',
        'entity_type': '',
      }, bundle.context);

      expect(result, isA<ErrorToolResult>());
      expect((result as ErrorToolResult).message, contains('type'));
    });

    test('filters results by type', () async {
      final triples = [
        const Triple(
          subject: 'kabuk:Note/abc',
          predicate: NS.schemaText,
          objectValue: 'note text',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Person/def',
          predicate: NS.schemaName,
          objectValue: 'note person',
          objectType: ObjectType.string,
        ),
      ];

      when(
        () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
      ).thenAnswer((_) async => triples);

      // Note entity matches the type filter
      when(() => bundle.knowledge.getEntities(any())).thenAnswer(
        (_) async => {
          'kabuk:Note/abc': [
            const Triple(
              subject: 'kabuk:Note/abc',
              predicate: NS.rdfType,
              objectValue: NS.schemaNote,
              objectType: ObjectType.uri,
            ),
            const Triple(
              subject: 'kabuk:Note/abc',
              predicate: NS.schemaName,
              objectValue: 'My Note',
              objectType: ObjectType.string,
            ),
          ],
          'kabuk:Person/def': [
            const Triple(
              subject: 'kabuk:Person/def',
              predicate: NS.rdfType,
              objectValue: NS.schemaPerson,
              objectType: ObjectType.uri,
            ),
            const Triple(
              subject: 'kabuk:Person/def',
              predicate: NS.schemaName,
              objectValue: 'Alice',
              objectType: ObjectType.string,
            ),
          ],
        },
      );

      final tool = agent.tools.firstWhere((t) => t.name == 'search_by_type');
      final result = await tool.execute({
        'query': 'note',
        'entity_type': NS.schemaNote,
      }, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('Note'));
      expect(text, contains('My Note'));
      // Should NOT contain the Person result
      expect(text, isNot(contains('Alice')));
    });

    test(
      'returns "No ... entities found" when type filter eliminates all',
      () async {
        final triples = [
          const Triple(
            subject: 'kabuk:Person/def',
            predicate: NS.schemaName,
            objectValue: 'Alice',
            objectType: ObjectType.string,
          ),
        ];

        when(
          () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
        ).thenAnswer((_) async => triples);

        when(() => bundle.knowledge.getEntities(any())).thenAnswer(
          (_) async => {
            'kabuk:Person/def': [
              const Triple(
                subject: 'kabuk:Person/def',
                predicate: NS.rdfType,
                objectValue: NS.schemaPerson,
                objectType: ObjectType.uri,
              ),
            ],
          },
        );

        final tool = agent.tools.firstWhere((t) => t.name == 'search_by_type');
        final result = await tool.execute({
          'query': 'Alice',
          'entity_type': NS.schemaNote,
        }, bundle.context);

        expect(result, isA<TextToolResult>());
        final text = (result as TextToolResult).content;
        expect(text, contains('No'));
        expect(text, contains('Note'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // recent tool
  // ---------------------------------------------------------------------------

  group('recent tool', () {
    test('returns "No recent entities" when store has none', () async {
      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(
        () => mockQb.orderBy(any(), descending: any(named: 'descending')),
      ).thenReturn(mockQb);
      when(() => mockQb.limit(any())).thenReturn(mockQb);
      when(mockQb.execute).thenAnswer((_) async => <Triple>[]);
      when(
        () => bundle.knowledge.getEntities(any()),
      ).thenAnswer((_) async => <String, List<Triple>>{});

      final tool = agent.tools.firstWhere((t) => t.name == 'recent');
      final result = await tool.execute({}, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('No recent'));
    });

    test('returns entities sorted by date', () async {
      final modifiedTriples = [
        const Triple(
          subject: 'kabuk:Note/x',
          predicate: NS.schemaDateModified,
          objectValue: '2026-02-25T10:00:00.000Z',
          objectType: ObjectType.string,
        ),
      ];

      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(
        () => mockQb.orderBy(any(), descending: any(named: 'descending')),
      ).thenReturn(mockQb);
      when(() => mockQb.limit(any())).thenReturn(mockQb);

      // First call returns modified triples, second call returns empty created
      var callCount = 0;
      when(mockQb.execute).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) return modifiedTriples;
        return <Triple>[];
      });

      when(() => bundle.knowledge.getEntities(any())).thenAnswer(
        (_) async => {
          'kabuk:Note/x': [
            const Triple(
              subject: 'kabuk:Note/x',
              predicate: NS.rdfType,
              objectValue: NS.schemaNote,
              objectType: ObjectType.uri,
            ),
            const Triple(
              subject: 'kabuk:Note/x',
              predicate: NS.schemaName,
              objectValue: 'Recent Note',
              objectType: ObjectType.string,
            ),
          ],
        },
      );

      final tool = agent.tools.firstWhere((t) => t.name == 'recent');
      final result = await tool.execute({}, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('Recent'));
      expect(text, contains('Recent Note'));
    });

    test('uses default limit of 10', () async {
      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(
        () => mockQb.orderBy(any(), descending: any(named: 'descending')),
      ).thenReturn(mockQb);
      when(() => mockQb.limit(any())).thenReturn(mockQb);
      when(mockQb.execute).thenAnswer((_) async => <Triple>[]);
      when(
        () => bundle.knowledge.getEntities(any()),
      ).thenAnswer((_) async => <String, List<Triple>>{});

      final tool = agent.tools.firstWhere((t) => t.name == 'recent');
      await tool.execute({}, bundle.context);

      verify(
        () => mockQb.limit(10),
      ).called(2); // once for modified, once for created
    });
  });

  // ---------------------------------------------------------------------------
  // count_entities tool
  // ---------------------------------------------------------------------------

  group('count_entities tool', () {
    test('counts specific type when entity_type provided', () async {
      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(() => mockQb.object(any())).thenReturn(mockQb);
      when(mockQb.count).thenAnswer((_) async => 42);

      final tool = agent.tools.firstWhere((t) => t.name == 'count_entities');
      final result = await tool.execute({
        'entity_type': NS.schemaNote,
      }, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('Note'));
      expect(text, contains('42'));
    });

    test('counts all types when entity_type not provided', () async {
      final typeTriples = [
        const Triple(
          subject: 'kabuk:Note/a',
          predicate: NS.rdfType,
          objectValue: NS.schemaNote,
          objectType: ObjectType.uri,
        ),
        const Triple(
          subject: 'kabuk:Note/b',
          predicate: NS.rdfType,
          objectValue: NS.schemaNote,
          objectType: ObjectType.uri,
        ),
        const Triple(
          subject: 'kabuk:Person/c',
          predicate: NS.rdfType,
          objectValue: NS.schemaPerson,
          objectType: ObjectType.uri,
        ),
      ];

      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(mockQb.execute).thenAnswer((_) async => typeTriples);

      final tool = agent.tools.firstWhere((t) => t.name == 'count_entities');
      final result = await tool.execute({}, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('Note'));
      expect(text, contains('2'));
      expect(text, contains('Person'));
      expect(text, contains('1'));
    });

    test('returns "No entities found" when store is empty', () async {
      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(mockQb.execute).thenAnswer((_) async => <Triple>[]);

      final tool = agent.tools.firstWhere((t) => t.name == 'count_entities');
      final result = await tool.execute({}, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('No entities'));
    });
  });

  // ---------------------------------------------------------------------------
  // Tool schema validation
  // ---------------------------------------------------------------------------

  group('tool schemas', () {
    test('search tool requires query parameter', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'search');
      expect(tool.parameters['required'], contains('query'));
    });

    test('search_by_type tool requires query and entity_type', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'search_by_type');
      final required = tool.parameters['required'] as List<dynamic>;
      expect(required, containsAll(['query', 'entity_type']));
    });

    test('recent tool has no required parameters', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'recent');
      expect(tool.parameters.containsKey('required'), isFalse);
    });

    test('count_entities tool has no required parameters', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'count_entities');
      expect(tool.parameters.containsKey('required'), isFalse);
    });

    test('all tools produce valid function schemas', () {
      for (final tool in agent.tools) {
        final schema = tool.toFunctionSchema();
        expect(schema['type'], 'function');
        final fn = schema['function'] as Map<String, dynamic>;
        expect(fn['name'], isNotEmpty);
        expect(fn['description'], isNotEmpty);
        expect(fn['parameters'], isA<Map<String, dynamic>>());
      }
    });
  });
}
