import 'dart:async';

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

Future<void> _pumpGate(WidgetTester tester, ProviderContainer c) => pumpLocalized(
      tester,
      const VaultGate(child: Text('VAULT-CONTENT')),
      theme: KivoTheme.dark(),
      container: c,
    );

void main() {
  testWidgets('biometric success unlocks and shows the child', (tester) async {
    final bio = FakeBiometricAuth(available: true, willSucceed: true);
    final c = await _container(biometricEnabled: true, bio: bio);
    addTearDown(c.dispose);
    await _pumpGate(tester, c);
    await tester.pumpAndSettle();
    expect(bio.authCalls, 1);
    expect(find.text('VAULT-CONTENT'), findsOneWidget);
    expect(c.read(vaultUnlockedProvider), true);
  });

  testWidgets('biometric failure falls back to the PIN pad', (tester) async {
    final bio = FakeBiometricAuth(available: true, willSucceed: false);
    final c = await _container(biometricEnabled: true, bio: bio);
    addTearDown(c.dispose);
    await _pumpGate(tester, c);
    await tester.pumpAndSettle();
    expect(find.text('VAULT-CONTENT'), findsNothing);
    expect(find.byKey(const Key('pin-key-1')), findsOneWidget);
  });

  testWidgets('correct PIN unlocks; wrong PIN stays locked', (tester) async {
    final bio = FakeBiometricAuth(available: false);
    final c = await _container(biometricEnabled: false, bio: bio);
    addTearDown(c.dispose);
    await _pumpGate(tester, c);
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

  testWidgets('PinPad is hidden while biometric is in flight, shown after it resolves negatively', (tester) async {
    final gate = Completer<bool>();
    final bio = FakeBiometricAuth(available: true, gate: gate);
    final c = await _container(biometricEnabled: true, bio: bio);
    addTearDown(c.dispose);
    await _pumpGate(tester, c);
    await tester.pump(); // let postFrame callback run and kick off the biometric attempt
    await tester.pump();

    // Biometric attempt is in flight: PinPad must not be shown yet.
    expect(find.byKey(const Key('pin-key-1')), findsNothing);

    // Resolve negatively (failure/cancel).
    gate.complete(false);
    await tester.pumpAndSettle();

    expect(find.text('VAULT-CONTENT'), findsNothing);
    expect(find.byKey(const Key('pin-key-1')), findsOneWidget);
  });

  testWidgets(
      'cancelling the biometric prompt (resolves false) does not re-prompt on the '
      'next resume and leaves PinPad reachable — KV bug: Cancel used to force '
      'another fingerprint attempt', (tester) async {
    // local_auth reports a user cancel the same way it reports a failed
    // attempt: authenticate() resolves to `false`, no exception. From
    // VaultGate's perspective these are the same outcome, and once resolved
    // (not merely in flight) a later app pause/resume — which is exactly
    // what fires around the OS sheet's own dismissal after Cancel — must
    // not be treated as "come back and try biometric again".
    final bio = FakeBiometricAuth(available: true, willSucceed: false);
    final c = await _container(biometricEnabled: true, bio: bio);
    addTearDown(c.dispose);
    await _pumpGate(tester, c);
    await tester.pumpAndSettle();

    expect(bio.authCalls, 1);
    expect(find.byKey(const Key('pin-key-1')), findsOneWidget);

    // Simulate the pause/resume blip that follows the OS sheet being
    // dismissed (whether via Cancel or the sheet settling after a failed
    // attempt) — this is indistinguishable, at the Flutter lifecycle level,
    // from the app being genuinely backgrounded and brought back.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // No re-prompt, no loop: still exactly one authenticate() call, and the
    // user is left on PinPad — not stuck, not thrown back into the sheet.
    expect(bio.authCalls, 1);
    expect(find.byKey(const Key('pin-key-1')), findsOneWidget);
    expect(find.text('VAULT-CONTENT'), findsNothing);
  });

  testWidgets('backgrounding mid-attempt (genuinely interrupted) then resuming '
      'still re-attempts biometric', (tester) async {
    // Distinguishes the case above from a real interruption: the app was
    // backgrounded WHILE the OS sheet/authenticate() call was still
    // pending (nothing resolved it), so on return it's worth trying again
    // rather than silently downgrading to PIN-only.
    final gate = Completer<bool>();
    final bio = FakeBiometricAuth(available: true, gate: gate);
    final c = await _container(biometricEnabled: true, bio: bio);
    addTearDown(c.dispose);
    await _pumpGate(tester, c);
    await tester.pump();
    await tester.pump();

    expect(bio.authCalls, 1);

    // Backgrounded while the first attempt is still unresolved...
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    // ...and only now does that in-flight attempt resolve negatively (e.g.
    // the OS tore down the sheet because the app lost foreground).
    gate.complete(false);
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(bio.authCalls, 2);
  });

  testWidgets('resume while biometric prompt is still pending does not fire a concurrent authenticate() call', (tester) async {
    final gate = Completer<bool>();
    final bio = FakeBiometricAuth(available: true, gate: gate);
    final c = await _container(biometricEnabled: true, bio: bio);
    addTearDown(c.dispose);
    await _pumpGate(tester, c);
    await tester.pump(); // let postFrame callback run and kick off the biometric attempt
    await tester.pump();

    expect(bio.authCalls, 1);
    expect(find.byKey(const Key('pin-key-1')), findsNothing);

    // Simulate stickyAuth's inactive/paused/resumed dance around the OS
    // biometric sheet WHILE the original authenticate() call is still
    // pending (gate not yet completed).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    // The resume must NOT have started a second, concurrent authenticate().
    expect(bio.authCalls, 1);
    expect(find.byKey(const Key('pin-key-1')), findsNothing);

    // Now resolve the original (still-pending) call and confirm normal
    // resolution proceeds as if nothing else happened.
    gate.complete(true);
    await tester.pumpAndSettle();

    expect(bio.authCalls, 1);
    expect(find.text('VAULT-CONTENT'), findsOneWidget);
    expect(c.read(vaultUnlockedProvider), true);
  });
}
