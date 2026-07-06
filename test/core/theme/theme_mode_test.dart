import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';

void main() {
  test('themeMode defaults to auto and round-trips', () {
    expect(KivoSettings.defaults().themeMode, 'auto');
    final m = KivoSettings.defaults().copyWith(themeMode: 'dark').toMap();
    expect(KivoSettings.fromMap(m).themeMode, 'dark');
  });
  test('themeModeFor maps strings', () {
    expect(themeModeFor('light'), ThemeMode.light);
    expect(themeModeFor('dark'), ThemeMode.dark);
    expect(themeModeFor('auto'), ThemeMode.system);
  });
  test('themes expose brand colors', () {
    expect(KivoTheme.light().colorScheme.primary, KivoColors.gold);
    expect(KivoTheme.dark().colorScheme.secondary, KivoColors.gold);
  });
}
