import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/ui/player/controls/seek_bar.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('dragging the seek bar keeps controls visible', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);

    // Seed duration so the slider has a non-zero range.
    await tester.runAsync(() async {
      c.listen(positionProvider, (_, __) {});
      c.listen(durationProvider, (_, __) {});
      engine.emitDuration(const Duration(minutes: 10));
      engine.emitPosition(const Duration(minutes: 1));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: Center(child: SeekBar()))),
    ));
    await tester.pump();

    // Show controls so they start visible.
    c.read(controlsVisibleProvider.notifier).show();
    expect(c.read(controlsVisibleProvider), true);

    // Drag the slider — each onChanged tick should call .show() and keep controls alive.
    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(20, 0));
    await tester.pump();

    expect(c.read(controlsVisibleProvider), true);

    // Drain auto-hide timer.
    await tester.pump(const Duration(seconds: 4));
  });
}
