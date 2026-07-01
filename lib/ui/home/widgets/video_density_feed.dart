import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/continue_watching.dart';
import '../../../player/library/library_grouping.dart';
import '../../../player/library/played.dart';
import 'continue_row.dart';
import 'video_tile.dart';

/// A reusable density-aware video feed: pinch-to-resize (1↔3 columns),
/// animated reflow ("reacomodado") on column change, list-row/cover tile
/// switching, and per-tile "Nuevo"/progress/size wiring.
///
/// Used by both the "Todo" tab (grouped by day, with the "Continuar viendo"
/// strip) and by [FolderScreen] (flat, no strip) so a folder looks and behaves
/// exactly like the main library.
class VideoDensityFeed extends ConsumerStatefulWidget {
  final List<VideoItem> videos;
  final void Function(VideoItem current, List<VideoItem> all) onOpen;
  final bool groupByDate;
  final bool showContinueRow;

  const VideoDensityFeed({
    super.key,
    required this.videos,
    required this.onOpen,
    this.groupByDate = true,
    this.showContinueRow = true,
  });

  @override
  ConsumerState<VideoDensityFeed> createState() => _VideoDensityFeedState();
}

class _VideoDensityFeedState extends ConsumerState<VideoDensityFeed>
    with SingleTickerProviderStateMixin {
  // Video sections sit more inset than the "Continuar" strip.
  static const double _sectionPad = 24;

  // One column step per pinch gesture (locks until the gesture ends).
  bool _pinchStepDone = false;

  // Animated reflow ("reacomodado") when the column count changes.
  late final AnimationController _reflowCtrl;
  late final Animation<double> _reflow;

  @override
  void initState() {
    super.initState();
    _reflowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1.0, // at rest → scale 1.0 (no effect)
    );
    _reflow = CurvedAnimation(parent: _reflowCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _reflowCtrl.dispose();
    super.dispose();
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // One column step per gesture: once we've stepped, ignore the rest of this
    // pinch until it ends. Only react to a genuine 2-finger pinch (gating on
    // pointerCount makes the gesture direction-agnostic, like a photo gallery).
    if (_pinchStepDone || d.pointerCount < 2) return;
    final rel = d.scale; // cumulative from gesture start
    final cols = ref.read(settingsProvider).libraryColumns;
    int next = cols;
    if (rel > 1.08) {
      next = (cols - 1).clamp(1, 3); // pinch out → fewer cols (bigger tiles)
    } else if (rel < 0.92) {
      next = (cols + 1).clamp(1, 3); // pinch in → more cols (smaller tiles)
    } else {
      return;
    }
    if (next != cols) {
      HapticFeedback.selectionClick();
      _setColumns(next);
      _pinchStepDone = true; // lock until this gesture ends
    }
  }

  void _setColumns(int cols) {
    final s = ref.read(settingsProvider);
    if (s.libraryColumns == cols) return;
    ref.read(settingsProvider.notifier).set(s.copyWith(libraryColumns: cols));
  }

  /// Wraps a tile so that, on a column change, it settles into place with a
  /// subtle 0.92→1.0 scale ("reacomodado") instead of fading. At rest the
  /// scale is 1.0 (no effect). The grid lays out at the new column count
  /// immediately — positions are final and scroll is preserved.
  Widget _reflowTile({required Widget child}) {
    return AnimatedBuilder(
      animation: _reflow,
      child: child,
      builder: (context, c) {
        if (_reflowCtrl.value >= 1.0) return c!;
        final scale = lerpDouble(0.92, 1.0, _reflow.value)!;
        return Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: c,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Any column change (pinch OR the density icon) triggers the reflow.
    ref.listen<int>(settingsProvider.select((s) => s.libraryColumns),
        (prev, next) {
      if (prev != null && prev != next) {
        _reflowCtrl.forward(from: 0);
      }
    });

    final cols = ref.watch(settingsProvider).libraryColumns;
    final sections = widget.groupByDate
        ? groupByDay(widget.videos, DateTime.now())
        : [DaySection('', widget.videos)];
    final continueItems = {
      for (final c in ref.watch(continueWatchingProvider)) c.video.name: c,
    };
    final played = ref.watch(playedKeysProvider);
    final cs = Theme.of(context).colorScheme;
    final accentColor = Color(ref.watch(settingsProvider).accentColor);

    return GestureDetector(
      onScaleStart: (_) {
        _pinchStepDone = false;
      },
      onScaleUpdate: _onScaleUpdate,
      // The CustomScrollView renders DIRECTLY at the current `cols` — positions
      // are final and scroll is preserved. Only the per-tile scale animates,
      // giving the "reacomodado" settle with no cross-fade or scroll reset.
      child: CustomScrollView(
        slivers: [
          if (widget.showContinueRow)
            SliverToBoxAdapter(
              child: ContinueRow(
                onOpen: (v) => widget.onOpen(v, widget.videos),
              ),
            ),
          for (final s in sections) ...[
            if (s.label.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(_sectionPad, 18, _sectionPad, 8),
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
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: _sectionPad),
              sliver: cols == 1
                  ? SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final v = s.items[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: _reflowTile(
                              child: VideoTile(
                                video: v,
                                listRow: true,
                                sizeLabel: fmtSize(v.sizeBytes),
                                progress: continueItems[v.name]?.fraction,
                                isNew: !played.contains(v.name),
                                onOptions: null,
                                onTap: () => widget.onOpen(v, widget.videos),
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
                            child: VideoTile(
                              video: v,
                              listRow: false,
                              sizeLabel: null,
                              progress: continueItems[v.name]?.fraction,
                              isNew: !played.contains(v.name),
                              onOptions: null,
                              onTap: () => widget.onOpen(v, widget.videos),
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
}
