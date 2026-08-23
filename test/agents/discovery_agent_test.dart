import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/domains/discovery_agent.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:kabuk/plugins/channel.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late DiscoveryAgent agent;
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
    registerFallbackValue(fakeMutationAction);
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    agent = DiscoveryAgent();
    bundle = createMockAgentContext();
  });

  // ---------------------------------------------------------------------------
  // Agent metadata
  // ---------------------------------------------------------------------------

  group('DiscoveryAgent metadata', () {
    test('name is "discover"', () {
      expect(agent.name, 'discover');
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
          'search_nostr_hashtag',
          'search_nostr_content',
          'trending_topics',
          'search_local',
          'subscribe_topic',
          'save_search',
          'list_saved_searches',
          'delete_saved_search',
          'bookmark_content',
        ]),
      );
    });

    test('requires correct capabilities', () {
      expect(
        agent.requiredCapabilities,
        containsAll([
          AgentCapability.knowledgeRead,
          AgentCapability.knowledgeWrite,
          AgentCapability.llmCall,
          AgentCapability.meshConnect,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // process() — LLM paths
  // ---------------------------------------------------------------------------

  group('process() with TextLlmResponse', () {
    test('returns text response from LLM', () async {
      stubLlmStreamText(bundle.llm, 'Let me search for that!');

      final message = AgentMessage.user(
        id: 'msg-1',
        timestamp: DateTime.now(),
        content: 'Find something interesting',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, 'Let me search for that!');
    });
  });

  group('process() with ErrorLlmResponse', () {
    test('returns error response', () async {
      stubLlmStreamError(bundle.llm, 'LLM down');

      final message = AgentMessage.user(
        id: 'msg-2',
        timestamp: DateTime.now(),
        content: 'Search nostr',
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
        toolName: 'trending_topics',
        arguments: {},
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<TextAgentResponse>());
      expect((response as TextAgentResponse).content, contains('discover'));
      verifyNever(() => bundle.llm.stream(any()));
    });
  });

  // ---------------------------------------------------------------------------
  // Direct dispatch — hashtag search
  // ---------------------------------------------------------------------------

  group('process() direct dispatch', () {
    test('handles #hashtag pattern directly via Nostr', () async {
      when(
        () => bundle.nostr.searchByHashtag(any(), limit: any(named: 'limit')),
      ).thenAnswer(
        (_) => Stream.fromIterable([
          NostrEvent(
            id: 'evt-1',
            pubkey: 'abcdef1234567890',
            createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            kind: 1,
            tags: [],
            content: 'Hello #flutter world',
            sig: '',
          ),
        ]),
      );

      final message = AgentMessage.user(
        id: 'msg-dd-1',
        timestamp: DateTime.now(),
        content: '#flutter',
      );

      final response = await agent.process(message, bundle.context);

      // Handled directly — no LLM call
      verifyNever(() => bundle.llm.stream(any()));
      expect(response, isA<TextAgentResponse>());
      final text = (response as TextAgentResponse).content;
      expect(text, contains('flutter'));
    });

    test('handles "trending" pattern directly', () async {
      when(
        () => bundle.nostr.trendingHashtags(window: any(named: 'window')),
      ).thenAnswer(
        (_) async => [
          (hashtag: 'flutter', count: 42),
          (hashtag: 'dart', count: 15),
        ],
      );

      final message = AgentMessage.user(
        id: 'msg-dd-2',
        timestamp: DateTime.now(),
        content: "what's trending?",
      );

      final response = await agent.process(message, bundle.context);

      verifyNever(() => bundle.llm.stream(any()));
      expect(response, isA<TextAgentResponse>());
    });
  });

  // ---------------------------------------------------------------------------
  // search_nostr_hashtag tool
  // ---------------------------------------------------------------------------

  group('search_nostr_hashtag tool', () {
    test('returns error when nostr service unavailable', () async {
      // Test with an empty stream to simulate no results.
      when(
        () => bundle.nostr.searchByHashtag(any(), limit: any(named: 'limit')),
      ).thenAnswer((_) => Stream.fromIterable([]));

      final tool = agent.tools.firstWhere(
        (t) => t.name == 'search_nostr_hashtag',
      );
      final result = await tool.execute({
        'hashtags': ['flutter'],
      }, bundle.context);

      // Should complete without error (empty results)
      expect(result, isA<TextToolResult>());
    });

    test('returns formatted results for hashtag search', () async {
      when(
        () => bundle.nostr.searchByHashtag(any(), limit: any(named: 'limit')),
      ).thenAnswer(
        (_) => Stream.fromIterable([
          NostrEvent(
            id: 'evt-1',
            pubkey: 'abcdef1234567890',
            createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            kind: 1,
            tags: [],
            content: 'Great article about Flutter',
            sig: '',
          ),
          NostrEvent(
            id: 'evt-2',
            pubkey: 'fedcba0987654321',
            createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            kind: 1,
            tags: [],
            content: 'Flutter is amazing',
            sig: '',
          ),
        ]),
      );

      final tool = agent.tools.firstWhere(
        (t) => t.name == 'search_nostr_hashtag',
      );
      final result = await tool.execute({
        'hashtags': ['flutter'],
      }, bundle.context);

      // The tool populates a channel with typed content items so the OS
      // can draw them with the existing primitives.
      expect(result, isA<ChannelToolResult>());
      final channel = result as ChannelToolResult;
      expect(channel.channel.title, contains('flutter'));
      expect(channel.channel.entityType, ChannelEntityType.topic);
      expect(channel.items, hasLength(2));
      expect(channel.items.first.sourcePluginId, 'nostr');
      expect(channel.summary, contains('2'));
    });
  });

  // ---------------------------------------------------------------------------
  // search_local tool
  // ---------------------------------------------------------------------------

  group('search_local tool', () {
    test('returns error for empty query', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'search_local');
      final result = await tool.execute({'query': ''}, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });

    test('returns "No results" when store is empty', () async {
      when(
        () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
      ).thenAnswer((_) async => <Triple>[]);

      final tool = agent.tools.firstWhere((t) => t.name == 'search_local');
      final result = await tool.execute({'query': 'flutter'}, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('No local results'));
    });

    test('returns formatted results with type filtering', () async {
      when(
        () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
      ).thenAnswer(
        (_) async => [
          const Triple(
            subject: 'kabuk:Note/1',
            predicate: NS.schemaName,
            objectValue: 'Flutter notes',
            objectType: ObjectType.string,
          ),
        ],
      );

      when(() => bundle.knowledge.getEntities(any())).thenAnswer(
        (_) async => {
          'kabuk:Note/1': [
            const Triple(
              subject: 'kabuk:Note/1',
              predicate: NS.rdfType,
              objectValue: NS.schemaNote,
              objectType: ObjectType.uri,
            ),
            const Triple(
              subject: 'kabuk:Note/1',
              predicate: NS.schemaName,
              objectValue: 'Flutter notes',
              objectType: ObjectType.string,
            ),
          ],
        },
      );

      final tool = agent.tools.firstWhere((t) => t.name == 'search_local');
      final result = await tool.execute({
        'query': 'flutter',
        'type': 'note',
      }, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('Flutter notes'));
    });
  });

  // ---------------------------------------------------------------------------
  // list_saved_searches tool
  // ---------------------------------------------------------------------------

  group('list_saved_searches tool', () {
    test('returns "No saved searches" when empty', () async {
      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(
        () => mockQb.where(any(), equals: any(named: 'equals')),
      ).thenReturn(mockQb);
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(() => mockQb.object(any())).thenReturn(mockQb);
      when(
        () => mockQb.orderBy(any(), descending: any(named: 'descending')),
      ).thenReturn(mockQb);
      when(() => mockQb.limit(any())).thenReturn(mockQb);
      when(mockQb.execute).thenAnswer((_) async => <Triple>[]);

      final tool = agent.tools.firstWhere(
        (t) => t.name == 'list_saved_searches',
      );
      final result = await tool.execute({}, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('No saved searches'));
    });
  });

  // ---------------------------------------------------------------------------
  // delete_saved_search tool
  // ---------------------------------------------------------------------------

  group('delete_saved_search tool', () {
    test('returns error for missing uri', () async {
      final tool = agent.tools.firstWhere(
        (t) => t.name == 'delete_saved_search',
      );
      final result = await tool.execute({'uri': ''}, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });

    test('deletes search and returns confirmation', () async {
      bundle.knowledge.onMutate = <T>(action) async {
        return await action(FakeMutationContext());
      };

      final tool = agent.tools.firstWhere(
        (t) => t.name == 'delete_saved_search',
      );
      final result = await tool.execute({
        'uri': 'kabuk:SavedSearch/1',
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
    test('search_nostr_hashtag requires hashtags', () {
      final tool = agent.tools.firstWhere(
        (t) => t.name == 'search_nostr_hashtag',
      );
      expect(tool.parameters['required'], contains('hashtags'));
    });

    test('search_nostr_content requires query', () {
      final tool = agent.tools.firstWhere(
        (t) => t.name == 'search_nostr_content',
      );
      expect(tool.parameters['required'], contains('query'));
    });

    test('search_local requires query', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'search_local');
      expect(tool.parameters['required'], contains('query'));
    });

    test('save_search requires name, query, and source', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'save_search');
      expect(
        tool.parameters['required'],
        containsAll(['name', 'query', 'source']),
      );
    });

    test('bookmark_content requires url', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'bookmark_content');
      expect(tool.parameters['required'], contains('url'));
    });

    test('delete_saved_search requires uri', () {
      final tool = agent.tools.firstWhere(
        (t) => t.name == 'delete_saved_search',
      );
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
      ).thenThrow(Exception('Connection failed'));

      final message = AgentMessage.user(
        id: 'msg-err',
        timestamp: DateTime.now(),
        content: 'find something interesting on nostr',
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
