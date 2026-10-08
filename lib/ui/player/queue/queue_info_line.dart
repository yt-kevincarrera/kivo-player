import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../../../player/open/video_source.dart';
import '../../../player/queue/queue_order.dart';

/// The line above the queue strip: `4 / 12 · quedan 2 h 10 min · acaba a
/// las 23:40`. Counts the play order (shuffle and edits included) and the
/// playback speed. Under repeat there is no end, and with any later duration
/// unknown there is no honest total — then it is just the counter.
class QueueInfoLine extends ConsumerWidget {
  const QueueInfoLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(currentVideoProvider);
    final order = s?.playOrder ?? const <int>[];
    if (s == null || order.length <= 1) return const SizedBox.shrink();
    final l10n = context.l10n;
    final parts = [l10n.playerQueuePosition(order.indexOf(s.index) + 1, order.length)];

    final repeat = repeatModeFor(ref.watch(settingsProvider).repeatMode);
    if (repeat == RepeatMode.off) {
      final left = queueTimeLeft(
        order: order,
        current: s.index,
        durationsMs: s.queueDurationsMs,
        currentDuration: ref.watch(durationProvider).valueOrNull ?? Duration.zero,
        position: ref.watch(positionProvider).valueOrNull ?? Duration.zero,
        rate: ref.watch(rateProvider),
      );
      if (left != null) {
        final minutes = (left.inSeconds / 60).ceil();
        final h = minutes ~/ 60;
        parts.add(l10n.playerQueueTimeLeft(h > 0
            ? l10n.playerQueueHoursMinutes(h, minutes % 60)
            : l10n.playerQueueMinutes(minutes)));
        final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
        final end = TimeOfDay.fromDateTime(DateTime.now().add(left));
        final clock = MaterialLocalizations.of(context)
            .formatTimeOfDay(end, alwaysUse24HourFormat: use24);
        final shownHour = use24
            ? end.hour
            : (end.hourOfPeriod == 0 ? 12 : end.hourOfPeriod);
        parts.add(l10n.playerQueueEndsAt(shownHour, clock));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        parts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 10,
          fontWeight: FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
