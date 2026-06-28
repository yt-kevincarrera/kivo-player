import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';

void main() {
  test('palette matches spec', () {
    expect(KivoColors.blue, const Color(0xFF2D6CFF));
    expect(KivoColors.gold, const Color(0xFFE8B84B));
  });

  test('dark theme uses gold as secondary accent', () {
    final theme = KivoTheme.dark();
    expect(theme.colorScheme.secondary, KivoColors.gold);
    expect(theme.brightness, Brightness.dark);
  });
}
