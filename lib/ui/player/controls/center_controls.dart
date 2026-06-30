import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../state/skip_feedback.dart';

// ---------------------------------------------------------------------------
// _PressBounce — translucent Listener that scales child to 0.92 on press.
// ---------------------------------------------------------------------------

class _PressBounce extends StatefulWidget {
  final Widget child;
  const _PressBounce({required this.child});
  @override
  State<_PressBounce> createState() => _PressBounceState();
}

class _PressBounceState extends State<_PressBounce> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
        // Translucent so the IconButton beneath still gets the tap; we only
        // observe the press to drive the scale (no event consumed).
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

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
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final dir = widget.forward ? 1.0 : -1.0;
    return _PressBounce(
      child: IconButton(
        iconSize: 34,
        color: Colors.white,
        padding: const EdgeInsets.all(18),
        constraints: const BoxConstraints(minWidth: 68, minHeight: 68),
        splashRadius: 34,
        tooltip: widget.forward ? 'Avanzar ${skip}s' : 'Retroceder ${skip}s',
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
                style: TextStyle(
                    color: accent, fontSize: 11, fontWeight: FontWeight.w700, height: 1.0)),
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
    final accent = Color(ref.watch(settingsProvider).accentColor);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SkipButton(forward: false),
        const SizedBox(width: 36),
        _PressBounce(
          child: IconButton(
            key: const Key('kivo_play_pause'),
            iconSize: 56,
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            style: IconButton.styleFrom(
              shape: CircleBorder(side: BorderSide(color: accent, width: 2)),
            ),
            tooltip: playing ? 'Pausar' : 'Reproducir',
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
  }
}
