import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/sections/general_section.dart';
import 'package:kivo_player/ui/settings/widgets/setting_tiles.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _pump(WidgetTester t) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: KivoTheme.dark(), home: const GeneralSettingsSection()),
  ));
  return c;
}

void main() {
  testWidgets('changing the theme segment persists themeMode', (t) async {
    final c = await _pump(t);
    await t.tap(find.text('Claro'));
    await t.pump();
    expect(c.read(settingsProvider).themeMode, 'light');
  });

  testWidgets('toggling haptics persists hapticsOnGestures', (t) async {
    final c = await _pump(t);
    final before = c.read(settingsProvider).hapticsOnGestures;
    await t.tap(find.byType(Switch));
    await t.pump();
    expect(c.read(settingsProvider).hapticsOnGestures, !before);
  });

  testWidgets('choosing an accent preset persists accentColor', (t) async {
    final c = await _pump(t);
    await t.tap(find.byKey(const ValueKey('accent-preset-1')));
    await t.pump();
    expect(c.read(settingsProvider).accentColor, kAccentPresets[1]);
  });
}
