import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../player/engine/playback_provider.dart';
import '../../../player/subtitles/subtitle_render.dart';
import '../../../player/subtitles/subtitle_render_controller.dart';
import '../state/controls_insets.dart';
import '../../../player/subtitles/secondary_subtitle.dart';
import '../state/controls_visibility.dart';
import '../state/lock_state.dart';
import '../state/pip_state.dart';
import '../tracks/track_sync_hud.dart';
import 'subtitle_text.dart';

/// Kivo's own subtitle layer, over the video and outside the zoom transform
/// (pinch-zoom enlarges the picture, not the words).
///
/// Draws the primary subtitle only while [SubtitleDrawer.kivo] owns it — when
/// mpv draws (pictures, styled ASS) this stays empty so they never double up.
/// The secondary subtitle is always Kivo's, at the top. Both step out of the
/// way of the control bars while those show, by the bars' measured height.
class SubtitleOverlay extends ConsumerWidget {
  const SubtitleOverlay({super.key});

  static const _move = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(playbackEngineProvider);
    final settings = ref.watch(settingsProvider);
    final drawer = ref.watch(subtitleDrawerProvider);
    // Lift only for bars that are actually drawn: not while locked (only the
    // unlock ring shows), not under the sync panel, not in PiP. Lifting for
    // invisible bars moved the text exactly while it was being synced.
    final controls = controlsShouldRender(
          visible: ref.watch(controlsVisibleProvider),
          syncPanelOpen: ref.watch(syncHudProvider) != null,
        ) &&
        !ref.watch(lockProvider) &&
        !ref.watch(pipModeProvider);
    // mpv reports the secondary text as unavailable once it is switched off,
    // and media_kit then keeps the last cue: only draw it while a secondary
    // track is really selected.
    ref.watch(secondarySubtitleRevisionProvider);
    final topInset = controls ? ref.watch(controlsTopInsetProvider) : 0.0;
    final bottomInset = controls ? ref.watch(controlsBottomInsetProvider) : 0.0;

    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        final size = box.biggest;
        final scale = subtitleScaleFor(size);
        return StreamBuilder<List<String>>(
          stream: engine.subtitleTextStream,
          initialData: engine.currentSubtitleText,
          builder: (context, snap) {
            final lines = snap.data ?? const ['', ''];
            final primary = drawer == SubtitleDrawer.kivo && lines.isNotEmpty
                ? lines[0].trim()
                : '';
            // Read per text event, not once per build: the per-open pick sets
            // it without any provider changing.
            final secondaryOn = engine.secondarySubtitleTrackId != null;
            final secondary =
                secondaryOn && lines.length > 1 ? lines[1].trim() : '';
            final side = EdgeInsets.symmetric(horizontal: 16 * scale);
            return Stack(
              children: [
                if (secondary.isNotEmpty)
                  AnimatedPositioned(
                    duration: _move,
                    curve: Curves.easeOut,
                    left: 0,
                    right: 0,
                    top: size.height * settings.secondarySubtitleTopMargin / 100 +
                        topInset,
                    child: Padding(
                      padding: side,
                      child: Center(
                        child: SubtitleText(
                          key: const Key('subtitle-secondary'),
                          text: secondary,
                          settings: settings,
                          scale: scale,
                        ),
                      ),
                    ),
                  ),
                if (primary.isNotEmpty)
                  AnimatedPositioned(
                    duration: _move,
                    curve: Curves.easeOut,
                    left: 0,
                    right: 0,
                    bottom: size.height * settings.subtitleBottomMargin / 100 +
                        bottomInset,
                    child: Padding(
                      padding: side,
                      child: Center(
                        child: SubtitleText(
                          key: const Key('subtitle-primary'),
                          text: primary,
                          settings: settings,
                          scale: scale,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      }),
    );
  }
}
