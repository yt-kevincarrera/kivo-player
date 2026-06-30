import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../../core/format.dart';
import '../../core/icons/kivo_icons.dart';
import '../../core/settings/settings_provider.dart';
import '../../core/theme/kivo_theme.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../platform/interfaces/media_permission.dart';
import '../../player/library/continue_watching.dart';
import '../../player/library/library_grouping.dart';
import '../../player/library/media_index.dart';
import '../../player/library/media_permission.dart';
import '../../player/open/video_source.dart';
import '../player/controls/resume_prompt.dart';
import '../player/player_screen.dart';
import 'folder_screen.dart';
import 'widgets/continue_row.dart';
import 'widgets/folder_grid.dart';
import 'widgets/video_tile.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  int _tab = 0; // 0 = Videos, 1 = Carpetas
  StreamSubscription<dynamic>? _shareSub;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  void _push() {
    ref.read(resumePromptProvider.notifier).state = null;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PlayerScreen()))
        .then((_) => ref.invalidate(continueWatchingProvider));
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
        .then((_) => ref.invalidate(continueWatchingProvider));
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path != null) _openPath(path);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final cols = ref.read(settingsProvider).libraryColumns;
    int next = cols;
    if (d.scale > 1.25) {
      next = (cols - 1).clamp(1, 3); // pinch out → fewer cols
    } else if (d.scale < 0.8) {
      next = (cols + 1).clamp(1, 3); // pinch in → more cols
    }
    if (next != cols) {
      HapticFeedback.selectionClick();
      final s = ref.read(settingsProvider);
      ref.read(settingsProvider.notifier).set(s.copyWith(libraryColumns: next));
    }
  }

  @override
  Widget build(BuildContext context) {
    final perm = ref.watch(mediaPermissionProvider);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            const Text(
              'Kivo',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: _DiscreetTabs(
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
          ],
        ),
        actions: [
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
      error: (e, __) =>
          Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white70))),
      data: (videos) => _tab == 0 ? _videosTab(videos) : _foldersTab(videos),
    );
  }

  Widget _videosTab(List<VideoItem> videos) {
    final cols = ref.watch(settingsProvider).libraryColumns;
    final sections = groupByDay(videos, DateTime.now());
    final continueItems = {
      for (final c in ref.watch(continueWatchingProvider)) c.video.name: c,
    };
    final accentColor = Color(ref.watch(settingsProvider).accentColor);

    return GestureDetector(
      onScaleStart: (_) {},
      onScaleUpdate: _onScaleUpdate,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ContinueRow(onOpen: (v) => _open(v, videos)),
          ),
          for (final s in sections) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: Row(children: [
                  Container(width: 3, height: 13, color: accentColor),
                  const SizedBox(width: 7),
                  Text(
                    s.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  childAspectRatio: 16 / 9,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final v = s.items[i];
                    return VideoTile(
                      video: v,
                      listRow: cols == 1,
                      sizeLabel: cols == 1 ? fmtSize(v.sizeBytes) : null,
                      progress: continueItems[v.name]?.fraction,
                      onTap: () => _open(v, videos),
                    );
                  },
                  childCount: s.items.length,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
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
            const Text(
              'Da acceso a tus videos para verlos aquí',
              style: TextStyle(color: Colors.white70),
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
// Discreet segmented tab control — compact, ~28px tall.
// ---------------------------------------------------------------------------
class _DiscreetTabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _DiscreetTabs({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFF1C2230),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tab('Videos', 0),
          _tab('Carpetas', 1),
        ],
      ),
    );
  }

  Widget _tab(String label, int i) {
    final active = index == i;
    return GestureDetector(
      onTap: () => onChanged(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        height: 28,
        decoration: BoxDecoration(
          color: active ? KivoColors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white54,
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
