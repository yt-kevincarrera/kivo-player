import 'package:flutter/painting.dart';
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

  test('detentSpeed snaps fraction to explicit detents', () {
    const d = [1.0, 1.25, 1.5, 2.0, 3.0, 4.0];
    expect(detentSpeed(0.0, d), 1.0);   // bottom -> first
    expect(detentSpeed(1.0, d), 4.0);   // top -> last
    expect(detentSpeed(0.5, d), 2.0);   // round(0.5*5)=3 -> index 3 = 2.0
    expect(detentSpeed(0.5, const []), 1.0);
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

  test('inVerticalDeadZone: top and bottom strips, middle is live', () {
    expect(inVerticalDeadZone(10, 400, 20, 30, 24), isTrue);   // within top inset+margin
    expect(inVerticalDeadZone(390, 400, 20, 30, 24), isTrue);  // within bottom strip
    expect(inVerticalDeadZone(200, 400, 20, 30, 24), isFalse); // live middle
  });

  test('defaultHoldRightIndex picks the detent nearest 2.0x', () {
    expect(defaultHoldRightIndex(const [1.0, 1.25, 1.5, 2.0, 3.0, 4.0]), 3);
    expect(defaultHoldRightIndex(const []), 0);
  });

  test('anchoredDetentIndex: up = faster, clamped, viewport-independent', () {
    expect(anchoredDetentIndex(300, 300, 48, 6, 3), 3);      // no move = base
    expect(anchoredDetentIndex(300, 300 - 96, 48, 6, 3), 5); // up 2 steps
    expect(anchoredDetentIndex(300, 300 + 144, 48, 6, 3), 0);// down 3 steps, clamped
    expect(anchoredDetentIndex(300, 0, 48, 6, 3), 5);        // clamp high
  });

  test('inLateralDeadZone: left/right edge strips, center is live', () {
    expect(inLateralDeadZone(10, 800, 38), isTrue);   // left strip
    expect(inLateralDeadZone(790, 800, 38), isTrue);  // right strip
    expect(inLateralDeadZone(400, 800, 38), isFalse); // center
  });

  test('inCenterRotateZone: only the central 30% band is true', () {
    // width 800, fraction 0.30 → band spans x 280..520 (35%..65%)
    expect(inCenterRotateZone(400, 800), isTrue);  // dead center
    expect(inCenterRotateZone(280, 800), isTrue);  // left edge of the band
    expect(inCenterRotateZone(520, 800), isTrue);  // right edge of the band
    expect(inCenterRotateZone(279, 800), isFalse); // just outside → brightness
    expect(inCenterRotateZone(521, 800), isFalse); // just outside → volume
    expect(inCenterRotateZone(10, 800), isFalse);  // far left
    expect(inCenterRotateZone(790, 800), isFalse); // far right
  });

  test('inCenterRotateZone: honors a custom fraction and degenerate widths', () {
    // fraction 0.20 → band spans x 400..600 of 1000
    expect(inCenterRotateZone(500, 1000, 0.20), isTrue);
    expect(inCenterRotateZone(399, 1000, 0.20), isFalse);
    expect(inCenterRotateZone(100, 0), isFalse); // no width → never claims the drag
  });

  test('horizontalSeekTarget: fixed ~60s per full screen, ms precision, sensitivity + clamp', () {
    const total = Duration(minutes: 10);
    const start = Duration(minutes: 2);
    // full-width drag at sensitivity 1.0 → +60s → 3:00 (fixed span, NOT the whole video)
    expect(horizontalSeekTarget(start: start, accumPx: 400, widthPx: 400, total: total, sensitivity: 1.0),
        const Duration(minutes: 3));
    // half width → +30s → 2:30
    expect(horizontalSeekTarget(start: start, accumPx: 200, widthPx: 400, total: total, sensitivity: 1.0),
        const Duration(minutes: 2, seconds: 30));
    // sub-second precision: 1px on 400px → (1/400)*60000 = 150ms
    expect(horizontalSeekTarget(start: Duration.zero, accumPx: 1, widthPx: 400, total: total, sensitivity: 1.0),
        const Duration(milliseconds: 150));
    // backward drag: -30s → 1:30
    expect(horizontalSeekTarget(start: start, accumPx: -200, widthPx: 400, total: total, sensitivity: 1.0),
        const Duration(minutes: 1, seconds: 30));
    // sensitivity scales the span: half width × 0.5 = +15s → 2:15
    expect(horizontalSeekTarget(start: start, accumPx: 200, widthPx: 400, total: total, sensitivity: 0.5),
        const Duration(minutes: 2, seconds: 15));
    // clamps to [0, total]: near the end, a forward full-width drag stops at total
    expect(horizontalSeekTarget(start: const Duration(minutes: 9, seconds: 59), accumPx: 400, widthPx: 400,
        total: total, sensitivity: 1.0), total);
    // width 0 → returns start (no crash)
    expect(horizontalSeekTarget(start: start, accumPx: 100, widthPx: 0, total: total, sensitivity: 1.0), start);
  });

  test('dismissCommit: commits past 25% progress or on a fast fling', () {
    expect(dismissCommit(0.30, 0), isTrue);   // dragged far enough
    expect(dismissCommit(0.10, 800), isTrue); // fast downward fling
    expect(dismissCommit(0.10, 0), isFalse);  // small, slow → snap back
    expect(dismissCommit(0.25, 0), isTrue);   // exactly at threshold
  });

  test('zone constants are the ones the zone functions use', () {
    // The gesture map draws from these; a drift here would draw a lie.
    expect(tapZoneOf(kTapCenterStart + 0.01), TapZone.center);
    expect(tapZoneOf(kTapCenterStart - 0.01), TapZone.left);
    expect(tapZoneOf(kTapCenterEnd + 0.01), TapZone.right);
    // Rotate band: inside at the center, outside just past half the fraction.
    expect(inCenterRotateZone(50, 100), true);
    expect(inCenterRotateZone(50 + 100 * kCenterRotateFraction / 2 + 1, 100), false);
    // Lateral edges and vertical dead zone.
    expect(inLateralDeadZone(kLateralEdgeMargin - 1, 400, kLateralEdgeMargin), true);
    expect(inLateralDeadZone(200, 400, kLateralEdgeMargin), false);
    expect(inVerticalDeadZone(kVerticalDeadMargin - 1, 800, 0, 0, kVerticalDeadMargin), true);
  });

  group('dragIntentFor', () {
    const viewport = Size(400, 800);

    DragIntent? route({
      int pointerCount = 1,
      bool pinchZoomEnabled = true,
      bool zoomActive = false,
      required Offset start,
      Offset delta = const Offset(50, 0),
      bool controlsVisible = false,
    }) =>
        dragIntentFor(
          pointerCount: pointerCount,
          pinchZoomEnabled: pinchZoomEnabled,
          zoomActive: zoomActive,
          start: start,
          delta: delta,
          viewport: viewport,
          topInset: 0,
          bottomInset: 0,
          controlsVisible: controlsVisible,
        );

    test('two fingers zoom', () {
      expect(route(pointerCount: 2, start: const Offset(200, 400)), DragIntent.zoom);
    });

    test('two fingers do nothing when pinch zoom is off', () {
      expect(route(pointerCount: 2, pinchZoomEnabled: false, start: const Offset(200, 400)),
          DragIntent.none);
    });

    test('two fingers win even over the lateral dismiss strip', () {
      expect(route(pointerCount: 2, start: const Offset(10, 400)), DragIntent.zoom);
    });

    test('one finger pans while zoomed', () {
      expect(route(zoomActive: true, start: const Offset(200, 400)), DragIntent.pan);
    });

    test('panning wins over every one-finger gesture while zoomed', () {
      // The suspension the design promises: no brightness, volume, seek,
      // minimize or rotate until the zoom is released.
      expect(route(zoomActive: true, start: const Offset(10, 400)), DragIntent.pan);
      expect(route(zoomActive: true, start: const Offset(80, 400), delta: const Offset(0, -60)),
          DragIntent.pan);
    });

    test('the lateral strip dismisses, with no slop needed', () {
      expect(route(start: const Offset(10, 400), delta: Offset.zero), DragIntent.dismiss);
      expect(route(start: const Offset(395, 400), delta: Offset.zero), DragIntent.dismiss);
    });

    test('the vertical dead strips are ignored', () {
      expect(route(start: const Offset(200, 5), delta: Offset.zero), DragIntent.none);
      expect(route(start: const Offset(200, 795), delta: Offset.zero), DragIntent.none);
    });

    test('below the slop nothing is decided yet', () {
      expect(route(start: const Offset(200, 400), delta: const Offset(4, 4)), isNull);
    });

    test('the centre band rotates on a vertical drag when the controls are hidden', () {
      expect(route(start: const Offset(200, 400), delta: const Offset(0, -60)), DragIntent.rotate);
    });

    test('the centre band does NOT rotate while the controls are up', () {
      expect(
          route(start: const Offset(200, 400), delta: const Offset(0, -60), controlsVisible: true),
          DragIntent.volume);
    });

    test('the centre band seeks on a horizontal drag, never rotates', () {
      expect(route(start: const Offset(200, 400), delta: const Offset(60, 0)), DragIntent.seek);
    });

    test('vertical drags are brightness on the left and volume on the right', () {
      expect(route(start: const Offset(80, 400), delta: const Offset(0, -60)),
          DragIntent.brightness);
      expect(route(start: const Offset(320, 400), delta: const Offset(0, -60)), DragIntent.volume);
    });

    test('horizontal drags seek', () {
      expect(route(start: const Offset(80, 400), delta: const Offset(60, 5)), DragIntent.seek);
    });

    test('a diagonal tie goes to seek', () {
      expect(route(start: const Offset(80, 400), delta: const Offset(40, 40)), DragIntent.seek);
    });
  });
}
