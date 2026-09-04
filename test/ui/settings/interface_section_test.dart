import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/sections/interface_section.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

Future<ProviderContainer> _pump(WidgetTester t) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  await pumpLocalized(t, const InterfaceSettingsSection(), container: c, theme: KivoTheme.dark());
  await t.pump();
  return c;
}

void main() {
  testWidgets('aspect segmented persists defaultAspectMode', (t) async {
    final c = await _pump(t);
    await t.tap(find.text(_l10n.settingsInterfaceAspectFill));
    await t.pump();
    expect(c.read(settingsProvider).defaultAspectMode, 'fill');
  });

  testWidgets('info-overlay content/corner hide when the overlay is off', (t) async {
    final c = await _pump(t);
    // Default showInfoOverlay is true → the content choice is present.
    expect(find.text(_l10n.settingsInterfaceOverlayContent), findsOneWidget);
    // Turn the overlay off (its switch) → content/corner disappear.
    final showRow = find.ancestor(of: find.text(_l10n.settingsInterfaceShowOverlay), matching: find.byType(Row)).first;
    await t.tap(find.descendant(of: showRow, matching: find.byType(Switch)));
    await t.pump();
    expect(c.read(settingsProvider).showInfoOverlay, isFalse);
    expect(find.text(_l10n.settingsInterfaceOverlayContent), findsNothing);
  });

  testWidgets('choosing a content mode persists infoOverlayContent', (t) async {
    final c = await _pump(t);
    await t.tap(find.text(_l10n.settingsInterfaceOverlayContentNameOnly));
    await t.pump();
    expect(c.read(settingsProvider).infoOverlayContent, 'name');
  });

  testWidgets('columns segmented persists libraryColumns', (t) async {
    final c = await _pump(t);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await t.pump();
    await t.tap(find.text('2'));
    await t.pump();
    expect(c.read(settingsProvider).libraryColumns, 2);
  });
}
