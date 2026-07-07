import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_file_ops.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/library/video_actions.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import '../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

const _a = VideoItem(id: '1', uri: 'u1', name: 'a.mp4', folder: 'F', durationMs: 1000, sizeBytes: 1, dateAddedMs: 0);
const _b = VideoItem(id: '2', uri: 'u2', name: 'b.mp4', folder: 'F', durationMs: 1000, sizeBytes: 1, dateAddedMs: 0);

ProviderContainer _c(FakeMediaFileOps ops, ResumeService r, PlayedStore p) => ProviderContainer(overrides: [
      mediaFileOpsProvider.overrideWithValue(ops),
      resumeServiceProvider.overrideWithValue(r),
      playedStoreProvider.overrideWithValue(p),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
    ]);

void main() {
  test('deleteMany clears resume+played for each and returns ok', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put('a.mp4', 5, 1);
    await played.markPlayed('b.mp4');
    final ops = FakeMediaFileOps()..deleteManyResult = FileOpStatus.ok;
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    final status = await c.read(videoActionsProvider).deleteMany([_a, _b]);
    expect(status, FileOpStatus.ok);
    expect(ops.deletedManyUris.single, ['u1', 'u2']);
    expect(resume.positionFor('a.mp4'), isNull);
    expect(played.isPlayed('b.mp4'), false);
  });

  test('cancelled deleteMany leaves stores untouched', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put('a.mp4', 5, 1);
    final ops = FakeMediaFileOps()..deleteManyResult = FileOpStatus.cancelled;
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).deleteMany([_a, _b]);
    expect(resume.positionFor('a.mp4'), const Duration(seconds: 5));
  });

  test('shareMany passes the uris', () async {
    final ops = FakeMediaFileOps();
    final c = _c(ops, ResumeService(InMemoryResumeStore()), InMemoryPlayedStore());
    addTearDown(c.dispose);
    await c.read(videoActionsProvider).shareMany([_a, _b]);
    expect(ops.sharedManyUris.single, ['u1', 'u2']);
  });
}
