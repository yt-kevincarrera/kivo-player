import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/widgets/setting_choice.dart';
import '../../helpers/pump_app.dart';

// SettingChoice itself never resolves l10n (it takes title/options as plain
// strings from its caller) — the real interface_section.dart's info-overlay
// content choice is the reason this fixture mirrors those exact three
// options, so it is built from the same ARB keys rather than restating
// their Spanish text inline.
final _l10n = l10nFor(const Locale('es'));

Future<void> _host(WidgetTester t, Widget child) =>
    pumpLocalized(t, Scaffold(body: child), theme: KivoTheme.dark());

void main() {
  testWidgets('shows a row per option; selected has the checked radio', (t) async {
    await _host(t, SettingChoice<String>(
        title: _l10n.settingsInterfaceOverlayContent, value: 'name',
        options: [
          ('name_time', _l10n.settingsInterfaceOverlayContentNameTime),
          ('name', _l10n.settingsInterfaceOverlayContentNameOnly),
          ('remaining', _l10n.settingsInterfaceOverlayContentRemaining),
        ],
        onChanged: (_) {}));
    expect(find.text(_l10n.settingsInterfaceOverlayContentNameTime), findsOneWidget);
    expect(find.text(_l10n.settingsInterfaceOverlayContentNameOnly), findsOneWidget);
    expect(find.text(_l10n.settingsInterfaceOverlayContentRemaining), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget); // exactly the selected
  });

  testWidgets('tapping another option reports its value', (t) async {
    String? got;
    await _host(t, SettingChoice<String>(
        title: _l10n.settingsInterfaceOverlayContent, value: 'name',
        options: [
          ('name_time', _l10n.settingsInterfaceOverlayContentNameTime),
          ('name', _l10n.settingsInterfaceOverlayContentNameOnly),
          ('remaining', _l10n.settingsInterfaceOverlayContentRemaining),
        ],
        onChanged: (v) => got = v));
    await t.tap(find.text(_l10n.settingsInterfaceOverlayContentRemaining));
    expect(got, 'remaining');
  });
}
