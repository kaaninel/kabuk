import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/platform/shared/device_capabilities.dart';
import 'package:kabuk/services/model_manager.dart';

void main() {
  const standard = RemoteModelInfo(
    id: kStandardModelId,
    name: 'MiniCPM5 1B (Q4_K_M)',
    downloadUrl: 'https://example.com/mini.gguf',
    fileName: 'minicpm5-1b-q4km.gguf',
    sizeBytes: 1190000000,
  );
  const big = RemoteModelInfo(
    id: 'qwen3.5-4b-q4km',
    name: 'Qwen3.5 4B (Q4_K_M)',
    downloadUrl: 'https://example.com/qwen.gguf',
    fileName: 'qwen3.5-4b-q4km.gguf',
    sizeBytes: 2740000000,
  );
  const tiny = RemoteModelInfo(
    id: 'qwen3.5-0.8b-q4km',
    name: 'Qwen3.5 0.8B (Q4_K_M)',
    downloadUrl: 'https://example.com/qwen8.gguf',
    fileName: 'qwen3.5-0.8b-q4km.gguf',
    sizeBytes: 533000000,
  );

  DeviceCapabilities device(int ramGb) => DeviceCapabilities(
    totalRamBytes: ramGb * 1024 * 1024 * 1024,
    // Only used fields matter for the picker.
  );

  test('picks the standard model when it fits in RAM', () {
    final picked = pickStandardModelForDevice(
      device(6),
      const [big, tiny, standard],
    );
    expect(picked.id, kStandardModelId);
  });

  test('picks the standard model even with a bigger candidate', () {
    final picked = pickStandardModelForDevice(
      device(16),
      const [big, standard],
    );
    expect(picked.id, kStandardModelId);
  });

  test('falls back to largest-that-fits when standard model is absent', () {
    final picked = pickStandardModelForDevice(
      device(16),
      const [big, tiny],
    );
    expect(picked.id, 'qwen3.5-4b-q4km');
  });

  test('falls back to the device picker when standard model is too big', () {
    // 2 GB RAM budget = 1 GB usable for models; MiniCPM needs ~2.4 GB.
    final picked = pickStandardModelForDevice(
      device(2),
      const [big, standard, tiny],
    );
    expect(picked.id, 'qwen3.5-0.8b-q4km');
  });
}