import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/widgets/setting_tiles.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

void main() {
  testWidgets('SettingColor shows a swatch per preset and reports a preset tap', (t) async {
    int? got;
    await pumpLocalized(
      t,
      Scaffold(body: SettingColor(title: 'Acento', value: kAccentPresets.first, onChanged: (v) => got = v)),
      theme: KivoTheme.dark(),
    );
    // one dot per preset + one "custom" dot
    expect(find.byKey(const ValueKey('accent-preset-1')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('accent-preset-1')));
    expect(got, kAccentPresets[1]);
  });

  testWidgets('the custom swatch opens the HSV sheet', (t) async {
    await pumpLocalized(
      t,
      Scaffold(body: SettingColor(title: 'Acento', value: kAccentPresets.first, onChanged: (_) {})),
      theme: KivoTheme.dark(),
    );
    await t.tap(find.byKey(const ValueKey('accent-custom')));
    await t.pumpAndSettle();
    expect(find.text(_l10n.settingsColorPickerTitle), findsOneWidget); // sheet header
    expect(find.text(_l10n.settingsColorPickerApplyAction), findsOneWidget);
  });
}
