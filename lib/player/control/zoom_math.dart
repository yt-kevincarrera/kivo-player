import 'dart:ui';

/// Zoom scale floor. Zooming out past the natural frame is out of scope: it
/// would letterbox an already-letterboxed video with nothing to show.
const double kZoomMin = 1.0;

/// Translation bound: with the frame scaled by [scale], the visible rect can
/// only slide by half the overflow before an edge would show empty. Returns
/// [Offset.zero] whenever there is no overflow to slide into.
///
/// The bound is measured against the VIEWPORT, not the letterboxed video rect —
/// deliberately, because that is what lets a zoom-and-pan crop black bars away.
Offset clampZoomOffset(Offset offset, double scale, Size viewport) {
  if (scale <= kZoomMin) return Offset.zero;
  final maxX = (scale - 1) * viewport.width / 2;
  final maxY = (scale - 1) * viewport.height / 2;
  return Offset(
    offset.dx.clamp(-maxX, maxX),
    offset.dy.clamp(-maxY, maxY),
  );
}

/// Focal-anchored zoom: multiplies [scale] by [factor] (clamped to
/// [kZoomMin]..[max]) and moves [offset] so the content under [focal] stays
/// under [focal].
///
/// [focal] is in the viewport's local coordinates. The transform this feeds
/// scales about the viewport CENTRE, so the focal point is measured from there.
({double scale, Offset offset}) zoomAt({
  required double scale,
  required Offset offset,
  required double factor,
  required Offset focal,
  required Size viewport,
  required double max,
}) {
  final ceiling = max < kZoomMin ? kZoomMin : max;
  final target = (scale * factor).clamp(kZoomMin, ceiling);
  if (target <= kZoomMin) return (scale: kZoomMin, offset: Offset.zero);
  final centre = Offset(viewport.width / 2, viewport.height / 2);
  final fromCentre = focal - centre;
  final ratio = target / scale;
  final next = fromCentre - (fromCentre - offset) * ratio;
  return (scale: target, offset: clampZoomOffset(next, target, viewport));
}
