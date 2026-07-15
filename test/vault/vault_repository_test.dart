import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/vault/vault_store.dart';
import 'package:kivo_player/vault/vault_repository.dart';
import '../fakes/fakes.dart';

VideoItem _v(String id) => VideoItem(
    id: id, uri: 'content://$id', name: '$id.mp4', folder: 'F',
    durationMs: 1, sizeBytes: 1, dateAddedMs: 1);

void main() {
  test('hide moves ops-returned entries into the store and returns them', () async {
    final store = InMemoryVaultStore();
    final ops = FakeVaultOps();
    final repo = VaultRepository(store, ops);

    final added = await repo.hide([_v('1'), _v('2')]);

    expect(added.map((e) => e.id), ['1', '2']);
    expect(repo.entries.length, 2);
    expect(ops.hiddenUris, ['content://1', 'content://2']);
  });

  test('hide only persists entries the native side actually returned (reconcile)', () async {
    final store = InMemoryVaultStore();
    final ops = FakeVaultOps()
      ..hideResult = ((uris) => [
            {
              'id': '1',
              'privatePath': '/vault/1.mp4',
              'displayName': '1.mp4',
              'originalRelativePath': 'Movies/',
            }
          ]); // uri '2' failed natively -> omitted
    final repo = VaultRepository(store, ops);

    final added = await repo.hide([_v('1'), _v('2')]);

    expect(added.map((e) => e.id), ['1']);
    expect(repo.entries.map((e) => e.id), ['1']);
  });

  test('hide dedupes by id (re-hiding same id does not duplicate)', () async {
    final store = InMemoryVaultStore();
    final repo = VaultRepository(store, FakeVaultOps());
    await repo.hide([_v('1')]);
    await repo.hide([_v('1')]);
    expect(repo.entries.length, 1);
  });

  test('unhide removes entries on success, keeps them on failure', () async {
    final store = InMemoryVaultStore();
    final ops = FakeVaultOps();
    final repo = VaultRepository(store, ops);
    final added = await repo.hide([_v('1'), _v('2')]);

    final ok = await repo.unhide([added.first]);
    expect(ok, true);
    expect(repo.entries.map((e) => e.id), ['2']);
    expect(ops.unhidden, ['/vault/1.mp4']);

    ops.unhideResult = false;
    final ok2 = await repo.unhide([added.last]);
    expect(ok2, false);
    expect(repo.entries.map((e) => e.id), ['2']); // unchanged
  });

  test('unhide with a partial-batch failure removes only the succeeded entry', () async {
    final store = InMemoryVaultStore();
    final ops = FakeVaultOps();
    final repo = VaultRepository(store, ops);
    final added = await repo.hide([_v('1'), _v('2')]);

    ops.failPaths = {'/vault/1.mp4'};
    final ok = await repo.unhide(added);

    expect(ok, false);
    expect(repo.entries.map((e) => e.privatePath), ['/vault/1.mp4']);
  });

  test('deleteForever removes entries on success', () async {
    final store = InMemoryVaultStore();
    final ops = FakeVaultOps();
    final repo = VaultRepository(store, ops);
    final added = await repo.hide([_v('1')]);
    final ok = await repo.deleteForever(added);
    expect(ok, true);
    expect(repo.entries, isEmpty);
    expect(ops.deleted, ['/vault/1.mp4']);
  });
}
