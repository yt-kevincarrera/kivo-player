import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/control/player_controller.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/loop/ab_loop.dart';
import 'package:kivo_player/player/open/video_source.dart';
import '../../fakes/fakes.dart';

void main() {
  late FakePlaybackEngine engine;
  late ProviderContainer c;

  Future<void> setUpContainer() async {
    engine = FakePlaybackEngine();
    final s = await SettingsService.load(InMemorySettingsStore());
    c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      // No deviceControlsProvider override needed: PlayerController.seekTo
      // only touches abLoop + engine; nothing in these tests reads it.
    ]);
    addTearDown(c.dispose);
    addTearDown(engine.dispose);
    c.listen(abLoopProvider, (_, __) {});
  }

  // Two microtask turns: StreamController delivery + StreamProvider hop.
  Future<void> pump() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> at(Duration pos) async {
    engine.emitPosition(pos);
    await pump();
  }

  test('begin → armedA; mark fixes A → armedB; mark fixes B → active', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    expect(c.read(abLoopProvider)!.phase, AbLoopPhase.armedA);
    await at(const Duration(seconds: 60));
    n.mark();
    var st = c.read(abLoopProvider)!;
    expect(st.phase, AbLoopPhase.armedB);
    expect(st.a, const Duration(seconds: 60));
    await at(const Duration(seconds: 90));
    n.mark();
    st = c.read(abLoopProvider)!;
    expect(st.phase, AbLoopPhase.active);
    expect(st.a, const Duration(seconds: 60));
    expect(st.b, const Duration(seconds: 90));
  });

  test('marking B before A swaps them', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    await at(const Duration(seconds: 90));
    n.mark();
    await at(const Duration(seconds: 60));
    n.mark();
    final st = c.read(abLoopProvider)!;
    expect(st.phase, AbLoopPhase.active);
    expect(st.a, const Duration(seconds: 60));
    expect(st.b, const Duration(seconds: 90));
  });

  test('a B mark closer than 1s to A is ignored', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    await at(const Duration(seconds: 60));
    n.mark();
    await at(const Duration(seconds: 60, milliseconds: 400));
    n.mark();
    expect(c.read(abLoopProvider)!.phase, AbLoopPhase.armedB); // still waiting for B
  });

  test('mark in active phase cancels the loop', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    await at(const Duration(seconds: 60));
    n.mark();
    await at(const Duration(seconds: 90));
    n.mark();
    n.mark();
    expect(c.read(abLoopProvider), isNull);
  });

  test('reaching B jumps back to A via a direct engine seek', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    await at(const Duration(seconds: 60));
    n.mark();
    await at(const Duration(seconds: 90));
    n.mark();
    engine.lastSeek = null;
    await at(const Duration(seconds: 91));
    expect(engine.lastSeek, const Duration(seconds: 60));
    expect(c.read(abLoopProvider)!.phase, AbLoopPhase.active); // still looping
  });

  test('userSeeked outside the range cancels; inside does not', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    await at(const Duration(seconds: 60));
    n.mark();
    await at(const Duration(seconds: 90));
    n.mark();
    n.userSeeked(const Duration(seconds: 75)); // inside
    expect(c.read(abLoopProvider), isNotNull);
    n.userSeeked(const Duration(seconds: 89, milliseconds: 500)); // within B+1s tolerance edge (inside)
    expect(c.read(abLoopProvider), isNotNull);
    n.userSeeked(const Duration(seconds: 120)); // outside
    expect(c.read(abLoopProvider), isNull);
  });

  test('userSeeked never cancels in armed phases', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    n.userSeeked(const Duration(minutes: 10));
    expect(c.read(abLoopProvider), isNotNull);
    await at(const Duration(seconds: 60));
    n.mark();
    n.userSeeked(const Duration(minutes: 20));
    expect(c.read(abLoopProvider)!.phase, AbLoopPhase.armedB);
  });

  test('PlayerController.seekTo notifies the loop (out-of-range seek cancels)', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    await at(const Duration(seconds: 60));
    n.mark();
    await at(const Duration(seconds: 90));
    n.mark();
    c.read(playerControllerProvider).seekTo(const Duration(minutes: 10));
    expect(c.read(abLoopProvider), isNull);
  });

  test('changing video cancels the loop', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    await at(const Duration(seconds: 60));
    n.mark();
    await at(const Duration(seconds: 90));
    n.mark();
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep2.mkv', displayName: 'ep2.mkv', queue: ['/v/ep2.mkv'], index: 0),
    );
    await pump();
    expect(c.read(abLoopProvider), isNull);
  });

  test('nudges clamp and seek to the verification point', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    engine.emitDuration(const Duration(seconds: 100));
    n.begin();
    await at(const Duration(seconds: 60));
    n.mark();
    await at(const Duration(seconds: 90));
    n.mark();

    n.nudgeA(-1); // 59
    var st = c.read(abLoopProvider)!;
    expect(st.a, const Duration(seconds: 59));
    expect(engine.lastSeek, const Duration(seconds: 59)); // verify jump to A

    n.nudgeB(1); // 91
    st = c.read(abLoopProvider)!;
    expect(st.b, const Duration(seconds: 91));
    expect(engine.lastSeek, const Duration(seconds: 89)); // B − 2s run-up

    // Clamp: A can't cross B−1s.
    for (var i = 0; i < 60; i++) {
      n.nudgeA(1);
    }
    st = c.read(abLoopProvider)!;
    expect(st.a, const Duration(seconds: 90)); // B(91s) − 1s

    // Clamp: B can't exceed duration.
    for (var i = 0; i < 30; i++) {
      n.nudgeB(1);
    }
    expect(c.read(abLoopProvider)!.b, const Duration(seconds: 100));
  });
}
