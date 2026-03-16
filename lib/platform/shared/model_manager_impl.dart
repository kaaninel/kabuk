/// Shared implementation of [ModelManager] for all platforms.
///
/// Discovers `.gguf` files in the app's documents directory under a
/// `models/` subdirectory, downloads new models via HTTP streaming,
/// and provides a curated list of recommended tiny models suitable
/// for on-device inference.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:kabuk/services/model_manager.dart';
import 'package:path_provider/path_provider.dart';

/// Shared [ModelManager] implementation using `dart:io` and `path_provider`.
class SharedModelManager implements ModelManager {
  /// Creates a [SharedModelManager].
  ///
  /// An optional [httpClient] can be injected for testing.
  SharedModelManager({http.Client? httpClient})
    : _client = httpClient ?? http.Client();

  final http.Client _client;
  String? _modelsDir;

  @override
  Future<String> get modelsDirectory async {
    if (_modelsDir != null) return _modelsDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/kabuk_models');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _modelsDir = dir.path;
    return _modelsDir!;
  }

  @override
  Future<List<LocalModelInfo>> listLocalModels() async {
    final dir = Directory(await modelsDirectory);
    if (!dir.existsSync()) return const [];

    final models = <LocalModelInfo>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.gguf')) {
        final stat = await entity.stat(); // ignore: avoid_slow_async_io
        final fileName = entity.uri.pathSegments.last;
        final id = fileName.replaceAll('.gguf', '');
        models.add(
          LocalModelInfo(
            id: id,
            name: _humanizeName(id),
            fileName: fileName,
            sizeBytes: stat.size,
            path: entity.path,
            quantization: _extractQuantization(fileName),
            parameterCount: _extractParamCount(fileName),
            chatFormat: _guessChatFormat(fileName),
          ),
        );
      }
    }

    models.sort((a, b) => a.name.compareTo(b.name));
    return models;
  }

  @override
  List<RemoteModelInfo> get recommendedModels => const [
    // ── Qwen3.5 0.8B (unsloth) ──────────────────────────────────────────────
    RemoteModelInfo(
      id: 'qwen3.5-0.8b-q4km',
      name: 'Qwen3.5 0.8B (Q4_K_M)',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf',
      fileName: 'qwen3.5-0.8b-q4km.gguf',
      sizeBytes: 533000000, // ~533 MB
      quantization: 'Q4_K_M',
      parameterCount: '0.8B',
      description:
          'Smallest Qwen3.5. Fast on-device inference, '
          'good for tool calling and quick agent tasks.',
      chatFormat: 'chatml',
    ),
    RemoteModelInfo(
      id: 'qwen3.5-0.8b-q8',
      name: 'Qwen3.5 0.8B (Q8_0)',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q8_0.gguf',
      fileName: 'qwen3.5-0.8b-q8.gguf',
      sizeBytes: 812000000, // ~812 MB
      quantization: 'Q8_0',
      parameterCount: '0.8B',
      description:
          'Near full-precision 0.8B. Best 0.8B quality at '
          'the cost of slightly more RAM.',
      chatFormat: 'chatml',
    ),
    // ── Qwen3.5 2B (unsloth) ────────────────────────────────────────────────
    RemoteModelInfo(
      id: 'qwen3.5-2b-q3km',
      name: 'Qwen3.5 2B (Q3_K_M)',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q3_K_M.gguf',
      fileName: 'qwen3.5-2b-q3km.gguf',
      sizeBytes: 1110000000, // ~1.11 GB
      quantization: 'Q3_K_M',
      parameterCount: '2B',
      description:
          'Compact 2B with aggressive quantization. Fits in '
          '~1.5 GB RAM with solid reasoning capability.',
      chatFormat: 'chatml',
    ),
    RemoteModelInfo(
      id: 'qwen3.5-2b-q4km',
      name: 'Qwen3.5 2B (Q4_K_M)',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf',
      fileName: 'qwen3.5-2b-q4km.gguf',
      sizeBytes: 1280000000, // ~1.28 GB
      quantization: 'Q4_K_M',
      parameterCount: '2B',
      description:
          'Best-value 2B. Strong multilingual reasoning, tool '
          'use, and structured output. Good all-rounder.',
      chatFormat: 'chatml',
    ),
    RemoteModelInfo(
      id: 'qwen3.5-2b-q8',
      name: 'Qwen3.5 2B (Q8_0)',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q8_0.gguf',
      fileName: 'qwen3.5-2b-q8.gguf',
      sizeBytes: 2010000000, // ~2.01 GB
      quantization: 'Q8_0',
      parameterCount: '2B',
      description:
          'Near full-precision 2B. Maximum quality from the '
          '2B tier, excellent for agentic tasks.',
      chatFormat: 'chatml',
    ),
    // ── Qwen3.5 4B (unsloth) ────────────────────────────────────────────────
    RemoteModelInfo(
      id: 'qwen3.5-4b-q3km',
      name: 'Qwen3.5 4B (Q3_K_M)',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q3_K_M.gguf',
      fileName: 'qwen3.5-4b-q3km.gguf',
      sizeBytes: 2290000000, // ~2.29 GB
      quantization: 'Q3_K_M',
      parameterCount: '4B',
      description:
          'Qwen3.5 4B at ~2.3 GB. Good fit for 3 GB RAM '
          'budgets with strong reasoning capability.',
      chatFormat: 'chatml',
    ),
    RemoteModelInfo(
      id: 'qwen3.5-4b-q4km',
      name: 'Qwen3.5 4B (Q4_K_M)',
      downloadUrl:
          'https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf',
      fileName: 'qwen3.5-4b-q4km.gguf',
      sizeBytes: 2740000000, // ~2.74 GB
      quantization: 'Q4_K_M',
      parameterCount: '4B',
      description:
          'Most capable small model. Excellent code, long-context '
          'reasoning, agents, and vision understanding.',
      chatFormat: 'chatml',
    ),
  ];

  @override
  Stream<ModelDownloadProgress> downloadModel(RemoteModelInfo model) async* {
    final dir = await modelsDirectory;
    final filePath = '$dir/${model.fileName}';
    final tmpPath = '$filePath.tmp';

    // Check for existing partial download.
    final tmpFile = File(tmpPath);
    final existingBytes = tmpFile.existsSync() ? tmpFile.lengthSync() : 0;

    final request = http.Request('GET', Uri.parse(model.downloadUrl));
    if (existingBytes > 0) {
      request.headers['Range'] = 'bytes=$existingBytes-';
    }

    final response = await _client.send(request);

    // Determine total size from content-length or known size.
    final contentLength = response.contentLength ?? 0;
    final totalBytes = existingBytes + contentLength;

    final sink = tmpFile.openWrite(
      mode: existingBytes > 0 ? FileMode.append : FileMode.write,
    );

    var bytesReceived = existingBytes;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        bytesReceived += chunk.length;
        yield ModelDownloadProgress(
          modelId: model.id,
          bytesReceived: bytesReceived,
          totalBytes: totalBytes > 0 ? totalBytes : model.sizeBytes,
        );
      }
      await sink.flush();
      await sink.close();

      // Move completed download to final path.
      await tmpFile.rename(filePath);
    } catch (e) {
      await sink.close();
      rethrow;
    }
  }

  @override
  Future<void> deleteModel(LocalModelInfo model) async {
    final file = File(model.path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// Disposes the HTTP client.
  void dispose() => _client.close();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Humanizes a model ID into a display name.
  static String _humanizeName(String id) {
    return id
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .replaceAll('.gguf', '')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// Extracts quantization from the file name (e.g., `q4_k_m`).
  static String? _extractQuantization(String fileName) {
    final match = RegExp(r'[qQ]\d[_\w]*').firstMatch(fileName);
    return match?.group(0)?.toUpperCase();
  }

  /// Extracts parameter count from the file name (e.g., `1.5b`, `3b`).
  static String? _extractParamCount(String fileName) {
    final match = RegExp(r'(\d+\.?\d*)[bB]').firstMatch(fileName);
    return match != null ? '${match.group(1)}B' : null;
  }

  /// Guesses the chat format based on the model file name.
  static String? _guessChatFormat(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('gemma')) return 'gemma';
    if (lower.contains('phi')) return 'chatml';
    if (lower.contains('qwen')) return 'chatml';
    if (lower.contains('smollm')) return 'chatml';
    if (lower.contains('llama')) return 'chatml';
    if (lower.contains('mistral')) return 'chatml';
    return 'chatml'; // Default to ChatML.
  }
}
