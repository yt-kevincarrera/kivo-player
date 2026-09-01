import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/continue_watching.dart';
import 'video_options_sheet.dart';
import 'video_tile.dart';

class ContinueRow extends ConsumerWidget {
  final void Function(VideoItem video, Rect? origin) onOpen;
  const ContinueRow({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueWatchingProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Text(
          'Continuar viendo',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      SizedBox(
        height: 128,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const PageScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (tileContext, i) => SizedBox(
            width: 200,
            child: VideoTile(
              video: items[i].video,
              progress: items[i].fraction,
              listRow: false,
              onTap: (origin) => onOpen(items[i].video, origin),
              // Same options sheet the library uses — long-pressing here must
              // offer info/rename/delete/etc, not a second, cut-down menu.
              // VideoTile's GestureDetector already loses the arena to the
              // row's HorizontalDragGestureRecognizer once the pointer moves
              // past the touch slop, so this doesn't eat the scroll gesture.
              onLongPress: () =>
                  showVideoOptions(tileContext, ref, items[i].video),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
    ]);
  }
}
