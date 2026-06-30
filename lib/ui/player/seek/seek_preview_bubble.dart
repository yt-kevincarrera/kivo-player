import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/engine/playback_provider.dart';
import 'seek_preview.dart';

/// Floating preview shown above the seek bar while scrubbing: the target frame
/// (gold-bordered) over its timestamp. Horizontally anchored to the scrub
/// fraction. Renders nothing when not scrubbing.
class SeekPreviewBubble extends ConsumerWidget {
  const SeekPreviewBubble({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrub = ref.watch(scrubProvider);
    if (scrub == null) return const SizedBox.shrink();
    final total = ref.watch(durationProvider).value ?? Duration.zero;
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final bytes = ref.watch(seekPreviewFrameProvider);
    final frac = total.inMilliseconds == 0
        ? 0.0
        : (scrub.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    // Map fraction 0..1 to Alignment x -1..1.
    final alignX = (frac * 2 - 1).clamp(-1.0, 1.0);

    return Align(
      alignment: Alignment(alignX, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 160,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent, width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes == null
                  ? const SizedBox.shrink()
                  : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(fmtDuration(scrub),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
