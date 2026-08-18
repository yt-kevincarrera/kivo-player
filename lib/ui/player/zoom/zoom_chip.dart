import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../state/zoom_state.dart';

/// Floating pill shown whenever the video is zoomed: the live factor plus
/// tap-to-restore.
///
/// It lives in its OWN overlay layer rather than inside ControlsOverlay,
/// because "am I zoomed, and how do I get out of it" must stay answerable while
/// the controls are hidden.
class ZoomChip extends ConsumerWidget {
  const ZoomChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zoom = ref.watch(zoomProvider);
    // Mounted only while zoomed: an always-mounted chip faded to zero would
    // still swallow taps aimed at the video underneath it.
    if (!zoom.active) return const SizedBox.shrink();
    final accent = Color(ref.watch(settingsProvider).accentColor);

    return Align(
      alignment: Alignment.bottomLeft,
      // Mirrors AbLoopChip on the right: clear of the seek bar + button row.
      child: Padding(
        padding: const EdgeInsets.only(left: 14, bottom: 116),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
          ),
          child: GestureDetector(
            onTap: () {
              ref.read(zoomProvider.notifier).reset();
              if (ref.read(settingsProvider).hapticsOnGestures) {
                HapticFeedback.lightImpact();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: accent.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.center_focus_strong, size: 13, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    '${zoom.scale.toStringAsFixed(1)}×',
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      // Tabular so the digits don't jitter from 1.9× to 2.0×.
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.close_rounded,
                      size: 12, color: Colors.white.withValues(alpha: 0.42)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
