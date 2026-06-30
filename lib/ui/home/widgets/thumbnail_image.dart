import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../player/library/thumbnails.dart';

class ThumbnailImage extends ConsumerWidget {
  final String id;
  final BoxFit fit;
  const ThumbnailImage(this.id, {super.key, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(thumbnailProvider(id));
    final bytes = async.valueOrNull;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: bytes == null
          ? Container(key: const ValueKey('ph'), color: const Color(0xFF1C2230))
          : Image.memory(bytes, key: ValueKey(id), fit: fit, gaplessPlayback: true),
    );
  }
}
