import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/library_query.dart';
import '../../widgets/press_bounce.dart';
import 'thumbnail_image.dart';

class FolderGrid extends ConsumerWidget {
  final List<VideoItem> videos;
  final void Function(String folder, List<VideoItem> items) onOpenFolder;

  const FolderGrid({
    super.key,
    required this.videos,
    required this.onOpenFolder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = groupByFolder(videos);
    final folders = groups.keys.toList()..sort();
    final cs = Theme.of(context).colorScheme;

    if (folders.isEmpty) {
      return Center(
        child: Text(
          'No se encontraron carpetas',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.25,
      ),
      itemCount: folders.length,
      itemBuilder: (_, i) {
        final name = folders[i];
        final items = groups[name]!;
        return PressBounce(
          onTap: () => onOpenFolder(name, items),
          child: _FolderCard(name: name, items: items),
        );
      },
    );
  }
}

class _FolderCard extends StatelessWidget {
  final String name;
  final List<VideoItem> items;

  const _FolderCard({required this.name, required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08), width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thumbnail cover — takes ~65% of the card
          Expanded(
            flex: 65,
            child: ThumbnailImage(
              items.first.id,
              fit: BoxFit.cover,
            ),
          ),
          // Footer with folder name and count pill
          Expanded(
            flex: 35,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _CountPill(items.length),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final int count;
  const _CountPill(this.count);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: KivoColors.gold.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KivoColors.gold.withValues(alpha: 0.55), width: 0.8),
      ),
      child: Text(
        '$count vids',
        style: const TextStyle(
          color: KivoColors.gold,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
