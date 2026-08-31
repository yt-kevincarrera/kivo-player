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
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';
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

// Copy of the container-assembly pattern from
// test/player/library/video_actions_test.dart, plus the playlist overrides.
ProviderContainer buildContainer({
  required PlaylistStore playlistStore,
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
    playlistStoreProvider.overrideWithValue(playlistStore),
    playlistClockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(1000)),
  ]);
}

void main() {
  test('renaming a video updates its name in playlists', () async {
    final store = InMemoryPlaylistStore();
    final c = buildContainer(playlistStore: store, renameTo: 'ep1-nuevo.mkv');
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v]);

    await c.read(videoActionsProvider).rename(_v, 'ep1-nuevo');

    expect(store.all().single.entries.single.displayName, 'ep1-nuevo.mkv');
  });

  test('deleting a video leaves the playlist entry alone', () async {
    // Deliberate: the entry renders greyed instead. An SD card unplugged for
    // an afternoon must not destroy a playlist, and there is no undo for that.
    final store = InMemoryPlaylistStore();
    final c = buildContainer(playlistStore: store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v]);

    await c.read(videoActionsProvider).delete(_v);

    expect(store.all().single.entries.length, 1);
  });
}
