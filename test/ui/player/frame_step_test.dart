import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/ui/player/controls/center_controls.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

Future<FakePlaybackEngine> _pump(WidgetTester t, {required bool playing}) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
  ]);
  addTearDown(c.dispose);
  c.listen(playingProvider, (_, __) {});
  await pumpLocalized(t, const Scaffold(body: Center(child: CenterControls())),
      container: c, theme: KivoTheme.dark());
  await t.runAsync(() async {
    engine.emitPlaying(playing);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
  await t.pumpAndSettle();
  return engine;
}

double _opacity(WidgetTester t) => t
    .widget<AnimatedOpacity>(find.ancestor(
        of: find.byKey(const Key('frame-next')),
        matching: find.byType(AnimatedOpacity)))
    .opacity;

void main() {
  testWidgets('while playing the capsule is invisible and untouchable',
      (t) async {
    final engine = await _pump(t, playing: true);
    expect(_opacity(t), 0);
    await t.tap(find.byKey(const Key('frame-next')), warnIfMissed: false);
    expect(engine.frameSteps, isEmpty);
  });

  testWidgets('paused: a tap steps one frame either way', (t) async {
    final engine = await _pump(t, playing: false);
    expect(_opacity(t), 1);
    await t.tap(find.byKey(const Key('frame-next')));
    await t.tap(find.byKey(const Key('frame-prev')));
    expect(engine.frameSteps, [true, false]);
  });

  testWidgets('holding repeats until released', (t) async {
    final engine = await _pump(t, playing: false);
    final g = await t.startGesture(t.getCenter(find.byKey(const Key('frame-next'))));
    await t.pump(const Duration(milliseconds: 600)); // long press kicks in
    await t.pump(const Duration(milliseconds: 500)); // ~4 repeats
    await g.up();
    final steps = engine.frameSteps.length;
    expect(steps, greaterThanOrEqualTo(4));
    await t.pump(const Duration(seconds: 1));
    expect(engine.frameSteps.length, steps, reason: 'stops on release');
  });

  testWidgets('pausing does not move the play button', (t) async {
    final engine = await _pump(t, playing: true);
    final before = t.getCenter(find.byKey(const Key('kivo_play_pause')));
    await t.runAsync(() async {
      engine.emitPlaying(false);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await t.pumpAndSettle();
    expect(t.getCenter(find.byKey(const Key('kivo_play_pause'))), before);
  });
}
