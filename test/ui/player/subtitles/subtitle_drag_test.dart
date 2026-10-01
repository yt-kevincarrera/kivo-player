import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/subtitles/subtitle_render.dart';
import 'package:kivo_player/player/subtitles/subtitle_render_controller.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import 'package:kivo_player/ui/player/state/lock_state.dart';
import 'package:kivo_player/ui/player/subtitles/subtitle_overlay.dart';
import '../../../fakes/fakes.dart';
import '../../../helpers/pump_app.dart';

class _H {
  _H(this.c, this.engine);
  final ProviderContainer c;
  final FakePlaybackEngine engine;
}

Future<_H> _pump(WidgetTester tester, {required bool playing}) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
  ]);
  addTearDown(c.dispose);
  c.read(subtitleDrawerProvider.notifier).state = SubtitleDrawer.kivo;
  c.listen(playingProvider, (_, __) {});
  await tester.binding.setSurfaceSize(const Size(720, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await pumpLocalized(tester, const SizedBox.expand(child: SubtitleOverlay()),
      container: c);
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

void main() {
  testWidgets('holding the line while playing pauses, moving it moves it, '
      'letting go saves it and plays on', (tester) async {
    final h = await _pump(tester, playing: true);
    final gesture = await tester.startGesture(tester.getCenter(_line));
    await tester.pump(const Duration(milliseconds: 600)); // long press
    expect(h.engine.lastPlayingCommand, isFalse, reason: 'paused while held');
    expect(find.byKey(const Key('subtitle-drag-chip')), findsOneWidget);

    await gesture.moveBy(const Offset(0, -80)); // 80 px up of 400 = +20 %
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final margin = h.c.read(settingsProvider).subtitleBottomMargin;
    expect(margin, 6 + 20);
    expect(h.engine.lastPlayingCommand, isTrue, reason: 'plays on');
    expect(find.byKey(const Key('subtitle-drag-chip')), findsNothing);
  });

  testWidgets('paused stays paused after moving it', (tester) async {
    final h = await _pump(tester, playing: false);
    final before = h.engine.lastPlayingCommand;
    final gesture = await tester.startGesture(tester.getCenter(_line));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(h.engine.lastPlayingCommand, before,
        reason: 'neither paused nor played by the drag');
    expect(h.c.read(settingsProvider).subtitleBottomMargin, 6 + 10);
  });

  testWidgets('it stays within the 0–40 % range', (tester) async {
    final h = await _pump(tester, playing: false);
    final gesture = await tester.startGesture(tester.getCenter(_line));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, -390));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(h.c.read(settingsProvider).subtitleBottomMargin, 40);
  });

  testWidgets('a short tap on the line toggles the controls', (tester) async {
    final h = await _pump(tester, playing: true);
    expect(h.c.read(controlsVisibleProvider), isFalse);
    await tester.tap(_line);
    await tester.pump();
    expect(h.c.read(controlsVisibleProvider), isTrue);
    await tester.pump(const Duration(seconds: 6)); // auto-hide timer
  });

  testWidgets('locked: the line cannot be picked up', (tester) async {
    final h = await _pump(tester, playing: true);
    h.c.read(lockProvider.notifier).lock();
    await tester.pump();
    final gesture = await tester.startGesture(tester.getCenter(_line));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, -80));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(h.c.read(settingsProvider).subtitleBottomMargin, 6);
  });
}
