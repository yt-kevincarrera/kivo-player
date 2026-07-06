import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../player/library/continue_watching.dart';
import '../../player/library/played.dart';
import '../../player/open/video_source.dart';
import '../player/controls/resume_prompt.dart';
import '../player/player_route.dart';
import 'widgets/video_density_feed.dart';

class FolderScreen extends ConsumerWidget {
  final String folder;
  final List<VideoItem> videos;

  const FolderScreen({super.key, required this.folder, required this.videos});

  void _open(
    BuildContext context,
    WidgetRef ref,
    VideoItem current,
    List<VideoItem> all,
    Rect? origin,
  ) {
    ref.read(resumePromptProvider.notifier).state = null;
    ref.read(currentVideoProvider.notifier).openFromList(current, all);
    Navigator.of(context, rootNavigator: true)
        .push(playerRoute(originRect: origin))
        .then((_) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(playedKeysProvider);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          folder,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: VideoDensityFeed(
        videos: videos,
        onOpen: (v, all, origin) => _open(context, ref, v, all, origin),
        groupByDate: false,
        showContinueRow: false,
      ),
    );
  }
}
