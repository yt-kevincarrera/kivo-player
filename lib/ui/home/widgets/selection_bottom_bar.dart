import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/kivo_failure.dart';
import '../../../platform/interfaces/media_file_ops.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../platform/media_file_ops_provider.dart';
import '../../../player/library/media_index.dart';
import '../../../player/library/video_actions.dart';
import '../../vault/vault_entry_actions.dart';
import '../../widgets/failure_snack_bar.dart';
import '../playlists/add_to_playlist_sheet.dart';
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
    final index = ref.watch(libraryIndexProvider).valueOrNull ?? const <VideoItem>[];
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
                // Clear the selection FIRST so this bar disappears immediately —
                // otherwise a slow op invites repeat taps that re-fire the move.
                final items = chosen;
                sel.clear();
                await moveToVault(context, ref, items);
              } : null),
              _action(cs.onSurface, Icons.playlist_add, 'A una lista', enabled ? () {
                // Clear FIRST, matching Al Vault above — the bar disappearing
                // immediately stops repeat taps. showAddToPlaylistSheet pops
                // and reports on its own, so this is fire-and-forget: nothing
                // here touches context after it starts.
                final items = chosen;
                sel.clear();
                showAddToPlaylistSheet(context, ref, items);
              } : null),
              _action(cs.onSurface, Icons.share_outlined, 'Compartir', enabled ? () async {
                await ref.read(videoActionsProvider).shareMany(chosen);
                sel.clear();
              } : null),
              _action(cs.error, Icons.delete_outline, 'Borrar', enabled ? () async {
                final movesToTrash = ref.read(mediaFileOpsProvider).movesToTrash;
                final n = chosen.length;
                final noun = n == 1 ? 'video' : 'videos';
                final confirmLabel = movesToTrash ? 'Mover a la papelera' : 'Borrar';
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(movesToTrash ? 'Mover a la papelera' : 'Borrar videos'),
                    content: Text(movesToTrash
                        ? '¿Mover $n $noun a la papelera?\n\nPodrás recuperarlos durante 30 días desde la app Archivos.'
                        : '¿Borrar $n $noun? Esta acción no se puede deshacer.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(confirmLabel, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                await maybeOfferAllFilesAccess(context, ref);
                if (!context.mounted) return;
                final status = await ref.read(videoActionsProvider).deleteMany(chosen);
                if (status == FileOpStatus.ok) {
                  final doneMsg = movesToTrash ? '$n $noun movidos a la papelera' : '$n $noun borrados';
                  messenger.showSnackBar(SnackBar(content: Text(doneMsg)));
                  sel.clear();
                } else if (status == FileOpStatus.error && context.mounted) {
                  showFailureSnackBar(context, KivoOp.delete);
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
