import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/vault_ops_provider.dart';
import 'package:kivo_player/vault/vault_providers.dart';
import 'package:kivo_player/vault/vault_store.dart';
import 'package:kivo_player/vault/vault_selection.dart';
import 'package:kivo_player/ui/vault/widgets/vault_bottom_bar.dart';
import '../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override Future<MediaAccess> status() async => MediaAccess.granted;
  @override Future<MediaAccess> request() async => MediaAccess.granted;
}

void main() {
  testWidgets('Sacar del Vault calls unhide for the selected entries', (tester) async {
    final ops = FakeVaultOps();
    final c = ProviderContainer(overrides: [
      vaultOpsProvider.overrideWithValue(ops),
      vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(const [])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
    ]);
    addTearDown(c.dispose);
    await c.read(vaultEntriesProvider.future);
    await c.read(vaultEntriesProvider.notifier).hide([
      const VideoItem(id: '1', uri: 'content://1', name: '1.mp4', folder: 'F', durationMs: 1, sizeBytes: 1, dateAddedMs: 1),
    ]);
    // hide() invalidates mediaIndexProvider, which schedules a Riverpod
    // refresh task via a bare Future — under testWidgets' FakeAsync zone
    // that surfaces as a pending Timer until a pump drains it. Drain here,
    // before pumpWidget, so teardown's !timersPending check doesn't trip.
    await tester.pump(Duration.zero);
    c.read(vaultSelectionProvider.notifier).selectAll(['/vault/1.mp4']);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(bottomNavigationBar: VaultBottomBar())),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.lock_open_outlined));
    await tester.pump();
    expect(ops.unhidden, ['/vault/1.mp4']);
  });

  testWidgets('Borrar del teléfono confirms then calls deleteForever', (tester) async {
    final ops = FakeVaultOps();
    final c = ProviderContainer(overrides: [
      vaultOpsProvider.overrideWithValue(ops),
      vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(const [])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
    ]);
    addTearDown(c.dispose);
    await c.read(vaultEntriesProvider.future);
    await c.read(vaultEntriesProvider.notifier).hide([
      const VideoItem(id: '2', uri: 'content://2', name: '2.mp4', folder: 'F', durationMs: 1, sizeBytes: 1, dateAddedMs: 1),
    ]);
    // See the sibling test above for why this pump is needed: hide()'s
    // ref.invalidate(mediaIndexProvider) schedules a task that must be
    // drained before pumpWidget, or teardown's !timersPending check trips.
    await tester.pump(Duration.zero);
    c.read(vaultSelectionProvider.notifier).selectAll(['/vault/2.mp4']);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(bottomNavigationBar: VaultBottomBar())),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_forever_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar'));
    await tester.pump();
    expect(ops.deleted, ['/vault/2.mp4']);
  });
}
