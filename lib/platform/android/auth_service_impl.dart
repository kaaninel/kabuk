/// Android [AuthService] implementation extending the shared one.
///
/// Adds real biometric authentication via `local_auth`.
library;

import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/platform/shared/auth_service_impl.dart';
import 'package:kabuk/services/auth.dart';
import 'package:local_auth/local_auth.dart';

/// Android [AuthService] that integrates fingerprint / face unlock
/// via `local_auth`.
class AndroidAuthService extends SharedAuthService implements AuthService {
  /// Creates an [AndroidAuthService].
  AndroidAuthService({super.knowledgeLoader});

  final _localAuth = LocalAuthentication();

  @override
  Future<bool> authenticateBiometric({String? reason}) async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;
      return _localAuth.authenticate(
        localizedReason: reason ?? 'Authenticate to continue',
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } on Object {
      return false;
    }
  }
}

/// A [Result]-wrapped version of biometric auth for use inside agents.
extension AndroidAuthServiceResultX on AndroidAuthService {
  /// Authenticate via biometrics, returning a typed [Result].
  Future<Result<bool>> authenticateBiometricResult({String? reason}) async {
    try {
      final ok = await authenticateBiometric(reason: reason);
      return Result.success(ok);
    } on Object catch (e, st) {
      return Result.failure(
        ServiceError.unknown('Biometric auth error: $e', e, st),
      );
    }
  }
}
