import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/vault_ops_provider.dart';
import 'package:kivo_player/ui/vault/vault_entry_actions.dart';
import 'package:kivo_player/vault/vault_providers.dart';
import 'package:kivo_player/vault/vault_store.dart';
import '../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

const _video = VideoItem(
  id: '1',
  uri: 'content://1',
  name: '1.mp4',
  folder: 'F',
  durationMs: 1,
  sizeBytes: 1,
  dateAddedMs: 1,
);

class _MoveButton extends ConsumerWidget {
  const _MoveButton();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => moveToVault(context, ref, const [_video]),
      child: const Text('Move'),
    );
  }
}

Future<ProviderContainer> _container() async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    vaultOpsProvider.overrideWithValue(FakeVaultOps()),
    vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(const [])),
    mediaPermissionImplProvider.overrideWithValue(_Perm()),
  ]);
  await c.read(vaultEntriesProvider.future);
  return c;
}

Widget _app(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: _MoveButton())),
    );

void main() {
  testWidgets('moveToVault hides the videos and shows one SnackBar (no dialog)', (tester) async {
    final c = await _container();
    addTearDown(c.dispose);

    await tester.pumpWidget(_app(c));
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    // hide()'s ref.invalidate(mediaIndexProvider) schedules a task that must be
    // drained, or teardown's !timersPending check trips (established pattern).
    await tester.pump(Duration.zero);

    // No confirmation dialog — files now live in shared storage.
    expect(find.text('Antes de ocultar'), findsNothing);

    final ops = c.read(vaultOpsProvider) as FakeVaultOps;
    expect(ops.hiddenUris, contains('content://1'));
    // Exactly one SnackBar for the batch.
    expect(find.text('1 movidos al Vault'), findsOneWidget);
  });
}
