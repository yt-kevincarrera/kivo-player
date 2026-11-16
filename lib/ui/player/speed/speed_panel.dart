import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../l10n/l10n.dart';
import '../../../player/control/gesture_math.dart';
import '../../../player/control/player_controller.dart';
import '../../widgets/kivo_focusable.dart';
import '../../tv/tv_modal.dart';
import '../../tv/tv_panel.dart';
import '../../../platform/television_provider.dart';

Future<void> showSpeedPanel(BuildContext context) {
  if (ProviderScope.containerOf(
    context,
    listen: false,
  ).read(isTelevisionProvider)) {
    return showTvPanel<void>(
      context: context,
      title: context.l10n.playerSpeedTooltip,
      builder: (_) => const _TvSpeedPanel(),
    );
  }

  return showTvAwareBottomSheet(
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

class _TvSpeedPanel extends ConsumerWidget {
  const _TvSpeedPanel();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rate = ref.watch(rateProvider);
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(playerControllerProvider);
    final rates = {
      0.25,
      0.5,
      0.75,
      1.0,
      1.25,
      1.5,
      2.0,
      3.0,
      4.0,
      ...settings.speedPresets,
      rate,
    }.where((v) => v <= settings.holdRightMax).toList()..sort();
    return ListView(
      padding: const EdgeInsets.all(5),
      children: [
        Row(
          children: [
            Expanded(
              child: TvOptionRow(
                label: '−${settings.speedFineStep}×',
                onPressed: () =>
                    controller.setRate(round2(rate - settings.speedFineStep)),
              ),
            ),
            Expanded(
              child: TvOptionRow(
                label: '+${settings.speedFineStep}×',
                onPressed: () =>
                    controller.setRate(round2(rate + settings.speedFineStep)),
              ),
            ),
          ],
        ),
        for (final value in rates)
          TvOptionRow(
            label: '${value.toStringAsFixed(2)}×',
            selected: (value - rate).abs() < .005,
            autofocus: (value - rate).abs() < .005,
            onPressed: () => controller.setRate(value),
          ),
        if (!settings.speedPresets.any((p) => (p - round2(rate)).abs() < .005))
          TvOptionRow(
            label: context.l10n.tvSaveSpeedPreset,
            value: '${round2(rate)}×',
            icon: Icons.add,
            onPressed: () {
              final latest = ref.read(settingsProvider);
              final presets = {...latest.speedPresets, round2(rate)}.toList()
                ..sort();
              ref
                  .read(settingsProvider.notifier)
                  .set(latest.copyWith(speedPresets: presets));
            },
          ),
      ],
    );
  }
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
    final accent = Color(st.accentColor);
    final ctrl = ref.read(playerControllerProvider);
    final detents = [...st.speedPresets, 3.0, 4.0];

    // Compare against the value we'd actually save (round2) at half the 0.01
    // rounding granularity, so a near-duplicate rate can't surface the chip.
    final isCustomRate = !st.speedPresets.any(
      (p) => (p - round2(rate)).abs() < 0.005,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
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
            Text(
              '${rate.toStringAsFixed(2)}x',
              style: TextStyle(
                color: accent,
                fontSize: 40,
                fontWeight: FontWeight.bold,
              ),
            ),
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
          activeColor: accent,
          onChanged: (v) => ctrl.setRate(snapToDetent(v, detents, 0.04)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final p in st.speedPresets)
              FocusableTap(
                onTap: () => ctrl.setRate(p),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: (p - rate).abs() < 0.001
                        ? accent.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.06),
                    border: Border.all(
                      color: (p - rate).abs() < 0.001 ? accent : Colors.white24,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${p}x',
                    style: TextStyle(
                      color: (p - rate).abs() < 0.001 ? accent : Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            if (isCustomRate)
              FocusableTap(
                onTap: () {
                  final next = {...st.speedPresets, round2(rate)}.toList()
                    ..sort();
                  ref
                      .read(settingsProvider.notifier)
                      .set(st.copyWith(speedPresets: next));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: accent),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KivoIcon(KivoIcons.plus, size: 16, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        context.l10n.playerSpeedSavePreset(
                          round2(rate).toString(),
                        ),
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            style: TextButton.styleFrom(foregroundColor: accent),
            onPressed: () => ctrl.setRate(1.0),
            child: Text(context.l10n.playerSpeedResetAction),
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
  Widget build(BuildContext context) => FocusableTap(
    onTap: widget.onStep,
    onLongPress: _start,
    onLongPressUp: _stop,
    onLongPressCancel: _stop,
    child: Padding(padding: const EdgeInsets.all(12), child: widget.icon),
  );
}
