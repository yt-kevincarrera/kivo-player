import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/playlists/playlist.dart';
import '../../../player/playlists/playlist_controller.dart';

/// Bottom sheet offered from both `SelectionBottomBar` and the video `⋮`
/// menu: pick an existing playlist to append [videos] to, or make a new one.
/// Both entry points share this single sheet on purpose (spec §7) — building
/// a list in one go and adding one video you're looking at are the same
/// action from the store's point of view.
class _AddToPlaylistSheet extends ConsumerWidget {
  const _AddToPlaylistSheet({required this.videos});

  final List<VideoItem> videos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final playlists = ref.watch(playlistsProvider);
    // Captured before any await below — the sheet pops on both paths and
    // `context` is defunct from that point on.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    return SafeArea(
      // Scroll-controlled and height-bounded, as more_menu.dart had to be: a
      // dozen playlists must scroll instead of overflowing the sheet. Only the
      // rows scroll here — the title and "Nueva lista" stay outside, so they
      // are always reachable. That leaves the fixed part unscrollable, so any
      // future row added above or below the list has to earn its height.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Añadir a lista',
                  style: TextStyle(
                      color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            if (playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text(
                  'Todavía no tienes listas. Crea una para empezar.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final p in playlists)
                        _row(
                          context,
                          Icons.playlist_play_rounded,
                          p.name,
                          cs.onSurface,
                          () => _addTo(ref, messenger, navigator, p),
                          trailing: '${p.entries.length}',
                        ),
                    ],
                  ),
                ),
              ),
            _row(
              context,
              Icons.add,
              'Nueva lista',
              cs.primary,
              () => _createAndAdd(context, ref, messenger, navigator),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap, {
    String? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 15)),
          ),
          if (trailing != null)
            Text(trailing, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ]),
      ),
    );
  }

  void _addTo(
    WidgetRef ref,
    ScaffoldMessengerState messenger,
    NavigatorState navigator,
    Playlist playlist,
  ) {
    // No await between reading the controller and popping: nothing here
    // crosses an async gap, so touching navigator/messenger stays safe.
    ref.read(playlistsProvider.notifier).addVideos(playlist.id, videos);
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Añadido a «${playlist.name}»')));
  }

  Future<void> _createAndAdd(
    BuildContext context,
    WidgetRef ref,
    ScaffoldMessengerState messenger,
    NavigatorState navigator,
  ) async {
    // Read the notifier before anything can pop this sheet: it belongs to the
    // container and outlives the sheet, where `ref` does not.
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
                // Blank (including whitespace-only) is refused by NOT popping:
                // the dialog stays open so the user sees why nothing happened,
                // rather than a silent no-op that just closes it.
                if (trimmed.isEmpty) return;
                Navigator.pop(dialogContext, trimmed);
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      );
    } finally {
      // Deferred for the same reason as rename_dialog.dart: the dialog's
      // exit transition still reads the controller for a frame or two.
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
    if (name == null) return;

    // Pop BEFORE the writes, not after. The sheet is dismissible, so a user
    // who swipes it away while the writes are in flight would otherwise have
    // this pop land on the screen underneath and send them back a level.
    navigator.pop();
    final playlist = await playlists.create(name);
    await playlists.addVideos(playlist.id, videos);
    messenger.showSnackBar(SnackBar(content: Text('Añadido a «${playlist.name}»')));
  }
}

/// Opens the add-to-playlist sheet for [videos].
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  List<VideoItem> videos,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) => _AddToPlaylistSheet(videos: videos),
  );
}
