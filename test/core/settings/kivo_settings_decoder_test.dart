import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('decoder fields have the documented defaults', () {
    final d = KivoSettings.defaults();
    expect(d.decoderMode, 'auto');
    expect(d.decoderAutoFallback, true);
    expect(d.decoderStallSeconds, 3);
  });

  test('all three round-trip through toMap/fromMap', () {
    final changed = KivoSettings.defaults().copyWith(
      decoderMode: 'sw',
      decoderAutoFallback: false,
      decoderStallSeconds: 7,
    );
    final back = KivoSettings.fromMap(changed.toMap());
    expect(back.decoderMode, 'sw');
    expect(back.decoderAutoFallback, false);
    expect(back.decoderStallSeconds, 7);
  });

  test('a settings map written before these fields existed keeps working', () {
    final old = KivoSettings.defaults().toMap()
      ..remove('decoderMode')
      ..remove('decoderAutoFallback')
      ..remove('decoderStallSeconds');
    final back = KivoSettings.fromMap(old);
    expect(back.decoderMode, 'auto');
    expect(back.decoderAutoFallback, true);
    expect(back.decoderStallSeconds, 3);
  });
}
