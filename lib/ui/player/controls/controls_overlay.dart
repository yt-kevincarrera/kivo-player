import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/background/audio_only.dart';
import '../loop/ab_loop_chip.dart';
import '../state/controls_visibility.dart';
import '../state/lock_state.dart';
import 'bottom_bar.dart';
import 'center_controls.dart';
import 'hold_to_unlock.dart';
import 'top_bar.dart';

class ControlsOverlay extends ConsumerWidget {
  const ControlsOverlay({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Audio-only behaves like a music player: controls never auto-hide and
    // the transport moves down to its own row so the center stays clear for
    // the waves/title.
    final audioOnly = ref.watch(audioOnlyProvider);
    final visible = ref.watch(controlsVisibleProvider) || audioOnly;
    final locked = ref.watch(lockProvider);
    final accent = Color(ref.watch(settingsProvider).accentColor);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: locked
          ? IgnorePointer(
              ignoring: !visible,
              child: Center(
                child: HoldToUnlock(
                  accent: accent,
                  onUnlock: () => ref.read(lockProvider.notifier).unlock(),
                ),
              ),
            )
          : Stack(children: [
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true, // never absorb taps — tap-to-hide must reach PlayerGestures
                  child: Container(
                      color: Colors.black.withValues(alpha: 0.22)),
                ),
              ),
              Listener(
                // Any touch on a control restarts the auto-hide timer so the
                // controls don't vanish while the user is interacting. Empty
                // areas hit no child (deferToChild) and fall through to
                // PlayerGestures' tap-to-hide.
                onPointerDown: (_) =>
                    ref.read(controlsVisibleProvider.notifier).show(),
                onPointerMove: (_) =>
                    ref.read(controlsVisibleProvider.notifier).show(),
                child: IgnorePointer(
                  ignoring: !visible,
                  child: Stack(
                  children: [
                    Positioned(
                      top: 0, left: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black54, Colors.transparent],
                          ),
                        ),
                        child: const SafeArea(bottom: false, child: TopBar()),
                      ),
                    ),
                    if (audioOnly)
                      // Music-player layout: transport above the bottom bar,
                      // scaled down so it reads as a row, not a hero.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 118,
                        child: Center(
                          child: Transform.scale(
                            scale: 0.82,
                            child: const CenterControls(),
                          ),
                        ),
                      )
                    else
                      const Center(child: CenterControls()),
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black87, Colors.transparent],
                          ),
                        ),
                        child: const SafeArea(top: false, child: BottomBar()),
                      ),
                    ),
                    const Positioned(
                      right: 14,
                      bottom: 116, // clear of the seek bar + button row
                      child: AbLoopChip(),
                    ),
                  ],
                ),
                ),
              ),
            ]),
    );
  }
}
