import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../l10n/l10n.dart';
import '../../player/open/video_source.dart';
import '../../player/queue/queue_undo.dart';
import '../player/state/queue_strip_state.dart';
import '../player/state/controls_visibility.dart';
import 'tv_focusable.dart';
import 'tv_panel.dart';

Future<void> showTvQueue(BuildContext context) => showTvPanel<void>(
  context: context,
  title: context.l10n.tvEditQueue,
  builder: (_) => Consumer(
    builder: (context, ref, _) {
      final session = ref.watch(currentVideoProvider);
      final order = session?.playOrder ?? [];
      return ListView(
        padding: const EdgeInsets.all(5),
        children: [
          for (final i in order)
            Row(
              key: ValueKey('queue-$i'),
              children: [
                Expanded(
                  child: TvOptionRow(
                    label: _name(session!, i),
                    selected: i == session.index,
                    autofocus: i == session.index,
                    onPressed: () {
                      Navigator.of(context).pop();
                      if (i != session.index) {
                        ref.read(queueJumpProvider.notifier).state = i;
                      }
                    },
                  ),
                ),
                TvFocusable(
                  label: '${context.l10n.tvOptions}: ${_name(session, i)}',
                  scale: 1,
                  onPressed: () => showTvQueueActions(context, i),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Icon(Icons.more_horiz, size: 28),
                  ),
                ),
              ],
            ),
          if (ref.watch(queueUndoProvider) != null)
            TvOptionRow(
              label: context.l10n.commonUndo,
              icon: Icons.undo,
              onPressed: () =>
                  ref.read(currentVideoProvider.notifier).undoQueueEdit(),
            ),
        ],
      );
    },
  ),
);

String _name(VideoSession session, int i) => i < session.queueNames.length
    ? session.queueNames[i]
    : basenameOf(session.queue[i]);

Future<void> showTvQueueActions(BuildContext context, int index) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final session = container.read(currentVideoProvider);
  if (session == null || index >= session.queue.length) return;
  final order = session.playOrder, position = session.playOrder.indexOf(index);
  if (position < 0) return;
  final current = index == session.index;
  final path = session.queue[index];
  final l = context.l10n;
  final controls = container.read(controlsVisibleProvider.notifier);
  controls.hold();
  try {
    final choice =
        await showTvPanelChoices<String>(context, _name(session, index), [
          if (!current) ('next', l.playerQueuePlayNext, null),
          if (position > 0) ('earlier', l.tvMoveEarlier, null),
          if (position < order.length - 1) ('later', l.tvMoveLater, null),
          if (!current) ('remove', l.playerQueueRemove, null),
        ]);
    if (!context.mounted || choice == null) return;
    final latest = container.read(currentVideoProvider);
    if (latest == null ||
        index >= latest.queue.length ||
        latest.queue[index] != path) {
      return;
    }
    final at = latest.playOrder.indexOf(index);
    if (at < 0) return;
    final controller = container.read(currentVideoProvider.notifier);
    switch (choice) {
      case 'next':
        if (index != latest.index) controller.playNext(index);
      case 'earlier':
        if (at > 0) controller.reorder(at, at - 1);
      case 'later':
        if (at < latest.playOrder.length - 1) controller.reorder(at, at + 1);
      case 'remove':
        if (index != latest.index) controller.remove(index);
    }
  } finally {
    controls.release();
  }
}
