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
      vsync: this, duration: const Duration(milliseconds: 800))
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
                builder: (_, __) => SizedBox(
                  width: 44, height: 44,
                  child: CircularProgressIndicator(
                    value: _c.value, strokeWidth: 3,
                    color: widget.accent, backgroundColor: Colors.white24),
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
