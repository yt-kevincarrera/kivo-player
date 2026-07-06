import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/ui/player/speed/speed_panel.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('speed panel active rate readout uses the accent', (t) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(accentColor: 0xFF2D6CFF));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: KivoTheme.dark(accent: const Color(0xFF2D6CFF)),
        home: Builder(builder: (ctx) => Scaffold(
            body: Center(child: ElevatedButton(
                onPressed: () => showSpeedPanel(ctx), child: const Text('open'))))),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    // The current-rate readout (e.g. "1.00x") is painted with the accent.
    final readout = t.widget<Text>(find.textContaining('x').first);
    expect(readout.style?.color, const Color(0xFF2D6CFF));
    await t.pump(const Duration(seconds: 1));
  });
}
