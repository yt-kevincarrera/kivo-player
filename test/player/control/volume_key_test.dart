import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/control/gesture_math.dart';

void main() {
  group('volumeKeyStep', () {
    test('one press up from 100 enters the boost range (not capped at 100)', () {
      final v = volumeKeyStep(100, 1, 15, 150);
      expect(v, greaterThan(100));
      expect(v, closeTo(106.67, 0.1));
    });

    test('repeated ups clamp at boostMax', () {
      var v = 100.0;
      for (var i = 0; i < 20; i++) {
        v = volumeKeyStep(v, 1, 15, 150);
      }
      expect(v, 150);
    });

    test('down never goes below 0', () {
      expect(volumeKeyStep(0, -1, 15, 150), 0);
      expect(volumeKeyStep(3, -1, 15, 150), 0);
    });

    test('below 100 moves one system step', () {
      expect(volumeKeyStep(50, 1, 15, 150), closeTo(56.67, 0.1));
      expect(volumeKeyStep(50, -1, 15, 150), closeTo(43.33, 0.1));
    });

    test('maxIndex 0 falls back to a 15-step granularity', () {
      expect(volumeKeyStep(50, 1, 0, 150), closeTo(56.67, 0.1));
    });
  });
}
