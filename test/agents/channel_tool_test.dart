import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/channels.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/agents/observation.dart';
import 'package:kabuk/plugins/channel.dart';
import 'package:kabuk/plugins/content_item.dart';

import '../helpers/mocks.dart';

/// Minimal agent whose single tool returns a [ToolResult.channel].
class _ChannelAgent extends BaseAgent {
  @override
  String get name => 'channel-agent';

  @override
  String get description => 'Test agent that populates channels';

  @override
  String get systemPrompt => 'You populate channels.';

  @override
  List<AgentTool> get tools => [
    AgentTool(
      name: 'make_channel',
      description: 'Make a test channel.',
      parameters: {
        'type': 'object',
        'properties': <String, dynamic>{},
      },
      execute: (args, ctx) async => ToolResult.channel(
        channel: const Channel(
          entityUri: 'kabuk:test/example-com',
          entityType: ChannelEntityType.website,
          title: 'Example',
        ),
        items: [
          ContentItem(
            sourcePluginId: 'test',
            externalId: '1',
            contentType: ContentType.article,
            title: 'First result',
            url: 'https://example.com/a',
          ),
          ContentItem(
            sourcePluginId: 'test',
            externalId: '2',
            contentType: ContentType.video,
            title: 'Second result',
          ),
        ],
        summary: 'Found 2 results.',
      ),
    ),
  ];

  @override
  Set<AgentCapability> get requiredCapabilities => {
    AgentCapability.knowledgeRead,
  };

  @override
  Future<AgentResponse> process(
    AgentMessage message,
    AgentContext context,
  ) async => const AgentResponse.text('ok');
}

void main() {
  late MockAgentContextBundle bundle;
  late AgentChannelController channels;
  late ObservationBus bus;
  late AgentContext context;
  late _ChannelAgent agent;

  setUp(() {
    bundle = createMockAgentContext();
    channels = AgentChannelController();
    bus = ObservationBus();
    context = AgentContext(
      knowledge: bundle.knowledge,
      vault: bundle.vault,
      mesh: bundle.mesh,
      media: bundle.media,
      auth: bundle.auth,
      notification: bundle.notification,
      presentation: bundle.presentation,
      llm: bundle.llm,
      runtime: bundle.runtime,
      channels: channels,
      observation: bus,
    );
    agent = _ChannelAgent();
  });

  test('ToolResult.channel serializes to a wire-safe map', () {
    final result = ToolResult.channel(
      channel: const Channel(
        entityUri: 'kabuk:test/x',
        entityType: ChannelEntityType.topic,
        title: 'X',
      ),
      items: [
        ContentItem(
          sourcePluginId: 's',
          externalId: 'i',
          contentType: ContentType.video,
          title: 'T',
          url: 'https://x/v',
        ),
      ],
      summary: 'sum',
    );

    final json = result.toJson();
    expect(json['type'], 'channel');
    expect(json['channelUri'], 'kabuk:test/x');
    expect(json['title'], 'X');
    expect(json['items'], hasLength(1));
    expect(json['items'][0]['contentType'], 'video');
    expect(json['summary'], 'sum');
  });

  test('executeTool populates the active channel session', () async {
    final tool = agent.tools.first;
    final result = await agent.executeTool(tool, const {}, context);

    expect(result, isA<ChannelToolResult>());
    final session = channels.current;
    expect(session, isNotNull);
    expect(session!.channel.title, 'Example');
    expect(session.channel.entityUri, 'kabuk:test/example-com');
    expect(session.items, hasLength(2));
    expect(session.items.first.title, 'First result');
    expect(session.summary, 'Found 2 results.');
    expect(session.agentName, 'channel-agent');
  });

  test('executeTool publishes a ChannelPopulatedEvent', () async {
    final events = <ObservationEvent>[];
    final sub = bus.stream.listen(events.add);
    final tool = agent.tools.first;

    await agent.executeTool(tool, const {}, context);
    // Broadcast stream delivery is async — flush microtasks.
    await pumpEventQueue();

    expect(events, hasLength(1));
    final event = events.single;
    expect(event, isA<ChannelPopulatedEvent>());
    final populated = event as ChannelPopulatedEvent;
    expect(populated.channelUri, 'kabuk:test/example-com');
    expect(populated.title, 'Example');
    expect(populated.itemCount, 2);
    expect(populated.agentName, 'channel-agent');
    expect(populated.summary, 'Found 2 results.');

    await sub.cancel();
  });

  test('does not touch the channel controller for non-channel results', () async {
    final agent = _TextOnlyAgent();
    final tool = agent.tools.first;
    await agent.executeTool(tool, const {}, context);
    expect(channels.current, isNull);
  });
}

class _TextOnlyAgent extends BaseAgent {
  @override
  String get name => 'text-agent';

  @override
  String get description => '';

  @override
  String get systemPrompt => '';

  @override
  List<AgentTool> get tools => [
    AgentTool(
      name: 'say_hi',
      description: 'Say hi.',
      parameters: {
        'type': 'object',
        'properties': <String, dynamic>{},
      },
      execute: (args, ctx) async => const ToolResult.text('hi'),
    ),
  ];

  @override
  Set<AgentCapability> get requiredCapabilities => const {};

  @override
  Future<AgentResponse> process(
    AgentMessage message,
    AgentContext context,
  ) async => const AgentResponse.text('hi');
}