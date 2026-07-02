import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/sleep/sleep_timer.dart';
import 'package:kivo_player/ui/player/more/more_menu.dart';
import 'package:kivo_player/ui/player/sleep/sleep_timer_panel.dart';
import '../../../fakes/fakes.dart';

Future<ProviderContainer> _pump(WidgetTester tester, {required bool viaMenu}) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
  ]);
  addTearDown(c.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: KivoTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => viaMenu ? showMoreMenu(context, ref) : showSleepTimerPanel(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('more menu shows the timer entry and navigates to the panel', (tester) async {
    await _pump(tester, viaMenu: true);
    expect(find.text('Temporizador de apagado'), findsOneWidget);
    await tester.tap(find.text('Temporizador de apagado'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Iniciar ·'), findsOneWidget);
  });

  testWidgets('the panel back arrow returns to the more menu', (tester) async {
    await _pump(tester, viaMenu: true);
    await tester.tap(find.text('Temporizador de apagado'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Iniciar ·'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    // Back in the menu: the timer entry row is visible again, the panel is gone.
    expect(find.text('Detener la reproducción automáticamente'), findsOneWidget);
    expect(find.textContaining('Iniciar ·'), findsNothing);
  });

  testWidgets('opened directly (no onBack) the panel shows no back arrow', (tester) async {
    await _pump(tester, viaMenu: false);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
  });

  testWidgets('stepper adjusts minutes and the start button label follows', (tester) async {
    await _pump(tester, viaMenu: false);
    expect(find.text('Iniciar · 30 min'), findsOneWidget); // default from settings
    await tester.tap(find.text('+'));
    await tester.pump();
    expect(find.text('Iniciar · 35 min'), findsOneWidget);
  });

  testWidgets('starting a fixed timer activates the provider and persists the minutes', (tester) async {
    final c = await _pump(tester, viaMenu: false);
    await tester.tap(find.text('+')); // 35
    await tester.pump();
    await tester.tap(find.text('Iniciar · 35 min'));
    await tester.pumpAndSettle();
    final st = c.read(sleepTimerProvider);
    expect(st, isNotNull);
    expect(st!.mode, SleepTimerMode.fixed);
    expect(st.original, const Duration(minutes: 35));
    expect(c.read(settingsProvider).sleepTimerLastMinutes, 35);
    c.read(sleepTimerProvider.notifier).cancel(); // clean up the real ticker
  });

  testWidgets('episode card selects episode mode and starts it', (tester) async {
    final c = await _pump(tester, viaMenu: false);
    await tester.tap(find.text('Al terminar el episodio'));
    await tester.pump();
    await tester.tap(find.text('Iniciar · Al terminar el episodio'));
    await tester.pumpAndSettle();
    expect(c.read(sleepTimerProvider)!.mode, SleepTimerMode.episode);
  });

  testWidgets('active view shows countdown and Desactivar cancels', (tester) async {
    final c = await _pump(tester, viaMenu: false);
    c.read(sleepTimerProvider.notifier).startFixed(const Duration(minutes: 30));
    await tester.pump();
    expect(find.textContaining('restante'), findsOneWidget);
    await tester.tap(find.text('Desactivar'));
    await tester.pump();
    expect(c.read(sleepTimerProvider), isNull);
  });
}
