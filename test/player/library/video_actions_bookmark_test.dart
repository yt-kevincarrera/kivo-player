import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_file_ops.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/bookmarks/bookmark.dart';
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
  uri: 'content://1',
  name: 'ep1.mkv',
  folder: 'Series',
  durationMs: 1000,
  sizeBytes: 10,
  dateAddedMs: 0,
);

// Copy of the container-assembly pattern from video_actions_playlist_test.dart,
// with a bookmark store override instead of a playlist one.
ProviderContainer _buildContainer({
  required BookmarkStore bookmarkStore,
  String renameTo = 'renamed.mp4',
}) {
  final ops = FakeMediaFileOps()
    ..renameOutcome = RenameOutcome(FileOpStatus.ok, newName: renameTo);
  return ProviderContainer(overrides: [
    mediaFileOpsProvider.overrideWithValue(ops),
    resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
    playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
    mediaPermissionImplProvider.overrideWithValue(_Perm()),
    bookmarkStoreProvider.overrideWithValue(bookmarkStore),
  ]);
}

void main() {
  test('renaming a video migrates its bookmarks to the new key', () async {
    final store = InMemoryBookmarkStore();
    await store.put('ep1.mkv', const [
      Bookmark(positionMs: 1000, name: 'Golazo', createdAtMs: 1),
    ]);
    final c = _buildContainer(bookmarkStore: store, renameTo: 'ep1-nuevo.mkv');
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).rename(_v, 'ep1-nuevo');

    expect(store.forVideo('ep1.mkv'), isEmpty);
    expect(store.forVideo('ep1-nuevo.mkv').single.name, 'Golazo');
  });

  test('a cancelled rename leaves the bookmarks under the old key', () async {
    final store = InMemoryBookmarkStore();
    await store.put('ep1.mkv', const [
      Bookmark(positionMs: 1000, name: 'Golazo', createdAtMs: 1),
    ]);
    final ops = FakeMediaFileOps()
      ..renameOutcome = const RenameOutcome(FileOpStatus.cancelled);
    final c = ProviderContainer(overrides: [
      mediaFileOpsProvider.overrideWithValue(ops),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
      bookmarkStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).rename(_v, 'ep1-nuevo');

    expect(store.forVideo('ep1.mkv').single.name, 'Golazo');
  });

  test('deleting a video leaves its bookmarks alone — no delete hook by design', () async {
    // Deliberate, same rule as playlists: a video deleted by mistake and
    // restored (or an SD card unplugged for an afternoon) must not destroy
    // what was marked in it.
    final store = InMemoryBookmarkStore();
    await store.put('ep1.mkv', const [
      Bookmark(positionMs: 1000, name: 'Golazo', createdAtMs: 1),
    ]);
    final c = _buildContainer(bookmarkStore: store);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).delete(_v);

    expect(store.forVideo('ep1.mkv').single.name, 'Golazo');
  });

  test('deleteMany also leaves bookmarks alone — no delete hook by design', () async {
    final store = InMemoryBookmarkStore();
    await store.put('ep1.mkv', const [
      Bookmark(positionMs: 1000, name: 'Golazo', createdAtMs: 1),
    ]);
    final c = _buildContainer(bookmarkStore: store);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).deleteMany([_v]);

    expect(store.forVideo('ep1.mkv').single.name, 'Golazo');
  });
}
