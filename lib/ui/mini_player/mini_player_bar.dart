import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/kivo_theme.dart';
import '../../player/control/player_controller.dart';
import '../../player/engine/playback_provider.dart';
import '../../player/library/continue_watching.dart';
import '../../player/library/played.dart';
import '../../player/open/video_source.dart';
import '../player/player_screen.dart';
import '../player/state/mini_player_state.dart';

/// Global, persistent mini-bar shown above any screen while a video is
/// minimized (see [playerMinimizedProvider]). Mounted once in `app.dart` via
/// `MaterialApp.builder`, above the Navigator, so it survives route changes.
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  void _expand(BuildContext context, WidgetRef ref) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PlayerScreen()))
        .then((_) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(playedKeysProvider);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minimized = ref.watch(playerMinimizedProvider);
    final session = ref.watch(currentVideoProvider);
    if (session == null) return const SizedBox.shrink();

    return IgnorePointer(
      ignoring: !minimized,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: minimized ? Offset.zero : const Offset(0, 1),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: minimized ? 1 : 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: _MiniPlayerContent(
                session: session,
                onExpand: () => _expand(context, ref),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPlayerContent extends ConsumerStatefulWidget {
  final VideoSession session;
  final VoidCallback onExpand;
  const _MiniPlayerContent({required this.session, required this.onExpand});

  @override
  ConsumerState<_MiniPlayerContent> createState() => _MiniPlayerContentState();
}

class _MiniPlayerContentState extends ConsumerState<_MiniPlayerContent> {
  double _dragDx = 0;

  void _close() => ref.read(playerMinimizedProvider.notifier).state = false;

  void _onDragEnd(DragEndDetails d) {
    if (_dragDx.abs() > 80) {
      _close();
      // Don't snap the horizontal offset back yet — let the bar continue
      // fading/sliding away from wherever the swipe left it (a continuous
      // exit motion) instead of jumping back to center first. Reset only
      // once it's already invisible, so it reappears centered next time.
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted) setState(() => _dragDx = 0);
      });
    } else {
      setState(() => _dragDx = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumb = ref.watch(miniPlayerThumbnailProvider);
    final playing = ref.watch(playingProvider).valueOrNull ?? false;
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration = ref.watch(durationProvider).valueOrNull ?? Duration.zero;
    final fraction = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final cs = Theme.of(context).colorScheme;

    // Deliberately NOT Flutter's Dismissible: the bar is always mounted (so
    // the show/hide slide+fade can animate smoothly regardless of which
    // action triggers it), but Dismissible expects its parent to stop
    // rebuilding it with the same key once dismissed — a persistently
    // mounted widget fights that contract. A hand-rolled drag-to-close
    // avoids it while keeping the same swipe-to-dismiss behavior.
    //
    // Tap-to-expand and drag-to-dismiss are on the SAME GestureDetector
    // (not a separate ancestor GestureDetector wrapping an InkWell) — two
    // independent recognizers competing over the same area in a
    // parent/child relationship can let the drag recognizer swallow a
    // plain tap. A single GestureDetector's own recognizers form one team
    // and disambiguate tap vs. drag correctly via touch slop.
    return GestureDetector(
      onTap: widget.onExpand,
      onHorizontalDragUpdate: (d) => setState(() => _dragDx += d.delta.dx),
      onHorizontalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(_dragDx, 0),
        child: Opacity(
          opacity: (1 - (_dragDx.abs() / 200)).clamp(0.3, 1.0),
          child: Material(
            color: cs.surfaceContainerHighest,
            elevation: 8,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 2,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fraction,
                    child: Container(color: KivoColors.gold),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      _Preview(bytes: thumb),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.session.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: cs.onSurface),
                        onPressed: () => ref.read(playerControllerProvider).togglePlayPause(),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                        onPressed: _close,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final Uint8List? bytes;
  const _Preview({required this.bytes});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 44,
        child: bytes != null
            ? Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true)
            : Container(
                color: cs.surfaceContainerHigh,
                child: Icon(Icons.movie_outlined, color: cs.onSurfaceVariant, size: 20),
              ),
      ),
    );
  }
}
