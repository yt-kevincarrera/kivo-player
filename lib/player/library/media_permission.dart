import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/interfaces/media_permission.dart';
import '../../platform/media_permission_provider.dart';

final mediaPermissionProvider =
    AsyncNotifierProvider<MediaPermissionNotifier, MediaAccess>(
        MediaPermissionNotifier.new);

class MediaPermissionNotifier extends AsyncNotifier<MediaAccess> {
  @override
  Future<MediaAccess> build() => ref.read(mediaPermissionImplProvider).status();

  Future<void> request() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(mediaPermissionImplProvider).request());
  }
}
