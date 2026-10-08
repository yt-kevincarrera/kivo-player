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

// ── Queue editing ────────────────────────────────────────────────────────────
// Every edit the user makes to the queue strip rewrites the PLAY ORDER only —
// a permutation of a subset of the queue's indices. The queue itself never
// changes, so a removed video is just an index missing from the order and
// undoing a removal is putting it back.

/// [order] with the entry at position [from] moved to position [to] (its
/// final position once moved). Always a fresh list.
List<int> moveInOrder(List<int> order, int from, int to) {
  final out = [...order];
  if (from < 0 || from >= out.length) return out;
  final v = out.removeAt(from);
  out.insert(to.clamp(0, out.length), v);
  return out;
}

/// [order] with [item] placed right after [current] — taken from wherever it
/// was, or re-inserted if it had been removed. A no-op for [current] itself.
List<int> playNextInOrder(List<int> order, int current, int item) {
  if (item == current) return [...order];
  final out = [...order]..remove(item);
  out.insert(out.indexOf(current) + 1, item);
  return out;
}

/// [order] without [item]. The video being watched ([current]) can never be
/// removed — the order must always contain it, or "next" has nowhere to
/// start from.
List<int> removeFromOrder(List<int> order, int current, int item) =>
    item == current ? [...order] : ([...order]..remove(item));

/// How long until the queue runs out: what is left of the current video plus
/// every video after it in [order], at playback speed [rate]. Null when it
/// cannot be known — the current duration has not arrived yet, or any later
/// video's duration is missing (a 0 in, or past the end of, [durationsMs]).
Duration? queueTimeLeft({
  required List<int> order,
  required int current,
  required List<int> durationsMs,
  required Duration currentDuration,
  required Duration position,
  required double rate,
}) {
  final at = order.indexOf(current);
  if (at < 0 || currentDuration <= Duration.zero) return null;
  var ms = (currentDuration - position).inMilliseconds;
  if (ms < 0) ms = 0;
  for (final i in order.skip(at + 1)) {
    final d = i < durationsMs.length ? durationsMs[i] : 0;
    if (d <= 0) return null;
    ms += d;
  }
  return Duration(milliseconds: (ms / (rate > 0 ? rate : 1)).round());
}
