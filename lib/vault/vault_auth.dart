import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Stores the vault PIN as a salted hash. Never holds the PIN in clear.
abstract class VaultCredentialStore {
  String? get hash;
  String? get salt;
  Future<void> save(String hash, String salt);
  Future<void> clear();
}

class InMemoryVaultCredentialStore implements VaultCredentialStore {
  String? _hash;
  String? _salt;
  @override
  String? get hash => _hash;
  @override
  String? get salt => _salt;
  @override
  Future<void> save(String hash, String salt) async {
    _hash = hash;
    _salt = salt;
  }
  @override
  Future<void> clear() async {
    _hash = null;
    _salt = null;
  }
}

/// PIN auth for the Vault: salted SHA-256, deterministic verification.
class VaultAuth {
  final VaultCredentialStore _store;
  VaultAuth(this._store);

  bool get isConfigured => _store.hash != null && _store.salt != null;

  static String hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt$pin')).toString();

  static String _newSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64Url.encode(bytes);
  }

  Future<void> setPin(String pin) async {
    final salt = _newSalt();
    await _store.save(hashPin(pin, salt), salt);
  }

  bool verify(String pin) {
    final h = _store.hash;
    final s = _store.salt;
    if (h == null || s == null) return false;
    return hashPin(pin, s) == h;
  }

  Future<void> clear() => _store.clear();
}
