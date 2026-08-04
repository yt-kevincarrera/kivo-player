import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/pip_controller_provider.dart';
import 'package:kivo_player/ui/settings/sections/playback_gestures_section.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('the settings row opens the gesture map', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
        pipControllerProvider.overrideWithValue(FakePipController()),
      ],
      child: const MaterialApp(home: PlaybackGesturesSection()),
    ));

    await tester.tap(find.text('Ver el mapa de gestos'));
    await tester.pumpAndSettle();
    expect(find.text('TOQUES'), findsOneWidget);
  });
}
