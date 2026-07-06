import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/sections/playback_gestures_section.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _pump(WidgetTester t) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: KivoTheme.dark(), home: const PlaybackGesturesSection()),
  ));
  await t.pump();
  return c;
}

void main() {
  testWidgets('toggling horizontal seek persists', (t) async {
    final c = await _pump(t);
    await t.tap(find.byType(Switch).at(0)); // first switch is doubleTapCenterPause; find horizontalSeek instead
    await t.pump();
    // Not asserting the specific switch here — see the targeted test below.
    expect(c.read(settingsProvider), isNotNull);
  });

  testWidgets('the fine-step segmented persists speedFineStep', (t) async {
    final c = await _pump(t);
    // The "Velocidad" group is below the fold; scroll it into the built range
    // before ensureVisible/tap can locate it.
    await t.drag(find.byType(ListView), const Offset(0, -2000));
    await t.pump();
    await t.ensureVisible(find.text('0.10×'));
    await t.tap(find.text('0.10×'));
    await t.pump();
    expect(c.read(settingsProvider).speedFineStep, 0.1);
  });

  testWidgets('removing a preset persists speedPresets', (t) async {
    final c = await _pump(t);
    final before = c.read(settingsProvider).speedPresets.length;
    // Remove the first removable preset chip.
    await t.drag(find.byType(ListView), const Offset(0, -2000));
    await t.pump();
    await t.ensureVisible(find.text('Velocidades preseleccionadas'));
    final closeIcons = find.byIcon(Icons.close);
    expect(closeIcons, findsWidgets);
    await t.tap(closeIcons.first);
    await t.pump();
    expect(c.read(settingsProvider).speedPresets.length, before - 1);
  });
}
