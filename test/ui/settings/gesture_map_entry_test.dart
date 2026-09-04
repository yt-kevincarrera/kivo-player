import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/pip_controller_provider.dart';
import 'package:kivo_player/ui/settings/sections/playback_gestures_section.dart';
import 'package:kivo_player/l10n/generated/app_localizations.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

void main() {
  testWidgets('the settings row opens the gesture map', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
        pipControllerProvider.overrideWithValue(FakePipController()),
      ],
      child: const MaterialApp(
        locale: Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PlaybackGesturesSection(),
      ),
    ));

    await tester.tap(find.text('Ver el mapa de gestos'));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.playerTutorialPageTaps.toUpperCase()), findsOneWidget);
  });
}
