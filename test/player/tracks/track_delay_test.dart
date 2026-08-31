// test/player/tracks/subtitle_delay_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/tracks/track_delay.dart';

void main() {
  test('nudging moves by whole steps in both directions', () {
    expect(nudgeDelay(0, 1), 50);
    expect(nudgeDelay(0, -1), -50);
    expect(nudgeDelay(500, 3), 650);
  });

  test('formatting uses a Spanish decimal comma and an explicit sign', () {
    expect(formatDelay(0), '0,00 s');
    expect(formatDelay(500), '+0,50 s');
    expect(formatDelay(-250), '−0,25 s');
    expect(formatDelay(2000), '+2,00 s');
  });

  test('zero delay lights only the centre segment', () {
    const centre = (trackDelaySegments - 1) ~/ 2;
    final m = delayMeter(0);
    expect(m.centerIndex, centre);
    expect(m.firstLit, centre);
    expect(m.lastLit, centre);
  });

  test('a positive delay lights outward to the right', () {
    const centre = (trackDelaySegments - 1) ~/ 2;
    // A quarter of the range lights a quarter of one side.
    final m = delayMeter(trackDelayRangeMs ~/ 4);
    expect(m.firstLit, centre);
    expect(m.lastLit, centre + (centre / 4).round());
  });

  test('a negative delay lights outward to the left', () {
    const centre = (trackDelaySegments - 1) ~/ 2;
    final m = delayMeter(-trackDelayRangeMs ~/ 4);
    expect(m.firstLit, centre - (centre / 4).round());
    expect(m.lastLit, centre);
  });

  test('beyond the meter range the bar pins instead of overflowing', () {
    const centre = (trackDelaySegments - 1) ~/ 2;
    final m = delayMeter(trackDelayRangeMs * 3);
    expect(m.lastLit, trackDelaySegments - 1);
    expect(m.firstLit, centre);
    final n = delayMeter(-trackDelayRangeMs * 3);
    expect(n.firstLit, 0);
    expect(n.lastLit, centre);
  });
  test('the drag maps the bar across the full range, centred on zero', () {
    expect(delayFromDragFraction(0.5), 0);
    expect(delayFromDragFraction(1.0), trackDelayRangeMs);
    expect(delayFromDragFraction(0.0), -trackDelayRangeMs);
    expect(delayFromDragFraction(0.75), trackDelayRangeMs ~/ 2);
  });

  test('the drag snaps to the same step the buttons use', () {
    // Anything the finger lands on rounds to a whole 50 ms, so dragging and
    // tapping cannot produce values that look different but are 7 ms apart.
    for (final f in [0.13, 0.37, 0.62, 0.81, 0.94]) {
      expect(delayFromDragFraction(f) % trackDelayStepMs, 0);
    }
  });

  test('a finger dragged past either end clamps instead of overshooting', () {
    expect(delayFromDragFraction(-0.4), -trackDelayRangeMs);
    expect(delayFromDragFraction(1.8), trackDelayRangeMs);
  });

  test('the bar spans three seconds each way', () {
    // The buttons keep going beyond this; the bar is where fine control lives.
    expect(trackDelayRangeMs, 3000);
  });

}
