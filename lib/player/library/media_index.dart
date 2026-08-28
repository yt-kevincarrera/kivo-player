import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
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

/// The index minus the folders the user hid — what every library surface must
/// read.
///
/// Deliberately a derived provider rather than a filter inside
/// [MediaIndexNotifier]: watching settings there would re-run `build()` and
/// publish a data-less `AsyncLoading`, which unmounts the scroll view. This
/// re-filters with no rescan and no loading flash.
final libraryIndexProvider = Provider<AsyncValue<List<VideoItem>>>((ref) {
  final raw = ref.watch(mediaIndexProvider);
  final excluded =
      ref.watch(settingsProvider.select((s) => s.excludedFolders)).toSet();
  if (excluded.isEmpty) return raw;
  return raw.whenData(
      (videos) => videos.where((v) => !excluded.contains(v.folder)).toList());
});
