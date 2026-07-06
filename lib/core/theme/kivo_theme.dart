import 'package:flutter/material.dart';

class KivoColors {
  static const blue = Color(0xFF2D6CFF);
  static const gold = Color(0xFFE8B84B); // default accent preset
  // Legacy player surfaces (fixed, not brand colors).
  static const ink = Color(0xFF0A0E1A);
  static const panel = Color(0xFF111726);
  static const darkBg = Color(0xFF0F1218);
  static const darkSurface = Color(0xFF181C24);
  static const lightBg = Color(0xFFF4F4F2);
  static const lightSurface = Color(0xFFFFFFFF);
}

/// Legible color for text/icons drawn on top of an [accent]-colored fill.
/// Warm dark ink on light accents (keeps the gold look), white on dark ones.
Color onAccent(Color accent) =>
    accent.computeLuminance() > 0.45 ? const Color(0xFF231705) : Colors.white;

class KivoTheme {
  static ThemeData dark({Color accent = KivoColors.gold}) => _build(
        brightness: Brightness.dark,
        accent: accent,
        bg: KivoColors.darkBg,
        surface: KivoColors.darkSurface,
        onBg: const Color(0xFFF1F2F4),
        onSurfaceVariant: const Color(0xFF9AA0A8),
      );

  static ThemeData light({Color accent = KivoColors.gold}) => _build(
        brightness: Brightness.light,
        accent: accent,
        bg: KivoColors.lightBg,
        surface: KivoColors.lightSurface,
        onBg: const Color(0xFF15171C),
        onSurfaceVariant: const Color(0xFF6B7280),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color accent,
    required Color bg,
    required Color surface,
    required Color onBg,
    required Color onSurfaceVariant,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      onPrimary: onAccent(accent),
      secondary: accent,
      onSecondary: onAccent(accent),
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
