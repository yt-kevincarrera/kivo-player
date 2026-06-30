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
    final maxMs = total.inMilliseconds == 0 ? 1.0 : total.inMilliseconds.toDouble();
    final shownPos = scrub ?? pos;
    return Row(
      children: [
        Text(fmtDuration(shownPos), style: const TextStyle(color: Colors.white, fontSize: 12)),
        Expanded(
          child: Slider(
            min: 0,
            max: maxMs,
            value: (scrub ?? pos).inMilliseconds.clamp(0, maxMs.toInt()).toDouble(),
            activeColor: accent,
            inactiveColor: Colors.white24,
            onChanged: (v) {
              final d = Duration(milliseconds: v.round());
              ref.read(scrubProvider.notifier).state = d;
              ref.read(controlsVisibleProvider.notifier).show();
              ref.read(seekPreviewControllerProvider).request(d);
            },
            onChangeEnd: (v) {
              ref.read(playerControllerProvider).seekTo(Duration(milliseconds: v.round()));
              ref.read(scrubProvider.notifier).state = null;
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
