import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../state/skip_feedback.dart';
import '../../widgets/press_bounce.dart';

// ---------------------------------------------------------------------------
// _SkipButton — ±10s skip with chevron nudge animation.
// ---------------------------------------------------------------------------

class _SkipButton extends ConsumerStatefulWidget {
  final bool forward;
  const _SkipButton({required this.forward});
  @override
  ConsumerState<_SkipButton> createState() => _SkipButtonState();
}

class _SkipButtonState extends ConsumerState<_SkipButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _nudge;
  late final Animation<double> _dx;

  @override
  void initState() {
    super.initState();
    _nudge = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _dx = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _nudge, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _nudge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(playerControllerProvider);
    final skip = ref.watch(settingsProvider).centerSkipSeconds;
    final dir = widget.forward ? 1.0 : -1.0;
    return PressBounce(
      child: IconButton(
        iconSize: 34,
        color: Colors.white,
        padding: const EdgeInsets.all(18),
        constraints: const BoxConstraints(minWidth: 68, minHeight: 68),
        splashRadius: 34,
        tooltip: widget.forward
            ? context.l10n.playerSkipForwardTooltip(skip)
            : context.l10n.playerSkipBackTooltip(skip),
        icon: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _dx,
              builder: (_, child) =>
                  Transform.translate(offset: Offset(_dx.value * 4 * dir, 0), child: child),
              child: KivoIcon(
                  widget.forward ? KivoIcons.skipForward : KivoIcons.skipBack,
                  size: 30, color: Colors.white),
            ),
            const SizedBox(height: 1),
            Text('${skip}s',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 4)])),
          ],
        ),
        onPressed: () {
          final s = widget.forward ? skip : -skip;
          ctrl.skipBy(s);
          ref.read(skipFeedbackProvider).bump(s);
          _nudge.forward(from: 0);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CenterControls — play/pause + skip buttons.
// ---------------------------------------------------------------------------

class CenterControls extends ConsumerWidget {
  const CenterControls({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playingProvider).value ?? false;
    final ctrl = ref.read(playerControllerProvider);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SkipButton(forward: false),
        const SizedBox(width: 36),
        PressBounce(
          child: IconButton(
            key: const Key('kivo_play_pause'),
            iconSize: 56,
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            style: IconButton.styleFrom(
              shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 3)),
            ),
            tooltip: playing ? context.l10n.playerPauseTooltip : context.l10n.playerPlayTooltip,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
              child: KivoIcon(playing ? KivoIcons.pause : KivoIcons.play,
                  key: ValueKey(playing), size: 56, color: Colors.white),
            ),
            onPressed: ctrl.togglePlayPause,
          ),
        ),
        const SizedBox(width: 36),
        const _SkipButton(forward: true),
      ],
    );
    // The capsule always takes its room (invisible and untouchable while
    // playing), with the same room reserved above: pausing must not make the
    // play button jump.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: _FrameStepCapsule.height + _FrameStepCapsule.gap),
        row,
        const SizedBox(height: _FrameStepCapsule.gap),
        IgnorePointer(
          ignoring: playing,
          child: AnimatedOpacity(
            opacity: playing ? 0 : 1,
            duration: const Duration(milliseconds: 160),
            child: const _FrameStepCapsule(),
          ),
        ),
      ],
    );
  }
}

/// Paused only: one frame back / forward. A tap steps once; holding repeats
/// at about 8 steps a second, with a light tick per step.
class _FrameStepCapsule extends ConsumerStatefulWidget {
  const _FrameStepCapsule();

  static const double height = 40;
  static const double gap = 14;

  @override
  ConsumerState<_FrameStepCapsule> createState() => _FrameStepCapsuleState();
}

class _FrameStepCapsuleState extends ConsumerState<_FrameStepCapsule> {
  Timer? _repeat;

  void _step(bool forward) {
    ref.read(playbackEngineProvider).frameStep(forward: forward);
    if (ref.read(settingsProvider).hapticsOnGestures) {
      HapticFeedback.selectionClick();
    }
  }

  void _startRepeat(bool forward) {
    _repeat?.cancel();
    _step(forward);
    _repeat = Timer.periodic(
        const Duration(milliseconds: 125), (_) => _step(forward));
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  Widget _button(bool forward, String tooltip) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          key: Key(forward ? 'frame-next' : 'frame-prev'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _step(forward),
          onLongPressStart: (_) => _startRepeat(forward),
          onLongPressEnd: (_) => _stopRepeat(),
          onLongPressCancel: _stopRepeat,
          child: SizedBox(
            width: 48,
            height: _FrameStepCapsule.height,
            child: Icon(
              forward ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      height: _FrameStepCapsule.height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(_FrameStepCapsule.height / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(false, l10n.playerFramePrevTooltip),
          Text(
            l10n.playerFrameLabel,
            style: const TextStyle(
                color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          _button(true, l10n.playerFrameNextTooltip),
        ],
      ),
    );
  }
}
