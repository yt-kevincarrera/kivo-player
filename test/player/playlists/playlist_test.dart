import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/playlists/playlist.dart';

VideoItem _v(String id, String name) => VideoItem(
      id: id,
      uri: 'content://$id',
      name: name,
      folder: 'Series',
      durationMs: 1000,
      sizeBytes: 10,
      dateAddedMs: 0,
    );

Playlist _list(List<PlaylistEntry> entries) =>
    Playlist(id: '1', name: 'Serie', createdAtMs: 0, entries: entries);

void main() {
  group('resolution', () {
    test('matches by media id first', () {
      final p = _list([const PlaylistEntry(mediaId: '7', displayName: 'viejo.mkv')]);
      // The file was renamed: the id still matches, the stored name no longer does.
      final resolved = resolvePlaylist(p, MediaLookup.build([_v('7', 'nuevo.mkv')]));
      expect(resolved.single.available, true);
      expect(resolved.single.video!.name, 'nuevo.mkv');
    });

    test('falls back to the display name when the id is gone', () {
      final p = _list([const PlaylistEntry(mediaId: '7', displayName: 'ep1.mkv')]);
      // The file was moved: MediaStore gave it a new row, so a new id.
      final resolved = resolvePlaylist(p, MediaLookup.build([_v('99', 'ep1.mkv')]));
      expect(resolved.single.available, true);
      expect(resolved.single.video!.id, '99');
    });

    test('an entry matching neither stays unresolved', () {
      final p = _list([const PlaylistEntry(mediaId: '7', displayName: 'ep1.mkv')]);
      final resolved = resolvePlaylist(p, MediaLookup.build([_v('99', 'otro.mkv')]));
      expect(resolved.single.available, false);
      expect(resolved.single.video, isNull);
    });

    test('keeps the playlist order, not the index order', () {
      final p = _list([
        const PlaylistEntry(mediaId: '3', displayName: 'c.mkv'),
        const PlaylistEntry(mediaId: '1', displayName: 'a.mkv'),
      ]);
      final resolved = resolvePlaylist(
          p, MediaLookup.build([_v('1', 'a.mkv'), _v('3', 'c.mkv')]));
      expect(resolved.map((r) => r.video!.id).toList(), ['3', '1']);
    });

    test('the same video twice is two entries, not one', () {
      final p = _list([
        const PlaylistEntry(mediaId: '1', displayName: 'a.mkv'),
        const PlaylistEntry(mediaId: '1', displayName: 'a.mkv'),
      ]);
      expect(
          resolvePlaylist(p, MediaLookup.build([_v('1', 'a.mkv')])).length, 2);
    });
  });

  group('where playback starts', () {
    ResolvedEntry avail(String id, String name) =>
        ResolvedEntry(PlaylistEntry(mediaId: id, displayName: name), _v(id, name));
    ResolvedEntry missing(String name) =>
        ResolvedEntry(PlaylistEntry(mediaId: 'x', displayName: name), null);

    test('is the first entry that has not been played', () {
      final entries = [avail('1', 'a.mkv'), avail('2', 'b.mkv'), avail('3', 'c.mkv')];
      expect(playlistStartIndex(entries, {'a.mkv'}), 1);
      expect(playlistStartIndex(entries, {'a.mkv', 'b.mkv'}), 2);
    });

    test('is the top when nothing has been played', () {
      final entries = [avail('1', 'a.mkv'), avail('2', 'b.mkv')];
      expect(playlistStartIndex(entries, const {}), 0);
    });

    // Otherwise finishing a series would leave it unplayable without scrolling.
    test('is the top again once everything has been played', () {
      final entries = [avail('1', 'a.mkv'), avail('2', 'b.mkv')];
      expect(playlistStartIndex(entries, {'a.mkv', 'b.mkv'}), 0);
    });

    test('skips entries that are not available', () {
      final entries = [missing('a.mkv'), avail('2', 'b.mkv')];
      expect(playlistStartIndex(entries, const {}), 1);
    });

    test('is -1 when there is nothing playable at all', () {
      expect(playlistStartIndex([missing('a.mkv')], const {}), -1);
      expect(playlistStartIndex(const [], const {}), -1);
    });
  });

  group('the shape that reaches Hive', () {
    test('a playlist survives the round trip, duplicates and all', () {
      const p = Playlist(
        id: '1000',
        name: 'Serie',
        createdAtMs: 1000,
        entries: [
          PlaylistEntry(mediaId: '7', displayName: 'ep1.mkv'),
          PlaylistEntry(mediaId: '7', displayName: 'ep1.mkv'),
          PlaylistEntry(mediaId: '8', displayName: 'ep2.mkv'),
        ],
      );
      final back = Playlist.fromMap(p.toMap());
      expect(back.id, p.id);
      expect(back.name, p.name);
      expect(back.createdAtMs, p.createdAtMs);
      expect(back.entries, p.entries);
    });

    test('a map typed the way Hive hands it back still reads', () {
      // Hive returns Map<dynamic, dynamic> and List<dynamic>, not the typed
      // maps toMap built — reading has to survive that.
      final Map<dynamic, dynamic> raw = {
        'id': '1',
        'name': 'Serie',
        'created': 1000,
        'entries': <dynamic>[
          <dynamic, dynamic>{'i': '7', 'n': 'ep1.mkv'},
        ],
      };
      final p = Playlist.fromMap(raw);
      expect(p.entries.single, const PlaylistEntry(mediaId: '7', displayName: 'ep1.mkv'));
    });

    test('a stored playlist from a future version does not throw', () {
      // Unknown keys are ignored and missing ones fall back, so a box written
      // by a newer build still opens instead of taking the library with it.
      final p = Playlist.fromMap(const {'id': '1', 'nuevo': 'algo'});
      expect(p.name, '');
      expect(p.createdAtMs, 0);
      expect(p.entries, isEmpty);
    });

    test('created reads as a num, so an int or a double both work', () {
      expect(Playlist.fromMap(const {'created': 1000.0}).createdAtMs, 1000);
      expect(Playlist.fromMap(const {'created': 1000}).createdAtMs, 1000);
    });
  });

  // Value equality (not identity) is what makes `playlistsProvider.select`
  // safe in playlist_playback.dart: HivePlaylistStore.all() deserializes a
  // fresh Playlist for every row on every read, touched or not, so identity
  // would make `select` see a "new" object every time and never filter out
  // an unrelated playlist's rebuild.
  group('value equality', () {
    test('two playlists with the same content are equal, even as distinct instances', () {
      const a = Playlist(
        id: '1',
        name: 'Serie',
        createdAtMs: 1000,
        entries: [PlaylistEntry(mediaId: '7', displayName: 'ep1.mkv')],
      );
      // Round-tripped through a map, like HivePlaylistStore.all() does on
      // every read — a distinct instance, same content.
      final b = Playlist.fromMap(a.toMap());
      expect(identical(a, b), false);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different name makes playlists unequal', () {
      const a = Playlist(id: '1', name: 'Serie', createdAtMs: 1000, entries: []);
      const b = Playlist(id: '1', name: 'Otra', createdAtMs: 1000, entries: []);
      expect(a == b, false);
    });

    test('a different entry list makes playlists unequal', () {
      const a = Playlist(
        id: '1',
        name: 'Serie',
        createdAtMs: 1000,
        entries: [PlaylistEntry(mediaId: '7', displayName: 'ep1.mkv')],
      );
      const b = Playlist(id: '1', name: 'Serie', createdAtMs: 1000, entries: []);
      expect(a == b, false);
    });

    test('entry order matters', () {
      const a = Playlist(
        id: '1',
        name: 'Serie',
        createdAtMs: 1000,
        entries: [
          PlaylistEntry(mediaId: '7', displayName: 'ep1.mkv'),
          PlaylistEntry(mediaId: '8', displayName: 'ep2.mkv'),
        ],
      );
      const b = Playlist(
        id: '1',
        name: 'Serie',
        createdAtMs: 1000,
        entries: [
          PlaylistEntry(mediaId: '8', displayName: 'ep2.mkv'),
          PlaylistEntry(mediaId: '7', displayName: 'ep1.mkv'),
        ],
      );
      expect(a == b, false);
    });
  });
}
