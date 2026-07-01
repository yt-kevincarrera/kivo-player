import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/navigation.dart';
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
/// Tap-to-expand uses [kivoNavigatorKey] rather than `Navigator.of(context)`:
/// `MaterialApp.builder`'s context is an ancestor of the Navigator, and a
/// widget built inside that builder's returned tree ends up a SIBLING of the
/// Navigator, not a descendant of it — `Navigator.of(context)` from here can
/// never find it.
///
/// Swipe-to-dismiss uses Flutter's [Dismissible] (mounted only while
/// minimized, per its own contract), which is the proven pattern for
/// "swipeable AND tappable" and exits toward whichever side it was swiped.
///
/// While minimized AND playing (the mini-bar's own play button can resume
/// playback), a periodic timer persists progress — otherwise closing via the
/// X without ever expanding would leave "Continuar" stuck at the
/// position saved when minimizing, even though playback kept advancing.
class MiniPlayerBar extends ConsumerStatefulWidget {
  const MiniPlayerBar({super.key});

  @override
  ConsumerState<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends ConsumerState<MiniPlayerBar> {
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _saveTimer = Timer.periodic(const Duration(seconds: 4), (_) => _maybeSaveProgress());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  Future<void> _maybeSaveProgress() async {
    if (!ref.read(playerMinimizedProvider)) return;
    final session = ref.read(currentVideoProvider);
    if (session == null) return;
    if (!(ref.read(playingProvider).valueOrNull ?? false)) return;
    final position = ref.read(positionProvider).valueOrNull;
    final duration = ref.read(durationProvider).valueOrNull;
    if (position == null || duration == null || duration == Duration.zero) return;
    await ref.read(resumeServiceProvider).record(
          session.resumeKey,
          position,
          duration,
          DateTime.now().millisecondsSinceEpoch,
        );
  }

  void _expand() {
    kivoNavigatorKey.currentState
        ?.push(MaterialPageRoute(builder: (_) => const PlayerScreen()))
        .then((_) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(playedKeysProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final minimized = ref.watch(playerMinimizedProvider);
    final session = ref.watch(currentVideoProvider);
    if (!minimized || session == null) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        // A fresh instance mounts every time minimizing happens (the `if`
        // above renders nothing otherwise), so this plays once per mount —
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
            child: _MiniPlayerContent(session: session, onExpand: _expand),
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
