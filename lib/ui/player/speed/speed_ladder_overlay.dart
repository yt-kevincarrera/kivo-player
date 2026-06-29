import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
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
    final steps = [for (var i = 5; i >= 0; i--) ladderSpeed(i / 5, st.holdRightMin, st.holdRightMax, 6)];
    return IgnorePointer(
      child: Stack(
        children: [
          Align(
            alignment: Alignment.center,
            child: Text('${speed.toStringAsFixed(1)}x',
                style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: steps.map((v) {
                  final active = (v - speed).abs() < 0.3;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? KivoColors.gold.withValues(alpha: 0.3) : Colors.black54,
                      border: Border.all(color: active ? KivoColors.gold : Colors.white24),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${v.toStringAsFixed(1)}x',
                        style: TextStyle(color: active ? Colors.white : Colors.white70, fontSize: 12)),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
