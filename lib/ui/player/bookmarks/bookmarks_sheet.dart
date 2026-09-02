import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/bookmarks/bookmark.dart';
import '../../../player/bookmarks/bookmarks_provider.dart';
import '../../../player/control/player_controller.dart';

Future<void> showBookmarksSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (_) => const _BookmarksSheet(),
  );
}

class _BookmarksSheet extends ConsumerWidget {
  const _BookmarksSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarksProvider);
    final accent = Color(ref.watch(settingsProvider).accentColor);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Marcadores',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 12),
            if (bookmarks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Todavía no marcaste nada en este video.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
              )
            else
              // Bounded so a video with many bookmarks scrolls instead of
              // growing the sheet past the screen — same rule as chapters.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: bookmarks.length,
                  itemBuilder: (_, i) => _BookmarkRow(
                    key: ValueKey('bookmark-row-$i'),
                    index: i,
                    bookmark: bookmarks[i],
                    accent: accent,
                    onTap: () {
                      Navigator.of(context).pop();
                      ref.read(playerControllerProvider).seekTo(
                            Duration(milliseconds: bookmarks[i].positionMs),
                          );
                    },
                    onRename: () =>
                        _renameBookmark(context, ref, i, bookmarks[i]),
                    onDelete: () =>
                        _deleteBookmark(context, ref, i, bookmarks[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Prompts for a bookmark name. Blank is refused by NOT popping the dialog —
/// same rule the playlist rename dialog uses (see `_rename` in
/// playlist_screen.dart). Shared by the sheet's rename row and the "Nombrar"
/// SnackBar action in more_menu.dart, so the two never drift apart.
Future<String?> promptBookmarkName(BuildContext context, {String initial = ''}) async {
  final controller = TextEditingController(text: initial);
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nombrar marcador'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) return;
              Navigator.pop(dialogContext, trimmed);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  } finally {
    // Deferred: the dialog's exit transition still reads the controller for
    // a frame or two after showDialog's future resolves.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }
}

Future<void> _renameBookmark(
  BuildContext context,
  WidgetRef ref,
  int index,
  Bookmark bookmark,
) async {
  // Captured before the dialog's await: the notifier belongs to the
  // container and outlives `context`.
  final notifier = ref.read(bookmarksProvider.notifier);
  final name = await promptBookmarkName(context, initial: bookmark.name);
  if (name == null) return;
  await notifier.rename(index, name);
}

/// Removes the bookmark at [index] immediately and offers a few seconds to
/// undo it. Messenger and notifier are captured before anything else, so
/// neither ever touches a BuildContext that may no longer be mounted.
void _deleteBookmark(
  BuildContext context,
  WidgetRef ref,
  int index,
  Bookmark bookmark,
) {
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(bookmarksProvider.notifier);

  notifier.removeAt(index);

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        bookmark.name.isEmpty
            ? 'Marcador borrado · ${fmtDuration(Duration(milliseconds: bookmark.positionMs))}'
            : '«${bookmark.name}» borrado',
      ),
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () => notifier.insert(bookmark),
      ),
    ),
  );
}

class _BookmarkRow extends StatelessWidget {
  const _BookmarkRow({
    super.key,
    required this.index,
    required this.bookmark,
    required this.accent,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final int index;
  final Bookmark bookmark;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final time = fmtDuration(Duration(milliseconds: bookmark.positionMs));
    final hasName = bookmark.name.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFF182036),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              // A diamond, not the chapter's tick — matches BookmarkMarksLayer
              // on the seek bar so the two read as the same kind of thing.
              Icon(Icons.bookmark_rounded, size: 16, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasName ? bookmark.name : time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasName) ...[
                const SizedBox(width: 10),
                Text(
                  time,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.42),
                    fontSize: 11,
                  ),
                ),
              ],
              const SizedBox(width: 2),
              IconButton(
                key: ValueKey('bookmark-rename-$index'),
                icon: const Icon(Icons.edit_outlined, size: 16),
                color: Colors.white.withValues(alpha: 0.6),
                onPressed: onRename,
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
              IconButton(
                key: ValueKey('bookmark-delete-$index'),
                icon: const Icon(Icons.close_rounded, size: 16),
                color: Colors.white.withValues(alpha: 0.6),
                onPressed: onDelete,
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
