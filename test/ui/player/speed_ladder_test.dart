import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/control/gesture_math.dart';
import 'package:kivo_player/ui/player/speed/speed_ladder_overlay.dart';

void main() {
  test('holdRightSpeedFor: finger-anchored, base ~2x, up = faster', () {
    const d = [1.0, 1.25, 1.5, 2.0, 3.0, 4.0];
    final base = defaultHoldRightIndex(d); // 3 -> 2.0x
    expect(holdRightSpeedFor(300, 300, 48, d, base), 2.0);       // no move
    expect(holdRightSpeedFor(300, 300 - 96, 48, d, base), 4.0);  // up 2 steps
    expect(holdRightSpeedFor(300, 300 + 144, 48, d, base), 1.0); // down 3 steps
  });
}
