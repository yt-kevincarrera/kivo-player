import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/media/video_identity.dart';
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
  test('renaming a full-path identity preserves the same-named video in another folder', () async {
    const first = VideoItem(id: '10', uri: 'content://v/10', name: 'old.mp4',
        folder: 'A', filePath: '/storage/A/old.mp4', durationMs: 100000,
        sizeBytes: 1, dateAddedMs: 0);
    const second = VideoItem(id: '11', uri: 'content://v/11', name: 'old.mp4',
        folder: 'B', filePath: '/storage/B/old.mp4', durationMs: 100000,
        sizeBytes: 1, dateAddedMs: 0);
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put(first.key, 20, 1);
    await store.put(second.key, 70, 2);
    await resume.markCompleted(first.key);
    await played.markPlayed(first.key);
    await played.markPlayed(second.key);
    final ops = FakeMediaFileOps()
      ..renameOutcome = const RenameOutcome(FileOpStatus.ok, newName: 'new.mp4');
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);
    await c.read(videoActionsProvider).rename(first, 'new');
    final renamed = videoIdentity('/storage/A/new.mp4', 'new.mp4');
    expect(resume.positionFor(renamed), const Duration(seconds: 20));
    expect(resume.positionFor(second.key), const Duration(seconds: 70));
    expect(played.keys(), {renamed, second.key});
    expect(resume.completedKeys, {renamed});
  });

  test('delete clears resume+played and returns ok', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put(_v.key, 30, 100);
    await played.markPlayed(_v.key);
    final ops = FakeMediaFileOps()..deleteResult = FileOpStatus.ok;
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    final status = await c.read(videoActionsProvider).delete(_v);
    expect(status, FileOpStatus.ok);
    expect(ops.deletedUris, ['content://v/1']);
    expect(resume.positionFor(_v.key), isNull);
    expect(played.isPlayed(_v.key), false);
  });

  test('cancelled delete leaves resume+played untouched', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put(_v.key, 30, 100);
    await played.markPlayed(_v.key);
    final ops = FakeMediaFileOps()..deleteResult = FileOpStatus.cancelled;
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    final status = await c.read(videoActionsProvider).delete(_v);
    expect(status, FileOpStatus.cancelled);
    expect(resume.positionFor(_v.key), const Duration(seconds: 30));
    expect(played.isPlayed(_v.key), true);
  });

  test('rename migrates resume+played to the new name', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put(_v.key, 30, 100);
    await played.markPlayed(_v.key);
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
    expect(resume.positionFor(_v.key), isNull);
    expect(resume.positionFor(videoIdentity(_v.uri, 'new.mp4')), const Duration(seconds: 30));
    expect(played.isPlayed(_v.key), false);
    expect(played.isPlayed(videoIdentity(_v.uri, 'new.mp4')), true);
  });

  test('cancelled rename does not migrate', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put(_v.key, 30, 100);
    final ops = FakeMediaFileOps()
      ..renameOutcome = const RenameOutcome(FileOpStatus.cancelled);
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).rename(_v, 'new');
    expect(resume.positionFor(_v.key), const Duration(seconds: 30));
    expect(resume.positionFor(videoIdentity(_v.uri, 'new.mp4')), isNull);
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

      expect(played.isPlayed(_v.key), true);
      expect(c.read(playedKeysProvider), {_v.key});
    },
  );

  test('setPlayed(false) unmarks played', () async {
    final played = InMemoryPlayedStore();
    await played.markPlayed(_v.key);
    final c = _c(
      FakeMediaFileOps(),
      ResumeService(InMemoryResumeStore()),
      played,
    );
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).setPlayed(_v, false);

    expect(played.isPlayed(_v.key), false);
    expect(c.read(playedKeysProvider), isEmpty);
  });

  test('clearResume drops the saved position', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    await store.put(_v.key, 30, 100);
    final c = _c(FakeMediaFileOps(), resume, InMemoryPlayedStore());
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).clearResume(_v);

    expect(resume.positionFor(_v.key), isNull);
  });

  test('a delete that moves to the trash keeps resume+played', () async {
    // The file is not gone: it can come back from the system trash for 30
    // days, and it should come back whole. Only a permanent delete forgets.
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put(_v.key, 30, 100);
    await played.markPlayed(_v.key);
    final ops = FakeMediaFileOps()
      ..deleteResult = FileOpStatus.ok
      ..movesToTrash = true;
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    final status = await c.read(videoActionsProvider).delete(_v);
    expect(status, FileOpStatus.ok);
    expect(ops.deletedUris, ['content://v/1']);
    expect(resume.positionFor(_v.key), isNotNull);
    expect(played.isPlayed(_v.key), true);
  });
}
