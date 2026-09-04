import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
// AndroidAuthMessages lives in local_auth_android, not re-exported by
// package:local_auth/local_auth.dart — this is the import local_auth_android's
// own example uses to reach it. Field names below (signInTitle, biometricHint,
// cancelButton, biometricNotRecognized, biometricSuccess,
// deviceCredentialsRequiredTitle, deviceCredentialsSetupDescription,
// goToSettingsButton, goToSettingsDescription) were checked against the
// installed local_auth_android 1.0.56 source
// (lib/src/auth_messages_android.dart) rather than guessed.
import 'package:local_auth_android/local_auth_android.dart';
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
  Future<bool> authenticate(BiometricAuthMessages messages) async {
    try {
      return await _auth.authenticate(
        localizedReason: messages.reason,
        authMessages: [
          AndroidAuthMessages(
            signInTitle: messages.signInTitle,
            biometricHint: messages.biometricHint,
            biometricNotRecognized: messages.biometricNotRecognized,
            biometricSuccess: messages.biometricSuccess,
            cancelButton: messages.cancelButton,
            biometricRequiredTitle: messages.biometricRequiredTitle,
            goToSettingsButton: messages.goToSettingsButton,
            goToSettingsDescription: messages.goToSettingsDescription,
            deviceCredentialsRequiredTitle:
                messages.deviceCredentialsRequiredTitle,
            deviceCredentialsSetupDescription:
                messages.deviceCredentialsSetupDescription,
          ),
        ],
        // false (the local_auth default) is deliberate: with stickyAuth
        // true, local_auth_android's AuthenticationHelper re-opens the OS
        // sheet on its own the moment the hosting Activity resumes — with
        // no way to tell "user just tapped Cancel and the sheet is
        // dismissing" apart from "app was genuinely backgrounded" (both
        // fire the same onPause/onResume dance on this device). That native
        // auto-reopen is what turned Cancel into a loop. VaultGate already
        // re-attempts biometric itself on a genuine app resume (see
        // didChangeAppLifecycleState), guarded so it only fires for an
        // attempt that was actually interrupted, not one the user resolved
        // by cancelling — so we don't need local_auth's own sticky retry.
        options: const AuthenticationOptions(stickyAuth: false, biometricOnly: true),
      );
    } catch (e) {
      // Genuinely unavailable/misconfigured (NotEnrolled, NotAvailable,
      // PasscodeNotSet, LockedOut, PermanentlyLockedOut, ...) lands here as
      // a PlatformException rather than a plain `false` return. We still
      // fall back to PIN either way, but log so a real misconfiguration
      // (as opposed to an ordinary user cancel/failed attempt, which
      // `authenticate` above resolves as `false` with no exception) is
      // diagnosable instead of silently degrading every unlock to PIN.
      debugPrint('LocalAuthBiometric.authenticate failed: $e');
      return false;
    }
  }
}
