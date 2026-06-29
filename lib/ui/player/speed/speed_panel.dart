import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/control/gesture_math.dart';
import '../../../player/control/player_controller.dart';

Future<void> showSpeedPanel(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: SpeedPanel(),
    ),
  );
}

class SpeedPanel extends ConsumerStatefulWidget {
  const SpeedPanel({super.key});
  @override
  ConsumerState<SpeedPanel> createState() => _SpeedPanelState();
}

class _SpeedPanelState extends ConsumerState<SpeedPanel> {
  @override
  Widget build(BuildContext context) {
    final rate = ref.watch(rateProvider);
    final st = ref.watch(settingsProvider);
    final ctrl = ref.read(playerControllerProvider);
    final detents = [...st.speedPresets, 3.0, 4.0];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: () => ctrl.setRate(round2(rate - st.speedFineStep)),
            ),
            Text('${rate.toStringAsFixed(2)}x',
                style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => ctrl.setRate(round2(rate + st.speedFineStep)),
            ),
          ],
        ),
        Slider(
          min: 0.25,
          max: st.holdRightMax,
          value: clampRate(rate, 0.25, st.holdRightMax),
          activeColor: KivoColors.gold,
          onChanged: (v) => ctrl.setRate(snapToDetent(v, detents, 0.04)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in st.speedPresets)
              ActionChip(label: Text('${p}x'), onPressed: () => ctrl.setRate(p)),
          ],
        ),
        const SizedBox(height: 12),
        TextButton(onPressed: () => ctrl.setRate(1.0), child: const Text('↺ Normal (1.0x)')),
      ],
    );
  }
}
