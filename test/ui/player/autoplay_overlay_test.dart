import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/autoplay/autoplay_overlay.dart';
import 'package:kivo_player/ui/player/state/autoplay_state.dart';
import '../../fakes/fakes.dart';

void main() {
  const pending = VideoSession(
    playbackPath: '/v/ep2.mkv',
    displayName: 'ep2.mkv',
    queue: ['/v/ep1.mkv', '/v/ep2.mkv'],
    queueNames: ['ep1.mkv', 'ep2.mkv'],
    index: 1,
  );

  Future<ProviderContainer> pumpOverlay(WidgetTester tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: AutoplayOverlay())),
    ));
    return c;
  }

  testWidgets('hidden when nothing pending', (tester) async {
    await pumpOverlay(tester);
    expect(find.text('PRÓXIMO'), findsNothing);
  });

  testWidgets('shows PRÓXIMO and the next video name when pending is set', (tester) async {
    final c = await pumpOverlay(tester);
    c.read(autoplayPendingProvider.notifier).state = pending;
    await tester.pump();

    expect(find.text('PRÓXIMO'), findsOneWidget);
    expect(find.text('ep2.mkv'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Cancelar clears the pending session', (tester) async {
    final c = await pumpOverlay(tester);
    c.read(autoplayPendingProvider.notifier).state = pending;
    await tester.pump();

    await tester.tap(find.text('Cancelar'));
    await tester.pump();

    expect(c.read(autoplayPendingProvider), isNull);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Reproducir sets autoplayConfirmProvider true', (tester) async {
    final c = await pumpOverlay(tester);
    c.read(autoplayPendingProvider.notifier).state = pending;
    await tester.pump();

    await tester.tap(find.text('Reproducir'));
    await tester.pump();

    expect(c.read(autoplayConfirmProvider), true);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('ring completing after 3s sets autoplayConfirmProvider true', (tester) async {
    final c = await pumpOverlay(tester);
    c.read(autoplayPendingProvider.notifier).state = pending;
    await tester.pump();

    await tester.pump(const Duration(seconds: 4));

    expect(c.read(autoplayConfirmProvider), true);
  });
}
