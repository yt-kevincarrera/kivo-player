import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
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
    final visible = ref.watch(controlsVisibleProvider);
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
              IgnorePointer(
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
                  ],
                ),
              ),
            ]),
    );
  }
}
