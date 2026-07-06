import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('pipAutoOnHome defaults true and round-trips through the map', () {
    final d = KivoSettings.defaults();
    expect(d.pipAutoOnHome, true);
    final off = d.copyWith(pipAutoOnHome: false);
    expect(off.pipAutoOnHome, false);
    expect(KivoSettings.fromMap(off.toMap()).pipAutoOnHome, false);
  });

  test('copyWith sets, keeps, and CLEARS preferred languages', () {
    final d = KivoSettings.defaults(); // languages null by default
    final en = d.copyWith(preferredSubtitleLanguage: 'en');
    expect(en.preferredSubtitleLanguage, 'en');
    // omitting the arg keeps the value
    expect(en.copyWith(pipAutoOnHome: false).preferredSubtitleLanguage, 'en');
    // passing null CLEARS it (the sentinel change)
    expect(en.copyWith(preferredSubtitleLanguage: null).preferredSubtitleLanguage, isNull);
    // audio language behaves the same
    final es = d.copyWith(preferredAudioLanguage: 'es');
    expect(es.preferredAudioLanguage, 'es');
    expect(es.copyWith(preferredAudioLanguage: null).preferredAudioLanguage, isNull);
  });
}
