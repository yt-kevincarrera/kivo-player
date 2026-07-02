import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/loop/ab_loop.dart';
import 'package:kivo_player/ui/player/loop/ab_range_layer.dart';
import 'package:kivo_player/ui/player/more/more_menu.dart';
import '../../../fakes/fakes.dart';

Future<(ProviderContainer, FakePlaybackEngine)> _setUp(WidgetTester tester, Widget child) async {
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
    child: MaterialApp(home: Scaffold(body: child)),
  ));
  await tester.pump();
  return (c, engine);
}

Future<void> _makeActiveLoop(WidgetTester tester, ProviderContainer c, FakePlaybackEngine engine) async {
  engine.emitDuration(const Duration(minutes: 10));
  c.read(abLoopProvider.notifier).begin();
  engine.emitPosition(const Duration(minutes: 2));
  await tester.pump();
  c.read(abLoopProvider.notifier).mark();
  engine.emitPosition(const Duration(minutes: 3));
  await tester.pump();
  c.read(abLoopProvider.notifier).mark();
  await tester.pump();
}

void main() {
  testWidgets('paints nothing without a loop, paints the range when active', (tester) async {
    final (c, engine) = await _setUp(tester, const SizedBox(width: 300, height: 48, child: AbRangeLayer()));
    expect(find.byKey(const ValueKey('ab-range-paint')), findsNothing);
    await _makeActiveLoop(tester, c, engine);
    expect(find.byKey(const ValueKey('ab-range-paint')), findsOneWidget);
  });

  testWidgets('menu row begins marking when no loop exists', (tester) async {
    final (c, _) = await _setUp(
      tester,
      Consumer(builder: (context, ref, _) => ElevatedButton(
        onPressed: () => showMoreMenu(context, ref),
        child: const Text('open'),
      )),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Bucle A-B'), findsOneWidget);
    expect(find.text('Repetir un fragmento del video'), findsOneWidget);
    await tester.tap(find.text('Bucle A-B'));
    await tester.pumpAndSettle();
    expect(c.read(abLoopProvider)!.phase, AbLoopPhase.armedA);
    // begin() also calls controlsVisibleProvider.show(), which starts an
    // auto-hide timer (controlsAutoHideMs = 3000ms default) — drain it so
    // the test doesn't leave a pending timer behind.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('menu row shows the active range and cancels on tap', (tester) async {
    late ProviderContainer c;
    late FakePlaybackEngine engine;
    (c, engine) = await _setUp(
      tester,
      Consumer(builder: (context, ref, _) => ElevatedButton(
        onPressed: () => showMoreMenu(context, ref),
        child: const Text('open'),
      )),
    );
    await _makeActiveLoop(tester, c, engine);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Activo · 02:00–03:00'), findsOneWidget);
    await tester.tap(find.text('Bucle A-B'));
    await tester.pumpAndSettle();
    expect(c.read(abLoopProvider), isNull);
  });
}
