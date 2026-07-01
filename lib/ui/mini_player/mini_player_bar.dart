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
/// No swipe-to-dismiss — closing is X-button only. (An earlier version had
/// swipe-to-close, which turned out to be a red herring for the real
/// "tap doesn't expand" bug: `MaterialApp.builder`'s context is an ancestor
/// of the Navigator, and a widget built inside that builder's returned tree
/// ends up a SIBLING of the Navigator, not a descendant — so
/// `Navigator.of(context)` from here could never find it. See
/// `kivoNavigatorKey` for the actual fix.)
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  void _expand(WidgetRef ref) {
    kivoNavigatorKey.currentState
        ?.push(MaterialPageRoute(builder: (_) => const PlayerScreen()))
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
                onExpand: () => _expand(ref),
              ),
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
