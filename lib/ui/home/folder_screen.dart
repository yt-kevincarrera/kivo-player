import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../player/library/continue_watching.dart';
import '../../player/library/media_index.dart';
import '../../player/library/played.dart';
import '../../player/open/video_source.dart';
import '../player/controls/resume_prompt.dart';
import '../player/player_route.dart';
import 'state/library_selection.dart';
import 'widgets/selection_app_bar.dart';
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
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(playerRoute(originRect: origin)).then((_) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(playedKeysProvider);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Derive the folder's contents LIVE from the index so a delete/rename
    // performed from inside this screen (via the shared VideoDensityFeed's
    // ⋮ menu) is reflected immediately. Fall back to the constructor
    // snapshot only while the index is still loading.
    final live = ref.watch(mediaIndexProvider).valueOrNull;
    final vids = live == null
        ? videos
        : live.where((v) => v.folder == folder).toList();
    final selecting = ref.watch(librarySelectionProvider).isNotEmpty;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(librarySelectionProvider.notifier).clear();
      },
      child: Scaffold(
        appBar: selecting
            ? SelectionAppBar(allVisible: vids)
            : AppBar(
                title: Text(
                  folder,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
        body: VideoDensityFeed(
          videos: vids,
          onOpen: (v, all, origin) => _open(context, ref, v, all, origin),
          groupByDate: false,
          showContinueRow: false,
        ),
      ),
    );
  }
}
