import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/library/library_filter.dart';

const _beta = VideoItem(id: '1', uri: 'content://1', name: 'Beta.mp4', folder: 'Movies', durationMs: 60000, sizeBytes: 500, dateAddedMs: 100);
const _alpha = VideoItem(id: '2', uri: 'content://2', name: 'Alpha.mp4', folder: 'Trips', durationMs: 120000, sizeBytes: 200, dateAddedMs: 300);
const _gamma = VideoItem(id: '3', uri: 'content://3', name: 'Gamma.mp4', folder: 'Movies', durationMs: 30000, sizeBytes: 900, dateAddedMs: 200);

void main() {
  final videos = [_beta, _alpha, _gamma];

  test('KivoSettings.librarySort defaults to recent and round-trips', () {
    expect(KivoSettings.defaults().librarySort, 'recent');
    final m = KivoSettings.defaults().copyWith(librarySort: 'nameAsc').toMap();
    expect(KivoSettings.fromMap(m).librarySort, 'nameAsc');
  });

  test('librarySortFor maps known strings and falls back to recent', () {
    expect(librarySortFor('nameAsc'), LibrarySort.nameAsc);
    expect(librarySortFor('sizeDesc'), LibrarySort.sizeDesc);
    expect(librarySortFor('not-a-real-value'), LibrarySort.recent);
  });

  group('applyLibraryFilters sort', () {
    test('recent: newest dateAddedMs first', () {
      final out = applyLibraryFilters(videos, sort: LibrarySort.recent);
      expect(out.map((v) => v.name), ['Alpha.mp4', 'Gamma.mp4', 'Beta.mp4']);
    });
    test('nameAsc: alphabetical', () {
      final out = applyLibraryFilters(videos, sort: LibrarySort.nameAsc);
      expect(out.map((v) => v.name), ['Alpha.mp4', 'Beta.mp4', 'Gamma.mp4']);
    });
    test('nameDesc: reverse alphabetical', () {
      final out = applyLibraryFilters(videos, sort: LibrarySort.nameDesc);
      expect(out.map((v) => v.name), ['Gamma.mp4', 'Beta.mp4', 'Alpha.mp4']);
    });
    test('durationAsc: shortest first', () {
      final out = applyLibraryFilters(videos, sort: LibrarySort.durationAsc);
      expect(out.map((v) => v.name), ['Gamma.mp4', 'Beta.mp4', 'Alpha.mp4']);
    });
    test('durationDesc: longest first', () {
      final out = applyLibraryFilters(videos, sort: LibrarySort.durationDesc);
      expect(out.map((v) => v.name), ['Alpha.mp4', 'Beta.mp4', 'Gamma.mp4']);
    });
    test('sizeAsc: lightest first', () {
      final out = applyLibraryFilters(videos, sort: LibrarySort.sizeAsc);
      expect(out.map((v) => v.name), ['Alpha.mp4', 'Beta.mp4', 'Gamma.mp4']);
    });
    test('sizeDesc: heaviest first', () {
      final out = applyLibraryFilters(videos, sort: LibrarySort.sizeDesc);
      expect(out.map((v) => v.name), ['Gamma.mp4', 'Beta.mp4', 'Alpha.mp4']);
    });
  });

  group('applyLibraryFilters query', () {
    test('matches by file name, case-insensitive', () {
      final out = applyLibraryFilters(videos, query: 'ALPHA');
      expect(out.map((v) => v.name), ['Alpha.mp4']);
    });
    test('matches by folder name, case-insensitive', () {
      final out = applyLibraryFilters(videos, query: 'movies');
      expect(out.map((v) => v.name).toSet(), {'Beta.mp4', 'Gamma.mp4'});
    });
    test('no match returns an empty list', () {
      expect(applyLibraryFilters(videos, query: 'zzz'), isEmpty);
    });
  });

  test('applyLibraryFilters unwatchedOnly excludes played keys', () {
    final out = applyLibraryFilters(videos, unwatchedOnly: true, playedKeys: {'Alpha.mp4'});
    expect(out.map((v) => v.name).toSet(), {'Beta.mp4', 'Gamma.mp4'});
  });

  test('applyLibraryFilters composes query + unwatchedOnly + sort', () {
    final out = applyLibraryFilters(
      videos,
      query: 'movies',
      unwatchedOnly: true,
      playedKeys: {'Gamma.mp4'},
      sort: LibrarySort.nameAsc,
    );
    expect(out.map((v) => v.name), ['Beta.mp4']);
  });
}
