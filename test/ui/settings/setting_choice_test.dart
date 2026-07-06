import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/widgets/setting_choice.dart';

Future<void> _host(WidgetTester t, Widget child) => t.pumpWidget(
    MaterialApp(theme: KivoTheme.dark(), home: Scaffold(body: child)));

void main() {
  testWidgets('shows a row per option; selected has the checked radio', (t) async {
    await _host(t, SettingChoice<String>(
        title: 'Contenido', value: 'name',
        options: const [('name_time', 'Nombre y tiempo'), ('name', 'Solo nombre'), ('remaining', 'Tiempo restante')],
        onChanged: (_) {}));
    expect(find.text('Nombre y tiempo'), findsOneWidget);
    expect(find.text('Solo nombre'), findsOneWidget);
    expect(find.text('Tiempo restante'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget); // exactly the selected
  });

  testWidgets('tapping another option reports its value', (t) async {
    String? got;
    await _host(t, SettingChoice<String>(
        title: 'Contenido', value: 'name',
        options: const [('name_time', 'Nombre y tiempo'), ('name', 'Solo nombre'), ('remaining', 'Tiempo restante')],
        onChanged: (v) => got = v));
    await t.tap(find.text('Tiempo restante'));
    expect(got, 'remaining');
  });
}
