import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/playlists/playlist.dart';
import '../../../player/playlists/playlist_controller.dart';
import '../../../player/playlists/playlist_filter.dart';
import '../../../player/playlists/playlist_playback.dart';
import '../../widgets/press_bounce.dart';
import '../state/library_filter_state.dart';
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
    final allPlaylists = ref.watch(playlistsProvider);
    final selecting = ref.watch(playlistsSelectionProvider).isNotEmpty;

    if (allPlaylists.isEmpty) {
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

    // library_screen.dart's search field is shared with the video tabs, but
    // while THIS tab is showing (normally, or via its search branch — see
    // that file's `_body`) it filters playlists instead: by the playlist's
    // own name first, and by any entry's display name as a second criterion
    // ("which list did I put episode 4 in?"). Sort applies unconditionally,
    // searching or not — it's the persisted Listas-tab order, not a search
    // option.
    final searching = ref.watch(librarySearchActiveProvider);
    final query = searching ? ref.watch(librarySearchQueryProvider) : '';
    final sort = playlistSortFor(ref.watch(settingsProvider).playlistSort);
    final playlists = applyPlaylistFilters(allPlaylists, query: query, sort: sort);

    // A non-empty library of playlists that a search query narrowed to
    // nothing — distinct from the "no playlists at all" state above, same
    // way _searchResults' own empty state differs from _videosEmptyState in
    // library_screen.dart.
    if (playlists.isEmpty) {
      return LibraryEmptyState(
        icon: Icons.search_off,
        title: 'Ninguna lista coincide con "$query"',
      );
    }

    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
          itemCount: playlists.length,
          // Keyed by playlist id: this row now carries swipe-reveal state
          // (_offset) that must stay with the right playlist across
          // reorders/deletes, not get silently reused by list position.
          itemBuilder: (context, i) => _PlaylistRow(
            key: ValueKey(playlists[i].id),
            playlist: playlists[i],
          ),
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
                // Keyed: a playlist row's own swipe-to-delete button also
                // reads "Borrar" now, so tests need a way to address this
                // one — the bulk bar's — specifically.
                key: const Key('playlists-bulk-borrar'),
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

/// Tracks which playlist row (by id) currently has its swipe actions
/// revealed, so revealing one row's actions closes any other's. Kept local
/// to this file, same convention as PlaylistsSelectionNotifier above. Null
/// means no row is swiped open.
final _playlistSwipeOpenRowProvider = StateProvider<String?>((ref) => null);

/// Width of each revealed swipe-action button (Renombrar / Borrar) — wide
/// enough to be an easy thumb target, matching the row's own thumbnail width
/// below.
const double _kSwipeActionWidth = 96;

/// Renames [playlist] via the same dialog shape as playlist_screen.dart's
/// private `_rename` (title, TextField pre-filled with the current name,
/// Cancelar/Guardar, blank refused by not popping, deferred controller
/// dispose). Duplicated here because that method is private to that file,
/// which this branch must not edit — keep the two in sync by hand if either
/// one changes.
Future<void> _renamePlaylist(BuildContext context, WidgetRef ref, Playlist playlist) async {
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
              // Blank (including whitespace-only) is refused by NOT popping,
              // matching every other rename/create dialog in this app.
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
  if (name == null) return;
  await notifier.rename(playlist.id, name);
}

class _PlaylistRow extends ConsumerStatefulWidget {
  const _PlaylistRow({super.key, required this.playlist});
  final Playlist playlist;

  @override
  ConsumerState<_PlaylistRow> createState() => _PlaylistRowState();
}

class _PlaylistRowState extends ConsumerState<_PlaylistRow>
    with SingleTickerProviderStateMixin {
  bool _pressing = false;

  // Horizontal swipe reveal. `_offset` is the row content's current
  // translateX: 0 closed, negative reveals Borrar on the right (swipe
  // left), positive reveals Renombrar on the left (swipe right). Dragging
  // sets it directly for 1:1 finger tracking; releasing hands off to
  // `_swipeController` to animate the snap to the nearest resting position.
  double _offset = 0;
  late final AnimationController _swipeController;
  Animation<double>? _swipeAnimation;

  @override
  void initState() {
    super.initState();
    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _swipeAnimation?.removeListener(_onSwipeTick);
    _swipeController.dispose();
    super.dispose();
  }

  void _onSwipeTick() {
    setState(() => _offset = _swipeAnimation!.value);
  }

  void _animateTo(double target) {
    _swipeAnimation?.removeListener(_onSwipeTick);
    _swipeAnimation = Tween<double>(begin: _offset, end: target).animate(
      CurvedAnimation(parent: _swipeController, curve: Curves.easeOut),
    )..addListener(_onSwipeTick);
    _swipeController
      ..stop()
      ..value = 0
      ..forward();
  }

  /// Snaps shut instantly (no slide) and forgets this row as the open one,
  /// if it was. Used right before an action fires (Borrar/Renombrar) and
  /// when multi-select marking starts — an animated slide would just be in
  /// the way in both cases.
  void _forceClose() {
    _swipeAnimation?.removeListener(_onSwipeTick);
    _swipeController.stop();
    if (_offset != 0) setState(() => _offset = 0);
    if (ref.read(_playlistSwipeOpenRowProvider) == widget.playlist.id) {
      ref.read(_playlistSwipeOpenRowProvider.notifier).state = null;
    }
  }

  void _onDragStart(DragStartDetails details) {
    _swipeAnimation?.removeListener(_onSwipeTick);
    _swipeController.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _offset =
          (_offset + details.delta.dx).clamp(-_kSwipeActionWidth, _kSwipeActionWidth);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final opensBorrar = _offset < -_kSwipeActionWidth / 2;
    final opensRenombrar = _offset > _kSwipeActionWidth / 2;
    if (opensBorrar || opensRenombrar) {
      ref.read(_playlistSwipeOpenRowProvider.notifier).state = widget.playlist.id;
      _animateTo(opensBorrar ? -_kSwipeActionWidth : _kSwipeActionWidth);
    } else {
      if (ref.read(_playlistSwipeOpenRowProvider) == widget.playlist.id) {
        ref.read(_playlistSwipeOpenRowProvider.notifier).state = null;
      }
      _animateTo(0);
    }
  }

  Future<void> _handleDeleteTapped() async {
    // Tapping Borrar here IS the confirmation (spec): unlike the bulk-delete
    // bar's Borrar, which deletes several at once and asks first, this
    // deletes just this one playlist and shows no dialog after the tap.
    final notifier = ref.read(playlistsProvider.notifier);
    _forceClose();
    await notifier.delete(widget.playlist.id);
  }

  void _handleRenameTapped() {
    _forceClose();
    _renamePlaylist(context, ref, widget.playlist);
  }

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final cs = Theme.of(context).colorScheme;
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final selectionIds = ref.watch(playlistsSelectionProvider);
    final selecting = selectionIds.isNotEmpty;
    final selected = selectionIds.contains(playlist.id);

    // Closes this row's swipe reveal the moment another row's opens, or the
    // moment multi-select marking starts: two competing gestures on one row
    // is confusing, and only one row's actions should ever be visible.
    ref.listen<String?>(_playlistSwipeOpenRowProvider, (previous, next) {
      if (next != playlist.id && _offset != 0) _animateTo(0);
    });
    ref.listen<Set<String>>(playlistsSelectionProvider, (previous, next) {
      if (next.isNotEmpty) _forceClose();
    });

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
      final openRowId = ref.read(_playlistSwipeOpenRowProvider);
      if (openRowId != null) {
        // A tap anywhere while a row's actions are showing — this row's own
        // content or another row's — closes them first rather than also
        // opening the playlist or toggling a mark (spec: swiping the row
        // back or touching another row is how the reveal goes away).
        ref.read(_playlistSwipeOpenRowProvider.notifier).state = null;
        if (_offset != 0) _animateTo(0);
        return;
      }
      if (selecting) {
        ref.read(playlistsSelectionProvider.notifier).toggle(playlist.id);
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlaylistScreen(playlistId: playlist.id),
      ));
    }

    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: selecting || _offset != 0
          ? null
          : () => ref.read(playlistsSelectionProvider.notifier).toggle(playlist.id),
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
      );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            // Swipe actions live behind the row content, uncovered only by
            // `_offset` — they don't need to exist at all (and shouldn't be
            // tappable) while multi-select marking owns the gesture.
            if (!selecting)
              Positioned.fill(
                child: _SwipeActionsBackground(
                  playlistId: playlist.id,
                  onRename: _handleRenameTapped,
                  onDelete: _handleDeleteTapped,
                ),
              ),
            // behavior is deliberately left at the default (deferToChild),
            // NOT opaque: opaque would claim this detector's own untranslated
            // bounds unconditionally, which — since Transform.translate moves
            // where the CHILD paints/hit-tests but not this detector's own
            // bounds — would permanently block the swipe buttons behind it
            // from ever being reachable, at any offset. deferToChild instead
            // asks the translated `row` whether the (inverse-transformed)
            // point is still within ITS bounds, so a point over the strip
            // `_offset` has uncovered correctly falls through to the
            // background beneath.
            GestureDetector(
              onHorizontalDragStart: selecting ? null : _onDragStart,
              onHorizontalDragUpdate: selecting ? null : _onDragUpdate,
              onHorizontalDragEnd: selecting ? null : _onDragEnd,
              child: Transform.translate(
                offset: Offset(_offset, 0),
                child: row,
              ),
            ),
          ],
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

/// The two swipe-revealed actions sitting behind a playlist row: Renombrar
/// on the left (revealed swiping right) and Borrar on the right (revealed
/// swiping left). Lives in a Positioned.fill behind the row's own
/// Transform.translate, so it's only ever visible in the strip `_offset`
/// uncovers.
class _SwipeActionsBackground extends StatelessWidget {
  const _SwipeActionsBackground({
    required this.playlistId,
    required this.onRename,
    required this.onDelete,
  });

  final String playlistId;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SwipeActionButton(
          // Keyed by playlist id: a row's own "Borrar" collides on text
          // with the bulk-select bar's, and "Renombrar" (this one) with
          // nothing else — keyed anyway for symmetry and so tests never
          // have to guess which row's button they hit.
          key: ValueKey('playlist-swipe-renombrar-$playlistId'),
          label: 'Renombrar',
          icon: Icons.edit_rounded,
          background: cs.secondaryContainer,
          foreground: cs.onSecondaryContainer,
          onTap: onRename,
        ),
        const Expanded(child: SizedBox()),
        _SwipeActionButton(
          key: ValueKey('playlist-swipe-borrar-$playlistId'),
          label: 'Borrar',
          icon: Icons.delete_outline_rounded,
          background: cs.error,
          foreground: cs.onError,
          onTap: onDelete,
        ),
      ],
    );
  }
}

/// One swipe-action button: fixed-width, stretched to the row's full
/// height — an easy thumb target. Tapping it fires immediately; Borrar's
/// confirmation IS the tap (spec), no dialog after it.
///
/// The icon+label are wrapped in a FittedBox rather than sized to a
/// guessed pixel budget: row height varies with content (a missing-videos
/// second line, font metrics, …), and this content must never overflow
/// whatever height a given row happens to be.
class _SwipeActionButton extends StatelessWidget {
  const _SwipeActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kSwipeActionWidth,
      child: Material(
        color: background,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: foreground),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style:
                        TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
