import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/queue/queue_strip.dart';
import 'package:kivo_player/ui/player/state/queue_strip_state.dart';
import '../../fakes/fakes.dart';

const _session = VideoSession(
  playbackPath: 'content://A/b.mkv', displayName: 'b.mkv',
  queue: ['content://A/a.mkv', 'content://A/b.mkv', 'content://A/c.mkv'],
  queueNames: ['a.mkv', 'b.mkv', 'c.mkv'],
  queueIds: ['ida', 'idb', 'idc'],
  index: 1, folder: 'A',
);

Future<ProviderContainer> _pump(WidgetTester tester, {VideoSession session = _session}) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(session);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: KivoTheme.dark(),
      home: const Scaffold(body: SafeArea(child: Align(alignment: Alignment.bottomCenter, child: QueueStrip()))),
    ),
  ));
  await tester.pump();
  return c;
}

void main() {
  testWidgets('shows a card per queue item with the current highlighted; tap sets queueJumpProvider', (tester) async {
    final c = await _pump(tester);
    expect(find.text('AHORA'), findsOneWidget); // current (index 1)
    expect(find.text('a.mkv'), findsOneWidget);
    expect(find.text('c.mkv'), findsOneWidget);
    await tester.tap(find.text('c.mkv'));
    await tester.pump();
    expect(c.read(queueJumpProvider), 2);
    // The tap also starts the controls-auto-hide timer (controlsVisibleProvider.show());
    // let it fire so no pending Timer trips the widget-test-binding invariant check.
    await tester.pump(const Duration(milliseconds: 3000));
  });

  testWidgets('tapping the current card does nothing', (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.text('b.mkv'));
    await tester.pump();
    expect(c.read(queueJumpProvider), isNull);
  });

  testWidgets('hidden for a single-item queue', (tester) async {
    await _pump(tester, session: const VideoSession(
      playbackPath: '/v/solo.mkv', displayName: 'solo.mkv',
      queue: ['/v/solo.mkv'], queueNames: ['solo.mkv'], queueIds: ['id'], index: 0,
    ));
    expect(find.text('solo.mkv'), findsNothing);
  });
}
