import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/video_actions.dart';

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

/// Opens the options sheet. Share is wired here; rename/details/delete are
/// wired in Task 8 (this task uses temporary stubs so the sheet is usable).
Future<void> showVideoOptions(BuildContext context, WidgetRef ref, VideoItem v) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) => VideoOptionsSheet(
      video: v,
      onShare: () {
        Navigator.pop(sheetContext);
        ref.read(videoActionsProvider).share(v);
      },
      onRename: () => Navigator.pop(sheetContext),
      onDetails: () => Navigator.pop(sheetContext),
      onDelete: () => Navigator.pop(sheetContext),
    ),
  );
}
