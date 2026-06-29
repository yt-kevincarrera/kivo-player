import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../player/open/video_source.dart';

class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  String _name(String? path) {
    if (path == null) return 'Kivo';
    final p = path.replaceAll('\\', '/');
    final i = p.lastIndexOf('/');
    return i < 0 ? p : p.substring(i + 1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentVideoProvider);
    return Row(
      children: [
        IconButton(
          color: Colors.white,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Text(_name(session?.path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
        // Disabled until later plans (Plan 3 / Hito 3)
        const IconButton(color: Colors.white38, icon: Icon(Icons.closed_caption), onPressed: null),
        const IconButton(color: Colors.white38, icon: Icon(Icons.picture_in_picture_alt), onPressed: null),
        const IconButton(color: Colors.white38, icon: Icon(Icons.headphones), onPressed: null),
        const IconButton(color: Colors.white38, icon: Icon(Icons.more_vert), onPressed: null),
      ],
    );
  }
}
