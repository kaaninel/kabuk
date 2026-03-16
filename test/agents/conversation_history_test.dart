/// Tests that domain agents pass conversation history to LLM requests.
///
/// Verifies that all domain agents include prior conversation messages
/// in their LLM calls when history is provided via [UserMessage].
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/domains/calendar_agent.dart';
import 'package:kabuk/agents/domains/contact_agent.dart';
import 'package:kabuk/agents/domains/file_agent.dart';
import 'package:kabuk/agents/domains/identity_agent.dart';
import 'package:kabuk/agents/domains/note_agent.dart';
import 'package:kabuk/agents/domains/search_agent.dart';
import 'package:kabuk/agents/domains/system_agent.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
    registerFallbackValue(fakeMutationAction);
  });

  setUp(() {
    bundle = createMockAgentContext();
  });

  /// Captures the [LlmRequest] sent to the LLM stream() call.
  LlmRequest captureLlmRequest() {
    final captured = verify(() => bundle.llm.stream(captureAny())).captured;
    return captured.first as LlmRequest;
  }

  /// Creates a user message with conversation history.
  AgentMessage messageWithHistory(String content) {
    return AgentMessage.user(
      id: 'msg-hist',
      timestamp: DateTime.now(),
      content: content,
      history: const [
        LlmMessage.user('What is the weather?'),
        LlmMessage.assistant('It is sunny today.'),
        LlmMessage.user('Tell me more'),
        LlmMessage.assistant('The temperature is 25°C.'),
      ],
    );
  }

  /// Creates a user message without history.
  AgentMessage messageWithoutHistory(String content) {
    return AgentMessage.user(
      id: 'msg-no-hist',
      timestamp: DateTime.now(),
      content: content,
    );
  }

  // -------------------------------------------------------------------------
  // NoteAgent
  // -------------------------------------------------------------------------

  group('NoteAgent conversation history', () {
    late NoteAgent agent;

    setUp(() {
      agent = NoteAgent();
    });

    test('includes history in LLM request when present', () async {
      stubLlmStreamText(bundle.llm, 'Here are your notes.');

      final response = await agent.process(
        messageWithHistory('List notes'),
        bundle.context,
      );
      await collectStreamingText(response);

      final request = captureLlmRequest();
      // 4 history messages + 1 current user message = 5
      expect(request.messages, hasLength(5));
      expect(request.messages.first, isA<UserLlmMessage>());
      expect(
        (request.messages.first as UserLlmMessage).content,
        'What is the weather?',
      );
      expect(request.messages.last, isA<UserLlmMessage>());
      expect((request.messages.last as UserLlmMessage).content, 'List notes');
    });

    test('works without history (single message)', () async {
      stubLlmStreamText(bundle.llm, 'Here are your notes.');

      final response = await agent.process(
        messageWithoutHistory('List notes'),
        bundle.context,
      );
      await collectStreamingText(response);

      final request = captureLlmRequest();
      expect(request.messages, hasLength(1));
      expect((request.messages.first as UserLlmMessage).content, 'List notes');
    });
  });

  // -------------------------------------------------------------------------
  // ContactAgent
  // -------------------------------------------------------------------------

  group('ContactAgent conversation history', () {
    test('includes history in LLM request', () async {
      final agent = ContactAgent();
      stubLlmStreamText(bundle.llm, 'Contact found.');

      final response = await agent.process(
        messageWithHistory('Find Alice'),
        bundle.context,
      );
      await collectStreamingText(response);

      final request = captureLlmRequest();
      expect(request.messages, hasLength(5));
    });
  });

  // -------------------------------------------------------------------------
  // CalendarAgent
  // -------------------------------------------------------------------------

  group('CalendarAgent conversation history', () {
    test('includes history in LLM request', () async {
      final agent = CalendarAgent();
      stubLlmStreamText(bundle.llm, 'No events today.');

      final response = await agent.process(
        messageWithHistory('Any events today?'),
        bundle.context,
      );
      await collectStreamingText(response);

      final request = captureLlmRequest();
      expect(request.messages, hasLength(5));
    });
  });

  // -------------------------------------------------------------------------
  // FileAgent
  // -------------------------------------------------------------------------

  group('FileAgent conversation history', () {
    test('includes history in LLM request', () async {
      final agent = FileAgent();
      stubLlmStreamText(bundle.llm, 'Files listed.');

      final response = await agent.process(
        messageWithHistory('Show my files'),
        bundle.context,
      );
      await collectStreamingText(response);

      final request = captureLlmRequest();
      expect(request.messages, hasLength(5));
    });
  });

  // -------------------------------------------------------------------------
  // SearchAgent
  // -------------------------------------------------------------------------

  group('SearchAgent conversation history', () {
    test('includes history in LLM request', () async {
      final agent = SearchAgent();
      stubLlmStreamText(bundle.llm, 'Results found.');

      final response = await agent.process(
        messageWithHistory('Search for photos'),
        bundle.context,
      );
      await collectStreamingText(response);

      final request = captureLlmRequest();
      expect(request.messages, hasLength(5));
    });
  });

  // -------------------------------------------------------------------------
  // SystemAgent
  // -------------------------------------------------------------------------

  group('SystemAgent conversation history', () {
    test('includes history in LLM request', () async {
      final agent = SystemAgent();
      stubLlmStreamText(bundle.llm, 'System info.');

      final response = await agent.process(
        messageWithHistory('Show system status'),
        bundle.context,
      );
      await collectStreamingText(response);

      final request = captureLlmRequest();
      expect(request.messages, hasLength(5));
    });
  });

  // -------------------------------------------------------------------------
  // IdentityAgent
  // -------------------------------------------------------------------------

  group('IdentityAgent conversation history', () {
    test('includes history in LLM request', () async {
      final agent = IdentityAgent();
      stubLlmStreamText(bundle.llm, 'Identity info.');

      final response = await agent.process(
        messageWithHistory('Show my identity'),
        bundle.context,
      );
      await collectStreamingText(response);

      final request = captureLlmRequest();
      expect(request.messages, hasLength(5));
    });
  });
}
