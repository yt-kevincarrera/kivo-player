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

/// The third sub-tab in Videos (spec §7): user-made playlists, each shown
/// with a cover (the first AVAILABLE entry's thumbnail) and a count.
class PlaylistsTab extends ConsumerWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);

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
        Positioned(
          right: 16,
          bottom: 16,
          child: _NewPlaylistButton(onTap: () => _createPlaylist(context, ref)),
        ),
      ],
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
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
    await ref.read(playlistsProvider.notifier).create(name);
  }
}

class _NewPlaylistButton extends ConsumerWidget {
  const _NewPlaylistButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Color(ref.watch(settingsProvider).accentColor);
    return FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: accent,
      foregroundColor: onAccent(accent),
      icon: const Icon(Icons.add),
      label: const Text('Nueva lista'),
    );
  }
}

class _PlaylistRow extends ConsumerWidget {
  const _PlaylistRow({required this.playlist});
  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
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

    final countLabel = missing == 0
        ? '${playlist.entries.length} videos'
        : '${playlist.entries.length} videos · $missing no disponibles';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressBounce(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PlaylistScreen(playlistId: playlist.id),
        )),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.08), width: 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
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
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
