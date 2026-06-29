import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/ui/player/controls/center_controls.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('play/pause button toggles engine playing', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: Center(child: CenterControls()))),
    ));

    // Emit playing=true, then let the stream propagate to the widget
    engine.emitPlaying(true);
    await tester.pump(); // process the stream event + rebuild

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    expect(engine.lastPlayingCommand, false); // pause() was called
  }, timeout: const Timeout(Duration(seconds: 30)));
}