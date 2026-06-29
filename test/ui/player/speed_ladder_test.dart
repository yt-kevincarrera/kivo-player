import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/speed/speed_ladder_overlay.dart';

void main() {
  test('holdRightSpeedFor: top of screen = max, bottom = min', () {
    expect(holdRightSpeedFor(0, 400, 1.0, 4.0), 4.0);   // y=0 -> fraction 1 -> max
    expect(holdRightSpeedFor(400, 400, 1.0, 4.0), 1.0); // y=height -> fraction 0 -> min
  });
}
