/// Every user-facing string a biometric prompt might show, resolved by the
/// caller (from `context.l10n`, see `VaultGate._maybeBiometric`) and passed
/// in — this file is pure Dart with no Flutter/context dependency, so it
/// takes the already-localized strings rather than resolving them itself.
class BiometricAuthMessages {
  /// The prompt's own reason line (`localizedReason` for `local_auth`), e.g.
  /// "Desbloquea el Vault" / "Unlock the Vault".
  final String reason;
  final String signInTitle;
  final String biometricHint;
  final String biometricNotRecognized;
  final String biometricSuccess;
  final String cancelButton;
  final String biometricRequiredTitle;
  final String goToSettingsButton;
  final String goToSettingsDescription;
  final String deviceCredentialsRequiredTitle;
  final String deviceCredentialsSetupDescription;

  const BiometricAuthMessages({
    required this.reason,
    required this.signInTitle,
    required this.biometricHint,
    required this.biometricNotRecognized,
    required this.biometricSuccess,
    required this.cancelButton,
    required this.biometricRequiredTitle,
    required this.goToSettingsButton,
    required this.goToSettingsDescription,
    required this.deviceCredentialsRequiredTitle,
    required this.deviceCredentialsSetupDescription,
  });
}

abstract class BiometricAuth {
  Future<bool> isAvailable();
  Future<bool> authenticate(BiometricAuthMessages messages);
}
