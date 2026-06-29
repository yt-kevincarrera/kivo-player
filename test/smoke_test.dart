import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/ui/home/open_screen.dart';
import 'fakes/fakes.dart';

void main() {
  testWidgets('OpenScreen renders without crashing', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWithValue(s)],
        child: const MaterialApp(home: OpenScreen()),
      ),
    );
    expect(find.byType(OpenScreen), findsOneWidget);
  });
}
