import 'package:flutter/material.dart';

class KivoColors {
  static const gold = Color(0xFFC7A15A); // matte gold, dark appearance
  static const lightGold = Color(0xFF826318); // readable on light surfaces
  // Legacy player surfaces (fixed, not brand colors).
  static const ink = Color(0xFF0A0E1A);
  static const panel = Color(0xFF111726);
  static const darkBg = Color(0xFF111419);
  static const darkSurface = Color(0xFF191D24);
  static const lightBg = Color(0xFFFAFAF7);
  static const lightSurface = Color(0xFFFFFFFF);
}

/// Legible color for text/icons drawn on top of an [accent]-colored fill.
/// Warm dark ink on light accents (keeps the gold look), white on dark ones.
Color onAccent(Color accent) {
  const ink = Color(0xFF231705);
  final luminance = accent.computeLuminance();
  final darkContrast = (luminance + 0.05) / (ink.computeLuminance() + 0.05);
  final lightContrast = 1.05 / (luminance + 0.05);
  if (darkContrast >= 4.5 && darkContrast >= lightContrast) return ink;
  if (lightContrast >= 4.5) return Colors.white;
  return Colors.black;
}

/// Preserve custom accents, deriving a legible control color for each theme.
Color accessibleAccent(Color accent, Color surface, Brightness brightness) {
  if (accent == KivoColors.gold || accent == const Color(0xFFE8B84B)) {
    return brightness == Brightness.light
        ? KivoColors.lightGold
        : KivoColors.gold;
  }
  final hsl = HSLColor.fromColor(accent);
  for (var step = 0; step <= 100; step++) {
    final lightness = brightness == Brightness.light
        ? hsl.lightness * (1 - step / 100)
        : hsl.lightness + (1 - hsl.lightness) * step / 100;
    final candidate = hsl.withLightness(lightness).toColor();
    final a = candidate.computeLuminance();
    final b = surface.computeLuminance();
    final contrast = a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
    if (contrast >= 4.5) return candidate;
  }
  return brightness == Brightness.light ? Colors.black : Colors.white;
}

class KivoTheme {
  static ThemeData dark({Color accent = KivoColors.gold}) => _build(
    brightness: Brightness.dark,
    accent: accent,
    bg: KivoColors.darkBg,
    surface: KivoColors.darkSurface,
    onBg: const Color(0xFFE9EAEC),
    onSurfaceVariant: const Color(0xFFA8AFB9),
  );

  static ThemeData light({Color accent = KivoColors.gold}) => _build(
    brightness: Brightness.light,
    accent: accent,
    bg: KivoColors.lightBg,
    surface: KivoColors.lightSurface,
    onBg: const Color(0xFF1A1D23),
    onSurfaceVariant: const Color(0xFF59616D),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color accent,
    required Color bg,
    required Color surface,
    required Color onBg,
    required Color onSurfaceVariant,
  }) {
    final controlAccent = accessibleAccent(accent, surface, brightness);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: controlAccent,
          onPrimary: onAccent(controlAccent),
          secondary: controlAccent,
          onSecondary: onAccent(controlAccent),
          surface: surface,
          surfaceContainerLow: brightness == Brightness.dark
              ? const Color(0xFF171B21)
              : const Color(0xFFF5F5F1),
          surfaceContainer: brightness == Brightness.dark
              ? const Color(0xFF1C2129)
              : const Color(0xFFF1F2EF),
          surfaceContainerHigh: brightness == Brightness.dark
              ? const Color(0xFF20252D)
              : const Color(0xFFEFF0ED),
          surfaceContainerHighest: brightness == Brightness.dark
              ? const Color(0xFF242A33)
              : const Color(0xFFE9ECEB),
          outlineVariant: brightness == Brightness.dark
              ? const Color(0xFF343C47)
              : const Color(0xFFD5D9DC),
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
