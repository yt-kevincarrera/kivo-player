import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../l10n/l10n.dart';
import '../../player/open/video_source.dart';
import 'tv_artwork.dart';
import '../player/state/queue_strip_state.dart';
import 'tv_focusable.dart';
import 'tv_queue_dialog.dart';

/// The queue is part of playback, not a trip back through the library.
class TvQueueStrip extends ConsumerStatefulWidget {
  const TvQueueStrip({super.key, required this.onEdit});
  final VoidCallback onEdit;
  @override
  ConsumerState<TvQueueStrip> createState() => _TvQueueStripState();
}

class _TvQueueStripState extends ConsumerState<TvQueueStrip> {
  final _scroll = ScrollController();
  String? _anchor;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentVideoProvider);
    if (session == null || session.playOrder.length < 2) {
      return const SizedBox.shrink();
    }
    final order = session.playOrder;
    if (_anchor != session.playbackPath) {
      _anchor = session.playbackPath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final target = order.indexOf(session.index) * 196.0;
        _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
      });
    }
    final c = Theme.of(context).colorScheme;
    return Column(
      key: const Key('tv-queue-strip'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.tvQueue,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
            TvFocusable(
              label: context.l10n.tvEditQueue,
              onPressed: widget.onEdit,
              scale: 1,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Text(
                      context.l10n.tvEditQueue,
                      style: const TextStyle(
                        fontSize: 19,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.more_horiz, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 118 + MediaQuery.textScalerOf(context).scale(18) * 1.7,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(5),
            itemCount: order.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, position) {
              final i = order[position];
              final name = i < session.queueNames.length
                  ? session.queueNames[i]
                  : basenameOf(session.queue[i]);
              final current = i == session.index;
              return SizedBox(
                width: 180,
                child: TvFocusable(
                  key: ValueKey('tv-strip-${session.queue[i]}'),
                  label: name,
                  selected: current,
                  onPressed: () {
                    if (!current) {
                      ref.read(queueJumpProvider.notifier).state = i;
                    }
                  },
                  onSecondary: () => showTvQueueActions(context, i),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 98,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: current ? c.primary : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: i < session.queueIds.length
                              ? TvArtwork(session.queueIds[i])
                              : const ColoredBox(
                                  color: Color(0xff20252d),
                                  child: Icon(
                                    Icons.video_file_outlined,
                                    color: Colors.white38,
                                    size: 28,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          color: current ? c.primary : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
