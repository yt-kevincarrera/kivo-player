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
import '../../player/library/media_index.dart';
import '../../player/library/media_permission.dart';
import '../../player/library/played.dart';
import '../../player/open/video_source.dart';
import '../player/controls/resume_prompt.dart';
import '../player/player_screen.dart';
import 'folder_screen.dart';
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
    super.dispose();
  }

  void _push() {
    ref.read(resumePromptProvider.notifier).state = null;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PlayerScreen()))
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
    ref.read(currentVideoProvider.notifier).openInFolder(v, all);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PlayerScreen()))
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

  @override
  Widget build(BuildContext context) {
    final perm = ref.watch(mediaPermissionProvider);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Text(
          'Kivo',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        actions: [
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
      data: (videos) => Column(
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
          ),
          Expanded(
            // The PageView provides the horizontal slide between tabs — no
            // fade. Swipe is disabled so the page changes only via chip taps,
            // which keeps the 2-finger pinch on the videos page conflict-free.
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _KeepAlivePage(key: const ValueKey(0), child: _videosTab(videos)),
                _KeepAlivePage(key: const ValueKey(1), child: _foldersTab(videos)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _videosTab(List<VideoItem> videos) => VideoDensityFeed(
        videos: videos,
        onOpen: (v, all) => _open(v, all),
        groupByDate: true,
        showContinueRow: true,
      );

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

  const _FilterChips({required this.selected, required this.onChanged});

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
