import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/l10n/generated/app_localizations.dart';
import 'package:kivo_player/platform/all_files_access_provider.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/pip_controller_provider.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/end_actions/end_flow.dart';
import 'package:kivo_player/player/end_actions/pending_trash.dart';
import 'package:kivo_player/player/end_actions/trash_queue.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/player/sleep/sleep_timer.dart';
import 'package:kivo_player/ui/player/player_screen.dart';
import 'package:kivo_player/ui/player/controls/seek_bar.dart';
import 'package:kivo_player/ui/player/state/autoplay_state.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import 'package:kivo_player/ui/player/state/queue_strip_state.dart';
import 'package:kivo_player/ui/player/state/mini_player_state.dart';
import '../../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

class _Controls implements DeviceControls {
  final List<double> brightness = [];
  final List<bool> awake = [];
  @override Future<double> currentBrightness() async => 0.7;
  @override Future<void> setBrightness(double v) async => brightness.add(v);
  @override Future<double> currentVolume() async => 0.5;
  @override Future<void> setSystemVolume(double v) async {}
  @override Future<void> setOrientation(List<DeviceOrientationLock> o) async {}
  @override Future<void> keepAwake(bool on) async => awake.add(on);
  @override Future<void> setImmersive(bool on) async {}
  @override Future<void> resetBrightness() async {}
  @override Stream<double> get systemVolumeStream => const Stream<double>.empty();
  @override Future<void> setVolumeKeyInterception(bool on) async {}
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
  final items = [_item(1), _item(2), _item(3)];
  late FakePlaybackEngine engine;
  late FakeMediaFileOps ops;
  late _Controls controls;
  late int exits;

  Future<ProviderContainer> pumpPlayer(
    WidgetTester tester, {
    bool trash = true,
    AfterEnd after = AfterEnd.keepGoing,
    bool autoplayNext = true,
    List<VideoItem>? queue,
    String? repeatMode,
    double textScale = 1,
  }) async {
    final shown = queue ?? items;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    ops = FakeMediaFileOps()..movesToTrash = true;
    controls = _Controls();
    exits = 0;
    final s = await SettingsService.load(InMemorySettingsStore());
    // Past the first-run gesture tutorial, which would cover the player.
    await s.update(s.current.copyWith(
      gestureMapShown: true,
      autoplayNext: autoplayNext,
      repeatMode: repeatMode,
    ));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(controls),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
      pipControllerProvider.overrideWithValue(FakePipController()),
      mediaFileOpsProvider.overrideWithValue(ops),
      allFilesAccessProvider.overrideWithValue(FakeAllFilesAccess()),
      pendingTrashStoreProvider.overrideWithValue(InMemoryPendingTrashStore()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(shown)),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
      trashUndoWindowProvider.overrideWithValue(const Duration(seconds: 1)),
      appExitProvider.overrideWithValue(() => exits++),
    ]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    c.read(currentVideoProvider.notifier).openFromList(shown[0], shown);
    c.read(endActionsProvider.notifier)
      ..setTrash(trash)
      ..setAfter(after);
    c.listen(trashQueueProvider, (_, _) {});

    // The player is pushed over a home route, as in the app, so closing it
    // has somewhere to go back to.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlayerScreen())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    // Unmount before the container goes (teardowns run last-in first-out).
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    engine.emitAudioTracks(const []);
    engine.emitSubtitleTracks(const []);
    await tester.pump();
    return c;
  }

  Future<void> drain(WidgetTester tester) async {
    engine.emitAudioTracks(const []);
    engine.emitSubtitleTracks(const []);
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('portrait end-actions chip stays clear of the seek bar with a queue',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = await pumpPlayer(tester);
    c.read(controlsVisibleProvider.notifier).show();
    await tester.pump(const Duration(milliseconds: 250));
    final chip = tester.getRect(find.byKey(const Key('end-actions-chip')));
    final seek = tester.getRect(find.byType(SeekBar));
    expect(chip.bottom, lessThanOrEqualTo(seek.top - 8));
    await drain(tester);
  });

  for (final layout in [
    (size: const Size(320, 640), scale: 1.0, inset: 24.0, queue: true),
    (size: const Size(390, 844), scale: 2.0, inset: 34.0, queue: true),
    (size: const Size(390, 844), scale: 1.0, inset: 34.0, queue: false),
    (size: const Size(844, 390), scale: 1.0, inset: 24.0, queue: true),
  ]) {
    testWidgets('end-actions clears seek at ${layout.size}, text ${layout.scale}, queue ${layout.queue}',
        (tester) async {
      tester.view.physicalSize = layout.size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(bottom: layout.inset);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final c = await pumpPlayer(tester, queue: layout.queue ? null : [items.first],
          textScale: layout.scale, after: AfterEnd.closePlayer);
      c.read(controlsVisibleProvider.notifier).show();
      await tester.pump(const Duration(milliseconds: 250));
      final chip = tester.getRect(find.byKey(const Key('end-actions-chip')));
      final seek = tester.getRect(find.byType(SeekBar));
      expect(chip.bottom, lessThanOrEqualTo(seek.top - 8));
      expect(chip.left, greaterThanOrEqualTo(0));
      expect(chip.right, lessThanOrEqualTo(layout.size.width));
      expect(tester.takeException(), isNull);
      await drain(tester);
    });
  }

  testWidgets('restart reopens the current video at zero without trash or a countdown',
      (tester) async {
    final c = await pumpPlayer(tester, after: AfterEnd.restart, autoplayNext: false);
    final session = c.read(currentVideoProvider)!;
    await c.read(resumeServiceProvider).record(session.resumeKey,
        const Duration(seconds: 30), const Duration(minutes: 5), 0);
    final before = engine.openCount;
    engine.emitCompleted(true);
    await tester.pump();
    await tester.pump();
    expect(engine.openCount, before + 1);
    expect(engine.openedPath, session.playbackPath);
    expect(engine.openedAt, Duration.zero);
    expect(c.read(resumeServiceProvider).positionFor(session.resumeKey), isNull);
    expect(engine.openedPlaying, isTrue);
    expect(c.read(currentVideoProvider)!.index, 0);
    expect(c.read(endTrashProvider), isNull);
    expect(c.read(trashQueueProvider), isEmpty);
    expect(c.read(autoplayPendingProvider), isNull);
    expect(c.read(afterPendingProvider), isNull);
    await drain(tester);
  });

  testWidgets('sleep episode stop takes priority over restart', (tester) async {
    final c = await pumpPlayer(tester, after: AfterEnd.restart);
    final before = engine.openCount;
    c.read(sleepEpisodeEndProvider.notifier).state++;
    await tester.pump();
    engine.emitCompleted(true);
    await tester.pump();
    expect(engine.openCount, before);
    expect(c.read(trashQueueProvider), isEmpty);
    await drain(tester);
  });

  testWidgets('trash on: the card warns, and moving on trashes the ended video',
      (tester) async {
    final c = await pumpPlayer(tester);
    engine.emitCompleted(true);
    await tester.pump();

    expect(c.read(autoplayPendingProvider)?.index, 1);
    expect(c.read(endTrashProvider)?.item.uri, 'content://media/1');
    expect(find.byKey(const Key('end-trash-line')), findsOneWidget);

    c.read(autoplayConfirmProvider.notifier).state = true;
    await tester.pump();
    await tester.pump();

    expect(c.read(currentVideoProvider)!.index, 1);
    expect(c.read(trashQueueProvider).map((e) => e.uri), ['content://media/1']);
    expect(c.read(currentVideoProvider)!.playOrder, [1, 2]);
    expect(c.read(trashUndoProvider), isNotNull);
    await drain(tester);
  });

  testWidgets('«Conservar» on the card keeps this one', (tester) async {
    final c = await pumpPlayer(tester);
    engine.emitCompleted(true);
    await tester.pump();
    await tester.tap(find.text(lookupAppLocalizations(const Locale('es')).endActionsKeep));
    await tester.pump();
    expect(find.byKey(const Key('end-trash-line')), findsNothing);

    c.read(autoplayConfirmProvider.notifier).state = true;
    await tester.pump();
    await tester.pump();
    expect(c.read(currentVideoProvider)!.index, 1);
    expect(c.read(trashQueueProvider), isEmpty);
    await drain(tester);
  });

  testWidgets('«Cancelar» means nothing happens: no advance, no trash',
      (tester) async {
    final c = await pumpPlayer(tester);
    engine.emitCompleted(true);
    await tester.pump();
    await tester.tap(find.text(lookupAppLocalizations(const Locale('es')).commonCancel));
    await tester.pump();
    expect(c.read(autoplayPendingProvider), isNull);
    expect(c.read(endTrashProvider), isNull);
    expect(c.read(currentVideoProvider)!.index, 0);
    expect(c.read(trashQueueProvider), isEmpty);
    await drain(tester);
  });

  testWidgets('no next video: trashed right away (the undo toast is the net)',
      (tester) async {
    final c = await pumpPlayer(tester, autoplayNext: false);
    engine.emitCompleted(true);
    await tester.pump();
    await tester.pump();
    expect(c.read(autoplayPendingProvider), isNull);
    expect(c.read(trashQueueProvider).map((e) => e.uri), ['content://media/1']);
    expect(find.text(lookupAppLocalizations(const Locale('es')).trashUndoOnExit),
        findsOneWidget);
    await drain(tester);
  });

  testWidgets('a mid-video pause from the fixed sleep timer runs nothing',
      (tester) async {
    final c = await pumpPlayer(tester, after: AfterEnd.closePlayer);
    c.read(sleepTimerProvider.notifier).startFixed(const Duration(minutes: 30));
    c.read(sleepTimerProvider.notifier).cancel(); // (as if it fired: no end signal)
    engine.emitPlaying(false);
    await tester.pump();
    expect(c.read(afterPendingProvider), isNull);
    expect(c.read(trashQueueProvider), isEmpty);
    expect(find.byType(PlayerScreen), findsOneWidget);
    await drain(tester);
  });

  testWidgets('the sleep timer stopping an episode is an ending — once',
      (tester) async {
    final c = await pumpPlayer(tester, autoplayNext: false);
    c.read(sleepEpisodeEndProvider.notifier).state++;
    await tester.pump();
    engine.emitCompleted(true); // a late `completed` for the same play-through
    await tester.pump();
    await tester.pump();
    expect(c.read(trashQueueProvider).length, 1);
    expect(c.read(currentVideoProvider)!.index, 0); // the timer said stop
    await drain(tester);
  });

  testWidgets('«Cerrar el reproductor» counts down, then closes with no mini-bar',
      (tester) async {
    final c = await pumpPlayer(tester, after: AfterEnd.closePlayer);
    engine.emitCompleted(true);
    await tester.pump();
    expect(c.read(afterPendingProvider), AfterEnd.closePlayer);
    expect(c.read(autoplayPendingProvider), isNull);
    expect(
        find.text(lookupAppLocalizations(const Locale('es')).endActionsCountdownClosePlayer),
        findsOneWidget);

    await tester.pump(); // the ring starts ticking on this frame
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1)); // the route leaving
    expect(find.byType(PlayerScreen), findsNothing);
    expect(c.read(playerMinimizedProvider), isFalse);
    expect(c.read(trashQueueProvider).map((e) => e.uri), ['content://media/1']);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('«Cerrar Kivo» closes the player, ends the session and leaves',
      (tester) async {
    final c = await pumpPlayer(tester, trash: false, after: AfterEnd.closeApp);
    engine.emitCompleted(true);
    await tester.pump();
    c.read(afterConfirmProvider.notifier).state = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
    expect(exits, 1);
    expect(c.read(currentVideoProvider), isNull);
    expect(c.read(suppressTrashFlushProvider), isTrue);
    expect(find.byType(PlayerScreen), findsNothing);
  });

  testWidgets('«Apagar la pantalla» dims and lets go of the screen; playing restores',
      (tester) async {
    final c = await pumpPlayer(tester, trash: false, after: AfterEnd.screenOff);
    engine.emitCompleted(true);
    await tester.pump();
    c.read(afterConfirmProvider.notifier).state = true;
    await tester.pump();
    await tester.pump();
    expect(controls.brightness.last, 0);
    expect(controls.awake.last, isFalse);

    engine.emitPlaying(true);
    await tester.pump();
    expect(controls.brightness.last, 0.7);
    expect(controls.awake.last, isTrue);
    await drain(tester);
  });

  testWidgets('«Terminar ya» skips the countdown', (tester) async {
    final c = await pumpPlayer(tester);
    c.read(finishNowProvider.notifier).state++;
    await tester.pump();
    await tester.pump();
    expect(c.read(autoplayPendingProvider), isNull);
    expect(c.read(currentVideoProvider)!.index, 1);
    expect(c.read(trashQueueProvider).map((e) => e.uri), ['content://media/1']);
    await drain(tester);
  });

  testWidgets('«Papelera y siguiente» works with the mode off', (tester) async {
    final c = await pumpPlayer(tester, trash: false);
    c.read(trashAndNextProvider.notifier).state++;
    await tester.pump();
    await tester.pump();
    expect(c.read(currentVideoProvider)!.index, 1);
    expect(c.read(trashQueueProvider).map((e) => e.uri), ['content://media/1']);
    expect(c.read(endActionsProvider).trash, isFalse);
    await drain(tester);
  });

  testWidgets('another video during a «Después» countdown cancels it', (tester) async {
    final c = await pumpPlayer(tester, trash: false, after: AfterEnd.closeApp);
    engine.emitCompleted(true);
    await tester.pump();
    expect(c.read(afterPendingProvider), AfterEnd.closeApp);
    c.read(queueJumpProvider.notifier).state = 2; // a card in the strip
    await tester.pump();
    await tester.pump();
    expect(c.read(afterPendingProvider), isNull);
    await tester.pump(const Duration(seconds: 4));
    expect(exits, 0);
    expect(find.byType(PlayerScreen), findsOneWidget);
    await drain(tester);
  });

  testWidgets('repeat-list on a one-video queue replays it: never trashed',
      (tester) async {
    final c = await pumpPlayer(tester, queue: [items[0]], repeatMode: 'list');
    engine.emitCompleted(true);
    await tester.pump();
    await tester.pump();
    expect(c.read(endTrashProvider), isNull);
    expect(c.read(trashQueueProvider), isEmpty);
    await drain(tester);
  });

  testWidgets('the chip\'s ⏭ is «Terminar ya»', (tester) async {
    final c = await pumpPlayer(tester);
    c.read(controlsVisibleProvider.notifier).show();
    await tester.pump();
    await tester.tap(find.byKey(const Key('end-actions-chip-finish')));
    await tester.pump();
    await tester.pump();
    expect(c.read(currentVideoProvider)!.index, 1);
    expect(c.read(trashQueueProvider).map((e) => e.uri), ['content://media/1']);
    await drain(tester);
  });
}
