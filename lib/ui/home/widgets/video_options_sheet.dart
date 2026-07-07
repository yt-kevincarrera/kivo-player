import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/interfaces/media_file_ops.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/video_actions.dart';
import 'rename_dialog.dart';
import 'video_details_sheet.dart';

/// Bottom-sheet menu for a library video's ⋮ button. Rows are theme-aware.
class VideoOptionsSheet extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onShare;
  final VoidCallback onRename;
  final VoidCallback onDetails;
  final VoidCallback onDelete;
  const VideoOptionsSheet({
    super.key,
    required this.video,
    required this.onShare,
    required this.onRename,
    required this.onDetails,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(video.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          _row(context, Icons.share_outlined, 'Compartir', cs.onSurface, onShare),
          _row(context, Icons.drive_file_rename_outline, 'Renombrar', cs.onSurface, onRename),
          _row(context, Icons.info_outline, 'Detalles', cs.onSurface, onDetails),
          _row(context, Icons.delete_outline, 'Borrar', cs.error, onDelete),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 16),
          Text(label, style: TextStyle(color: color, fontSize: 15)),
        ]),
      ),
    );
  }
}

/// Opens the options sheet, fully wired: share, rename (dialog + controller),
/// details (sheet), and delete (own confirm dialog + controller).
Future<void> showVideoOptions(BuildContext context, WidgetRef ref, VideoItem v) {
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) => VideoOptionsSheet(
      video: v,
      onShare: () {
        Navigator.pop(sheetContext);
        ref.read(videoActionsProvider).share(v);
      },
      onDetails: () {
        Navigator.pop(sheetContext);
        showVideoDetails(context, v);
      },
      onRename: () async {
        Navigator.pop(sheetContext);
        final base = await showRenameDialog(context, v);
        if (base == null) return;
        if (!context.mounted) return;
        final r = await ref.read(videoActionsProvider).rename(v, base);
        if (r.status == FileOpStatus.error) {
          messenger.showSnackBar(const SnackBar(content: Text('No se pudo renombrar')));
        }
      },
      onDelete: () async {
        Navigator.pop(sheetContext);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Borrar video'),
            content: Text('¿Borrar «${v.name}»? Esta acción no se puede deshacer.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Borrar', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        if (!context.mounted) return;
        final status = await ref.read(videoActionsProvider).delete(v);
        if (status == FileOpStatus.ok) {
          messenger.showSnackBar(const SnackBar(content: Text('Video borrado')));
        } else if (status == FileOpStatus.error) {
          messenger.showSnackBar(const SnackBar(content: Text('No se pudo borrar')));
        }
      },
    ),
  );
}
