import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/engine/playback_provider.dart';
import '../../../player/open/video_source.dart';
import '../../../player/sleep/sleep_timer.dart';
import '../more/more_menu.dart';
import '../tracks/track_picker.dart';

class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentVideoProvider);
    final infoOn = ref.watch(settingsProvider).showInfoOverlay;
    final accent = Color(ref.watch(settingsProvider).accentColor);
    return Row(
      children: [
        IconButton(
          color: Colors.white,
          tooltip: 'Atrás',
          icon: KivoIcon(KivoIcons.back, size: 24, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Text(session?.displayName ?? 'Kivo',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
        IconButton(
          color: infoOn ? accent : Colors.white54,
          tooltip: infoOn ? 'Ocultar información en pantalla' : 'Mostrar información en pantalla',
          icon: KivoIcon(KivoIcons.info, size: 24, color: infoOn ? accent : Colors.white54),
          onPressed: () {
            final s = ref.read(settingsProvider);
            ref.read(settingsProvider.notifier).set(s.copyWith(showInfoOverlay: !s.showInfoOverlay));
          },
        ),
        Builder(
          builder: (context) {
            // Tint only when a subtitle track is actually active right now —
            // "mostrar por defecto" being on doesn't mean this video has one.
            final subsActive = ref.watch(currentSubtitleTrackProvider).valueOrNull != null;
            return IconButton(
              color: subsActive ? accent : Colors.white,
              tooltip: 'Subtítulos',
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  KivoIcon(KivoIcons.subtitles, size: 24, color: subsActive ? accent : Colors.white),
                  if (subsActive)
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
              onPressed: () => showSubtitlePicker(context, ref),
            );
          },
        ),
        // PiP lands in 3d — still disabled here.
        IconButton(color: Colors.white38, tooltip: 'Imagen en imagen', icon: KivoIcon(KivoIcons.pip, size: 24, opacity: 0.38), onPressed: null),
        Builder(
          builder: (context) => IconButton(
            color: Colors.white,
            tooltip: 'Audio',
            icon: KivoIcon(KivoIcons.audio, size: 24, color: Colors.white),
            onPressed: () => showAudioPicker(context, ref),
          ),
        ),
        Builder(
          builder: (context) {
            final sleep = ref.watch(sleepTimerProvider);
            final active = sleep != null;
            return IconButton(
              color: active ? accent : Colors.white,
              tooltip: 'Más opciones',
              icon: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KivoIcon(KivoIcons.more, size: active ? 20 : 24, color: active ? accent : Colors.white),
                  if (active)
                    Text(
                      fmtDuration(sleep.remaining),
                      style: TextStyle(
                        color: accent,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
              onPressed: () => showMoreMenu(context, ref),
            );
          },
        ),
      ],
    );
  }
}
