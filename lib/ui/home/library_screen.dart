import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../../core/icons/kivo_icons.dart';
import '../../core/settings/settings_provider.dart';
import '../../core/theme/kivo_theme.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../platform/interfaces/media_permission.dart';
import '../../player/library/continue_watching.dart';
import '../../player/library/library_filter.dart';
import '../../player/library/media_index.dart';
import '../../player/library/media_permission.dart';
import '../../player/library/played.dart';
import '../../player/open/video_source.dart';
import '../../player/playlists/playlist_filter.dart';
import '../player/controls/resume_prompt.dart';
import '../player/player_route.dart';
import '../vault/vault_entry_actions.dart';
import '../widgets/failure_view.dart';
import 'folder_screen.dart';
import 'playlists/playlists_tab.dart';
import 'state/library_filter_state.dart';
import 'state/library_selection.dart';
import 'widgets/folder_grid.dart';
import 'widgets/library_empty_state.dart';
import 'widgets/selection_app_bar.dart';
import 'widgets/video_density_feed.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

/// Which sub-tab of Videos is showing: 0 = Todo, 1 = Carpetas, 2 = Listas.
///
/// Lives outside the screen so the root back handler in home_shell.dart can
/// send the user back to Todo instead of out of the app. The screen still
/// owns the pager; it just no longer owns the answer to "which tab".
final librarySubTabProvider = StateProvider<int>((ref) => 0);

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  StreamSubscription<dynamic>? _shareSub;
  late final PageController _pageController;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    try {
      ReceiveSharingIntent.instance.getInitialMedia().then((files) {
        if (!mounted) return;
        if (files.isNotEmpty) _openPath(files.first.path);
      });
      _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen((
        files,
      ) {
        if (files.isNotEmpty) _openPath(files.first.path);
      });
    } catch (_) {
      // ReceiveSharingIntent not available in test/desktop environments.
    }
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _push() {
    ref.read(resumePromptProvider.notifier).state = null;
    Navigator.of(context, rootNavigator: true).push(playerRoute()).then((_) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(playedKeysProvider);
    });
  }

  void _openPath(String path) {
    if (!mounted) return;
    ref.read(currentVideoProvider.notifier).openPath(path);
    _push();
  }

  void _open(VideoItem v, List<VideoItem> all, Rect? origin) {
    ref.read(currentVideoProvider.notifier).openFromList(v, all);
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(playerRoute(originRect: origin)).then((_) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(playedKeysProvider);
    });
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path != null) _openPath(path);
  }

  /// 1→2→3→1, the same cycle the button's tooltip announces.
  int get _nextColumns => (ref.read(settingsProvider).libraryColumns % 3) + 1;

  void _goToPage(int i) {
    if (!_pageController.hasClients) return;
    if (_pageController.page?.round() == i) return;
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _cycleDensity() {
    final s = ref.read(settingsProvider);
    final next = (s.libraryColumns % 3) + 1; // 1→2→3→1
    HapticFeedback.selectionClick();
    _setColumns(next);
  }

  void _setColumns(int cols) {
    final s = ref.read(settingsProvider);
    if (s.libraryColumns == cols) return;
    ref.read(settingsProvider.notifier).set(s.copyWith(libraryColumns: cols));
  }

  void _openSearch() {
    ref.read(librarySearchActiveProvider.notifier).state = true;
    // Same reason _FilterChips' onChanged below clears it on a sub-tab
    // switch: opening search over Listas swaps the visible rows to the
    // filtered set, and a selection left pointing at rows no longer shown
    // is the bug — not just orphaned, actionable-but-wrong (the bulk bar's
    // Borrar would otherwise still see the hidden ones).
    ref.read(playlistsSelectionProvider.notifier).clear();
  }

  void _closeSearch() {
    ref.read(librarySearchActiveProvider.notifier).state = false;
    ref.read(librarySearchQueryProvider.notifier).state = '';
    _searchController.clear();
    _syncPagerToTab();
  }

  /// Search replaces the whole chips+pager column, so closing it REMOUNTS the
  /// PageView — and a re-attached PageController starts at its initialPage
  /// (0), not where the user was. Without this, closing search from Carpetas
  /// or Listas showed Todo under a chip that still said otherwise.
  void _syncPagerToTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      final i = ref.read(librarySubTabProvider);
      if (_pageController.page?.round() != i) _pageController.jumpToPage(i);
    });
  }

  /// The video list currently fed to [VideoDensityFeed] — used both by the
  /// feed itself and by [SelectionAppBar] ("select all" + resolving selected
  /// URIs to [VideoItem]s for batch ops). Mirrors the filtering done in
  /// `_videosTab`/`_searchResults`: same source list, sort, and unwatched
  /// filter; search additionally applies the query. Only meaningful while a
  /// video list (not the Carpetas grid) is showing, which is the only place
  /// selection can be entered from (long-press on a [VideoTile]).
  List<VideoItem> _currentVisibleVideos() {
    final index = ref.watch(libraryIndexProvider).valueOrNull;
    if (index == null) return const [];
    final sort = librarySortFor(ref.watch(settingsProvider).librarySort);
    final unwatchedOnly = ref.watch(libraryUnwatchedOnlyProvider);
    final played = ref.watch(playedKeysProvider);
    final searching = ref.watch(librarySearchActiveProvider);
    return applyLibraryFilters(
      index,
      query: searching ? ref.watch(librarySearchQueryProvider) : '',
      sort: sort,
      unwatchedOnly: unwatchedOnly,
      playedKeys: played,
    );
  }

  @override
  Widget build(BuildContext context) {
    final perm = ref.watch(mediaPermissionProvider);
    final tab = ref.watch(librarySubTabProvider);
    final selecting = ref.watch(librarySelectionProvider).isNotEmpty;
    // The tab can also change from outside (back returns to Todo), and the
    // pager has to follow it there, not only on a chip tap.
    ref.listen<int>(librarySubTabProvider, (_, next) => _goToPage(next));
    // Selection only applies to the video list (Todo tab / search results),
    // never the Carpetas grid — but it's safe to compute unconditionally
    // since it's only ever non-empty when a video list was showing.
    final showingVideos = tab == 0 || ref.watch(librarySearchActiveProvider);
    final scaffold = Scaffold(
      appBar: selecting && showingVideos
          ? SelectionAppBar(allVisible: _currentVisibleVideos())
          : AppBar(
              titleSpacing: 12,
              title: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                // Default AnimatedSwitcher alignment is center — "Kivo" (narrow)
                // and the search TextField (fills the slot) then anchor
                // differently, so the text visibly jumps sideways as it
                // crossfades. Anchoring both to the left (matching the AppBar's
                // normal title position) keeps them in place; only opacity animates.
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                child: ref.watch(librarySearchActiveProvider)
                    ? TextField(
                        key: const ValueKey('search-field'),
                        controller: _searchController,
                        autofocus: true,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        decoration: InputDecoration(
                          // Listas' search filters playlists (by name, and
                          // by member-video name), not videos or folders —
                          // say so, or the hint just lies on that tab.
                          hintText:
                              tab == 2 ? 'Buscar listas' : 'Buscar videos o carpetas',
                          border: InputBorder.none,
                        ),
                        onChanged: (q) =>
                            ref
                                    .read(librarySearchQueryProvider.notifier)
                                    .state =
                                q,
                      )
                    : GestureDetector(
                        key: const ValueKey('title'),
                        behavior: HitTestBehavior.opaque,
                        onLongPress: () {
                          HapticFeedback.selectionClick();
                          openVault(context);
                        },
                        child: Text(
                          'Kivo',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
              ),
              actions: [
                // Distinct keys force Flutter to treat search/close as genuinely
                // different widgets rather than reusing the same IconButton
                // Element with a swapped icon — without this, an in-flight tap
                // ripple can visibly carry over onto the new icon.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: ref.watch(librarySearchActiveProvider)
                      ? IconButton(
                          key: const ValueKey('close'),
                          tooltip: 'Cerrar búsqueda',
                          icon: const Icon(Icons.close),
                          onPressed: _closeSearch,
                        )
                      : IconButton(
                          key: const ValueKey('search'),
                          tooltip: 'Buscar',
                          icon: const Icon(Icons.search),
                          onPressed: _openSearch,
                        ),
                ),
                if (ref.watch(librarySearchActiveProvider) || tab == 0 || tab == 2)
                  // While searching, the search view (not `tab`) decides what
                  // is being sorted — but the search view on Listas IS the
                  // playlist list (see `_body`'s search branch above), so
                  // `tab == 2` is still the right switch even mid-search.
                  (tab == 2 ? const _PlaylistSortMenuButton() : const _SortMenuButton()),
                if (!ref.watch(librarySearchActiveProvider)) ...[
                  // Density is a property of the Todo feed and the Carpetas
                  // grid; on Listas the button would respond and change
                  // nothing.
                  if (tab != 2)
                    IconButton(
                      // Says what the tap DOES, not what the feature is
                      // called: "densidad" told the user nothing.
                      tooltip: _nextColumns == 1
                          ? 'Ver en 1 columna'
                          : 'Ver en $_nextColumns columnas',
                      icon: const Icon(Icons.grid_view),
                      onPressed: _cycleDensity,
                    ),
                  IconButton(
                    tooltip: 'Abrir archivo',
                    icon: KivoIcon(KivoIcons.folderOpen, size: 22),
                    onPressed: _pick,
                  ),
                ],
              ],
            ),
      body: perm.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _accessPrompt(),
        data: (access) =>
            access == MediaAccess.denied ? _accessPrompt() : _body(),
      ),
    );
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(librarySelectionProvider.notifier).clear();
      },
      child: scaffold,
    );
  }

  Widget _body() {
    final index = ref.watch(libraryIndexProvider);
    final tab = ref.watch(librarySubTabProvider);
    return index.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, __) => FailureView.from(
        e,
        onRetry: () => ref.invalidate(mediaIndexProvider),
      ),
      data: (videos) {
        if (ref.watch(librarySearchActiveProvider)) {
          // On Listas, search filters PLAYLISTS, not videos — PlaylistsTab
          // itself reads the same query/active providers (see its build) and
          // switches to `applyPlaylistFilters` when active, so re-showing it
          // here is enough; there is no separate playlist search view.
          if (tab == 2) return PlaylistsTab(onClearSearch: _closeSearch);
          return _searchResults(videos);
        }
        return Column(
          children: [
            _FilterChips(
              selected: tab,
              onChanged: (i) {
                // Selection is only meaningful in the videos list (tab 0):
                // switching sub-tabs away from it would otherwise leave the
                // selection set non-empty while SelectionAppBar is no longer
                // shown, orphaning it (and PopScope would swallow back).
                if (i != tab) {
                  ref.read(librarySelectionProvider.notifier).clear();
                  // Same reason, for the Listas tab's own marks: leaving
                  // the tab must not leave a selection behind with no bar.
                  ref.read(playlistsSelectionProvider.notifier).clear();
                }
                // The listener above moves the pager; setting the tab here
                // keeps a chip tap and a back press on one single path.
                ref.read(librarySubTabProvider.notifier).state = i;
              },
              showUnwatchedToggle: tab == 0,
              unwatchedOnly: ref.watch(libraryUnwatchedOnlyProvider),
              onToggleUnwatched: () {
                final notifier = ref.read(
                  libraryUnwatchedOnlyProvider.notifier,
                );
                notifier.state = !notifier.state;
              },
            ),
            Expanded(
              // The PageView provides the horizontal slide between tabs — no
              // fade. Swipe is disabled so the page changes only via chip taps,
              // which keeps the 2-finger pinch on the videos page conflict-free.
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _KeepAlivePage(
                    key: const ValueKey(0),
                    child: _videosTab(videos),
                  ),
                  _KeepAlivePage(
                    key: const ValueKey(1),
                    child: _foldersTab(videos),
                  ),
                  _KeepAlivePage(
                    key: const ValueKey(2),
                    child: PlaylistsTab(onClearSearch: _closeSearch),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _searchResults(List<VideoItem> videos) {
    final query = ref.watch(librarySearchQueryProvider);
    final sort = librarySortFor(ref.watch(settingsProvider).librarySort);
    final unwatchedOnly = ref.watch(libraryUnwatchedOnlyProvider);
    final played = ref.watch(playedKeysProvider);
    final filtered = applyLibraryFilters(
      videos,
      query: query,
      sort: sort,
      unwatchedOnly: unwatchedOnly,
      playedKeys: played,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              _UnwatchedChip(
                active: unwatchedOnly,
                onTap: () =>
                    ref.read(libraryUnwatchedOnlyProvider.notifier).state =
                        !unwatchedOnly,
              ),
            ],
          ),
        ),
        Expanded(
          child: VideoDensityFeed(
            videos: filtered,
            onOpen: (v, all, origin) => _open(v, all, origin),
            groupByDate: sort == LibrarySort.recent,
            showContinueRow: false,
            // An empty query hasn't failed to match anything — it just hasn't
            // been typed yet, so it keeps the (equally empty) feed.
            emptyState: query.trim().isEmpty
                ? null
                : LibraryEmptyState(
                    icon: Icons.search_off,
                    title: 'No se encontraron videos para "$query"',
                    primaryLabel: 'Borrar búsqueda',
                    onPrimary: _closeSearch,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _videosTab(List<VideoItem> videos) {
    final sort = librarySortFor(ref.watch(settingsProvider).librarySort);
    final unwatchedOnly = ref.watch(libraryUnwatchedOnlyProvider);
    final played = ref.watch(playedKeysProvider);
    final filtered = applyLibraryFilters(
      videos,
      sort: sort,
      unwatchedOnly: unwatchedOnly,
      playedKeys: played,
    );
    return VideoDensityFeed(
      videos: filtered,
      onOpen: (v, all, origin) => _open(v, all, origin),
      groupByDate: sort == LibrarySort.recent,
      showContinueRow: true,
      // `videos` is the unfiltered index: non-empty here means the videos do
      // exist and it's the "No vistos" filter that emptied the list.
      emptyState: _videosEmptyState(hiddenByFilter: videos.isNotEmpty),
    );
  }

  /// The three ways the videos list can legitimately come back empty. They
  /// look alike but the way out differs, so each gets its own state rather
  /// than one generic "no hay nada".
  Widget _videosEmptyState({required bool hiddenByFilter}) {
    if (hiddenByFilter) {
      return LibraryEmptyState(
        icon: Icons.visibility_off_outlined,
        title: 'Ya viste todo',
        subtitle: 'No queda ningún video sin ver.',
        primaryLabel: 'Quitar filtro',
        onPrimary: () =>
            ref.read(libraryUnwatchedOnlyProvider.notifier).state = false,
      );
    }
    // Android 14's partial grant: the scan is honest, it just can't see past
    // the handful of videos the user picked — so the fix is widening that
    // selection, not looking for files that were never hidden.
    if (ref.watch(mediaPermissionProvider).valueOrNull == MediaAccess.limited) {
      return LibraryEmptyState(
        icon: Icons.rule_folder_outlined,
        title: 'Kivo solo ve los videos que elegiste',
        subtitle: 'Amplía la selección para ver el resto de tu galería.',
        primaryLabel: 'Elegir más videos',
        onPrimary: () => ref.read(mediaPermissionProvider.notifier).request(),
        secondaryLabel: 'Abrir archivo',
        onSecondary: _pick,
      );
    }
    return LibraryEmptyState(
      icon: Icons.video_library_outlined,
      title: 'Todavía no hay videos',
      subtitle: 'Cuando grabes o descargues uno aparecerá aquí.',
      primaryLabel: 'Abrir archivo',
      onPrimary: _pick,
      // MediaStore can index a file minutes after it lands, so a manual
      // re-scan is the difference between "empty" and "empty for now".
      secondaryLabel: 'Volver a buscar',
      onSecondary: () => ref.read(mediaIndexProvider.notifier).refresh(),
    );
  }

  Widget _foldersTab(List<VideoItem> videos) => FolderGrid(
    videos: videos,
    onOpenFolder: (folder, items) => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FolderScreen(folder: folder, videos: items),
      ),
    ),
  );

  Widget _accessPrompt() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Da acceso a tus videos para verlos aquí',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => ref.read(mediaPermissionProvider.notifier).request(),
          child: const Text('Dar acceso'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Filter chips row — Todo | Carpetas
// ---------------------------------------------------------------------------
class _FilterChips extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  final bool showUnwatchedToggle;
  final bool unwatchedOnly;
  final VoidCallback onToggleUnwatched;

  const _FilterChips({
    required this.selected,
    required this.onChanged,
    required this.showUnwatchedToggle,
    required this.unwatchedOnly,
    required this.onToggleUnwatched,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          _chip(context, cs, 'Todo', 0),
          const SizedBox(width: 8),
          _chip(context, cs, 'Carpetas', 1, icon: Icons.folder_outlined),
          const SizedBox(width: 8),
          _chip(context, cs, 'Listas', 2, icon: Icons.queue_music_outlined),
          if (showUnwatchedToggle) ...[
            const SizedBox(width: 8),
            _UnwatchedChip(active: unwatchedOnly, onTap: onToggleUnwatched),
          ],
        ],
      ),
    );
  }

  /// A chip with an [icon] carries its label only while it is the selected
  /// one: four full-width chips ate the row, and the three that are not
  /// selected do not need to spell themselves out to stay recognisable.
  /// "Todo" keeps its text always — it has no icon that would read as
  /// "everything" without one.
  /// A chip with an [icon] carries its label only while it is the selected
  /// one: four full-width chips ate the row, and the three that are not
  /// selected do not need to spell themselves out to stay recognisable.
  /// "Todo" keeps its text always — it has no icon that would read as
  /// "everything" without one.
  Widget _chip(
    BuildContext context,
    ColorScheme cs,
    String label,
    int i, {
    IconData? icon,
  }) {
    return Consumer(
      builder: (context, ref, _) {
        final accent = Color(ref.watch(settingsProvider).accentColor);
        final active = selected == i;
        final showLabel = icon == null || active;
        final fg = active ? onAccent(accent) : cs.onSurfaceVariant;
        return Semantics(
          // The unselected chips are icon-only, so the label has to live
          // here or a screen reader gets nothing to read.
          label: label,
          button: true,
          selected: active,
          child: GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: _chipAnim,
              curve: _chipCurve,
              padding: EdgeInsets.symmetric(
                horizontal: showLabel ? 14 : 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: active ? accent : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) Icon(icon, size: 15, color: fg),
                  _chipLabel(
                    show: showLabel,
                    gap: icon != null,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One duration and curve for every chip, so the tabs and the filter next to
/// them expand in step.
const _chipAnim = Duration(milliseconds: 260);
const _chipCurve = Curves.easeOutCubic;

/// The label's width and its opacity ride the same value, so it slides out
/// from behind the icon instead of popping in once the box has finished
/// growing. AnimatedSize alone animated the box but not the text, which is
/// what made the old version feel abrupt.
Widget _chipLabel({
  required bool show,
  required bool gap,
  required Widget child,
}) {
  return TweenAnimationBuilder<double>(
    tween: Tween(begin: show ? 1 : 0, end: show ? 1 : 0),
    duration: _chipAnim,
    curve: _chipCurve,
    builder: (context, t, inner) => ClipRect(
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: t,
        child: Opacity(opacity: t, child: inner),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [if (gap) const SizedBox(width: 5), child],
    ),
  );
}

// ---------------------------------------------------------------------------
// "No vistos" toggle — a filter, not a tab (visually distinct from _chip).
// ---------------------------------------------------------------------------
class _UnwatchedChip extends ConsumerWidget {
  final bool active;
  final VoidCallback onTap;
  const _UnwatchedChip({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final fg = active ? onAccent(accent) : cs.onSurfaceVariant;
    return Semantics(
      label: 'No vistos',
      button: true,
      selected: active,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: _chipAnim,
          curve: _chipCurve,
          padding: EdgeInsets.symmetric(
            horizontal: active ? 14 : 10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: active ? accent : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          // Same rule as the tabs: the label shows only while the filter is
          // on, which is also when it is worth saying out loud.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_off_outlined, size: 15, color: fg),
              _chipLabel(
                show: active,
                gap: true,
                child: Text(
                  'No vistos',
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sort menu — reads/writes settings.librarySort directly (like libraryColumns).
// ---------------------------------------------------------------------------
class _SortMenuButton extends ConsumerWidget {
  const _SortMenuButton();

  static const _labels = {
    LibrarySort.recent: 'Más reciente',
    LibrarySort.nameAsc: 'Nombre A-Z',
    LibrarySort.nameDesc: 'Nombre Z-A',
    LibrarySort.durationDesc: 'Duración: más larga',
    LibrarySort.durationAsc: 'Duración: más corta',
    LibrarySort.sizeDesc: 'Tamaño: más pesado',
    LibrarySort.sizeAsc: 'Tamaño: más liviano',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = librarySortFor(ref.watch(settingsProvider).librarySort);
    return PopupMenuButton<LibrarySort>(
      tooltip: 'Ordenar',
      icon: const Icon(Icons.sort),
      onSelected: (sort) {
        final s = ref.read(settingsProvider);
        ref
            .read(settingsProvider.notifier)
            .set(s.copyWith(librarySort: sort.name));
      },
      itemBuilder: (context) => _labels.entries.map((e) {
        return PopupMenuItem<LibrarySort>(
          value: e.key,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: e.key == current
                    ? const Icon(Icons.check, size: 18)
                    : null,
              ),
              const SizedBox(width: 6),
              Flexible(child: Text(e.value)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Playlist sort menu — same idiom as _SortMenuButton above, but reads/writes
// settings.playlistSort and offers PlaylistSort's own options. A sibling
// rather than a parameterised _SortMenuButton: the two enums (LibrarySort,
// PlaylistSort) don't share a shape, so a single generic button would need
// to take both the label map and the settings field as parameters anyway —
// which is exactly what a small sibling widget already is, more legibly.
// ---------------------------------------------------------------------------
class _PlaylistSortMenuButton extends ConsumerWidget {
  const _PlaylistSortMenuButton();

  static const _labels = {
    PlaylistSort.recent: 'Más reciente',
    PlaylistSort.nameAsc: 'Nombre A-Z',
    PlaylistSort.nameDesc: 'Nombre Z-A',
    PlaylistSort.mostVideos: 'Más videos primero',
    PlaylistSort.lastPlayed: 'Última reproducida',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = playlistSortFor(ref.watch(settingsProvider).playlistSort);
    return PopupMenuButton<PlaylistSort>(
      tooltip: 'Ordenar',
      icon: const Icon(Icons.sort),
      onSelected: (sort) {
        final s = ref.read(settingsProvider);
        ref
            .read(settingsProvider.notifier)
            .set(s.copyWith(playlistSort: sort.name));
      },
      itemBuilder: (context) => _labels.entries.map((e) {
        return PopupMenuItem<PlaylistSort>(
          value: e.key,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: e.key == current
                    ? const Icon(Icons.check, size: 18)
                    : null,
              ),
              const SizedBox(width: 6),
              Flexible(child: Text(e.value)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Keeps a PageView page's Element alive so it isn't disposed/rebuilt when
// swiped offscreen (prevents thumbnail re-fetch/fade-in flicker on return).
// ---------------------------------------------------------------------------
class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({super.key, required this.child});
  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return widget.child;
  }
}
