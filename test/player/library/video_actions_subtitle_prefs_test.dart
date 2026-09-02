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
import 'package:kivo_player/player/tracks/subtitle_importer.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import '../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

const _v = VideoItem(
    id: '1', uri: 'content://1', name: 'ep1.mkv', folder: 'Series',
    durationMs: 1000, sizeBytes: 10, dateAddedMs: 0);
const _v2 = VideoItem(
    id: '2', uri: 'content://2', name: 'ep2.mkv', folder: 'Series',
    durationMs: 1000, sizeBytes: 10, dateAddedMs: 0);

/// Assembles a [VideoActionsController] container the same way the other
/// `video_actions_*_test.dart` files do, plus the subtitle prefs store this
/// file exercises. Named-parameter shape so later tests (e.g. an `importer`
/// override) can extend it without touching existing call sites.
Future<ProviderContainer> buildVideoActionsContainer({
  required TrackPrefsStore subtitlePrefs,
  String? renameTo,
  SubtitleImporter? importer,
}) async {
  final resume = ResumeService(InMemoryResumeStore());
  final played = InMemoryPlayedStore();
  final ops = FakeMediaFileOps()
    ..deleteResult = FileOpStatus.ok
    ..deleteManyResult = FileOpStatus.ok;
  if (renameTo != null) {
    ops.renameOutcome = RenameOutcome(FileOpStatus.ok, newName: renameTo);
  }
  return ProviderContainer(overrides: [
    mediaFileOpsProvider.overrideWithValue(ops),
    resumeServiceProvider.overrideWithValue(resume),
    playedStoreProvider.overrideWithValue(played),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
    mediaPermissionImplProvider.overrideWithValue(_Perm()),
    trackPrefsStoreProvider.overrideWithValue(subtitlePrefs),
    subtitleImporterProvider.overrideWithValue(importer ?? FakeSubtitleImporter()),
    bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
  ]);
}

void main() {
  test('rename carries the subtitle prefs to the new name', () async {
    final store = InMemoryTrackPrefsStore();
    await store.put('ep1.mkv', const VideoTrackPrefs(subtitleDelayMs: 500));
    final c = await buildVideoActionsContainer(
        subtitlePrefs: store, renameTo: 'ep1-renamed.mkv');
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).rename(_v, 'ep1-renamed');

    expect(store.forKey('ep1.mkv'), isNull);
    expect(store.forKey('ep1-renamed.mkv')!.subtitleDelayMs, 500);
  });

  test('delete clears the subtitle prefs', () async {
    final store = InMemoryTrackPrefsStore();
    await store.put('ep1.mkv', const VideoTrackPrefs(subtitleDelayMs: 500));
    final c = await buildVideoActionsContainer(subtitlePrefs: store);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).delete(_v);

    expect(store.forKey('ep1.mkv'), isNull);
  });

  test('deleteMany clears the prefs of every video in the batch', () async {
    final store = InMemoryTrackPrefsStore();
    await store.put('ep1.mkv', const VideoTrackPrefs(subtitleDelayMs: 500));
    final c = await buildVideoActionsContainer(subtitlePrefs: store);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).deleteMany([_v]);

    expect(store.forKey('ep1.mkv'), isNull);
  });

  test('deleting a video also deletes its imported subtitle copy', () async {
    final store = InMemoryTrackPrefsStore();
    await store.put('ep1.mkv',
        const VideoTrackPrefs(subtitlePath: '/app/subs/ep1.mkv.srt'));
    final importer = FakeSubtitleImporter();
    final c = await buildVideoActionsContainer(
        subtitlePrefs: store, importer: importer);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).delete(_v);

    expect(importer.discarded, ['/app/subs/ep1.mkv.srt']);
  });

  test('a video with no imported copy discards nothing', () async {
    final store = InMemoryTrackPrefsStore();
    await store.put('ep1.mkv', const VideoTrackPrefs(subtitleDelayMs: 500));
    final importer = FakeSubtitleImporter();
    final c = await buildVideoActionsContainer(
        subtitlePrefs: store, importer: importer);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).delete(_v);

    expect(importer.discarded, isEmpty);
  });

  test('deleteMany discards each video\'s own imported subtitle copy',
      () async {
    final store = InMemoryTrackPrefsStore();
    await store.put('ep1.mkv',
        const VideoTrackPrefs(subtitlePath: '/app/subs/ep1.mkv.srt'));
    await store.put('ep2.mkv',
        const VideoTrackPrefs(subtitlePath: '/app/subs/ep2.mkv.srt'));
    final importer = FakeSubtitleImporter();
    final c = await buildVideoActionsContainer(
        subtitlePrefs: store, importer: importer);
    addTearDown(c.dispose);

    // Two videos, not one: this is what proves the discard runs per-item
    // inside the deleteMany loop, rather than once for the whole batch.
    await c.read(videoActionsProvider).deleteMany([_v, _v2]);

    expect(
        importer.discarded,
        unorderedEquals(
            ['/app/subs/ep1.mkv.srt', '/app/subs/ep2.mkv.srt']));
  });
}
