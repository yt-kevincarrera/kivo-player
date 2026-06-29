import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/control/gesture_math.dart';

final holdSpeedProvider = StateProvider<double?>((ref) => null);

double holdRightSpeedFor(double localY, double height, double min, double max) =>
    ladderSpeed(height <= 0 ? 0 : (1 - (localY / height)).clamp(0.0, 1.0), min, max, 6);

class SpeedLadderOverlay extends ConsumerWidget {
  const SpeedLadderOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(holdSpeedProvider);
    if (speed == null) return const SizedBox.shrink();
    final st = ref.watch(settingsProvider);
    final accent = Color(st.accentColor);
    final min = st.holdRightMin, max = st.holdRightMax;
    final fill = max <= min ? 0.0 : ((speed - min) / (max - min)).clamp(0.0, 1.0);
    const segCount = 16;
    final lit = (fill * segCount).round();

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KivoIcon(KivoIcons.speed, size: 26, color: Colors.white),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [for (var i = segCount - 1; i >= 0; i--) seg(i < lit)],
            ),
          ),
        ],
      ),
    );

    return IgnorePointer(
      child: Stack(
        children: [
          Align(
            alignment: Alignment.center,
            child: Text('${speed.toStringAsFixed(1)}x',
                style: TextStyle(color: accent, fontSize: 48, fontWeight: FontWeight.bold)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: capsule,
            ),
          ),
        ],
      ),
    );
  }
}
