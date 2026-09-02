import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('repeatMode and shuffle default to off/false', () {
    final d = KivoSettings.defaults();
    expect(d.repeatMode, 'off');
    expect(d.shuffle, false);
  });

  test('both round-trip through toMap/fromMap', () {
    final changed = KivoSettings.defaults().copyWith(
      repeatMode: 'list',
      shuffle: true,
    );
    final back = KivoSettings.fromMap(changed.toMap());
    expect(back.repeatMode, 'list');
    expect(back.shuffle, true);
  });

  test('repeatMode is persisted by name, not by index', () {
    // A settings map is a plain JSON-ish map — this is what actually gets
    // written to disk. Asserting the value is a string (not 0/1/2) is what
    // pins the "persist by name, never by index" rule.
    final map = KivoSettings.defaults()
        .copyWith(repeatMode: 'video')
        .toMap();
    expect(map['repeatMode'], 'video');
    expect(map['repeatMode'], isA<String>());
  });

  test('a settings map written before this feature existed keeps working', () {
    final old = KivoSettings.defaults().toMap()
      ..remove('repeatMode')
      ..remove('shuffle');
    final back = KivoSettings.fromMap(old);
    expect(back.repeatMode, 'off');
    expect(back.shuffle, false);
  });
}
