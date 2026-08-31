import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_playback.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';
import '../../fakes/fakes.dart';

VideoItem _v(String id, String name) => VideoItem(
      id: id,
      uri: 'content://$id',
      name: name,
      folder: 'Series',
      durationMs: 1000,
      sizeBytes: 10,
      dateAddedMs: 0,
    );

// Named to match the existing convention in library_index_test.dart — there
// is no shared FakeMediaPermission in test/fakes/fakes.dart, each test file
// defines its own trivial granted-access permission.
class _GrantedPerm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

// Copy the container-assembly pattern from the existing tests in
// test/player/library/ for mediaIndexerProvider and mediaPermissionImplProvider
// — do not invent fake names. mediaIndexProvider.build() watches
// mediaPermissionProvider, which reads mediaPermissionImplProvider, so that
// provider must be overridden too or the build throws UnimplementedError.
Future<ProviderContainer> _c(List<VideoItem> index, PlayedStore played) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  var tick = 0;
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(index)),
    mediaPermissionImplProvider.overrideWithValue(_GrantedPerm()),
    playedStoreProvider.overrideWithValue(played),
    playlistStoreProvider.overrideWithValue(InMemoryPlaylistStore()),
    playlistClockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(1000 + tick++)),
  ]);
}

void main() {
  test('playing a playlist opens the first unplayed entry', () async {
    final played = InMemoryPlayedStore()..markPlayed('a.mkv');
    final c = await _c([_v('1', 'a.mkv'), _v('2', 'b.mkv')], played);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);

    expect(c.read(playlistPlaybackProvider).play(p.id), true);

    final session = c.read(currentVideoProvider)!;
    expect(session.displayName, 'b.mkv');
    // The whole playlist is the queue, so autoplay walks it.
    expect(session.queue.length, 2);
    expect(session.index, 1);
  });

  test('an unavailable entry is not in the queue', () async {
    final c = await _c([_v('2', 'b.mkv')], InMemoryPlayedStore());
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);

    expect(c.read(playlistPlaybackProvider).play(p.id), true);
    final session = c.read(currentVideoProvider)!;
    expect(session.queue.length, 1);
    expect(session.displayName, 'b.mkv');
  });

  test('a playlist with nothing playable refuses instead of opening', () async {
    final c = await _c(const [], InMemoryPlayedStore());
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    expect(c.read(playlistPlaybackProvider).play(p.id), false);
    expect(c.read(currentVideoProvider), isNull);
  });

  test('playAt opens the entry that was tapped', () async {
    final c = await _c([_v('1', 'a.mkv'), _v('2', 'b.mkv')], InMemoryPlayedStore());
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);

    expect(c.read(playlistPlaybackProvider).playAt(p.id, 1), true);
    expect(c.read(currentVideoProvider)!.displayName, 'b.mkv');
  });

  test('playAt on an unavailable entry refuses', () async {
    final c = await _c([_v('2', 'b.mkv')], InMemoryPlayedStore());
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);

    expect(c.read(playlistPlaybackProvider).playAt(p.id, 0), false);
    expect(c.read(currentVideoProvider), isNull);
  });

  test('resolution reads the raw index, past the hidden-folders filter',
      () async {
    final c = await _c([_v('1', 'a.mkv')], InMemoryPlayedStore());
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    // Hide the folder the video lives in. A playlist the user built by hand
    // must not empty itself because of a view filter.
    final s = c.read(settingsProvider);
    await c.read(settingsProvider.notifier)
        .set(s.copyWith(excludedFolders: const ['Series']));

    expect(c.read(resolvedPlaylistProvider(p.id)).single.available, true);
  });
}
