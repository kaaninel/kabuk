/// Media service — camera, files, audio, and gallery.
///
/// Platform implementations provide the concrete behavior.
/// Agents access this only through `AgentContext`.
library;

/// Abstract interface for media capture and playback.
///
/// Provides access to camera, microphone, file system, and gallery
/// through a unified, platform-agnostic API.
abstract interface class MediaService {
  /// Capture a photo and return the file path.
  Future<String?> capturePhoto();

  /// Capture a video and return the file path.
  Future<String?> captureVideo();

  /// Record audio and return the file path where recording will be saved.
  ///
  /// Call [stopRecording] when done to finalize and obtain the recorded file.
  Future<String?> recordAudio();

  /// Stop an active audio recording and return the path of the saved file.
  ///
  /// Returns `null` if no recording was in progress.
  Future<String?> stopRecording();

  /// Whether audio recording is currently in progress.
  Future<bool> isRecording();

  /// Pick a file from the device. Returns the file path or `null`.
  Future<String?> pickFile({List<String>? allowedExtensions});

  /// Pick an image from the gallery. Returns the file path or `null`.
  Future<String?> pickImage();

  /// Pick multiple images from the gallery. Returns a list of paths.
  Future<List<String>> pickMultipleImages();

  /// Pick a video from the gallery. Returns the file path or `null`.
  Future<String?> pickVideo();

  /// Read a file as bytes.
  Future<List<int>> readFile(String path);

  /// Write bytes to a file.
  Future<void> writeFile(String path, List<int> data);

  /// Delete a file at [path].
  Future<void> deleteFile(String path);

  /// Whether a file exists at [path].
  Future<bool> fileExists(String path);

  /// Returns the path to a platform-appropriate temporary directory.
  Future<String> getTemporaryDirectoryPath();
}
