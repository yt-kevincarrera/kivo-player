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

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(mediaIndexerProvider).scan());
  }
}
