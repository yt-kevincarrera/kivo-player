import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../platform/interfaces/storage_browser.dart';
import '../../platform/storage_browser_provider.dart';
import 'media_index.dart';

final tvVolumesProvider = FutureProvider<List<StorageVolume>>((ref) {
  return ref.watch(storageBrowserProvider).volumes();
});

/// Source selection changes the catalogue, never the TV's navigation shell.
/// Only mounted removable sources belong in the default TV library. A missing
/// drive must not make unrelated internal files look like its contents.
List<VideoItem> videosOnVolumes(
  List<VideoItem> videos,
  List<StorageVolume> volumes,
) {
  final roots = volumes
      .where((v) => v.removable)
      .map((v) => v.path.replaceAll(RegExp(r'/+$'), ''))
      .toList();
  return videos.where((video) {
    final uri = Uri.tryParse(video.uri);
    final path = video.filePath.isNotEmpty
        ? video.filePath
        : uri?.scheme == 'file'
        ? uri!.path
        : '';
    return roots.any((root) => path.startsWith('$root/'));
  }).toList();
}

final tvLibraryIndexProvider = Provider<AsyncValue<List<VideoItem>>>((ref) {
  final volumes = ref.watch(tvVolumesProvider);
  final index = ref.watch(libraryIndexProvider);
  if (volumes.hasError) return AsyncError(volumes.error!, volumes.stackTrace!);
  if (!volumes.hasValue) return const AsyncLoading();
  return index.whenData((videos) => videosOnVolumes(videos, volumes.value!));
});
