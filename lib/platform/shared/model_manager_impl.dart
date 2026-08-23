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
    // ── MiniCPM5 1B — STANDARD on-device model ──────────────────────────────
    // Kabuk standardizes on MiniCPM5 1B: it is the only on-device model,
    // auto-downloaded during onboarding. Good instruction following, tool
    // calling and multilingual support at a size that fits any phone.
    RemoteModelInfo(
      id: 'minicpm5-1b-q4km',
      name: 'MiniCPM5 1B (Q4_K_M)',
      downloadUrl:
          'https://huggingface.co/openbmb/MiniCPM5-1B-GGUF/resolve/main/MiniCPM5-1B-Q4_K_M.gguf',
      fileName: 'minicpm5-1b-q4km.gguf',
      sizeBytes: 1190000000, // ~1.19 GB
      quantization: 'Q4_K_M',
      parameterCount: '1B',
      description:
          'The standard Kabuk model. Fast, fits in ~2.5 GB RAM, '
          'strong tool calling and instruction following for agent tasks.',
      chatFormat: 'minicpm',
    ),
    RemoteModelInfo(
      id: 'minicpm5-1b-q8',
      name: 'MiniCPM5 1B (Q8_0)',
      downloadUrl:
          'https://huggingface.co/openbmb/MiniCPM5-1B-GGUF/resolve/main/MiniCPM5-1B-Q8_0.gguf',
      fileName: 'minicpm5-1b-q8.gguf',
      sizeBytes: 1790000000, // ~1.79 GB
      quantization: 'Q8_0',
      parameterCount: '1B',
      description:
          'Near full-precision MiniCPM5 1B. Best quality from the '
          'standard tier at the cost of more RAM.',
      chatFormat: 'minicpm',
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
    if (lower.contains('minicpm')) return 'minicpm';
    if (lower.contains('gemma')) return 'gemma';
    if (lower.contains('phi')) return 'chatml';
    if (lower.contains('qwen')) return 'chatml';
    if (lower.contains('smollm')) return 'chatml';
    if (lower.contains('llama')) return 'chatml';
    if (lower.contains('mistral')) return 'chatml';
    return 'chatml'; // Default to ChatML.
  }
}
