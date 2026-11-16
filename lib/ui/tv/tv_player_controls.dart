import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../l10n/l10n.dart';
import '../../player/control/player_controller.dart';
import '../../player/engine/playback_provider.dart';
import '../../player/open/video_source.dart';
import '../player/controls/seek_bar.dart';
import '../player/keys/player_keys.dart';
import '../player/more/more_menu.dart';
import '../player/speed/speed_panel.dart';
import '../player/state/aspect_state.dart';
import '../player/state/controls_visibility.dart';
import '../player/state/queue_strip_state.dart';
import '../player/state/skip_feedback.dart';
import '../player/tracks/track_picker.dart';
import 'tv_focusable.dart';
import 'tv_panel.dart';
import 'tv_queue_dialog.dart';
import 'tv_queue_strip.dart';

class TvPlayerControls extends ConsumerWidget {
  const TvPlayerControls({super.key, required this.visible});
  final bool visible;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final session = ref.watch(currentVideoProvider);
    Future<void> panel(Future<void> Function() open) async {
      final invoker = FocusManager.instance.primaryFocus;
      final controls = ref.read(controlsVisibleProvider.notifier);
      controls.hold();
      try {
        await open();
      } finally {
        controls.release();
      }
      if (context.mounted) {
        (invoker?.context != null ? invoker! : ref.read(playPauseFocusProvider))
            .requestFocus();
      }
    }

    void seek(int delta) {
      ref.read(playerControllerProvider).skipBy(delta);
      ref.read(skipFeedbackProvider).bump(delta);
      ref.read(controlsVisibleProvider.notifier).show();
    }

    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeFocus(
          excluding: !visible,
          child: Focus(
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                ref.read(controlsVisibleProvider.notifier).show();
              }
              return KeyEventResult.ignored;
            },
            child: Stack(
              children: [
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, .22, .48, 1],
                          colors: [
                            Colors.black54,
                            Colors.black26,
                            Color(0xb8000000),
                            Colors.black,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(44, 26, 44, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            _TvPlayerAction(
                              label: l.commonGoBack,
                              icon: Icons.arrow_back,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            const SizedBox(width: 22),
                            Expanded(
                              child: Text(
                                session?.displayName ?? 'Kivo',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TvQueueStrip(
                                    onEdit: () =>
                                        panel(() => showTvQueue(context)),
                                  ),
                                  const SizedBox(height: 22),
                                  const SeekBar(),
                                  const SizedBox(height: 18),
                                  _TvPlaybackActions(
                                    onSeek: seek,
                                    openPanel: panel,
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    l.tvPlayerControlsHint,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.white60,
                                    ),
                                  ),
                                ],
                              ),
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
      ),
    );
  }
}

/// A remote row has a stable logical order even when text grows. Scrolling
/// keeps every action visible; a wrapped row breaks rightward navigation.
class _TvPlaybackActions extends ConsumerStatefulWidget {
  const _TvPlaybackActions({required this.onSeek, required this.openPanel});
  final ValueChanged<int> onSeek;
  final Future<void> Function(Future<void> Function()) openPanel;
  @override
  ConsumerState<_TvPlaybackActions> createState() => _TvPlaybackActionsState();
}

class _TvPlaybackActionsState extends ConsumerState<_TvPlaybackActions> {
  final _nodes = List.generate(5, (i) => FocusNode(debugLabel: 'tv-action-$i'));
  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final step = ref.watch(settingsProvider).tvRemoteSeekSeconds;
    final playing = ref.watch(playingProvider).valueOrNull ?? false;
    final nodes = [
      _nodes[0],
      ref.watch(playPauseFocusProvider),
      ..._nodes.skip(1),
    ];
    return FocusTraversalGroup(
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          if (key != LogicalKeyboardKey.arrowLeft &&
              key != LogicalKeyboardKey.arrowRight) {
            return KeyEventResult.ignored;
          }
          final index = nodes.indexWhere((node) => node.hasFocus);
          if (index < 0) return KeyEventResult.ignored;
          final next = (index + (key == LogicalKeyboardKey.arrowRight ? 1 : -1))
              .clamp(0, nodes.length - 1);
          ref.read(controlsVisibleProvider.notifier).show();
          nodes[next].requestFocus();
          return KeyEventResult.handled;
        },
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              _TvPlayerAction(
                label: '−$step s',
                icon: Icons.replay,
                focusNode: nodes[0],
                onPressed: () => widget.onSeek(-step),
              ),
              const SizedBox(width: 18),
              _TvPlayerAction(
                key: const Key('tv-play-pause'),
                focusNode: nodes[1],
                label: playing ? l.playerPauseTooltip : l.playerPlayTooltip,
                icon: playing ? Icons.pause : Icons.play_arrow,
                primary: true,
                onPressed: () {
                  ref.read(playerControllerProvider).togglePlayPause();
                  ref.read(controlsVisibleProvider.notifier).show();
                },
              ),
              const SizedBox(width: 18),
              _TvPlayerAction(
                label: '+$step s',
                icon: Icons.forward_10,
                focusNode: nodes[2],
                onPressed: () => widget.onSeek(step),
              ),
              const SizedBox(width: 44),
              _TvPlayerAction(
                key: const Key('tv-player-audio'),
                focusNode: nodes[3],
                label: l.playerAudioTooltip,
                icon: Icons.volume_up_outlined,
                onPressed: () =>
                    widget.openPanel(() => showAudioPicker(context, ref)),
              ),
              const SizedBox(width: 18),
              _TvPlayerAction(
                key: const Key('tv-player-subtitles'),
                focusNode: nodes[4],
                label: l.playerSubtitlesTooltip,
                icon: Icons.subtitles_outlined,
                onPressed: () =>
                    widget.openPanel(() => showSubtitlePicker(context, ref)),
              ),
              const SizedBox(width: 18),
              _TvPlayerAction(
                key: const Key('tv-player-more'),
                focusNode: nodes[5],
                label: l.playerMoreOptionsTooltip,
                icon: Icons.more_horiz,
                onPressed: () =>
                    widget.openPanel(() => _showPlaybackOptions(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvPlayerAction extends StatelessWidget {
  const _TvPlayerAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.focusNode,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) => TvFocusable(
    label: label,
    focusNode: focusNode,
    onPressed: onPressed,
    scale: 1.03,
    child: Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: primary ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 27, color: primary ? Colors.black : Colors.white),
          if (!primary) ...[
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 20, color: Colors.white),
            ),
          ],
        ],
      ),
    ),
  );
}

Future<void> _showPlaybackOptions(BuildContext context) => showTvPanel<void>(
  context: context,
  title: context.l10n.playerMoreOptionsTooltip,
  builder: (ctx) => Consumer(
    builder: (context, ref, _) {
      final l = context.l10n;
      final session = ref.watch(currentVideoProvider);
      final previous = queueStep(session, forward: false, wrap: false);
      final next = queueStep(session, forward: true, wrap: false);
      final aspect = ref.watch(aspectModeProvider);
      final rate = ref.watch(rateProvider);
      return ListView(
        padding: const EdgeInsets.all(5),
        children: [
          TvOptionRow(
            label: l.tvImage,
            value: aspectLabelFor(l, aspect),
            autofocus: true,
            onPressed: () async {
              final value = await showTvPanelChoices<AspectMode>(
                context,
                l.tvImage,
                [
                  (AspectMode.fit, l.playerAspectFit, l.tvFitHint),
                  (AspectMode.fill, l.playerAspectFill, l.tvFillHint),
                  (AspectMode.stretch, l.playerAspectStretch, l.tvStretchHint),
                ],
                selected: aspect,
              );
              if (value != null && context.mounted) {
                ref.read(aspectModeProvider.notifier).set(value);
              }
            },
          ),
          TvOptionRow(
            label: l.playerSpeedTooltip,
            value: '${rate.toStringAsFixed(2)}×',
            onPressed: () => showSpeedPanel(context),
          ),
          if ((session?.playOrder.length ?? 0) > 1)
            TvOptionRow(
              label: l.tvEditQueue,
              onPressed: () => showTvQueue(context),
            ),
          if (previous != null)
            TvOptionRow(
              label: l.tvPrevious,
              onPressed: () {
                Navigator.of(ctx).pop();
                ref.read(queueJumpProvider.notifier).state = previous;
              },
            ),
          if (next != null)
            TvOptionRow(
              label: l.tvNext,
              onPressed: () {
                Navigator.of(ctx).pop();
                ref.read(queueJumpProvider.notifier).state = next;
              },
            ),
          TvOptionRow(
            label: l.tvMorePlayback,
            icon: Icons.tune,
            onPressed: () => showMoreMenu(context, ref),
          ),
        ],
      );
    },
  ),
);
