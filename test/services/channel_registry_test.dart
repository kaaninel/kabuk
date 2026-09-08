import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/services/channels.dart';

void main() {
  group('ChannelRegistry', () {
    test('registers servers and lists the union of tools', () {
      final registry = ChannelRegistry()
        ..register(_FakeServer('a', ['tool_a']))
        ..register(_FakeServer('b', ['tool_b', 'tool_c']));

      expect(registry.servers, hasLength(2));
      expect(registry.server('a'), isNotNull);
      expect(registry.server('missing'), isNull);
      expect(registry.listTools().map((t) => t.name), [
        'tool_a',
        'tool_b',
        'tool_c',
      ]);
    });

    test('invoke dispatches to the right server and tool', () async {
      final registry = ChannelRegistry()..register(_FakeServer('a', ['ping']));
      final result = await registry.invoke('a', 'ping', {'x': 1});
      expect(result, isA<ChannelTextResult>());
      expect((result as ChannelTextResult).content, 'pong');
    });

    test('invoke returns an error for an unknown server', () async {
      final registry = ChannelRegistry();
      final result = await registry.invoke('missing', 'x', {});
      expect(result, isA<ChannelErrorResult>());
    });

    test('invoke returns an error for an unknown tool', () async {
      final registry = ChannelRegistry()..register(_FakeServer('a', ['ok']));
      final result = await registry.invoke('a', 'nope', {});
      expect(result, isA<ChannelErrorResult>());
    });

    test('invoke catches server exceptions and returns an error', () async {
      final registry = ChannelRegistry()..register(_FakeServer('a', ['boom']));
      final result = await registry.invoke('a', 'boom', {});
      expect(result, isA<ChannelErrorResult>());
    });

    test('content result carries typed items', () {
      const result = ChannelCallResult.content([
        ContentItem(
          sourcePluginId: 'web',
          externalId: '1',
          contentType: ContentType.article,
          title: 'T',
        ),
      ]);
      expect(result, isA<ChannelContentResult>());
      expect((result as ChannelContentResult).items.single.title, 'T');
    });
  });
}

class _FakeServer implements ChannelServer {
  _FakeServer(this.id, List<String> toolNames)
      : _tools = [
          for (final n in toolNames)
            ChannelTool(name: n, description: 'tool $n'),
        ];

  @override
  final String id;

  final List<ChannelTool> _tools;

  @override
  String get name => id;
  @override
  String get description => 'fake server $id';

  @override
  List<ChannelTool> listTools() => _tools;

  @override
  Future<ChannelCallResult> callTool(
    String tool,
    Map<String, dynamic> args,
  ) async {
    if (tool == 'boom') throw StateError('boom');
    if (tool == 'ping') {
      return const ChannelCallResult.text('pong');
    }
    return ChannelCallResult.error('unknown tool $tool');
  }

  @override
  List<ChannelResource> listResources() => const [];

  @override
  Future<ChannelResource> readResource(String uri) async =>
      throw ArgumentError('no resources');
}