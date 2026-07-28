import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../platform/interfaces/media_permission.dart';
import '../../platform/media_indexer_provider.dart';
import 'media_permission.dart';

final mediaIndexProvider =
    AsyncNotifierProvider<MediaIndexNotifier, List<VideoItem>>(
        MediaIndexNotifier.new);

class MediaIndexNotifier extends AsyncNotifier<List<VideoItem>> {
  @override
  Future<List<VideoItem>> build() async {
    final access = await ref.watch(mediaPermissionProvider.future);
    if (access == MediaAccess.denied) return const [];
    return ref.read(mediaIndexerProvider).scan();
  }

  /// Re-scans in place, KEEPING the current list on screen until the new one
  /// arrives. It must never publish a data-less `AsyncLoading`: the library
  /// renders a spinner for that, which unmounts the scroll view and throws the
  /// user back to the top of the list — jarring right after deleting an item.
  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(mediaIndexerProvider).scan());
  }
}
