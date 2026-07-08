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

Future<ProviderContainer> _container({required bool warningShown}) async {
  final store = InMemorySettingsStore();
  final svc = await SettingsService.load(store);
  await svc.update(svc.current.copyWith(vaultUninstallWarningShown: warningShown));
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
  testWidgets('first call shows the one-time warning, then hides', (tester) async {
    final c = await _container(warningShown: false);
    addTearDown(c.dispose);

    await tester.pumpWidget(_app(c));
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();

    expect(find.text('Antes de ocultar'), findsOneWidget);
    expect(
      find.text(
        'Los videos del Vault viven dentro de Kivo. Si desinstalas la app se '
        'pierden. Sácalos del Vault para devolverlos a tu galería.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    // hide()'s ref.invalidate(mediaIndexProvider) schedules a task that must
    // be drained, or teardown's !timersPending check trips (established
    // pattern; see vault_bottom_bar_test.dart).
    await tester.pump(Duration.zero);

    expect(c.read(settingsProvider).vaultUninstallWarningShown, true);
    final ops = c.read(vaultOpsProvider) as FakeVaultOps;
    expect(ops.hiddenUris, contains('content://1'));
    expect(find.text('1 movidos al Vault'), findsOneWidget);
  });

  testWidgets('second call skips the dialog when the flag is already set', (tester) async {
    final c = await _container(warningShown: true);
    addTearDown(c.dispose);

    await tester.pumpWidget(_app(c));
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    await tester.pump(Duration.zero);

    expect(find.text('Entendido'), findsNothing);
    final ops = c.read(vaultOpsProvider) as FakeVaultOps;
    expect(ops.hiddenUris, contains('content://1'));
    expect(find.text('1 movidos al Vault'), findsOneWidget);
  });
}
