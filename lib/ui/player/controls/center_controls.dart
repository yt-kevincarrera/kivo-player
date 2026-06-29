import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
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
          padding: const EdgeInsets.all(18),
          constraints: const BoxConstraints(minWidth: 68, minHeight: 68),
          splashRadius: 34,
          icon: KivoIcon(KivoIcons.replay10, size: 34, color: Colors.white),
          onPressed: () {
            ref.read(hudProvider.notifier).show(HudKind.seek, -1.0, '-${skip}s');
            ctrl.skipBy(-skip);
          },
        ),
        const SizedBox(width: 36),
        IconButton(
          key: const Key('kivo_play_pause'),
          iconSize: 56,
          color: Colors.white,
          icon: KivoIcon(playing ? KivoIcons.pause : KivoIcons.play, size: 56, color: Colors.white),
          onPressed: ctrl.togglePlayPause,
        ),
        const SizedBox(width: 36),
        IconButton(
          iconSize: 34,
          color: Colors.white,
          padding: const EdgeInsets.all(18),
          constraints: const BoxConstraints(minWidth: 68, minHeight: 68),
          splashRadius: 34,
          icon: KivoIcon(KivoIcons.forward10, size: 34, color: Colors.white),
          onPressed: () {
            ref.read(hudProvider.notifier).show(HudKind.seek, 1.0, '+${skip}s');
            ctrl.skipBy(skip);
          },
        ),
      ],
    );
  }
}
