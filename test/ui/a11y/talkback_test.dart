import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/l10n/spoken.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/ui/home/widgets/video_tile.dart';
import 'package:kivo_player/ui/player/controls/bottom_bar.dart';
import 'package:kivo_player/ui/player/controls/hold_to_unlock.dart';
import 'package:kivo_player/ui/player/state/lock_state.dart';
import 'package:kivo_player/ui/player/controls/seek_bar.dart';
import 'package:kivo_player/ui/player/player_route.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import 'package:kivo_player/ui/vault/pin_pad.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _es = l10nFor(const Locale('es'));

Future<ProviderContainer> _container({FakePlaybackEngine? engine}) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      if (engine != null) playbackEngineProvider.overrideWithValue(engine),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('spokenDuration', () {
    test('reads like speech, not like a clock', () {
      expect(
        spokenDuration(_es, const Duration(minutes: 1, seconds: 30)),
        '1 minuto 30 segundos',
      );
      expect(spokenDuration(_es, const Duration(minutes: 10)), '10 minutos');
      expect(spokenDuration(_es, Duration.zero), '0 segundos');
    });

    test('past an hour the seconds are dropped', () {
      expect(
        spokenDuration(_es, const Duration(hours: 2, minutes: 5, seconds: 9)),
        '2 horas 5 minutos',
      );
    });

    test(
      'the seek bar keeps them, or a 10 s step would sound like nothing',
      () {
        expect(
          spokenDuration(
            _es,
            const Duration(hours: 1, minutes: 5, seconds: 20),
            withSeconds: true,
          ),
          '1 hora 5 minutos 20 segundos',
        );
        expect(
          spokenDuration(_es, const Duration(hours: 1), withSeconds: true),
          '1 hora',
        );
      },
    );
  });

  testWidgets('controls stay up while TalkBack is on; fade again once off', (
    t,
  ) async {
    final c = await _container();
    final n = c.read(controlsVisibleProvider.notifier);
    n.setAssistive(true);
    await t.pump(const Duration(seconds: 30));
    expect(c.read(controlsVisibleProvider), true);

    n.setAssistive(false);
    await t.pump(const Duration(seconds: 30));
    expect(c.read(controlsVisibleProvider), false);
  });

  // The provider outlives the player: hidden on purpose in one video, the
  // controls must still come up when the next one opens under TalkBack.
  testWidgets(
    'every player opened under TalkBack starts with the controls up',
    (t) async {
      final c = await _container();
      final n = c.read(controlsVisibleProvider.notifier);
      n.setAssistive(true);
      n.hide();
      n.setAssistive(true); // the next PlayerGestures mount
      expect(c.read(controlsVisibleProvider), true);
    },
  );

  testWidgets('locking under TalkBack leaves the unlock button reachable', (
    t,
  ) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final c = await _container(engine: engine);
    c.read(controlsVisibleProvider.notifier).setAssistive(true);
    await pumpLocalized(
      t,
      const Scaffold(backgroundColor: Colors.black, body: BottomBar()),
      container: c,
      theme: KivoTheme.dark(),
    );
    await t.tap(find.byTooltip(_es.playerLockScreenTooltip));
    await t.pump();
    expect(c.read(lockProvider), true);
    expect(c.read(controlsVisibleProvider), true);
  });

  testWidgets('the seek bar says where you are and steps by the skip jump', (
    t,
  ) async {
    final h = t.ensureSemantics();
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final c = await _container(engine: engine);
    await t.runAsync(() async {
      c.listen(positionProvider, (_, __) {});
      c.listen(durationProvider, (_, __) {});
      engine.emitDuration(const Duration(minutes: 10));
      engine.emitPosition(const Duration(minutes: 1, seconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await pumpLocalized(
      t,
      const Scaffold(backgroundColor: Colors.black, body: SeekBar()),
      container: c,
      theme: KivoTheme.dark(),
    );
    await t.pump();

    final bar = find.bySemanticsLabel(_es.playerSeekBarLabel);
    expect(
      t.getSemantics(bar),
      matchesSemantics(
        label: _es.playerSeekBarLabel,
        value: '1 minuto 30 segundos de 10 minutos',
        increasedValue: '1 minuto 40 segundos de 10 minutos',
        decreasedValue: '1 minuto 20 segundos de 10 minutos',
        isSlider: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        // Focusable for a remote / keyboard (←/→ step).
        isFocusable: true,
        hasFocusAction: true,
      ),
    );

    t
        .getSemantics(bar)
        .owner!
        .performAction(t.getSemantics(bar).id, SemanticsAction.increase);
    await t.pump();
    expect(engine.lastSeek, const Duration(minutes: 1, seconds: 40));

    // Two quick swipes: the second steps on from the first, not from the
    // position playback has not reached yet.
    final node = t.getSemantics(bar);
    node.owner!.performAction(node.id, SemanticsAction.increase);
    await t.pump();
    expect(engine.lastSeek, const Duration(minutes: 1, seconds: 50));

    // The time on the right is a button that says what it shows.
    expect(
      find.bySemanticsLabel(_es.playerTotalTimeLabel('10 minutos')),
      findsOneWidget,
    );
    h.dispose();
  });

  testWidgets('a video tile is one node that says what the picture shows', (
    t,
  ) async {
    final h = t.ensureSemantics();
    final c = await _container();
    const video = VideoItem(
      id: '1',
      uri: 'content://1',
      name: 'cool.mkv',
      folder: 'F',
      durationMs: 65000,
      sizeBytes: 1,
      dateAddedMs: 0,
    );
    await pumpLocalized(
      t,
      Scaffold(
        body: SizedBox(
          width: 400,
          child: VideoTile(
            video: video,
            listRow: true,
            progress: 0.4,
            isNew: true,
            onTap: (_) {},
            onOptions: () {},
          ),
        ),
      ),
      container: c,
    );
    await t.pump();
    expect(
      find.bySemanticsLabel(
        'cool.mkv, 1 minuto 5 segundos, visto al 40 %, ${_es.videoTileNewBadge}',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip(_es.videoTileOptionsTooltip), findsOneWidget);
    h.dispose();
  });

  testWidgets('the PIN pad says how many digits are in, not which', (t) async {
    final h = t.ensureSemantics();
    await pumpLocalized(
      t,
      Scaffold(
        body: PinPad(title: 'PIN', onComplete: (_) {}),
      ),
    );
    expect(find.bySemanticsLabel(_es.vaultPinProgress(0, 4)), findsOneWidget);
    await t.tap(find.text('1'));
    await t.tap(find.text('2'));
    await t.pump();
    expect(find.bySemanticsLabel(_es.vaultPinProgress(2, 4)), findsOneWidget);
    expect(find.byTooltip(_es.vaultPinBackspace), findsOneWidget);
    h.dispose();
  });

  testWidgets('a wrong PIN is announced', (t) async {
    final h = t.ensureSemantics();
    await pumpLocalized(
      t,
      Scaffold(
        body: PinPad(title: 'PIN', error: 'PIN incorrecto', onComplete: (_) {}),
      ),
    );
    expect(
      t.getSemantics(find.text('PIN incorrecto')),
      matchesSemantics(label: 'PIN incorrecto', isLiveRegion: true),
    );
    h.dispose();
  });

  testWidgets('locked: TalkBack unlocks with a plain double tap', (t) async {
    final h = t.ensureSemantics();
    var unlocked = 0;
    await pumpLocalized(
      t,
      Scaffold(
        body: Center(
          child: HoldToUnlock(accent: Colors.amber, onUnlock: () => unlocked++),
        ),
      ),
    );
    final node = t.getSemantics(find.bySemanticsLabel(_es.playerUnlockAction));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    expect(unlocked, 1);
    h.dispose();
  });

  testWidgets(
    '"remove animations": the player fades in, no flight from the tile',
    (t) async {
      late Widget result;
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(seconds: 1),
      )..value = 0.5;
      addTearDown(controller.dispose);
      // forward() so the status is "forward", the case that would otherwise grow.
      controller.forward();
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              result = playerTransition(
                context,
                controller,
                const Rect.fromLTWH(20, 100, 168, 94.5),
                const SizedBox(),
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(result, isA<FadeTransition>());
      controller.stop();
    },
  );
}
