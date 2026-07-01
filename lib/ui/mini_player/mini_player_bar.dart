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
///
/// Mounted ONLY while minimized (not persistently, with a visibility toggle)
/// so it can use Flutter's [Dismissible] for swipe-to-close — a hand-rolled
/// GestureDetector combining onTap + onHorizontalDrag on one widget works in
/// synthetic widget tests (which move zero pixels during a "tap") but not on
/// real touchscreens: any jitter during a real finger tap gets misread as
/// the start of a drag, and the drag recognizer wins the gesture arena
/// before the tap ever fires. Dismissible's own gesture handling is the
/// battle-tested pattern for "swipeable AND tappable" (the same shape as a
/// swipe-to-delete ListTile that's also tappable), and it exits toward
/// whichever side it was swiped, matching the "desaparece por los costados"
/// requirement for free.
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
    if (!minimized || session == null) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        // A fresh instance mounts every time minimizing happens (the `if`
        // above returns nothing otherwise), so this plays once per mount —
        // a simple slide-up + fade-in entrance, no AnimationController needed.
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, (1 - t) * 24), child: child),
          ),
          child: Dismissible(
            key: ValueKey('mini-player-${session.playbackPath}'),
            direction: DismissDirection.horizontal,
            // No list to shrink into — the bar just vanishes once the
            // parent stops rendering it (the `if` above, on the next
            // build after this fires), so opt out of Dismissible's own
            // resize-then-remove choreography.
            resizeDuration: null,
            onDismissed: (_) => ref.read(playerMinimizedProvider.notifier).state = false,
            child: _MiniPlayerContent(
              session: session,
              onExpand: () => _expand(context, ref),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPlayerContent extends ConsumerWidget {
  final VideoSession session;
  final VoidCallback onExpand;
  const _MiniPlayerContent({required this.session, required this.onExpand});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumb = ref.watch(miniPlayerThumbnailProvider);
    final playing = ref.watch(playingProvider).valueOrNull ?? false;
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration = ref.watch(durationProvider).valueOrNull ?? Duration.zero;
    final fraction = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final cs = Theme.of(context).colorScheme;

    return Material(
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
          InkWell(
            onTap: onExpand,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  _Preview(bytes: thumb),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      session.displayName,
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
                    onPressed: () => ref.read(playerMinimizedProvider.notifier).state = false,
                  ),
                ],
              ),
            ),
          ),
        ],
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
