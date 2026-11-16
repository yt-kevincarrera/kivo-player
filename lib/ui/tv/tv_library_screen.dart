import 'dart:async';
import 'dart:io';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/settings/settings_provider.dart';
import '../../l10n/l10n.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../platform/storage_browser_provider.dart';
import '../../player/library/continue_watching.dart';
import '../../player/library/library_filter.dart';
import '../../player/library/media_index.dart';
import '../../player/library/media_permission.dart';
import '../../platform/interfaces/media_permission.dart';
import '../../player/library/played.dart';
import '../../player/open/video_source.dart';
import 'tv_artwork.dart';
import '../home/widgets/video_options_sheet.dart';
import '../player/controls/resume_prompt.dart';
import '../player/player_route.dart';
import '../player/state/external_open_state.dart';
import '../player/state/player_dismiss_state.dart';
import 'tv_focusable.dart';
import 'tv_settings_screen.dart';
import 'tv_panel.dart';
import 'tv_playlists.dart';
import '../../player/library/tv_library.dart';

Future<void> openTvVideo(
  BuildContext context,
  WidgetRef ref,
  VideoItem video,
  List<VideoItem> all,
) async {
  ref.read(resumePromptProvider.notifier).state = null;
  ref.read(currentVideoProvider.notifier).openFromList(video, all);
  await Navigator.of(context, rootNavigator: true).push(playerRoute());
  if (!context.mounted) return;
  ref.invalidate(continueWatchingProvider);
  ref.invalidate(playedKeysProvider);
}

/// TV owns every library route, including folders and lists.
class TvLibraryScreen extends ConsumerStatefulWidget {
  const TvLibraryScreen({super.key});
  @override
  ConsumerState<TvLibraryScreen> createState() => _TvLibraryScreenState();
}

class _TvLibraryScreenState extends ConsumerState<TvLibraryScreen>
    with WidgetsBindingObserver {
  VideoItem? _selected;
  Timer? _artworkDelay;
  final _search = TextEditingController();
  final _libraryNode = FocusNode(debugLabel: 'tv-library');
  final _searchNode = FocusNode(debugLabel: 'tv-search-nav');
  final _homeNode = FocusNode(debugLabel: 'tv-home');
  final _heroNode = FocusNode(debugLabel: 'tv-hero');
  final _searchField = FocusNode(debugLabel: 'tv-search-field');
  bool _allVideos = false, _searching = false, _refreshing = false;
  int _tab = 0;
  String _query = '';
  String? _folder;
  LibraryWatchFilter _filter = LibraryWatchFilter.all;
  final _indexedRoots = <String>{};
  StreamSubscription<List<SharedMediaFile>>? _shares;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _heroNode.onKeyEvent = (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _homeNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    if (Platform.isAndroid) {
      ReceiveSharingIntent.instance.getInitialMedia().then(
        _incoming,
        onError: (Object _) {},
      );
      _shares = ReceiveSharingIntent.instance.getMediaStream().listen(
        _incoming,
        onError: (Object _) {},
      );
    }
  }

  void _incoming(List<SharedMediaFile> files) {
    if (!mounted || files.isEmpty) return;
    ref.read(currentVideoProvider.notifier).openPath(files.first.path);
    ReceiveSharingIntent.instance.reset();
    final session = ref.read(currentVideoProvider);
    if (ref.read(playerDismissProvider) != null && session != null) {
      ref.read(externalOpenProvider.notifier).state = session;
      return;
    }
    final nav = Navigator.of(context, rootNavigator: true);
    nav.popUntil((route) => route.isFirst);
    nav.push(playerRoute()).then((_) {
      if (!mounted) return;
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(playedKeysProvider);
    });
  }

  Future<void> _refresh({bool force = false}) async {
    if (!mounted || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      ref.invalidate(tvVolumesProvider);
      final volumes = await ref.read(tvVolumesProvider.future);
      if (!mounted) return;
      final roots = volumes
          .where((v) => v.removable)
          .map((v) => v.path)
          .toSet();
      _indexedRoots.retainAll(roots);
      final access = await ref.read(mediaPermissionProvider.future);
      if (!mounted) return;
      if (access != MediaAccess.denied) {
        for (final root in roots) {
          if (force || !_indexedRoots.contains(root)) {
            try {
              await ref
                  .read(storageBrowserProvider)
                  .rescan(root)
                  .timeout(const Duration(seconds: 30));
              _indexedRoots.add(root);
            } catch (_) {
              // Existing indexed/readable videos stay usable. Refresh retries
              // recovery without treating a denied read as an empty library.
            }
          }
        }
      }
      if (mounted) await ref.read(mediaIndexProvider.notifier).refresh();
    } catch (_) {
      // Source/index providers expose their own errors and retry action.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _artworkDelay?.cancel();
    _shares?.cancel();
    _search.dispose();
    for (final node in [
      _libraryNode,
      _searchNode,
      _homeNode,
      _heroNode,
      _searchField,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _select(VideoItem video) {
    _artworkDelay?.cancel();
    _artworkDelay = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _selected = video);
    });
  }

  void _home() => setState(() {
    _allVideos = false;
    _searching = false;
    _query = '';
    _folder = null;
    _tab = 0;
    _search.clear();
  });
  void _library({bool search = false}) {
    setState(() {
      _allVideos = true;
      _searching = search;
      _folder = null;
    });
    if (search) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchField.requestFocus();
      });
    }
  }

  Future<void> _push(Widget screen) async {
    final invoker = FocusManager.instance.primaryFocus;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted && invoker?.context != null) invoker!.requestFocus();
  }

  String _filterLabel(LibraryWatchFilter filter) => switch (filter) {
    LibraryWatchFilter.all => context.l10n.libraryWatchFilterAll,
    LibraryWatchFilter.unwatched => context.l10n.libraryUnwatchedFilter,
    LibraryWatchFilter.inProgress => context.l10n.libraryWatchFilterInProgress,
    LibraryWatchFilter.completed => context.l10n.libraryWatchFilterCompleted,
  };
  String _sortLabel(LibrarySort sort) => switch (sort) {
    LibrarySort.recent => context.l10n.librarySortRecent,
    LibrarySort.nameAsc => context.l10n.librarySortNameAsc,
    LibrarySort.nameDesc => context.l10n.librarySortNameDesc,
    LibrarySort.durationAsc => context.l10n.librarySortDurationAsc,
    LibrarySort.durationDesc => context.l10n.librarySortDurationDesc,
    LibrarySort.sizeAsc => context.l10n.librarySortSizeAsc,
    LibrarySort.sizeDesc => context.l10n.librarySortSizeDesc,
  };

  @override
  Widget build(BuildContext context) {
    ref.listen(storageChangesProvider, (_, event) {
      if (event.hasValue) {
        ref.invalidate(tvVolumesProvider);
        _refresh();
      }
    });
    final l = context.l10n, colors = Theme.of(context).colorScheme;
    final index = ref.watch(tvLibraryIndexProvider);
    final all = index.valueOrNull ?? <VideoItem>[];
    final continuing = ref
        .watch(continueWatchingProvider)
        .where((item) => all.any((v) => v.key == item.video.key))
        .toList();
    final videos = applyLibraryFilters(
      all,
      query: _query,
      sort: librarySortFor(ref.watch(settingsProvider).librarySort),
      watchFilter: _filter,
      playedKeys: ref.watch(playedKeysProvider),
      inProgressKeys: continuing.map((e) => e.video.key).toSet(),
      completedKeys: ref.read(resumeServiceProvider).completedKeys,
    );
    final selected =
        all.where((v) => v.key == _selected?.key).firstOrNull ??
        continuing.firstOrNull?.video ??
        all.firstOrNull;
    final progress = {
      for (final item in continuing) item.video.key: item.fraction,
    };
    final reduce = MediaQuery.disableAnimationsOf(context);
    return PopScope(
      canPop: !_allVideos && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_folder != null) {
          setState(() => _folder = null);
          return;
        }
        if (_searching) {
          setState(() {
            _searching = false;
            _query = '';
            _search.clear();
          });
          _searchNode.requestFocus();
        } else {
          _home();
          _libraryNode.requestFocus();
        }
      },
      child: Scaffold(
        backgroundColor: colors.surface,
        body: Stack(
          children: [
            if (!_allVideos && selected != null)
              Positioned.fill(
                left: 180,
                child: ExcludeSemantics(
                  child: AnimatedSwitcher(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    child: SizedBox.expand(
                      key: ValueKey(selected.id),
                      child: TvArtwork(selected.id, decorative: true),
                    ),
                  ),
                ),
              ),
            if (!_allVideos) ...[
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        stops: const [0, .22, .52, 1],
                        colors: [
                          colors.surface,
                          colors.surface,
                          colors.surface.withValues(alpha: .82),
                          colors.surface.withValues(alpha: .06),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, .32, .69, 1],
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          colors.surface.withValues(alpha: .96),
                          colors.surface,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: (210 * MediaQuery.textScalerOf(context).scale(1))
                        .clamp(210, 330),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 30, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 12, bottom: 65),
                            child: Text(
                              'kivo',
                              style: TextStyle(
                                fontSize: 33,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.5,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  _nav(
                                    l.tvHome,
                                    Icons.home_outlined,
                                    !_allVideos,
                                    _home,
                                    focusNode: _homeNode,
                                  ),
                                  _nav(
                                    l.librarySearchTooltip,
                                    Icons.search,
                                    _searching,
                                    () => _library(search: true),
                                    focusNode: _searchNode,
                                    key: const Key('tv-search-nav'),
                                  ),
                                  _nav(
                                    l.tvLibraryComplete,
                                    Icons.video_library_outlined,
                                    _allVideos && !_searching,
                                    () => _library(),
                                    focusNode: _libraryNode,
                                    key: const Key('tv-complete-library'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _nav(
                            l.tvSettings,
                            Icons.settings_outlined,
                            false,
                            () => _push(const TvSettingsScreen()),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 36, 42, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: index.isLoading && !index.hasValue
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _allVideos
                                ? _catalog(videos, all)
                                : all.isEmpty
                                ? _empty(index.hasError)
                                : _homeContent(selected!, all, progress),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _refreshing
                                ? l.tvScanningVideos
                                : l.tvNavigationHint,
                            style: TextStyle(
                              fontSize: 15,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nav(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onPressed, {
    FocusNode? focusNode,
    Key? key,
  }) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: TvFocusable(
        key: key,
        label: label,
        focusNode: focusNode,
        selected: selected,
        onPressed: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? c.onSurface.withValues(alpha: .06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24,
                color: selected ? c.primary : c.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? c.onSurface : c.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeContent(
    VideoItem selected,
    List<VideoItem> videos,
    Map<String, double> progress,
  ) {
    final l = context.l10n, c = Theme.of(context).colorScheme;
    final resume = ref.read(resumeServiceProvider).positionFor(selected.key);
    return SingleChildScrollView(
      key: const PageStorageKey('tv-library-scroll'),
      clipBehavior: Clip.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 350),
            child: Padding(
              padding: const EdgeInsets.only(top: 38, bottom: 28),
              child: SizedBox(
                width: 620,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resume == null ? l.tvFromLibrary : l.tvContinueWatching,
                      style: TextStyle(
                        fontSize: 16,
                        letterSpacing: 1.7,
                        color: c.primary,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      selected.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 44,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 17),
                    Text(
                      [
                        selected.folder,
                        if (selected.durationMs > 0)
                          fmtDuration(
                            Duration(milliseconds: selected.durationMs),
                          ),
                      ].where((s) => s.isNotEmpty).join('  ·  '),
                      style: TextStyle(fontSize: 21, color: c.onSurfaceVariant),
                    ),
                    const SizedBox(height: 26),
                    TvButton(
                      key: const Key('tv-hero-play'),
                      focusNode: _heroNode,
                      autofocus: true,
                      primary: true,
                      label: resume == null
                          ? l.playerPlayTooltip
                          : l.tvContinue,
                      icon: Icons.play_arrow,
                      onPressed: () =>
                          openTvVideo(context, ref, selected, videos),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            l.tvYourVideos,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 172 + MediaQuery.textScalerOf(context).scale(19) * 2.5,
            child: ListView.separated(
              key: const PageStorageKey('tv-home-videos'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(7),
              itemCount: videos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 20),
              itemBuilder: (_, i) => SizedBox(
                width: 250,
                child: TvVideoCard(
                  key: ValueKey('tv-home-${videos[i].id}'),
                  video: videos[i],
                  progress: progress[videos[i].key],
                  onFocus: () => _select(videos[i]),
                  onOpen: () => openTvVideo(context, ref, videos[i], videos),
                  onOptions: () => showVideoOptions(context, ref, videos[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _catalog(List<VideoItem> videos, List<VideoItem> all) {
    final l = context.l10n;
    final displayed = _folder == null
        ? videos
        : videos.where((v) => v.folder == _folder).toList();
    final sort = librarySortFor(ref.watch(settingsProvider).librarySort);
    return Column(
      key: const Key('tv-all-videos'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _folder ??
              (_searching ? l.librarySearchTooltip : l.tvLibraryComplete),
          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w600),
        ),
        if (_searching)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: TextField(
              key: const Key('tv-search'),
              controller: _search,
              focusNode: _searchField,
              style: const TextStyle(fontSize: 22),
              decoration: InputDecoration(
                hintText: l.librarySearchHintVideos,
                border: const OutlineInputBorder(),
              ),
              onChanged: (q) => setState(() => _query = q),
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            ),
          ),
        const SizedBox(height: 20),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                for (final (i, label) in [
                  (0, l.libraryTabAll),
                  (1, l.libraryTabFolders),
                  (2, l.libraryTabPlaylists),
                ]) ...[
                  TvButton(
                    label: label,
                    selected: _tab == i,
                    key: Key('tv-library-tab-$i'),
                    onPressed: () => setState(() {
                      _tab = i;
                      _folder = null;
                    }),
                  ),
                  const SizedBox(width: 12),
                ],
                if (_tab != 2) ...[
                  TvButton(
                    key: const Key('tv-library-filter'),
                    label: _filterLabel(_filter),
                    icon: Icons.filter_list,
                    onPressed: () async {
                      final selected =
                          await showTvPanelChoices<LibraryWatchFilter>(
                            context,
                            l.libraryWatchFilterTooltip(_filterLabel(_filter)),
                            LibraryWatchFilter.values
                                .map((f) => (f, _filterLabel(f), null))
                                .toList(),
                            selected: _filter,
                          );
                      if (selected != null && mounted) {
                        setState(() => _filter = selected);
                      }
                    },
                  ),
                  const SizedBox(width: 14),
                  TvButton(
                    key: const Key('tv-library-sort'),
                    label: l.librarySortTooltip,
                    icon: Icons.sort,
                    onPressed: () async {
                      final selected = await showTvPanelChoices<LibrarySort>(
                        context,
                        l.librarySortTooltip,
                        LibrarySort.values
                            .map((s) => (s, _sortLabel(s), null))
                            .toList(),
                        selected: sort,
                      );
                      if (selected != null) {
                        ref
                            .read(settingsProvider.notifier)
                            .set(
                              ref
                                  .read(settingsProvider)
                                  .copyWith(librarySort: selected.name),
                            );
                      }
                    },
                  ),
                ],
                const SizedBox(width: 14),
                TvButton(
                  label: l.tvRefresh,
                  icon: Icons.refresh,
                  onPressed: _refreshing ? null : () => _refresh(force: true),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: _tab == 2
              ? TvPlaylists(query: _query)
              : _tab == 1 && _folder == null
              ? (videos.isEmpty
                    ? _empty(false, filtered: all.isNotEmpty)
                    : _folders(videos))
              : displayed.isEmpty
              ? _empty(false, filtered: all.isNotEmpty)
              : _grid(displayed),
        ),
      ],
    );
  }

  Widget _grid(List<VideoItem> videos) => GridView.builder(
    padding: const EdgeInsets.all(7),
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 290,
      mainAxisExtent: 180 + MediaQuery.textScalerOf(context).scale(19) * 2.5,
      mainAxisSpacing: 24,
      crossAxisSpacing: 22,
    ),
    itemCount: videos.length,
    itemBuilder: (_, i) => TvVideoCard(
      key: ValueKey('tv-grid-${videos[i].id}'),
      video: videos[i],
      onOpen: () => openTvVideo(context, ref, videos[i], videos),
      onOptions: () => showVideoOptions(context, ref, videos[i]),
    ),
  );

  Widget _folders(List<VideoItem> videos) {
    final folders = videos.map((v) => v.folder).toSet().toList()..sort();
    return GridView.builder(
      padding: const EdgeInsets.all(7),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 350,
        mainAxisExtent: 150 + MediaQuery.textScalerOf(context).scale(20) * 2,
        mainAxisSpacing: 22,
        crossAxisSpacing: 22,
      ),
      itemCount: folders.length,
      itemBuilder: (_, i) {
        final folder = folders[i];
        final cover = videos.firstWhere((v) => v.folder == folder);
        return TvFocusable(
          label: folder,
          onPressed: () => setState(() => _folder = folder),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TvArtwork(cover.id),
                      const ColoredBox(color: Colors.black38),
                      const Center(
                        child: Icon(Icons.folder_outlined, size: 46),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                folder,
                style: const TextStyle(fontSize: 21),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _empty(bool error, {bool filtered = false}) {
    final l = context.l10n;
    final permission = ref.watch(mediaPermissionProvider).valueOrNull;
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtered ? Icons.search_off : Icons.video_library_outlined,
              size: 60,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 22),
            Text(
              filtered
                  ? (_query.isEmpty
                        ? l.tvNoMatchingVideos
                        : l.libraryNoSearchResults(_query))
                  : l.tvYourVideos,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            if (!filtered)
              Text(
                error ? l.tvStorageUnavailableBody : l.tvLibraryConnectHint,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 21),
              ),
            const SizedBox(height: 26),
            TvButton(
              label: filtered ? l.tvClearFilters : l.tvRefresh,
              icon: Icons.refresh,
              autofocus: true,
              onPressed: () => filtered
                  ? setState(() {
                      _query = '';
                      _search.clear();
                      _filter = LibraryWatchFilter.all;
                    })
                  : _refresh(force: true),
            ),
            if (!filtered && permission == MediaAccess.denied) ...[
              const SizedBox(height: 16),
              TvButton(
                label: l.libraryAccessPromptAction,
                onPressed: () async {
                  await ref.read(mediaPermissionProvider.notifier).request();
                  _refresh(force: true);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TvVideoCard extends StatelessWidget {
  const TvVideoCard({
    super.key,
    required this.video,
    required this.onOpen,
    required this.onOptions,
    this.onFocus,
    this.progress,
  });
  final VideoItem video;
  final VoidCallback onOpen, onOptions;
  final VoidCallback? onFocus;
  final double? progress;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TvFocusable(
        label: '${video.name}. ${video.folder}',
        onPressed: onOpen,
        onSecondary: onOptions,
        onFocus: (focused) {
          if (focused) onFocus?.call();
        },
        scale: 1.02,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                TvArtwork(video.id),
                if (progress != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                if (video.durationMs > 0)
                  Positioned(
                    bottom: 9,
                    right: 9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        child: Text(
                          fmtDuration(Duration(milliseconds: video.durationMs)),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: Text(
              video.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 19,
                height: 1.25,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 6),
          TvFocusable(
            label: '${context.l10n.tvOptions}: ${video.name}',
            onPressed: onOptions,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.more_horiz, size: 24),
            ),
          ),
        ],
      ),
    ],
  );
}
