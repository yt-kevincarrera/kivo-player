import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../state/controls_visibility.dart';

final showRemainingProvider = StateProvider<bool>((ref) => false);

class SeekBar extends ConsumerWidget {
  const SeekBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final total = ref.watch(durationProvider).value ?? Duration.zero;
    final maxMs = total.inMilliseconds == 0 ? 1.0 : total.inMilliseconds.toDouble();
    return Row(
      children: [
        Text(fmtDuration(pos), style: const TextStyle(color: Colors.white, fontSize: 12)),
        Expanded(
          child: Slider(
            min: 0,
            max: maxMs,
            value: pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble(),
            activeColor: accent,
            inactiveColor: Colors.white24,
            onChanged: (v) {
              ref.read(playerControllerProvider).seekTo(Duration(milliseconds: v.round()));
              ref.read(controlsVisibleProvider.notifier).show();
            },
          ),
        ),
        GestureDetector(
          onTap: () => ref.read(showRemainingProvider.notifier).update((v) => !v),
          behavior: HitTestBehavior.opaque,
          child: Text(
            ref.watch(showRemainingProvider)
                ? '-${fmtDuration(total - pos < Duration.zero ? Duration.zero : total - pos)}'
                : fmtDuration(total),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
