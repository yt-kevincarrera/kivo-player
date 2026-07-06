import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The player's shrink-to-mini-player exit, published by PlayerScreen (which
/// owns the AnimationController) so the swipe release, the top-bar back, and the
/// system back all trigger the same animation. Null while no PlayerScreen is
/// mounted.
class PlayerDismissApi {
  final void Function() complete; // shrink → minimize → pop
  final void Function() cancel;   // return to 0 (drag not committed)
  const PlayerDismissApi({required this.complete, required this.cancel});
}

final playerDismissProvider = StateProvider<PlayerDismissApi?>((ref) => null);

/// Duration of the programmatic shrink: a back-press from a resting player
/// (progress 0) takes 240ms; a nearly-complete swipe finishes fast. Clamped to
/// an 80ms floor so it never feels instantaneous.
int dismissDurationMs(double progress) =>
    (240 * (1.0 - progress)).round().clamp(80, 240);
