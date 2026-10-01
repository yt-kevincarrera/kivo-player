import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/biometric_auth_provider.dart';
import 'package:kivo_player/vault/vault_providers.dart';
import 'package:kivo_player/vault/vault_auth.dart';
import 'package:kivo_player/ui/vault/vault_gate.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

Future<ProviderContainer> _container(InMemoryVaultCredentialStore creds) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    vaultCredentialStoreProvider.overrideWithValue(creds),
    biometricAuthProvider
        .overrideWithValue(FakeBiometricAuth(available: false, willSucceed: false)),
  ]);
}

Future<void> _pump(WidgetTester tester, ProviderContainer c) async {
  await pumpLocalized(tester, const VaultGate(child: Text('VAULT-CONTENT')),
      theme: KivoTheme.dark(), container: c);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(Key('pin-key-$d')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('creating the PIN says plainly that the Vault does not encrypt',
      (tester) async {
    final c = await _container(InMemoryVaultCredentialStore());
    addTearDown(c.dispose);
    await _pump(tester, c);
    expect(find.text(_l10n.vaultHonestNotice), findsOneWidget);
  });

  testWidgets('the notice is not repeated on every unlock', (tester) async {
    final creds = InMemoryVaultCredentialStore();
    await VaultAuth(creds).setPin('1234');
    final c = await _container(creds);
    addTearDown(c.dispose);
    await _pump(tester, c);
    expect(find.byKey(const Key('vault-honest-notice')), findsNothing);
  });

  testWidgets('five misses lock the pad, with a countdown', (tester) async {
    final creds = InMemoryVaultCredentialStore();
    await VaultAuth(creds).setPin('1234');
    final c = await _container(creds);
    addTearDown(c.dispose);
    await _pump(tester, c);

    for (var i = 0; i < 4; i++) {
      await _enter(tester, '0000');
      expect(find.text(_l10n.vaultPinIncorrectError), findsOneWidget);
    }
    await _enter(tester, '0000');
    expect(find.textContaining(_l10n.vaultPinLockedError('').trim()),
        findsOneWidget);

    // Even the right PIN is refused while locked.
    await _enter(tester, '1234');
    expect(find.text('VAULT-CONTENT'), findsNothing);
    expect(creds.failedAttempts, 5);
  });

  testWidgets('a lock from before is shown as soon as the gate opens',
      (tester) async {
    final creds = InMemoryVaultCredentialStore();
    await VaultAuth(creds).setPin('1234');
    await creds.saveAttempts(
        5,
        DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch);
    final c = await _container(creds);
    addTearDown(c.dispose);
    await _pump(tester, c);
    expect(find.textContaining(_l10n.vaultPinLockedError('').trim()),
        findsOneWidget);
  });
}
