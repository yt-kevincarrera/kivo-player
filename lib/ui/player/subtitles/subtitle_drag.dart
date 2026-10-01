import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../player/engine/playback_provider.dart';

enum SubtitleLine { primary, secondary }

/// The same 0–40 % range the Estilo sliders offer.
const subtitleMaxMargin = 40.0;

/// A subtitle line being moved with the finger, and where it is right now.
@immutable
class SubtitleDrag {
  const SubtitleDrag(this.line, this.margin);
  final SubtitleLine line;
  final double margin;
}

/// Where the subtitle lines are on screen, so the player's gestures can tell
/// whether a long press landed on one. The overlay itself takes no touches —
/// that is what keeps double-tap, swipes and pinch working over the text.
class SubtitleHitTargets {
  final primary = GlobalKey(debugLabel: 'subtitle-primary-target');
  final secondary = GlobalKey(debugLabel: 'subtitle-secondary-target');

  GlobalKey keyOf(SubtitleLine line) =>
      line == SubtitleLine.primary ? primary : secondary;

  /// The line under [global], if any. The primary wins where both overlap.
  SubtitleLine? lineAt(Offset global) {
    for (final line in const [SubtitleLine.primary, SubtitleLine.secondary]) {
      final box = keyOf(line).currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      // A little slack: a finger is wider than the text's exact box.
      if (rect.inflate(8).contains(global)) return line;
    }
    return null;
  }
}

final subtitleHitTargetsProvider =
    Provider<SubtitleHitTargets>((ref) => SubtitleHitTargets());

/// Press-and-hold-to-move for subtitle lines. Playback pauses while a line is
/// held if it was playing, and carries on when it is let go; paused stays
/// paused. The position is saved on release, not on every frame.
class SubtitleDragNotifier extends Notifier<SubtitleDrag?> {
  double _startMargin = 0;
  double _startY = 0;
  double _height = 1;
  bool _resume = false;

  @override
  SubtitleDrag? build() => null;

  double _savedMargin(SubtitleLine line) {
    final s = ref.read(settingsProvider);
    return line == SubtitleLine.primary
        ? s.subtitleBottomMargin
        : s.secondarySubtitleTopMargin;
  }

  void _haptic(void Function() f) {
    if (ref.read(settingsProvider).hapticsOnGestures) f();
  }

  void start(SubtitleLine line, double globalY, double height) {
    final playing = ref.read(playingProvider).value ?? false;
    _resume = playing;
    if (playing) ref.read(playbackEngineProvider).pause();
    _startMargin = _savedMargin(line);
    _startY = globalY;
    _height = height <= 0 ? 1 : height;
    _haptic(HapticFeedback.mediumImpact);
    state = SubtitleDrag(line, _startMargin);
  }

  void update(double globalY) {
    final d = state;
    if (d == null) return;
    final dy = globalY - _startY;
    // The primary is measured from the bottom (up = more), the secondary from
    // the top (down = more).
    final delta = (d.line == SubtitleLine.primary ? -dy : dy) / _height * 100;
    final next =
        (_startMargin + delta).clamp(0.0, subtitleMaxMargin).roundToDouble();
    if (next == d.margin) return;
    _haptic(HapticFeedback.selectionClick);
    state = SubtitleDrag(d.line, next);
  }

  /// Saves where the line was let go and resumes playback if the hold paused
  /// it. Also the way out when the gesture is torn down mid-drag (minimize,
  /// back pressed with another finger): never leaves the video paused.
  void end() {
    final d = state;
    if (d == null) return;
    final s = ref.read(settingsProvider);
    ref.read(settingsProvider.notifier).set(d.line == SubtitleLine.primary
        ? s.copyWith(subtitleBottomMargin: d.margin)
        : s.copyWith(secondarySubtitleTopMargin: d.margin));
    if (_resume) ref.read(playbackEngineProvider).play();
    _resume = false;
    state = null;
  }
}

final subtitleDragProvider =
    NotifierProvider<SubtitleDragNotifier, SubtitleDrag?>(
        SubtitleDragNotifier.new);
