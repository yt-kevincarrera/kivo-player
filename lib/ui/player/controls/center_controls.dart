import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../state/skip_feedback.dart';

class CenterControls extends ConsumerWidget {
  const CenterControls({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playingProvider).value ?? false;
    final ctrl = ref.read(playerControllerProvider);
    final skip = ref.watch(settingsProvider).centerSkipSeconds;
    final accent = Color(ref.watch(settingsProvider).accentColor);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          iconSize: 34,
          color: Colors.white,
          padding: const EdgeInsets.all(18),
          constraints: const BoxConstraints(minWidth: 68, minHeight: 68),
          splashRadius: 34,
          tooltip: 'Retroceder ${skip}s',
          icon: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              KivoIcon(KivoIcons.skipBack, size: 30, color: Colors.white),
              const SizedBox(height: 1),
              Text('${skip}s',
                  style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700, height: 1.0)),
            ],
          ),
          onPressed: () {
            ctrl.skipBy(-skip);
            ref.read(skipFeedbackProvider).bump(-skip);
          },
        ),
        const SizedBox(width: 36),
        IconButton(
          key: const Key('kivo_play_pause'),
          iconSize: 56,
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          style: IconButton.styleFrom(
            shape: CircleBorder(side: BorderSide(color: accent, width: 2)),
          ),
          tooltip: playing ? 'Pausar' : 'Reproducir',
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
          tooltip: 'Avanzar ${skip}s',
          icon: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              KivoIcon(KivoIcons.skipForward, size: 30, color: Colors.white),
              const SizedBox(height: 1),
              Text('${skip}s',
                  style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700, height: 1.0)),
            ],
          ),
          onPressed: () {
            ctrl.skipBy(skip);
            ref.read(skipFeedbackProvider).bump(skip);
          },
        ),
      ],
    );
  }
}
