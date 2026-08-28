import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../player/open/video_source.dart';
import '../../../player/tracks/subtitle_delay.dart';
import '../../../player/tracks/subtitle_sync_controller.dart';

/// Whether the sync capsule is on screen. Opened from the ⋮ menu and from the
/// track picker; closes itself after [_idleTimeout].
class SubtitleSyncVisibleNotifier extends Notifier<bool> {
  @override
  bool build() {
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
    return false;
  }

  void show() => state = true;
  void hide() => state = false;
}

final subtitleSyncVisibleProvider =
    NotifierProvider<SubtitleSyncVisibleNotifier, bool>(
        SubtitleSyncVisibleNotifier.new);

const _idleTimeout = Duration(seconds: 3);

/// Top-centre because subtitles render at the bottom: the whole point is
/// watching the subtitle move while you nudge it, so the control must not sit
/// on top of it.
class SubtitleSyncHud extends ConsumerStatefulWidget {
  const SubtitleSyncHud({super.key});

  @override
  ConsumerState<SubtitleSyncHud> createState() => _SubtitleSyncHudState();
}

class _SubtitleSyncHudState extends ConsumerState<SubtitleSyncHud> {
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    // ref.listen fires on transitions only, never on the first build. The HUD
    // can perfectly well mount already visible, so arm the auto-hide here too
    // or nothing ever would.
    if (ref.read(subtitleSyncVisibleProvider)) _touch();
  }

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
      ref.read(subtitleSyncProvider.notifier).flush();
      ref.read(subtitleSyncVisibleProvider.notifier).hide();
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
    ref.listen<bool>(subtitleSyncVisibleProvider, (previous, next) {
      if (next) {
        _touch();
      } else {
        _cancelIdle();
      }
    });

    final visible = ref.watch(subtitleSyncVisibleProvider);
    if (!visible) {
      return const SizedBox.shrink();
    }

    final ms = ref.watch(subtitleSyncProvider);
    final accent = Color(ref.watch(settingsProvider.select((s) => s.accentColor)));
    final sync = ref.read(subtitleSyncProvider.notifier);

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
