import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/control/gesture_math.dart';

void main() {
  test('tapZoneOf splits screen into thirds', () {
    expect(tapZoneOf(0.1), TapZone.left);
    expect(tapZoneOf(0.5), TapZone.center);
    expect(tapZoneOf(0.9), TapZone.right);
  });

  test('clampSeek clamps to [0, total]', () {
    const total = Duration(minutes: 10);
    expect(clampSeek(const Duration(seconds: 5), const Duration(seconds: -10), total), Duration.zero);
    expect(clampSeek(const Duration(minutes: 9, seconds: 59), const Duration(seconds: 10), total), total);
    expect(clampSeek(const Duration(minutes: 1), const Duration(seconds: 10), total), const Duration(minutes: 1, seconds: 10));
  });

  test('dragValue increases when dragging up (negative dy)', () {
    // region 400px, sensitivity 1.0, drag up 200px => +0.5
    expect(dragValue(0.2, -200, 400, 1.0), closeTo(0.7, 1e-9));
    // clamps at 1.0
    expect(dragValue(0.9, -400, 400, 1.0), 1.0);
    // drag down decreases, clamps at 0
    expect(dragValue(0.1, 200, 400, 1.0), 0.0);
  });

  test('ladderSpeed maps fraction to discrete steps', () {
    // 6 steps between 1.0 and 4.0 => [1.0,1.6,2.2,2.8,3.4,4.0]
    expect(ladderSpeed(0.0, 1.0, 4.0, 6), closeTo(1.0, 1e-9));
    expect(ladderSpeed(1.0, 1.0, 4.0, 6), closeTo(4.0, 1e-9));
    expect(ladderSpeed(0.5, 1.0, 4.0, 6), closeTo(2.8, 1e-9)); // nearest step index round(0.5*5)=3 -> 1+3*0.6=2.8
  });

  test('snapToDetent snaps within epsilon, passes through otherwise', () {
    expect(snapToDetent(1.02, const [1.0, 1.5, 2.0], 0.05), 1.0);
    expect(snapToDetent(1.30, const [1.0, 1.5, 2.0], 0.05), 1.30);
  });

  test('clampRate and round2', () {
    expect(clampRate(5.0, 0.25, 4.0), 4.0);
    expect(clampRate(0.1, 0.25, 4.0), 0.25);
    expect(round2(1.126), 1.13);
  });

  test('volumeMapping splits system vs player gain at 100%', () {
    final a = volumeMapping(80, 150);
    expect(a.system01, closeTo(0.8, 1e-9));
    expect(a.playerPercent, 100); // no double attenuation below 100%
    final b = volumeMapping(140, 150);
    expect(b.system01, 1.0);
    expect(b.playerPercent, 140);
  });

  test('dragVolumePercent: drag up from 80 caps at 100 (per-drag cap)', () {
    // drag up 400px in a 400px region at 1.0 sensitivity: +100 -> would be 180, capped at 100
    expect(dragVolumePercent(80, -400, 400, 1.0, 100), closeTo(100, 1e-9));
  });

  test('dragVolumePercent: drag up from 100 can reach boostMax 150', () {
    // drag up 200px in 400px region: +50 -> 150, capped at 150
    expect(dragVolumePercent(100, -200, 400, 1.0, 150), closeTo(150, 1e-9));
  });

  test('dragVolumePercent: drag down lowers volume', () {
    // drag down 200px in 400px region: -50 -> 10
    expect(dragVolumePercent(60, 200, 400, 1.0, 100), closeTo(10, 1e-9));
  });
}
