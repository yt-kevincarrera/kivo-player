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
      final resolved = resolvePlaylist(p, [_v('7', 'nuevo.mkv')]);
      expect(resolved.single.available, true);
      expect(resolved.single.video!.name, 'nuevo.mkv');
    });

    test('falls back to the display name when the id is gone', () {
      final p = _list([const PlaylistEntry(mediaId: '7', displayName: 'ep1.mkv')]);
      // The file was moved: MediaStore gave it a new row, so a new id.
      final resolved = resolvePlaylist(p, [_v('99', 'ep1.mkv')]);
      expect(resolved.single.available, true);
      expect(resolved.single.video!.id, '99');
    });

    test('an entry matching neither stays unresolved', () {
      final p = _list([const PlaylistEntry(mediaId: '7', displayName: 'ep1.mkv')]);
      final resolved = resolvePlaylist(p, [_v('99', 'otro.mkv')]);
      expect(resolved.single.available, false);
      expect(resolved.single.video, isNull);
    });

    test('keeps the playlist order, not the index order', () {
      final p = _list([
        const PlaylistEntry(mediaId: '3', displayName: 'c.mkv'),
        const PlaylistEntry(mediaId: '1', displayName: 'a.mkv'),
      ]);
      final resolved = resolvePlaylist(p, [_v('1', 'a.mkv'), _v('3', 'c.mkv')]);
      expect(resolved.map((r) => r.video!.id).toList(), ['3', '1']);
    });

    test('the same video twice is two entries, not one', () {
      final p = _list([
        const PlaylistEntry(mediaId: '1', displayName: 'a.mkv'),
        const PlaylistEntry(mediaId: '1', displayName: 'a.mkv'),
      ]);
      expect(resolvePlaylist(p, [_v('1', 'a.mkv')]).length, 2);
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
}
