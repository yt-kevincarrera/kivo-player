import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/pip_controller_provider.dart';
import 'package:kivo_player/l10n/generated/app_localizations.dart';
import 'package:kivo_player/ui/player/tutorial/gesture_map_route.dart';
import '../../../fakes/fakes.dart';
import '../../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

void main() {
  testWidgets('pages through the map and Entendido closes it', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    var popped = false;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
        pipControllerProvider.overrideWithValue(FakePipController()),
      ],
      child: MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              await Navigator.of(context).push(gestureMapRoute());
              popped = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Page 1.
    expect(find.text(_l10n.playerTutorialPageTaps.toUpperCase()), findsOneWidget);
    expect(find.textContaining(_l10n.playerTutorialDoubleTapBack(10)), findsOneWidget);

    await tester.tap(find.text(_l10n.playerTutorialNextAction));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.playerTutorialPageDrags.toUpperCase()), findsOneWidget);

    await tester.tap(find.text(_l10n.playerTutorialNextAction));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.playerTutorialPageButtons.toUpperCase()), findsOneWidget);

    // Last page closes.
    await tester.tap(find.text(_l10n.playerTutorialDoneAction));
    await tester.pumpAndSettle();
    expect(popped, true);
    expect(find.text(_l10n.playerTutorialPageButtons.toUpperCase()), findsNothing);
  });
}
