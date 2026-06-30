import 'dart:async';
import 'dart:ui' show lerpDouble;
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

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  static const double _pagePad = 16;

  int _tab = 0; // 0 = Todo, 1 = Carpetas
  int _prevTab = 0;
  double _scaleBaseline = 1.0;
  StreamSubscription<dynamic>? _shareSub;

  // Animated reflow ("reacomodado") when the column count changes.
  late final AnimationController _reflowCtrl;
  late final Animation<double> _reflow;
  int _prevCols = 1;

  @override
  void initState() {
    super.initState();
    _prevCols = ref.read(settingsProvider).libraryColumns;
    _reflowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 1.0, // at rest → scale 1.0 (no effect)
    );
    _reflow = CurvedAnimation(parent: _reflowCtrl, curve: Curves.easeOutCubic);
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
    _reflowCtrl.dispose();
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
    // Only react to a genuine 2-finger pinch. Gating on pointerCount (rather
    // than horizontal movement) makes the gesture direction-agnostic, like a
    // photo gallery.
    if (d.pointerCount < 2) return;
    final rel = d.scale / _scaleBaseline;
    final cols = ref.read(settingsProvider).libraryColumns;
    int next = cols;
    if (rel > 1.15) {
      next = (cols - 1).clamp(1, 3); // pinch out → fewer cols (bigger tiles)
    } else if (rel < 0.87) {
      next = (cols + 1).clamp(1, 3); // pinch in → more cols (smaller tiles)
    }
    if (next != cols) {
      // Reset baseline so each further notch needs a fresh pinch — one step
      // per notch, so 1↔2↔3 are all reachable (no 1→3 skip).
      _scaleBaseline = d.scale;
      HapticFeedback.selectionClick();
      _setColumns(next);
    }
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
    // Any column change (pinch OR the density icon) triggers the reflow.
    ref.listen<int>(settingsProvider.select((s) => s.libraryColumns),
        (prev, next) {
      if (prev != null && prev != next) {
        _prevCols = prev;
        _reflowCtrl.forward(from: 0);
      }
    });
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
            onChanged: (i) => setState(() {
              _prevTab = _tab;
              _tab = i;
            }),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) {
                // Direction by travel: going to Carpetas (tab 1) slides in from
                // the right; going back to Todo slides from the left.
                final goingRight = _tab > _prevTab;
                final dx = goingRight ? 0.12 : -0.12;
                final offset = Tween<Offset>(
                  begin: Offset(dx, 0),
                  end: Offset.zero,
                ).animate(animation);
                return SlideTransition(
                  position: offset,
                  // A whisper of fade just softens the edge; the slide is the
                  // primary motion.
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: _tab == 0
                  ? _videosTab(videos, key: const ValueKey(0))
                  : _foldersTab(videos, key: const ValueKey(1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _videosTab(List<VideoItem> videos, {Key? key}) {
    final cols = ref.watch(settingsProvider).libraryColumns;
    final sections = groupByDay(videos, DateTime.now());
    final continueItems = {
      for (final c in ref.watch(continueWatchingProvider)) c.video.name: c,
    };
    final cs = Theme.of(context).colorScheme;
    final accentColor = Color(ref.watch(settingsProvider).accentColor);

    return GestureDetector(
      key: key,
      onScaleStart: (_) {
        _scaleBaseline = 1.0;
      },
      onScaleUpdate: _onScaleUpdate,
      // The CustomScrollView renders DIRECTLY at the current `cols` — positions
      // are final and scroll is preserved. Only the per-tile scale animates,
      // giving the "reacomodado" settle with no cross-fade or scroll reset.
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ContinueRow(onOpen: (v) => _open(v, videos)),
          ),
          for (final s in sections) ...[
            SliverToBoxAdapter(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1.0 - value) * 8),
                    child: child,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                  child: Row(children: [
                    Container(width: 3, height: 13, color: accentColor),
                    const SizedBox(width: 7),
                    Text(
                      s.label,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: _pagePad),
              sliver: cols == 1
                  ? SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final v = s.items[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _reflowTile(
                              cols: cols,
                              child: VideoTile(
                                video: v,
                                listRow: true,
                                sizeLabel: fmtSize(v.sizeBytes),
                                progress: continueItems[v.name]?.fraction,
                                onTap: () => _open(v, videos),
                              ),
                            ),
                          );
                        },
                        childCount: s.items.length,
                      ),
                    )
                  : SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        childAspectRatio: 16 / 9,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final v = s.items[i];
                          return _reflowTile(
                            cols: cols,
                            child: VideoTile(
                              video: v,
                              listRow: false,
                              sizeLabel: null,
                              progress: continueItems[v.name]?.fraction,
                              onTap: () => _open(v, videos),
                            ),
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

  /// Wraps a tile so that, on a column change, it animates from its previous
  /// relative extent up/down to its new one — tiles grow/shrink into place
  /// ("reacomodado") instead of fading. At rest the scale is 1.0 (no effect).
  Widget _reflowTile({required int cols, required Widget child}) {
    return AnimatedBuilder(
      animation: _reflow,
      child: child,
      builder: (context, c) {
        if (_reflowCtrl.value >= 1.0 || _prevCols == cols) return c!;
        final usableWidth = MediaQuery.sizeOf(context).width - 2 * _pagePad;
        final newExtent = usableWidth / cols;
        final prevExtent = usableWidth / _prevCols;
        final fromScale = prevExtent / newExtent;
        final scale = lerpDouble(fromScale, 1.0, _reflow.value)!;
        return Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: c,
        );
      },
    );
  }

  Widget _foldersTab(List<VideoItem> videos, {Key? key}) => FolderGrid(
        key: key,
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
