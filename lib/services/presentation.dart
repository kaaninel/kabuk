/// Display, brightness, and external screen abstraction.
///
/// PresentationService provides a unified interface for querying
/// screen information, managing brightness, and discovering external
/// displays. Platform implementations live in `lib/platform/`.
///
/// Agents access this service exclusively through `AgentContext` to
/// adapt UI output based on available screen real estate and user
/// display preferences.
abstract interface class PresentationService {
  /// Discovers all currently connected external displays.
  ///
  /// Returns an empty list if no external displays are connected.
  /// For continuous monitoring, use [watchDisplays] instead.
  Future<List<ExternalDisplay>> discoverDisplays();

  /// Emits the current list of connected external displays whenever
  /// it changes.
  ///
  /// The stream is broadcast — multiple listeners may subscribe.
  /// Emits immediately with the current list upon subscription, then
  /// re-emits whenever displays are connected or disconnected.
  Stream<List<ExternalDisplay>> watchDisplays();

  /// Returns information about the device's primary screen.
  Future<ScreenInfo> getScreenInfo();

  /// Returns the current screen brightness as a value between 0.0
  /// (dimmest) and 1.0 (brightest).
  Future<double> getBrightness();

  /// Sets the screen brightness to [value].
  ///
  /// - [value]: A double between 0.0 (dimmest) and 1.0 (brightest).
  ///
  /// Throws [ArgumentError] if [value] is outside the valid range.
  /// On platforms that do not support programmatic brightness control,
  /// this is a no-op.
  Future<void> setBrightness(double value);
}

/// An external display connected to the device.
///
/// Represents monitors, projectors, AirPlay displays, or any other
/// secondary screen the device can present content on.
class ExternalDisplay {
  /// Creates an [ExternalDisplay].
  const ExternalDisplay({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
  });

  /// Platform-specific unique identifier for the display.
  final String id;

  /// Human-readable name of the display (e.g. "LG UltraWide").
  final String name;

  /// Display width in logical pixels.
  final int width;

  /// Display height in logical pixels.
  final int height;

  @override
  String toString() =>
      'ExternalDisplay(id: $id, name: $name, ${width}x$height)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ExternalDisplay && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Information about the device's primary screen.
class ScreenInfo {
  /// Creates a [ScreenInfo].
  const ScreenInfo({
    required this.width,
    required this.height,
    required this.pixelRatio,
    required this.orientation,
  });

  /// Screen width in logical pixels.
  final double width;

  /// Screen height in logical pixels.
  final double height;

  /// The device pixel ratio (physical pixels per logical pixel).
  ///
  /// A value of 2.0 means the screen has 2 physical pixels for every
  /// logical pixel (e.g. Retina displays).
  final double pixelRatio;

  /// The current screen orientation.
  final ScreenOrientation orientation;

  @override
  String toString() =>
      'ScreenInfo(${width}x$height, pixelRatio: $pixelRatio, orientation: $orientation)';
}

/// The orientation of the device screen.
enum ScreenOrientation {
  /// Portrait mode with the device upright.
  portrait,

  /// Portrait mode with the device upside down.
  portraitUpsideDown,

  /// Landscape mode with the device rotated left.
  landscapeLeft,

  /// Landscape mode with the device rotated right.
  landscapeRight,
}
