import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('gestureMapShown defaults to false', () {
    expect(KivoSettings.defaults().gestureMapShown, false);
  });

  test('gestureMapShown round-trips through toMap/fromMap', () {
    final s = KivoSettings.defaults().copyWith(gestureMapShown: true);
    expect(KivoSettings.fromMap(s.toMap()).gestureMapShown, true);
  });

  test('fromMap defaults the flag to false when absent (older persisted map)', () {
    // An install that predates the tutorial gets to see it once.
    final map = KivoSettings.defaults().toMap()..remove('gestureMapShown');
    expect(KivoSettings.fromMap(map).gestureMapShown, false);
  });
}
