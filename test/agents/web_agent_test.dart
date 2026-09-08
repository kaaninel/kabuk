import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/domains/web_agent.dart';
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/services/channels.dart';
import '../helpers/mocks.dart';

void main() {
  late MockAgentContextBundle bundle;

  setUp(() {
    bundle = createMockAgentContext();
  });

  group('WebAgent tools', () {
    test('exposes web and channel search tools', () {
      final agent = WebAgent();
      final names = agent.tools.map((t) => t.name).toSet();
      expect(
        names,
        containsAll([
          'web_search',
          'web_fetch',
          'reddit_search',
          'reddit_list',
          'nostr_search',
          'nostr_hashtag',
          'usenet_search',
          'rss_fetch',
        ]),
      );
      expect(agent.name, 'web');
      expect(agent.description, isNotEmpty);
    });

    test('web_search returns a channel with items from the registry', () async {
      final registry = _allChannelsRegistry();
      final context = _contextWithRegistry(registry);

      final agent = WebAgent();
      final tool = agent.tools.firstWhere((t) => t.name == 'web_search');
      final result = await tool.execute({'query': 'flutter'}, context);

      expect(result, isA<ChannelToolResult>());
      final channel = result as ChannelToolResult;
      expect(channel.items, hasLength(1));
      expect(channel.items.single.title, 'Result');
      expect(channel.channel.title, contains('flutter'));
      expect(channel.channel.sourcePluginId, 'web');
    });

    test('web_search returns an error when the registry is unavailable',
        () async {
      final agent = WebAgent();
      final tool = agent.tools.firstWhere((t) => t.name == 'web_search');
      final result = await tool.execute({'query': 'flutter'}, bundle.context);
      expect(result, isA<ErrorToolResult>());
    });

    test('web_fetch returns text from the registry', () async {
      final registry = _allChannelsRegistry();
      final context = _contextWithRegistry(registry);

      final agent = WebAgent();
      final tool = agent.tools.firstWhere((t) => t.name == 'web_fetch');
      final result = await tool.execute({'url': 'https://example.com'}, context);
      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, 'page body');
    });

    test('web_fetch returns an error when the registry is unavailable',
        () async {
      final agent = WebAgent();
      final tool = agent.tools.firstWhere((t) => t.name == 'web_fetch');
      final result = await tool.execute({'url': 'https://x.com'}, bundle.context);
      expect(result, isA<ErrorToolResult>());
    });

    test('reddit_search returns a channel via the registry', () async {
      final registry = _allChannelsRegistry();
      final context = _contextWithRegistry(registry);

      final agent = WebAgent();
      final tool = agent.tools.firstWhere((t) => t.name == 'reddit_search');
      final result = await tool.execute({'query': 'flutter'}, context);

      expect(result, isA<ChannelToolResult>());
      final channel = result as ChannelToolResult;
      expect(channel.channel.sourcePluginId, 'reddit');
      expect(channel.items, isNotEmpty);
    });

    test('usenet_search returns a channel via the registry', () async {
      final registry = _allChannelsRegistry();
      final context = _contextWithRegistry(registry);

      final agent = WebAgent();
      final tool = agent.tools.firstWhere((t) => t.name == 'usenet_search');
      final result = await tool.execute({'query': 'dune'}, context);

      expect(result, isA<ChannelToolResult>());
      expect((result as ChannelToolResult).channel.sourcePluginId, 'usenet');
    });

    test('channel tools return an error when the registry is unavailable',
        () async {
      final agent = WebAgent();
      final tool = agent.tools.firstWhere((t) => t.name == 'reddit_search');
      final result = await tool.execute({'query': 'x'}, bundle.context);
      expect(result, isA<ErrorToolResult>());
    });
  });
}

AgentContext _contextWithRegistry(ChannelRegistry registry) {
  final b = createMockAgentContext();
  return AgentContext(
    knowledge: b.knowledge,
    vault: b.vault,
    mesh: b.mesh,
    media: b.media,
    auth: b.auth,
    notification: b.notification,
    presentation: b.presentation,
    llm: b.llm,
    runtime: b.runtime,
    channelRegistry: registry,
  );
}

/// A registry with fake servers for every channel the agent can invoke.
ChannelRegistry _allChannelsRegistry() {
  final registry = ChannelRegistry();
  for (final id in ['web', 'reddit', 'nostr', 'usenet', 'rss']) {
    registry.register(_FakeWebServer(id));
  }
  return registry;
}

class _FakeWebServer implements ChannelServer {
  _FakeWebServer([this.id = 'web']);

  @override
  final String id;
  @override
  String get name => id;
  @override
  String get description => 'fake';

  @override
  List<ChannelTool> listTools() => const [
    ChannelTool(name: 'web_search', description: 'search'),
    ChannelTool(name: 'web_fetch', description: 'fetch'),
    ChannelTool(name: 'reddit_search', description: 'search'),
    ChannelTool(name: 'reddit_list', description: 'list'),
    ChannelTool(name: 'nostr_search', description: 'search'),
    ChannelTool(name: 'nostr_hashtag', description: 'hashtag'),
    ChannelTool(name: 'usenet_search', description: 'search'),
    ChannelTool(name: 'rss_fetch', description: 'fetch'),
  ];

  @override
  Future<ChannelCallResult> callTool(
    String tool,
    Map<String, dynamic> args,
  ) async {
    switch (tool) {
      case 'web_search' || 'reddit_search' || 'reddit_list' ||
            'nostr_search' || 'nostr_hashtag' || 'usenet_search' ||
            'rss_fetch':
        return const ChannelCallResult.content([
          ContentItem(
            sourcePluginId: 'web',
            externalId: '1',
            contentType: ContentType.article,
            title: 'Result',
            url: 'https://example.com/1',
          ),
        ]);
      case 'web_fetch':
        return const ChannelCallResult.text('page body');
      default:
        return ChannelCallResult.error('unknown tool $tool');
    }
  }

  @override
  List<ChannelResource> listResources() => const [];

  @override
  Future<ChannelResource> readResource(String uri) async =>
      throw ArgumentError('no resources');
}