import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';

void main() {
  test('onAccent is dark on a light accent and white on a dark accent', () {
    expect(
      onAccent(const Color(0xFFE8B84B)),
      const Color(0xFF231705),
    ); // gold → dark ink
    expect(
      onAccent(const Color(0xFF13315C)),
      Colors.white,
    ); // deep blue → white
  });

  test('theme primary and secondary follow the given accent', () {
    final blue = KivoTheme.dark(accent: const Color(0xFF4488FF));
    expect(blue.colorScheme.primary, const Color(0xFF4488FF));
    expect(blue.colorScheme.secondary, const Color(0xFF4488FF));
    expect(blue.colorScheme.onSecondary, onAccent(const Color(0xFF4488FF)));
  });

  test('default accent is gold', () {
    expect(KivoTheme.dark().colorScheme.secondary, KivoColors.gold);
  });

  test(
    'both appearances meet text contrast for default and custom controls',
    () {
      double contrast(Color a, Color b) {
        final x = a.computeLuminance();
        final y = b.computeLuminance();
        return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
      }

      for (final accent in [
        KivoColors.gold,
        const Color(0xFFE8B84B),
        const Color(0xFF5B9BE8),
        const Color(0xFFB77BE8),
        const Color(0xFF777777),
        const Color(0xFFFFFFFF),
        const Color(0xFF000000),
      ]) {
        for (final theme in [
          KivoTheme.light(accent: accent),
          KivoTheme.dark(accent: accent),
        ]) {
          final cs = theme.colorScheme;
          expect(contrast(cs.primary, cs.surface), greaterThanOrEqualTo(4.5));
          expect(contrast(cs.onPrimary, cs.primary), greaterThanOrEqualTo(4.5));
          expect(
            contrast(cs.onSurfaceVariant, cs.surface),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
      expect(KivoTheme.light().colorScheme.primary, KivoColors.lightGold);
    },
  );
}
