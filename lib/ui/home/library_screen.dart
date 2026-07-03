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
import '../player/controls/resume_prompt.dart';
import '../player/player_route.dart';
import '../settings/settings_route.dart';
import 'folder_screen.dart';
import 'state/library_filter_state.dart';
import 'widgets/folder_grid.dart';
import 'widgets/video_density_feed.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  int _tab = 0; // 0 = Todo, 1 = Carpetas
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
      _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
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
    Navigator.of(context)
        .push(playerRoute())
        .then((_) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(playedKeysProvider);
    });
  }

  void _openPath(String path) {
    if (!mounted) return;
    ref.read(currentVideoProvider.notifier).openPath(path);
    _push();
  }

  void _open(VideoItem v, List<VideoItem> all) {
    ref.read(currentVideoProvider.notifier).openFromList(v, all);
    Navigator.of(context)
        .push(playerRoute())
        .then((_) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(playedKeysProvider);
    });
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path != null) _openPath(path);
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
  }

  void _closeSearch() {
    ref.read(librarySearchActiveProvider.notifier).state = false;
    ref.read(librarySearchQueryProvider.notifier).state = '';
    _searchController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final perm = ref.watch(mediaPermissionProvider);
    return Scaffold(
      appBar: AppBar(
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
            children: [...previousChildren, if (currentChild != null) currentChild],
          ),
          child: ref.watch(librarySearchActiveProvider)
              ? TextField(
                  key: const ValueKey('search-field'),
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: const InputDecoration(
                    hintText: 'Buscar videos o carpetas',
                    border: InputBorder.none,
                  ),
                  onChanged: (q) =>
                      ref.read(librarySearchQueryProvider.notifier).state = q,
                )
              : Text(
                  'Kivo',
                  key: const ValueKey('title'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
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
          if (ref.watch(librarySearchActiveProvider) || _tab == 0)
            const _SortMenuButton(),
          if (!ref.watch(librarySearchActiveProvider)) ...[
            IconButton(
              tooltip: 'Ajustes',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(settingsRoute()),
            ),
            IconButton(
              tooltip: 'Cambiar densidad',
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
  }

  Widget _body() {
    final index = ref.watch(mediaIndexProvider);
    return index.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, __) => Center(
        child: Text(
          'Error: $e',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      data: (videos) {
        if (ref.watch(librarySearchActiveProvider)) {
          return _searchResults(videos);
        }
        return Column(
          children: [
            _FilterChips(
              selected: _tab,
              onChanged: (i) {
                setState(() => _tab = i);
                _pageController.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                );
              },
              showUnwatchedToggle: _tab == 0,
              unwatchedOnly: ref.watch(libraryUnwatchedOnlyProvider),
              onToggleUnwatched: () {
                final notifier = ref.read(libraryUnwatchedOnlyProvider.notifier);
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
                      key: const ValueKey(0), child: _videosTab(videos)),
                  _KeepAlivePage(
                      key: const ValueKey(1), child: _foldersTab(videos)),
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
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              _UnwatchedChip(
                active: unwatchedOnly,
                onTap: () => ref
                    .read(libraryUnwatchedOnlyProvider.notifier)
                    .state = !unwatchedOnly,
              ),
            ],
          ),
        ),
        Expanded(
          child: query.trim().isEmpty || filtered.isNotEmpty
              ? VideoDensityFeed(
                  videos: filtered,
                  onOpen: (v, all) => _open(v, all),
                  groupByDate: sort == LibrarySort.recent,
                  showContinueRow: false,
                )
              : Center(
                  child: Text(
                    'No se encontraron videos para "$query"',
                    style: TextStyle(color: cs.onSurfaceVariant),
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
      onOpen: (v, all) => _open(v, all),
      groupByDate: sort == LibrarySort.recent,
      showContinueRow: true,
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
              onPressed: () =>
                  ref.read(mediaPermissionProvider.notifier).request(),
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
          _chip(context, cs, 'Carpetas', 1),
          if (showUnwatchedToggle) ...[
            const SizedBox(width: 8),
            _UnwatchedChip(active: unwatchedOnly, onTap: onToggleUnwatched),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, ColorScheme cs, String label, int i) {
    final active = selected == i;
    return GestureDetector(
      onTap: () => onChanged(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? KivoColors.blue : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : cs.onSurfaceVariant,
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "No vistos" toggle — a filter, not a tab (visually distinct from _chip).
// ---------------------------------------------------------------------------
class _UnwatchedChip extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _UnwatchedChip({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? KivoColors.blue : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility_off_outlined,
              size: 14,
              color: active ? Colors.white : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              'No vistos',
              style: TextStyle(
                color: active ? Colors.white : cs.onSurfaceVariant,
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
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
        ref.read(settingsProvider.notifier).set(s.copyWith(librarySort: sort.name));
      },
      itemBuilder: (context) => _labels.entries.map((e) {
        return PopupMenuItem<LibrarySort>(
          value: e.key,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: e.key == current ? const Icon(Icons.check, size: 18) : null,
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
