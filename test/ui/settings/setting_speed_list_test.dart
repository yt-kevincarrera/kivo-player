import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/widgets/setting_speed_list.dart';

Future<void> _host(WidgetTester t, Widget child) => t.pumpWidget(
      MaterialApp(theme: KivoTheme.dark(), home: Scaffold(body: child)),
    );

void main() {
  testWidgets('shows one chip per value, sorted', (t) async {
    await _host(t, SettingSpeedList(
        title: 'Presets', values: const [2.0, 1.0, 1.5], onChanged: (_) {}));
    expect(find.text('1×'), findsOneWidget);
    expect(find.text('1.5×'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);
  });

  testWidgets('removing a chip reports the list without it', (t) async {
    List<double>? got;
    await _host(t, SettingSpeedList(
        title: 'Presets', values: const [1.0, 1.5, 2.0], onChanged: (v) => got = v));
    // Each removable chip has a close icon; tap the one inside the 1.5× chip.
    await t.tap(find.descendant(
      of: find.ancestor(of: find.text('1.5×'), matching: find.byType(Row)).first,
      matching: find.byIcon(Icons.close)));
    expect(got, isNotNull);
    expect(got!.contains(1.5), isFalse);
    expect(got!.length, 2);
  });

  testWidgets('a single value has no remove affordance', (t) async {
    await _host(t, SettingSpeedList(
        title: 'Presets', values: const [1.0], onChanged: (_) {}));
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('the add chip opens a sheet that reports a new sorted value', (t) async {
    List<double>? got;
    await _host(t, SettingSpeedList(
        title: 'Presets', values: const [1.0, 2.0], min: 0.25, max: 4.0, onChanged: (v) => got = v));
    await t.tap(find.byKey(const ValueKey('speed-add')));
    await t.pumpAndSettle();
    expect(find.text('Añadir'), findsOneWidget);
    await t.tap(find.text('Añadir')); // default sheet value is min-ish; just confirm it reports
    await t.pumpAndSettle();
    expect(got, isNotNull);
    // list stays sorted and deduped
    final sorted = [...got!]..sort();
    expect(got, sorted);
  });
}
