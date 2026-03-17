/// Local on-device LLM service using llamadart.
///
/// Runs GGUF models directly on the device via [llamadart]'s
/// [LlamaEngine], using Dart Native Assets for zero-config native
/// library linking on iOS, macOS, Android, Linux, and Windows.
/// Supports streaming, configurable sampling parameters, and automatic
/// chat template detection from GGUF metadata.
///
/// This implementation honors the [LlmService] interface so it plugs
/// seamlessly into the agent layer without any upstream changes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kabuk/agents/llm.dart';
import 'package:llamadart/llamadart.dart';

/// Configuration specific to a local GGUF model.
///
/// Extends the base [LlmConfig] concept with fields that only make
/// sense for on-device inference: model file path, GPU layer count,
/// context window size, and thread count.
///
/// The chat template format is auto-detected from GGUF metadata by
/// llamadart, so no explicit format field is needed.
class LocalModelConfig {
  /// Creates a [LocalModelConfig].
  const LocalModelConfig({
    required this.modelPath,
    this.nGpuLayers = 0,
    this.contextSize = 4096,
    this.maxTokens = 1024,
    this.threads = 0,
    this.temperature = 0.7,
    this.topP = 0.9,
    this.minP = 0.05,
    this.topK = 40,
    this.mmprojPath,
  });

  /// Absolute path to the `.gguf` model file on disk.
  final String modelPath;

  /// Number of layers to offload to GPU (Metal on Apple Silicon, CUDA on NVIDIA).
  ///
  /// Defaults to `0` (CPU-only) for maximum compatibility across all devices
  /// and simulators. Set to `999` to offload all layers for maximum GPU
  /// performance on supported hardware. Users can adjust this in
  /// Settings > Local Models.
  final int nGpuLayers;

  /// Context window size in tokens.
  final int contextSize;

  /// Default maximum number of tokens to generate per response.
  final int maxTokens;

  /// Number of CPU threads for inference. `0` = auto-detect.
  final int threads;

  /// Sampling temperature (0.0 = deterministic, 1.0+ = creative).
  final double temperature;

  /// Top-p (nucleus) sampling threshold.
  final double topP;

  /// Min-p sampling threshold.
  final double minP;

  /// Top-k sampling threshold.
  final int topK;

  /// Optional path to a vision projector file (for multimodal models).
  final String? mmprojPath;

  /// Serializes this config to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'modelPath': modelPath,
    'nGpuLayers': nGpuLayers,
    'contextSize': contextSize,
    'maxTokens': maxTokens,
    'threads': threads,
    'temperature': temperature,
    'topP': topP,
    'minP': minP,
    'topK': topK,
    'mmprojPath': mmprojPath,
  };

  /// Deserializes a [LocalModelConfig] from a JSON map.
  ///
  /// Silently ignores the legacy `chatFormat` key for backward
  /// compatibility with previously persisted configurations.
  factory LocalModelConfig.fromJson(Map<String, dynamic> json) {
    return LocalModelConfig(
      modelPath: json['modelPath'] as String,
      nGpuLayers: (json['nGpuLayers'] as num?)?.toInt() ?? 0,
      contextSize: (json['contextSize'] as num?)?.toInt() ?? 4096,
      maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 1024,
      threads: (json['threads'] as num?)?.toInt() ?? 0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      topP: (json['topP'] as num?)?.toDouble() ?? 0.9,
      minP: (json['minP'] as num?)?.toDouble() ?? 0.05,
      topK: (json['topK'] as num?)?.toInt() ?? 40,
      mmprojPath: json['mmprojPath'] as String?,
    );
  }
}

/// On-device LLM service backed by llamadart (llama.cpp via Dart
/// Native Assets).
///
/// Manages a [LlamaEngine] instance for inference. The model is
/// loaded lazily on the first call to [complete] or [stream], and
/// disposed when [dispose] is called.
///
/// Chat template formatting is handled automatically by llamadart
/// based on the model's GGUF metadata — no explicit format
/// configuration is required.
///
/// Usage:
/// ```dart
/// final service = LocalLlmService(config: localConfig);
/// final response = await service.complete(request);
/// service.dispose();
/// ```
class LocalLlmService implements LlmService {
  /// Creates a [LocalLlmService] with the given [config].
  LocalLlmService({required this.config});

  /// The local model configuration.
  final LocalModelConfig config;

  LlamaEngine? _engine;
  bool _initializing = false;
  Completer<void>? _initCompleter;

  /// Whether the model is loaded and ready for inference.
  bool get isReady => _engine?.isReady ?? false;

  /// Loads the model if it hasn't been loaded yet.
  ///
  /// Safe to call multiple times — concurrent calls will wait on the
  /// same initialization future.
  Future<void> ensureLoaded() async {
    if (isReady) return;

    if (_initializing) {
      await _initCompleter?.future;
      return;
    }

    _initializing = true;
    _initCompleter = Completer<void>();

    try {
      // Verify the model file exists before attempting to load it.
      final modelFile = File(config.modelPath);
      if (!modelFile.existsSync()) {
        throw Exception(
          'Model file not found: ${config.modelPath}. '
          'Please download the model first from Settings > Local Models.',
        );
      }

      final engine = LlamaEngine(LlamaBackend());
      await engine.setLogLevel(LlamaLogLevel.warn);

      final modelParams = ModelParams(
        gpuLayers: config.nGpuLayers,
        contextSize: config.contextSize,
        numberOfThreads: config.threads,
        numberOfThreadsBatch: config.threads,
      );

      await engine.loadModel(config.modelPath, modelParams: modelParams);

      if (config.mmprojPath != null) {
        await engine.loadMultimodalProjector(config.mmprojPath!);
      }

      _engine = engine;
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      _engine = null;
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    try {
      await ensureLoaded();

      final messages = _buildMessages(request);
      final params = _buildGenParams(request);
      final buffer = StringBuffer();

      await for (final chunk in _engine!.create(messages, params: params)) {
        for (final choice in chunk.choices) {
          if (choice.delta.content != null) {
            buffer.write(choice.delta.content);
          }

          // Handle native tool calls from the engine.
          if (choice.delta.toolCalls != null) {
            final toolCalls = _extractToolCalls(choice.delta.toolCalls!);
            if (toolCalls.isNotEmpty) {
              final text = buffer.toString().trim();
              return LlmResponse.toolCalls(
                text.isEmpty ? null : text,
                toolCalls,
              );
            }
          }
        }
      }

      final text = buffer.toString().trim();
      // Fall back to parsing tool calls from text for models that
      // don't support native tool calling.
      final parsed = _tryParseToolCalls(text);
      return parsed ?? LlmResponse.text(text);
    } on Exception catch (e) {
      return LlmResponse.error('Local LLM error: $e');
    }
  }

  @override
  Stream<LlmStreamEvent> stream(LlmRequest request) async* {
    try {
      await ensureLoaded();
    } catch (e) {
      throw LlmStreamException('Failed to load local model: $e');
    }

    final messages = _buildMessages(request);
    final params = _buildGenParams(request);

    try {
      await for (final chunk in _engine!.create(messages, params: params)) {
        for (final choice in chunk.choices) {
          if (choice.delta.content != null) {
            yield LlmStreamEvent.textDelta(choice.delta.content!);
          }
          if (choice.delta.toolCalls != null) {
            for (final tc in _extractToolCalls(choice.delta.toolCalls!)) {
              yield LlmStreamEvent.toolCall(tc);
            }
          }
          if (choice.finishReason != null) {
            yield const LlmStreamEvent.done();
          }
        }
      }
    } on Object catch (e) {
      throw LlmStreamException('Local LLM inference error: $e');
    }
  }

  @override
  int countTokens(String text) {
    // Rough approximation: ~4 chars per token for English.
    // Accurate counting requires the model loaded and is async,
    // but this interface is synchronous.
    return (text.length / 4).ceil();
  }

  /// Cancels any current generation.
  void cancelGeneration() {
    _engine?.cancelGeneration();
  }

  /// Disposes the engine and frees model resources.
  Future<void> dispose() async {
    await _engine?.dispose();
    _engine = null;
  }

  // ---------------------------------------------------------------------------
  // Message building
  // ---------------------------------------------------------------------------

  /// Converts an [LlmRequest] into a list of [LlamaChatMessage]s
  /// suitable for [LlamaEngine.create].
  ///
  /// The Hermes/Mistral chat template requires exactly one system message and
  /// it must be the very first message. All system-level content (the agent
  /// system prompt and any tool-use instructions) is therefore merged into a
  /// single leading system message.
  List<LlamaChatMessage> _buildMessages(LlmRequest request) {
    final messages = <LlamaChatMessage>[];

    // Merge system prompt and tool-use instructions into one system message so
    // the Hermes chat template constraint ("system message must be first") is
    // satisfied even when tools are present.
    final systemParts = <String>[
      if (request.systemPrompt != null) request.systemPrompt!,
      if (request.tools != null && request.tools!.isNotEmpty)
        _buildToolSystemPrompt(request.tools!),
    ];
    if (systemParts.isNotEmpty) {
      messages.add(
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: systemParts.join('\n\n'),
        ),
      );
    }

    // Conversation history — skip any SystemLlmMessage entries here because
    // system content is already merged above; emitting a system role mid-
    // conversation would violate the Hermes template constraint.
    for (final msg in request.messages) {
      switch (msg) {
        case SystemLlmMessage():
          // Intentionally ignored — system content is handled above.
          break;
        case UserLlmMessage(:final content):
          messages.add(
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: content),
          );
        case AssistantLlmMessage(:final content):
          messages.add(
            LlamaChatMessage.fromText(
              role: LlamaChatRole.assistant,
              text: content,
            ),
          );
        case ToolResultLlmMessage(:final content, :final callId):
          messages.add(
            LlamaChatMessage.fromText(
              role: LlamaChatRole.tool,
              text: '[Tool result for $callId]: $content',
            ),
          );
      }
    }

    return messages;
  }

  /// Builds [GenerationParams] from the [LlmRequest] and [config].
  GenerationParams _buildGenParams(LlmRequest request) {
    return GenerationParams(
      maxTokens: request.maxTokens ?? config.maxTokens,
      temp: request.temperature ?? config.temperature,
      topP: config.topP,
      topK: config.topK,
      minP: config.minP,
    );
  }

  // ---------------------------------------------------------------------------
  // Tool call helpers
  // ---------------------------------------------------------------------------

  /// Extracts [LlmToolCall]s from streaming chunk tool call deltas.
  List<LlmToolCall> _extractToolCalls(
    List<LlamaCompletionChunkToolCall> chunkToolCalls,
  ) {
    return chunkToolCalls.where((tc) => tc.function?.name != null).map((tc) {
      Map<String, dynamic> args = {};
      if (tc.function?.arguments != null) {
        try {
          args = jsonDecode(tc.function!.arguments!) as Map<String, dynamic>;
        } on Object {
          // Partial or invalid JSON — use empty args.
        }
      }
      return LlmToolCall(
        id: tc.id ?? 'local_${DateTime.now().microsecondsSinceEpoch}',
        name: tc.function!.name!,
        arguments: args,
      );
    }).toList();
  }

  /// Generates a system prompt that teaches the model to emit tool calls
  /// in a parseable JSON format.
  String _buildToolSystemPrompt(List<Map<String, dynamic>> tools) {
    final toolDescriptions = tools
        .map((t) {
          final fn = t['function'] as Map<String, dynamic>? ?? t;
          return '- ${fn['name']}: ${fn['description']}\n'
              '  Parameters: ${jsonEncode(fn['parameters'])}';
        })
        .join('\n');

    return '''
You have access to the following tools. To use a tool, respond with a JSON block:
```json
{"tool_calls": [{"name": "tool_name", "arguments": {...}}]}
```

Available tools:
$toolDescriptions

If you don't need a tool, respond normally with text.''';
  }

  /// Attempts to parse tool calls from the model's text output.
  ///
  /// Local models don't always have native tool calling — they may be
  /// prompted to output a specific JSON format. This tries to extract
  /// that JSON as a fallback.
  LlmResponse? _tryParseToolCalls(String text) {
    // Look for a JSON block containing tool_calls.
    final jsonPattern = RegExp(r'```json\s*(\{.*?\})\s*```', dotAll: true);
    final match = jsonPattern.firstMatch(text);
    if (match == null) return null;

    try {
      final json = jsonDecode(match.group(1)!) as Map<String, dynamic>;
      final calls = json['tool_calls'] as List<dynamic>?;
      if (calls == null || calls.isEmpty) return null;

      final toolCalls = calls.map((c) {
        final call = c as Map<String, dynamic>;
        return LlmToolCall(
          id: 'local_${DateTime.now().microsecondsSinceEpoch}',
          name: call['name'] as String,
          arguments: call['arguments'] as Map<String, dynamic>? ?? {},
        );
      }).toList();

      // Extract any text before the JSON block.
      final textBefore = text.substring(0, match.start).trim();
      return LlmResponse.toolCalls(
        textBefore.isEmpty ? null : textBefore,
        toolCalls,
      );
    } on Object {
      return null; // Not valid tool call JSON — treat as plain text.
    }
  }
}
