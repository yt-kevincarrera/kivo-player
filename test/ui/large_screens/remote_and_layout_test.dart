import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/controls/hold_to_unlock.dart';
import 'package:kivo_player/ui/player/controls/seek_bar.dart';
import 'package:kivo_player/ui/player/state/lock_state.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/ui/home/widgets/video_density_feed.dart';
import 'package:kivo_player/ui/home/widgets/video_tile.dart';
import 'package:kivo_player/ui/player/controls/center_controls.dart';
import 'package:kivo_player/ui/player/keys/player_keys.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import 'package:kivo_player/ui/widgets/readable_width.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

void main() {
  group('playerKeyAction', () {
    PlayerKeyAction a(
      LogicalKeyboardKey k, {
      bool visible = false,
      bool locked = false,
    }) => playerKeyAction(k, controlsVisible: visible, locked: locked);

    test(
      'controls hidden: the D-pad seeks, OK plays/pauses, up/down reveal',
      () {
        expect(a(LogicalKeyboardKey.arrowLeft), PlayerKeyAction.seekBack);
        expect(a(LogicalKeyboardKey.arrowRight), PlayerKeyAction.seekForward);
        expect(a(LogicalKeyboardKey.select), PlayerKeyAction.togglePlay);
        expect(a(LogicalKeyboardKey.enter), PlayerKeyAction.togglePlay);
        expect(a(LogicalKeyboardKey.arrowUp), PlayerKeyAction.revealControls);
        expect(a(LogicalKeyboardKey.arrowDown), PlayerKeyAction.revealControls);
      },
    );

    test('controls up: the D-pad belongs to the buttons', () {
      for (final k in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.select,
      ]) {
        expect(a(k, visible: true), PlayerKeyAction.pass, reason: '$k');
      }
      expect(
        a(LogicalKeyboardKey.space, visible: true),
        PlayerKeyAction.togglePlay,
      );
    });

    test('media keys always work, even locked; nothing else does locked', () {
      expect(
        a(LogicalKeyboardKey.mediaPlayPause, locked: true),
        PlayerKeyAction.togglePlay,
      );
      expect(
        a(LogicalKeyboardKey.mediaFastForward, locked: true),
        PlayerKeyAction.seekForward,
      );
      expect(
        a(LogicalKeyboardKey.mediaTrackNext, visible: true),
        PlayerKeyAction.next,
      );
      expect(
        a(LogicalKeyboardKey.arrowRight, locked: true),
        PlayerKeyAction.pass,
      );
      expect(a(LogicalKeyboardKey.space, locked: true), PlayerKeyAction.pass);
    });
  });

  group('queueStep', () {
    const s = VideoSession(
      playbackPath: 'b',
      displayName: 'b',
      queue: ['a', 'b', 'c'],
      index: 1,
    );
    test('neighbours in play order; wraps only under repeat-list', () {
      expect(queueStep(s, forward: true, wrap: false), 2);
      expect(queueStep(s, forward: false, wrap: false), 0);
      const last = VideoSession(
        playbackPath: 'c',
        displayName: 'c',
        queue: ['a', 'b', 'c'],
        index: 2,
      );
      expect(queueStep(last, forward: true, wrap: false), isNull);
      expect(queueStep(last, forward: true, wrap: true), 0);
    });

    test('shuffled: follows the drawn order', () {
      const sh = VideoSession(
        playbackPath: 'a',
        displayName: 'a',
        queue: ['a', 'b', 'c'],
        index: 0,
        order: [0, 2, 1],
      );
      expect(queueStep(sh, forward: true, wrap: false), 2);
    });
  });

  group('PlayerKeys', () {
    Future<(ProviderContainer, FakePlaybackEngine)> pump(WidgetTester t) async {
      final engine = FakePlaybackEngine();
      addTearDown(engine.dispose);
      final s = await SettingsService.load(InMemorySettingsStore());
      final c = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWithValue(s),
          playbackEngineProvider.overrideWithValue(engine),
        ],
      );
      addTearDown(c.dispose);
      await t.runAsync(() async {
        c.listen(positionProvider, (_, __) {});
        c.listen(durationProvider, (_, __) {});
        c.listen(playingProvider, (_, __) {});
        engine.emitDuration(const Duration(minutes: 10));
        engine.emitPosition(const Duration(minutes: 1));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await pumpLocalized(
        t,
        const PlayerKeys(
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CenterControls()),
          ),
        ),
        container: c,
        theme: KivoTheme.dark(),
      );
      await t.pump();
      return (c, engine);
    }

    testWidgets('→ with the controls hidden skips forward', (t) async {
      final (_, engine) = await pump(t);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(engine.lastSeek, const Duration(minutes: 1, seconds: 10));
      await t.pump(const Duration(seconds: 2)); // the skip HUD's timer
    });

    testWidgets('OK plays/pauses', (t) async {
      final (_, engine) = await pump(t);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pump();
      expect(engine.lastPlayingCommand, isNotNull);
    });

    testWidgets('↓ brings the controls up with play/pause focused', (t) async {
      final (c, _) = await pump(t);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      await t.pump();
      expect(c.read(controlsVisibleProvider), true);
      expect(c.read(playPauseFocusProvider).hasFocus, true);
      await t.pump(const Duration(seconds: 5)); // auto-hide timer
    });
  });

  testWidgets('locked: a D-pad press brings up unlock, OK unlocks', (t) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
        playbackEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(c.dispose);
    c.read(lockProvider.notifier).lock();
    await pumpLocalized(
      t,
      PlayerKeys(
        child: Scaffold(
          body: Center(
            child: Consumer(
              builder: (context, ref, _) => HoldToUnlock(
                accent: Colors.amber,
                focusNode: ref.watch(unlockFocusProvider),
                onUnlock: () => ref.read(lockProvider.notifier).unlock(),
              ),
            ),
          ),
        ),
      ),
      container: c,
      theme: KivoTheme.dark(),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    await t.pump();
    expect(c.read(unlockFocusProvider).hasFocus, true);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(c.read(lockProvider), false);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets(
    'the seek bar on a remote: ←/→ step by the skip jump, the slider never traps focus',
    (t) async {
      final engine = FakePlaybackEngine();
      addTearDown(engine.dispose);
      final s = await SettingsService.load(InMemorySettingsStore());
      final c = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWithValue(s),
          playbackEngineProvider.overrideWithValue(engine),
          frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
        ],
      );
      addTearDown(c.dispose);
      await t.runAsync(() async {
        c.listen(positionProvider, (_, __) {});
        c.listen(durationProvider, (_, __) {});
        engine.emitDuration(const Duration(minutes: 10));
        engine.emitPosition(const Duration(minutes: 1));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await pumpLocalized(
        t,
        const Scaffold(backgroundColor: Colors.black, body: SeekBar()),
        container: c,
        theme: KivoTheme.dark(),
      );
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      // The bar's own key handler has it; the Slider inside never does.
      final sliderFocus = t.widget<Focus>(
        find
            .descendant(of: find.byType(Slider), matching: find.byType(Focus))
            .first,
      );
      expect(sliderFocus.focusNode?.hasFocus ?? false, false);
      expect(FocusManager.instance.primaryFocus, isNotNull);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(engine.lastSeek, const Duration(minutes: 1, seconds: 10));
      await t.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('controls fading out hand the focus back to the player', (
    t,
  ) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
        playbackEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(c.dispose);
    await t.runAsync(() async {
      c.listen(playingProvider, (_, __) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await pumpLocalized(
      t,
      const PlayerKeys(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CenterControls()),
        ),
      ),
      container: c,
      theme: KivoTheme.dark(),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    await t.pump();
    expect(c.read(playPauseFocusProvider).hasFocus, true);
    c.read(controlsVisibleProvider.notifier).hide();
    await t.pump();
    expect(c.read(playPauseFocusProvider).hasFocus, false);
    // → now seeks again instead of moving among invisible buttons.
    await t.runAsync(() async {
      c.listen(durationProvider, (_, __) {});
      c.listen(positionProvider, (_, __) {});
      engine.emitDuration(const Duration(minutes: 10));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(engine.lastSeek, const Duration(seconds: 10));
    await t.pump(const Duration(seconds: 5));
  });

  group('wide screens', () {
    test('a phone keeps the chosen columns; wider screens get more', () {
      expect(adaptiveColumns(2, 393), 2);
      expect(adaptiveColumns(3, 393), 3);
      expect(adaptiveColumns(2, 800), 3);
      expect(adaptiveColumns(2, 1280), 6);
      expect(adaptiveColumns(3, 2000), 8);
      expect(adaptiveColumns(1, 1280), 1, reason: 'a list stays a list');
    });

    testWidgets('settings stay readable: centred within 720', (t) async {
      late EdgeInsets phone, tv;
      Widget probe(double w, void Function(EdgeInsets) out) => MediaQuery(
        data: MediaQueryData(size: Size(w, 800)),
        child: Builder(
          builder: (context) {
            out(
              readablePadding(
                context,
                const EdgeInsets.symmetric(horizontal: 14),
              ),
            );
            return const SizedBox();
          },
        ),
      );
      await t.pumpWidget(probe(393, (e) => phone = e));
      await t.pumpWidget(probe(1280, (e) => tv = e));
      expect(phone.left, 14);
      expect(tv.left, 14 + (1280 - 720) / 2);
    });
  });

  testWidgets(
    'a video tile opens with OK and shows its options with the menu key',
    (t) async {
      final s = await SettingsService.load(InMemorySettingsStore());
      final c = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWithValue(s),
          mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
        ],
      );
      addTearDown(c.dispose);
      var opened = 0, options = 0;
      await pumpLocalized(
        t,
        Scaffold(
          body: SizedBox(
            width: 400,
            child: VideoTile(
              video: const VideoItem(
                id: '1',
                uri: 'content://1',
                name: 'a.mkv',
                folder: 'F',
                durationMs: 1000,
                sizeBytes: 1,
                dateAddedMs: 0,
              ),
              listRow: true,
              onTap: (_) => opened++,
              onOptions: () => options++,
            ),
          ),
        ),
        container: c,
      );
      await t.pump();
      // Tab moves the focus like a D-pad press would onto the first control.
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(opened, 1);
      await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await t.pump();
      expect(options, 1);
    },
  );
}
