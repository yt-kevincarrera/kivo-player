import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/vault_ops_provider.dart';
import 'package:kivo_player/platform/biometric_auth_provider.dart';
import 'package:kivo_player/vault/vault_providers.dart';
import 'package:kivo_player/vault/vault_auth.dart';
import 'package:kivo_player/vault/vault_store.dart';
import 'package:kivo_player/ui/vault/vault_screen.dart';
import '../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override Future<MediaAccess> status() async => MediaAccess.granted;
  @override Future<MediaAccess> request() async => MediaAccess.granted;
}

void main() {
  testWidgets('toggling "Ocultar entrada" flips the setting', (tester) async {
    final creds = InMemoryVaultCredentialStore();
    await VaultAuth(creds).setPin('1234');
    final svc = await SettingsService.load(InMemorySettingsStore());
    await svc.update(svc.current.copyWith(vaultBiometricEnabled: true));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(const [])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
      vaultOpsProvider.overrideWithValue(FakeVaultOps()),
      vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
      vaultCredentialStoreProvider.overrideWithValue(creds),
      biometricAuthProvider.overrideWithValue(FakeBiometricAuth(available: true, willSucceed: true)),
    ]);
    addTearDown(c.dispose);
    await c.read(vaultEntriesProvider.future);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: KivoTheme.dark(), home: const VaultScreen()),
    ));
    await tester.pumpAndSettle(); // biometric auto-unlock

    expect(c.read(settingsProvider).vaultEntranceHidden, false);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ocultar entrada'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).vaultEntranceHidden, true);
  });
}
