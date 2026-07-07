import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/interfaces/media_file_ops.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/video_actions.dart';
import '../state/library_selection.dart';
import 'video_options_sheet.dart'; // maybeOfferAllFilesAccess

/// Contextual AppBar shown while library selection mode is active: shows the
/// selected count, "select all" (from [allVisible]), share, and batch-delete.
class SelectionAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final List<VideoItem> allVisible;
  const SelectionAppBar({super.key, required this.allVisible});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(librarySelectionProvider);
    final sel = ref.read(librarySelectionProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final chosen = allVisible.where((v) => selected.contains(v.uri)).toList();
    final messenger = ScaffoldMessenger.of(context);

    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cancelar', onPressed: sel.clear),
      title: Text('${selected.length} seleccionado${selected.length == 1 ? '' : 's'}'),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all), tooltip: 'Seleccionar todo',
          onPressed: () => sel.selectAll(allVisible.map((v) => v.uri)),
        ),
        IconButton(
          icon: const Icon(Icons.share), tooltip: 'Compartir',
          onPressed: chosen.isEmpty ? null : () async {
            await ref.read(videoActionsProvider).shareMany(chosen);
            sel.clear();
          },
        ),
        IconButton(
          icon: Icon(Icons.delete, color: cs.error), tooltip: 'Borrar',
          onPressed: chosen.isEmpty ? null : () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Borrar videos'),
                content: Text('¿Borrar ${chosen.length} videos? Esta acción no se puede deshacer.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('Borrar', style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
                ],
              ),
            );
            if (ok != true || !context.mounted) return;
            await maybeOfferAllFilesAccess(context, ref);
            if (!context.mounted) return;
            final status = await ref.read(videoActionsProvider).deleteMany(chosen);
            if (status == FileOpStatus.ok) {
              messenger.showSnackBar(SnackBar(content: Text('${chosen.length} videos borrados')));
              sel.clear();
            } else if (status == FileOpStatus.error) {
              messenger.showSnackBar(const SnackBar(content: Text('No se pudieron borrar')));
            }
          },
        ),
      ],
    );
  }
}
