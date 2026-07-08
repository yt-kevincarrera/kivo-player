import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/interfaces/media_file_ops.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/media_index.dart';
import '../../../player/library/video_actions.dart';
import '../../vault/vault_entry_actions.dart';
import '../state/library_selection.dart';
import 'video_options_sheet.dart'; // maybeOfferAllFilesAccess

/// Bottom action bar shown during selection (thumb-reachable). Resolves the
/// chosen videos from the media index ∩ selected uris, so it works in both the
/// library and a folder without needing the visible list.
class SelectionBottomBar extends ConsumerWidget {
  const SelectionBottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(librarySelectionProvider);
    final sel = ref.read(librarySelectionProvider.notifier);
    final index = ref.watch(mediaIndexProvider).valueOrNull ?? const <VideoItem>[];
    final chosen = index.where((v) => selected.contains(v.uri)).toList();
    final cs = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final enabled = chosen.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _action(cs.onSurface, Icons.lock_outline, 'Al Vault', enabled ? () async {
                await moveToVault(context, ref, chosen);
                sel.clear();
              } : null),
              _action(cs.onSurface, Icons.share_outlined, 'Compartir', enabled ? () async {
                await ref.read(videoActionsProvider).shareMany(chosen);
                sel.clear();
              } : null),
              _action(cs.error, Icons.delete_outline, 'Borrar', enabled ? () async {
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
              } : null),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(Color color, IconData icon, String label, VoidCallback? onTap) {
    final c = onTap == null ? color.withValues(alpha: 0.4) : color;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: c),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 11, color: c)),
          ],
        ),
      ),
    );
  }
}
