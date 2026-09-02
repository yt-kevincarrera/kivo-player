import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('playlistSort defaults to recent', () {
    final d = KivoSettings.defaults();
    expect(d.playlistSort, 'recent');
  });

  test('round-trips through toMap/fromMap', () {
    final changed =
        KivoSettings.defaults().copyWith(playlistSort: 'lastPlayed');
    final back = KivoSettings.fromMap(changed.toMap());
    expect(back.playlistSort, 'lastPlayed');
  });

  test('is persisted by name, not by index', () {
    final map =
        KivoSettings.defaults().copyWith(playlistSort: 'mostVideos').toMap();
    expect(map['playlistSort'], 'mostVideos');
    expect(map['playlistSort'], isA<String>());
  });

  test('a settings map written before this feature existed keeps working', () {
    final old = KivoSettings.defaults().toMap()..remove('playlistSort');
    final back = KivoSettings.fromMap(old);
    expect(back.playlistSort, 'recent');
  });

  test('copyWith leaves playlistSort alone when not passed', () {
    final s = KivoSettings.defaults().copyWith(playlistSort: 'nameAsc');
    final untouched = s.copyWith(libraryColumns: 2);
    expect(untouched.playlistSort, 'nameAsc');
  });
}
