/// Model manager — discovery, download, and lifecycle for local GGUF models.
///
/// Provides an abstract interface for managing on-device LLM models.
/// The concrete implementation lives in `lib/platform/shared/` and uses
/// the file system + HTTP to download and cache GGUF files.
library;

/// Metadata about a locally available GGUF model.
class LocalModelInfo {
  /// Creates a [LocalModelInfo].
  const LocalModelInfo({
    required this.id,
    required this.name,
    required this.fileName,
    required this.sizeBytes,
    required this.path,
    this.quantization,
    this.parameterCount,
    this.description,
    this.chatFormat,
  });

  /// Unique identifier for this model (e.g., `'qwen2.5-1.5b-q4km'`).
  final String id;

  /// Human-readable display name.
  final String name;

  /// The `.gguf` file name on disk.
  final String fileName;

  /// File size in bytes.
  final int sizeBytes;

  /// Absolute path to the model file.
  final String path;

  /// Quantization level (e.g., `'Q4_K_M'`, `'Q5_K_S'`).
  final String? quantization;

  /// Approximate parameter count (e.g., `'1.5B'`, `'3B'`).
  final String? parameterCount;

  /// Short description of the model's capabilities.
  final String? description;

  /// Suggested chat format for this model.
  final String? chatFormat;

  /// Human-readable file size.
  String get formattedSize {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fileName': fileName,
    'sizeBytes': sizeBytes,
    'path': path,
    'quantization': quantization,
    'parameterCount': parameterCount,
    'description': description,
    'chatFormat': chatFormat,
  };

  /// Deserializes from JSON.
  factory LocalModelInfo.fromJson(Map<String, dynamic> json) {
    return LocalModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      fileName: json['fileName'] as String,
      sizeBytes: json['sizeBytes'] as int,
      path: json['path'] as String,
      quantization: json['quantization'] as String?,
      parameterCount: json['parameterCount'] as String?,
      description: json['description'] as String?,
      chatFormat: json['chatFormat'] as String?,
    );
  }
}

/// A downloadable model from a remote source (e.g., Hugging Face).
class RemoteModelInfo {
  /// Creates a [RemoteModelInfo].
  const RemoteModelInfo({
    required this.id,
    required this.name,
    required this.downloadUrl,
    required this.fileName,
    required this.sizeBytes,
    this.quantization,
    this.parameterCount,
    this.description,
    this.chatFormat,
  });

  /// Unique identifier.
  final String id;

  /// Display name.
  final String name;

  /// Direct download URL for the GGUF file.
  final String downloadUrl;

  /// File name to save as.
  final String fileName;

  /// Expected file size in bytes.
  final int sizeBytes;

  /// Quantization level.
  final String? quantization;

  /// Parameter count.
  final String? parameterCount;

  /// Description.
  final String? description;

  /// Suggested chat format.
  final String? chatFormat;

  /// Human-readable file size.
  String get formattedSize {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }
}

/// Current progress of a model download.
class ModelDownloadProgress {
  /// Creates a [ModelDownloadProgress].
  const ModelDownloadProgress({
    required this.modelId,
    required this.bytesReceived,
    required this.totalBytes,
  });

  /// The model being downloaded.
  final String modelId;

  /// Bytes received so far.
  final int bytesReceived;

  /// Total expected bytes (may be 0 if unknown).
  final int totalBytes;

  /// Download progress as a fraction (0.0 to 1.0).
  double get progress =>
      totalBytes > 0 ? (bytesReceived / totalBytes).clamp(0.0, 1.0) : 0.0;
}

/// Abstract interface for managing local GGUF models.
///
/// Implementations handle discovery of existing models on disk,
/// downloading new models, and deletion.
abstract interface class ModelManager {
  /// Lists all locally available GGUF models.
  Future<List<LocalModelInfo>> listLocalModels();

  /// Returns a curated list of recommended small models for download.
  List<RemoteModelInfo> get recommendedModels;

  /// Downloads a model from [url] and saves it to the models directory.
  ///
  /// Yields [ModelDownloadProgress] events. The returned stream completes
  /// when the download finishes.
  Stream<ModelDownloadProgress> downloadModel(RemoteModelInfo model);

  /// Deletes a locally stored model.
  Future<void> deleteModel(LocalModelInfo model);

  /// Returns the directory path where models are stored.
  Future<String> get modelsDirectory;
}
