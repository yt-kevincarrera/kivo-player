import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/pip_controller_provider.dart';
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
    final l10n = context.l10n;
    return Row(
      children: [
        IconButton(
          color: Colors.white,
          tooltip: l10n.playerBackTooltip,
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
          tooltip: infoOn ? l10n.playerInfoOverlayHideTooltip : l10n.playerInfoOverlayShowTooltip,
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
              tooltip: l10n.playerSubtitlesTooltip,
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
        Consumer(
          builder: (context, ref, _) {
            final supported = ref.watch(pipSupportedProvider).value ?? false;
            if (!supported) return const SizedBox.shrink();
            return IconButton(
              color: Colors.white,
              tooltip: context.l10n.playerPipTooltip,
              icon: KivoIcon(KivoIcons.pip, size: 24, color: Colors.white),
              onPressed: () => ref.read(pipControllerProvider).enterNow(),
            );
          },
        ),
        Builder(
          builder: (context) => IconButton(
            color: Colors.white,
            tooltip: context.l10n.playerAudioTooltip,
            icon: KivoIcon(KivoIcons.audio, size: 24, color: Colors.white),
            onPressed: () => showAudioPicker(context, ref),
          ),
        ),
        Consumer(
          builder: (context, ref, _) {
            final sleep = ref.watch(sleepTimerProvider);
            final active = sleep != null;
            return IconButton(
              color: active ? accent : Colors.white,
              tooltip: context.l10n.playerMoreOptionsTooltip,
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
