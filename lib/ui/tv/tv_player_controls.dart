import 'package:flutter/material.dart';
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
import 'tv_settings_screen.dart';
import 'tv_queue_dialog.dart';

class TvPlayerControls extends ConsumerWidget {
  const TvPlayerControls({super.key, required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final session = ref.watch(currentVideoProvider);
    final playing = ref.watch(playingProvider).valueOrNull ?? false;
    final skip = ref.watch(settingsProvider).tvRemoteSeekSeconds;
    final rate = ref.watch(rateProvider);
    final aspect = ref.watch(aspectModeProvider);
    final colors = Theme.of(context).colorScheme;
    Future<void> panel(Future<void> Function() open) async {
      final controls = ref.read(controlsVisibleProvider.notifier);
      controls.hold();
      try {
        await open();
      } finally {
        controls.release();
      }
      if (!context.mounted) return;
      ref.read(playPauseFocusProvider).requestFocus();
    }

    void seek(int delta) {
      ref.read(playerControllerProvider).skipBy(delta);
      ref.read(skipFeedbackProvider).bump(delta);
      ref.read(controlsVisibleProvider.notifier).show();
    }

    final previous = queueStep(session, forward: false, wrap: false);
    final next = queueStep(session, forward: true, wrap: false);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeFocus(
          excluding: !visible,
          child: Stack(
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, .30, .48, 1],
                        colors: [
                          Colors.black87,
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(40, 24, 40, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 18,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TvButton(
                            label: l.commonGoBack,
                            icon: Icons.arrow_back,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          Text(
                            session?.displayName ?? 'Kivo',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Flexible(
                        flex: 0,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SeekBar(),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 14,
                                runSpacing: 14,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (previous != null)
                                    TvButton(
                                      label: l.tvPrevious,
                                      icon: Icons.skip_previous,
                                      onPressed: () =>
                                          ref
                                                  .read(
                                                    queueJumpProvider.notifier,
                                                  )
                                                  .state =
                                              previous,
                                    ),
                                  TvButton(
                                    label: '−$skip s',
                                    icon: Icons.replay,
                                    onPressed: () => seek(-skip),
                                  ),
                                  TvButton(
                                    key: const Key('tv-play-pause'),
                                    focusNode: ref.watch(
                                      playPauseFocusProvider,
                                    ),
                                    label: playing
                                        ? l.playerPauseTooltip
                                        : l.playerPlayTooltip,
                                    icon: playing
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    primary: true,
                                    onPressed: () {
                                      ref
                                          .read(playerControllerProvider)
                                          .togglePlayPause();
                                      ref
                                          .read(
                                            controlsVisibleProvider.notifier,
                                          )
                                          .show();
                                    },
                                  ),
                                  TvButton(
                                    label: '+$skip s',
                                    icon: Icons.forward_10,
                                    onPressed: () => seek(skip),
                                  ),
                                  if (next != null)
                                    TvButton(
                                      label: l.tvNext,
                                      icon: Icons.skip_next,
                                      onPressed: () =>
                                          ref
                                                  .read(
                                                    queueJumpProvider.notifier,
                                                  )
                                                  .state =
                                              next,
                                    ),
                                  TvButton(
                                    label: l.playerAudioTooltip,
                                    icon: Icons.volume_up_outlined,
                                    onPressed: () => panel(
                                      () => showAudioPicker(context, ref),
                                    ),
                                  ),
                                  if ((session?.playOrder.length ?? 0) > 1)
                                    TvButton(
                                      label: l.tvQueue,
                                      icon: Icons.queue_play_next,
                                      onPressed: () =>
                                          panel(() => showTvQueue(context)),
                                    ),
                                  TvButton(
                                    label: l.playerSubtitlesTooltip,
                                    icon: Icons.subtitles_outlined,
                                    onPressed: () => panel(
                                      () => showSubtitlePicker(context, ref),
                                    ),
                                  ),
                                  TvButton(
                                    label: l.tvImage,
                                    icon: Icons.aspect_ratio,
                                    onPressed: () => panel(() async {
                                      final value =
                                          await showTvChoices<AspectMode>(
                                            context,
                                            l.tvImage,
                                            [
                                              (
                                                AspectMode.fit,
                                                l.playerAspectFit,
                                                l.tvFitHint,
                                              ),
                                              (
                                                AspectMode.fill,
                                                l.playerAspectFill,
                                                l.tvFillHint,
                                              ),
                                              (
                                                AspectMode.stretch,
                                                l.playerAspectStretch,
                                                l.tvStretchHint,
                                              ),
                                            ],
                                            selected: aspect,
                                          );
                                      if (value != null) {
                                        ref
                                            .read(aspectModeProvider.notifier)
                                            .set(value);
                                      }
                                    }),
                                  ),
                                  TvButton(
                                    label: '${rate.toStringAsFixed(2)}×',
                                    icon: Icons.speed,
                                    onPressed: () =>
                                        panel(() => showSpeedPanel(context)),
                                  ),
                                  TvButton(
                                    label: l.playerMoreOptionsTooltip,
                                    icon: Icons.more_horiz,
                                    onPressed: () =>
                                        panel(() => showMoreMenu(context, ref)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Text(
                                l.tvPlaybackHint,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: colors.onSurfaceVariant,
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
            ],
          ),
        ),
      ),
    );
  }
}
