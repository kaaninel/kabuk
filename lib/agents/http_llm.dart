/// HTTP-based LLM service implementation.
///
/// Supports OpenAI-compatible APIs (OpenAI, Anthropic via proxy,
/// Ollama, llama.cpp server). Handles retries, rate limiting, and
/// streaming.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kabuk/agents/llm.dart';

/// Configuration for an HTTP-based LLM provider.
class LlmConfig {
  /// Creates an [LlmConfig].
  const LlmConfig({
    required this.provider,
    required this.baseUrl,
    required this.apiKey,
    this.defaultModel,
    this.defaultTemperature = 0.7,
    this.defaultMaxTokens = 4096,
    this.timeoutSeconds = 60,
  });

  /// Creates a config for OpenAI.
  const LlmConfig.openai({required String apiKey, String model = 'gpt-4o'})
    : this(
        provider: LlmProvider.openai,
        baseUrl: 'https://api.openai.com/v1',
        apiKey: apiKey,
        defaultModel: model,
      );

  /// Creates a config for Anthropic.
  const LlmConfig.anthropic({
    required String apiKey,
    String model = 'claude-sonnet-4-20250514',
  }) : this(
         provider: LlmProvider.anthropic,
         baseUrl: 'https://api.anthropic.com/v1',
         apiKey: apiKey,
         defaultModel: model,
       );

  /// Creates a config for a local Ollama server.
  const LlmConfig.ollama({
    String baseUrl = 'http://localhost:11434',
    String model = 'llama3.1',
  }) : this(
         provider: LlmProvider.ollama,
         baseUrl: baseUrl,
         apiKey: '',
         defaultModel: model,
       );

  /// Creates a config for an OpenAI-compatible endpoint.
  ///
  /// Works with OpenRouter, LM Studio, vLLM, llama.cpp server, Groq,
  /// Together, and any server exposing the OpenAI Chat Completions API.
  /// The provider is set to [LlmProvider.openai] so the OpenAI wire
  /// format + Bearer auth are used, but requests go to [baseUrl].
  const LlmConfig.openAICompatible({
    required String baseUrl,
    String apiKey = '',
    String? model,
  }) : this(
         provider: LlmProvider.openai,
         baseUrl: baseUrl,
         apiKey: apiKey,
         defaultModel: model,
       );

  /// The LLM provider type.
  final LlmProvider provider;

  /// Base URL for the API.
  final String baseUrl;

  /// API key for authentication.
  final String apiKey;

  /// Default model to use if not specified per-request.
  final String? defaultModel;

  /// Default sampling temperature.
  final double defaultTemperature;

  /// Default max tokens to generate.
  final int defaultMaxTokens;

  /// Request timeout in seconds.
  final int timeoutSeconds;

  /// Serializes this [LlmConfig] to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'provider': provider.name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'defaultModel': defaultModel,
    'defaultTemperature': defaultTemperature,
    'defaultMaxTokens': defaultMaxTokens,
    'timeoutSeconds': timeoutSeconds,
  };

  /// Deserializes an [LlmConfig] from a JSON map.
  factory LlmConfig.fromJson(Map<String, dynamic> json) => LlmConfig(
    provider: LlmProvider.values.byName(json['provider'] as String),
    baseUrl: json['baseUrl'] as String,
    apiKey: json['apiKey'] as String,
    defaultModel: json['defaultModel'] as String?,
    defaultTemperature: (json['defaultTemperature'] as num?)?.toDouble() ?? 0.7,
    defaultMaxTokens: (json['defaultMaxTokens'] as num?)?.toInt() ?? 4096,
    timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 60,
  );
}

/// HTTP-based implementation of [LlmService].
///
/// Sends requests to OpenAI-compatible endpoints. Supports both
/// blocking completion and streaming responses.
class HttpLlmService implements LlmService {
  /// Creates an [HttpLlmService] with the given [config].
  HttpLlmService({required this.config, http.Client? client})
    : _client = client ?? http.Client();

  /// The provider configuration.
  final LlmConfig config;
  final http.Client _client;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    try {
      final body = _buildRequestBody(request, stream: false);
      final response = await _sendRequestWithRetry(body);

      if (response.statusCode != 200) {
        return LlmResponse.error(
          _humanReadableError(response.statusCode, response.body),
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseResponse(json);
    } on TimeoutException {
      return const LlmResponse.error(
        'The AI took too long to respond. Try again with a shorter message.',
      );
    } on FormatException catch (e) {
      return LlmResponse.error(
        'Received an invalid response from the AI provider: ${e.message}',
      );
    } on Exception catch (e) {
      return LlmResponse.error('LLM request failed: $e');
    }
  }

  @override
  Stream<LlmStreamEvent> stream(LlmRequest request) async* {
    try {
      final body = _buildRequestBody(request, stream: true);
      final uri = _getEndpointUri();
      final httpRequest = http.Request('POST', uri)
        ..headers.addAll(_buildHeaders())
        ..body = jsonEncode(body);

      final streamedResponse = await _client
          .send(httpRequest)
          .timeout(Duration(seconds: config.timeoutSeconds));

      // Accumulators for tool call deltas (OpenAI sends them incrementally).
      final toolCallBuffers = <int, _ToolCallBuffer>{};
      // Clear Anthropic tool buffers for this new stream.
      _anthropicToolBuffers.clear();
      LlmUsage? streamUsage;

      await for (final chunk
          in streamedResponse.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (!chunk.startsWith('data: ')) continue;
        final data = chunk.substring(6).trim();
        if (data == '[DONE]') break;

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          // Capture usage from the final data chunk (OpenAI stream_options).
          final rawUsage = json['usage'] as Map<String, dynamic>?;
          if (rawUsage != null) {
            streamUsage = _parseOpenAiUsage(json);
          }
          yield* _extractStreamEvents(json, toolCallBuffers);
        } on FormatException {
          // Skip malformed chunks.
        }
      }

      // Emit any buffered tool calls that are now complete.
      for (final buffer in toolCallBuffers.values) {
        if (buffer.name != null) {
          yield LlmStreamEvent.toolCall(
            LlmToolCall(
              id: buffer.id ?? '',
              name: buffer.name!,
              arguments: _tryParseJson(buffer.arguments.toString()),
            ),
          );
        }
      }

      // Emit usage before done, if available.
      if (streamUsage != null) {
        yield LlmStreamEvent.usage(streamUsage);
      }

      yield const LlmStreamEvent.done();
    } on Exception catch (e) {
      throw LlmStreamException('Streaming failed: $e');
    }
  }

  @override
  int countTokens(String text) {
    // Rough approximation: ~4 chars per token for English text.
    return (text.length / 4).ceil();
  }

  // ---------------------------------------------------------------------------
  // Request building
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _buildRequestBody(
    LlmRequest request, {
    required bool stream,
  }) {
    final messages = <Map<String, dynamic>>[];

    // Add system prompt.
    if (request.systemPrompt != null) {
      if (config.provider == LlmProvider.anthropic) {
        // Anthropic uses a top-level `system` field.
      } else {
        messages.add({'role': 'system', 'content': request.systemPrompt});
      }
    }

    // Add conversation messages.
    for (final msg in request.messages) {
      messages.add(msg.toJson());
    }

    final body = <String, dynamic>{
      'model': request.model ?? config.defaultModel ?? 'gpt-4o',
      'messages': messages,
      'temperature': request.temperature ?? config.defaultTemperature,
      'max_tokens': request.maxTokens ?? config.defaultMaxTokens,
      'stream': stream,
    };

    // Request usage reporting in the final streaming chunk (OpenAI only —
    // some third-party compatible servers reject the extra field).
    if (stream &&
        config.provider == LlmProvider.openai &&
        config.baseUrl.contains('api.openai.com')) {
      body['stream_options'] = {'include_usage': true};
    }

    // Add system prompt for Anthropic.
    if (config.provider == LlmProvider.anthropic &&
        request.systemPrompt != null) {
      body['system'] = request.systemPrompt;
    }

    // Add tools if present.
    if (request.tools != null && request.tools!.isNotEmpty) {
      if (config.provider == LlmProvider.anthropic) {
        body['tools'] = request.tools!.map((t) {
          final fn = t['function'] as Map<String, dynamic>? ?? {};
          return {
            'name': fn['name'],
            'description': fn['description'],
            'input_schema': fn['parameters'],
          };
        }).toList();
      } else {
        body['tools'] = request.tools;
      }
    }

    return body;
  }

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};

    switch (config.provider) {
      case LlmProvider.openai:
        headers['Authorization'] = 'Bearer ${config.apiKey}';
      case LlmProvider.anthropic:
        headers['x-api-key'] = config.apiKey;
        headers['anthropic-version'] = '2023-06-01';
      case LlmProvider.ollama:
        break; // No auth needed.
      case LlmProvider.local:
        break; // Local models don't need auth.
    }

    return headers;
  }

  Uri _getEndpointUri() {
    return switch (config.provider) {
      LlmProvider.openai => Uri.parse('${config.baseUrl}/chat/completions'),
      LlmProvider.anthropic => Uri.parse('${config.baseUrl}/messages'),
      LlmProvider.ollama => Uri.parse('${config.baseUrl}/api/chat'),
      LlmProvider.local => Uri.parse('${config.baseUrl}/v1/chat/completions'),
    };
  }

  Future<http.Response> _sendRequest(Map<String, dynamic> body) {
    return _client
        .post(
          _getEndpointUri(),
          headers: _buildHeaders(),
          body: jsonEncode(body),
        )
        .timeout(Duration(seconds: config.timeoutSeconds));
  }

  /// Sends a request with retry and exponential backoff for transient errors.
  ///
  /// Retries up to [maxRetries] times with exponential backoff starting
  /// at [initialDelay]. Retries on: 429, 500, 502, 503, 504 status codes
  /// and on timeout/network exceptions.
  Future<http.Response> _sendRequestWithRetry(
    Map<String, dynamic> body, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    const retryableCodes = {429, 500, 502, 503, 504};
    var delay = initialDelay;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await _sendRequest(body);
        if (retryableCodes.contains(response.statusCode) &&
            attempt < maxRetries) {
          // Check for Retry-After header (common with 429).
          final retryAfter = response.headers['retry-after'];
          if (retryAfter != null) {
            final seconds = int.tryParse(retryAfter);
            if (seconds != null) {
              delay = Duration(seconds: seconds);
            }
          }
          await Future<void>.delayed(delay);
          delay *= 2; // Exponential backoff.
          continue;
        }
        return response;
      } on TimeoutException {
        if (attempt >= maxRetries) rethrow;
        await Future<void>.delayed(delay);
        delay *= 2;
      } on Exception {
        if (attempt >= maxRetries) rethrow;
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
    // Should never reach here, but satisfies the compiler.
    return _sendRequest(body);
  }

  // ---------------------------------------------------------------------------
  // Response parsing
  // ---------------------------------------------------------------------------

  LlmResponse _parseResponse(Map<String, dynamic> json) {
    if (config.provider == LlmProvider.anthropic) {
      return _parseAnthropicResponse(json);
    }
    return _parseOpenAiResponse(json);
  }

  LlmResponse _parseOpenAiResponse(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      return const LlmResponse.error('No choices in response');
    }

    final choice = choices.first as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>? ?? {};
    final content = message['content'] as String? ?? '';
    final toolCalls = message['tool_calls'] as List<dynamic>?;

    // Parse usage (OpenAI always returns this for non-streaming).
    final usage = _parseOpenAiUsage(json);

    if (toolCalls != null && toolCalls.isNotEmpty) {
      final calls = toolCalls.map((tc) {
        final tcMap = tc as Map<String, dynamic>;
        final fn = tcMap['function'] as Map<String, dynamic>;
        final argsStr = fn['arguments'] as String? ?? '{}';
        return LlmToolCall(
          id: tcMap['id'] as String? ?? '',
          name: fn['name'] as String? ?? '',
          arguments: jsonDecode(argsStr) as Map<String, dynamic>,
        );
      }).toList();
      return LlmResponse.toolCalls(
        content.isEmpty ? null : content,
        calls,
        usage: usage,
      );
    }

    return LlmResponse.text(content, usage: usage);
  }

  LlmResponse _parseAnthropicResponse(Map<String, dynamic> json) {
    final contentBlocks = json['content'] as List<dynamic>? ?? [];
    final textParts = <String>[];
    final toolCalls = <LlmToolCall>[];

    for (final block in contentBlocks) {
      final blockMap = block as Map<String, dynamic>;
      final type = blockMap['type'] as String?;
      if (type == 'text') {
        textParts.add(blockMap['text'] as String? ?? '');
      } else if (type == 'tool_use') {
        toolCalls.add(
          LlmToolCall(
            id: blockMap['id'] as String? ?? '',
            name: blockMap['name'] as String? ?? '',
            arguments: blockMap['input'] as Map<String, dynamic>? ?? {},
          ),
        );
      }
    }

    final text = textParts.join();
    final usage = _parseAnthropicUsage(json);

    if (toolCalls.isNotEmpty) {
      return LlmResponse.toolCalls(
        text.isEmpty ? null : text,
        toolCalls,
        usage: usage,
      );
    }

    return LlmResponse.text(text, usage: usage);
  }

  /// Extract stream events from a parsed JSON chunk.
  ///
  /// Handles both text deltas and tool call deltas for OpenAI and
  /// Anthropic streaming formats. Tool call arguments are accumulated
  /// in [toolCallBuffers] until complete.
  Stream<LlmStreamEvent> _extractStreamEvents(
    Map<String, dynamic> json,
    Map<int, _ToolCallBuffer> toolCallBuffers,
  ) async* {
    if (config.provider == LlmProvider.anthropic) {
      yield* _extractAnthropicStreamEvents(json);
    } else {
      yield* _extractOpenAiStreamEvents(json, toolCallBuffers);
    }
  }

  /// Accumulator for Anthropic tool call deltas streamed across chunks.
  ///
  /// Anthropic sends tool_use blocks via content_block_start (id + name),
  /// then input_json_delta events for arguments, then content_block_stop.
  final _anthropicToolBuffers = <int, _ToolCallBuffer>{};

  /// Parse Anthropic streaming events.
  ///
  /// Anthropic sends tool_use blocks via content_block_start (id + name),
  /// then input_json_delta chunks for arguments, then content_block_stop
  /// to signal the block is complete. We accumulate arguments and emit
  /// a [ToolCallEvent] at content_block_stop.
  Stream<LlmStreamEvent> _extractAnthropicStreamEvents(
    Map<String, dynamic> json,
  ) async* {
    final type = json['type'] as String?;

    if (type == 'content_block_start') {
      final index = json['index'] as int? ?? 0;
      final block = json['content_block'] as Map<String, dynamic>?;
      if (block != null && block['type'] == 'tool_use') {
        // Start accumulating a new tool call.
        _anthropicToolBuffers[index] = _ToolCallBuffer()
          ..id = block['id'] as String?
          ..name = block['name'] as String?;
      }
    } else if (type == 'content_block_delta') {
      final index = json['index'] as int? ?? 0;
      final delta = json['delta'] as Map<String, dynamic>?;
      if (delta == null) return;

      final deltaType = delta['type'] as String?;
      if (deltaType == 'text_delta') {
        final text = delta['text'] as String?;
        if (text != null && text.isNotEmpty) {
          yield LlmStreamEvent.textDelta(text);
        }
      } else if (deltaType == 'input_json_delta') {
        // Accumulate JSON argument fragments for the tool call.
        final partialJson = delta['partial_json'] as String?;
        if (partialJson != null) {
          _anthropicToolBuffers[index]?.arguments.write(partialJson);
        }
      }
    } else if (type == 'content_block_stop') {
      final index = json['index'] as int? ?? 0;
      final buffer = _anthropicToolBuffers.remove(index);
      if (buffer != null && buffer.name != null) {
        yield LlmStreamEvent.toolCall(
          LlmToolCall(
            id: buffer.id ?? '',
            name: buffer.name!,
            arguments: _tryParseJson(buffer.arguments.toString()),
          ),
        );
      }
    } else if (type == 'message_delta') {
      // Anthropic sends usage in message_delta at end of stream.
      final usage = json['usage'] as Map<String, dynamic>?;
      if (usage != null) {
        final outputTokens = (usage['output_tokens'] as num?)?.toInt() ?? 0;
        yield LlmStreamEvent.usage(
          LlmUsage(
            promptTokens: 0, // Not available in message_delta.
            completionTokens: outputTokens,
            totalTokens: outputTokens,
            model: config.defaultModel ?? 'unknown',
            provider: config.provider,
          ),
        );
      }
    }
  }

  /// Parse OpenAI/Ollama streaming events.
  ///
  /// OpenAI sends tool call deltas incrementally across multiple chunks:
  /// first chunk has index/id/name, subsequent chunks append to arguments.
  Stream<LlmStreamEvent> _extractOpenAiStreamEvents(
    Map<String, dynamic> json,
    Map<int, _ToolCallBuffer> toolCallBuffers,
  ) async* {
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return;

    final delta =
        (choices.first as Map<String, dynamic>)['delta']
            as Map<String, dynamic>?;
    if (delta == null) return;

    // Text content delta.
    final content = delta['content'] as String?;
    if (content != null && content.isNotEmpty) {
      yield LlmStreamEvent.textDelta(content);
    }

    // Tool call deltas.
    final toolCalls = delta['tool_calls'] as List<dynamic>?;
    if (toolCalls != null) {
      for (final tc in toolCalls) {
        final tcMap = tc as Map<String, dynamic>;
        final index = tcMap['index'] as int? ?? 0;
        final fn = tcMap['function'] as Map<String, dynamic>?;

        final buffer = toolCallBuffers.putIfAbsent(
          index,
          _ToolCallBuffer.new,
        );

        // First chunk for this tool call provides id and name.
        final id = tcMap['id'] as String?;
        if (id != null) buffer.id = id;
        if (fn != null) {
          final name = fn['name'] as String?;
          if (name != null) buffer.name = name;
          final args = fn['arguments'] as String?;
          if (args != null) buffer.arguments.write(args);
        }
      }
    }
  }

  /// Try to parse a JSON string, returning an empty map on failure.
  Map<String, dynamic> _tryParseJson(String input) {
    try {
      return jsonDecode(input) as Map<String, dynamic>;
    } on FormatException {
      return {};
    }
  }

  /// Convert an HTTP status code and body into a user-friendly error message.
  ///
  /// Attempts to extract the provider's error message from the JSON response
  /// body, falling back to generic descriptions based on the status code.
  String _humanReadableError(int statusCode, String body) {
    // Try to extract a structured error message from the response.
    String? providerMessage;
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      // OpenAI: {"error": {"message": "..."}}
      final error = json['error'];
      if (error is Map<String, dynamic>) {
        providerMessage = error['message'] as String?;
      }
      // Anthropic: {"error": {"message": "..."}} or {"message": "..."}
      providerMessage ??= json['message'] as String?;
    } on FormatException {
      // Body is not JSON.
    }

    final detail = providerMessage ?? '';

    return switch (statusCode) {
      400 =>
        'Bad request to the AI provider. ${detail.isNotEmpty ? detail : 'Check your message and try again.'}',
      401 => 'Invalid API key. Please update your API key in Settings.',
      403 =>
        'Access denied by the AI provider. ${detail.isNotEmpty ? detail : 'Your API key may lack the required permissions.'}',
      404 =>
        'The selected AI model was not found. ${detail.isNotEmpty ? detail : 'Check your model setting.'}',
      429 =>
        'Rate limit exceeded. ${detail.isNotEmpty ? detail : 'Please wait a moment and try again.'}',
      500 =>
        'The AI provider experienced an internal error. Try again shortly.',
      502 || 503 =>
        'The AI provider is temporarily unavailable. Try again in a few seconds.',
      504 =>
        'Request to the AI provider timed out. Try again with a shorter message.',
      _ =>
        'AI provider error ($statusCode). ${detail.isNotEmpty
            ? detail
            : body.length > 200
            ? '${body.substring(0, 200)}...'
            : body}',
    };
  }

  // ---------------------------------------------------------------------------
  // Usage parsing
  // ---------------------------------------------------------------------------

  /// Parse token usage from an OpenAI (or Ollama) response JSON.
  ///
  /// OpenAI response structure:
  /// ```json
  /// { "usage": { "prompt_tokens": 10, "completion_tokens": 20, "total_tokens": 30 },
  ///   "model": "gpt-4o" }
  /// ```
  LlmUsage? _parseOpenAiUsage(Map<String, dynamic> json) {
    final raw = json['usage'] as Map<String, dynamic>?;
    if (raw == null) return null;
    final model = json['model'] as String? ?? config.defaultModel ?? 'unknown';
    return LlmUsage(
      promptTokens: (raw['prompt_tokens'] as num?)?.toInt() ?? 0,
      completionTokens: (raw['completion_tokens'] as num?)?.toInt() ?? 0,
      totalTokens: (raw['total_tokens'] as num?)?.toInt() ?? 0,
      model: model,
      provider: config.provider,
    );
  }

  /// Parse token usage from an Anthropic response JSON.
  ///
  /// Anthropic response structure:
  /// ```json
  /// { "usage": { "input_tokens": 10, "output_tokens": 20 },
  ///   "model": "claude-3-5-sonnet-20241022" }
  /// ```
  LlmUsage? _parseAnthropicUsage(Map<String, dynamic> json) {
    final raw = json['usage'] as Map<String, dynamic>?;
    if (raw == null) return null;
    final prompt = (raw['input_tokens'] as num?)?.toInt() ?? 0;
    final completion = (raw['output_tokens'] as num?)?.toInt() ?? 0;
    final model = json['model'] as String? ?? config.defaultModel ?? 'unknown';
    return LlmUsage(
      promptTokens: prompt,
      completionTokens: completion,
      totalTokens: prompt + completion,
      model: model,
      provider: config.provider,
    );
  }

  /// Dispose the HTTP client.
  void dispose() => _client.close();
}

/// Accumulator for OpenAI tool call deltas streamed across chunks.
class _ToolCallBuffer {
  /// The tool call ID.
  String? id;

  /// The tool function name.
  String? name;

  /// Accumulated JSON argument fragments.
  final arguments = StringBuffer();
}
