import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/widgets/setting_tiles.dart';
import '../../helpers/pump_app.dart';

// setting_tiles.dart itself never resolves l10n (every string it shows is a
// plain parameter from its caller) — the "SettingSegmented" fixture below
// mirrors general_section.dart's real theme selector, so it draws from the
// same ARB keys rather than restating their Spanish text inline.
final _l10n = l10nFor(const Locale('es'));

Future<void> _host(WidgetTester t, Widget child) =>
    pumpLocalized(t, Scaffold(body: child), theme: KivoTheme.dark());

void main() {
  testWidgets('SettingNavRow shows title/subtitle and fires onTap', (t) async {
    var tapped = false;
    await _host(t, SettingNavRow(icon: Icons.tune, title: 'General', subtitle: 'Tema', onTap: () => tapped = true));
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Tema'), findsOneWidget);
    await t.tap(find.text('General'));
    expect(tapped, isTrue);
  });

  testWidgets('SettingSwitch reflects value and toggles', (t) async {
    bool? got;
    await _host(t, SettingSwitch(title: 'Háptica', value: true, onChanged: (v) => got = v));
    await t.tap(find.byType(Switch));
    expect(got, isFalse);
  });

  testWidgets('SettingSlider shows the formatted label and reports changes', (t) async {
    double? got;
    await _host(t, SettingSlider(
      title: 'Sensibilidad', value: 1.0, min: 0.5, max: 2.0, label: (v) => v.toStringAsFixed(1), onChanged: (v) => got = v));
    expect(find.text('1.0'), findsOneWidget);
    await t.drag(find.byType(Slider), const Offset(60, 0));
    expect(got, isNotNull);
    expect(got, greaterThan(1.0));
  });

  testWidgets('SettingStepper clamps at min/max and steps', (t) async {
    int? got;
    await _host(t, SettingStepper(
      title: 'Salto', value: 10, min: 5, max: 30, step: 5, label: (v) => '$v s', onChanged: (v) => got = v));
    expect(find.text('10 s'), findsOneWidget);
    await t.tap(find.text('+'));
    expect(got, 15);
  });

  testWidgets('SettingStepper disables + at max', (t) async {
    int? got;
    await _host(t, SettingStepper(
      title: 'Salto', value: 30, min: 5, max: 30, step: 5, label: (v) => '$v s', onChanged: (v) => got = v));
    await t.tap(find.text('+'));
    expect(got, isNull); // at max, no change
  });

  testWidgets('SettingSegmented highlights the active option and switches', (t) async {
    String? got;
    await _host(t, SettingSegmented<String>(
      title: _l10n.settingsGeneralTheme,
      options: [
        ('auto', _l10n.settingsGeneralThemeAuto),
        ('dark', _l10n.settingsGeneralThemeDark),
        ('light', _l10n.settingsGeneralThemeLight),
      ],
      value: 'dark',
      onChanged: (v) => got = v));
    expect(find.text(_l10n.settingsGeneralThemeDark), findsOneWidget);
    await t.tap(find.text(_l10n.settingsGeneralThemeLight));
    expect(got, 'light');
  });
}
