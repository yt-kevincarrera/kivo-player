import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/transition/grow_rect.dart';

void main() {
  const origin = Rect.fromLTWH(20, 100, 168, 94.5);
  const full = Rect.fromLTWH(0, 0, 400, 800);

  test('growRect at t=0 is the origin rect', () {
    expect(growRect(origin, full, 0), origin);
  });

  test('growRect at t=1 is the full rect', () {
    expect(growRect(origin, full, 1), full);
  });

  test('growRect at t=0.5 is the midpoint lerp', () {
    expect(growRect(origin, full, 0.5), Rect.lerp(origin, full, 0.5));
  });

  test('growRect clamps t outside [0,1]', () {
    expect(growRect(origin, full, -1), origin);
    expect(growRect(origin, full, 2), full);
  });

  test('growRect with a degenerate origin does not throw', () {
    expect(growRect(Rect.zero, full, 0.5), Rect.lerp(Rect.zero, full, 0.5));
  });
}
