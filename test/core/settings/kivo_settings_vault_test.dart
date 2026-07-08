import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('vault flags default to false', () {
    final d = KivoSettings.defaults();
    expect(d.vaultEntranceHidden, false);
    expect(d.vaultBiometricEnabled, false);
    expect(d.vaultUninstallWarningShown, false);
  });

  test('vault flags round-trip through toMap/fromMap and copyWith', () {
    final s = KivoSettings.defaults().copyWith(
      vaultEntranceHidden: true,
      vaultBiometricEnabled: true,
      vaultUninstallWarningShown: true,
    );
    final back = KivoSettings.fromMap(s.toMap());
    expect(back.vaultEntranceHidden, true);
    expect(back.vaultBiometricEnabled, true);
    expect(back.vaultUninstallWarningShown, true);
  });

  test('fromMap on legacy map (no vault keys) yields false defaults', () {
    final legacy = KivoSettings.defaults().toMap()
      ..remove('vaultEntranceHidden')
      ..remove('vaultBiometricEnabled')
      ..remove('vaultUninstallWarningShown');
    final back = KivoSettings.fromMap(legacy);
    expect(back.vaultEntranceHidden, false);
    expect(back.vaultBiometricEnabled, false);
    expect(back.vaultUninstallWarningShown, false);
  });
}
