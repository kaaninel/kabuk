/// Tests for the privacy filter — anonymization and de-anonymization.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/privacy_filter.dart';

void main() {
  group('AnonymizationMap', () {
    test('deAnonymize replaces placeholders with original values', () {
      final map = const AnonymizationMap(
        replacements: {'[PERSON_1]': 'Alice', '[EMAIL_1]': 'alice@example.com'},
        originalPrompt: 'Send Alice an email at alice@example.com',
        anonymizedPrompt: 'Send [PERSON_1] an email at [EMAIL_1]',
      );

      expect(
        map.deAnonymize('I sent a message to [PERSON_1] at [EMAIL_1].'),
        'I sent a message to Alice at alice@example.com.',
      );
    });

    test('deAnonymize with no replacements returns text unchanged', () {
      expect(AnonymizationMap.empty.deAnonymize('Hello world'), 'Hello world');
    });

    test('hasReplacements returns false for empty map', () {
      expect(AnonymizationMap.empty.hasReplacements, isFalse);
    });

    test('hasReplacements returns true when replacements exist', () {
      final map = const AnonymizationMap(
        replacements: {'[PERSON_1]': 'Bob'},
        originalPrompt: 'Hi Bob',
        anonymizedPrompt: 'Hi [PERSON_1]',
      );
      expect(map.hasReplacements, isTrue);
    });
  });

  group('PrivacyFilter — regex fallback', () {
    // Test without a local LLM to exercise the regex-based fallback.
    const filter = PrivacyFilter(localLlm: null);

    test('anonymizes email addresses', () async {
      final request = LlmRequest(
        messages: [
          const LlmMessage.user('Email me at john.doe@example.com please'),
        ],
      );

      final result = await filter.anonymizeRequest(
        request,
        PrivacyLevel.standard,
      );

      expect(result.map.hasReplacements, isTrue);
      expect(result.map.replacements.values, contains('john.doe@example.com'));

      // The anonymized message should not contain the email.
      final msg = result.request.messages.first;
      expect(msg, isA<UserLlmMessage>());
      expect(
        (msg as UserLlmMessage).content,
        isNot(contains('john.doe@example.com')),
      );
    });

    test('anonymizes phone numbers', () async {
      final request = LlmRequest(
        messages: [const LlmMessage.user('Call me at 555-123-4567')],
      );

      final result = await filter.anonymizeRequest(
        request,
        PrivacyLevel.standard,
      );

      expect(result.map.hasReplacements, isTrue);
      expect(result.map.replacements.values, contains('555-123-4567'));
    });

    test('anonymizes IP addresses', () async {
      final request = LlmRequest(
        messages: [const LlmMessage.user('My server is at 192.168.1.42')],
      );

      final result = await filter.anonymizeRequest(
        request,
        PrivacyLevel.standard,
      );

      expect(result.map.hasReplacements, isTrue);
      expect(result.map.replacements.values, contains('192.168.1.42'));
    });

    test('skips anonymization when privacy level is none', () async {
      final request = LlmRequest(
        messages: [const LlmMessage.user('Email me at alice@example.com')],
      );

      final result = await filter.anonymizeRequest(request, PrivacyLevel.none);

      expect(result.map.hasReplacements, isFalse);
      expect(result.request, same(request));
    });

    test('does not modify system or tool result messages', () async {
      final request = LlmRequest(
        messages: [
          const LlmMessage.system('You are a helpful assistant.'),
          const LlmMessage.user('nothing to anonymize here'),
          const LlmMessage.toolResult(
            callId: 'tc_1',
            content: 'secret@email.com',
          ),
        ],
      );

      final result = await filter.anonymizeRequest(
        request,
        PrivacyLevel.standard,
      );

      // System and tool result messages should be unchanged.
      expect(
        (result.request.messages[0] as SystemLlmMessage).content,
        'You are a helpful assistant.',
      );
      expect(
        (result.request.messages[2] as ToolResultLlmMessage).content,
        'secret@email.com',
      );
    });
  });

  group('PrivacyFilter — de-anonymization', () {
    const filter = PrivacyFilter(localLlm: null);

    test('deAnonymizeResponse restores text response', () {
      final map = AnonymizationMap(
        replacements: {'[PERSON_1]': 'Alice'},
        originalPrompt: '',
        anonymizedPrompt: '',
      );

      final response = LlmResponse.text(
        'I scheduled a meeting with [PERSON_1].',
      );

      final restored = filter.deAnonymizeResponse(response, map);
      expect(
        (restored as TextLlmResponse).content,
        'I scheduled a meeting with Alice.',
      );
    });

    test('deAnonymizeResponse restores tool call arguments', () {
      final map = AnonymizationMap(
        replacements: {'[PERSON_1]': 'Bob'},
        originalPrompt: '',
        anonymizedPrompt: '',
      );

      final response = LlmResponse.toolCalls(null, [
        LlmToolCall(
          id: 'tc_1',
          name: 'create_contact',
          arguments: {'name': '[PERSON_1]'},
        ),
      ]);

      final restored = filter.deAnonymizeResponse(response, map);
      final calls = (restored as ToolCallsLlmResponse).calls;
      expect(calls.first.arguments['name'], 'Bob');
    });

    test('deAnonymizeResponse passes through error responses', () {
      final map = AnonymizationMap(
        replacements: {'[PERSON_1]': 'Alice'},
        originalPrompt: '',
        anonymizedPrompt: '',
      );

      const response = LlmResponse.error('Something went wrong');
      final restored = filter.deAnonymizeResponse(response, map);
      expect(restored, same(response));
    });

    test('deAnonymizeEvent restores text delta', () {
      final map = AnonymizationMap(
        replacements: {'[PERSON_1]': 'Charlie'},
        originalPrompt: '',
        anonymizedPrompt: '',
      );

      const event = LlmStreamEvent.textDelta('Hello [PERSON_1]!');
      final restored = filter.deAnonymizeEvent(event, map);
      expect((restored as TextDeltaEvent).text, 'Hello Charlie!');
    });
  });
}
