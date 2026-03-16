/// Shared `PresentationService` using Flutter's `PlatformDispatcher`.
///
/// Reads real screen metrics (size, pixel ratio, orientation) from the
/// platform's primary display. External display discovery is not
/// available without platform-specific plugins, so `discoverDisplays`
/// returns an empty list.
library;

import 'dart:async';
import 'dart:ui';

import 'package:kabuk/services/presentation.dart';

/// Cross-platform [PresentationService] using real display metrics.
///
/// `getScreenInfo()` queries `PlatformDispatcher.implicitView` for
/// live screen dimensions, pixel ratio, and orientation. Brightness
/// control remains a no-op since programmatic brightness requires
/// platform-specific APIs.
class SharedPresentationService implements PresentationService {
  /// Creates a [SharedPresentationService].
  const SharedPresentationService();

  @override
  Future<List<ExternalDisplay>> discoverDisplays() async => const [];

  @override
  Stream<List<ExternalDisplay>> watchDisplays() {
    return Stream.value(const []);
  }

  @override
  Future<ScreenInfo> getScreenInfo() async {
    final view = PlatformDispatcher.instance.implicitView;

    if (view == null) {
      // No view available (e.g. headless test environment).
      return const ScreenInfo(
        width: 390,
        height: 844,
        pixelRatio: 3.0,
        orientation: ScreenOrientation.portrait,
      );
    }

    final size = view.physicalSize / view.devicePixelRatio;
    final orientation = size.width > size.height
        ? ScreenOrientation.landscapeLeft
        : ScreenOrientation.portrait;

    return ScreenInfo(
      width: size.width,
      height: size.height,
      pixelRatio: view.devicePixelRatio,
      orientation: orientation,
    );
  }

  @override
  Future<double> getBrightness() async {
    final view = PlatformDispatcher.instance.implicitView;
    if (view == null) return 1.0;
    // PlatformDispatcher doesn't expose brightness directly,
    // but we can infer from platform brightness setting.
    final brightness = PlatformDispatcher.instance.platformBrightness;
    return brightness == Brightness.dark ? 0.5 : 1.0;
  }

  @override
  Future<void> setBrightness(double value) async {
    if (value < 0.0 || value > 1.0) {
      throw ArgumentError.value(
        value,
        'value',
        'Brightness must be between 0.0 and 1.0',
      );
    }
    // No-op — programmatic brightness control requires platform APIs.
  }
}
