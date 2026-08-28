/// Pure maths for the subtitle-sync HUD. No Riverpod, no widgets, no mpv —
/// everything here is a function of a single integer offset in milliseconds.
library kivo_player.player.tracks.subtitle_delay;

/// One tap of the HUD's − / + buttons.
const int subtitleDelayStepMs = 50;

/// What the full width of the meter represents, in each direction. Offsets
/// beyond this pin the meter; the number keeps counting.
const int subtitleDelayMeterRangeMs = 1500;

/// Odd, so there is a true centre segment for "no offset".
const int subtitleDelaySegments = 13;

int nudgeSubtitleDelay(int currentMs, int steps) =>
    currentMs + steps * subtitleDelayStepMs;

/// `+0,50 s` — Spanish decimal comma, explicit sign, U+2212 for the minus so
/// it matches the HUD's − button rather than a hyphen.
String formatSubtitleDelay(int ms) {
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
class SubtitleMeter {
  const SubtitleMeter({
    required this.centerIndex,
    required this.firstLit,
    required this.lastLit,
  });
  final int centerIndex;
  final int firstLit;
  final int lastLit;
}

SubtitleMeter subtitleMeter(int delayMs) {
  const center = (subtitleDelaySegments - 1) ~/ 2;
  const perSide = center;
  final ratio = delayMs.abs() / subtitleDelayMeterRangeMs;
  final lit = (ratio * perSide).round().clamp(0, perSide);
  if (delayMs >= 0) {
    return SubtitleMeter(
        centerIndex: center, firstLit: center, lastLit: center + lit);
  }
  return SubtitleMeter(
      centerIndex: center, firstLit: center - lit, lastLit: center);
}
