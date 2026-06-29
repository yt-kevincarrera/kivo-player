import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/control/player_controller.dart';
import 'package:kivo_player/ui/player/speed/speed_panel.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('tapping the 2.0x preset chip sets the rate', (tester) async {
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
      child: const MaterialApp(home: Scaffold(body: SpeedPanel())),
    ));

    await tester.tap(find.text('2.0x'));
    await tester.pump();
    expect(engine.rate, 2.0);
    expect(c.read(rateProvider), 2.0);
  });
}
