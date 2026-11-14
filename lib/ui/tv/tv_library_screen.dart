import 'dart:async';
import 'dart:io';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter/material.dart';
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
import '../../player/library/played.dart';
import '../../player/open/video_source.dart';
import '../home/home_shell.dart';
import '../home/widgets/thumbnail_image.dart';
import '../home/widgets/video_options_sheet.dart';
import '../player/controls/resume_prompt.dart';
import '../player/player_route.dart';
import '../player/state/external_open_state.dart';
import '../player/state/player_dismiss_state.dart';
import 'tv_focusable.dart';
import 'tv_settings_screen.dart';
import 'tv_storage_screen.dart';

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

/// TV has its own navigation and density. Shared media, history, queue and
/// playback services preserve the player's behavior and stored data.
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
  String _query = '';
  bool _searching = false;
  bool _managing = false;
  StreamSubscription<List<SharedMediaFile>>? _shares;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    if (!mounted || files.isEmpty || _managing) return;
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _artworkDelay?.cancel();
    _shares?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(mediaIndexProvider.notifier).refresh();
    }
  }

  void _select(VideoItem video) {
    _artworkDelay?.cancel();
    _artworkDelay = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _selected = video);
    });
  }

  Future<void> _push(Widget screen) async {
    if (screen is HomeShell) _managing = true;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    _managing = false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(storageChangesProvider, (_, event) {
      if (event.hasValue) ref.read(mediaIndexProvider.notifier).refresh();
    });
    final l = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final index = ref.watch(libraryIndexProvider);
    final videos = applyLibraryFilters(
      index.valueOrNull ?? [],
      query: _query,
      sort: librarySortFor(ref.watch(settingsProvider).librarySort),
    );
    final continuing = ref.watch(continueWatchingProvider);
    final selected =
        videos.where((v) => v.key == _selected?.key).firstOrNull ??
        continuing.firstOrNull?.video ??
        videos.firstOrNull;
    final resume = selected == null
        ? null
        : ref.read(resumeServiceProvider).positionFor(selected.key);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() {
            _searching = false;
            _query = '';
            _search.clear();
          });
        }
      },
      child: Scaffold(
        backgroundColor: colors.surface,
        body: FocusTraversalGroup(
          child: Stack(
            children: [
              if (selected != null)
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: AnimatedSwitcher(
                      duration: reduce
                          ? Duration.zero
                          : const Duration(milliseconds: 360),
                      child: SizedBox.expand(
                        key: ValueKey(selected.id),
                        child: ThumbnailImage(selected.id),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          colors.surface,
                          colors.surface.withValues(alpha: .78),
                          colors.surface.withValues(alpha: .35),
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
                        stops: const [0, .28, .66, 1],
                        colors: [
                          colors.surface.withValues(alpha: .9),
                          Colors.transparent,
                          colors.surface.withValues(alpha: .94),
                          colors.surface,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(42, 22, 42, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 14,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'kivo',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.5,
                            ),
                          ),
                          TvButton(
                            label: l.tvHome,
                            icon: Icons.home_outlined,
                            selected: true,
                            onPressed: () => setState(() {
                              _searching = false;
                              _query = '';
                              _search.clear();
                            }),
                          ),
                          TvButton(
                            label: l.tvUsb,
                            icon: Icons.usb,
                            onPressed: () => _push(const TvStorageScreen()),
                          ),
                          TvButton(
                            label: l.tvSettings,
                            icon: Icons.settings_outlined,
                            onPressed: () => _push(const TvSettingsScreen()),
                          ),
                          TvButton(
                            key: const Key('tv-search'),
                            label: _searching
                                ? l.librarySearchClose
                                : l.librarySearchTooltip,
                            icon: _searching ? Icons.close : Icons.search,
                            onPressed: () => setState(() {
                              _searching = !_searching;
                              if (!_searching) {
                                _query = '';
                                _search.clear();
                              }
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_searching)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            autofocus: true,
                            controller: _search,
                            style: const TextStyle(fontSize: 22),
                            decoration: InputDecoration(
                              hintText: l.librarySearchHintVideos,
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (q) => setState(() => _query = q),
                          ),
                        ),
                      Expanded(
                        child: index.isLoading && !index.hasValue
                            ? const Center(child: CircularProgressIndicator())
                            : videos.isEmpty
                            ? _empty(index.hasError)
                            : SingleChildScrollView(
                                key: const PageStorageKey('tv-library-scroll'),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (!_searching && selected != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 14,
                                          bottom: 30,
                                          left: 6,
                                        ),
                                        child: SizedBox(
                                          width: 650,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                l.tvFromLibrary,
                                                style: TextStyle(
                                                  color: colors.primary,
                                                  fontSize: 16,
                                                  letterSpacing: 2,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                selected.name,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 42,
                                                  height: 1.12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                [
                                                      selected.folder,
                                                      if (selected.durationMs >
                                                          0)
                                                        fmtDuration(
                                                          Duration(
                                                            milliseconds:
                                                                selected
                                                                    .durationMs,
                                                          ),
                                                        ),
                                                      fmtSize(
                                                        selected.sizeBytes,
                                                      ),
                                                    ]
                                                    .where((s) => s.isNotEmpty)
                                                    .join('  ·  '),
                                                style: TextStyle(
                                                  fontSize: 19,
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                              ),
                                              const SizedBox(height: 22),
                                              Wrap(
                                                spacing: 16,
                                                runSpacing: 12,
                                                children: [
                                                  TvButton(
                                                    key: const Key(
                                                      'tv-hero-play',
                                                    ),
                                                    autofocus: true,
                                                    primary: true,
                                                    label: resume == null
                                                        ? l.playerPlayTooltip
                                                        : l.tvContinue,
                                                    icon: Icons.play_arrow,
                                                    onPressed: () =>
                                                        openTvVideo(
                                                          context,
                                                          ref,
                                                          selected,
                                                          videos,
                                                        ),
                                                  ),
                                                  TvButton(
                                                    label: l.tvOptions,
                                                    icon: Icons.more_horiz,
                                                    onPressed: () =>
                                                        showVideoOptions(
                                                          context,
                                                          ref,
                                                          selected,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (!_searching && continuing.isNotEmpty)
                                      _shelf(
                                        l.tvContinueWatching,
                                        continuing.map((e) => e.video).toList(),
                                        videos,
                                        progress: {
                                          for (final item in continuing)
                                            item.video.key: item.fraction,
                                        },
                                      ),
                                    _shelf(l.tvYourVideos, videos, videos),
                                    if (!_searching) ...[
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 14,
                                        runSpacing: 12,
                                        children: [
                                          TvButton(
                                            label: l.tvLibraryComplete,
                                            icon: Icons.video_library_outlined,
                                            onPressed: () =>
                                                _push(const HomeShell()),
                                          ),
                                          TvButton(
                                            label: l.tvRefresh,
                                            icon: Icons.refresh,
                                            onPressed: () => ref
                                                .read(
                                                  mediaIndexProvider.notifier,
                                                )
                                                .refresh(),
                                          ),
                                          TvButton(
                                            label: l.tvRemoteGuide,
                                            icon:
                                                Icons.settings_remote_outlined,
                                            onPressed: () =>
                                                showTvRemoteGuide(context),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 24),
                                  ],
                                ),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          l.tvNavigationHint,
                          style: TextStyle(
                            fontSize: 15,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(bool error) {
    final l = context.l10n;
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.video_library_outlined, size: 64),
            const SizedBox(height: 20),
            Text(
              error
                  ? l.tvStorageUnavailable
                  : _query.isNotEmpty
                  ? l.libraryNoSearchResults(_query)
                  : l.libraryEmptyNoVideosTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 30),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                TvButton(
                  label: l.libraryAccessPromptAction,
                  autofocus: true,
                  primary: true,
                  onPressed: () async {
                    await ref.read(mediaPermissionProvider.notifier).request();
                    if (mounted) {
                      ref.read(mediaIndexProvider.notifier).refresh();
                    }
                  },
                ),
                TvButton(
                  label: l.tvUsb,
                  icon: Icons.usb,
                  onPressed: () => _push(const TvStorageScreen()),
                ),
                TvButton(
                  label: l.tvRefresh,
                  icon: Icons.refresh,
                  onPressed: () =>
                      ref.read(mediaIndexProvider.notifier).refresh(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _shelf(
    String title,
    List<VideoItem> items,
    List<VideoItem> queue, {
    Map<String, double> progress = const {},
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 10),
            child: Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            height: 184 + MediaQuery.textScalerOf(context).scale(19) * 2.4,
            child: ListView.separated(
              key: PageStorageKey('tv-shelf-$title'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(6, 7, 12, 12),
              cacheExtent: 800,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 18),
              itemBuilder: (_, i) => SizedBox(
                width: 270,
                child: TvVideoCard(
                  key: ValueKey('$title-${items[i].id}'),
                  video: items[i],
                  progress: progress[items[i].key],
                  onFocus: () => _select(items[i]),
                  onOpen: () => openTvVideo(context, ref, items[i], queue),
                  onOptions: () => showVideoOptions(context, ref, items[i]),
                ),
              ),
            ),
          ),
        ],
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
  final VoidCallback onOpen;
  final VoidCallback onOptions;
  final VoidCallback? onFocus;
  final double? progress;
  @override
  Widget build(BuildContext context) => TvFocusable(
    label: '${video.name}. ${video.folder}',
    onPressed: onOpen,
    onSecondary: onOptions,
    onFocus: (focused) {
      if (focused) onFocus?.call();
    },
    scale: 1.025,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ThumbnailImage(video.id),
                const Center(
                  child: Icon(
                    Icons.play_circle_outline,
                    color: Colors.white38,
                    size: 42,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 45,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                ),
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
                    right: 9,
                    bottom: 9,
                    child: Text(
                      fmtDuration(Duration(milliseconds: video.durationMs)),
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 9),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Text(
            video.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 19,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
