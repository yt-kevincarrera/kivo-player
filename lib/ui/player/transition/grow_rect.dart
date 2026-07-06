import 'package:flutter/widgets.dart';

/// Interpolated rect of the tile→screen grow. [t] is the (already-curved)
/// progress: 0 = tile, 1 = full screen. Returns [full] if the lerp is null.
Rect growRect(Rect origin, Rect full, double t) {
  final c = t.clamp(0.0, 1.0);
  return Rect.lerp(origin, full, c) ?? full;
}
