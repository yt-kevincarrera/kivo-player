import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/library/continue_watching.dart';
import '../../../player/library/played.dart';
import '../../../player/playlists/playlist.dart';
import '../../../player/playlists/playlist_controller.dart';
import '../../../player/playlists/playlist_playback.dart';
import '../../player/player_route.dart';
import '../widgets/library_empty_state.dart';
import '../widgets/thumbnail_image.dart';

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

    return Scaffold(
      appBar: AppBar(
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
      floatingActionButton: FloatingActionButton.extended(
        // Distinct tags: otherwise the tab's «Nueva lista» pill flies across
        // and morphs into this one on the push, which reads as a glitch.
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
                return _EntryRow(
                  key: ValueKey('playlist-entry-$i'),
                  index: i,
                  resolved: re,
                  onTap: re.available ? () => _openEntry(context, ref, i) : null,
                  onRemove: () => _removeEntry(context, ref, i, re),
                );
              },
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

/// One row: the video's name, or `No disponible` when it can't be resolved.
///
/// An unavailable entry reads as unmistakably unavailable rather than merely
/// dimmed — a strikethrough name, a red icon and a red label, not just lower
/// opacity — per a standing note in this app that a subtle-only cue gets
/// missed. It stays draggable (ReorderableListView owns that, independent of
/// this row's own tap handler) and removable (its own button, always live).
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required super.key,
    required this.index,
    required this.resolved,
    required this.onTap,
    required this.onRemove,
  });

  final int index;
  final ResolvedEntry resolved;
  final VoidCallback? onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final available = resolved.available;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: available ? cs.surfaceContainerHighest : cs.errorContainer.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: available
            ? null
            : Border.all(color: cs.error.withValues(alpha: 0.4), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Same row scale as VideoTile's list row (168 wide, 16:9,
                // 8-radius corners) so a playlist entry reads like any other
                // video row in the app. An unavailable entry has no video and
                // therefore no id to fetch a thumbnail for, so it gets the
                // same coverless-playlist placeholder the Listas tab uses,
                // with a small error badge standing in for the icon this
                // row used to show alone — the un-softened cue moves onto
                // the thumbnail instead of disappearing.
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 168,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: available
                          ? ThumbnailImage(resolved.video!.id, fit: BoxFit.cover)
                          : Stack(
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
                                  child: Icon(
                                    Icons.error_outline,
                                    size: 16,
                                    color: cs.error,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        // The resolved video's name when there is one: a
                        // rename done outside Kivo never reached the entry,
                        // and the row should not keep showing a name the file
                        // no longer has. An unavailable entry has only the
                        // stored name to offer.
                        resolved.video?.name ?? resolved.entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: available ? cs.onSurface : cs.onSurfaceVariant,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          decoration: available ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      if (!available) ...[
                        const SizedBox(height: 2),
                        Text(
                          'No disponible',
                          style: TextStyle(
                            color: cs.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('playlist-remove-$index'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                  tooltip: 'Quitar de la lista',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
