import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/vault/vault_auth.dart';

/// A fast stand-in so these tests don't each spend 100k HMAC rounds.
Future<String> _fastKdf(String pin, String salt, int iterations) async =>
    pbkdf2Sha256Hex(pin, salt, 2);

class _Clock {
  DateTime t = DateTime(2026, 10, 1, 12);
  DateTime call() => t;
}

void main() {
  group('pbkdf2Sha256Hex matches the published PBKDF2-HMAC-SHA256 vectors', () {
    test('c = 1', () {
      expect(pbkdf2Sha256Hex('password', 'salt', 1),
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
    });
    test('c = 2', () {
      expect(pbkdf2Sha256Hex('password', 'salt', 2),
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
    });
    test('c = 4096', () {
      expect(pbkdf2Sha256Hex('password', 'salt', 4096),
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
    });
  });

  test('unconfigured store: not configured, nothing verifies', () async {
    final auth = VaultAuth(InMemoryVaultCredentialStore(), kdf: _fastKdf);
    expect(auth.isConfigured, false);
    expect((await auth.verify('1234')).result, PinResult.wrong);
  });

  test('setPin stores a PBKDF2 hash, never the PIN, and verifies it', () async {
    final store = InMemoryVaultCredentialStore();
    final auth = VaultAuth(store, kdf: _fastKdf);
    await auth.setPin('2468');
    expect(store.kdf, VaultAuth.kdfName);
    expect(store.iterations, VaultAuth.defaultIterations);
    expect(store.hash, isNot(contains('2468')));
    expect((await auth.verify('2468')).result, PinResult.ok);
    expect((await auth.verify('0000')).result, PinResult.wrong);
  });

  test('the real default derivation round-trips', () async {
    final auth = VaultAuth(InMemoryVaultCredentialStore());
    await auth.setPin('1357');
    expect((await auth.verify('1357')).result, PinResult.ok);
  });

  test('same PIN, different salts, different hashes', () async {
    final s1 = InMemoryVaultCredentialStore();
    final s2 = InMemoryVaultCredentialStore();
    await VaultAuth(s1, kdf: _fastKdf).setPin('1234');
    await VaultAuth(s2, kdf: _fastKdf).setPin('1234');
    expect(s1.hash, isNot(s2.hash));
  });

  // Users who set a PIN before this version must not be locked out — and
  // must end up on the stronger scheme without doing anything.
  test('a legacy salted-SHA-256 PIN still opens, and is upgraded', () async {
    final store = InMemoryVaultCredentialStore();
    await store.save(VaultAuth.legacyHash('4321', 'oldsalt'), 'oldsalt');
    final auth = VaultAuth(store, kdf: _fastKdf);

    expect((await auth.verify('4321')).result, PinResult.ok);
    expect(store.kdf, VaultAuth.kdfName);
    expect((await auth.verify('4321')).result, PinResult.ok,
        reason: 'and opens with the new hash too');
  });

  test('a wrong legacy PIN does not trigger the upgrade', () async {
    final store = InMemoryVaultCredentialStore();
    await store.save(VaultAuth.legacyHash('4321', 'oldsalt'), 'oldsalt');
    await VaultAuth(store, kdf: _fastKdf).verify('0000');
    expect(store.kdf, isNull);
  });

  // A crash between the upgrade's writes: the PBKDF2 hash landed, the scheme
  // marker did not. The owner must still get in (and the record be repaired).
  test('a half-written upgrade still opens and is repaired', () async {
    final store = InMemoryVaultCredentialStore();
    await store.save(await _fastKdf('4321', 'salt0', 0), 'salt0'); // kdf missing
    final auth = VaultAuth(store, kdf: _fastKdf);
    expect((await auth.verify('4321')).result, PinResult.ok);
    expect(store.kdf, VaultAuth.kdfName);
    expect(store.salt, 'salt0', reason: 'the upgrade keeps the salt');
    expect(store.failedAttempts, 0);
  });

  test('the upgrade reuses the salt, so any partial write stays checkable',
      () async {
    final store = InMemoryVaultCredentialStore();
    await store.save(VaultAuth.legacyHash('4321', 'oldsalt'), 'oldsalt');
    await VaultAuth(store, kdf: _fastKdf).verify('4321');
    expect(store.salt, 'oldsalt');
  });

  group('lockout', () {
    test('lockFor: free for 4 misses, then 30 s doubling, capped at 1 h', () {
      expect(lockFor(4), Duration.zero);
      expect(lockFor(5), const Duration(seconds: 30));
      expect(lockFor(6), const Duration(seconds: 60));
      expect(lockFor(7), const Duration(seconds: 120));
      expect(lockFor(20), const Duration(hours: 1));
      // pow() would overflow to a negative (= no lock) from here on.
      expect(lockFor(64), const Duration(hours: 1));
      expect(lockFor(1000), const Duration(hours: 1));
    });

    test('the fifth miss locks; while locked even the right PIN is refused',
        () async {
      final clock = _Clock();
      final auth = VaultAuth(InMemoryVaultCredentialStore(),
          kdf: _fastKdf, now: clock.call);
      await auth.setPin('1111');
      for (var i = 0; i < 4; i++) {
        expect((await auth.verify('0000')).result, PinResult.wrong);
      }
      final fifth = await auth.verify('0000');
      expect(fifth.result, PinResult.locked);
      expect(fifth.retryIn, const Duration(seconds: 30));
      expect((await auth.verify('1111')).result, PinResult.locked);

      clock.t = clock.t.add(const Duration(seconds: 31));
      expect((await auth.verify('1111')).result, PinResult.ok);
      expect(auth.lockRemaining(), isNull);
    });

    test('the lock survives a restart (it lives in the store)', () async {
      final clock = _Clock();
      final store = InMemoryVaultCredentialStore();
      final first = VaultAuth(store, kdf: _fastKdf, now: clock.call);
      await first.setPin('1111');
      for (var i = 0; i < 5; i++) {
        await first.verify('0000');
      }
      final restarted = VaultAuth(store, kdf: _fastKdf, now: clock.call);
      expect(restarted.lockRemaining(), isNotNull);
    });

    test('a clock moved back cannot stretch the lock past what was earned',
        () async {
      final clock = _Clock();
      final store = InMemoryVaultCredentialStore();
      final auth = VaultAuth(store, kdf: _fastKdf, now: clock.call);
      await auth.setPin('1111');
      for (var i = 0; i < 5; i++) {
        await auth.verify('0000');
      }
      clock.t = clock.t.subtract(const Duration(days: 3));
      expect(auth.lockRemaining(), const Duration(seconds: 30));
    });

    test('a fingerprint unlock ends the miss streak', () async {
      final store = InMemoryVaultCredentialStore();
      final auth = VaultAuth(store, kdf: _fastKdf);
      await auth.setPin('1111');
      for (var i = 0; i < 3; i++) {
        await auth.verify('0000');
      }
      await auth.recordSuccess();
      expect(store.failedAttempts, 0);
    });
  });

  test('clear removes credentials and the lock state', () async {
    final store = InMemoryVaultCredentialStore();
    final auth = VaultAuth(store, kdf: _fastKdf);
    await auth.setPin('1234');
    await auth.verify('0000');
    await auth.clear();
    expect(auth.isConfigured, false);
    expect(store.hash, isNull);
    expect(store.failedAttempts, 0);
  });
}
