import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/control/gesture_math.dart';

final holdSpeedProvider = StateProvider<double?>((ref) => null);
// true while a hold-RIGHT (variable speed) is active → show the detent meter;
// false for hold-LEFT (fixed speed) → show only a compact badge.
final holdSpeedIsLadderProvider = StateProvider<bool>((ref) => false);

double holdRightSpeedFor(
        double startY, double currentY, double stepPx, List<double> detents, int baseIndex) =>
    detents.isEmpty
        ? 1.0
        : detents[anchoredDetentIndex(startY, currentY, stepPx, detents.length, baseIndex)];

String _fmtSpeed(double v) =>
    v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

class SpeedLadderOverlay extends ConsumerWidget {
  const SpeedLadderOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(holdSpeedProvider);
    if (speed == null) return const SizedBox.shrink();
    final isLadder = ref.watch(holdSpeedIsLadderProvider);
    final st = ref.watch(settingsProvider);
    final accent = Color(st.accentColor);

    // Hold-LEFT (fixed speed): a compact badge in the upper third — NOT
    // centered, or it sits right on top of the play/skip controls.
    if (!isLadder) {
      return IgnorePointer(
        child: Align(
          alignment: const Alignment(0, -0.55),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              KivoIcon(KivoIcons.speed, size: 22, color: Colors.white),
              const SizedBox(width: 8),
              Text('${_fmtSpeed(speed)}x',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
            ]),
          ),
        ),
      );
    }

    // Hold-RIGHT (variable): detent meter on the LEFT edge + big centered readout.
    final detents = st.holdRightDetents;
    final idx = detents.indexWhere((d) => (d - speed).abs() < 1e-6);
    final lit = idx < 0 ? 0 : idx + 1;

    Widget seg(bool on) => Container(
          width: 22,
          height: 8,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: on ? accent : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(2.5),
          ),
        );

    final capsule = Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        KivoIcon(KivoIcons.speed, size: 26, color: Colors.white),
        const SizedBox(height: 12),
        for (var i = detents.length - 1; i >= 0; i--) seg(i < lit),
      ]),
    );

    return IgnorePointer(
      child: Stack(children: [
        Align(
          // Upper third, clear of the centered play/skip controls.
          alignment: const Alignment(0, -0.55),
          child: Text('${_fmtSpeed(speed)}x',
              style: TextStyle(color: accent, fontSize: 48, fontWeight: FontWeight.bold)),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(padding: const EdgeInsets.only(left: 20), child: capsule),
        ),
      ]),
    );
  }
}
