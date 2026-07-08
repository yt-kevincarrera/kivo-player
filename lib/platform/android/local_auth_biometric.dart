import 'package:local_auth/local_auth.dart';
import '../interfaces/biometric_auth.dart';

class LocalAuthBiometric implements BiometricAuth {
  final LocalAuthentication _auth = LocalAuthentication();
  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }
  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );
    } catch (_) {
      return false;
    }
  }
}
