import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HoldToUnlock extends StatefulWidget {
  final VoidCallback onUnlock;
  final Color accent;
  const HoldToUnlock({super.key, required this.onUnlock, required this.accent});
  @override State<HoldToUnlock> createState() => _HoldToUnlockState();
}

class _HoldToUnlockState extends State<HoldToUnlock> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.mediumImpact();
        widget.onUnlock();
        _c.reset();
      }
    });
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) { HapticFeedback.selectionClick(); _c.forward(from: 0); },
      onLongPressEnd: (_) => _c.reverse(),
      onLongPressCancel: () => _c.reverse(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 44, height: 44,
            child: Stack(alignment: Alignment.center, children: [
              AnimatedBuilder(
                animation: _c,
                builder: (_, __) => CustomPaint(
                  size: const Size(44, 44),
                  painter: _SegmentRingPainter(_c.value, widget.accent),
                ),
              ),
              Icon(Icons.lock, color: widget.accent, size: 22),
            ]),
          ),
          const SizedBox(height: 10),
          const Text('mantén para desbloquear',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

class _SegmentRingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color accent;
  static const int segments = 24;
  _SegmentRingPainter(this.progress, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rOuter = size.width / 2 - 1;
    final rInner = rOuter - 5.5;
    final lit = (progress * segments).round();
    final unlitPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    final litPaint = Paint()
      ..color = accent
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < segments; i++) {
      final a = -math.pi / 2 + (i / segments) * 2 * math.pi; // start at top, clockwise
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        center + dir * rInner,
        center + dir * rOuter,
        i < lit ? litPaint : unlitPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_SegmentRingPainter old) =>
      old.progress != progress || old.accent != accent;
}
