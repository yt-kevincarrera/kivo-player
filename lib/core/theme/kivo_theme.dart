import 'package:flutter/material.dart';

class KivoColors {
  static const blue = Color(0xFF2D6CFF);
  static const gold = Color(0xFFE8B84B);
  // Legacy player surfaces (kept — used by PlayerScreen/speed_panel/etc.)
  static const ink = Color(0xFF0A0E1A);
  static const panel = Color(0xFF111726);
  // Soft surfaces for library theme
  static const darkBg = Color(0xFF0F1218);
  static const darkSurface = Color(0xFF181C24);
  static const lightBg = Color(0xFFF4F4F2);
  static const lightSurface = Color(0xFFFFFFFF);
}

class KivoTheme {
  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        bg: KivoColors.darkBg,
        surface: KivoColors.darkSurface,
        onBg: const Color(0xFFF1F2F4),
        onSurfaceVariant: const Color(0xFF9AA0A8),
      );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        bg: KivoColors.lightBg,
        surface: KivoColors.lightSurface,
        onBg: const Color(0xFF15171C),
        onSurfaceVariant: const Color(0xFF6B7280),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color onBg,
    required Color onSurfaceVariant,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: KivoColors.blue,
      brightness: brightness,
    ).copyWith(
      primary: KivoColors.blue,
      secondary: KivoColors.gold,
      surface: surface,
      onSurface: onBg,
      onSurfaceVariant: onSurfaceVariant,
    );
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onBg,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }
}

ThemeMode themeModeFor(String mode) => switch (mode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
