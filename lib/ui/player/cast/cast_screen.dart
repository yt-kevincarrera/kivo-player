import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../l10n/l10n.dart';
import '../../../player/cast/cast_controller.dart';
import '../keys/player_keys.dart';

/// What the player shows while its video plays on a TV: where it is
/// playing, a remote for it (play/pause, skips, the bar) and "Dejar de
/// enviar". Opaque: the phone's own video and gestures are underneath.
class CastScreen extends ConsumerWidget {
  /// Called with where the TV was, after "Dejar de enviar".
  final void Function(Duration at) onStopped;
  const CastScreen({super.key, required this.onStopped});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cast = ref.watch(castControllerProvider);
    final ctrl = ref.read(castControllerProvider.notifier);
    final l10n = context.l10n;
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final skip = ref.watch(settingsProvider).centerSkipSeconds;
    final device = cast.device?.name ?? '';
    final connecting = cast.phase == CastPhase.connecting;
    final total = cast.duration;
    final maxMs = total.inMilliseconds <= 0
        ? 1.0
        : total.inMilliseconds.toDouble();
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cast_connected, size: 72, color: accent),
                  const SizedBox(height: 16),
                  Text(
                    connecting
                        ? l10n.castConnecting(device)
                        : l10n.castPlayingOn(device),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (connecting)
                    const CircularProgressIndicator()
                  else ...[
                    Row(
                      children: [
                        Text(
                          fmtDuration(cast.position),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        Expanded(
                          child: _CastSeekBar(
                            position: cast.position,
                            maxMs: maxMs,
                            enabled: total > Duration.zero,
                            accent: accent,
                            onSeek: ctrl.seekTo,
                          ),
                        ),
                        Text(
                          fmtDuration(total),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          iconSize: 36,
                          color: Colors.white,
                          tooltip: l10n.playerSkipBackTooltip(skip),
                          icon: const Icon(Icons.replay_10),
                          onPressed: () => ctrl.skip(-skip),
                        ),
                        const SizedBox(width: 24),
                        IconButton(
                          key: const Key('cast-play-pause'),
                          iconSize: 56,
                          color: Colors.white,
                          tooltip: cast.playing
                              ? l10n.playerPauseTooltip
                              : l10n.playerPlayTooltip,
                          icon: Icon(
                            cast.playing
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                          ),
                          onPressed: ctrl.togglePlay,
                        ),
                        const SizedBox(width: 24),
                        IconButton(
                          iconSize: 36,
                          color: Colors.white,
                          tooltip: l10n.playerSkipForwardTooltip(skip),
                          icon: const Icon(Icons.forward_10),
                          onPressed: () => ctrl.skip(skip),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    key: const Key('cast-stop'),
                    focusNode: ref.watch(castStopFocusProvider),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: onAccent(accent),
                    ),
                    icon: const Icon(Icons.cast),
                    label: Text(l10n.castStop),
                    onPressed: () async => onStopped(await ctrl.stop()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The TV's position, draggable: while the finger is down the thumb follows
/// it (the once-a-second polls would otherwise pull it back), and the seek
/// goes to the TV on release.
class _CastSeekBar extends StatefulWidget {
  final Duration position;
  final double maxMs;
  final bool enabled;
  final Color accent;
  final void Function(Duration) onSeek;
  const _CastSeekBar({
    required this.position,
    required this.maxMs,
    required this.enabled,
    required this.accent,
    required this.onSeek,
  });

  @override
  State<_CastSeekBar> createState() => _CastSeekBarState();
}

class _CastSeekBarState extends State<_CastSeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final live = widget.position.inMilliseconds
        .clamp(0, widget.maxMs.toInt())
        .toDouble();
    return Slider(
      min: 0,
      max: widget.maxMs,
      value: (_drag ?? live).clamp(0, widget.maxMs),
      activeColor: widget.accent,
      inactiveColor: Colors.white24,
      onChanged: widget.enabled ? (v) => setState(() => _drag = v) : null,
      onChangeEnd: (v) {
        setState(() => _drag = null);
        widget.onSeek(Duration(milliseconds: v.round()));
      },
    );
  }
}
