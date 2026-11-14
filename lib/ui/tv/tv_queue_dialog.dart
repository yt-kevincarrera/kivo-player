import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../l10n/l10n.dart';
import '../../player/open/video_source.dart';
import '../../player/queue/queue_undo.dart';
import '../player/state/queue_strip_state.dart';
import 'tv_focusable.dart';
import 'tv_settings_screen.dart';

/// Queue editing never requires dragging or a remote's optional Menu key.
Future<void> showTvQueue(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) => Dialog(
    child: SizedBox(
      width: 900,
      height: MediaQuery.sizeOf(ctx).height * .8,
      child: Consumer(
        builder: (context, ref, _) {
          final session = ref.watch(currentVideoProvider);
          final order = session?.playOrder ?? [];
          final l = context.l10n;
          return Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.tvQueue,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(5),
                    itemCount: order.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, position) {
                      final index = order[position];
                      final current = index == session!.index;
                      final name = index < session.queueNames.length
                          ? session.queueNames[index]
                          : basenameOf(session.queue[index]);
                      return Row(
                        children: [
                          Expanded(
                            child: TvButton(
                              key: ValueKey('queue-$index'),
                              label: name,
                              autofocus: current,
                              selected: current,
                              subtitle: current ? l.playerQueueNowBadge : null,
                              icon: current
                                  ? Icons.play_arrow
                                  : Icons.video_file_outlined,
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                if (!current) {
                                  ref.read(queueJumpProvider.notifier).state =
                                      index;
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          TvButton(
                            label: l.tvOptions,
                            icon: Icons.more_horiz,
                            onPressed: () async {
                              final choice =
                                  await showTvChoices<String>(context, name, [
                                    if (!current)
                                      ('next', l.playerQueuePlayNext, null),
                                    if (position > 0)
                                      ('earlier', l.tvMoveEarlier, null),
                                    if (position < order.length - 1)
                                      ('later', l.tvMoveLater, null),
                                    if (!current)
                                      ('remove', l.playerQueueRemove, null),
                                  ]);
                              if (!context.mounted || choice == null) return;
                              final controller = ref.read(
                                currentVideoProvider.notifier,
                              );
                              switch (choice) {
                                case 'next':
                                  controller.playNext(index);
                                case 'earlier':
                                  controller.reorder(position, position - 1);
                                case 'later':
                                  controller.reorder(position, position + 1);
                                case 'remove':
                                  controller.remove(index);
                              }
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                if (ref.watch(queueUndoProvider) != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TvButton(
                      label: l.commonUndo,
                      icon: Icons.undo,
                      onPressed: () => ref
                          .read(currentVideoProvider.notifier)
                          .undoQueueEdit(),
                    ),
                  ),
                TvButton(
                  label: l.commonGoBack,
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          );
        },
      ),
    ),
  ),
);
