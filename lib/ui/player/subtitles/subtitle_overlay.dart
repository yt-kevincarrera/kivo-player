import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../player/engine/playback_provider.dart';
import '../../../player/subtitles/secondary_subtitle.dart';
import '../../../player/subtitles/subtitle_render.dart';
import '../../../player/subtitles/subtitle_render_controller.dart';
import '../state/controls_insets.dart';
import '../state/controls_visibility.dart';
import '../state/lock_state.dart';
import '../state/pip_state.dart';
import '../tracks/track_sync_hud.dart';
import 'subtitle_drag.dart';
import 'subtitle_text.dart';

/// Kivo's own subtitle layer, over the video and outside the zoom transform
/// (pinch-zoom enlarges the picture, not the words).
///
/// Draws the primary subtitle only while [SubtitleDrawer.kivo] owns it — when
/// mpv draws (pictures, styled ASS) this stays empty so they never double up.
/// The secondary subtitle is always Kivo's, at the top. Both step out of the
/// way of the control bars while those show, by the bars' measured height.
///
/// Takes no touches at all, so every player gesture works over the text too.
/// Moving a line is the gestures' job: a long press that lands on one (found
/// through [SubtitleHitTargets]) drives [subtitleDragProvider], and this
/// layer only shows it — following the finger, framed, with its percentage.
class SubtitleOverlay extends ConsumerWidget {
  const SubtitleOverlay({super.key});

  static const _move = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(playbackEngineProvider);
    final settings = ref.watch(settingsProvider);
    final drawer = ref.watch(subtitleDrawerProvider);
    final drag = ref.watch(subtitleDragProvider);
    final targets = ref.read(subtitleHitTargetsProvider);
    final locked = ref.watch(lockProvider);
    final pip = ref.watch(pipModeProvider);
    // Lift only for bars that are actually drawn: not while locked (only the
    // unlock ring shows), not under the sync panel, not in PiP. Lifting for
    // invisible bars moved the text exactly while it was being synced.
    final controls = controlsShouldRender(
          visible: ref.watch(controlsVisibleProvider),
          syncPanelOpen: ref.watch(syncHudProvider) != null,
        ) &&
        !locked &&
        !pip;
    // mpv reports the secondary text as unavailable once it is switched off,
    // and media_kit then keeps the last cue: only draw it while a secondary
    // track is really selected.
    ref.watch(secondarySubtitleRevisionProvider);
    final topInset = controls ? ref.watch(controlsTopInsetProvider) : 0.0;
    final bottomInset = controls ? ref.watch(controlsBottomInsetProvider) : 0.0;
    final accent = Color(settings.accentColor);

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

            Widget line(SubtitleLine which, String text) {
              final dragging = drag?.line == which;
              final margin = dragging
                  ? drag!.margin
                  : which == SubtitleLine.primary
                      ? settings.subtitleBottomMargin
                      : settings.secondarySubtitleTopMargin;
              final offset = size.height * margin / 100;
              return AnimatedPositioned(
                key: ValueKey(which),
                // Follows the finger exactly while held; eases otherwise.
                duration: dragging ? Duration.zero : _move,
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: which == SubtitleLine.secondary ? offset + topInset : null,
                bottom:
                    which == SubtitleLine.primary ? offset + bottomInset : null,
                child: Padding(
                  padding: side,
                  child: Center(
                    child: KeyedSubtree(
                      key: targets.keyOf(which),
                      child: _Grabbable(
                        dragging: dragging,
                        accent: accent,
                        percent: margin.round(),
                        above: which == SubtitleLine.primary,
                        child: SubtitleText(
                          key: Key(which == SubtitleLine.primary
                              ? 'subtitle-primary'
                              : 'subtitle-secondary'),
                          text: text,
                          settings: settings,
                          scale: scale,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            return Stack(
              children: [
                if (secondary.isNotEmpty) line(SubtitleLine.secondary, secondary),
                if (primary.isNotEmpty) line(SubtitleLine.primary, primary),
              ],
            );
          },
        );
      }),
    );
  }
}

/// While a line is held: an accent frame around it, slightly enlarged, and
/// its position as a percentage — the feedback that it is being moved.
class _Grabbable extends StatelessWidget {
  const _Grabbable({
    required this.dragging,
    required this.accent,
    required this.percent,
    required this.above,
    required this.child,
  });

  final bool dragging;
  final Color accent;
  final int percent;

  /// Where the percentage chip goes: above the primary, below the secondary,
  /// so it never runs off the screen edge.
  final bool above;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      key: const Key('subtitle-drag-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.7)),
      ),
      child: Text(
        context.l10n.playerTracksPositionValue(percent),
        style: TextStyle(
          color: accent,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    return AnimatedScale(
      scale: dragging ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dragging && above) ...[chip, const SizedBox(height: 6)],
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: dragging ? accent : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Padding(padding: const EdgeInsets.all(4), child: child),
          ),
          if (dragging && !above) ...[const SizedBox(height: 6), chip],
        ],
      ),
    );
  }
}
