import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../seek/seek_preview.dart';
import '../state/controls_visibility.dart';

final showRemainingProvider = StateProvider<bool>((ref) => false);

class _GrowingThumbShape extends SliderComponentShape {
  final Animation<double> anim; // 0 = rest, 1 = scrubbing
  final Color color;
  const _GrowingThumbShape(this.anim, this.color);

  @override
  Size getPreferredSize(bool enabled, bool isDiscrete) => const Size.fromRadius(11);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
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
    final maxMs = total.inMilliseconds == 0 ? 1.0 : total.inMilliseconds.toDouble();
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
    return Row(
      children: [
        Text(fmtDuration(shownPos), style: const TextStyle(color: Colors.white, fontSize: 12)),
        Expanded(
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
                value: shownPos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble(),
                activeColor: accent,
                inactiveColor: Colors.white24,
                onChanged: (v) {
                  final d = Duration(milliseconds: v.round());
                  ref.read(pendingSeekProvider.notifier).state = null; // new drag supersedes
                  ref.read(scrubProvider.notifier).state = d;
                  ref.read(controlsVisibleProvider.notifier).show();
                  ref.read(seekPreviewControllerProvider).request(d);
                },
                onChangeEnd: (v) {
                  final target = Duration(milliseconds: v.round());
                  ref.read(playerControllerProvider).seekTo(target);
                  ref.read(pendingSeekProvider.notifier).state = target; // hold slider until pos catches up
                  ref.read(scrubProvider.notifier).state = null; // hide the bubble
                  // Drop the last preview frame so the next scrub doesn't briefly
                  // flash the previous position's frame before the new one loads.
                  ref.read(seekPreviewFrameProvider.notifier).state = null;
                },
              ),
            ),
          ),
        ),
        GestureDetector(
          onTap: () => ref.read(showRemainingProvider.notifier).update((s) => !s),
          behavior: HitTestBehavior.opaque,
          child: Text(
            ref.watch(showRemainingProvider)
                ? '-${fmtDuration(total - shownPos < Duration.zero ? Duration.zero : total - shownPos)}'
                : fmtDuration(total),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
