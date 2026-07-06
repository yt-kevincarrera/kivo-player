import 'package:flutter/material.dart';

/// Interpolated rect of the tile→screen grow. [t] is the (already-curved)
/// progress: 0 = tile, 1 = full screen. Returns [full] if the lerp is null.
Rect growRect(Rect origin, Rect full, double t) {
  final c = t.clamp(0.0, 1.0);
  return Rect.lerp(origin, full, c) ?? full;
}

/// Grows [child] from [origin] (a global rect) to the full screen as
/// [animation] runs 0→1, with a fade. Used by the player route's open flight.
/// The scale is non-uniform (screen aspect ≠ tile aspect); the momentary
/// distortion is imperceptible over the ~300ms grow and is standard for a
/// container-transform.
class GrowFromRect extends StatelessWidget {
  final Animation<double> animation;
  final Rect origin;
  final Widget child;
  const GrowFromRect({
    super.key,
    required this.animation,
    required this.origin,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final full = Offset.zero & size;
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      builder: (context, _) {
        final t = curve.value;
        final rect = growRect(origin, full, t);
        final sx = full.width == 0 ? 1.0 : rect.width / full.width;
        final sy = full.height == 0 ? 1.0 : rect.height / full.height;
        final m = Matrix4.identity()
          ..translate(rect.left, rect.top)
          ..scale(sx, sy);
        return Opacity(
          // Content reaches full opacity a bit before full size.
          opacity: (t * 1.4).clamp(0.0, 1.0),
          child: ClipRect(
            child: Transform(
              transform: m,
              transformHitTests: false,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
