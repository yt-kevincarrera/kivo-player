import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/ui/player/controls/center_controls.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('skip-seconds label is white (not the accent)', (t) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(accentColor: 0xFF2D6CFF, centerSkipSeconds: 10));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: KivoTheme.dark(accent: const Color(0xFF2D6CFF)),
        home: const Scaffold(body: Center(child: CenterControls())),
      ),
    ));
    await t.pump();
    final label = t.widget<Text>(find.text('10s').first);
    expect(label.style!.color, Colors.white);
    expect(label.style!.shadows, isNotNull); // has a legibility shadow
  });
}
