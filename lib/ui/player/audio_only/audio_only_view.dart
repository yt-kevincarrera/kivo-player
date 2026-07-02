import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/background/audio_only.dart';
import '../../../player/open/video_source.dart';
import '../state/controls_visibility.dart';

/// Black surface shown over the (disabled) video while "Solo audio" is on.
/// The center content follows the controls' show/hide; the black fill is
/// permanent so a hidden-controls state is a near-black OLED-friendly screen.
class AudioOnlyView extends ConsumerWidget {
  const AudioOnlyView({super.key});

  static const _waveHeights = [12.0, 22.0, 34.0, 18.0, 26.0, 10.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(audioOnlyProvider);
    if (!on) return const SizedBox.shrink();
    final visible = ref.watch(controlsVisibleProvider);
    final title = ref.watch(currentVideoProvider)?.displayName ?? '';
    return IgnorePointer(
      child: Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final h in _waveHeights)
                    Container(
                      width: 5,
                      height: h,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: KivoColors.gold.withValues(
                            alpha: 0.5 + 0.5 * (h / 34.0)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'SOLO AUDIO',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.42),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
