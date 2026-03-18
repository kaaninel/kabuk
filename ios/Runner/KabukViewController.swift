import Flutter
import UIKit

/// Custom FlutterViewController that hides the iOS home indicator
/// and defers bottom-edge system gestures so the app's own navigation
/// bar receives touches first.
class KabukViewController: FlutterViewController {
  override var prefersHomeIndicatorAutoHidden: Bool {
    return true
  }

  override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
    return .bottom
  }
}
