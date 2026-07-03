import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/background/audio_only.dart';
import '../../../player/control/player_controller.dart';
import '../speed/speed_panel.dart';
import '../state/controls_visibility.dart';
import '../state/aspect_state.dart';
import '../state/flash_state.dart';
import '../state/lock_state.dart';
import '../state/orientation_state.dart';
import 'seek_bar.dart';
import '../seek/seek_preview_bubble.dart';

class BottomBar extends ConsumerWidget {
  const BottomBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final rate = ref.watch(rateProvider);
    final mode = ref.watch(aspectModeProvider);
    // In "Solo audio" there's no video, so aspect-ratio and rotation controls
    // are meaningless — hide them (and the player is locked to portrait).
    final audioOnly = ref.watch(audioOnlyProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Stack(
          clipBehavior: Clip.none,
          children: [
            SeekBar(),
            Positioned(
              left: 0, right: 0, bottom: 28, // sit above the bar
              child: SeekPreviewBubble(),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Tooltip(
              message: 'Velocidad',
              child: TextButton(
                onPressed: () => showSpeedPanel(context),
                child: Text('${rate.toStringAsFixed(2)}x',
                    style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
              ),
            ),
            IconButton(
              color: Colors.white,
              tooltip: 'Bloquear pantalla',
              icon: KivoIcon(KivoIcons.lock, size: 24, color: Colors.white),
              onPressed: () {
                ref.read(lockProvider.notifier).lock();
                ref.read(controlsVisibleProvider.notifier).hide();
              },
            ),
            if (!audioOnly) ...[
              IconButton(
                color: Colors.white,
                tooltip: 'Relación de aspecto',
                icon: KivoIcon(aspectIconFor(mode), size: 24, color: Colors.white),
                onPressed: () {
                  ref.read(aspectModeProvider.notifier).cycle();
                  ref.read(flashProvider.notifier).show(aspectLabelFor(ref.read(aspectModeProvider)));
                },
              ),
              IconButton(
                color: Colors.white,
                tooltip: 'Rotar',
                icon: KivoIcon(KivoIcons.rotate, size: 24, color: Colors.white),
                onPressed: () => ref.read(orientationProvider.notifier).cycle(),
              ),
            ],
            IconButton(
              color: audioOnly ? accent : Colors.white,
              tooltip: audioOnly ? 'Ver video' : 'Solo audio',
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  KivoIcon(KivoIcons.audioOnly,
                      size: 24, color: audioOnly ? accent : Colors.white),
                  if (audioOnly)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
              onPressed: () => ref.read(audioOnlyProvider.notifier).toggle(),
            ),
          ],
        ),
      ],
    );
  }
}
