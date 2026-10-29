import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log_provider.dart';
import 'package:kivo_player/core/navigation.dart';
import 'package:kivo_player/l10n/generated/app_localizations.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/ui/widgets/playback_failure_listener.dart';
import '../fakes/fakes.dart';

void main() {
  testWidgets('an asynchronous no-streams failure shows KV-501 and is logged',
      (tester) async {
    final engine = FakePlaybackEngine();
    final container = ProviderContainer(overrides: [
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(container.dispose);
    addTearDown(engine.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: kivoNavigatorKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('es'),
        builder: (context, child) => PlaybackFailureListener(child: child!),
        home: const Scaffold(body: Text('Player')),
      ),
    ));

    // Like libmpv's loadfile: the command succeeds, decoding fails later.
    await engine.open('/movies/sample.rm');
    engine.emitUnplayable('No video or audio streams selected.');
    await tester.pumpAndSettle();

    expect(find.textContaining('KV-501'), findsOneWidget);
    expect(container.read(errorLogProvider).entries().map((e) => e.detail),
        [contains('No video or audio streams selected.')]);
    expect(find.text('Player'), findsOneWidget);
  });
}
