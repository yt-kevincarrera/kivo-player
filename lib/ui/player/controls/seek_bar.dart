import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/spoken.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../bookmarks/bookmark_marks_layer.dart';
import '../chapters/chapter_marks_layer.dart';
import '../loop/ab_range_layer.dart';
import '../seek/seek_preview.dart';
import '../state/controls_visibility.dart';

final showRemainingProvider = StateProvider<bool>((ref) => false);

class _GrowingThumbShape extends SliderComponentShape {
  final Animation<double> anim; // 0 = rest, 1 = scrubbing
  final Color color;
  const _GrowingThumbShape(this.anim, this.color);

  @override
  Size getPreferredSize(bool enabled, bool isDiscrete) =>
      const Size.fromRadius(11);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final radius = 7.0 + 4.0 * anim.value; // 7 → 11
    context.canvas.drawCircle(center, radius, Paint()..color = color);
  }
}

class SeekBar extends ConsumerStatefulWidget {
  const SeekBar({super.key});
  @override
  ConsumerState<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<SeekBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _thumbAnim;

  @override
  void initState() {
    super.initState();
    _thumbAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
  }

  @override
  void dispose() {
    _thumbAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final total = ref.watch(durationProvider).value ?? Duration.zero;
    final scrub = ref.watch(scrubProvider);
    final pending = ref.watch(pendingSeekProvider);
    final maxMs = total.inMilliseconds == 0
        ? 1.0
        : total.inMilliseconds.toDouble();
    // While dragging show the scrub target; just after release hold the
    // committed target until real playback position catches up; else live pos.
    final shownPos = scrub ?? pending ?? pos;

    // Drive thumb animation from scrub state.
    ref.listen(scrubProvider, (prev, next) {
      if (next != null) {
        _thumbAnim.forward();
      } else {
        _thumbAnim.reverse();
      }
    });

    // Clear the post-release hold once the player position reaches the target.
    ref.listen(positionProvider, (_, next) {
      final target = ref.read(pendingSeekProvider);
      if (target == null) return;
      final cur = next.value ?? Duration.zero;
      if ((cur - target).abs() < const Duration(milliseconds: 700)) {
        ref.read(pendingSeekProvider.notifier).state = null;
      }
    });
    final l10n = context.l10n;
    final remaining = total - shownPos < Duration.zero
        ? Duration.zero
        : total - shownPos;
    final showRemaining = ref.watch(showRemainingProvider);
    String spokenAt(Duration d) => l10n.playerSeekBarValue(
      spokenDuration(l10n, d, withSeconds: true),
      spokenDuration(l10n, total),
    );
    // A screen reader steps the bar by the same jump as the skip buttons —
    // the slider's own 5 % would be six minutes of a two-hour film.
    final step = Duration(
      seconds: ref.watch(settingsProvider).centerSkipSeconds,
    );
    final hasTotal = total > Duration.zero;
    void stepTo(Duration target) {
      ref.read(playerControllerProvider).seekTo(target);
      ref.read(pendingSeekProvider.notifier).state = target;
    }

    Duration clampTo(Duration d) =>
        d < Duration.zero ? Duration.zero : (d > total ? total : d);
    return Row(
      children: [
        ExcludeSemantics(
          child: Text(
            fmtDuration(shownPos),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(child: AbRangeLayer()),
              const Positioned.fill(child: ChapterMarksLayer()),
              const Positioned.fill(child: BookmarkMarksLayer()),
              Semantics(
                slider: true,
                label: l10n.playerSeekBarLabel,
                value: spokenAt(shownPos),
                // From what was just announced (a quick second swipe lands
                // one more step on), and held as the pending seek so the
                // value does not jump back until playback catches up. No
                // steps before the duration is known: they would all clamp
                // to 0 and restart the video.
                increasedValue: hasTotal
                    ? spokenAt(clampTo(shownPos + step))
                    : null,
                decreasedValue: hasTotal
                    ? spokenAt(clampTo(shownPos - step))
                    : null,
                onIncrease: hasTotal
                    ? () => stepTo(clampTo(shownPos + step))
                    : null,
                onDecrease: hasTotal
                    ? () => stepTo(clampTo(shownPos - step))
                    : null,
                excludeSemantics: true,
                child: AnimatedBuilder(
                  animation: _thumbAnim,
                  builder: (context, _) => SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: _GrowingThumbShape(_thumbAnim, accent),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      min: 0,
                      max: maxMs,
                      value: shownPos.inMilliseconds
                          .clamp(0, maxMs.toInt())
                          .toDouble(),
                      activeColor: accent,
                      inactiveColor: Colors.white24,
                      onChanged: (v) {
                        final d = Duration(milliseconds: v.round());
                        ref.read(pendingSeekProvider.notifier).state =
                            null; // new drag supersedes
                        ref.read(scrubProvider.notifier).state = d;
                        ref.read(controlsVisibleProvider.notifier).show();
                        ref.read(seekPreviewControllerProvider).request(d);
                      },
                      onChangeEnd: (v) {
                        final target = Duration(milliseconds: v.round());
                        ref.read(playerControllerProvider).seekTo(target);
                        ref.read(pendingSeekProvider.notifier).state =
                            target; // hold slider until pos catches up
                        ref.read(scrubProvider.notifier).state =
                            null; // hide the bubble
                        // Drop the last preview frame so the next scrub doesn't briefly
                        // flash the previous position's frame before the new one loads.
                        ref.read(seekPreviewFrameProvider.notifier).state =
                            null;
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Semantics(
          button: true,
          label: showRemaining
              ? l10n.playerRemainingTimeLabel(spokenDuration(l10n, remaining))
              : l10n.playerTotalTimeLabel(spokenDuration(l10n, total)),
          onTapHint: l10n.playerTimeToggleHint,
          onTap: () =>
              ref.read(showRemainingProvider.notifier).update((s) => !s),
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () =>
                ref.read(showRemainingProvider.notifier).update((s) => !s),
            behavior: HitTestBehavior.opaque,
            child: Text(
              showRemaining ? '-${fmtDuration(remaining)}' : fmtDuration(total),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}
