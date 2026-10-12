import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/all_files_access_provider.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/player/autoplay/autoplay_coordinator.dart';
import 'package:kivo_player/player/end_actions/end_actions.dart';
import 'package:kivo_player/player/end_actions/end_flow.dart';
import 'package:kivo_player/player/end_actions/pending_trash.dart';
import 'package:kivo_player/player/end_actions/trash_queue.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/sleep/sleep_timer.dart';
import 'package:kivo_player/ui/player/state/mini_player_state.dart';
import '../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

VideoItem _item(int i) => VideoItem(
      id: '$i',
      uri: 'content://media/$i',
      name: 'ep$i.mkv',
      folder: 'Serie',
      durationMs: 1000,
      sizeBytes: 1,
      dateAddedMs: 0,
    );

void main() {
  final items = [_item(1), _item(2)];
  late int exits;

  Future<(ProviderContainer, FakePlaybackEngine)> setup(
    WidgetTester t, {
    bool trash = true,
    AfterEnd after = AfterEnd.keepGoing,
  }) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    exits = 0;
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(decoderAutoFallback: false));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      resumeServiceProvider.overrideWithValue(FakeResumeService()),
      subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      mediaFileOpsProvider.overrideWithValue(FakeMediaFileOps()..movesToTrash = true),
      allFilesAccessProvider.overrideWithValue(FakeAllFilesAccess()),
      pendingTrashStoreProvider.overrideWithValue(InMemoryPendingTrashStore()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(items)),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
      appExitProvider.overrideWithValue(() => exits++),
    ]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    c.read(currentVideoProvider.notifier).openFromList(items[0], items);
    c.read(endActionsProvider.notifier)
      ..setTrash(trash)
      ..setAfter(after);
    c.read(playerMinimizedProvider.notifier).state = true;
    c.listen(trashQueueProvider, (_, _) {});
    c.read(autoplayCoordinatorProvider);
    return (c, engine);
  }

  Future<void> settle(WidgetTester t, FakePlaybackEngine engine) async {
    await t.pump();
    engine.emitAudioTracks(const []);
    await t.pump();
    engine.emitSubtitleTracks(const []);
    await t.pump();
    await t.pump(const Duration(seconds: 6)); // undo window
  }

  testWidgets('minimized: advances and trashes the one that ended', (t) async {
    final (c, engine) = await setup(t);
    engine.emitCompleted(true);
    await settle(t, engine);
    expect(c.read(currentVideoProvider)!.index, 1);
    expect(c.read(trashQueueProvider).map((e) => e.uri), ['content://media/1']);
    expect(c.read(currentVideoProvider)!.playOrder, [1]);
  });

  testWidgets('minimized «Cerrar el reproductor»: closes the mini-bar and asks to flush',
      (t) async {
    final (c, engine) = await setup(t, after: AfterEnd.closePlayer);
    engine.emitCompleted(true);
    await settle(t, engine);
    expect(c.read(playerMinimizedProvider), isFalse);
    expect(c.read(trashFlushRequestProvider), 1);
    expect(c.read(currentVideoProvider)!.index, 0); // did not advance
    expect(engine.lastPlayingCommand, false);
  });

  testWidgets('minimized «Cerrar Kivo»: session ends and Kivo leaves', (t) async {
    final (c, engine) = await setup(t, trash: false, after: AfterEnd.closeApp);
    engine.emitCompleted(true);
    await settle(t, engine);
    expect(exits, 1);
    expect(c.read(currentVideoProvider), isNull);
    expect(c.read(suppressTrashFlushProvider), isTrue);
  });

  testWidgets('minimized: the sleep timer\'s episode end runs it too', (t) async {
    final (c, engine) = await setup(t);
    c.read(sleepEpisodeEndProvider.notifier).state++;
    await settle(t, engine);
    expect(c.read(currentVideoProvider)!.index, 0);
    expect(c.read(trashQueueProvider).length, 1);
  });
}
