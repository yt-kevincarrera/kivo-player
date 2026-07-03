import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/widgets/setting_tiles.dart';
import 'package:kivo_player/ui/settings/widgets/color_picker_sheet.dart';

void main() {
  testWidgets('SettingColor shows a swatch per preset and reports a preset tap', (t) async {
    int? got;
    await t.pumpWidget(MaterialApp(
      theme: KivoTheme.dark(),
      home: Scaffold(body: SettingColor(title: 'Acento', value: kAccentPresets.first, onChanged: (v) => got = v)),
    ));
    // one dot per preset + one "custom" dot
    expect(find.byKey(const ValueKey('accent-preset-1')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('accent-preset-1')));
    expect(got, kAccentPresets[1]);
  });

  testWidgets('the custom swatch opens the HSV sheet', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: KivoTheme.dark(),
      home: Scaffold(body: SettingColor(title: 'Acento', value: kAccentPresets.first, onChanged: (_) {})),
    ));
    await t.tap(find.byKey(const ValueKey('accent-custom')));
    await t.pumpAndSettle();
    expect(find.text('Personalizado'), findsOneWidget); // sheet header
    expect(find.text('Aplicar'), findsOneWidget);
  });
}
