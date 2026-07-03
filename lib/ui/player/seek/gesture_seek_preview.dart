import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import 'seek_preview.dart';

/// Centered preview shown while seeking by a horizontal swipe: the target frame
/// (gold-bordered) over its timestamp + signed delta. Independent of the
/// controls layer, so it stays visible even when the controls are hidden.
/// Renders nothing when no swipe-seek is in progress.
class GestureSeekPreview extends ConsumerWidget {
  const GestureSeekPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gesture = ref.watch(gestureSeekProvider);
    if (gesture == null) return const SizedBox.shrink();
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final bytes = ref.watch(seekPreviewFrameProvider);
    final delta = gesture.target - gesture.from;
    final label = delta == Duration.zero
        ? fmtDuration(gesture.target)
        : '${fmtDuration(gesture.target)}  '
            '(${delta.isNegative ? '-' : '+'}${fmtDuration(delta.abs())})';

    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.4),
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
              child: Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
