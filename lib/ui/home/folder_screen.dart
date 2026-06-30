import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../player/library/continue_watching.dart';
import '../../player/open/video_source.dart';
import '../player/controls/resume_prompt.dart';
import '../player/player_screen.dart';
import 'widgets/video_tile.dart';

class FolderScreen extends ConsumerWidget {
  final String folder;
  final List<VideoItem> videos;

  const FolderScreen({super.key, required this.folder, required this.videos});

  void _open(BuildContext context, WidgetRef ref, VideoItem v) {
    ref.read(resumePromptProvider.notifier).state = null;
    ref.read(currentVideoProvider.notifier).openInFolder(v, videos);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PlayerScreen()))
        .then((_) => ref.invalidate(continueWatchingProvider));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cols = ref.watch(settingsProvider).libraryColumns;
    final continueItems = {
      for (final c in ref.watch(continueWatchingProvider)) c.video.name: c,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(
          folder,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: 16 / 9,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: videos.length,
        itemBuilder: (_, i) {
          final v = videos[i];
          return VideoTile(
            video: v,
            listRow: cols == 1,
            sizeLabel: cols == 1 ? fmtSize(v.sizeBytes) : null,
            progress: continueItems[v.name]?.fraction,
            onTap: () => _open(context, ref, v),
          );
        },
      ),
    );
  }
}
