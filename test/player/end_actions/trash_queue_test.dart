import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/all_files_access_provider.dart';
import 'package:kivo_player/platform/interfaces/media_file_ops.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/end_actions/pending_trash.dart';
import 'package:kivo_player/player/end_actions/trash_queue.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import '../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

VideoItem _item(String n) => VideoItem(
      id: n,
      uri: 'content://v/$n',
      name: '$n.mp4',
      folder: 'Series',
      durationMs: 1000,
      sizeBytes: 1,
      dateAddedMs: 0,
    );

void main() {
  late FakeMediaFileOps ops;
  late FakeAllFilesAccess access;
  late InMemoryPendingTrashStore store;
  final items = [_item('a'), _item('b'), _item('c')];

  Future<ProviderContainer> make({bool granted = false}) async {
    ops = FakeMediaFileOps()..movesToTrash = true;
    access = FakeAllFilesAccess(granted: granted);
    store = InMemoryPendingTrashStore();
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaFileOpsProvider.overrideWithValue(ops),
      allFilesAccessProvider.overrideWithValue(access),
      pendingTrashStoreProvider.overrideWithValue(store),
      trashUndoWindowProvider.overrideWithValue(const Duration(milliseconds: 10)),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
      bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
    ]);
    addTearDown(c.dispose);
    c.listen(trashQueueProvider, (_, _) {});
    c.read(currentVideoProvider.notifier).openFromList(items[0], items);
    return c;
  }

  Future<void> afterWindow() =>
      Future<void>.delayed(const Duration(milliseconds: 40));

  test('libraryItemIn finds the item by uri, or null outside the library', () {
    const s = VideoSession(
        playbackPath: 'content://v/b', displayName: 'b.mp4', queue: [], index: 0);
    expect(libraryItemIn(items, s)?.name, 'b.mp4');
    expect(libraryItemIn(null, s), isNull);
    const vault = VideoSession(
        playbackPath: '/data/vault/x.mp4', displayName: 'x.mp4', queue: [], index: 0);
    expect(libraryItemIn(items, vault), isNull);
  });

  test('stage persists, publishes the undo toast and drops it from the order',
      () async {
    final c = await make();
    final ended = c.read(currentVideoProvider)!;
    c.read(currentVideoProvider.notifier)
        .advanceTo(c.read(currentVideoProvider.notifier).sessionAt(1)!);
    await c.read(trashQueueProvider.notifier).stage(items[0], ended: ended);

    expect(store.all().map((e) => e.uri), ['content://v/a']);
    expect(c.read(trashUndoProvider)!.entry.uri, 'content://v/a');
    expect(c.read(trashUndoProvider)!.silent, isFalse);
    expect(c.read(currentVideoProvider)!.playOrder, [1, 2]);
  });

  test('undo keeps the file and puts the video back in the order', () async {
    final c = await make();
    final ended = c.read(currentVideoProvider)!;
    c.read(currentVideoProvider.notifier)
        .advanceTo(c.read(currentVideoProvider.notifier).sessionAt(1)!);
    await c.read(trashQueueProvider.notifier).stage(items[0], ended: ended);
    await c.read(trashQueueProvider.notifier).undo('content://v/a');

    expect(store.all(), isEmpty);
    expect(c.read(trashQueueProvider), isEmpty);
    expect(c.read(trashUndoProvider), isNull);
    expect(c.read(currentVideoProvider)!.playOrder, [0, 1, 2]);
    expect(c.read(currentVideoProvider)!.orderEdited, isFalse);
    await afterWindow();
    expect(ops.deletedManyUris, isEmpty);
  });

  test('with all-files access it commits on its own after the window', () async {
    final c = await make(granted: true);
    await c.read(trashQueueProvider.notifier).stage(items[0]);
    expect(c.read(trashUndoProvider)!.silent, isTrue);
    expect(ops.deletedManyUris, isEmpty);
    await afterWindow();
    expect(ops.deletedManyUris, [
      ['content://v/a']
    ]);
    expect(store.all(), isEmpty);
    expect(c.read(trashUndoProvider), isNull);
  });

  test('without access it waits for the batched dialog', () async {
    final c = await make();
    await c.read(trashQueueProvider.notifier).stage(items[0]);
    await c.read(trashQueueProvider.notifier).stage(items[1]);
    await afterWindow();
    expect(ops.deletedManyUris, isEmpty);
    expect(c.read(trashQueueProvider).length, 2);

    final status = await c.read(trashQueueProvider.notifier).flushInteractive();
    expect(status, FileOpStatus.ok);
    expect(ops.deletedManyUris, [
      ['content://v/a', 'content://v/b']
    ]);
    expect(store.all(), isEmpty);
  });

  test('declining the dialog keeps the files and empties the queue', () async {
    final c = await make();
    await c.read(trashQueueProvider.notifier).stage(items[0]);
    ops.deleteManyResult = FileOpStatus.cancelled;
    final status = await c.read(trashQueueProvider.notifier).flushInteractive();
    expect(status, FileOpStatus.cancelled);
    expect(c.read(trashQueueProvider), isEmpty);
  });

  test('the flush never includes the video still loaded', () async {
    final c = await make();
    await c.read(trashQueueProvider.notifier).stage(items[0]);
    await c.read(trashQueueProvider.notifier).stage(items[1]);
    await c
        .read(trashQueueProvider.notifier)
        .flushInteractive(loadedUri: 'content://v/b');
    expect(ops.deletedManyUris, [
      ['content://v/a']
    ]);
    expect(c.read(trashQueueProvider).map((e) => e.uri), ['content://v/b']);
  });

  test('nothing pending → no dialog', () async {
    final c = await make();
    expect(await c.read(trashQueueProvider.notifier).flushInteractive(), isNull);
    expect(ops.deletedManyUris, isEmpty);
  });

  test('pending entries survive a restart (read back from the store)', () async {
    final c = await make();
    await c.read(trashQueueProvider.notifier).stage(items[2]);
    c.invalidate(trashQueueProvider);
    expect(c.read(trashQueueProvider).map((e) => e.uri), ['content://v/c']);
  });

  test('commitSilentlyIfPossible: silent only, past the window', () async {
    final c = await make();
    await store.put(const PendingTrash(
        uri: 'content://v/a', name: 'a.mp4', id: 'a', stagedAtMs: 1));
    c.invalidate(trashQueueProvider);
    await c.read(trashQueueProvider.notifier).commitSilentlyIfPossible();
    expect(ops.deletedManyUris, isEmpty); // no access → never without asking
    access.granted = true;
    await c.read(trashQueueProvider.notifier).commitSilentlyIfPossible();
    expect(ops.deletedManyUris, [
      ['content://v/a']
    ]);
  });

  test('keepAll forgets everything without deleting', () async {
    final c = await make();
    await c.read(trashQueueProvider.notifier).stage(items[0]);
    await c.read(trashQueueProvider.notifier).keepAll();
    expect(store.all(), isEmpty);
    await afterWindow();
    expect(ops.deletedManyUris, isEmpty);
  });
}
