import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/television_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/ui/player/keys/player_keys.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<(ProviderContainer, FakePlaybackEngine)> setup(
    WidgetTester t, {
    bool tv = true,
  }) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final settings = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWithValue(settings),
        playbackEngineProvider.overrideWithValue(engine),
        isTelevisionProvider.overrideWithValue(tv),
      ],
    );
    addTearDown(c.dispose);
    await t.runAsync(() async {
      c.listen(positionProvider, (_, __) {});
      c.listen(durationProvider, (_, __) {});
      engine.emitPosition(const Duration(minutes: 1));
      engine.emitDuration(const Duration(minutes: 10));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await pumpLocalized(
      t,
      const PlayerKeys(child: Scaffold(body: SizedBox.expand())),
      container: c,
    );
    await t.pump();
    return (c, engine);
  }

  testWidgets(
    'TV tap seeks three seconds; OEM repeats do not duplicate hold ticks',
    (t) async {
      final (_, engine) = await setup(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      expect(engine.lastSeek, const Duration(seconds: 63));
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      expect(engine.lastSeek, const Duration(seconds: 63));
      await t.pump(const Duration(milliseconds: 650));
      expect(engine.lastSeek, const Duration(seconds: 69));
      await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await t.pump(const Duration(seconds: 5));
      expect(engine.lastSeek, const Duration(seconds: 69));
    },
  );

  testWidgets('changing focus or revealing controls stops a held TV seek', (
    t,
  ) async {
    final (c, engine) = await setup(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    expect(engine.lastSeek, const Duration(seconds: 57));
    c.read(controlsVisibleProvider.notifier).show();
    await t.pump(const Duration(seconds: 2));
    expect(engine.lastSeek, const Duration(seconds: 57));
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    c.read(controlsVisibleProvider.notifier).hide();
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('phone keyboard keeps the existing ten-second skip', (t) async {
    final (_, engine) = await setup(t, tv: false);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(engine.lastSeek, const Duration(seconds: 70));
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets(
    'rapid TV taps accumulate while the decoder reports the old position',
    (t) async {
      final (_, engine) = await setup(t);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(engine.lastSeek, const Duration(seconds: 66));
      await t.pump(const Duration(seconds: 2));
    },
  );

  testWidgets('suspending the TV stops seeking even if key-up never arrives', (
    t,
  ) async {
    final (_, engine) = await setup(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(const Duration(seconds: 3));
    expect(engine.lastSeek, const Duration(seconds: 63));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await t.pump(const Duration(seconds: 2));
    expect(engine.lastSeek, const Duration(seconds: 63));
  });
}
