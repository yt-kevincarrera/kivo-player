import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('update flags defaults', () {
    final d = KivoSettings.defaults();
    expect(d.autoCheckUpdates, true);
    expect(d.lastUpdateCheckMs, 0);
    expect(d.skippedUpdateVersion, null);
  });

  test('round-trips through toMap/fromMap + copyWith', () {
    final s = KivoSettings.defaults().copyWith(
      autoCheckUpdates: false,
      lastUpdateCheckMs: 123,
      skippedUpdateVersion: '1.2.3',
    );
    final back = KivoSettings.fromMap(s.toMap());
    expect(back.autoCheckUpdates, false);
    expect(back.lastUpdateCheckMs, 123);
    expect(back.skippedUpdateVersion, '1.2.3');
  });

  test('skippedUpdateVersion can be reset to null via copyWith', () {
    final s = KivoSettings.defaults().copyWith(skippedUpdateVersion: '1.2.3');
    final cleared = s.copyWith(skippedUpdateVersion: null);
    expect(cleared.skippedUpdateVersion, null);
  });

  test('legacy map (no update keys) yields defaults', () {
    final legacy = KivoSettings.defaults().toMap()
      ..remove('autoCheckUpdates')
      ..remove('lastUpdateCheckMs')
      ..remove('skippedUpdateVersion');
    final back = KivoSettings.fromMap(legacy);
    expect(back.autoCheckUpdates, true);
    expect(back.lastUpdateCheckMs, 0);
    expect(back.skippedUpdateVersion, null);
  });
}
