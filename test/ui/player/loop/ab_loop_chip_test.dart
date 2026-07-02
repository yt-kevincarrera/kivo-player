import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/loop/ab_loop.dart';
import 'package:kivo_player/ui/player/loop/ab_loop_chip.dart';
import '../../../fakes/fakes.dart';

void main() {
  late FakePlaybackEngine engine;
  late ProviderContainer c;

  Future<void> pumpChip(WidgetTester tester) async {
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
      child: const MaterialApp(
        home: Scaffold(body: Align(alignment: Alignment.bottomRight, child: AbLoopChip())),
      ),
    ));
    await tester.pump();
  }

  testWidgets('hidden without loop; cycles Marcar A → Marcar B → range on taps', (tester) async {
    await pumpChip(tester);
    expect(find.text('Marcar A'), findsNothing);

    c.read(abLoopProvider.notifier).begin();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 2));
    await tester.pump();
    expect(find.text('Marcar A'), findsOneWidget);

    await tester.tap(find.text('Marcar A'));
    await tester.pump();
    expect(find.text('Marcar B'), findsOneWidget);

    engine.emitPosition(const Duration(minutes: 3));
    await tester.pump();
    await tester.tap(find.text('Marcar B'));
    await tester.pump();
    expect(find.textContaining('–'), findsOneWidget); // "02:00–03:00"

    // Tap once more: loop off, chip gone.
    await tester.tap(find.textContaining('–'));
    await tester.pump();
    expect(c.read(abLoopProvider), isNull);
    expect(find.text('Marcar A'), findsNothing);
    expect(find.textContaining('–'), findsNothing);
  });

  testWidgets('long-press opens the popover and nudges adjust + seek', (tester) async {
    await pumpChip(tester);
    c.read(abLoopProvider.notifier).begin();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 2));
    await tester.pump();
    c.read(abLoopProvider.notifier).mark();
    engine.emitPosition(const Duration(minutes: 3));
    await tester.pump();
    c.read(abLoopProvider.notifier).mark();
    await tester.pump();

    await tester.longPress(find.textContaining('–'));
    await tester.pump();
    expect(find.text('−1s'), findsNWidgets(2));
    expect(find.text('+1s'), findsNWidgets(2));

    engine.lastSeek = null;
    // First "−1s" is A's.
    await tester.tap(find.text('−1s').first);
    await tester.pump();
    expect(c.read(abLoopProvider)!.a, const Duration(minutes: 1, seconds: 59));
    expect(engine.lastSeek, const Duration(minutes: 1, seconds: 59));
  });

  testWidgets('tapping the chip while the popover is open only closes the popover', (tester) async {
    await pumpChip(tester);
    c.read(abLoopProvider.notifier).begin();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 2));
    await tester.pump();
    c.read(abLoopProvider.notifier).mark();
    engine.emitPosition(const Duration(minutes: 3));
    await tester.pump();
    c.read(abLoopProvider.notifier).mark();
    await tester.pump();

    await tester.longPress(find.textContaining('–'));
    await tester.pump();
    expect(find.text('−1s'), findsNWidgets(2));
    await tester.tap(find.textContaining('–'));
    await tester.pump();
    expect(find.text('−1s'), findsNothing); // popover closed…
    expect(c.read(abLoopProvider), isNotNull); // …loop still on
  });
}
