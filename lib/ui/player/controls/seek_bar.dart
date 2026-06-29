import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';

String fmtDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

class SeekBar extends ConsumerWidget {
  const SeekBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            activeColor: KivoColors.gold,
            inactiveColor: Colors.white24,
            onChanged: (v) =>
                ref.read(playerControllerProvider).seekTo(Duration(milliseconds: v.round())),
          ),
        ),
        Text(fmtDuration(total), style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}
