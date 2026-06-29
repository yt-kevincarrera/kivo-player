enum TapZone { left, center, right }

TapZone tapZoneOf(double dxFraction, {double centerStart = 0.33, double centerEnd = 0.67}) {
  if (dxFraction < centerStart) return TapZone.left;
  if (dxFraction > centerEnd) return TapZone.right;
  return TapZone.center;
}

Duration clampSeek(Duration current, Duration delta, Duration total) {
  final ms = (current + delta).inMilliseconds;
  if (ms < 0) return Duration.zero;
  if (ms > total.inMilliseconds) return total;
  return Duration(milliseconds: ms);
}

double dragValue(double current01, double dyPixels, double regionPixels, double sensitivity) {
  if (regionPixels <= 0) return current01;
  final next = current01 - (dyPixels / regionPixels) * sensitivity;
  return next.clamp(0.0, 1.0);
}

/// Maps a 0..1 fraction to the nearest detent in [detents] (index = round(f*(n-1))).
double detentSpeed(double fraction, List<double> detents) {
  if (detents.isEmpty) return 1.0;
  final f = fraction.clamp(0.0, 1.0);
  final index = (f * (detents.length - 1)).round();
  return detents[index];
}

double ladderSpeed(double fraction, double min, double max, int steps) {
  final f = fraction.clamp(0.0, 1.0);
  if (steps <= 1) return min;
  final index = (f * (steps - 1)).round();
  return min + index * (max - min) / (steps - 1);
}

double snapToDetent(double value, List<double> detents, double epsilon) {
  for (final d in detents) {
    if ((value - d).abs() <= epsilon) return d;
  }
  return value;
}

double clampRate(double value, double min, double max) => value.clamp(min, max);

double round2(double value) => (value * 100).round() / 100;

({double system01, double playerPercent}) volumeMapping(double percent, double boostMax) {
  final p = percent.clamp(0.0, boostMax);
  final system = (p < 100 ? p : 100) / 100;
  return (system01: system, playerPercent: p < 100 ? 100 : p);
}

/// Volume drag in PERCENT space (0..capMax). Drag UP (negative dy) raises.
/// A full-region drag ≈ 100 percentage points × sensitivity.
double dragVolumePercent(double currentPct, double dyPixels, double regionPixels,
    double sensitivity, double capMax) {
  if (regionPixels <= 0) return currentPct;
  final next = currentPct - (dyPixels / regionPixels) * 100 * sensitivity;
  return next.clamp(0.0, capMax);
}
