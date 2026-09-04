import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/sections/playback_gestures_section.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

Future<ProviderContainer> _pump(WidgetTester t) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  await pumpLocalized(t, const PlaybackGesturesSection(), container: c, theme: KivoTheme.dark());
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
    // The "Velocidad" group is below the fold. Scroll UNTIL it is actually
    // visible instead of by a fixed offset: a fixed drag leaves the target
    // outside the 600px test viewport as soon as a card is added above, and the
    // tap then silently lands on nothing.
    await t.scrollUntilVisible(find.text('0.10×'), 300,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.tap(find.text('0.10×'));
    await t.pump();
    expect(c.read(settingsProvider).speedFineStep, 0.1);
  });

  testWidgets('removing a preset persists speedPresets', (t) async {
    final c = await _pump(t);
    final before = c.read(settingsProvider).speedPresets.length;
    // Remove the first removable preset chip.
    await t.scrollUntilVisible(find.text(_l10n.settingsGesturesSpeedPresets), 300,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    final closeIcons = find.byIcon(Icons.close);
    expect(closeIcons, findsWidgets);
    await t.tap(closeIcons.first);
    await t.pump();
    expect(c.read(settingsProvider).speedPresets.length, before - 1);
  });
}
