import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/playlists/playlist.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';

Playlist _p(String id, String name, {List<PlaylistEntry> entries = const []}) =>
    Playlist(id: id, name: name, createdAtMs: int.parse(id), entries: entries);

void main() {
  test('round-trips a playlist with its entries in order', () async {
    final s = InMemoryPlaylistStore();
    await s.put(_p('1', 'Serie', entries: const [
      PlaylistEntry(mediaId: '7', displayName: 'ep1.mkv'),
      PlaylistEntry(mediaId: '8', displayName: 'ep2.mkv'),
    ]));

    final read = s.all().single;
    expect(read.name, 'Serie');
    expect(read.entries.map((e) => e.displayName), ['ep1.mkv', 'ep2.mkv']);
  });

  test('put replaces a playlist with the same id rather than duplicating it',
      () async {
    final s = InMemoryPlaylistStore();
    await s.put(_p('1', 'Serie'));
    await s.put(_p('1', 'Serie renombrada'));

    expect(s.all().length, 1);
    expect(s.all().single.name, 'Serie renombrada');
  });

  test('two playlists may share a name — the id is the identity', () async {
    final s = InMemoryPlaylistStore();
    await s.put(_p('1', 'Serie'));
    await s.put(_p('2', 'Serie'));
    expect(s.all().length, 2);
  });

  test('remove takes out only the one asked for', () async {
    final s = InMemoryPlaylistStore();
    await s.put(_p('1', 'A'));
    await s.put(_p('2', 'B'));
    await s.remove('1');
    expect(s.all().single.name, 'B');
  });

  test('removing an id that is not there is a no-op, not a throw', () async {
    final s = InMemoryPlaylistStore();
    await s.remove('nope');
    expect(s.all(), isEmpty);
  });

  test('playlists come back newest first', () async {
    final s = InMemoryPlaylistStore();
    await s.put(_p('1', 'vieja'));
    await s.put(_p('2', 'nueva'));
    expect(s.all().map((p) => p.name), ['nueva', 'vieja']);
  });
}
