import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../state/hud_state.dart';

class CenterControls extends ConsumerWidget {
  const CenterControls({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playingProvider).value ?? false;
    final ctrl = ref.read(playerControllerProvider);
    final skip = ref.watch(settingsProvider).centerSkipSeconds;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          iconSize: 34,
          color: Colors.white,
          icon: const Icon(Icons.replay_10),
          onPressed: () {
            ref.read(hudProvider.notifier).show(HudKind.seek, -1.0, '-${skip}s');
            ctrl.skipBy(-skip);
          },
        ),
        const SizedBox(width: 36),
        IconButton(
          iconSize: 56,
          color: Colors.white,
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: ctrl.togglePlayPause,
        ),
        const SizedBox(width: 36),
        IconButton(
          iconSize: 34,
          color: Colors.white,
          icon: const Icon(Icons.forward_10),
          onPressed: () {
            ref.read(hudProvider.notifier).show(HudKind.seek, 1.0, '+${skip}s');
            ctrl.skipBy(skip);
          },
        ),
      ],
    );
  }
}
