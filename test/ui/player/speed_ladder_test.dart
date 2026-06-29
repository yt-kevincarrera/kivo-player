import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/speed/speed_ladder_overlay.dart';

void main() {
  test('holdRightSpeedFor: top of screen = last detent, bottom = first', () {
    const d = [1.0, 1.25, 1.5, 2.0, 3.0, 4.0];
    expect(holdRightSpeedFor(0, 400, d), 4.0);    // y=0 -> fraction 1 -> last
    expect(holdRightSpeedFor(400, 400, d), 1.0);  // y=height -> fraction 0 -> first
  });
}
