import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/vault_ops_provider.dart';

class VaultThumbnail extends ConsumerWidget {
  final String path;
  const VaultThumbnail({super.key, required this.path});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder(
      future: ref.read(vaultOpsProvider).thumbnail(path),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return Container(
            color: cs.surfaceContainerHighest,
            child: Icon(Icons.movie_outlined, color: cs.onSurfaceVariant),
          );
        }
        return Image.memory(bytes, fit: BoxFit.cover);
      },
    );
  }
}
