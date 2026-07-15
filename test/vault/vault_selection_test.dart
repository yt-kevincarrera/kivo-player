import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/vault/vault_selection.dart';
import 'package:kivo_player/platform/vault_ops_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/vault/vault_providers.dart';
import 'package:kivo_player/vault/vault_store.dart';
import 'package:kivo_player/vault/vault_entry.dart';
import '../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

void main() {
  test('toggle adds then removes; active tracks non-empty', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(vaultSelectionProvider.notifier);
    expect(n.active, false);
    n.toggle('/vault/a.mp4');
    expect(c.read(vaultSelectionProvider), {'/vault/a.mp4'});
    expect(n.active, true);
    n.toggle('/vault/a.mp4');
    expect(n.active, false);
  });

  test('clear empties the selection', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(vaultSelectionProvider.notifier);
    n.selectAll(['/vault/a.mp4', '/vault/b.mp4']);
    expect(c.read(vaultSelectionProvider).length, 2);
    n.clear();
    expect(c.read(vaultSelectionProvider), isEmpty);
  });

  test('vaultEntriesProvider.hide persists and exposes entries', () async {
    final c = ProviderContainer(overrides: [
      vaultOpsProvider.overrideWithValue(FakeVaultOps()),
      vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(const [])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
    ]);
    addTearDown(c.dispose);

    await c.read(vaultEntriesProvider.future);
    await c.read(vaultEntriesProvider.notifier).hide([
      const VideoItem(id: '9', uri: 'content://9', name: '9.mp4', folder: 'F',
          durationMs: 1, sizeBytes: 1, dateAddedMs: 1),
    ]);
    final entries = c.read(vaultEntriesProvider).valueOrNull ?? const <VaultEntry>[];
    expect(entries.single.id, '9');
  });
}
