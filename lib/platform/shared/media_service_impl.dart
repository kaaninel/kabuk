/// Shared [MediaService] implementation using `dart:io` and platform plugins.
///
/// Provides real file I/O operations for mobile and desktop platforms.
/// Photo/video capture and image picking use the `image_picker` plugin.
/// Audio recording uses the `record` plugin.
/// File picking uses the `file_picker` plugin.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kabuk/services/media.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Cross-platform [MediaService] backed by `dart:io` file operations
/// and the `image_picker` / `record` / `file_picker` plugins.
///
/// File reading, writing, deletion, and existence checks work on all
/// non-web platforms. Media capture methods use platform plugins.
class SharedMediaService implements MediaService {
  /// Creates a [SharedMediaService].
  SharedMediaService();

  final _picker = ImagePicker();
  AudioRecorder? _recorder;

  /// Lazily creates the [AudioRecorder] instance.
  AudioRecorder get _audioRecorder => _recorder ??= AudioRecorder();

  @override
  Future<String?> capturePhoto() async {
    final file = await _picker.pickImage(source: ImageSource.camera);
    return file?.path;
  }

  @override
  Future<String?> captureVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.camera);
    return file?.path;
  }

  @override
  Future<String?> recordAudio() async {
    final recorder = _audioRecorder;

    // Check microphone permission.
    if (!await recorder.hasPermission()) {
      return null;
    }

    // Generate a temporary file path for the recording.
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${dir.path}/recordings/audio_$timestamp.m4a';
    await Directory('${dir.path}/recordings').create(recursive: true);

    // Start recording in AAC format.
    await recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );

    // Returns the path where the recording will be saved.
    // Call stopRecording() to finalize.
    return path;
  }

  @override
  Future<String?> stopRecording() async {
    final recorder = _audioRecorder;
    if (!await recorder.isRecording()) return null;
    return recorder.stop();
  }

  @override
  Future<bool> isRecording() => _audioRecorder.isRecording();

  @override
  Future<String?> pickFile({List<String>? allowedExtensions}) async {
    final result = await FilePicker.platform.pickFiles(
      type: allowedExtensions != null && allowedExtensions.isNotEmpty
          ? FileType.custom
          : FileType.any,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
    );

    return result?.files.firstOrNull?.path;
  }

  @override
  Future<String?> pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    return file?.path;
  }

  @override
  Future<List<String>> pickMultipleImages() async {
    final files = await _picker.pickMultiImage();
    return files.map((f) => f.path).toList();
  }

  @override
  Future<String?> pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    return file?.path;
  }

  @override
  Future<List<int>> readFile(String path) => File(path).readAsBytes();

  @override
  Future<void> writeFile(String path, List<int> data) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data);
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  @override
  Future<bool> fileExists(String path) async => File(path).existsSync();

  @override
  Future<String> getTemporaryDirectoryPath() async {
    final dir = await getTemporaryDirectory();
    return dir.path;
  }
}
