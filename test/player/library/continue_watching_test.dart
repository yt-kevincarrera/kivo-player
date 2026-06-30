import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/library/continue_watching.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import '../../fakes/fakes.dart';

class _Granted implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

VideoItem v(String n, int dur) => VideoItem(
    id: n,
    uri: 'content://$n',
    name: n,
    folder: 'F',
    durationMs: dur,
    sizeBytes: 1,
    dateAddedMs: 0);

void main() {
  test('joins resume entries with index, drops finished, newest first',
      () async {
    final store = InMemoryResumeStore();
    await store.put('a.mp4', 30, 100); // 30s of 100s = 30%
    await store.put('b.mp4', 95, 200); // 95s of 100s = 95% (keep; <97%)
    await store.put('c.mp4', 99, 300); // 99% finished → drop
    await store.put('ghost.mp4', 10, 400); // not in index → drop
    final c = ProviderContainer(overrides: [
      mediaPermissionImplProvider.overrideWithValue(_Granted()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(
          [v('a.mp4', 100000), v('b.mp4', 100000), v('c.mp4', 100000)])),
      resumeServiceProvider.overrideWithValue(ResumeService(store)),
    ]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future); // ensure index loaded
    final list = c.read(continueWatchingProvider);
    expect(list.map((e) => e.video.name).toList(),
        ['b.mp4', 'a.mp4']); // updatedAt desc
    expect(list.first.fraction, closeTo(0.95, 0.001));
  });
}
