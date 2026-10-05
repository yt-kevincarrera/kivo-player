import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/vault_ops_provider.dart';

/// One fetch per file while its tile is on screen. Selecting a video
/// rebuilds the whole grid; a FutureBuilder fetching in build came back with
/// new bytes every time, so every image reloaded and the grid blinked.
final vaultThumbnailProvider =
    FutureProvider.autoDispose.family<Uint8List?, String>(
        (ref, path) => ref.read(vaultOpsProvider).thumbnail(path));

class VaultThumbnail extends ConsumerWidget {
  final String path;
  const VaultThumbnail({super.key, required this.path});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final bytes = ref.watch(vaultThumbnailProvider(path)).valueOrNull;
    if (bytes == null) {
      return Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.movie_outlined, color: cs.onSurfaceVariant),
      );
    }
    // gaplessPlayback: should the bytes ever change, keep the old picture
    // until the new one has decoded instead of flashing empty.
    return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
  }
}
