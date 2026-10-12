import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/kivo_failure.dart';
import '../../core/settings/settings_provider.dart';
import '../../core/theme/kivo_theme.dart';
import '../../l10n/l10n.dart';
import '../../platform/interfaces/media_file_ops.dart';
import '../../platform/media_file_ops_provider.dart';
import '../../player/end_actions/end_flow.dart';
import '../../player/end_actions/pending_trash.dart';
import '../../player/end_actions/trash_queue.dart';
import '../../player/open/video_source.dart';
import '../player/state/mini_player_state.dart';
import '../widgets/failure_snack_bar.dart';

/// The video still loaded in the mini-bar — never deleted from under it.
String? loadedTrashUri(WidgetRef ref) => ref.read(playerMinimizedProvider)
    ? ref.read(currentVideoProvider)?.playbackPath
    : null;

/// Leaving the player (or closing the mini-bar): every pending «Al terminar»
/// deletion in one go — one system dialog for the batch without all-files
/// access. Skipped while Kivo is closing itself (asked about next time).
Future<void> flushPendingTrash(BuildContext context, WidgetRef ref) async {
  if (ref.read(suppressTrashFlushProvider)) return;
  final loaded = loadedTrashUri(ref);
  final count =
      ref.read(trashQueueProvider).where((e) => e.uri != loaded).length;
  if (count == 0) return;
  final status = await ref
      .read(trashQueueProvider.notifier)
      .flushInteractive(loadedUri: loaded);
  if (!context.mounted || status == null) return;
  _report(context, ref, status, count);
}

void _report(BuildContext context, WidgetRef ref, FileOpStatus status, int count) {
  switch (status) {
    case FileOpStatus.ok:
      final l10n = context.l10n;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(ref.read(mediaFileOpsProvider).movesToTrash
              ? l10n.selectionTrashedSnackbar(count)
              : l10n.selectionDeletedSnackbar(count)),
        ));
    case FileOpStatus.cancelled:
      break; // declining the dialog keeps the files — nothing to say
    case FileOpStatus.error:
      showFailureSnackBar(context, KivoOp.delete);
  }
}

/// App start / back to the app, outside the player: commit silently what
/// can be, and ask about the rest.
Future<void> askAboutPendingTrash(BuildContext context, WidgetRef ref) async {
  final queue = ref.read(trashQueueProvider.notifier);
  if (queue.busy) return;
  final loaded = loadedTrashUri(ref);
  await queue.commitSilentlyIfPossible(loadedUri: loaded);
  if (!context.mounted) return;
  final due = queue.due(loadedUri: loaded);
  if (due.isEmpty) return;
  final move = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => PendingTrashSheet(entries: due),
  );
  if (move == null || !context.mounted) return;
  // Only what the sheet listed: entries still in their undo window (or the
  // video in the mini-bar) were not asked about.
  final listed = due.map((e) => e.uri).toSet();
  if (!move) {
    await queue.keep(listed);
    return;
  }
  final status = await queue.flushInteractive(loadedUri: loaded, only: listed);
  if (status != null && context.mounted) _report(context, ref, status, due.length);
}

class PendingTrashSheet extends ConsumerWidget {
  final List<PendingTrash> entries;
  const PendingTrashSheet({super.key, required this.entries});

  static const _shown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final toTrash = ref.watch(mediaFileOpsProvider).movesToTrash;
    final names = entries.take(_shown).map((e) => e.name).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.delete_outline_rounded, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    toTrash
                        ? l10n.pendingTrashTitle(entries.length)
                        : l10n.pendingTrashDeleteTitle(entries.length),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(l10n.pendingTrashBody,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            for (final n in names)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(n,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            if (entries.length > _shown)
              Text(l10n.pendingTrashMore(entries.length - _shown),
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('pending-trash-keep'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l10n.endActionsKeep),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('pending-trash-move'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: onAccent(accent),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(toTrash ? l10n.trashMoveTitle : l10n.commonDelete),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
