import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../state/library_selection.dart';

/// Contextual AppBar shown while library selection mode is active: shows the
/// selected count and "select all" (from [allVisible]). Batch actions
/// (share/delete) live in [SelectionBottomBar].
class SelectionAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final List<VideoItem> allVisible;
  const SelectionAppBar({super.key, required this.allVisible});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(librarySelectionProvider);
    final sel = ref.read(librarySelectionProvider.notifier);
    final chosen = allVisible.where((v) => selected.contains(v.uri)).toList();

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancelar',
        onPressed: sel.clear,
      ),
      title: Text(
        '${chosen.length} seleccionado${chosen.length == 1 ? '' : 's'}',
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: 'Seleccionar todo',
          onPressed: () => sel.selectAll(allVisible.map((v) => v.uri)),
        ),
      ],
    );
  }
}
