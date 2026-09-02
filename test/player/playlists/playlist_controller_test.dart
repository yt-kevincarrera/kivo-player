import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/playlists/playlist.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';

VideoItem _v(String id, String name) => VideoItem(
      id: id,
      uri: 'content://$id',
      name: name,
      folder: 'Series',
      durationMs: 1000,
      sizeBytes: 10,
      dateAddedMs: 0,
    );

ProviderContainer _c(PlaylistStore store, {DateTime Function()? clock}) {
  var tick = 0;
  return ProviderContainer(overrides: [
    playlistStoreProvider.overrideWithValue(store),
    playlistClockProvider.overrideWithValue(
        clock ?? () => DateTime.fromMillisecondsSinceEpoch(1000 + tick++)),
  ]);
}

void main() {
  test('creating a playlist persists it and returns it', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);

    final made = await c.read(playlistsProvider.notifier).create('Serie');

    expect(made.name, 'Serie');
    expect(made.entries, isEmpty);
    expect(store.all().single.id, made.id);
    expect(c.read(playlistsProvider).single.name, 'Serie');
  });

  test('the id comes from the clock, so it is deterministic in tests', () async {
    final c = _c(InMemoryPlaylistStore(),
        clock: () => DateTime.fromMillisecondsSinceEpoch(4242));
    addTearDown(c.dispose);

    final made = await c.read(playlistsProvider.notifier).create('Serie');
    expect(made.id, '4242');
    expect(made.createdAtMs, 4242);
  });

  test('adding videos appends them in the order given', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');

    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);

    expect(store.all().single.entries.map((e) => e.displayName),
        ['a.mkv', 'b.mkv']);
  });

  test('adding the same video again appends a second entry', () async {
    // Duplicates are legal: the same clip twice in one list is a real want.
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');

    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    expect(store.all().single.entries.length, 2);
  });

  test('reorder moves an entry and keeps the rest in order', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(
        p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv'), _v('3', 'c.mkv')]);

    await c.read(playlistsProvider.notifier).reorder(p.id, 2, 0);

    expect(store.all().single.entries.map((e) => e.displayName),
        ['c.mkv', 'a.mkv', 'b.mkv']);
  });

  test('removing an entry takes out that position only', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);

    await c.read(playlistsProvider.notifier).removeEntryAt(p.id, 0);

    expect(store.all().single.entries.single.displayName, 'b.mkv');
  });

  test('insertEntryAt puts the entry back at exactly that position', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(
        p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv'), _v('3', 'c.mkv')]);
    final removed = store.all().single.entries[1]; // b.mkv

    await c.read(playlistsProvider.notifier).removeEntryAt(p.id, 1);
    await c.read(playlistsProvider.notifier).insertEntryAt(p.id, 1, removed);

    expect(store.all().single.entries.map((e) => e.displayName),
        ['a.mkv', 'b.mkv', 'c.mkv']);
  });

  test('insertEntryAt clamps an out-of-range index instead of throwing',
      () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);
    const entry = PlaylistEntry(mediaId: '2', displayName: 'b.mkv');

    await c.read(playlistsProvider.notifier).insertEntryAt(p.id, 99, entry);

    expect(store.all().single.entries.map((e) => e.displayName),
        ['a.mkv', 'b.mkv']);
  });

  test('insertEntryAt with a negative index clamps to the front', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);
    const entry = PlaylistEntry(mediaId: '2', displayName: 'b.mkv');

    await c.read(playlistsProvider.notifier).insertEntryAt(p.id, -5, entry);

    expect(store.all().single.entries.map((e) => e.displayName),
        ['b.mkv', 'a.mkv']);
  });

  test('undo round-trip restores original order even with duplicate videos',
      () async {
    // Spec §1 makes duplicates legal, and removeEntryAt is position-based —
    // undo must be too, or removing the SECOND occurrence of a repeated
    // video could restore it into the FIRST occurrence's slot instead.
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(
        p.id, [_v('1', 'a.mkv'), _v('1', 'a.mkv'), _v('1', 'a.mkv')]);
    final second = store.all().single.entries[1];

    await c.read(playlistsProvider.notifier).removeEntryAt(p.id, 1);
    await c.read(playlistsProvider.notifier).insertEntryAt(p.id, 1, second);

    expect(store.all().single.entries.length, 3);
    expect(store.all().single.entries.map((e) => e.mediaId), ['1', '1', '1']);
  });

  test('renaming a playlist keeps its entries and its id', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    await c.read(playlistsProvider.notifier).rename(p.id, 'Otra');

    expect(store.all().single.id, p.id);
    expect(store.all().single.name, 'Otra');
    expect(store.all().single.entries.length, 1);
  });

  test('deleting a playlist removes it everywhere', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');

    await c.read(playlistsProvider.notifier).delete(p.id);

    expect(store.all(), isEmpty);
    expect(c.read(playlistsProvider), isEmpty);
  });

  test('a video rename updates the stored name in every playlist', () async {
    // The media id survives a rename on its own; the name is the fallback that
    // covers a move, and a stale one would quietly disable it.
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final a = await c.read(playlistsProvider.notifier).create('A');
    final b = await c.read(playlistsProvider.notifier).create('B');
    await c.read(playlistsProvider.notifier).addVideos(a.id, [_v('1', 'viejo.mkv')]);
    await c.read(playlistsProvider.notifier).addVideos(b.id, [_v('1', 'viejo.mkv')]);

    await c.read(playlistsProvider.notifier).renameEntry('1', 'viejo.mkv', 'nuevo.mkv');

    for (final p in store.all()) {
      expect(p.entries.single.displayName, 'nuevo.mkv');
      expect(p.entries.single.mediaId, '1');
    }
  });

  test('renaming one video leaves another with the same name alone', () async {
    // Two files in different folders can share a name. Matching on the name
    // would rewrite the other one's entry too, leaving it labelled with a
    // name it does not have and its move fallback pointing at the wrong video.
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('A');
    await c.read(playlistsProvider.notifier).addVideos(
        p.id, [_v('1', 'S01E01.mkv'), _v('2', 'S01E01.mkv')]);

    await c.read(playlistsProvider.notifier)
        .renameEntry('1', 'S01E01.mkv', 'Piloto.mkv');

    final entries = store.all().single.entries;
    expect(entries[0].displayName, 'Piloto.mkv');
    expect(entries[1].displayName, 'S01E01.mkv');
  });

  test('acting on an unknown playlist id does nothing', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);

    await c.read(playlistsProvider.notifier).addVideos('nope', [_v('1', 'a.mkv')]);
    await c.read(playlistsProvider.notifier).rename('nope', 'x');
    await c.read(playlistsProvider.notifier).removeEntryAt('nope', 0);
    await c.read(playlistsProvider.notifier).reorder('nope', 0, 1);
    await c.read(playlistsProvider.notifier).insertEntryAt(
        'nope', 0, const PlaylistEntry(mediaId: '1', displayName: 'a.mkv'));

    expect(store.all(), isEmpty);
  });

  test('a reorder shows in state before the write lands', () async {
    // ReorderableListView drops the row into its new slot and expects the
    // very next build to agree. If state only changed after the store write,
    // one frame rendered the OLD order and the rows visibly jumped back
    // before settling. So the update is synchronous; the write follows.
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('A');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv'), _v('3', 'c.mkv')]);

    final pending = c.read(playlistsProvider.notifier).reorder(p.id, 0, 2);
    // Deliberately not awaited yet.
    expect(
      c.read(playlistsProvider).single.entries.map((e) => e.displayName),
      ['b.mkv', 'c.mkv', 'a.mkv'],
    );
    await pending;
    expect(
      store.all().single.entries.map((e) => e.displayName),
      ['b.mkv', 'c.mkv', 'a.mkv'],
    );
  });
}
