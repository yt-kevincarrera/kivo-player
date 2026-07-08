import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/vault/vault_auth.dart';

void main() {
  test('unconfigured store means not configured', () {
    final auth = VaultAuth(InMemoryVaultCredentialStore());
    expect(auth.isConfigured, false);
    expect(auth.verify('1234'), false);
  });

  test('setPin then verify: correct pin passes, wrong fails', () async {
    final auth = VaultAuth(InMemoryVaultCredentialStore());
    await auth.setPin('2468');
    expect(auth.isConfigured, true);
    expect(auth.verify('2468'), true);
    expect(auth.verify('0000'), false);
  });

  test('hashPin is deterministic for same salt, differs across salts', () {
    final a = VaultAuth.hashPin('1234', 'saltA');
    final b = VaultAuth.hashPin('1234', 'saltA');
    final c = VaultAuth.hashPin('1234', 'saltB');
    expect(a, b);
    expect(a, isNot(c));
  });

  test('two setPin calls with the same pin produce different stored hashes (random salt)', () async {
    final s1 = InMemoryVaultCredentialStore();
    final s2 = InMemoryVaultCredentialStore();
    await VaultAuth(s1).setPin('1234');
    await VaultAuth(s2).setPin('1234');
    expect(s1.hash, isNot(s2.hash));
    // but each still verifies its own pin
    expect(VaultAuth(s1).verify('1234'), true);
    expect(VaultAuth(s2).verify('1234'), true);
  });

  test('clear removes credentials', () async {
    final store = InMemoryVaultCredentialStore();
    final auth = VaultAuth(store);
    await auth.setPin('1234');
    await auth.clear();
    expect(auth.isConfigured, false);
    expect(store.hash, isNull);
  });
}
