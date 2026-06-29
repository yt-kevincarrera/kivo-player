import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/ui/player/state/hud_state.dart';
import 'package:kivo_player/ui/player/hud/hud_overlay.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('HudOverlay shows label when HUD active, nothing when null', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: HudOverlay())),
    ));
    expect(find.text('80%'), findsNothing);

    c.read(hudProvider.notifier).show(HudKind.volume, 0.8, '80%');
    await tester.pump();
    expect(find.text('80%'), findsOneWidget);

    // drain the 800 ms auto-clear timer so no pending timers remain
    await tester.pump(const Duration(milliseconds: 801));
  });

  testWidgets('HudOverlay renders brightness HUD with label', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: HudOverlay())),
    ));
    expect(find.text('30%'), findsNothing);

    c.read(hudProvider.notifier).show(HudKind.brightness, 0.3, '30%');
    await tester.pump();
    expect(find.text('30%'), findsOneWidget);

    // drain the 800 ms auto-clear timer so no pending timers remain
    await tester.pump(const Duration(milliseconds: 801));
  });
}
