import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/continue_watching.dart';
import 'video_options_sheet.dart';
import 'video_tile.dart';
import '../library_layout.dart';

class ContinueRow extends ConsumerWidget {
  final void Function(VideoItem video, Rect? origin) onOpen;
  const ContinueRow({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueWatchingProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final compactCards = usesWideLibrary(context) || hasCompactHeight(context);
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      double.infinity,
    );
    final cards = SizedBox(
      height: compactCards ? 100 * scale : 200 * 9 / 16 + 12 + 56 * scale,
      child: ListView.separated(
        key: const PageStorageKey('continue-watching-cards'),
        scrollDirection: Axis.horizontal,
        physics: const PageScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (tileContext, i) => SizedBox(
          width: compactCards ? 360 : 200,
          child: VideoTile(
            video: items[i].video,
            progress: items[i].fraction,
            listRow: compactCards,
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
    );
    final title = Text(
      context.l10n.continueRowTitle,
      style: TextStyle(
        color: cs.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
    if (hasCompactHeight(context)) {
      // The library remains visible with the mini-player open on a short
      // landscape phone. Resume items stay one labeled, accessible tap away.
      return ExpansionTile(
        key: const PageStorageKey('compact-continue-watching'),
        minTileHeight: 48,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: const Border(),
        collapsedShape: const Border(),
        title: title,
        expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : null,
        children: [cards, const SizedBox(height: 6)],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: title,
        ),
        cards,
        const SizedBox(height: 6),
      ],
    );
  }
}
