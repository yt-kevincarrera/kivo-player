import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/sections/advanced_playback_section.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

Future<ProviderContainer> _pump(WidgetTester t,
    {KivoSettings Function(KivoSettings)? tweak}) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  if (tweak != null) await s.update(tweak(s.current));
  final c = ProviderContainer(
      overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  await t.binding.setSurfaceSize(const Size(420, 3000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await pumpLocalized(t, const AdvancedPlaybackSection(),
      container: c, theme: KivoTheme.dark());
  await t.pump();
  return c;
}

Finder _switchOf(String title) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
    matching: find.byType(Switch));

void main() {
  testWidgets('the strength choices only show while the feature is on',
      (t) async {
    await _pump(t);
    expect(find.text(_l10n.settingsNightModeLevel), findsNothing);
    expect(find.text(_l10n.settingsVoiceBoostLevel), findsNothing);
  });

  testWidgets('turning Modo noche on persists and reveals its strength',
      (t) async {
    final c = await _pump(t);
    await t.tap(_switchOf(_l10n.settingsNightMode));
    await t.pump();
    expect(c.read(settingsProvider).nightMode, isTrue);
    expect(find.text(_l10n.settingsNightModeLevel), findsOneWidget);
  });

  testWidgets('a strength pick persists', (t) async {
    final c = await _pump(t, tweak: (s) => s.copyWith(voiceBoost: true));
    await t.tap(find.text(_l10n.settingsLevelStrong));
    await t.pump();
    expect(c.read(settingsProvider).voiceBoostLevel, 'strong');
  });
}
