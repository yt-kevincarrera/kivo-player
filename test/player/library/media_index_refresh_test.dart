import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import '../../fakes/fakes.dart';

class _GrantedPerm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

const _a = VideoItem(
    id: '1', uri: 'u1', name: 'a.mp4', folder: 'F', durationMs: 1, sizeBytes: 1, dateAddedMs: 1);
const _b = VideoItem(
    id: '2', uri: 'u2', name: 'b.mp4', folder: 'F', durationMs: 1, sizeBytes: 1, dateAddedMs: 1);

void main() {
  test('refresh never publishes a data-less state (list stays mounted → scroll survives)', () async {
    final fake = FakeMediaIndexer([_a, _b]);
    final c = ProviderContainer(overrides: [
      mediaIndexerProvider.overrideWithValue(fake),
      mediaPermissionImplProvider.overrideWithValue(_GrantedPerm()),
    ]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    // Record any emission that carries no data: that is what makes
    // library_screen swap the CustomScrollView for a spinner, unmounting it and
    // resetting the scroll offset to the top after a delete.
    final datalessEmissions = <AsyncValue<List<VideoItem>>>[];
    c.listen<AsyncValue<List<VideoItem>>>(mediaIndexProvider, (_, next) {
      if (!next.hasValue) datalessEmissions.add(next);
    });

    fake.items = [_a]; // the deleted video is gone from the next scan
    await c.read(mediaIndexProvider.notifier).refresh();

    expect(datalessEmissions, isEmpty,
        reason: 'a data-less loading state unmounts the list and loses the scroll position');
    expect(c.read(mediaIndexProvider).value, [_a]);
  });
}
