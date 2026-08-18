import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/ui/player/state/zoom_state.dart';
import 'package:kivo_player/ui/player/zoom/zoom_chip.dart';
import '../../../fakes/fakes.dart';

void main() {
  const viewport = Size(400, 800);
  const centre = Offset(200, 400);

  Future<ProviderContainer> harness(WidgetTester tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(body: Stack(children: [Positioned.fill(child: ZoomChip())])),
      ),
    ));
    return c;
  }

  testWidgets('hidden at 1x', (tester) async {
    await harness(tester);
    expect(find.textContaining('×'), findsNothing);
  });

  testWidgets('shows the factor once zoomed and restores on tap', (tester) async {
    final c = await harness(tester);
    c.read(zoomProvider.notifier).pinch(factor: 1.8, focal: centre, viewport: viewport);
    await tester.pumpAndSettle();

    expect(find.text('1.8×'), findsOneWidget);

    await tester.tap(find.text('1.8×'));
    await tester.pumpAndSettle();

    expect(c.read(zoomProvider).active, false);
    expect(find.textContaining('×'), findsNothing);
  });

  testWidgets('the factor tracks the zoom live', (tester) async {
    final c = await harness(tester);
    c.read(zoomProvider.notifier).pinch(factor: 2.0, focal: centre, viewport: viewport);
    await tester.pumpAndSettle();
    expect(find.text('2.0×'), findsOneWidget);

    c.read(zoomProvider.notifier).pinch(factor: 1.5, focal: centre, viewport: viewport);
    await tester.pumpAndSettle();
    expect(find.text('3.0×'), findsOneWidget);
    expect(find.text('2.0×'), findsNothing);
  });
}
