import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/audio/equalizer.dart';

void main() {
  group('EqualizerSettings', () {
    test('flat() is disabled by default with ten zero gains', () {
      final s = EqualizerSettings.flat();
      expect(s.enabled, false);
      expect(s.preampDb, 0);
      expect(s.gainsDb, List.filled(10, 0.0));
    });

    test('value equality compares enabled, preamp and every gain', () {
      final a = EqualizerSettings.flat().copyWith(enabled: true, preampDb: 2);
      final b = EqualizerSettings.flat().copyWith(enabled: true, preampDb: 2);
      final c = EqualizerSettings.flat().copyWith(enabled: true, preampDb: 3);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('withBand replaces exactly one band and clamps to range', () {
      final s = EqualizerSettings.flat().withBand(2, 5.0).withBand(9, 99.0);
      expect(s.gainsDb[2], 5.0);
      expect(s.gainsDb[9], equalizerMaxDb);
      expect(s.gainsDb.where((g) => g != 0).length, 2);
    });

    test('toMap/fromMap round-trips', () {
      final s = EqualizerSettings(
        enabled: true,
        preampDb: -3.5,
        gainsDb: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((e) => e.toDouble()).toList(),
      );
      final back = EqualizerSettings.fromMap(s.toMap());
      expect(back, s);
    });

    test('fromMap tolerates a missing map entirely', () {
      expect(EqualizerSettings.fromMap(null), EqualizerSettings.flat());
    });

    test('fromMap tolerates unknown extra keys', () {
      final m = EqualizerSettings.flat(enabled: true).toMap()..['mystery'] = 42;
      final back = EqualizerSettings.fromMap(m);
      expect(back.enabled, true);
    });

    test('fromMap falls back to flat gains when the stored list has the wrong length', () {
      final m = {'on': true, 'pre': 4.0, 'g': [1.0, 2.0, 3.0]};
      final back = EqualizerSettings.fromMap(m);
      expect(back.gainsDb, List.filled(10, 0.0));
      // Other fields are unaffected by the bad list.
      expect(back.enabled, true);
      expect(back.preampDb, 4.0);
    });
  });

  group('presetFor', () {
    test('matches EqPreset.flat for an untouched flat curve', () {
      expect(presetFor(EqualizerSettings.flat()), EqPreset.flat);
    });

    test('matches a named preset regardless of enabled/preamp', () {
      final s = EqualizerSettings(
        enabled: false,
        preampDb: 5,
        gainsDb: equalizerPresetCurves['Graves']!,
      );
      expect(presetFor(s), EqPreset.bass);
    });

    test('falls back to EqPreset.custom for a hand-tuned curve', () {
      final s = EqualizerSettings.flat().withBand(0, 1.5);
      expect(presetFor(s), EqPreset.custom);
    });
  });

  group('mpvAudioFilter', () {
    test('a flat, disabled curve clears the filter', () {
      expect(mpvAudioFilter(EqualizerSettings.flat()), '');
    });

    test('a flat, enabled curve with no preamp also clears the filter', () {
      expect(mpvAudioFilter(EqualizerSettings.flat(enabled: true)), '');
    });

    test('disabled always clears the filter even with a hand-tuned curve', () {
      final s = EqualizerSettings.flat().withBand(3, 6.0);
      expect(mpvAudioFilter(s), '');
    });

    test('one nonzero band with no preamp builds all ten stages, no volume stage', () {
      const s = EqualizerSettings(
        enabled: true,
        preampDb: 0,
        gainsDb: [3.0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      );
      expect(
        mpvAudioFilter(s),
        'lavfi=[equalizer=f=31:t=q:w=1:g=3.0,'
        'equalizer=f=62:t=q:w=1:g=0.0,'
        'equalizer=f=125:t=q:w=1:g=0.0,'
        'equalizer=f=250:t=q:w=1:g=0.0,'
        'equalizer=f=500:t=q:w=1:g=0.0,'
        'equalizer=f=1000:t=q:w=1:g=0.0,'
        'equalizer=f=2000:t=q:w=1:g=0.0,'
        'equalizer=f=4000:t=q:w=1:g=0.0,'
        'equalizer=f=8000:t=q:w=1:g=0.0,'
        'equalizer=f=16000:t=q:w=1:g=0.0]',
      );
    });

    test('preamp-only (flat gains, nonzero preamp) appends a volume stage', () {
      final s = EqualizerSettings.flat(enabled: true).copyWith(preampDb: 2.5);
      expect(
        mpvAudioFilter(s),
        'lavfi=[equalizer=f=31:t=q:w=1:g=0.0,'
        'equalizer=f=62:t=q:w=1:g=0.0,'
        'equalizer=f=125:t=q:w=1:g=0.0,'
        'equalizer=f=250:t=q:w=1:g=0.0,'
        'equalizer=f=500:t=q:w=1:g=0.0,'
        'equalizer=f=1000:t=q:w=1:g=0.0,'
        'equalizer=f=2000:t=q:w=1:g=0.0,'
        'equalizer=f=4000:t=q:w=1:g=0.0,'
        'equalizer=f=8000:t=q:w=1:g=0.0,'
        'equalizer=f=16000:t=q:w=1:g=0.0,'
        'volume=2.5dB]',
      );
    });

    test('a negative gain formats with its sign', () {
      final s = EqualizerSettings.flat(enabled: true).withBand(0, -6.5);
      expect(mpvAudioFilter(s), contains('equalizer=f=31:t=q:w=1:g=-6.5'));
    });
  });
}
