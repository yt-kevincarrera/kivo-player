import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/player/audio/equalizer.dart';

void main() {
  test('equalizer defaults to flat and disabled', () {
    final d = KivoSettings.defaults();
    expect(d.equalizer.enabled, false);
    expect(d.equalizer.preampDb, 0);
    expect(d.equalizer.gainsDb, List.filled(10, 0.0));
  });

  test('equalizer round-trips through toMap/fromMap', () {
    final changed = KivoSettings.defaults().copyWith(
      equalizer: EqualizerSettings(
        enabled: true,
        preampDb: -2.5,
        gainsDb: equalizerPresetCurves['Voz']!,
      ),
    );
    final back = KivoSettings.fromMap(changed.toMap());
    expect(back.equalizer, changed.equalizer);
  });

  test('a settings map written before equalizer existed keeps working', () {
    final old = KivoSettings.defaults().toMap()..remove('equalizer');
    final back = KivoSettings.fromMap(old);
    expect(back.equalizer, EqualizerSettings.flat());
  });

  test('a settings map with a corrupted equalizer entry falls back to flat', () {
    final map = KivoSettings.defaults().toMap()..['equalizer'] = 'not a map';
    final back = KivoSettings.fromMap(map);
    expect(back.equalizer, EqualizerSettings.flat());
  });
}
