import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/sections/advanced_playback_section.dart';
import 'package:kivo_player/ui/settings/widgets/setting_choice.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _pump(WidgetTester t, {String? subLang}) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  if (subLang != null) await s.update(s.current.copyWith(preferredSubtitleLanguage: subLang));
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: KivoTheme.dark(), home: const AdvancedPlaybackSection()),
  ));
  await t.pump();
  return c;
}

void main() {
  testWidgets('resume behavior choice persists', (t) async {
    final c = await _pump(t);
    await t.tap(find.text('Desactivado'));
    await t.pump();
    expect(c.read(settingsProvider).resumeBehavior, 'off');
  });

  testWidgets('toggling PiP-auto persists pipAutoOnHome', (t) async {
    final c = await _pump(t);
    final before = c.read(settingsProvider).pipAutoOnHome;
    final pipRow = find.ancestor(
        of: find.text('Miniatura flotante (PiP) al salir al inicio'),
        matching: find.byType(Row)).first;
    await t.tap(find.descendant(of: pipRow, matching: find.byType(Switch)));
    await t.pump();
    expect(c.read(settingsProvider).pipAutoOnHome, !before);
  });

  testWidgets('resetting subtitle language to Automático clears it', (t) async {
    final c = await _pump(t, subLang: 'en');
    expect(c.read(settingsProvider).preferredSubtitleLanguage, 'en');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await t.pump();
    final subtitleRow = find.ancestor(
        of: find.text('Idioma de subtítulos preferido'),
        matching: find.byType(SettingChoice<String?>));
    await t.tap(find.descendant(of: subtitleRow, matching: find.text('Automático')));
    await t.pump();
    expect(c.read(settingsProvider).preferredSubtitleLanguage, isNull);
  });
}
