import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/kivo_theme.dart';
import '../state/autoplay_state.dart';

/// Bottom-right "Próximo" corner card shown for 3s (foreground fullscreen
/// only — PlayerScreen keeps this out of the tree in PiP) when autoplay has
/// a pending next session. The gold ring drains over 3s; on completion (or
/// "Reproducir") it flips [autoplayConfirmProvider] true, which PlayerScreen
/// listens to and uses to advance. "Cancelar" clears the pending session
/// instead.
class AutoplayOverlay extends ConsumerStatefulWidget {
  const AutoplayOverlay({super.key});
  @override
  ConsumerState<AutoplayOverlay> createState() => _AutoplayOverlayState();
}

class _AutoplayOverlayState extends ConsumerState<AutoplayOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    _ring.addStatusListener(_onRingStatus);
  }

  void _onRingStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      ref.read(autoplayConfirmProvider.notifier).state = true;
    }
  }

  @override
  void dispose() {
    _ring.removeStatusListener(_onRingStatus);
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(autoplayPendingProvider, (previous, next) {
      if (previous == null && next != null) {
        _ring.forward(from: 0);
      } else if (next == null) {
        _ring.stop();
      }
    });

    final pending = ref.watch(autoplayPendingProvider);
    if (pending == null) {
      if (_ring.status != AnimationStatus.dismissed) _ring.reset();
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24, right: 16),
        child: Container(
          width: 290,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(10, 14, 26, 0.92),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 74,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: KivoColors.gold.withValues(alpha: 0.5)),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: KivoColors.gold, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PRÓXIMO',
                          style: TextStyle(
                            color: KivoColors.gold,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pending.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedBuilder(
                    animation: _ring,
                    builder: (context, _) {
                      final secondsLeft = ((1 - _ring.value) * 3).ceil();
                      return SizedBox(
                        width: 34,
                        height: 34,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 34,
                              height: 34,
                              child: CircularProgressIndicator(
                                value: 1 - _ring.value,
                                strokeWidth: 3,
                                backgroundColor: Colors.white.withValues(alpha: 0.14),
                                valueColor: const AlwaysStoppedAnimation(KivoColors.gold),
                              ),
                            ),
                            Text(
                              '$secondsLeft',
                              style: const TextStyle(
                                color: KivoColors.gold,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        _ring.stop();
                        ref.read(autoplayPendingProvider.notifier).state = null;
                      },
                      child: const Text('Cancelar',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: KivoColors.gold,
                        foregroundColor: const Color(0xFF231705),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        ref.read(autoplayConfirmProvider.notifier).state = true;
                      },
                      child: const Text('Reproducir',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
