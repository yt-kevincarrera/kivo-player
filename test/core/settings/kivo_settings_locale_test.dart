import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('locale defaults to system and round-trips through the map', () {
    final d = KivoSettings.defaults();
    expect(d.locale, 'system');
    final en = d.copyWith(locale: 'en');
    expect(en.locale, 'en');
    expect(KivoSettings.fromMap(en.toMap()).locale, 'en');
  });

  test('a map saved before locale existed reads back as system', () {
    final legacyMap = KivoSettings.defaults().toMap()..remove('locale');
    expect(KivoSettings.fromMap(legacyMap).locale, 'system');
  });
}
