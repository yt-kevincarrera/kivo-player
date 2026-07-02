import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/loop/ab_loop.dart';

/// Floating pill: tap cycles mark A → mark B → loop on → off. Long-press
/// while the loop runs opens the ±1s adjust popover (video stays visible —
/// every nudge seeks to the adjusted point so it can be verified live).
class AbLoopChip extends ConsumerStatefulWidget {
  const AbLoopChip({super.key});
  @override
  ConsumerState<AbLoopChip> createState() => _AbLoopChipState();
}

class _AbLoopChipState extends ConsumerState<AbLoopChip> {
  bool _popoverOpen = false;

  @override
  Widget build(BuildContext context) {
    final loop = ref.watch(abLoopProvider);
    if (loop == null) {
      if (_popoverOpen) _popoverOpen = false;
      return const SizedBox.shrink();
    }
    final n = ref.read(abLoopProvider.notifier);
    final active = loop.phase == AbLoopPhase.active;

    return TapRegion(
      onTapOutside: (_) {
        if (_popoverOpen) setState(() => _popoverOpen = false);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_popoverOpen && active) ...[
            _AdjustPopover(
              a: loop.a!,
              b: loop.b!,
              onNudgeA: n.nudgeA,
              onNudgeB: n.nudgeB,
            ),
            const SizedBox(height: 8),
          ],
          GestureDetector(
            onTap: () {
              if (_popoverOpen) {
                setState(() => _popoverOpen = false);
                return;
              }
              n.mark();
            },
            onLongPress: active ? () => setState(() => _popoverOpen = true) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: active ? KivoColors.gold.withValues(alpha: 0.16) : Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: active
                      ? KivoColors.gold
                      : KivoColors.gold.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.repeat_rounded,
                      size: 13, color: active ? KivoColors.gold : Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    switch (loop.phase) {
                      AbLoopPhase.armedA => 'Marcar A',
                      AbLoopPhase.armedB => 'Marcar B',
                      AbLoopPhase.active =>
                        '${fmtDuration(loop.a!)}–${fmtDuration(loop.b!)}',
                    },
                    style: TextStyle(
                      color: active ? KivoColors.gold : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (loop.phase == AbLoopPhase.armedB) ...[
                    const SizedBox(width: 6),
                    Text(
                      'A ${fmtDuration(loop.a!)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdjustPopover extends StatelessWidget {
  final Duration a;
  final Duration b;
  final void Function(int seconds) onNudgeA;
  final void Function(int seconds) onNudgeB;
  const _AdjustPopover({
    required this.a,
    required this.b,
    required this.onNudgeA,
    required this.onNudgeB,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xEB0A0E1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row('A', a, onNudgeA),
          const SizedBox(height: 6),
          _row('B', b, onNudgeB),
        ],
      ),
    );
  }

  Widget _row(String label, Duration ts, void Function(int) onNudge) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: KivoColors.gold.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(
                  color: KivoColors.gold, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 8),
        _StepBtn(label: '−1s', onTap: () => onNudge(-1)),
        Expanded(
          child: Text(
            fmtDuration(ts),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: KivoColors.gold,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        _StepBtn(label: '+1s', onTap: () => onNudge(1)),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _StepBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      );
}
