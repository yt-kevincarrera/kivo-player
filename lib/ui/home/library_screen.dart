import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../../core/icons/kivo_icons.dart';
import '../../core/settings/settings_provider.dart';
import '../../l10n/l10n.dart';
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
import 'library_layout.dart';
import 'playlists/playlists_tab.dart';
import 'state/library_filter_state.dart';
import 'state/library_selection.dart';
import 'widgets/folder_grid.dart';
import 'widgets/library_empty_state.dart';
import 'widgets/selection_app_bar.dart';
import 'widgets/video_density_feed.dart';
import '../widgets/kivo_focusable.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.sideTools = false});
  final bool sideTools;

  @override
  ConsumerState<LibraryScreen> createState() => LibraryScreenState();
}

/// Which sub-tab of Videos is showing: 0 = Todo, 1 = Carpetas, 2 = Listas.
///
/// Lives outside the screen so the root back handler in home_shell.dart can
/// send the user back to Todo instead of out of the app. The screen still
/// owns the pager; it just no longer owns the answer to "which tab".
final librarySubTabProvider = StateProvider<int>((ref) => 0);

class LibraryScreenState extends ConsumerState<LibraryScreen> {
  // Quick taps on the title toggle incognito (a shortcut to the switch in
  // Ajustes › Reproducción avanzada; how many is a setting, 0 = off). Taps
  // more than [_tapGap] apart start the count again, so ordinary taps never
  // add up to it.
  static const _tapGap = Duration(milliseconds: 600);
  int _titleTaps = 0;
  DateTime _lastTitleTap = DateTime.fromMillisecondsSinceEpoch(0);

  void _onTitleTap() {
    final needed = ref.read(settingsProvider).incognitoTapCount;
    if (needed <= 0) return;
    final now = DateTime.now();
    _titleTaps = now.difference(_lastTitleTap) > _tapGap ? 1 : _titleTaps + 1;
    _lastTitleTap = now;
    if (_titleTaps < needed) return;
    _titleTaps = 0;
    final s = ref.read(settingsProvider);
    final on = !s.incognito;
    HapticFeedback.mediumImpact();
    ref.read(settingsProvider.notifier).set(s.copyWith(incognito: on));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            on
                ? context.l10n.libraryIncognitoOnSnackbar
                : context.l10n.libraryIncognitoOffSnackbar,
          ),
        ),
      );
  }

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

  void _openPath(String path, {String? originalUri, String? displayName}) {
    if (!mounted) return;
    final known = ref
        .read(libraryIndexProvider)
        .valueOrNull
        ?.where(
          (v) =>
              v.uri == originalUri ||
              (v.filePath.isNotEmpty && v.filePath == path),
        )
        .toList();
    final notifier = ref.read(currentVideoProvider.notifier);
    if (known != null && known.length == 1) {
      notifier.openFromList(known.single, [known.single]);
    } else {
      notifier.openPath(
        path,
        originalUri: originalUri,
        displayName: displayName,
      );
    }
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
    // Some video containers (notably RealMedia) have an application/* MIME
    // type, or none at all on a vendor's Android build. Let the playback
    // engine inspect the selected file instead of hiding it in the picker.
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final picked = result?.files.single;
    final path = picked?.path;
    if (path != null) {
      _openPath(
        path,
        originalUri: picked!.identifier,
        displayName: picked.name,
      );
    }
  }

  void toggleSearch() =>
      ref.read(librarySearchActiveProvider) ? _closeSearch() : _openSearch();

  Future<void> pickFile() => _pick();

  void _goToPage(int i) {
    if (!_pageController.hasClients) return;
    if (_pageController.page?.round() == i) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(i);
      return;
    }
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
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
    final watchFilter = ref.watch(libraryWatchFilterProvider);
    final played = ref.watch(playedKeysProvider);
    final searching = ref.watch(librarySearchActiveProvider);
    return applyLibraryFilters(
      index,
      query: searching ? ref.watch(librarySearchQueryProvider) : '',
      sort: sort,
      watchFilter: watchFilter,
      inProgressKeys: ref
          .watch(continueWatchingProvider)
          .map((e) => e.video.key)
          .toSet(),
      completedKeys: ref.read(resumeServiceProvider).completedKeys,
      playedKeys: played,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sideTools = widget.sideTools && usesSideNavigation(context);
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
                          hintText: tab == 2
                              ? context.l10n.librarySearchHintPlaylists
                              : context.l10n.librarySearchHintVideos,
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
                        onTap: _onTitleTap,
                        onLongPress: () {
                          HapticFeedback.selectionClick();
                          openVault(context);
                        },
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: 1,
                            child: Text(
                              'Kivo',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
              ),
              actions: [
                // Visible only while incognito is on: a mode that changes what
                // gets remembered must never be on without saying so.
                if (ref.watch(settingsProvider.select((s) => s.incognito)))
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Tooltip(
                      message: context.l10n.libraryIncognitoChipTooltip,
                      child: ActionChip(
                        key: const Key('incognito-chip'),
                        avatar: const Icon(
                          Icons.visibility_off_outlined,
                          size: 16,
                        ),
                        label: Text(context.l10n.libraryIncognitoChip),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          final messenger = ScaffoldMessenger.of(context);
                          final off = context.l10n.libraryIncognitoOffSnackbar;
                          final s = ref.read(settingsProvider);
                          ref
                              .read(settingsProvider.notifier)
                              .set(s.copyWith(incognito: false));
                          messenger.showSnackBar(SnackBar(content: Text(off)));
                        },
                      ),
                    ),
                  ),
                // Distinct keys force Flutter to treat search/close as genuinely
                // different widgets rather than reusing the same IconButton
                // Element with a swapped icon — without this, an in-flight tap
                // ripple can visibly carry over onto the new icon.
                if (!sideTools || ref.watch(librarySearchActiveProvider))
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: ref.watch(librarySearchActiveProvider)
                        ? IconButton(
                            key: const ValueKey('close'),
                            tooltip: context.l10n.librarySearchClose,
                            icon: const Icon(Icons.close),
                            onPressed: _closeSearch,
                          )
                        : IconButton(
                            key: const ValueKey('search'),
                            tooltip: context.l10n.librarySearchTooltip,
                            icon: const Icon(Icons.search),
                            onPressed: _openSearch,
                          ),
                  ),
                if (!sideTools &&
                    (ref.watch(librarySearchActiveProvider) ||
                        tab == 0 ||
                        tab == 2))
                  // While searching, the search view (not `tab`) decides what
                  // is being sorted — but the search view on Listas IS the
                  // playlist list (see `_body`'s search branch above), so
                  // `tab == 2` is still the right switch even mid-search.
                  (tab == 2
                      ? const _PlaylistSortMenuButton()
                      : const _SortMenuButton()),
                if (!sideTools && !ref.watch(librarySearchActiveProvider)) ...[
                  // Density is a property of the Todo feed and the Carpetas
                  // grid; on Listas the button would respond and change
                  // nothing.
                  if (tab != 2) const LibraryDensityButton(),
                  IconButton(
                    tooltip: context.l10n.libraryOpenFile,
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
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        child: scaffold,
      ),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
              showWatchFilter: tab == 0,
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
    final watchFilter = ref.watch(libraryWatchFilterProvider);
    final played = ref.watch(playedKeysProvider);
    final filtered = applyLibraryFilters(
      videos,
      query: query,
      sort: sort,
      watchFilter: watchFilter,
      inProgressKeys: ref
          .watch(continueWatchingProvider)
          .map((e) => e.video.key)
          .toSet(),
      completedKeys: ref.read(resumeServiceProvider).completedKeys,
      playedKeys: played,
    );
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [_WatchFilterButton()]),
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
                ? _videosEmptyState(hiddenByFilter: videos.isNotEmpty)
                : LibraryEmptyState(
                    icon: Icons.search_off,
                    title: context.l10n.libraryNoSearchResults(query),
                    primaryLabel: context.l10n.librarySearchClearAction,
                    onPrimary: _closeSearch,
                    secondaryLabel: watchFilter == LibraryWatchFilter.all
                        ? null
                        : context.l10n.libraryEmptyRemoveFilterAction,
                    onSecondary: () =>
                        ref.read(libraryWatchFilterProvider.notifier).state =
                            LibraryWatchFilter.all,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _videosTab(List<VideoItem> videos) {
    final sort = librarySortFor(ref.watch(settingsProvider).librarySort);
    final watchFilter = ref.watch(libraryWatchFilterProvider);
    final played = ref.watch(playedKeysProvider);
    final filtered = applyLibraryFilters(
      videos,
      sort: sort,
      watchFilter: watchFilter,
      inProgressKeys: ref
          .watch(continueWatchingProvider)
          .map((e) => e.video.key)
          .toSet(),
      completedKeys: ref.read(resumeServiceProvider).completedKeys,
      playedKeys: played,
    );
    return VideoDensityFeed(
      videos: filtered,
      onOpen: (v, all, origin) => _open(v, all, origin),
      groupByDate: sort == LibrarySort.recent,
      showContinueRow: watchFilter == LibraryWatchFilter.all,
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
        title:
            ref.watch(libraryWatchFilterProvider) ==
                LibraryWatchFilter.unwatched
            ? context.l10n.libraryEmptyAllWatchedTitle
            : context.l10n.libraryEmptyWatchFilterTitle,
        subtitle: context.l10n.libraryEmptyWatchFilterSubtitle,
        primaryLabel: context.l10n.libraryEmptyRemoveFilterAction,
        onPrimary: () => ref.read(libraryWatchFilterProvider.notifier).state =
            LibraryWatchFilter.all,
      );
    }
    // Android 14's partial grant: the scan is honest, it just can't see past
    // the handful of videos the user picked — so the fix is widening that
    // selection, not looking for files that were never hidden.
    if (ref.watch(mediaPermissionProvider).valueOrNull == MediaAccess.limited) {
      return LibraryEmptyState(
        icon: Icons.rule_folder_outlined,
        title: context.l10n.libraryEmptyLimitedAccessTitle,
        subtitle: context.l10n.libraryEmptyLimitedAccessSubtitle,
        primaryLabel: context.l10n.libraryEmptyChooseMoreAction,
        onPrimary: () => ref.read(mediaPermissionProvider.notifier).request(),
        secondaryLabel: context.l10n.libraryOpenFile,
        onSecondary: _pick,
      );
    }
    return LibraryEmptyState(
      icon: Icons.video_library_outlined,
      title: context.l10n.libraryEmptyNoVideosTitle,
      subtitle: context.l10n.libraryEmptyNoVideosSubtitle,
      primaryLabel: context.l10n.libraryOpenFile,
      onPrimary: _pick,
      // MediaStore can index a file minutes after it lands, so a manual
      // re-scan is the difference between "empty" and "empty for now".
      secondaryLabel: context.l10n.libraryEmptyRescanAction,
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
          context.l10n.libraryAccessPromptTitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => ref.read(mediaPermissionProvider.notifier).request(),
          child: Text(context.l10n.libraryAccessPromptAction),
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
  final bool showWatchFilter;

  const _FilterChips({
    required this.selected,
    required this.onChanged,
    required this.showWatchFilter,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip(context, cs, context.l10n.libraryTabAll, 0),
                  const SizedBox(width: 8),
                  _chip(
                    context,
                    cs,
                    context.l10n.libraryTabFolders,
                    1,
                    icon: Icons.folder_outlined,
                  ),
                  const SizedBox(width: 8),
                  _chip(
                    context,
                    cs,
                    context.l10n.libraryTabPlaylists,
                    2,
                    icon: Icons.queue_music_outlined,
                  ),
                ],
              ),
            ),
          ),
          if (showWatchFilter) ...[
            const SizedBox(width: 8),
            const _WatchFilterButton(),
          ],
        ],
      ),
    );
  }

  /// Stable labels make the sections discoverable and keep their hit targets
  /// in place when selection changes. The row scrolls when text needs space.
  Widget _chip(
    BuildContext context,
    ColorScheme cs,
    String label,
    int i, {
    IconData? icon,
  }) {
    final accent = Theme.of(context).colorScheme.primary;
    final active = selected == i;
    final fg = active ? cs.onSurface : cs.onSurfaceVariant;
    return Semantics(
      label: label,
      button: true,
      selected: active,
      inMutuallyExclusiveGroup: true,
      onTap: () => onChanged(i),
      // The visible text (when shown) would read the label twice.
      excludeSemantics: true,
      child: KivoFocusable(
        onActivate: () => onChanged(i),
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            onTap: () => onChanged(i),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active
                    ? accent.withValues(alpha: 0.12)
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? accent : Colors.transparent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 22, color: fg),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
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

// ---------------------------------------------------------------------------
// Watch-status filter — separate from the library navigation tabs.
// ---------------------------------------------------------------------------
class _WatchFilterButton extends ConsumerWidget {
  const _WatchFilterButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(libraryWatchFilterProvider);
    final l10n = context.l10n;
    final labels = {
      LibraryWatchFilter.all: l10n.libraryWatchFilterAll,
      LibraryWatchFilter.unwatched: l10n.libraryUnwatchedFilter,
      LibraryWatchFilter.inProgress: l10n.libraryWatchFilterInProgress,
      LibraryWatchFilter.completed: l10n.libraryWatchFilterCompleted,
    };
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<LibraryWatchFilter>(
      tooltip: l10n.libraryWatchFilterTooltip(labels[active]!),
      initialValue: active,
      onSelected: (value) {
        ref.read(librarySelectionProvider.notifier).clear();
        ref.invalidate(continueWatchingProvider);
        ref.invalidate(playedKeysProvider);
        ref.read(libraryWatchFilterProvider.notifier).state = value;
      },
      itemBuilder: (_) => [
        for (final value in LibraryWatchFilter.values)
          CheckedPopupMenuItem(
            value: value,
            checked: value == active,
            child: Text(labels[value]!),
          ),
      ],
      child: Semantics(
        button: true,
        label: l10n.libraryWatchFilterTooltip(labels[active]!),
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: active == LibraryWatchFilter.all
                ? cs.surfaceContainerHighest
                : cs.primaryContainer,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active == LibraryWatchFilter.all
                    ? Icons.filter_list
                    : Icons.filter_list_alt,
                size: 22,
                color: active == LibraryWatchFilter.all
                    ? cs.onSurfaceVariant
                    : cs.onPrimaryContainer,
              ),
              if (usesWideLibrary(context) &&
                  MediaQuery.sizeOf(context).width >= 1000 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 18) ...[
                const SizedBox(width: 6),
                Text(
                  labels[active]!,
                  style: TextStyle(
                    color: active == LibraryWatchFilter.all
                        ? cs.onSurfaceVariant
                        : cs.onPrimaryContainer,
                  ),
                ),
              ],
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

  Map<LibrarySort, String> _labels(BuildContext context) => {
    LibrarySort.recent: context.l10n.librarySortRecent,
    LibrarySort.nameAsc: context.l10n.librarySortNameAsc,
    LibrarySort.nameDesc: context.l10n.librarySortNameDesc,
    LibrarySort.durationDesc: context.l10n.librarySortDurationDesc,
    LibrarySort.durationAsc: context.l10n.librarySortDurationAsc,
    LibrarySort.sizeDesc: context.l10n.librarySortSizeDesc,
    LibrarySort.sizeAsc: context.l10n.librarySortSizeAsc,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = librarySortFor(ref.watch(settingsProvider).librarySort);
    return PopupMenuButton<LibrarySort>(
      tooltip: context.l10n.librarySortTooltip,
      icon: const Icon(Icons.sort),
      onSelected: (sort) {
        final s = ref.read(settingsProvider);
        ref
            .read(settingsProvider.notifier)
            .set(s.copyWith(librarySort: sort.name));
      },
      itemBuilder: (context) => _labels(context).entries.map((e) {
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

  Map<PlaylistSort, String> _labels(BuildContext context) => {
    PlaylistSort.recent: context.l10n.librarySortRecent,
    PlaylistSort.nameAsc: context.l10n.librarySortNameAsc,
    PlaylistSort.nameDesc: context.l10n.librarySortNameDesc,
    PlaylistSort.mostVideos: context.l10n.playlistSortMostVideos,
    PlaylistSort.lastPlayed: context.l10n.playlistSortLastPlayed,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = playlistSortFor(ref.watch(settingsProvider).playlistSort);
    return PopupMenuButton<PlaylistSort>(
      tooltip: context.l10n.librarySortTooltip,
      icon: const Icon(Icons.sort),
      onSelected: (sort) {
        final s = ref.read(settingsProvider);
        ref
            .read(settingsProvider.notifier)
            .set(s.copyWith(playlistSort: sort.name));
      },
      itemBuilder: (context) => _labels(context).entries.map((e) {
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

/// Same library commands on a vertical axis. The screen retains its controllers
/// and routes while HomeShell chooses where to present these controls.
class LibraryRailTools extends ConsumerWidget {
  const LibraryRailTools({
    super.key,
    required this.onSearch,
    required this.onPick,
  });
  final VoidCallback onSearch;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(librarySubTabProvider);
    final searching = ref.watch(librarySearchActiveProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!searching)
          IconButton(
            tooltip: context.l10n.librarySearchTooltip,
            onPressed: onSearch,
            icon: const Icon(Icons.search),
          ),
        if (searching || tab == 0 || tab == 2)
          tab == 2 ? const _PlaylistSortMenuButton() : const _SortMenuButton(),
        if (tab != 2) const LibraryDensityButton(),
        IconButton(
          tooltip: context.l10n.libraryOpenFile,
          onPressed: onPick,
          icon: KivoIcon(KivoIcons.folderOpen, size: 22),
        ),
      ],
    );
  }
}
