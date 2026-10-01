import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/subtitles/subtitle_render.dart';
import 'package:kivo_player/player/subtitles/subtitle_render_controller.dart';
import 'package:kivo_player/ui/player/gestures/player_gestures.dart';
import 'package:kivo_player/ui/player/state/lock_state.dart';
import 'package:kivo_player/ui/player/subtitles/subtitle_drag.dart';
import 'package:kivo_player/ui/player/subtitles/subtitle_overlay.dart';
import '../../../fakes/fakes.dart';
import '../../../helpers/pump_app.dart';
import '../video_ready_test.dart' show NoopControls;

class _H {
  _H(this.c, this.engine);
  final ProviderContainer c;
  final FakePlaybackEngine engine;
}

/// The player's own stacking: gestures, then the (touch-transparent)
/// subtitle layer above them.
Future<_H> _pump(WidgetTester tester, {required bool playing}) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  await s.update(s.current.copyWith(doubleTapCenterPause: true));
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    deviceControlsProvider.overrideWithValue(NoopControls()),
  ]);
  addTearDown(c.dispose);
  c.read(subtitleDrawerProvider.notifier).state = SubtitleDrawer.kivo;
  c.listen(playingProvider, (_, __) {});
  await tester.binding.setSurfaceSize(const Size(720, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await pumpLocalized(
    tester,
    const Stack(children: [
      Positioned.fill(child: PlayerGestures(child: SizedBox.expand())),
      Positioned.fill(child: SubtitleOverlay()),
    ]),
    container: c,
  );
  await tester.runAsync(() async {
    engine.emitPlaying(playing);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
  engine.emitSubtitleText('Una línea');
  await tester.pump();
  await tester.pump();
  return _H(c, engine);
}

Finder get _line => find.byKey(const Key('subtitle-primary'));

Future<void> _hold(WidgetTester tester, Offset by) async {
  final gesture = await tester.startGesture(tester.getCenter(_line));
  await tester.pump(const Duration(milliseconds: 700)); // long press
  await gesture.moveBy(by);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('holding the line while playing pauses, moves it, and on '
      'release saves it and plays on', (tester) async {
    final h = await _pump(tester, playing: true);
    final gesture = await tester.startGesture(tester.getCenter(_line));
    await tester.pump(const Duration(milliseconds: 700));
    expect(h.engine.lastPlayingCommand, isFalse, reason: 'paused while held');
    expect(find.byKey(const Key('subtitle-drag-chip')), findsOneWidget);

    await gesture.moveBy(const Offset(0, -80)); // 80 of 400 px = +20 %
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(h.c.read(settingsProvider).subtitleBottomMargin, 6 + 20);
    expect(h.engine.lastPlayingCommand, isTrue, reason: 'plays on');
    expect(find.byKey(const Key('subtitle-drag-chip')), findsNothing);
    expect(h.engine.rate, 1.0, reason: 'a hold on the text is not a speed hold');
  });

  testWidgets('paused stays paused after moving it', (tester) async {
    final h = await _pump(tester, playing: false);
    final before = h.engine.lastPlayingCommand;
    await _hold(tester, const Offset(0, -40));
    expect(h.engine.lastPlayingCommand, before);
    expect(h.c.read(settingsProvider).subtitleBottomMargin, 6 + 10);
  });

  testWidgets('it stays within the 0–40 % range', (tester) async {
    final h = await _pump(tester, playing: false);
    await _hold(tester, const Offset(0, -390));
    expect(h.c.read(settingsProvider).subtitleBottomMargin, 40);
  });

  // The review's finding: with the subtitle layer taking touches, every
  // gesture that began on the text was lost.
  testWidgets('a double tap on the text still reaches the player gestures',
      (tester) async {
    final h = await _pump(tester, playing: true);
    final at = tester.getCenter(_line);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(h.engine.lastPlayingCommand, isFalse,
        reason: 'double tap in the centre pauses, as anywhere else');
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('locked: the line cannot be picked up', (tester) async {
    final h = await _pump(tester, playing: true);
    h.c.read(lockProvider.notifier).lock();
    await tester.pump();
    await _hold(tester, const Offset(0, -80));
    expect(h.c.read(settingsProvider).subtitleBottomMargin, 6);
  });

  testWidgets('torn down mid-drag: the position is saved and playback resumes',
      (tester) async {
    final h = await _pump(tester, playing: true);
    final gesture = await tester.startGesture(tester.getCenter(_line));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await tester.pumpWidget(const SizedBox()); // minimized / screen gone
    expect(h.engine.lastPlayingCommand, isTrue);
    expect(h.c.read(subtitleDragProvider), isNull);
    expect(h.c.read(settingsProvider).subtitleBottomMargin, 6 + 10);
    await gesture.up();
  });
}
