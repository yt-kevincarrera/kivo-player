import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/l10n.dart';
import '../../player/library/tv_library.dart';
import '../../player/playlists/playlist.dart';
import '../../player/playlists/playlist_controller.dart';
import '../../player/playlists/playlist_filter.dart';
import '../../player/playlists/playlist_playback.dart';
import '../../core/settings/settings_provider.dart';
import '../player/player_route.dart';
import 'tv_focusable.dart';
import 'tv_page.dart';
import 'tv_panel.dart';

/// Lists use the existing playlist store and playback model; only their
/// presentation and reorder controls differ from the touch interface.
class TvPlaylists extends ConsumerWidget {
  const TvPlaylists({super.key, required this.query});
  final String query;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final playlists = applyPlaylistFilters(
      ref.watch(playlistsProvider),
      query: query,
      sort: playlistSortFor(ref.watch(settingsProvider).playlistSort),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TvButton(
            label: l.playlistNewListLabel,
            icon: Icons.add,
            onPressed: () async {
              final notifier = ref.read(playlistsProvider.notifier);
              final name = await showTvTextInput(
                context,
                l.playlistNewListLabel,
              );
              if (name != null) await notifier.create(name);
            },
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: playlists.isEmpty
              ? Center(
                  child: Text(
                    query.trim().isNotEmpty
                        ? l.playlistsNoSearchResults(query)
                        : l.playlistsEmptyTitle,
                    style: const TextStyle(fontSize: 24),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(6),
                  children: [
                    for (final playlist in playlists)
                      TvOptionRow(
                        label: playlist.name,
                        icon: Icons.playlist_play,
                        value: '${playlist.entries.length}',
                        onPressed: () async {
                          final invoker = FocusManager.instance.primaryFocus;
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  _TvPlaylistScreen(id: playlist.id),
                            ),
                          );
                          if (context.mounted && invoker?.context != null) {
                            invoker!.requestFocus();
                          }
                        },
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _TvPlaylistScreen extends ConsumerWidget {
  const _TvPlaylistScreen({required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final playlist = ref
        .watch(playlistsProvider)
        .where((p) => p.id == id)
        .firstOrNull;
    final resolved = ref.watch(resolvedPlaylistProvider(id));
    return TvPage(
      title: playlist?.name ?? l.libraryTabPlaylists,
      actions: [
        TvButton(
          label: l.playerPlayTooltip,
          icon: Icons.play_arrow,
          onPressed: resolved.any((e) => e.available)
              ? () => _play(context, ref)
              : null,
        ),
        const SizedBox(width: 12),
        TvButton(
          label: l.tvOptions,
          icon: Icons.more_horiz,
          onPressed: playlist == null
              ? null
              : () => _options(context, ref, playlist),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(7),
        children: [
          if (resolved.isEmpty)
            Padding(
              padding: const EdgeInsets.all(30),
              child: Text(
                l.playlistsEmptyTitle,
                style: const TextStyle(fontSize: 24),
              ),
            ),
          for (var i = 0; i < resolved.length; i++)
            Row(
              children: [
                Expanded(
                  child: TvOptionRow(
                    label: resolved[i].entry.displayName,
                    icon: resolved[i].available
                        ? Icons.play_circle_outline
                        : Icons.videocam_off_outlined,
                    onPressed: resolved[i].available
                        ? () => _play(context, ref, index: i)
                        : null,
                  ),
                ),
                TvFocusable(
                  label: '${l.tvOptions}: ${resolved[i].entry.displayName}',
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Icon(Icons.more_horiz, size: 28),
                  ),
                  onPressed: () => _entryOptions(context, ref, i),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _play(BuildContext context, WidgetRef ref, {int? index}) async {
    final playback = ref.read(playlistPlaybackProvider);
    final opened = index == null
        ? playback.play(id)
        : playback.playAt(id, index);
    if (opened) {
      await Navigator.of(context, rootNavigator: true).push(playerRoute());
    }
  }

  Future<void> _options(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) => showTvPanel<void>(
    context: context,
    title: playlist.name,
    builder: (ctx) => ListView(
      padding: const EdgeInsets.all(6),
      children: [
        TvOptionRow(
          label: ctx.l10n.playlistAddToListLabel,
          icon: Icons.add,
          autofocus: true,
          onPressed: () => _add(ctx, ref),
        ),
        TvOptionRow(
          label: ctx.l10n.playlistRenameTitle,
          icon: Icons.edit_outlined,
          onPressed: () async {
            final notifier = ref.read(playlistsProvider.notifier);
            final name = await showTvTextInput(
              ctx,
              ctx.l10n.playlistRenameTitle,
              initial: playlist.name,
            );
            if (name != null) await notifier.rename(id, name);
          },
        ),
        TvOptionRow(
          label: ctx.l10n.playlistDeleteTitle,
          icon: Icons.delete_outline,
          onPressed: () async {
            final notifier = ref.read(playlistsProvider.notifier);
            final confirm = await showTvPanelChoices<bool>(
              ctx,
              ctx.l10n.playlistDeleteTitle,
              [
                (false, ctx.l10n.commonCancel, null),
                (
                  true,
                  ctx.l10n.commonDelete,
                  ctx.l10n.playlistDeleteConfirmBody(playlist.name),
                ),
              ],
              selected: false,
            );
            if (confirm == true && ctx.mounted) {
              final owner = ModalRoute.of(context);
              final navigator = Navigator.of(ctx);
              navigator.popUntil((route) => route == owner);
              navigator.pop();
              await notifier.delete(id);
            }
          },
        ),
      ],
    ),
  );

  Future<void> _add(BuildContext context, WidgetRef ref) => showTvPanel<void>(
    context: context,
    title: context.l10n.playlistAddToListLabel,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final videos = ref.watch(tvLibraryIndexProvider).valueOrNull ?? [];
        return ListView(
          padding: const EdgeInsets.all(6),
          children: [
            for (final video in videos)
              TvOptionRow(
                label: video.name,
                subtitle: video.folder,
                icon: Icons.add,
                onPressed: () async {
                  final notifier = ref.read(playlistsProvider.notifier);
                  Navigator.of(ctx).pop();
                  await notifier.addVideos(id, [video]);
                },
              ),
          ],
        );
      },
    ),
  );

  Future<void> _entryOptions(BuildContext context, WidgetRef ref, int index) {
    final entries =
        ref
            .read(playlistsProvider)
            .where((p) => p.id == id)
            .firstOrNull
            ?.entries ??
        [];
    if (index >= entries.length) return Future.value();
    final entry = entries[index];
    return showTvPanel<void>(
      context: context,
      title: entry.displayName,
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(6),
        children: [
          if (index > 0)
            TvOptionRow(
              label: ctx.l10n.tvMoveEarlier,
              onPressed: () {
                ref
                    .read(playlistsProvider.notifier)
                    .reorder(id, index, index - 1);
                Navigator.of(ctx).pop();
              },
            ),
          if (index + 1 < entries.length)
            TvOptionRow(
              label: ctx.l10n.tvMoveLater,
              onPressed: () {
                ref
                    .read(playlistsProvider.notifier)
                    .reorder(id, index, index + 1);
                Navigator.of(ctx).pop();
              },
            ),
          TvOptionRow(
            label: ctx.l10n.playerQueueRemove,
            icon: Icons.remove_circle_outline,
            onPressed: () {
              final notifier = ref.read(playlistsProvider.notifier);
              notifier.removeEntryAt(id, index);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(entry.displayName),
                  action: SnackBarAction(
                    label: context.l10n.commonUndo,
                    onPressed: () => notifier.insertEntryAt(id, index, entry),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
