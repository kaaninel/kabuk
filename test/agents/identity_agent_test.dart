/// Tests for [IdentityAgent] — Nostr identity management agent.
///
/// Verifies agent metadata, tool declarations, and LLM integration.
/// Uses mocked [AgentContext] with [MockNostrService] and [MockAuthService].
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart' show AgentContext;
import 'package:kabuk/agents/domains/identity_agent.dart';
import 'package:kabuk/agents/exports.dart' show AgentContext;
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late IdentityAgent agent;
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
    registerFallbackValue(fakeMutationAction);
  });

  setUp(() {
    agent = IdentityAgent();
    bundle = createMockAgentContext();
  });

  // ---------------------------------------------------------------------------
  // Agent metadata
  // ---------------------------------------------------------------------------

  group('IdentityAgent metadata', () {
    test('name is "identity"', () {
      expect(agent.name, 'identity');
    });

    test('description is non-empty', () {
      expect(agent.description, isNotEmpty);
    });

    test('systemPrompt mentions Nostr', () {
      expect(agent.systemPrompt.toLowerCase(), contains('nostr'));
    });

    test('declares all 12 tools', () {
      final toolNames = agent.tools.map((t) => t.name).toList();
      expect(
        toolNames,
        containsAll([
          'get_identity',
          'publish_note',
          'update_profile',
          'list_relays',
          'add_relay',
          'remove_relay',
          'fetch_profile',
          'read_feed',
          'sign_message',
          'list_identities',
          'switch_identity',
          'remove_identity',
        ]),
      );
      expect(toolNames.length, 12);
    });

    test('requires knowledgeRead and llmCall', () {
      expect(
        agent.requiredCapabilities,
        containsAll([AgentCapability.knowledgeRead, AgentCapability.llmCall]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // process() — text response
  // ---------------------------------------------------------------------------

  group('process() with TextLlmResponse', () {
    test('returns text response from LLM', () async {
      stubLlmStreamText(bundle.llm, 'Your npub is npub1abc...');

      final message = AgentMessage.user(
        id: 'msg-1',
        timestamp: DateTime.now(),
        content: 'What is my identity?',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, 'Your npub is npub1abc...');
    });
  });

  // ---------------------------------------------------------------------------
  // process() — tool calls
  // ---------------------------------------------------------------------------

  group('process() with tool calls', () {
    test('handles get_identity tool call', () async {
      var callCount = 0;
      when(() => bundle.llm.stream(any())).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          return Stream.fromIterable([
            const LlmStreamEvent.toolCall(
              LlmToolCall(
                id: 'tc1',
                name: 'get_identity',
                arguments: <String, dynamic>{},
              ),
            ),
            const LlmStreamEvent.done(),
          ]);
        }
        return Stream.fromIterable([
          const LlmStreamEvent.textDelta('Here is your identity info.'),
          const LlmStreamEvent.done(),
        ]);
      });

      when(() => bundle.auth.currentUser).thenAnswer((_) async => null);

      final message = AgentMessage.user(
        id: 'msg-2',
        timestamp: DateTime.now(),
        content: 'Show my identity',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      await collectStreamingText(response);
      verify(() => bundle.llm.stream(any())).called(greaterThanOrEqualTo(2));
    });

    test('handles list_relays tool call', () async {
      var callCount = 0;
      when(() => bundle.llm.stream(any())).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          return Stream.fromIterable([
            const LlmStreamEvent.toolCall(
              LlmToolCall(
                id: 'tc1',
                name: 'list_relays',
                arguments: <String, dynamic>{},
              ),
            ),
            const LlmStreamEvent.done(),
          ]);
        }
        return Stream.fromIterable([
          const LlmStreamEvent.textDelta('You have 0 relays configured.'),
          const LlmStreamEvent.done(),
        ]);
      });

      when(() => bundle.nostr.relays).thenReturn([]);
      when(() => bundle.nostr.connectedRelays).thenReturn([]);

      final message = AgentMessage.user(
        id: 'msg-3',
        timestamp: DateTime.now(),
        content: 'List my relays',
      );

      final response = await agent.process(message, bundle.context);
      expect(response, isA<StreamingAgentResponse>());
      await collectStreamingText(response);
    });
  });

  // ---------------------------------------------------------------------------
  // process() — error response
  // ---------------------------------------------------------------------------

  group('process() with ErrorLlmResponse', () {
    test('returns error response', () async {
      stubLlmStreamError(bundle.llm, 'Rate limited');

      final message = AgentMessage.user(
        id: 'msg-4',
        timestamp: DateTime.now(),
        content: 'Publish a note',
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
  // Tool schemas
  // ---------------------------------------------------------------------------

  group('tool parameter schemas', () {
    test('publish_note requires content', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'publish_note');
      final schema = tool.parameters;
      final required = schema['required'] as List;
      expect(required, contains('content'));
    });

    test('add_relay requires url', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'add_relay');
      final schema = tool.parameters;
      final required = schema['required'] as List;
      expect(required, contains('url'));
    });

    test('fetch_profile requires pubkey', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'fetch_profile');
      final schema = tool.parameters;
      final required = schema['required'] as List;
      expect(required, contains('pubkey'));
    });

    test('sign_message requires message', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'sign_message');
      final schema = tool.parameters;
      final required = schema['required'] as List;
      expect(required, contains('message'));
    });

    test('get_identity has no required params', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'get_identity');
      final schema = tool.parameters;
      expect(schema.containsKey('required'), isFalse);
    });
  });
}
