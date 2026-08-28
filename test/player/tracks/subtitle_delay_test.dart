// test/player/tracks/subtitle_delay_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/tracks/subtitle_delay.dart';

void main() {
  test('nudging moves by whole steps in both directions', () {
    expect(nudgeSubtitleDelay(0, 1), 50);
    expect(nudgeSubtitleDelay(0, -1), -50);
    expect(nudgeSubtitleDelay(500, 3), 650);
  });

  test('formatting uses a Spanish decimal comma and an explicit sign', () {
    expect(formatSubtitleDelay(0), '0,00 s');
    expect(formatSubtitleDelay(500), '+0,50 s');
    expect(formatSubtitleDelay(-250), '−0,25 s');
    expect(formatSubtitleDelay(2000), '+2,00 s');
  });

  test('zero delay lights only the centre segment', () {
    final m = subtitleMeter(0);
    expect(m.centerIndex, 6);
    expect(m.firstLit, 6);
    expect(m.lastLit, 6);
  });

  test('a positive delay lights outward to the right', () {
    final m = subtitleMeter(500); // 500/1500 of 6 segments = 2
    expect(m.firstLit, 6);
    expect(m.lastLit, 8);
  });

  test('a negative delay lights outward to the left', () {
    final m = subtitleMeter(-500);
    expect(m.firstLit, 4);
    expect(m.lastLit, 6);
  });

  test('beyond the meter range the bar pins instead of overflowing', () {
    final m = subtitleMeter(9000);
    expect(m.lastLit, subtitleDelaySegments - 1);
    expect(m.firstLit, 6);
    final n = subtitleMeter(-9000);
    expect(n.firstLit, 0);
    expect(n.lastLit, 6);
  });
}
