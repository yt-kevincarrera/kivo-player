abstract class BiometricAuth {
  Future<bool> isAvailable();
  Future<bool> authenticate(String reason);
}
