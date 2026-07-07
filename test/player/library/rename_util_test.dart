import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/library/rename_util.dart';

void main() {
  test('sanitizeRenameTarget trims and rejects empty / path separators', () {
    expect(sanitizeRenameTarget('  Mi Video  '), 'Mi Video');
    expect(sanitizeRenameTarget(''), isNull);
    expect(sanitizeRenameTarget('   '), isNull);
    expect(sanitizeRenameTarget('a/b'), isNull);
    expect(sanitizeRenameTarget('a\\b'), isNull);
  });

  test('splitNameExt splits at the last dot', () {
    expect(splitNameExt('movie.mp4'), (base: 'movie', ext: '.mp4'));
    expect(splitNameExt('my.home.video.mkv'), (base: 'my.home.video', ext: '.mkv'));
    expect(splitNameExt('noext'), (base: 'noext', ext: ''));
    expect(splitNameExt('.hidden'), (base: '.hidden', ext: ''));
  });
}
