import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../player/library/thumbnails.dart';

/// TV artwork fills its allocated rectangle even while cross-fading.
class TvArtwork extends ConsumerWidget {
  const TvArtwork(this.id, {super.key, this.decorative = false});
  final String id;
  final bool decorative;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(thumbnailProvider(id)).valueOrNull;
    final c = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: bytes == null
          ? ColoredBox(
              key: const ValueKey('missing'),
              color: c.surfaceContainerHigh,
              child: decorative
                  ? const SizedBox.expand()
                  : Icon(
                      Icons.video_file_outlined,
                      color: c.onSurfaceVariant.withValues(alpha: .5),
                      size: 36,
                    ),
            )
          : Image.memory(
              bytes,
              key: ValueKey(id),
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
    );
  }
}
