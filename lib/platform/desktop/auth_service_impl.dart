/// Desktop [AuthService] implementation extending the shared one.
///
/// Desktop platforms (macOS, Linux, Windows) do not currently support
/// biometric authentication through Flutter's `local_auth`. On macOS,
/// Touch ID may be available in the future through dedicated APIs.
/// Returns `false` gracefully for biometric calls.
library;

import 'package:kabuk/platform/shared/auth_service_impl.dart';
import 'package:kabuk/services/auth.dart';

/// Desktop [AuthService] — identical to shared but named for clarity.
/// Biometric auth is not supported on desktop.
class DesktopAuthService extends SharedAuthService implements AuthService {
  /// Creates a [DesktopAuthService].
  DesktopAuthService({super.knowledgeLoader});

  @override
  Future<bool> authenticateBiometric({String? reason}) async {
    // Biometric auth is not available on desktop platforms.
    return false;
  }
}
