/// Pure maths for the subtitle-sync HUD. No Riverpod, no widgets, no mpv —
/// everything here is a function of a single integer offset in milliseconds.
library kivo_player.player.tracks.subtitle_delay;

/// One tap of the HUD's − / + buttons.
const int trackDelayStepMs = 50;

/// What the full width of the meter represents, in each direction, and the
/// span the drag covers. Offsets beyond this pin the meter and clamp the
/// drag; the − / + buttons keep counting past it, because a badly muxed file
/// can need more than the range where fine control matters.
const int trackDelayRangeMs = 3000;

/// Odd, so there is a true centre segment for "no offset". Enough of them
/// that dragging reads as continuous rather than as a row of buttons.
const int trackDelaySegments = 25;

int nudgeDelay(int currentMs, int steps) =>
    currentMs + steps * trackDelayStepMs;

/// Maps a horizontal drag across the bar to an offset.
///
/// [fraction] is 0 at the left edge and 1 at the right, so 0.5 is centre and
/// zero offset. The result is snapped to [trackDelayStepMs] so a dragged value
/// and a tapped one are always the same kind of number, and clamped to the
/// range so a finger sliding off the end does not run away.
int delayFromDragFraction(double fraction) {
  final clamped = fraction.clamp(0.0, 1.0);
  final raw = (clamped * 2 - 1) * trackDelayRangeMs;
  final snapped = (raw / trackDelayStepMs).round() * trackDelayStepMs;
  return snapped.clamp(-trackDelayRangeMs, trackDelayRangeMs);
}

/// `+0,50 s` — Spanish decimal comma, explicit sign, U+2212 for the minus so
/// it matches the HUD's − button rather than a hyphen.
String formatDelay(int ms) {
  final seconds = (ms.abs() / 1000).toStringAsFixed(2).replaceAll('.', ',');
  final sign = ms == 0
      ? ''
      : ms > 0
          ? '+'
          : '−';
  return '$sign$seconds s';
}

/// Which segments of the meter are lit, as an inclusive index range that
/// always contains [centerIndex].
class DelayMeter {
  const DelayMeter({
    required this.centerIndex,
    required this.firstLit,
    required this.lastLit,
  });
  final int centerIndex;
  final int firstLit;
  final int lastLit;
}

DelayMeter delayMeter(int delayMs) {
  const center = (trackDelaySegments - 1) ~/ 2;
  const perSide = center;
  final ratio = delayMs.abs() / trackDelayRangeMs;
  final lit = (ratio * perSide).round().clamp(0, perSide);
  if (delayMs >= 0) {
    return DelayMeter(
        centerIndex: center, firstLit: center, lastLit: center + lit);
  }
  return DelayMeter(
      centerIndex: center, firstLit: center - lit, lastLit: center);
}
