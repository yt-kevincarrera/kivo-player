import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/ui/settings/settings_screen.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _c(bool hidden) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  await svc.update(svc.current.copyWith(vaultEntranceHidden: hidden));
  return ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(svc)]);
}

void main() {
  testWidgets('Vault row visible when entrance not hidden', (tester) async {
    final c = await _c(false);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const MaterialApp(home: SettingsScreen())));
    await tester.pump();
    expect(find.text('Vault'), findsOneWidget);
  });

  testWidgets('Vault row hidden when entrance hidden', (tester) async {
    final c = await _c(true);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const MaterialApp(home: SettingsScreen())));
    await tester.pump();
    expect(find.text('Vault'), findsNothing);
  });
}
