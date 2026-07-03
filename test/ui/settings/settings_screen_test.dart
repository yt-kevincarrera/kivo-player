import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/settings_screen.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _pump(WidgetTester t) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: KivoTheme.dark(), home: const SettingsScreen()),
  ));
  return c;
}

void main() {
  testWidgets('root lists Acerca de and Restablecer', (t) async {
    await _pump(t);
    expect(find.text('Acerca de'), findsOneWidget);
    expect(find.text('Restablecer valores'), findsOneWidget);
  });

  testWidgets('tapping Acerca de navigates to the about screen', (t) async {
    await _pump(t);
    await t.tap(find.text('Acerca de'));
    await t.pumpAndSettle();
    expect(find.text('Kivo'), findsWidgets);
    expect(find.textContaining('1.0'), findsOneWidget);
  });

  testWidgets('reset asks for confirmation, then restores defaults', (t) async {
    final c = await _pump(t);
    // Put a non-default value.
    final n = c.read(settingsProvider.notifier);
    n.set(c.read(settingsProvider).copyWith(accentColor: 0xFF5B9BE8));
    await t.pump();
    await t.tap(find.text('Restablecer valores'));
    await t.pumpAndSettle();
    expect(find.text('Restablecer'), findsOneWidget); // dialog confirm button
    await t.tap(find.text('Restablecer').last);
    await t.pumpAndSettle();
    expect(c.read(settingsProvider).accentColor, KivoSettings.defaults().accentColor);
  });
}
