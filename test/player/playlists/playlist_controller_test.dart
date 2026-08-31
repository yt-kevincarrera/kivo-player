import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
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

    await c.read(playlistsProvider.notifier).renameEntry('viejo.mkv', 'nuevo.mkv');

    for (final p in store.all()) {
      expect(p.entries.single.displayName, 'nuevo.mkv');
      expect(p.entries.single.mediaId, '1');
    }
  });

  test('acting on an unknown playlist id does nothing', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);

    await c.read(playlistsProvider.notifier).addVideos('nope', [_v('1', 'a.mkv')]);
    await c.read(playlistsProvider.notifier).rename('nope', 'x');
    await c.read(playlistsProvider.notifier).removeEntryAt('nope', 0);
    await c.read(playlistsProvider.notifier).reorder('nope', 0, 1);

    expect(store.all(), isEmpty);
  });
}
