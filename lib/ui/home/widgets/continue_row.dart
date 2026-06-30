import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/continue_watching.dart';
import 'video_tile.dart';

class ContinueRow extends ConsumerWidget {
  final void Function(VideoItem) onOpen;
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
          itemBuilder: (_, i) => SizedBox(
            width: 200,
            child: VideoTile(
              video: items[i].video,
              progress: items[i].fraction,
              listRow: false,
              onTap: () => onOpen(items[i].video),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
    ]);
  }
}
