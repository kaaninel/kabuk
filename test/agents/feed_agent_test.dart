import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/domains/feed_agent.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:kabuk/services/feed.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late FeedAgent agent;
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
    registerFallbackValue(fakeMutationAction);
    registerFallbackValue(FeedSourceType.rss);
  });

  setUp(() {
    agent = FeedAgent();
    bundle = createMockAgentContext();
  });

  // ---------------------------------------------------------------------------
  // Agent metadata
  // ---------------------------------------------------------------------------

  group('FeedAgent metadata', () {
    test('name is "feeds"', () {
      expect(agent.name, 'feeds');
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
          'subscribe_feed',
          'list_feeds',
          'unsubscribe_feed',
          'refresh_feed',
          'list_articles',
          'search_articles',
          'mark_read',
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
      stubLlmStreamText(bundle.llm, 'Here are your feeds!');

      final message = AgentMessage.user(
        id: 'msg-1',
        timestamp: DateTime.now(),
        content: 'What feeds do I have?',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, 'Here are your feeds!');
    });
  });

  group('process() with ErrorLlmResponse', () {
    test('returns error response', () async {
      stubLlmStreamError(bundle.llm, 'Rate limited');

      final message = AgentMessage.user(
        id: 'msg-2',
        timestamp: DateTime.now(),
        content: 'Subscribe to a feed',
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
        toolName: 'list_feeds',
        arguments: {},
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<TextAgentResponse>());
      expect((response as TextAgentResponse).content, contains('feed'));
      verifyNever(() => bundle.llm.stream(any()));
    });
  });

  // ---------------------------------------------------------------------------
  // Direct dispatch — subscribe patterns
  // ---------------------------------------------------------------------------

  group('process() direct dispatch', () {
    test('handles r/subreddit pattern directly', () async {
      // Feed service must be available for subscribe
      final mockSource = MockFeedSource();
      when(
        () => bundle.feed.detectType(any()),
      ).thenAnswer((_) async => FeedSourceType.reddit);
      when(() => bundle.feed.getSource(any())).thenReturn(mockSource);
      when(() => mockSource.validate(any())).thenAnswer((_) async => true);
      when(
        () => bundle.feed.fetchItems(any(), type: any(named: 'type')),
      ).thenAnswer((_) async => <FeedItem>[]);

      // Stub knowledge store for subscription creation + listFeedSubscriptions
      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(() => mockQb.object(any())).thenReturn(mockQb);
      when(
        () => mockQb.where(any(), equals: any(named: 'equals')),
      ).thenReturn(mockQb);
      when(() => mockQb.limit(any())).thenReturn(mockQb);
      when(
        () => mockQb.orderBy(any(), descending: any(named: 'descending')),
      ).thenReturn(mockQb);
      when(mockQb.execute).thenAnswer((_) async => <Triple>[]);

      bundle.knowledge.onMutate = <T>(action) async {
        return await action(FakeMutationContext());
      };

      final message = AgentMessage.user(
        id: 'msg-dd-1',
        timestamp: DateTime.now(),
        content: 'subscribe to r/flutter',
      );

      final response = await agent.process(message, bundle.context);

      // Should handle directly without LLM
      verifyNever(() => bundle.llm.stream(any()));
      expect(response, isA<TextAgentResponse>());
    });

    test('handles "list feeds" pattern directly', () async {
      // Stub listFeedSubscriptions via query().predicate().object().execute()
      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(() => mockQb.object(any())).thenReturn(mockQb);
      when(() => mockQb.limit(any())).thenReturn(mockQb);
      when(
        () => mockQb.where(any(), equals: any(named: 'equals')),
      ).thenReturn(mockQb);
      when(
        () => mockQb.orderBy(any(), descending: any(named: 'descending')),
      ).thenReturn(mockQb);
      when(mockQb.execute).thenAnswer((_) async => <Triple>[]);

      final message = AgentMessage.user(
        id: 'msg-dd-2',
        timestamp: DateTime.now(),
        content: 'list feeds',
      );

      final response = await agent.process(message, bundle.context);

      verifyNever(() => bundle.llm.stream(any()));
      expect(response, isA<TextAgentResponse>());
    });
  });

  // ---------------------------------------------------------------------------
  // search_articles tool
  // ---------------------------------------------------------------------------

  group('search_articles tool', () {
    test('returns error for empty query', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'search_articles');
      final result = await tool.execute({'query': ''}, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });

    test('returns "No articles found" when no matches', () async {
      when(
        () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
      ).thenAnswer((_) async => <Triple>[]);

      final tool = agent.tools.firstWhere((t) => t.name == 'search_articles');
      final result = await tool.execute({'query': 'flutter'}, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('No articles'));
    });

    test('returns formatted articles when found', () async {
      when(
        () => bundle.knowledge.search(any(), limit: any(named: 'limit')),
      ).thenAnswer(
        (_) async => [
          const Triple(
            subject: 'kabuk:Article/1',
            predicate: NS.schemaName,
            objectValue: 'Flutter 4.0 Released',
            objectType: ObjectType.string,
          ),
        ],
      );

      when(() => bundle.knowledge.getEntities(any())).thenAnswer(
        (_) async => {
          'kabuk:Article/1': [
            const Triple(
              subject: 'kabuk:Article/1',
              predicate: NS.rdfType,
              objectValue: NS.schemaArticle,
              objectType: ObjectType.uri,
            ),
            const Triple(
              subject: 'kabuk:Article/1',
              predicate: NS.schemaName,
              objectValue: 'Flutter 4.0 Released',
              objectType: ObjectType.string,
            ),
            const Triple(
              subject: 'kabuk:Article/1',
              predicate: NS.schemaUrl,
              objectValue: 'https://flutter.dev/blog',
              objectType: ObjectType.string,
            ),
          ],
        },
      );

      final tool = agent.tools.firstWhere((t) => t.name == 'search_articles');
      final result = await tool.execute({'query': 'flutter'}, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('Flutter 4.0'));
    });
  });

  // ---------------------------------------------------------------------------
  // list_feeds tool
  // ---------------------------------------------------------------------------

  group('list_feeds tool', () {
    test('returns "No feeds" when empty', () async {
      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(() => mockQb.object(any())).thenReturn(mockQb);
      when(() => mockQb.limit(any())).thenReturn(mockQb);
      when(
        () => mockQb.where(any(), equals: any(named: 'equals')),
      ).thenReturn(mockQb);
      when(
        () => mockQb.orderBy(any(), descending: any(named: 'descending')),
      ).thenReturn(mockQb);
      when(mockQb.execute).thenAnswer((_) async => <Triple>[]);

      final tool = agent.tools.firstWhere((t) => t.name == 'list_feeds');
      final result = await tool.execute({}, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('No feed'));
    });
  });

  // ---------------------------------------------------------------------------
  // unsubscribe_feed tool
  // ---------------------------------------------------------------------------

  group('unsubscribe_feed tool', () {
    test('returns error for missing uri', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'unsubscribe_feed');
      final result = await tool.execute({'uri': ''}, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });
  });

  // ---------------------------------------------------------------------------
  // mark_read tool
  // ---------------------------------------------------------------------------

  group('mark_read tool', () {
    test('returns error for missing uri', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'mark_read');
      final result = await tool.execute({'uri': ''}, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });
  });

  // ---------------------------------------------------------------------------
  // Tool schema validation
  // ---------------------------------------------------------------------------

  group('tool schemas', () {
    test('subscribe_feed requires url', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'subscribe_feed');
      expect(tool.parameters['required'], contains('url'));
    });

    test('search_articles requires query', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'search_articles');
      expect(tool.parameters['required'], contains('query'));
    });

    test('unsubscribe_feed requires uri', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'unsubscribe_feed');
      expect(tool.parameters['required'], contains('uri'));
    });

    test('mark_read requires uri', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'mark_read');
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
        content: 'what feeds exist',
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
