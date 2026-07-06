import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/widgets/setting_corner_picker.dart';

Future<void> _host(WidgetTester t, Widget child) => t.pumpWidget(
    MaterialApp(theme: KivoTheme.dark(), home: Scaffold(body: child)));

void main() {
  testWidgets('has four corners; tapping one reports its code', (t) async {
    String? got;
    await _host(t, SettingCornerPicker(title: 'Esquina', value: 'tl', onChanged: (v) => got = v));
    for (final c in ['tl', 'tr', 'bl', 'br']) {
      expect(find.byKey(ValueKey('corner-$c')), findsOneWidget);
    }
    await t.tap(find.byKey(const ValueKey('corner-br')));
    expect(got, 'br');
  });
}
