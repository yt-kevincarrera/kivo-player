import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/open/video_source.dart';
import '../../../player/tracks/track_delay.dart';
import '../../../player/tracks/track_delay_controller.dart';

/// Which stream the sync capsule is currently adjusting.
enum SyncTarget { subtitles, audio }

/// Which target the sync capsule is showing, or null when it is off screen.
///
/// Visibility and target are one value rather than two providers: they cannot
/// then disagree about whether an open capsule is adjusting anything.
/// Opened from the ⋮ menu and from either track picker; closes itself after
/// [_idleTimeout].
class SyncHudNotifier extends Notifier<SyncTarget?> {
  @override
  SyncTarget? build() {
    // Scoped to the video that is open, so leaving the player, minimizing, or
    // advancing to the next video always puts the capsule away. Without it the
    // flag survives a PlayerScreen teardown and the HUD mounts visible on the
    // next video with no side-effect-free way out — its only other exits (±
    // and the value tap) change the user's subtitle timing.
    //
    // Done here rather than from _PlayerScreenState.dispose(): `ref` is
    // off-limits in dispose() in this codebase, and this keeps the lifetime
    // rule next to the state it governs — the same shape SubtitleSyncNotifier
    // already uses to reset its own value per video.
    ref.watch(currentVideoProvider);
    return null;
  }

  void show(SyncTarget target) => state = target;
  void hide() => state = null;
}

final syncHudProvider = NotifierProvider<SyncHudNotifier, SyncTarget?>(
  SyncHudNotifier.new,
);

/// Longer than a capsule would need: this is a panel you drag, compare against
/// the subtitle, and adjust again. Three seconds closed it mid-task.
const _idleTimeout = Duration(seconds: 8);

/// Sits just above the subtitle line: the point is to watch the subtitle move
/// while you drag, so the panel must clear it without perching out of thumb
/// reach at the top of the screen.
class TrackSyncHud extends ConsumerStatefulWidget {
  const TrackSyncHud({super.key});

  @override
  ConsumerState<TrackSyncHud> createState() => _TrackSyncHudState();
}

class _TrackSyncHudState extends ConsumerState<TrackSyncHud> {
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    // ref.listen fires on transitions only, never on the first build. The HUD
    // can perfectly well mount already visible, so arm the auto-hide here too
    // or nothing ever would.
    if (ref.read(syncHudProvider) != null) _touch();
  }

  /// The notifier for whichever stream the capsule is adjusting right now.
  TrackDelayNotifier _notifierFor(SyncTarget target) =>
      target == SyncTarget.subtitles
      ? ref.read(subtitleSyncProvider.notifier)
      : ref.read(audioSyncProvider.notifier);

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  // Arms (or re-arms) the auto-hide timer. Driven from ref.listen and from
  // user interaction, never from build() itself — a Timer created straight
  // out of build would get re-armed on every unrelated rebuild and could fire
  // after the widget is torn down mid-frame.
  void _touch() {
    _idle?.cancel();
    _idle = Timer(_idleTimeout, () {
      if (!mounted) return;
      // Push the last nudge through before the capsule goes away.
      final target = ref.read(syncHudProvider);
      if (target != null) _notifierFor(target).flush();
      ref.read(syncHudProvider.notifier).hide();
    });
  }

  void _cancelIdle() {
    _idle?.cancel();
    _idle = null;
  }

  @override
  Widget build(BuildContext context) {
    // React to visibility changes as a side effect, not as part of the build
    // itself: arm the idle timer when the HUD opens, cancel it when it closes
    // (whether that close came from us or from elsewhere).
    ref.listen<SyncTarget?>(syncHudProvider, (previous, next) {
      if (next != null) {
        _touch();
      } else {
        _cancelIdle();
      }
    });

    final target = ref.watch(syncHudProvider);
    if (target == null) {
      return const SizedBox.shrink();
    }

    final ms = target == SyncTarget.subtitles
        ? ref.watch(subtitleSyncProvider)
        : ref.watch(audioSyncProvider);
    final accent = Color(
      ref.watch(settingsProvider.select((s) => s.accentColor)),
    );
    final sync = _notifierFor(target);

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        // Clears the subtitle line beneath it: the point is still to watch the
        // subtitle move while you drag, so the panel sits above it rather than
        // on it. Higher than the old capsule's top perch, which the user found
        // both awkward to reach and easy to miss.
        child: Padding(
          padding: const EdgeInsets.only(bottom: 68),
          child: Container(
            width: 280,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.86),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TargetToggle(
                  target: target,
                  accent: accent,
                  onChanged: (t) {
                    ref.read(syncHudProvider.notifier).show(t);
                    _touch();
                  },
                ),
                const SizedBox(height: 10),
                // Value above, buttons below: a thumb on the − / + never
                // covers the number it is changing.
                Text(
                  formatDelay(ms),
                  key: const ValueKey('subtitle-sync-value'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    letterSpacing: 0.5,
                    height: 1.1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 12),
                _DragBar(
                  key: const ValueKey('sync-drag-bar'),
                  delayMs: ms,
                  accent: accent,
                  onDelay: (v) {
                    sync.setTo(v);
                    _touch();
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'arrastra la barra o usa los botones',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _PanelButton(
                      key: const ValueKey('subtitle-sync-minus'),
                      glyph: '−',
                      repeats: true,
                      onStep: () {
                        sync.nudge(-1);
                        _touch();
                      },
                    ),
                    // Resets only the side that is showing — `sync` is already
                    // the active notifier, so each tab gets its own reset for
                    // free.
                    _PanelButton(
                      key: const ValueKey('sync-reset'),
                      glyph: '⟲',
                      quiet: true,
                      onStep: () {
                        sync.reset();
                        _touch();
                      },
                    ),
                    _PanelButton(
                      key: const ValueKey('subtitle-sync-plus'),
                      glyph: '+',
                      repeats: true,
                      onStep: () {
                        sync.nudge(1);
                        _touch();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The `Sub | Audio` switch inside the capsule. Both offsets are per-video and
/// independent, so this only chooses which one the − / + are moving.
class _TargetToggle extends StatelessWidget {
  const _TargetToggle({
    required this.target,
    required this.accent,
    required this.onChanged,
  });

  final SyncTarget target;
  final Color accent;
  final ValueChanged<SyncTarget> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TargetChip(
            key: const ValueKey('sync-target-subtitles'),
            label: 'Sub',
            active: target == SyncTarget.subtitles,
            accent: accent,
            onTap: () => onChanged(SyncTarget.subtitles),
          ),
          _TargetChip(
            key: const ValueKey('sync-target-audio'),
            label: 'Audio',
            active: target == SyncTarget.audio,
            accent: accent,
            onTap: () => onChanged(SyncTarget.audio),
          ),
        ],
      ),
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({
    super.key,
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: active ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? onAccent(accent)
                : Colors.white.withValues(alpha: 0.55),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A 46-px target — over the 44-px guideline, because the old 30-px buttons
/// were reported as easy to miss with big thumbs.
///
/// [repeats] gives the − / + long-press auto-repeat, so lining up a
/// two-second offset is one gesture. The reset button does not repeat: there
/// is nothing to repeat towards.
class _PanelButton extends StatefulWidget {
  const _PanelButton({
    super.key,
    required this.glyph,
    required this.onStep,
    this.repeats = false,
    this.quiet = false,
  });

  final String glyph;
  final VoidCallback onStep;
  final bool repeats;

  /// Reads as secondary to the − / + it sits between.
  final bool quiet;

  @override
  State<_PanelButton> createState() => _PanelButtonState();
}

class _PanelButtonState extends State<_PanelButton> {
  Timer? _repeat;

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onStep,
      onLongPressStart: widget.repeats
          ? (_) {
              widget.onStep();
              _repeat = Timer.periodic(
                const Duration(milliseconds: 90),
                (_) => widget.onStep(),
              );
            }
          : null,
      onLongPressEnd: widget.repeats ? (_) => _stopRepeat() : null,
      onLongPressCancel: widget.repeats ? _stopRepeat : null,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: widget.quiet ? 0.05 : 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            widget.glyph,
            style: TextStyle(
              color: widget.quiet
                  ? Colors.white.withValues(alpha: 0.7)
                  : Colors.white,
              fontSize: widget.quiet ? 17 : 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// Kivo's signature segmented meter, promoted from a readout to the control:
/// the whole width is draggable, and the lit segment furthest from centre is
/// the thumb.
class _DragBar extends StatelessWidget {
  const _DragBar({
    super.key,
    required this.delayMs,
    required this.accent,
    required this.onDelay,
  });

  final int delayMs;
  final Color accent;
  final ValueChanged<int> onDelay;

  void _report(double dx, double width) {
    if (width <= 0) return;
    onDelay(delayFromDragFraction(dx / width));
  }

  @override
  Widget build(BuildContext context) {
    final m = delayMeter(delayMs);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _report(d.localPosition.dx, width),
          onHorizontalDragStart: (d) => _report(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _report(d.localPosition.dx, width),
          child: SizedBox(
            // Taller than the segments so the whole strip is grabbable, not
            // just the 8 px of painted bar.
            height: 34,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < trackDelaySegments; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: _Segment(
                        index: i,
                        meter: m,
                        delayMs: delayMs,
                        accent: accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.index,
    required this.meter,
    required this.delayMs,
    required this.accent,
  });

  final int index;
  final DelayMeter meter;
  final int delayMs;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final lit = index >= meter.firstLit && index <= meter.lastLit;
    final isCentre = index == meter.centerIndex;
    // The outermost lit segment reads as the thumb — it is where the finger
    // conceptually is, so it gets the full height.
    final isThumb =
        delayMs != 0 && index == (delayMs > 0 ? meter.lastLit : meter.firstLit);

    final height = isThumb
        ? 22.0
        : isCentre
        ? 14.0
        : 8.0;

    final color = isCentre && delayMs == 0
        ? Colors.white.withValues(alpha: 0.45)
        : lit
        ? accent
        : Colors.white.withValues(alpha: 0.18);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: isThumb ? BorderRadius.circular(2) : null,
      ),
    );
  }
}
