import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/sleep/sleep_timer.dart';
import 'package:kivo_player/ui/player/sleep/sleep_warning_toast.dart';
import '../../../fakes/fakes.dart';

void main() {
  late FakePlaybackEngine engine;
  late ProviderContainer c;

  Future<void> pumpToast(WidgetTester tester) async {
    engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: SleepWarningToast())),
    ));
  }

  // Drives the notifier into a warning state without waiting real minutes:
  // episode mode + position 8s from the end.
  Future<void> enterWarning(WidgetTester tester) async {
    c.read(sleepTimerProvider.notifier).startEpisode();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 9, seconds: 52));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('hidden with no timer; visible in warning with countdown', (tester) async {
    await pumpToast(tester);
    expect(find.textContaining('Pausando en'), findsNothing);
    await enterWarning(tester);
    expect(find.textContaining('Pausando en'), findsOneWidget);
    expect(find.text('Extender'), findsOneWidget);
    expect(find.text('Desactivar'), findsOneWidget);
  });

  testWidgets('Desactivar cancels the timer', (tester) async {
    await pumpToast(tester);
    await enterWarning(tester);
    await tester.tap(find.text('Desactivar'));
    await tester.pump();
    expect(c.read(sleepTimerProvider), isNull);
    expect(find.textContaining('Pausando en'), findsNothing);
  });

  testWidgets('Extender in episode mode cancels (keeps watching)', (tester) async {
    await pumpToast(tester);
    await enterWarning(tester);
    await tester.tap(find.text('Extender'));
    await tester.pump();
    expect(c.read(sleepTimerProvider), isNull);
  });

  testWidgets('close (✕) hides the toast but the timer keeps running', (tester) async {
    await pumpToast(tester);
    await enterWarning(tester);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.textContaining('Pausando en'), findsNothing);
    expect(c.read(sleepTimerProvider), isNotNull);
    expect(c.read(sleepTimerProvider)!.warning, true);
  });
}
