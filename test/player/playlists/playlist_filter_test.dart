import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/playlists/playlist.dart';
import 'package:kivo_player/player/playlists/playlist_filter.dart';

Playlist _p(
  String id,
  String name, {
  int created = 0,
  int lastPlayed = 0,
  List<PlaylistEntry> entries = const [],
}) =>
    Playlist(
      id: id,
      name: name,
      createdAtMs: created,
      entries: entries,
      lastPlayedAtMs: lastPlayed,
    );

void main() {
  group('playlistSortFor', () {
    test('maps every enum name back to itself', () {
      for (final s in PlaylistSort.values) {
        expect(playlistSortFor(s.name), s);
      }
    });

    test('an unrecognized value defaults to recent', () {
      expect(playlistSortFor('nope'), PlaylistSort.recent);
      expect(playlistSortFor(''), PlaylistSort.recent);
    });
  });

  group('query', () {
    test('matches by playlist name, case-insensitively', () {
      final all = [_p('1', 'Serie de Verano'), _p('2', 'Curso de Kotlin')];
      final out =
          applyPlaylistFilters(all, query: 'SERIE', sort: PlaylistSort.recent);
      expect(out.map((p) => p.id), ['1']);
    });

    test('matches an entry display name as a second criterion', () {
      final all = [
        _p('1', 'Serie', entries: const [
          PlaylistEntry(mediaId: '1', displayName: 'Episodio 4.mkv'),
        ]),
        _p('2', 'Curso', entries: const [
          PlaylistEntry(mediaId: '2', displayName: 'Leccion 1.mkv'),
        ]),
      ];
      final out = applyPlaylistFilters(all,
          query: 'episodio 4', sort: PlaylistSort.recent);
      expect(out.map((p) => p.id), ['1']);
    });

    test('an empty (or whitespace-only) query matches everything', () {
      final all = [_p('1', 'Serie'), _p('2', 'Curso')];
      expect(
          applyPlaylistFilters(all, query: '', sort: PlaylistSort.recent)
              .length,
          2);
      expect(
          applyPlaylistFilters(all, query: '   ', sort: PlaylistSort.recent)
              .length,
          2);
    });

    test('no match returns an empty list', () {
      final all = [_p('1', 'Serie')];
      expect(
          applyPlaylistFilters(all, query: 'zzz', sort: PlaylistSort.recent),
          isEmpty);
    });
  });

  group('sort: recent', () {
    test('newest created first', () {
      final all = [_p('1', 'A', created: 1000), _p('2', 'B', created: 2000)];
      final out =
          applyPlaylistFilters(all, query: '', sort: PlaylistSort.recent);
      expect(out.map((p) => p.id), ['2', '1']);
    });

    test('a tie on createdAtMs is broken deterministically by id', () {
      final all = [_p('1', 'A', created: 1000), _p('2', 'B', created: 1000)];
      final out1 =
          applyPlaylistFilters(all, query: '', sort: PlaylistSort.recent);
      final out2 = applyPlaylistFilters(all.reversed.toList(),
          query: '', sort: PlaylistSort.recent);
      expect(out1.map((p) => p.id).toList(), out2.map((p) => p.id).toList());
    });
  });

  group('sort: nameAsc / nameDesc', () {
    test('nameAsc orders A→Z case-insensitively', () {
      final all = [_p('1', 'zulu'), _p('2', 'Alfa')];
      final out =
          applyPlaylistFilters(all, query: '', sort: PlaylistSort.nameAsc);
      expect(out.map((p) => p.id), ['2', '1']);
    });

    test('nameDesc orders Z→A case-insensitively', () {
      final all = [_p('1', 'zulu'), _p('2', 'Alfa')];
      final out =
          applyPlaylistFilters(all, query: '', sort: PlaylistSort.nameDesc);
      expect(out.map((p) => p.id), ['1', '2']);
    });

    test('a name tie falls back to recent, deterministically', () {
      final all = [
        _p('1', 'Serie', created: 1000),
        _p('2', 'Serie', created: 2000),
      ];
      final out =
          applyPlaylistFilters(all, query: '', sort: PlaylistSort.nameAsc);
      // Newer of the two same-named playlists sorts first, same tiebreak
      // `recent` itself uses.
      expect(out.map((p) => p.id), ['2', '1']);
    });
  });

  group('sort: mostVideos', () {
    test('more entries first', () {
      final all = [
        _p('1', 'A', entries: List.filled(2, const PlaylistEntry(mediaId: 'x', displayName: 'x'))),
        _p('2', 'B', entries: List.filled(5, const PlaylistEntry(mediaId: 'x', displayName: 'x'))),
      ];
      final out = applyPlaylistFilters(all,
          query: '', sort: PlaylistSort.mostVideos);
      expect(out.map((p) => p.id), ['2', '1']);
    });

    test('a tie on entry count breaks by recent', () {
      final all = [
        _p('1', 'A', created: 1000, entries: const [
          PlaylistEntry(mediaId: 'x', displayName: 'x'),
        ]),
        _p('2', 'B', created: 2000, entries: const [
          PlaylistEntry(mediaId: 'x', displayName: 'x'),
        ]),
      ];
      final out = applyPlaylistFilters(all,
          query: '', sort: PlaylistSort.mostVideos);
      expect(out.map((p) => p.id), ['2', '1']);
    });
  });

  group('sort: lastPlayed', () {
    test('most recently played first', () {
      final all = [
        _p('1', 'A', lastPlayed: 1000),
        _p('2', 'B', lastPlayed: 3000),
        _p('3', 'C', lastPlayed: 2000),
      ];
      final out = applyPlaylistFilters(all,
          query: '', sort: PlaylistSort.lastPlayed);
      expect(out.map((p) => p.id), ['2', '3', '1']);
    });

    test('never-played (0) playlists sort last, after every played one', () {
      final all = [
        _p('1', 'Never', created: 5000, lastPlayed: 0),
        _p('2', 'Played once', created: 1000, lastPlayed: 1000),
      ];
      final out = applyPlaylistFilters(all,
          query: '', sort: PlaylistSort.lastPlayed);
      expect(out.map((p) => p.id), ['2', '1']);
    });

    test('among never-played playlists, falls back to recent', () {
      final all = [
        _p('1', 'A', created: 1000, lastPlayed: 0),
        _p('2', 'B', created: 2000, lastPlayed: 0),
      ];
      final out = applyPlaylistFilters(all,
          query: '', sort: PlaylistSort.lastPlayed);
      expect(out.map((p) => p.id), ['2', '1']);
    });

    test('a tie on lastPlayedAtMs among played playlists breaks by recent',
        () {
      final all = [
        _p('1', 'A', created: 1000, lastPlayed: 5000),
        _p('2', 'B', created: 2000, lastPlayed: 5000),
      ];
      final out = applyPlaylistFilters(all,
          query: '', sort: PlaylistSort.lastPlayed);
      expect(out.map((p) => p.id), ['2', '1']);
    });
  });

  test('search and sort compose: filters first, then orders what remains',
      () {
    final all = [
      _p('1', 'Serie A', created: 1000),
      _p('2', 'Serie B', created: 2000),
      _p('3', 'Curso', created: 3000),
    ];
    final out = applyPlaylistFilters(all,
        query: 'serie', sort: PlaylistSort.recent);
    expect(out.map((p) => p.id), ['2', '1']);
  });
}
