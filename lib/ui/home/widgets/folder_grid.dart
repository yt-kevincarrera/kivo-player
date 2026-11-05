import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/library_query.dart';
import '../../widgets/press_bounce.dart';
import 'folder_options_sheet.dart';
import 'library_empty_state.dart';
import 'thumbnail_image.dart';
import '../../widgets/kivo_focusable.dart';
import '../library_layout.dart';

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
    final accent = Theme.of(context).colorScheme.primary;

    if (folders.isEmpty) {
      return LibraryEmptyState(
        icon: Icons.folder_off_outlined,
        title: context.l10n.foldersEmptyTitle,
        subtitle: context.l10n.foldersEmptySubtitle,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = usesWideLibrary(context);
        final density = libraryDensity(context, ref.watch(settingsProvider));
        final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
          1.0,
          double.infinity,
        );
        final compactRows = (wide && density == 0) || scale >= 1.5 || constraints.maxHeight < 300;
        final columns = compactRows
            ? 1
            : libraryGridColumns(
                width: constraints.maxWidth - 48,
                wide: wide,
                density: wide
                    ? (density == 0 ? 2 : density)
                    : density.clamp(2, 3),
                textScale: scale,
              );
        final tileWidth =
            (constraints.maxWidth - 48 - (columns - 1) * 12) / columns;
        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: compactRows
                ? 28 + 68 * scale
                : tileWidth * 9 / 16 + 76 * scale,
          ),
          itemCount: folders.length,
          itemBuilder: (_, i) {
            final name = folders[i];
            final items = groups[name]!;
            return Semantics(
              container: true,
              button: true,
              label: context.l10n.a11yFolderLabel(name, items.length),
              child: KivoFocusable(
                onActivate: () => onOpenFolder(name, items),
                onSecondary: () => showFolderOptionsSheet(context, ref, name),
                borderRadius: BorderRadius.circular(10),
                child: GestureDetector(
                  onLongPress: () => showFolderOptionsSheet(context, ref, name),
                  child: PressBounce(
                    onTap: () => onOpenFolder(name, items),
                    child: ExcludeSemantics(
                      child: _FolderCard(
                        name: name,
                        items: items,
                        accent: accent,
                        compact: compactRows,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _FolderCard extends StatelessWidget {
  final String name;
  final List<VideoItem> items;
  final Color accent;
  final bool compact;

  const _FolderCard({
    required this.name,
    required this.items,
    required this.accent,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (compact) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              height: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: ThumbnailImage(items.first.id, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _CountPill(items.length, accent),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cs.onSurface.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thumbnail cover — takes ~65% of the card
          Expanded(
            flex: 65,
            child: ThumbnailImage(items.first.id, fit: BoxFit.cover),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _CountPill(items.length, accent),
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
  final Color accent;
  const _CountPill(this.count, this.accent);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.55), width: 0.8),
      ),
      child: Text(
        context.l10n.folderCardVideoCount(count),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
