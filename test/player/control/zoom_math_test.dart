import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/control/zoom_math.dart';

void main() {
  const viewport = Size(400, 800);
  const centre = Offset(200, 400);

  test('no zoom means no translation is possible', () {
    expect(clampZoomOffset(const Offset(50, 50), 1.0, viewport), Offset.zero);
    expect(clampZoomOffset(const Offset(50, 50), 0.5, viewport), Offset.zero);
  });

  test('translation is bounded by half the overflow on each axis', () {
    // scale 2 over a 400x800 viewport => limits are 200 and 400.
    expect(clampZoomOffset(const Offset(500, 900), 2.0, viewport), const Offset(200, 400));
    expect(clampZoomOffset(const Offset(-500, -900), 2.0, viewport), const Offset(-200, -400));
    // inside the bounds it passes through untouched
    expect(clampZoomOffset(const Offset(30, -40), 2.0, viewport), const Offset(30, -40));
  });

  test('zoomAt clamps the scale into [1, max]', () {
    final up = zoomAt(
        scale: 1.0, offset: Offset.zero, factor: 99,
        focal: centre, viewport: viewport, max: 4.0);
    expect(up.scale, 4.0);

    final down = zoomAt(
        scale: 2.0, offset: Offset.zero, factor: 0.01,
        focal: centre, viewport: viewport, max: 4.0);
    expect(down.scale, 1.0);
    expect(down.offset, Offset.zero, reason: 'falling back to 1x must recentre');
  });

  test('a pinch centred on the viewport centre introduces no translation', () {
    final r = zoomAt(
        scale: 1.0, offset: Offset.zero, factor: 2.0,
        focal: centre, viewport: viewport, max: 4.0);
    expect(r.scale, 2.0);
    expect(r.offset.dx, closeTo(0, 1e-9));
    expect(r.offset.dy, closeTo(0, 1e-9));
  });

  test('a pinch keeps its focal point anchored', () {
    // Focal 100px left of centre: doubling the scale pushes content right by
    // 100px so the same pixel stays under the fingers.
    final r = zoomAt(
        scale: 1.0, offset: Offset.zero, factor: 2.0,
        focal: const Offset(100, 400), viewport: viewport, max: 4.0);
    expect(r.scale, 2.0);
    expect(r.offset.dx, closeTo(100, 1e-9));
    expect(r.offset.dy, closeTo(0, 1e-9));
  });

  test('the anchor result is still clamped inside the bounds', () {
    // A focal point at the very edge asks for more translation than a 2x frame
    // can give; the bound wins, so no empty edge is ever exposed.
    final r = zoomAt(
        scale: 1.0, offset: Offset.zero, factor: 2.0,
        focal: Offset.zero, viewport: viewport, max: 4.0);
    expect(r.offset.dx, 200);
    expect(r.offset.dy, 400);
  });

  test('a degenerate max below 1 cannot drag the scale under 1', () {
    final r = zoomAt(
        scale: 1.0, offset: Offset.zero, factor: 2.0,
        focal: centre, viewport: viewport, max: 0.5);
    expect(r.scale, 1.0);
    expect(r.offset, Offset.zero);
  });
}
