import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/playlists/playlist.dart';
import '../../../player/playlists/playlist_controller.dart';
import '../../../player/playlists/playlist_playback.dart';
import '../../widgets/press_bounce.dart';
import '../widgets/library_empty_state.dart';
import '../widgets/thumbnail_image.dart';
import 'playlist_screen.dart';

/// This tab's fixed position inside library_screen.dart's sub-tab PageView
/// (Todo=0, Carpetas=1, Listas=2 — see the `_tab` comment and the PageView's
/// `children` list there). Selection-clear-on-leave (below) needs to know its
/// own index and has no other way to learn it without editing that file.

/// Bulk-delete marking for the Listas tab, kept entirely local to this file
/// per the design brief: this is NOT library_screen.dart's
/// SelectionAppBar/SelectionBottomBar machinery, which is gated on the videos
/// tab and belongs to a file this branch does not touch. Selection is active
/// ⇔ the set is non-empty (unmarking the last one exits it, same convention
/// as LibrarySelectionNotifier).
class PlaylistsSelectionNotifier extends StateNotifier<Set<String>> {
  PlaylistsSelectionNotifier() : super(const {});

  void toggle(String id) {
    final next = Set<String>.of(state);
    if (!next.remove(id)) next.add(id);
    state = next;
  }

  void clear() => state = const {};
}

/// Public so library_screen.dart can clear it when the user leaves the
/// Listas sub-tab: the pager keeps every sub-tab alive, so a selection left
/// behind would sit there invisibly with its bar gone and come back on
/// return. The tab itself has no way to notice it stopped being the visible
/// one, and inventing one by reaching up to the ambient pager was worse than
/// letting the screen that owns the pager say so.
final playlistsSelectionProvider =
    StateNotifierProvider<PlaylistsSelectionNotifier, Set<String>>(
  (ref) => PlaylistsSelectionNotifier(),
);

/// The third sub-tab in Videos (spec §7): user-made playlists, each shown
/// with a cover (the first AVAILABLE entry's thumbnail) and a count.
///
/// Long-pressing a row marks it for a bulk delete; while any row is marked,
/// a plain tap toggles the mark instead of opening the playlist (spec: "me
/// gustaria poder borrar la lista sin tener que entrar a ella").
class PlaylistsTab extends ConsumerWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final selecting = ref.watch(playlistsSelectionProvider).isNotEmpty;

    if (playlists.isEmpty) {
      return LibraryEmptyState(
        icon: Icons.playlist_play_rounded,
        title: 'Todavía no tienes listas',
        subtitle:
            'Una lista es un orden que tú eliges: crea una y añade videos '
            'desde la selección o desde el menú de un video.',
        primaryLabel: 'Nueva lista',
        onPrimary: () => _createPlaylist(context, ref),
      );
    }

    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
          itemCount: playlists.length,
          itemBuilder: (context, i) => _PlaylistRow(playlist: playlists[i]),
        ),
        // The selection bar and the "Nueva lista" FAB share the same corner —
        // never both at once, so marking a row doesn't leave a control fighting
        // the bar for space.
        if (selecting)
          const Positioned(left: 0, right: 0, bottom: 0, child: _PlaylistsSelectionBar())
        else
          Positioned(
            right: 16,
            bottom: 16,
            child: _NewPlaylistButton(onTap: () => _createPlaylist(context, ref)),
          ),
      ],
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    // Read before the dialog: the notifier belongs to the container and
    // outlives this widget, where ref does not. Same rule the sheet and the
    // playlist screen follow.
    final playlists = ref.read(playlistsProvider.notifier);
    final controller = TextEditingController();
    String? name;
    try {
      name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Nueva lista'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                // Blank (including whitespace-only) is refused by NOT popping,
                // matching add_to_playlist_sheet.dart's «Nueva lista» dialog.
                if (trimmed.isEmpty) return;
                Navigator.pop(dialogContext, trimmed);
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
    if (name == null) return;
    await playlists.create(name);
  }
}

class _NewPlaylistButton extends ConsumerWidget {
  const _NewPlaylistButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Color(ref.watch(settingsProvider).accentColor);
    return FloatingActionButton.extended(
      heroTag: 'playlists-new',
      onPressed: onTap,
      backgroundColor: accent,
      foregroundColor: onAccent(accent),
      icon: const Icon(Icons.add),
      label: const Text('Nueva lista'),
    );
  }
}

/// Bottom bar shown while any playlist is marked. Mirrors
/// SelectionBottomBar's visual register (full-width, top border, safe-area)
/// without touching that file — this one is local to the Listas tab.
class _PlaylistsSelectionBar extends ConsumerWidget {
  const _PlaylistsSelectionBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(playlistsSelectionProvider);
    final cs = Theme.of(context).colorScheme;
    final count = selected.length;
    final label = count == 1 ? '1 lista seleccionada' : '$count listas seleccionadas';

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
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              TextButton(
                onPressed: () => ref.read(playlistsSelectionProvider.notifier).clear(),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => _delete(context, ref),
                child: Text(
                  'Borrar',
                  style: TextStyle(color: cs.error, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    // Captured BEFORE the confirm dialog's await, matching the rule
    // playlist_screen.dart's own _delete follows: the notifier and the ids to
    // act on outlive whatever happens to `context` while the dialog is up.
    final notifier = ref.read(playlistsProvider.notifier);
    final selectionNotifier = ref.read(playlistsSelectionProvider.notifier);
    final ids = ref.read(playlistsSelectionProvider).toList();
    final n = ids.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar listas'),
        content: Text(
          n == 1
              ? '¿Borrar 1 lista? Esta acción no se puede deshacer. '
                  'Los videos no se borran, solo las listas.'
              : '¿Borrar $n listas? Esta acción no se puede deshacer. '
                  'Los videos no se borran, solo las listas.',
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

    // Deleting several is not undoable — the confirm above is the guard, so
    // clear the mark first and go, same "clear before the slow op" order
    // SelectionBottomBar uses.
    selectionNotifier.clear();
    for (final id in ids) {
      await notifier.delete(id);
    }
  }
}

class _PlaylistRow extends ConsumerStatefulWidget {
  const _PlaylistRow({required this.playlist});
  final Playlist playlist;

  @override
  ConsumerState<_PlaylistRow> createState() => _PlaylistRowState();
}

class _PlaylistRowState extends ConsumerState<_PlaylistRow> {
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final cs = Theme.of(context).colorScheme;
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final selectionIds = ref.watch(playlistsSelectionProvider);
    final selecting = selectionIds.isNotEmpty;
    final selected = selectionIds.contains(playlist.id);

    // Resolves this one playlist against the raw media index. See
    // resolvedPlaylistProvider's doc for why the raw index, not the
    // folder-filtered one.
    final resolved = ref.watch(resolvedPlaylistProvider(playlist.id));
    var missing = 0;
    String? coverId;
    for (final r in resolved) {
      if (r.available) {
        // First wins: a playlist's cover is its first AVAILABLE entry (spec
        // §7), not necessarily its first entry.
        coverId ??= r.video!.id;
      } else {
        missing++;
      }
    }

    final n = playlist.entries.length;
    final videos = n == 1 ? '1 video' : '$n videos';
    final countLabel = missing == 0
        ? videos
        : '$videos · $missing no ${missing == 1 ? 'disponible' : 'disponibles'}';

    void handleTap() {
      if (selecting) {
        ref.read(playlistsSelectionProvider.notifier).toggle(playlist.id);
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlaylistScreen(playlistId: playlist.id),
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => ref.read(playlistsSelectionProvider.notifier).toggle(playlist.id),
        onLongPressDown: (_) => setState(() => _pressing = true),
        onLongPressCancel: () => setState(() => _pressing = false),
        onLongPressUp: () => setState(() => _pressing = false),
        child: AnimatedScale(
          scale: _pressing ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: PressBounce(
            onTap: handleTap,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                // Marked is a clearly different border, not a shade
                // difference — the app has rejected too-subtle selection
                // cues before.
                border: Border.all(
                  color: selected ? accent : cs.onSurface.withValues(alpha: 0.08),
                  width: selected ? 2 : 0.5,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: coverId == null
                              ? Container(
                                  color: cs.surfaceContainerHigh,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.playlist_play_rounded,
                                    color: cs.onSurfaceVariant,
                                  ),
                                )
                              : ThumbnailImage(coverId, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                playlist.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                countLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!selecting) ...[
                        Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                      ] else
                        const SizedBox(width: 44),
                    ],
                  ),
                  if (selected)
                    Positioned.fill(
                      // IgnorePointer: this is a purely visual tint sitting on
                      // top of the row in the Stack's paint order — without
                      // it, hit testing lands on this box instead of passing
                      // through to the Row underneath.
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: accent.withValues(alpha: 0.22)),
                        ),
                      ),
                    ),
                  if (selecting)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IgnorePointer(child: _selectionBadge(accent, selected)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionBadge(Color accent, bool selected) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? accent : Colors.black.withValues(alpha: 0.35),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: selected ? Icon(Icons.check, size: 14, color: onAccent(accent)) : null,
      );
}
