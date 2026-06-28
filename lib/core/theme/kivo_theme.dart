import 'package:flutter/material.dart';

class KivoColors {
  static const blue = Color(0xFF2D6CFF);
  static const gold = Color(0xFFE8B84B);
  static const ink = Color(0xFF0A0E1A);
  static const panel = Color(0xFF111726);
}

class KivoTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: KivoColors.blue,
      secondary: KivoColors.gold,
      surface: KivoColors.panel,
    );
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: KivoColors.ink,
      useMaterial3: true,
    );
  }
}
