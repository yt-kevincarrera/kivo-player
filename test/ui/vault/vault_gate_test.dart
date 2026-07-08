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

Future<ProviderContainer> _container({
  required bool biometricEnabled,
  required FakeBiometricAuth bio,
  bool pinConfigured = true,
}) async {
  final creds = InMemoryVaultCredentialStore();
  if (pinConfigured) await VaultAuth(creds).setPin('1234');
  final store = InMemorySettingsStore();
  final svc = await SettingsService.load(store);
  await svc.update(svc.current.copyWith(vaultBiometricEnabled: biometricEnabled));
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    vaultCredentialStoreProvider.overrideWithValue(creds),
    biometricAuthProvider.overrideWithValue(bio),
  ]);
}

Widget _app(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: KivoTheme.dark(),
        home: const VaultGate(child: Text('VAULT-CONTENT')),
      ),
    );

void main() {
  testWidgets('biometric success unlocks and shows the child', (tester) async {
    final bio = FakeBiometricAuth(available: true, willSucceed: true);
    final c = await _container(biometricEnabled: true, bio: bio);
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    expect(bio.authCalls, 1);
    expect(find.text('VAULT-CONTENT'), findsOneWidget);
    expect(c.read(vaultUnlockedProvider), true);
  });

  testWidgets('biometric failure falls back to the PIN pad', (tester) async {
    final bio = FakeBiometricAuth(available: true, willSucceed: false);
    final c = await _container(biometricEnabled: true, bio: bio);
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    expect(find.text('VAULT-CONTENT'), findsNothing);
    expect(find.byKey(const Key('pin-key-1')), findsOneWidget);
  });

  testWidgets('correct PIN unlocks; wrong PIN stays locked', (tester) async {
    final bio = FakeBiometricAuth(available: false);
    final c = await _container(biometricEnabled: false, bio: bio);
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();

    // wrong
    for (final d in ['9','9','9','9']) {
      await tester.tap(find.byKey(Key('pin-key-$d')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('VAULT-CONTENT'), findsNothing);

    // right
    for (final d in ['1','2','3','4']) {
      await tester.tap(find.byKey(Key('pin-key-$d')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('VAULT-CONTENT'), findsOneWidget);
  });
}
