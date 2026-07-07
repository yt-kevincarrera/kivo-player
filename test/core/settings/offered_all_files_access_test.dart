import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('offeredAllFilesAccess defaults to false', () {
    expect(KivoSettings.defaults().offeredAllFilesAccess, false);
  });

  test('offeredAllFilesAccess round-trips through toMap/fromMap', () {
    final s = KivoSettings.defaults().copyWith(offeredAllFilesAccess: true);
    final restored = KivoSettings.fromMap(s.toMap());
    expect(restored.offeredAllFilesAccess, true);
  });

  test('fromMap defaults the flag to false when absent (older persisted map)', () {
    final map = KivoSettings.defaults().toMap()..remove('offeredAllFilesAccess');
    expect(KivoSettings.fromMap(map).offeredAllFilesAccess, false);
  });
}
