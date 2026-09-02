import 'dart:math';

/// Repeat behavior for the current queue. Persisted in [KivoSettings] as a
/// String — the enum's `.name`, never its index (see [repeatModeFor] and
/// kivo_settings.dart's `repeatMode` field, matching how `librarySort` is
/// stored there).
enum RepeatMode { off, list, video }

/// Maps a persisted `KivoSettings.repeatMode` string back to [RepeatMode],
/// defaulting to [RepeatMode.off] for anything unrecognized — a settings map
/// written before this feature existed, or a future downgrade.
RepeatMode repeatModeFor(String value) => RepeatMode.values.firstWhere(
      (m) => m.name == value,
      orElse: () => RepeatMode.off,
    );

/// A permutation of `0..length-1` with [current] placed first.
///
/// Meant to be generated ONCE per session and reused for every advance —
/// re-drawing it on each step would let the same video reappear back-to-back
/// (or even repeat three times running) and shuffle would feel broken.
List<int> shuffledOrder(int length, int current, Random rng) {
  if (length <= 0) return const [];
  final rest = [for (var i = 0; i < length; i++) if (i != current) i];
  rest.shuffle(rng);
  return [current, ...rest];
}

/// The index (into the original queue) to advance to, or null when playback
/// should stop there.
///
/// [order] is the effective play order — the shuffled permutation, or
/// `0..n-1` when shuffle is off. [position] is where the CURRENT video sits
/// within [order] (not necessarily within the original queue — use
/// `order.indexOf(currentIndex)` to find it).
int? nextIndex({
  required List<int> order,
  required int position,
  required RepeatMode mode,
}) {
  if (order.isEmpty || position < 0 || position >= order.length) return null;
  if (mode == RepeatMode.video) return order[position];
  final isLast = position == order.length - 1;
  if (isLast) return mode == RepeatMode.list ? order.first : null;
  return order[position + 1];
}

/// Mirror of [nextIndex] for stepping backward.
int? previousIndex({
  required List<int> order,
  required int position,
  required RepeatMode mode,
}) {
  if (order.isEmpty || position < 0 || position >= order.length) return null;
  if (mode == RepeatMode.video) return order[position];
  final isFirst = position == 0;
  if (isFirst) return mode == RepeatMode.list ? order.last : null;
  return order[position - 1];
}
