import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../seek/seek_preview.dart';
import '../state/controls_visibility.dart';

final showRemainingProvider = StateProvider<bool>((ref) => false);

class SeekBar extends ConsumerWidget {
  const SeekBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final total = ref.watch(durationProvider).value ?? Duration.zero;
    final scrub = ref.watch(scrubProvider);
    final pending = ref.watch(pendingSeekProvider);
    final maxMs = total.inMilliseconds == 0 ? 1.0 : total.inMilliseconds.toDouble();
    // While dragging show the scrub target; just after release hold the
    // committed target until real playback position catches up; else live pos.
    final shownPos = scrub ?? pending ?? pos;

    // Clear the post-release hold once the player position reaches the target.
    ref.listen(positionProvider, (_, next) {
      final target = ref.read(pendingSeekProvider);
      if (target == null) return;
      final cur = next.value ?? Duration.zero;
      if ((cur - target).abs() < const Duration(milliseconds: 700)) {
        ref.read(pendingSeekProvider.notifier).state = null;
      }
    });
    return Row(
      children: [
        Text(fmtDuration(shownPos), style: const TextStyle(color: Colors.white, fontSize: 12)),
        Expanded(
          child: Slider(
            min: 0,
            max: maxMs,
            value: shownPos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble(),
            activeColor: accent,
            inactiveColor: Colors.white24,
            onChanged: (v) {
              final d = Duration(milliseconds: v.round());
              ref.read(pendingSeekProvider.notifier).state = null; // new drag supersedes
              ref.read(scrubProvider.notifier).state = d;
              ref.read(controlsVisibleProvider.notifier).show();
              ref.read(seekPreviewControllerProvider).request(d);
            },
            onChangeEnd: (v) {
              final target = Duration(milliseconds: v.round());
              ref.read(playerControllerProvider).seekTo(target);
              ref.read(pendingSeekProvider.notifier).state = target; // hold slider until pos catches up
              ref.read(scrubProvider.notifier).state = null; // hide the bubble
              // Drop the last preview frame so the next scrub doesn't briefly
              // flash the previous position's frame before the new one loads.
              ref.read(seekPreviewFrameProvider.notifier).state = null;
            },
          ),
        ),
        GestureDetector(
          onTap: () => ref.read(showRemainingProvider.notifier).update((s) => !s),
          behavior: HitTestBehavior.opaque,
          child: Text(
            ref.watch(showRemainingProvider)
                ? '-${fmtDuration(total - shownPos < Duration.zero ? Duration.zero : total - shownPos)}'
                : fmtDuration(total),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
