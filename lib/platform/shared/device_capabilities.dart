/// Device capability detection for model selection.
///
/// Queries the host OS for total physical RAM and other hardware
/// characteristics so the app can automatically pick the best
/// on-device model for the user's hardware.
///
/// This file may use `dart:io` and lives in `lib/platform/shared/`
/// as required by the architecture guidelines.
library;

import 'dart:io';

import 'package:kabuk/services/model_manager.dart';

/// Hardware capabilities of the current device.
class DeviceCapabilities {
  /// Creates a [DeviceCapabilities].
  const DeviceCapabilities({required this.totalRamBytes});

  /// Total physical RAM in bytes.
  final int totalRamBytes;

  /// Total RAM in gigabytes (floating point).
  double get totalRamGB => totalRamBytes / (1024 * 1024 * 1024);

  /// Detects the current device's hardware capabilities.
  ///
  /// On iOS/macOS uses `sysctl hw.memsize`.
  /// On Android reads `/proc/meminfo`.
  /// On Linux reads `/proc/meminfo`.
  /// Falls back to a conservative 2 GB estimate on unknown platforms.
  static Future<DeviceCapabilities> detect() async {
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        return await _detectApple();
      } else if (Platform.isAndroid || Platform.isLinux) {
        return await _detectLinux();
      }
    } on Object {
      // Fall through to conservative default.
    }
    // Conservative fallback: assume 2 GB.
    return const DeviceCapabilities(totalRamBytes: 2 * 1024 * 1024 * 1024);
  }

  /// Reads total RAM on Apple platforms via `sysctl`.
  static Future<DeviceCapabilities> _detectApple() async {
    final result = await Process.run('sysctl', ['-n', 'hw.memsize']);
    if (result.exitCode == 0) {
      final bytes = int.tryParse((result.stdout as String).trim());
      if (bytes != null && bytes > 0) {
        return DeviceCapabilities(totalRamBytes: bytes);
      }
    }
    return const DeviceCapabilities(totalRamBytes: 2 * 1024 * 1024 * 1024);
  }

  /// Reads total RAM on Linux/Android via `/proc/meminfo`.
  static Future<DeviceCapabilities> _detectLinux() async {
    final file = File('/proc/meminfo');
    if (file.existsSync()) {
      final contents = await file.readAsString();
      final match = RegExp(r'MemTotal:\s+(\d+)\s+kB').firstMatch(contents);
      if (match != null) {
        final kb = int.tryParse(match.group(1)!);
        if (kb != null) {
          return DeviceCapabilities(totalRamBytes: kb * 1024);
        }
      }
    }
    return const DeviceCapabilities(totalRamBytes: 2 * 1024 * 1024 * 1024);
  }
}

/// Picks the best model from [candidates] for the given [device].
///
/// Selection strategy:
/// - A model needs roughly 2x its file size in RAM for inference
///   (model weights + KV cache + overhead).
/// - We pick the **largest** model whose estimated RAM usage stays
///   under 50 % of total device RAM, leaving headroom for the OS
///   and the rest of the app.
/// - If no model fits, we fall back to the smallest available.
///
/// The returned model is the recommended one to auto-download.
RemoteModelInfo pickModelForDevice(
  DeviceCapabilities device,
  List<RemoteModelInfo> candidates,
) {
  if (candidates.isEmpty) {
    throw ArgumentError('candidates must not be empty');
  }

  // Sort by size ascending so we can find the largest that fits.
  final sorted = [...candidates]
    ..sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));

  // Budget: 50% of total RAM for model inference.
  final ramBudget = device.totalRamBytes ~/ 2;

  // Estimated RAM usage ≈ 2x file size (weights + KV cache + overhead).
  RemoteModelInfo best = sorted.first; // fallback to smallest
  for (final model in sorted) {
    final estimatedRam = model.sizeBytes * 2;
    if (estimatedRam <= ramBudget) {
      best = model; // keep upgrading to the largest that fits
    } else {
      break; // sorted ascending, so no larger models will fit
    }
  }

  return best;
}
