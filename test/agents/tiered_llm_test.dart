/// Tests for the tiered LLM service — tier selection, fallthrough,
/// and privacy filtering integration.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/privacy_filter.dart';
import 'package:kabuk/agents/tiered_llm.dart';

/// A simple in-memory LLM service for testing.
///
/// Records calls and returns a configurable response.
class FakeLlmService implements LlmService {
  FakeLlmService({required this.name, this.response});

  final String name;
  LlmResponse? response;
  final List<LlmRequest> calls = [];

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    calls.add(request);
    return response ?? LlmResponse.text('Response from $name');
  }

  @override
  Stream<LlmStreamEvent> stream(LlmRequest request) async* {
    calls.add(request);
    yield LlmStreamEvent.textDelta('Streaming from $name');
    yield const LlmStreamEvent.done();
  }

  @override
  int countTokens(String text) => text.split(' ').length;
}

void main() {
  group('TieredLlmService', () {
    late FakeLlmService baseLlm;
    late FakeLlmService standardLlm;
    late FakeLlmService advancedLlm;

    setUp(() {
      baseLlm = FakeLlmService(name: 'base');
      standardLlm = FakeLlmService(name: 'standard');
      advancedLlm = FakeLlmService(name: 'advanced');
    });

    test('routes to base tier by default', () async {
      final service = TieredLlmService(
        config: TieredLlmConfig(
          baseLlm: baseLlm,
          standardLlm: standardLlm,
          advancedLlm: advancedLlm,
          enablePrivacyFilter: false,
        ),
      );

      await service.complete(
        const LlmRequest(messages: [LlmMessage.user('Hello')]),
      );

      expect(baseLlm.calls, hasLength(1));
      expect(standardLlm.calls, isEmpty);
      expect(advancedLlm.calls, isEmpty);
    });

    test('routes to standard tier when requested', () async {
      final service = TieredLlmService(
        config: TieredLlmConfig(
          baseLlm: baseLlm,
          standardLlm: standardLlm,
          advancedLlm: advancedLlm,
          enablePrivacyFilter: false,
        ),
      );

      await service.complete(
        const LlmRequest(
          messages: [LlmMessage.user('Hello')],
          model: 'tier:standard',
        ),
      );

      expect(baseLlm.calls, isEmpty);
      expect(standardLlm.calls, hasLength(1));
      expect(advancedLlm.calls, isEmpty);
    });

    test('routes to advanced tier when requested', () async {
      final service = TieredLlmService(
        config: TieredLlmConfig(
          baseLlm: baseLlm,
          standardLlm: standardLlm,
          advancedLlm: advancedLlm,
          enablePrivacyFilter: false,
        ),
      );

      await service.complete(
        const LlmRequest(
          messages: [LlmMessage.user('Hello')],
          model: 'tier:advanced',
        ),
      );

      expect(baseLlm.calls, isEmpty);
      expect(standardLlm.calls, isEmpty);
      expect(advancedLlm.calls, hasLength(1));
    });

    test('falls through to base when standard is not configured', () async {
      final service = TieredLlmService(
        config: TieredLlmConfig(baseLlm: baseLlm, enablePrivacyFilter: false),
      );

      await service.complete(
        const LlmRequest(
          messages: [LlmMessage.user('Hello')],
          model: 'tier:standard',
        ),
      );

      expect(baseLlm.calls, hasLength(1));
    });

    test('falls through advanced → standard → base', () async {
      final service = TieredLlmService(
        config: TieredLlmConfig(baseLlm: baseLlm, enablePrivacyFilter: false),
      );

      await service.complete(
        const LlmRequest(
          messages: [LlmMessage.user('Hello')],
          model: 'tier:advanced',
        ),
      );

      expect(baseLlm.calls, hasLength(1));
    });

    test(
      'falls through advanced → standard when only standard exists',
      () async {
        final service = TieredLlmService(
          config: TieredLlmConfig(
            baseLlm: baseLlm,
            standardLlm: standardLlm,
            enablePrivacyFilter: false,
          ),
        );

        await service.complete(
          const LlmRequest(
            messages: [LlmMessage.user('Hello')],
            model: 'tier:advanced',
          ),
        );

        expect(standardLlm.calls, hasLength(1));
        expect(baseLlm.calls, isEmpty);
      },
    );

    test(
      'strips tier: prefix from model field in downstream request',
      () async {
        final service = TieredLlmService(
          config: TieredLlmConfig(baseLlm: baseLlm, enablePrivacyFilter: false),
        );

        await service.complete(
          const LlmRequest(
            messages: [LlmMessage.user('Hello')],
            model: 'tier:base',
          ),
        );

        expect(baseLlm.calls.first.model, isNull);
      },
    );

    test('preserves non-tier model strings', () async {
      final service = TieredLlmService(
        config: TieredLlmConfig(baseLlm: baseLlm, enablePrivacyFilter: false),
      );

      await service.complete(
        const LlmRequest(messages: [LlmMessage.user('Hello')], model: 'gpt-4o'),
      );

      // Non-tier model string routes to base but model is preserved.
      expect(baseLlm.calls.first.model, 'gpt-4o');
    });

    test('isTierAvailable reports correctly', () {
      final service = TieredLlmService(
        config: TieredLlmConfig(baseLlm: baseLlm, standardLlm: standardLlm),
      );

      expect(service.isTierAvailable(LlmTier.base), isTrue);
      expect(service.isTierAvailable(LlmTier.standard), isTrue);
      expect(service.isTierAvailable(LlmTier.advanced), isFalse);
    });

    test('countTokens delegates to base', () {
      final service = TieredLlmService(
        config: TieredLlmConfig(baseLlm: baseLlm),
      );

      expect(
        service.countTokens('hello world'),
        baseLlm.countTokens('hello world'),
      );
    });

    test('streaming routes to the correct tier', () async {
      final service = TieredLlmService(
        config: TieredLlmConfig(
          baseLlm: baseLlm,
          advancedLlm: advancedLlm,
          enablePrivacyFilter: false,
        ),
      );

      final events = await service
          .stream(
            const LlmRequest(
              messages: [LlmMessage.user('Hello')],
              model: 'tier:advanced',
            ),
          )
          .toList();

      expect(advancedLlm.calls, hasLength(1));
      expect(events.first, isA<TextDeltaEvent>());
    });
  });

  group('LlmRequestTierExtension', () {
    test('withTier sets model to tier: prefix', () {
      const request = LlmRequest(
        messages: [LlmMessage.user('Test')],
        temperature: 0.5,
      );

      final tiered = request.withTier(LlmTier.advanced);
      expect(tiered.model, 'tier:advanced');
      expect(tiered.temperature, 0.5);
      expect(tiered.messages, hasLength(1));
    });
  });

  group('TieredLlmService — privacy filtering', () {
    test('applies regex-based anonymization for remote requests', () async {
      final baseLlm = FakeLlmService(name: 'base');
      final advancedLlm = FakeLlmService(name: 'advanced');

      final service = TieredLlmService(
        config: TieredLlmConfig(
          baseLlm: baseLlm,
          advancedLlm: advancedLlm,
          enablePrivacyFilter: true,
          defaultPrivacyLevel: PrivacyLevel.standard,
        ),
      );

      // The advanced LLM returns a response with a placeholder.
      advancedLlm.response = const LlmResponse.text(
        'I emailed [EMAIL_1] for you.',
      );

      final response = await service.complete(
        const LlmRequest(
          messages: [LlmMessage.user('Email alice@example.com')],
          model: 'tier:advanced',
        ),
      );

      // The advanced LLM should have received an anonymized request.
      final sentRequest = advancedLlm.calls.first;
      final sentMsg = sentRequest.messages.first as UserLlmMessage;
      expect(sentMsg.content, isNot(contains('alice@example.com')));

      // The response should be de-anonymized.
      expect(
        (response as TextLlmResponse).content,
        contains('alice@example.com'),
      );
    });

    test('does not filter base tier requests', () async {
      final baseLlm = FakeLlmService(name: 'base');

      final service = TieredLlmService(
        config: TieredLlmConfig(baseLlm: baseLlm, enablePrivacyFilter: true),
      );

      await service.complete(
        const LlmRequest(
          messages: [LlmMessage.user('Email alice@example.com')],
        ),
      );

      // Base tier is local — no anonymization.
      final sentMsg = baseLlm.calls.first.messages.first as UserLlmMessage;
      expect(sentMsg.content, contains('alice@example.com'));
    });
  });
}
