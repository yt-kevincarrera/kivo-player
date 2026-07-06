import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/background/audio_only.dart';
import '../../../player/open/video_source.dart';
import '../state/lock_state.dart';

/// "Solo audio" surface: black fill over the (disabled) video with an
/// always-visible mini music-player center — waves, title, label and a
/// tappable "Ver video" pill. Mounted ABOVE PlayerGestures: only the pill is
/// hit-testable, so taps/drag gestures keep working everywhere else.
class AudioOnlyView extends ConsumerWidget {
  const AudioOnlyView({super.key});

  static const _waveHeights = [12.0, 22.0, 34.0, 18.0, 26.0, 10.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(audioOnlyProvider);
    if (!on) return const SizedBox.shrink();
    // When locked, show only the black fill — the hold-to-unlock control owns
    // the center, and the "Ver video" pill must not be tappable through the lock.
    if (ref.watch(lockProvider)) {
      return const IgnorePointer(child: ColoredBox(color: Colors.black));
    }
    final title = ref.watch(currentVideoProvider)?.displayName ?? '';
    final accent = Color(ref.watch(settingsProvider).accentColor);
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(child: Container(color: Colors.black)),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IgnorePointer(
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
                              color: accent
                                  .withValues(alpha: 0.5 + 0.5 * (h / 34.0)),
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
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
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
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => ref.read(audioOnlyProvider.notifier).disable(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                        color: accent.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_outlined,
                          size: 13, color: accent),
                      const SizedBox(width: 6),
                      Text(
                        'Ver video',
                        style: TextStyle(
                          color: accent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
