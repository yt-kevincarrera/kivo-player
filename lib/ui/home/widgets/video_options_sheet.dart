import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/kivo_failure.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/media_file_ops_provider.dart';
import '../../../platform/all_files_access_provider.dart';
import '../../../platform/interfaces/all_files_access.dart';
import '../../../platform/interfaces/media_file_ops.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/played.dart';
import '../../../player/library/video_actions.dart';
import '../../../player/open/video_source.dart'; // resumeServiceProvider
import '../../vault/vault_entry_actions.dart';
import '../../widgets/failure_snack_bar.dart';
import '../playlists/add_to_playlist_sheet.dart';
import 'rename_dialog.dart';
import 'video_details_sheet.dart';

/// Bottom-sheet menu for a library video's ⋮ button. Rows are theme-aware.
class VideoOptionsSheet extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onShare;
  final VoidCallback onRename;
  final VoidCallback onDetails;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onDelete;
  final VoidCallback onMoveToVault;
  final bool isPlayed;
  final VoidCallback onTogglePlayed;
  final bool hasResume;
  final VoidCallback onClearResume;
  const VideoOptionsSheet({
    super.key,
    required this.video,
    required this.onShare,
    required this.onRename,
    required this.onDetails,
    required this.onAddToPlaylist,
    required this.onDelete,
    required this.onMoveToVault,
    required this.isPlayed,
    required this.onTogglePlayed,
    required this.hasResume,
    required this.onClearResume,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      // Scroll-controlled and height-bounded, as more_menu.dart had to be:
      // six rows no longer fit a fixed sheet on a short screen. Bounded so a
      // future seventh row is a non-event instead of an overflow.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  video.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _row(
                context,
                Icons.share_outlined,
                context.l10n.commonShare,
                cs.onSurface,
                onShare,
              ),
              _row(
                context,
                Icons.drive_file_rename_outline,
                context.l10n.commonRename,
                cs.onSurface,
                onRename,
              ),
              _row(
                context,
                Icons.info_outline,
                context.l10n.videoSheetDetails,
                cs.onSurface,
                onDetails,
              ),
              _row(
                context,
                isPlayed
                    ? Icons.remove_circle_outline
                    : Icons.check_circle_outline,
                isPlayed
                    ? context.l10n.videoSheetMarkUnwatched
                    : context.l10n.videoSheetMarkWatched,
                cs.onSurface,
                onTogglePlayed,
              ),
              if (hasResume)
                _row(
                  context,
                  Icons.playlist_remove,
                  context.l10n.videoSheetClearResume,
                  cs.onSurface,
                  onClearResume,
                ),
              _row(
                context,
                Icons.playlist_add,
                context.l10n.playlistAddToListLabel,
                cs.onSurface,
                onAddToPlaylist,
              ),
              _row(
                context,
                Icons.lock_outline,
                context.l10n.videoSheetMoveToVault,
                cs.onSurface,
                onMoveToVault,
              ),
              _row(
                context,
                Icons.delete_outline,
                context.l10n.commonDelete,
                cs.error,
                onDelete,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(color: color, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

/// One-time offer to grant All-files-access so future delete/rename skip the
/// system consent dialog. Shows at most once (persisted via
/// [KivoSettings.offeredAllFilesAccess]); on accept it opens the settings
/// screen. The caller then proceeds with the op regardless — the native side
/// decides silent-vs-consent from the current permission.
Future<void> maybeOfferAllFilesAccess(
  BuildContext context,
  WidgetRef ref,
) async {
  final access = ref.read(allFilesAccessProvider);
  final granted = await access.isGranted();
  final settings = ref.read(settingsProvider);
  if (!shouldOfferAllFilesAccess(granted, settings.offeredAllFilesAccess)) {
    return;
  }
  ref
      .read(settingsProvider.notifier)
      .set(settings.copyWith(offeredAllFilesAccess: true));
  if (!context.mounted) return;
  final give = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.l10n.allFilesAccessDialogTitle),
      content: Text(context.l10n.allFilesAccessDialogBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(context.l10n.commonNotNow),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(context.l10n.libraryAccessPromptAction),
        ),
      ],
    ),
  );
  if (give == true) await access.request();
}

/// Opens the options sheet, fully wired: share, rename (dialog + controller),
/// details (sheet), and delete (own confirm dialog + controller).
Future<void> showVideoOptions(
  BuildContext context,
  WidgetRef ref,
  VideoItem v,
) {
  final messenger = ScaffoldMessenger.of(context);
  final isPlayed = ref.read(playedStoreProvider).isPlayed(v.name);
  final hasResume = ref.read(resumeServiceProvider).positionFor(v.name) != null;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) => VideoOptionsSheet(
      video: v,
      isPlayed: isPlayed,
      hasResume: hasResume,
      onTogglePlayed: () async {
        Navigator.pop(sheetContext);
        final newPlayed = !isPlayed;
        await ref.read(videoActionsProvider).setPlayed(v, newPlayed);
        if (!context.mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              newPlayed
                  ? context.l10n.videoSheetMarkedWatched
                  : context.l10n.videoSheetMarkedUnwatched,
            ),
          ),
        );
      },
      onClearResume: () async {
        Navigator.pop(sheetContext);
        await ref.read(videoActionsProvider).clearResume(v);
        if (!context.mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.videoSheetResumeCleared)),
        );
      },
      onShare: () {
        Navigator.pop(sheetContext);
        ref.read(videoActionsProvider).share(v);
      },
      onDetails: () {
        Navigator.pop(sheetContext);
        showVideoDetails(context, v);
      },
      onAddToPlaylist: () {
        // Pop first, like every other row here. showAddToPlaylistSheet pops
        // and reports on its own, so this is fire-and-forget — nothing below
        // touches context after it starts.
        Navigator.pop(sheetContext);
        showAddToPlaylistSheet(context, ref, [v]);
      },
      onMoveToVault: () async {
        Navigator.pop(sheetContext);
        await moveToVault(context, ref, [v]);
      },
      onRename: () async {
        Navigator.pop(sheetContext);
        final base = await showRenameDialog(context, v);
        if (base == null) return;
        if (!context.mounted) return;
        await maybeOfferAllFilesAccess(context, ref);
        if (!context.mounted) return;
        final r = await ref.read(videoActionsProvider).rename(v, base);
        if (r.status == FileOpStatus.error && context.mounted) {
          showFailureSnackBar(context, KivoOp.rename);
        }
      },
      onDelete: () async {
        Navigator.pop(sheetContext);
        // Android 11+ moves to the system trash; the dialog must say so —
        // «no se puede deshacer» would be a lie there.
        final toTrash = ref.read(mediaFileOpsProvider).movesToTrash;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              toTrash
                  ? context.l10n.trashMoveTitle
                  : context.l10n.videoSheetDeleteTitle,
            ),
            content: Text(
              toTrash
                  ? context.l10n.videoSheetTrashConfirmBody(v.name)
                  : context.l10n.videoSheetDeleteConfirmBody(v.name),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.l10n.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  toTrash ? context.l10n.trashMoveTitle : context.l10n.commonDelete,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        if (!context.mounted) return;
        await maybeOfferAllFilesAccess(context, ref);
        if (!context.mounted) return;
        final status = await ref.read(videoActionsProvider).delete(v);
        if (!context.mounted) return;
        if (status == FileOpStatus.ok) {
          messenger.showSnackBar(
            SnackBar(content: Text(context.l10n.videoSheetDeletedSnackbar)),
          );
        } else if (status == FileOpStatus.error && context.mounted) {
          showFailureSnackBar(context, KivoOp.delete);
        }
      },
    ),
  );
}
