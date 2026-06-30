import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
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

    final isCustomRate = !st.speedPresets.any((p) => (p - rate).abs() < 0.001);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RepeatButton(
              icon: KivoIcon(KivoIcons.minus, size: 24, color: Colors.white),
              onStep: () => ctrl.setRate(round2(rate - st.speedFineStep)),
            ),
            Text('${rate.toStringAsFixed(2)}x',
                style: const TextStyle(color: KivoColors.gold, fontSize: 40, fontWeight: FontWeight.bold)),
            _RepeatButton(
              icon: KivoIcon(KivoIcons.plus, size: 24, color: Colors.white),
              onStep: () => ctrl.setRate(round2(rate + st.speedFineStep)),
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
          alignment: WrapAlignment.center,
          children: [
            for (final p in st.speedPresets)
              GestureDetector(
                onTap: () => ctrl.setRate(p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: (p - rate).abs() < 0.001
                        ? KivoColors.gold.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.06),
                    border: Border.all(
                      color: (p - rate).abs() < 0.001 ? KivoColors.gold : Colors.white24,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${p}x',
                      style: TextStyle(
                        color: (p - rate).abs() < 0.001 ? KivoColors.gold : Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      )),
                ),
              ),
            if (isCustomRate)
              GestureDetector(
                onTap: () {
                  final next = [...st.speedPresets, round2(rate)]..sort();
                  ref.read(settingsProvider.notifier).set(st.copyWith(speedPresets: next));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: KivoColors.gold),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    KivoIcon(KivoIcons.plus, size: 16, color: KivoColors.gold),
                    const SizedBox(width: 4),
                    Text('Guardar ${round2(rate)}x',
                        style: const TextStyle(color: KivoColors.gold, fontWeight: FontWeight.w600, fontSize: 13)),
                  ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            style: TextButton.styleFrom(foregroundColor: KivoColors.gold),
            onPressed: () => ctrl.setRate(1.0),
            child: const Text('Restablecer (1x)'),
          ),
        ),
      ],
    );
  }
}

class _RepeatButton extends StatefulWidget {
  final Widget icon;
  final VoidCallback onStep;
  const _RepeatButton({required this.icon, required this.onStep});
  @override
  State<_RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<_RepeatButton> {
  Timer? _timer;

  void _start() {
    // Fire first step immediately on long-press recognition
    widget.onStep();
    // Start repeating: begin slow, accelerate each tick until floor
    var interval = 300;
    void schedule() {
      _timer = Timer(Duration(milliseconds: interval), () {
        if (!mounted) return;
        widget.onStep();
        if (interval > 70) {
          interval = (interval * 0.80).round().clamp(70, 300);
        }
        schedule();
      });
    }
    schedule();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: widget.onStep,
        onLongPress: _start,
        onLongPressUp: _stop,
        onLongPressCancel: _stop,
        child: Padding(padding: const EdgeInsets.all(12), child: widget.icon),
      );
}
