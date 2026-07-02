import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/engine/playback_provider.dart';
import '../../../player/loop/ab_loop.dart';

/// Gold A-B range band + markers painted behind the seek bar's Slider.
/// Purely decorative: IgnorePointer so the Slider's gestures are untouched.
class AbRangeLayer extends ConsumerWidget {
  const AbRangeLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loop = ref.watch(abLoopProvider);
    final total = ref.watch(durationProvider).value ?? Duration.zero;
    if (loop == null || loop.a == null || total == Duration.zero) {
      return const SizedBox.shrink();
    }
    final totalMs = total.inMilliseconds.toDouble();
    final aFrac = (loop.a!.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final bFrac =
        loop.b == null ? null : (loop.b!.inMilliseconds / totalMs).clamp(0.0, 1.0);
    return IgnorePointer(
      child: CustomPaint(
        key: const ValueKey('ab-range-paint'),
        painter: _AbRangePainter(aFrac: aFrac, bFrac: bFrac, color: KivoColors.gold),
        size: Size.infinite,
      ),
    );
  }
}

class _AbRangePainter extends CustomPainter {
  final double aFrac;
  final double? bFrac;
  final Color color;
  // Matches the Slider's effective horizontal track inset (thumb radius).
  static const _inset = 11.0;
  const _AbRangePainter({required this.aFrac, required this.bFrac, required this.color});

  double _x(Size size, double frac) => _inset + frac * (size.width - 2 * _inset);

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final xa = _x(size, aFrac);
    if (bFrac != null) {
      final xb = _x(size, bFrac!);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(xa, cy - 4, xb, cy + 4),
          const Radius.circular(3),
        ),
        Paint()..color = color.withValues(alpha: 0.28),
      );
    }
    _marker(canvas, xa, cy, 'A');
    if (bFrac != null) _marker(canvas, _x(size, bFrac!), cy, 'B');
  }

  void _marker(Canvas canvas, double x, double cy, String label) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, cy), width: 2.5, height: 14),
        const Radius.circular(2),
      ),
      Paint()..color = color,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 7.5, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, cy - 7 - tp.height - 1));
  }

  @override
  bool shouldRepaint(_AbRangePainter old) =>
      old.aFrac != aFrac || old.bFrac != bFrac || old.color != color;
}
