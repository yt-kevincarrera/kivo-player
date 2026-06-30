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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text('Continuar viendo', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
      SizedBox(height: 120, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const PageScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => SizedBox(width: 190, child: VideoTile(
          video: items[i].video, progress: items[i].fraction,
          listRow: false,
          onTap: () => onOpen(items[i].video))),
      )),
    ]);
  }
}
