import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/widgets/segmented_progress.dart';
import 'package:kivo_player/ui/player/queue/queue_strip.dart';
import 'package:kivo_player/ui/player/state/queue_strip_state.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

const _session = VideoSession(
  playbackPath: 'content://A/b.mkv', displayName: 'b.mkv',
  queue: ['content://A/a.mkv', 'content://A/b.mkv', 'content://A/c.mkv'],
  queueNames: ['a.mkv', 'b.mkv', 'c.mkv'],
  queueIds: ['ida', 'idb', 'idc'],
  index: 1, folder: 'A',
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  VideoSession session = _session,
  InMemoryResumeStore? resume,
  InMemoryPlayedStore? played,
}) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
    resumeServiceProvider
        .overrideWithValue(ResumeService(resume ?? InMemoryResumeStore())),
    playedStoreProvider.overrideWithValue(played ?? InMemoryPlayedStore()),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(session);
  await pumpLocalized(
    tester,
    const Scaffold(body: SafeArea(child: Align(alignment: Alignment.bottomCenter, child: QueueStrip()))),
    container: c,
    theme: KivoTheme.dark(),
  );
  await tester.pump();
  return c;
}

void main() {
  testWidgets('shows a card per queue item with the current highlighted; tap sets queueJumpProvider', (tester) async {
    final c = await _pump(tester);
    expect(find.text(_l10n.playerQueueNowBadge), findsOneWidget); // current (index 1)
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

  testWidgets('with a shuffle order the strip follows it; taps map back to the real index',
      (tester) async {
    // Permutation puts the current video (index 1) first, then 2, then 0 —
    // the strip must lay the cards out in THAT order, and tapping a card
    // must jump to the card's real queue index, not its position.
    final c = await _pump(tester, session: const VideoSession(
      playbackPath: 'content://A/b.mkv', displayName: 'b.mkv',
      queue: ['content://A/a.mkv', 'content://A/b.mkv', 'content://A/c.mkv'],
      queueNames: ['a.mkv', 'b.mkv', 'c.mkv'],
      queueIds: ['ida', 'idb', 'idc'],
      index: 1, folder: 'A',
      order: [1, 2, 0],
    ));
    final xb = tester.getTopLeft(find.text('b.mkv')).dx;
    final xc = tester.getTopLeft(find.text('c.mkv')).dx;
    final xa = tester.getTopLeft(find.text('a.mkv')).dx;
    expect(xb < xc && xc < xa, isTrue, reason: 'cards should read b, c, a');
    expect(find.text(_l10n.playerQueueNowBadge), findsOneWidget);

    await tester.tap(find.text('a.mkv'));
    await tester.pump();
    expect(c.read(queueJumpProvider), 0);
    await tester.pump(const Duration(milliseconds: 3000));
  });

  /// Long-press [finder], optionally drag by [by], release. Leaves time for
  /// the drop animation and any menu to settle.
  Future<void> holdAndDrop(WidgetTester tester, Finder finder,
      {Offset by = Offset.zero}) async {
    final g = await tester.startGesture(tester.getCenter(finder));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    if (by != Offset.zero) {
      // In small steps, like a finger — the list reorders as it passes cards.
      for (var i = 0; i < 10; i++) {
        await g.moveBy(by / 10);
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  group('editing', () {
    // Every hold ends with the controls auto-hide timer restarted; let it
    // run out so no Timer outlives the test.
    Future<void> settleControls(WidgetTester tester) =>
        tester.pump(const Duration(seconds: 4));

    testWidgets('long-press and drag moves a card in the play order',
        (tester) async {
      final c = await _pump(tester);
      // a (index 0) past b and c — the strip is in landscape in tests (112 px per card).
      await holdAndDrop(tester, find.text('a.mkv'), by: const Offset(260, 0));
      expect(c.read(currentVideoProvider)!.playOrder, [1, 2, 0]);
      final xb = tester.getTopLeft(find.text('b.mkv')).dx;
      final xa = tester.getTopLeft(find.text('a.mkv')).dx;
      expect(xa > xb, isTrue);
      await settleControls(tester);
    });

    testWidgets('long-press and release opens the menu; "Reproducir a continuación"',
        (tester) async {
      final c = await _pump(tester);
      await holdAndDrop(tester, find.text('a.mkv'));
      expect(find.text(_l10n.playerQueuePlayNext), findsOneWidget);
      expect(find.text(_l10n.playerQueueRemove), findsOneWidget);
      await tester.tap(find.text(_l10n.playerQueuePlayNext));
      await tester.pumpAndSettle();
      expect(c.read(currentVideoProvider)!.playOrder, [1, 0, 2]);
      expect(find.text(_l10n.playerQueuePlayNext), findsNothing);
      await settleControls(tester);
    });

    testWidgets('the card already next offers only "Quitar de la cola"',
        (tester) async {
      await _pump(tester);
      await holdAndDrop(tester, find.text('c.mkv'));
      expect(find.text(_l10n.playerQueuePlayNext), findsNothing);
      expect(find.text(_l10n.playerQueueRemove), findsOneWidget);
    });

    testWidgets('"Quitar de la cola" takes the card out of the strip',
        (tester) async {
      final c = await _pump(tester, session: const VideoSession(
        playbackPath: 'content://A/b.mkv', displayName: 'b.mkv',
        queue: ['content://A/a.mkv', 'content://A/b.mkv', 'content://A/c.mkv', 'content://A/d.mkv'],
        queueNames: ['a.mkv', 'b.mkv', 'c.mkv', 'd.mkv'],
        queueIds: ['ida', 'idb', 'idc', 'idd'],
        index: 1, folder: 'A',
      ));
      await holdAndDrop(tester, find.text('a.mkv'));
      await tester.tap(find.text(_l10n.playerQueueRemove));
      await tester.pumpAndSettle();
      expect(c.read(currentVideoProvider)!.playOrder, [1, 2, 3]);
      expect(find.text('a.mkv'), findsNothing);
      await settleControls(tester);
    });

    testWidgets('the current card has no menu', (tester) async {
      await _pump(tester);
      await holdAndDrop(tester, find.text('b.mkv'));
      expect(find.text(_l10n.playerQueueRemove), findsNothing);
      await settleControls(tester);
    });

    testWidgets('tapping outside closes the menu without changes', (tester) async {
      final c = await _pump(tester);
      await holdAndDrop(tester, find.text('a.mkv'));
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.playerQueueRemove), findsNothing);
      expect(c.read(currentVideoProvider)!.order, isNull);
      await settleControls(tester);
    });

    testWidgets('the same video twice in a playlist does not break the strip',
        (tester) async {
      await _pump(tester, session: const VideoSession(
        playbackPath: 'content://A/x.mkv', displayName: 'x.mkv',
        queue: ['content://A/x.mkv', 'content://A/b.mkv', 'content://A/x.mkv'],
        queueNames: ['x.mkv', 'b.mkv', 'x.mkv'],
        queueIds: ['idx', 'idb', 'idx'],
        index: 0,
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('x.mkv'), findsNWidgets(2));
    });

    testWidgets('hidden once only the current video is left', (tester) async {
      final c = await _pump(tester);
      final n = c.read(currentVideoProvider.notifier);
      n.remove(0);
      n.remove(2);
      await tester.pump();
      expect(find.text('b.mkv'), findsNothing);
    });
  });

  testWidgets('a video in progress shows its progress; a played one a check',
      (tester) async {
    final resume = InMemoryResumeStore();
    await resume.put('a.mkv', 30, 0);
    final played = InMemoryPlayedStore();
    await played.markPlayed('a.mkv');
    await played.markPlayed('c.mkv');
    await _pump(tester, resume: resume, played: played, session: const VideoSession(
      playbackPath: 'content://A/b.mkv', displayName: 'b.mkv',
      queue: ['content://A/a.mkv', 'content://A/b.mkv', 'content://A/c.mkv'],
      queueNames: ['a.mkv', 'b.mkv', 'c.mkv'],
      queueIds: ['ida', 'idb', 'idc'],
      queueDurationsMs: [60000, 60000, 60000],
      index: 1, folder: 'A',
    ));
    expect(find.byType(SegmentedProgress), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
