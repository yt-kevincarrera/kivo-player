import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('the new subtitle style fields have the documented defaults', () {
    final d = KivoSettings.defaults();
    expect(d.subtitleOutlineWidth, 2.0);
    expect(d.subtitleOutlineColor, 0xFF000000);
    expect(d.subtitleShadow, true);
    expect(d.subtitleBold, false);
    expect(d.subtitleFontFamily, 'default');
    expect(d.subtitleBottomMargin, 6.0);
    expect(d.secondarySubtitleTopMargin, 6.0);
    expect(d.subtitleRespectAss, true);
    expect(d.secondarySubtitleLanguage, isNull);
  });

  test('they round-trip, and whole doubles survive JSON as ints', () {
    final changed = KivoSettings.defaults().copyWith(
      subtitleOutlineWidth: 3.5,
      subtitleOutlineColor: 0xFF123456,
      subtitleShadow: false,
      subtitleBold: true,
      subtitleFontFamily: 'serif',
      subtitleBottomMargin: 12,
      secondarySubtitleTopMargin: 20,
      subtitleRespectAss: false,
      secondarySubtitleLanguage: 'en',
    );
    final map = changed.toMap()..['subtitleBottomMargin'] = 12;
    final back = KivoSettings.fromMap(map);
    expect(back.subtitleOutlineWidth, 3.5);
    expect(back.subtitleOutlineColor, 0xFF123456);
    expect(back.subtitleShadow, false);
    expect(back.subtitleBold, true);
    expect(back.subtitleFontFamily, 'serif');
    expect(back.subtitleBottomMargin, 12.0);
    expect(back.secondarySubtitleTopMargin, 20.0);
    expect(back.subtitleRespectAss, false);
    expect(back.secondarySubtitleLanguage, 'en');
  });

  test('the secondary language can be cleared back to off', () {
    final s = KivoSettings.defaults().copyWith(secondarySubtitleLanguage: 'en');
    expect(s.copyWith(secondarySubtitleLanguage: null).secondarySubtitleLanguage,
        isNull);
  });

  test('a map from before these fields existed keeps working', () {
    final old = KivoSettings.defaults().toMap()
      ..remove('subtitleOutlineWidth')
      ..remove('subtitleRespectAss')
      ..remove('secondarySubtitleLanguage');
    final back = KivoSettings.fromMap(old);
    expect(back.subtitleOutlineWidth, 2.0);
    expect(back.subtitleRespectAss, true);
  });
}
