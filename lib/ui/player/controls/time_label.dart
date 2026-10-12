import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/spoken.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/open/video_source.dart';
import '../../../player/queue/queue_order.dart';

/// What the time right of the seek bar shows; a tap moves to the next one.
enum TimeLabelMode { total, remaining, endsAt }

final timeLabelModeProvider =
    StateProvider<TimeLabelMode>((ref) => TimeLabelMode.total);

/// How long until what the "ends at" label counts to: the end of the queue
/// when there is one that ends (no repeat) and every later duration is known,
/// otherwise the end of this video. Both at playback speed [rate].
({Duration left, bool queue}) timeToEnd({
  required VideoSession? session,
  required RepeatMode repeat,
  required Duration total,
  required Duration position,
  required double rate,
}) {
  final order = session?.playOrder ?? const <int>[];
  if (session != null && order.length > 1 && repeat == RepeatMode.off) {
    final left = queueTimeLeft(
      order: order,
      current: session.index,
      durationsMs: session.queueDurationsMs,
      currentDuration: total,
      position: position,
      rate: rate,
    );
    if (left != null) return (left: left, queue: true);
  }
  final rest = total - position;
  final ms = rest.isNegative ? 0 : rest.inMilliseconds;
  return (
    left: Duration(milliseconds: (ms / (rate > 0 ? rate : 1)).round()),
    queue: false,
  );
}

/// The time right of the seek bar: `1:42:10` → `-48:32` → `fin 23:40` (or
/// `fin cola 23:40` when the queue's end is known), a tap at a time. Takes
/// no height of its own — the end time lives in the room the length had.
class TimeLabel extends ConsumerStatefulWidget {
  /// The video's length and the position shown on the bar (the scrub target
  /// while dragging, so the end time follows the thumb).
  final Duration total;
  final Duration position;
  const TimeLabel({super.key, required this.total, required this.position});

  @override
  ConsumerState<TimeLabel> createState() => _TimeLabelState();
}

class _TimeLabelState extends ConsumerState<TimeLabel> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Paused, nothing else rebuilds the label, yet the end keeps moving with
    // the wall clock.
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && ref.read(timeLabelModeProvider) == TimeLabelMode.endsAt) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _next() => ref.read(timeLabelModeProvider.notifier).update(
      (m) => TimeLabelMode.values[(m.index + 1) % TimeLabelMode.values.length]);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mode = ref.watch(timeLabelModeProvider);
    final total = widget.total;
    final remaining = total - widget.position < Duration.zero
        ? Duration.zero
        : total - widget.position;

    final String text;
    final String label;
    switch (mode) {
      case TimeLabelMode.total:
        text = fmtDuration(total);
        label = l10n.playerTotalTimeLabel(spokenDuration(l10n, total));
      case TimeLabelMode.remaining:
        text = '-${fmtDuration(remaining)}';
        label = l10n.playerRemainingTimeLabel(spokenDuration(l10n, remaining));
      case TimeLabelMode.endsAt:
        final end = timeToEnd(
          session: ref.watch(currentVideoProvider),
          repeat: repeatModeFor(ref.watch(settingsProvider).repeatMode),
          total: total,
          position: widget.position,
          rate: ref.watch(rateProvider),
        );
        final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
        final at = TimeOfDay.fromDateTime(DateTime.now().add(end.left));
        final clock = MaterialLocalizations.of(context)
            .formatTimeOfDay(at, alwaysUse24HourFormat: use24);
        // Only for «a la 1» / «a las 2»: the hour as the clock shows it.
        final shownHour =
            use24 ? at.hour : (at.hourOfPeriod == 0 ? 12 : at.hourOfPeriod);
        text = end.queue
            ? l10n.playerQueueEndsAtShort(clock)
            : l10n.playerEndsAtShort(clock);
        label = end.queue
            ? l10n.playerQueueEndsAtLabel(shownHour, clock)
            : l10n.playerEndsAtLabel(shownHour, clock);
    }

    return Semantics(
      button: true,
      label: label,
      onTapHint: l10n.playerTimeToggleHint,
      onTap: _next,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: _next,
        behavior: HitTestBehavior.opaque,
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}
