import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('both enhancements start off, at medium', () {
    final d = KivoSettings.defaults();
    expect(d.nightMode, false);
    expect(d.nightModeLevel, 'medium');
    expect(d.voiceBoost, false);
    expect(d.voiceBoostLevel, 'medium');
  });

  test('all four round-trip through toMap/fromMap', () {
    final changed = KivoSettings.defaults().copyWith(
      nightMode: true,
      nightModeLevel: 'strong',
      voiceBoost: true,
      voiceBoostLevel: 'soft',
    );
    final back = KivoSettings.fromMap(changed.toMap());
    expect(back.nightMode, true);
    expect(back.nightModeLevel, 'strong');
    expect(back.voiceBoost, true);
    expect(back.voiceBoostLevel, 'soft');
  });

  test('a settings map written before these fields existed keeps working', () {
    final old = KivoSettings.defaults().toMap()
      ..remove('nightMode')
      ..remove('nightModeLevel')
      ..remove('voiceBoost')
      ..remove('voiceBoostLevel');
    final back = KivoSettings.fromMap(old);
    expect(back.nightMode, false);
    expect(back.voiceBoostLevel, 'medium');
  });
}
