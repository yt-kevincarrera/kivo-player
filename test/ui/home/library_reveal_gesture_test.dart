import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/platform/vault_ops_provider.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/vault/vault_providers.dart';
import 'package:kivo_player/vault/vault_auth.dart';
import 'package:kivo_player/vault/vault_store.dart';
import 'package:kivo_player/platform/biometric_auth_provider.dart';
import 'package:kivo_player/ui/home/library_screen.dart';
import '../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override Future<MediaAccess> status() async => MediaAccess.granted;
  @override Future<MediaAccess> request() async => MediaAccess.granted;
}

void main() {
  testWidgets('long-press on the Kivo title opens the Vault gate', (tester) async {
    final creds = InMemoryVaultCredentialStore();
    await VaultAuth(creds).setPin('1234'); // configured -> gate shows PIN pad
    final svc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      mediaFileOpsProvider.overrideWithValue(FakeMediaFileOps()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(const [])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      vaultOpsProvider.overrideWithValue(FakeVaultOps()),
      vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
      vaultCredentialStoreProvider.overrideWithValue(creds),
      biometricAuthProvider.overrideWithValue(FakeBiometricAuth(available: false)),
    ]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: KivoTheme.dark(), home: const LibraryScreen()),
    ));
    await tester.pump();

    await tester.longPress(find.byKey(const ValueKey('title')));
    await tester.pumpAndSettle();

    // The gate's PIN pad is showing (proves VaultScreen was pushed).
    expect(find.byKey(const Key('pin-key-1')), findsOneWidget);
  });
}
