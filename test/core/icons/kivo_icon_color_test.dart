import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/icons/kivo_icons.dart';

void main() {
  const white = Color(0xFFFFFFFF);
  const dark = Color(0xFF1A1A1A);

  test('explicit color always wins', () {
    expect(resolveIconBaseColor(dark, white), dark);
    expect(resolveIconBaseColor(dark, null), dark);
  });

  test('no explicit color falls back to the ambient IconTheme color', () {
    // This is the light-mode fix: an AppBar action icon adopts the theme's
    // (dark) icon color instead of the hardcoded white.
    expect(resolveIconBaseColor(null, dark), dark);
  });

  test('no explicit color and no ambient color falls back to white', () {
    expect(resolveIconBaseColor(null, null), white);
  });
}
