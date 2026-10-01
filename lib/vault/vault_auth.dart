import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

/// Stores the vault PIN as a derived hash, plus the failed-attempt state
/// that must survive the app being killed. Never holds the PIN in clear.
abstract class VaultCredentialStore {
  String? get hash;
  String? get salt;

  /// 'pbkdf2-sha256', or null for a record written before it existed
  /// (salted SHA-256), which is upgraded on the next correct entry.
  String? get kdf;
  int get iterations;
  Future<void> save(String hash, String salt,
      {String? kdf, int iterations = 0});

  int get failedAttempts;
  int get lockedUntilMs;
  Future<void> saveAttempts(int failed, int lockedUntilMs);

  Future<void> clear();
}

class InMemoryVaultCredentialStore implements VaultCredentialStore {
  String? _hash;
  String? _salt;
  String? _kdf;
  int _iterations = 0;
  int _failed = 0;
  int _lockedUntil = 0;
  @override
  String? get hash => _hash;
  @override
  String? get salt => _salt;
  @override
  String? get kdf => _kdf;
  @override
  int get iterations => _iterations;
  @override
  int get failedAttempts => _failed;
  @override
  int get lockedUntilMs => _lockedUntil;
  @override
  Future<void> save(String hash, String salt,
      {String? kdf, int iterations = 0}) async {
    _hash = hash;
    _salt = salt;
    _kdf = kdf;
    _iterations = iterations;
  }

  @override
  Future<void> saveAttempts(int failed, int lockedUntilMs) async {
    _failed = failed;
    _lockedUntil = lockedUntilMs;
  }

  @override
  Future<void> clear() async {
    _hash = null;
    _salt = null;
    _kdf = null;
    _iterations = 0;
    _failed = 0;
    _lockedUntil = 0;
  }
}

/// PBKDF2-HMAC-SHA256 (RFC 8018), one 32-byte block, as hex.
String pbkdf2Sha256Hex(String pin, String salt, int iterations) {
  final hmac = Hmac(sha256, utf8.encode(pin));
  var u = hmac.convert([...utf8.encode(salt), 0, 0, 0, 1]).bytes;
  final out = List<int>.of(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Derives the stored hash from a PIN. Swappable because 100k iterations take
/// a noticeable moment: in the app they run off the UI isolate.
typedef VaultKdf = Future<String> Function(
    String pin, String salt, int iterations);

Future<String> _isolateKdf(String pin, String salt, int iterations) =>
    Isolate.run(() => pbkdf2Sha256Hex(pin, salt, iterations));

Future<String> _inlineKdf(String pin, String salt, int iterations) async =>
    pbkdf2Sha256Hex(pin, salt, iterations);

/// Off the UI isolate in the app. Inline under `flutter test`: a real isolate
/// never resolves inside a widget test's fake clock.
final VaultKdf defaultVaultKdf =
    Platform.environment.containsKey('FLUTTER_TEST') ? _inlineKdf : _isolateKdf;

enum PinResult { ok, wrong, locked }

class PinCheck {
  const PinCheck(this.result, {this.retryIn});
  final PinResult result;

  /// While [PinResult.locked]: how long until another try is allowed.
  final Duration? retryIn;
}

/// How long the PIN pad stays locked after [failed] wrong entries in a row:
/// free for 4, then 30 s, doubling with each further miss, at most an hour.
/// A 4-digit PIN has only 10 000 values; this is what keeps someone holding
/// the phone from simply trying them.
Duration lockFor(int failed) {
  if (failed < 5) return Duration.zero;
  // Past this the doubling is over the cap anyway — and pow() would overflow
  // to a negative (no lock at all) from 64 misses on.
  if (failed >= 12) return const Duration(hours: 1);
  final seconds = 30 * pow(2, failed - 5).toInt();
  return Duration(seconds: min(seconds, 3600));
}

/// PIN auth for the Vault.
///
/// What it protects against, honestly: someone with the phone in their hand.
/// The files themselves are hidden, not encrypted (see the Vault's own
/// notice), and a 4–6 digit PIN cannot resist an offline attack on a copy of
/// the app's data whatever the hash — the derivation cost and the lockout
/// make guessing slow on the device, which is the threat that matters here.
class VaultAuth {
  VaultAuth(this._store, {VaultKdf? kdf, DateTime Function()? now})
      : _kdf = kdf ?? defaultVaultKdf,
        _now = now ?? DateTime.now;

  static const String kdfName = 'pbkdf2-sha256';
  static const int defaultIterations = 100000;

  final VaultCredentialStore _store;
  final VaultKdf _kdf;
  final DateTime Function() _now;

  bool get isConfigured => _store.hash != null && _store.salt != null;

  /// The original scheme (before PBKDF2): kept only to verify, and upgrade,
  /// PINs set by older versions.
  static String legacyHash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt$pin')).toString();

  static String _newSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64Url.encode(bytes);
  }

  Future<void> setPin(String pin) async {
    final salt = _newSalt();
    final hash = await _kdf(pin, salt, defaultIterations);
    await _store.save(hash, salt, kdf: kdfName, iterations: defaultIterations);
    await _store.saveAttempts(0, 0);
  }

  /// Re-derives a legacy PIN with PBKDF2 under the SAME salt: if the app dies
  /// mid-write, whatever landed is still checkable with that salt (see the
  /// two-scheme check in [verify]).
  Future<void> _upgrade(String pin, String salt) async {
    final hash = await _kdf(pin, salt, defaultIterations);
    await _store.save(hash, salt, kdf: kdfName, iterations: defaultIterations);
  }

  /// Time left on the lockout, or null when a try is allowed.
  ///
  /// Never more than the lock the current streak earns: a clock moved back
  /// (or corrected after running ahead) would otherwise lock the owner out
  /// for days. A clock moved FORWARD does shorten the wait — the wall clock
  /// is all an app can persist across a reboot; an accepted limit.
  Duration? lockRemaining() {
    final left = _store.lockedUntilMs - _now().millisecondsSinceEpoch;
    if (left <= 0) return null;
    final cap = lockFor(_store.failedAttempts);
    final d = Duration(milliseconds: left);
    return d > cap ? cap : d;
  }

  Future<PinCheck> verify(String pin) async {
    final h = _store.hash;
    final s = _store.salt;
    if (h == null || s == null) return const PinCheck(PinResult.wrong);
    final locked = lockRemaining();
    if (locked != null) return PinCheck(PinResult.locked, retryIn: locked);

    final legacy = _store.kdf == null;
    final iterations =
        _store.iterations > 0 ? _store.iterations : defaultIterations;
    final candidate =
        legacy ? legacyHash(pin, s) : await _kdf(pin, s, iterations);
    var ok = _constantTimeEquals(candidate, h);
    var needsUpgrade = legacy && ok;
    if (!ok) {
      // The record may say one scheme and hold the other: an upgrade cut off
      // between its writes. Checking both before counting a miss is what
      // keeps a crash from locking the owner out of their own Vault.
      final other =
          legacy ? await _kdf(pin, s, defaultIterations) : legacyHash(pin, s);
      ok = _constantTimeEquals(other, h);
      needsUpgrade = ok;
    }
    if (ok) {
      await _store.saveAttempts(0, 0);
      // Legacy or half-upgraded: (re-)derive it now, while we have the PIN.
      if (needsUpgrade) await _upgrade(pin, s);
      return const PinCheck(PinResult.ok);
    }

    final failed = _store.failedAttempts + 1;
    final lock = lockFor(failed);
    final until =
        lock == Duration.zero ? 0 : _now().add(lock).millisecondsSinceEpoch;
    await _store.saveAttempts(failed, until);
    return lock == Duration.zero
        ? const PinCheck(PinResult.wrong)
        : PinCheck(PinResult.locked, retryIn: lock);
  }

  /// Unlocked another way (fingerprint): the miss streak is over.
  Future<void> recordSuccess() => _store.saveAttempts(0, 0);

  Future<void> clear() => _store.clear();

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

class HiveVaultCredentialStore implements VaultCredentialStore {
  final Box box;
  HiveVaultCredentialStore(this.box);
  @override
  String? get hash => box.get('hash') as String?;
  @override
  String? get salt => box.get('salt') as String?;
  @override
  String? get kdf => box.get('kdf') as String?;
  @override
  int get iterations => (box.get('iter') as int?) ?? 0;
  @override
  int get failedAttempts => (box.get('fails') as int?) ?? 0;
  @override
  int get lockedUntilMs => (box.get('lockedUntil') as int?) ?? 0;
  @override
  Future<void> save(String hash, String salt,
      {String? kdf, int iterations = 0}) async {
    // One batch, not four puts: Hive appends the whole batch in a single
    // write, so a crash cannot leave a hash paired with the wrong salt/scheme.
    if (kdf == null) {
      await box.deleteAll(['kdf', 'iter']);
      await box.putAll({'hash': hash, 'salt': salt});
    } else {
      await box.putAll(
          {'kdf': kdf, 'iter': iterations, 'hash': hash, 'salt': salt});
    }
  }

  @override
  Future<void> saveAttempts(int failed, int lockedUntilMs) async {
    await box.put('fails', failed);
    await box.put('lockedUntil', lockedUntilMs);
  }

  @override
  Future<void> clear() async {
    for (final k in ['hash', 'salt', 'kdf', 'iter', 'fails', 'lockedUntil']) {
      await box.delete(k);
    }
  }
}
