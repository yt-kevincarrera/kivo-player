import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_file_ops.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
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

const _v = VideoItem(
  id: '1',
  uri: 'content://v/1',
  name: 'old.mp4',
  folder: 'Movies',
  durationMs: 600000,
  sizeBytes: 100,
  dateAddedMs: 0,
);

ProviderContainer _c(
  FakeMediaFileOps ops,
  ResumeService resume,
  PlayedStore played,
) => ProviderContainer(
  overrides: [
    mediaFileOpsProvider.overrideWithValue(ops),
    resumeServiceProvider.overrideWithValue(resume),
    playedStoreProvider.overrideWithValue(played),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
    mediaPermissionImplProvider.overrideWithValue(_Perm()),
    bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
  ],
);

void main() {
  test('delete clears resume+played and returns ok', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put('old.mp4', 30, 100);
    await played.markPlayed('old.mp4');
    final ops = FakeMediaFileOps()..deleteResult = FileOpStatus.ok;
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    final status = await c.read(videoActionsProvider).delete(_v);
    expect(status, FileOpStatus.ok);
    expect(ops.deletedUris, ['content://v/1']);
    expect(resume.positionFor('old.mp4'), isNull);
    expect(played.isPlayed('old.mp4'), false);
  });

  test('cancelled delete leaves resume+played untouched', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put('old.mp4', 30, 100);
    await played.markPlayed('old.mp4');
    final ops = FakeMediaFileOps()..deleteResult = FileOpStatus.cancelled;
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    final status = await c.read(videoActionsProvider).delete(_v);
    expect(status, FileOpStatus.cancelled);
    expect(resume.positionFor('old.mp4'), const Duration(seconds: 30));
    expect(played.isPlayed('old.mp4'), true);
  });

  test('rename migrates resume+played to the new name', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put('old.mp4', 30, 100);
    await played.markPlayed('old.mp4');
    final ops = FakeMediaFileOps()
      ..renameOutcome = const RenameOutcome(
        FileOpStatus.ok,
        newName: 'new.mp4',
      );
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    final r = await c.read(videoActionsProvider).rename(_v, 'new');
    expect(r.status, FileOpStatus.ok);
    expect(ops.renamed.single, ('content://v/1', 'new'));
    expect(resume.positionFor('old.mp4'), isNull);
    expect(resume.positionFor('new.mp4'), const Duration(seconds: 30));
    expect(played.isPlayed('old.mp4'), false);
    expect(played.isPlayed('new.mp4'), true);
  });

  test('cancelled rename does not migrate', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put('old.mp4', 30, 100);
    final ops = FakeMediaFileOps()
      ..renameOutcome = const RenameOutcome(FileOpStatus.cancelled);
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).rename(_v, 'new');
    expect(resume.positionFor('old.mp4'), const Duration(seconds: 30));
    expect(resume.positionFor('new.mp4'), isNull);
  });

  test('share passes the uri through', () async {
    final ops = FakeMediaFileOps();
    final c = _c(
      ops,
      ResumeService(InMemoryResumeStore()),
      InMemoryPlayedStore(),
    );
    addTearDown(c.dispose);
    await c.read(videoActionsProvider).share(_v);
    expect(ops.sharedUris, ['content://v/1']);
  });

  test(
    'setPlayed(true) marks played and invalidates playedKeysProvider',
    () async {
      final played = InMemoryPlayedStore();
      final c = _c(
        FakeMediaFileOps(),
        ResumeService(InMemoryResumeStore()),
        played,
      );
      addTearDown(c.dispose);
      expect(c.read(playedKeysProvider), isEmpty);

      await c.read(videoActionsProvider).setPlayed(_v, true);

      expect(played.isPlayed('old.mp4'), true);
      expect(c.read(playedKeysProvider), {'old.mp4'});
    },
  );

  test('setPlayed(false) unmarks played', () async {
    final played = InMemoryPlayedStore();
    await played.markPlayed('old.mp4');
    final c = _c(
      FakeMediaFileOps(),
      ResumeService(InMemoryResumeStore()),
      played,
    );
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).setPlayed(_v, false);

    expect(played.isPlayed('old.mp4'), false);
    expect(c.read(playedKeysProvider), isEmpty);
  });

  test('clearResume drops the saved position', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    await store.put('old.mp4', 30, 100);
    final c = _c(FakeMediaFileOps(), resume, InMemoryPlayedStore());
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).clearResume(_v);

    expect(resume.positionFor('old.mp4'), isNull);
  });

  test('a delete that moves to the trash keeps resume+played', () async {
    // The file is not gone: it can come back from the system trash for 30
    // days, and it should come back whole. Only a permanent delete forgets.
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put('old.mp4', 30, 100);
    await played.markPlayed('old.mp4');
    final ops = FakeMediaFileOps()
      ..deleteResult = FileOpStatus.ok
      ..movesToTrash = true;
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    final status = await c.read(videoActionsProvider).delete(_v);
    expect(status, FileOpStatus.ok);
    expect(ops.deletedUris, ['content://v/1']);
    expect(resume.positionFor('old.mp4'), isNotNull);
    expect(played.isPlayed('old.mp4'), true);
  });
}
