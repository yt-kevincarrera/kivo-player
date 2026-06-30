import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import '../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  final MediaAccess a;
  _Perm(this.a);
  @override Future<MediaAccess> status() async => a;
  @override Future<MediaAccess> request() async => a;
}

void main() {
  test('granted → scans; denied → empty, no scan', () async {
    final fake = FakeMediaIndexer([
      const VideoItem(id: '1', uri: 'content://1', name: 'a.mp4', folder: 'A',
          durationMs: 1000, sizeBytes: 1, dateAddedMs: 0),
    ]);
    final granted = ProviderContainer(overrides: [
      mediaPermissionImplProvider.overrideWithValue(_Perm(MediaAccess.granted)),
      mediaIndexerProvider.overrideWithValue(fake),
    ]);
    addTearDown(granted.dispose);
    expect((await granted.read(mediaIndexProvider.future)).length, 1);
    expect(fake.scans, 1);

    final denied = ProviderContainer(overrides: [
      mediaPermissionImplProvider.overrideWithValue(_Perm(MediaAccess.denied)),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer([])),
    ]);
    addTearDown(denied.dispose);
    expect(await denied.read(mediaIndexProvider.future), isEmpty);
  });
}
