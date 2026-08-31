import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/open/video_source.dart';
import '../../../player/tracks/subtitle_delay.dart';
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

final syncHudProvider =
    NotifierProvider<SyncHudNotifier, SyncTarget?>(SyncHudNotifier.new);

const _idleTimeout = Duration(seconds: 3);

/// Top-centre because subtitles render at the bottom: the whole point is
/// watching the subtitle move while you nudge it, so the control must not sit
/// on top of it.
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
    final accent = Color(ref.watch(settingsProvider.select((s) => s.accentColor)));
    final sync = _notifierFor(target);

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
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
                const SizedBox(width: 12),
                _StepButton(
                  key: const ValueKey('subtitle-sync-minus'),
                  glyph: '−',
                  onStep: () {
                    sync.nudge(-1);
                    _touch();
                  },
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  key: const ValueKey('subtitle-sync-value'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    sync.reset();
                    _touch();
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatSubtitleDelay(ms),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 5),
                      _Meter(delayMs: ms, accent: accent),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _StepButton(
                  key: const ValueKey('subtitle-sync-plus'),
                  glyph: '+',
                  onStep: () {
                    sync.nudge(1);
                    _touch();
                  },
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
            color:
                active ? onAccent(accent) : Colors.white.withValues(alpha: 0.55),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Long-press repeats, so lining up a two-second offset is one gesture.
class _StepButton extends StatefulWidget {
  const _StepButton({super.key, required this.glyph, required this.onStep});
  final String glyph;
  final VoidCallback onStep;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  Timer? _repeat;

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onStep,
      onLongPressStart: (_) {
        widget.onStep();
        _repeat = Timer.periodic(
            const Duration(milliseconds: 90), (_) => widget.onStep());
      },
      onLongPressEnd: (_) => _stopRepeat(),
      onLongPressCancel: _stopRepeat,
      child: SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: Text(widget.glyph,
              style: const TextStyle(color: Colors.white, fontSize: 18)),
        ),
      ),
    );
  }
}

/// Kivo's signature meter, lit outward from a brighter centre tick.
class _Meter extends StatelessWidget {
  const _Meter({required this.delayMs, required this.accent});
  final int delayMs;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final m = subtitleMeter(delayMs);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < subtitleDelaySegments; i++)
          Container(
            width: 5,
            height: i == m.centerIndex ? 9 : 5,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            color: i == m.centerIndex
                ? (delayMs == 0
                    ? Colors.white.withValues(alpha: 0.42)
                    : accent)
                : (i >= m.firstLit && i <= m.lastLit
                    ? accent
                    : Colors.white.withValues(alpha: 0.18)),
          ),
      ],
    );
  }
}
