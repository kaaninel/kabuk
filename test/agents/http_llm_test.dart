import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kabuk/agents/http_llm.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:mocktail/mocktail.dart';

/// Mock HTTP client for testing [HttpLlmService].
class MockHttpClient extends Mock implements http.Client {}

void main() {
  // ---------------------------------------------------------------------------
  // LlmConfig serialization
  // ---------------------------------------------------------------------------

  group('LlmConfig', () {
    group('toJson()', () {
      test('produces expected map', () {
        const config = LlmConfig(
          provider: LlmProvider.openai,
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'sk-test',
          defaultModel: 'gpt-4o',
          defaultTemperature: 0.5,
          defaultMaxTokens: 2048,
          timeoutSeconds: 30,
        );

        final json = config.toJson();

        expect(json, {
          'provider': 'openai',
          'baseUrl': 'https://api.openai.com/v1',
          'apiKey': 'sk-test',
          'defaultModel': 'gpt-4o',
          'defaultTemperature': 0.5,
          'defaultMaxTokens': 2048,
          'timeoutSeconds': 30,
        });
      });
    });

    group('fromJson()', () {
      test('roundtrips correctly', () {
        const original = LlmConfig(
          provider: LlmProvider.anthropic,
          baseUrl: 'https://api.anthropic.com/v1',
          apiKey: 'sk-ant-test',
          defaultModel: 'claude-sonnet-4-20250514',
          defaultTemperature: 0.9,
          defaultMaxTokens: 8192,
          timeoutSeconds: 120,
        );

        final restored = LlmConfig.fromJson(original.toJson());

        expect(restored.provider, original.provider);
        expect(restored.baseUrl, original.baseUrl);
        expect(restored.apiKey, original.apiKey);
        expect(restored.defaultModel, original.defaultModel);
        expect(restored.defaultTemperature, original.defaultTemperature);
        expect(restored.defaultMaxTokens, original.defaultMaxTokens);
        expect(restored.timeoutSeconds, original.timeoutSeconds);
      });

      test('handles missing optional fields with defaults', () {
        final config = LlmConfig.fromJson({
          'provider': 'openai',
          'baseUrl': 'https://api.openai.com/v1',
          'apiKey': 'sk-test',
          // defaultModel, defaultTemperature, defaultMaxTokens, timeoutSeconds
          // are all omitted.
        });

        expect(config.defaultModel, isNull);
        expect(config.defaultTemperature, 0.7);
        expect(config.defaultMaxTokens, 4096);
        expect(config.timeoutSeconds, 60);
      });

      test('preserves all provider values', () {
        for (final provider in LlmProvider.values) {
          final json = {
            'provider': provider.name,
            'baseUrl': 'http://localhost',
            'apiKey': '',
          };
          final config = LlmConfig.fromJson(json);
          expect(config.provider, provider);
        }
      });
    });

    group('convenience constructors', () {
      test('openai() sets correct provider and baseUrl', () {
        const config = LlmConfig.openai(apiKey: 'sk-test');
        expect(config.provider, LlmProvider.openai);
        expect(config.baseUrl, 'https://api.openai.com/v1');
        expect(config.apiKey, 'sk-test');
        expect(config.defaultModel, 'gpt-4o');
      });

      test('anthropic() sets correct provider and baseUrl', () {
        const config = LlmConfig.anthropic(apiKey: 'sk-ant-test');
        expect(config.provider, LlmProvider.anthropic);
        expect(config.baseUrl, 'https://api.anthropic.com/v1');
        expect(config.apiKey, 'sk-ant-test');
        expect(config.defaultModel, 'claude-sonnet-4-20250514');
      });

      test('ollama() sets correct provider with local defaults', () {
        const config = LlmConfig.ollama();
        expect(config.provider, LlmProvider.ollama);
        expect(config.baseUrl, 'http://localhost:11434');
        expect(config.apiKey, isEmpty);
        expect(config.defaultModel, 'llama3.1');
      });
    });
  });

  // ---------------------------------------------------------------------------
  // HttpLlmService retry logic
  // ---------------------------------------------------------------------------

  group('HttpLlmService retry', () {
    late MockHttpClient mockClient;
    late HttpLlmService service;

    /// A minimal valid OpenAI completion response body.
    String successBody({String content = 'Hello!'}) => jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content},
        },
      ],
    });

    /// A simple [LlmRequest] for testing.
    const testRequest = LlmRequest(messages: [LlmMessage.user('Hi')]);

    setUp(() {
      mockClient = MockHttpClient();
      service = HttpLlmService(
        config: const LlmConfig.openai(apiKey: 'sk-test'),
        client: mockClient,
      );
    });

    setUpAll(() {
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    test('succeeds on first try returns response', () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response(successBody(), 200));

      final result = await service.complete(testRequest);

      expect(result, isA<TextLlmResponse>());
      expect((result as TextLlmResponse).content, 'Hello!');
      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(1);
    });

    test('retries on 429 and eventually succeeds', () async {
      var callCount = 0;
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async {
        callCount++;
        if (callCount <= 2) {
          return http.Response('Rate limited', 429);
        }
        return http.Response(successBody(), 200);
      });

      final result = await service.complete(testRequest);

      expect(result, isA<TextLlmResponse>());
      // 2 retries + final success = 3 calls
      expect(callCount, 3);
    });

    test('retries on 500 and eventually succeeds', () async {
      var callCount = 0;
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          return http.Response('Server Error', 500);
        }
        return http.Response(successBody(), 200);
      });

      final result = await service.complete(testRequest);

      expect(result, isA<TextLlmResponse>());
      expect(callCount, 2);
    });

    test('returns error after max retries exhausted', () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('Rate limited', 429));

      final result = await service.complete(testRequest);

      // After 3 retries the 429 response is returned, which is not 200,
      // so HttpLlmService returns an error LlmResponse.
      expect(result, isA<ErrorLlmResponse>());
      expect((result as ErrorLlmResponse).message, contains('Rate limit'));
      // 1 initial + 3 retries = 4 calls
      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(4);
    });

    test('respects Retry-After header', () async {
      var callCount = 0;
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          return http.Response(
            'Rate limited',
            429,
            headers: {'retry-after': '1'},
          );
        }
        return http.Response(successBody(), 200);
      });

      final result = await service.complete(testRequest);

      expect(result, isA<TextLlmResponse>());
      expect(callCount, 2);
    });

    test('does not retry on 400 (non-retryable)', () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('Bad Request', 400));

      final result = await service.complete(testRequest);

      expect(result, isA<ErrorLlmResponse>());
      expect((result as ErrorLlmResponse).message, contains('Bad request'));
      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(1);
    });

    test('does not retry on 401 (non-retryable)', () async {
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('Unauthorized', 401));

      final result = await service.complete(testRequest);

      expect(result, isA<ErrorLlmResponse>());
      expect((result as ErrorLlmResponse).message, contains('Invalid API key'));
      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(1);
    });
  });
}
