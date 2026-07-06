import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';

void main() {
  test('onAccent is dark on a light accent and white on a dark accent', () {
    expect(onAccent(const Color(0xFFE8B84B)), const Color(0xFF231705)); // gold → dark ink
    expect(onAccent(const Color(0xFF13315C)), Colors.white);            // deep blue → white
  });

  test('theme primary and secondary follow the given accent', () {
    final blue = KivoTheme.dark(accent: const Color(0xFF2D6CFF));
    expect(blue.colorScheme.primary, const Color(0xFF2D6CFF));
    expect(blue.colorScheme.secondary, const Color(0xFF2D6CFF));
    expect(blue.colorScheme.onSecondary, onAccent(const Color(0xFF2D6CFF)));
  });

  test('default accent is gold', () {
    expect(KivoTheme.dark().colorScheme.secondary, const Color(0xFFE8B84B));
  });
}
