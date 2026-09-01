import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/library/continue_watching.dart';
import '../../../player/library/played.dart';
import '../../../player/playlists/playlist.dart';
import '../../../player/playlists/playlist_controller.dart';
import '../../../player/playlists/playlist_playback.dart';
import '../../player/player_route.dart';
import '../state/library_selection.dart';
import '../widgets/library_empty_state.dart';
import '../widgets/selection_app_bar.dart';
import '../widgets/video_tile.dart';

/// One playlist's entries, in order: reorder, remove, rename the playlist,
/// delete the playlist, and play (spec §7).
class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    Playlist? playlist;
    for (final p in playlists) {
      if (p.id == playlistId) {
        playlist = p;
        break;
      }
    }

    if (playlist == null) {
      // The playlist no longer resolves — most likely this screen's own
      // delete already popped it and this build is a rebuild racing that
      // pop (Riverpod's state change and Navigator's pop are not atomic).
      // Render nothing and finish the pop on the next frame rather than
      // reading a null title/entries and crashing.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }

    final resolved = ref.watch(resolvedPlaylistProvider(playlistId));
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final selected = ref.watch(librarySelectionProvider);
    final selecting = selected.isNotEmpty;

    final scaffold = Scaffold(
      appBar: selecting
          ? SelectionAppBar(
              allVisible: [
                for (final r in resolved)
                  if (r.available) r.video!,
              ],
            )
          : AppBar(
              title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'rename') _rename(context, ref, playlist!);
                    if (value == 'delete') _delete(context, ref, playlist!);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Renombrar lista')),
                    PopupMenuItem(value: 'delete', child: Text('Borrar lista')),
                  ],
                ),
              ],
            ),
      floatingActionButton: selecting
          ? null
          : FloatingActionButton.extended(
              // Distinct tags: otherwise the tab's «Nueva lista» pill flies
              // across and morphs into this one on the push, which reads as
              // a glitch.
              heroTag: 'playlist-play',
              onPressed: () => _play(context, ref),
              backgroundColor: accent,
              foregroundColor: onAccent(accent),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Reproducir'),
            ),
      body: resolved.isEmpty
          ? const LibraryEmptyState(
              icon: Icons.playlist_play_rounded,
              title: 'Esta lista está vacía',
              subtitle: 'Añade videos desde la selección o desde el menú de '
                  'un video, con «Añadir a lista».',
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 96),
              buildDefaultDragHandles: false,
              itemCount: resolved.length,
              onReorder: (oldIndex, newIndex) {
                // Flutter reports newIndex as the position BEFORE the
                // dragged item is removed from the list, so dragging item 0
                // to the very end reports newIndex == length, not the real
                // final index (length - 1). PlaylistsNotifier.reorder treats
                // newIndex as the FINAL position, so the down-drag case
                // (oldIndex < newIndex) needs one subtracted before calling
                // through. Dragging up needs no adjustment: the reported
                // index is already the final one.
                final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
                ref.read(playlistsProvider.notifier).reorder(playlistId, oldIndex, adjusted);
              },
              itemBuilder: (context, i) {
                final re = resolved[i];
                return _buildEntryRow(context, ref, i, re, selecting, selected);
              },
            ),
    );

    // Back clears an active mark instead of leaving the screen — same
    // convention as folder_screen.dart / home_shell.dart. The global
    // SelectionBottomBar (mounted once in HomeShell, below every pushed
    // screen in this tab's Navigator) reacts to librarySelectionProvider on
    // its own and needs no wiring here.
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(librarySelectionProvider.notifier).clear();
      },
      child: scaffold,
    );
  }

  /// One playlist row, grip-first: [Icons.drag_handle] is the only drag
  /// target (`ReorderableListView.builder` above sets
  /// `buildDefaultDragHandles: false`, so nothing else on the row starts a
  /// drag) — freeing the rest of the row for long-press-to-mark. An
  /// available entry reuses [VideoTile] itself, the same widget the library
  /// and folder screens use, so a playlist row is not an imitation of a
  /// library row but literally one: identical thumbnail box (fixing the
  /// inconsistent-thumbnail-size bug — VideoTile wraps its thumbnail in a
  /// `Stack(fit: StackFit.expand)`, which forces every thumbnail to the same
  /// box regardless of the source video's own aspect ratio, whereas the old
  /// hand-rolled row did not), selection tinting, and long-press. VideoTile's
  /// only trailing affordance is a fixed ⋮ icon with no menu of its own here
  /// to open, so it is wired directly to this entry's one relevant action:
  /// quitting it from the list (same remove-with-Deshacer behavior as
  /// before). An unavailable entry has no [VideoItem] to hand VideoTile, so
  /// it is rebuilt by hand to match VideoTile's list-row metrics exactly
  /// (168-wide 16:9 thumbnail box, 8-radius corners, same text styles) while
  /// keeping its own un-softened unavailable treatment, and carries neither
  /// long-press-to-mark nor a selection tint — it cannot join the selection.
  Widget _buildEntryRow(
    BuildContext context,
    WidgetRef ref,
    int i,
    ResolvedEntry re,
    bool selecting,
    Set<String> selected,
  ) {
    final cs = Theme.of(context).colorScheme;
    final content = re.available
        ? VideoTile(
            video: re.video!,
            listRow: true,
            sizeLabel: fmtSize(re.video!.sizeBytes),
            selected: selected.contains(re.video!.uri),
            selecting: selecting,
            // Not a ⋮: this button removes the entry, so it says so.
            // Sharing, renaming and the rest live behind long-press, the
            // same selection the library uses.
            trailingIcon: Icons.close,
            trailingTooltip: 'Quitar de la lista',
            onOptions: () => _removeEntry(context, ref, i, re),
            onLongPress: () {
              HapticFeedback.selectionClick();
              ref.read(librarySelectionProvider.notifier).toggle(re.video!.uri);
            },
            onTap: (origin) {
              if (selecting) {
                HapticFeedback.selectionClick();
                ref.read(librarySelectionProvider.notifier).toggle(re.video!.uri);
                return;
              }
              _openEntry(context, ref, i);
            },
          )
        : _UnavailableEntryRow(
            resolved: re,
            onRemove: () => _removeEntry(context, ref, i, re),
          );

    return Padding(
      key: ValueKey('playlist-entry-$i'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: i,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.drag_handle, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }

  /// Removes the entry at [index] and offers a few seconds to undo it — captured
  /// before anything else, matching this branch's rule of grabbing the
  /// messenger and the notifier BEFORE any await, so neither ever touches a
  /// BuildContext that may no longer be mounted.
  void _removeEntry(BuildContext context, WidgetRef ref, int index, ResolvedEntry re) {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(playlistsProvider.notifier);
    final entry = re.entry;
    // Same name the row itself shows: the resolved video's current name when
    // there is one, the stored name otherwise.
    final name = re.video?.name ?? entry.displayName;

    notifier.removeEntryAt(playlistId, index);

    // Hide any snackbar already up first — removing several entries quickly
    // must not queue a snackbar per removal.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('«$name» quitado de la lista'),
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () => notifier.insertEntryAt(playlistId, index, entry),
      ),
    ));
  }

  void _openEntry(BuildContext context, WidgetRef ref, int index) {
    final ok = ref.read(playlistPlaybackProvider).playAt(playlistId, index);
    if (!ok) return;
    Navigator.of(context, rootNavigator: true).push(playerRoute()).then((_) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(playedKeysProvider);
    });
  }

  void _play(BuildContext context, WidgetRef ref) {
    final ok = ref.read(playlistPlaybackProvider).play(playlistId);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nada disponible para reproducir ahora mismo')),
      );
      return;
    }
    Navigator.of(context, rootNavigator: true).push(playerRoute()).then((_) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(playedKeysProvider);
    });
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Playlist playlist) async {
    // Captured before the confirm dialog's await — the notifier belongs to
    // the container and outlives whatever happens to `context`.
    final notifier = ref.read(playlistsProvider.notifier);
    final controller = TextEditingController(text: playlist.name);
    String? name;
    try {
      name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Renombrar lista'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                // Blank (including whitespace-only) is refused by NOT
                // popping, matching the create-list dialogs elsewhere.
                if (trimmed.isEmpty) return;
                Navigator.pop(dialogContext, trimmed);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
    } finally {
      // Deferred: the dialog's exit transition still reads the controller
      // for a frame or two after showDialog's future resolves.
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
    if (name == null) return;
    await notifier.rename(playlist.id, name);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Playlist playlist) async {
    // Captured BEFORE the confirm dialog's await. Deleting is not undoable,
    // so once the user confirms we pop this screen immediately — before the
    // write — rather than after: the write is async, and popping after it
    // would race a rebuild of this very screen against a playlistId that no
    // longer resolves (see the null-guard in build()).
    final navigator = Navigator.of(context);
    final notifier = ref.read(playlistsProvider.notifier);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar lista'),
        content: Text(
          '¿Borrar «${playlist.name}»? Esta acción no se puede deshacer. '
          'Los videos no se borran, solo la lista.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Borrar', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    navigator.pop();
    await notifier.delete(playlist.id);
  }
}

/// An unavailable entry's row: no [VideoItem] exists behind it, so it cannot
/// be a [VideoTile] (which requires one) — this hand-builds the exact same
/// list-row metrics instead (168-wide 16:9 thumbnail box, 8-radius corners,
/// same 10px thumbnail↔text gap, same title text style) so it occupies the
/// identical row shape as the available entries around it.
///
/// It reads as unmistakably unavailable rather than merely dimmed — a
/// strikethrough name, a red icon and a red label, not just lower opacity —
/// per a standing note in this app that a subtle-only cue gets missed. It
/// carries neither long-press-to-mark nor a selection tint (there is no
/// [VideoItem] to add to the selection) and stays draggable — the grip
/// beside it is wired the same as every other row.
class _UnavailableEntryRow extends StatelessWidget {
  const _UnavailableEntryRow({required this.resolved, required this.onRemove});

  final ResolvedEntry resolved;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 168,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: cs.surfaceContainerHigh,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.playlist_play_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Icon(Icons.error_outline, size: 16, color: cs.error),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  // The resolved video's name when there is one: a rename
                  // done outside Kivo never reached the entry, and the row
                  // should not keep showing a name the file no longer has.
                  // An unavailable entry has only the stored name to offer.
                  resolved.video?.name ?? resolved.entry.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'No disponible',
                  style: TextStyle(
                    color: cs.error,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.more_vert, size: 20, color: cs.onSurfaceVariant),
            onPressed: onRemove,
            tooltip: 'Quitar de la lista',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
