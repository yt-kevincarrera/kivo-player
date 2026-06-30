import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import 'ripple_state.dart';

/// Expanding wave + chevrons + accumulated seconds on the tapped half, on
/// double-tap. Renders nothing between animations. Never blocks gestures.
class RippleOverlay extends ConsumerStatefulWidget {
  const RippleOverlay({super.key});
  @override
  ConsumerState<RippleOverlay> createState() => _RippleOverlayState();
}

class _RippleOverlayState extends ConsumerState<RippleOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  int _lastId = 0;
  RippleEvent? _event;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(rippleProvider, (_, next) {
      if (next != null && next.id != _lastId) {
        _lastId = next.id;
        setState(() => _event = next);
        _c.forward(from: 0);
      }
    });

    final e = _event;
    if (e == null) return const SizedBox.shrink();
    final accent = Color(ref.watch(settingsProvider).accentColor);

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          if (t >= 1.0) return const SizedBox.shrink();
          final fade = 1.0 - t;
          return Align(
            alignment: e.left ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: 0.32 * fade,
                    child: Transform.scale(
                      scale: 0.3 + t * 1.2,
                      child: Container(
                        width: 170,
                        height: 170,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Colors.white),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: fade,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        KivoIcon(e.left ? KivoIcons.skipBack : KivoIcons.skipForward,
                            size: 34, color: Colors.white),
                        const SizedBox(height: 2),
                        Text('${e.seconds}s',
                            style: TextStyle(
                                color: accent,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
