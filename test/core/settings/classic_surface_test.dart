import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  // 1.26.5 stored its opt-in (fastVideoStart) as false for everyone; the
  // fixed surface is the default now, behind a NEW opt-out key.
  test('the fixed surface is the default, also over 1.26.5 settings', () {
    expect(KivoSettings.defaults().classicVideoSurface, false);
    final old = KivoSettings.defaults().toMap()
      ..remove('classicVideoSurface')
      ..['fastVideoStart'] = false;
    expect(KivoSettings.fromMap(old).classicVideoSurface, false);
  });

  test('the escape hatch round-trips', () {
    final s = KivoSettings.defaults().copyWith(classicVideoSurface: true);
    expect(KivoSettings.fromMap(s.toMap()).classicVideoSurface, true);
  });
}
