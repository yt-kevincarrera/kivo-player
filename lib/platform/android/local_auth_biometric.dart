import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import '../interfaces/biometric_auth.dart';

class LocalAuthBiometric implements BiometricAuth {
  final LocalAuthentication _auth = LocalAuthentication();
  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (e) {
      // Falling back to PIN is intended, but a thrown check hides real
      // misconfiguration (e.g. a non-AppCompat host theme) — surface it.
      debugPrint('LocalAuthBiometric.isAvailable failed: $e');
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
    } catch (e) {
      // Same rationale: a swallowed exception here silently degrades every
      // biometric unlock to PIN with no signal. Log so it's diagnosable.
      debugPrint('LocalAuthBiometric.authenticate failed: $e');
      return false;
    }
  }
}
