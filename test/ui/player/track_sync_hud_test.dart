import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/track_delay.dart';
import 'package:kivo_player/player/tracks/track_delay_controller.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import 'package:kivo_player/ui/player/tracks/track_sync_hud.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _c(FakePlaybackEngine engine) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  return ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      playbackEngineProvider.overrideWithValue(engine),
      trackPrefsStoreProvider.overrideWithValue(InMemoryTrackPrefsStore()),
    ],
  );
}

Future<void> _pump(WidgetTester tester, ProviderContainer c) =>
    tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: TrackSyncHud())),
      ),
    );

void main() {
  testWidgets('stays out of the way until it is shown', (tester) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    await _pump(tester, c);
    expect(find.text('0,00 s'), findsNothing);
  });

  testWidgets('shows the offset and moves it a step per tap', (tester) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    c
        .read(currentVideoProvider.notifier)
        .open(
          const VideoSession(
            playbackPath: '/v/a.mkv',
            displayName: 'a.mkv',
            queue: ['/v/a.mkv'],
            index: 0,
          ),
        );
    await _pump(tester, c);

    c.read(syncHudProvider.notifier).show(SyncTarget.subtitles);
    await tester.pump();
    expect(find.text('0,00 s'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('subtitle-sync-plus')));
    await tester.pump();
    expect(find.text('+0,05 s'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('subtitle-sync-minus')));
    await tester.tap(find.byKey(const ValueKey('subtitle-sync-minus')));
    await tester.pump();
    expect(find.text('−0,05 s'), findsOneWidget);

    // Drain subtitleSyncProvider's trailing debounce (track_delay_controller.dart)
    // so its Timer isn't still pending when the widget tree tears down.
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('the reset button zeroes only the tab it is showing', (
    tester,
  ) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    c
        .read(currentVideoProvider.notifier)
        .open(
          const VideoSession(
            playbackPath: '/v/a.mkv',
            displayName: 'a.mkv',
            queue: ['/v/a.mkv'],
            index: 0,
          ),
        );
    await _pump(tester, c);
    c.read(syncHudProvider.notifier).show(SyncTarget.subtitles);
    await tester.pump();

    // Put a value on each side, then reset only the one on screen.
    await tester.tap(find.byKey(const ValueKey('subtitle-sync-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sync-target-audio')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('subtitle-sync-minus')));
    await tester.pump();
    expect(c.read(subtitleSyncProvider), 50);
    expect(c.read(audioSyncProvider), -50);

    await tester.tap(find.byKey(const ValueKey('sync-reset')));
    await tester.pump();

    expect(find.text('0,00 s'), findsOneWidget);
    expect(c.read(audioSyncProvider), 0);
    // The subtitle side is untouched — that is the point of a per-tab reset.
    expect(c.read(subtitleSyncProvider), 50);

    // Drain the trailing debounce (track_delay_controller.dart) so its Timer
    // isn't still pending when the widget tree tears down.
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('dragging the bar sets the offset without touching the buttons', (
    tester,
  ) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    c
        .read(currentVideoProvider.notifier)
        .open(
          const VideoSession(
            playbackPath: '/v/a.mkv',
            displayName: 'a.mkv',
            queue: ['/v/a.mkv'],
            index: 0,
          ),
        );
    await _pump(tester, c);
    c.read(syncHudProvider.notifier).show(SyncTarget.subtitles);
    await tester.pump();

    final bar = find.byKey(const ValueKey('sync-drag-bar'));
    expect(bar, findsOneWidget);
    final box = tester.getRect(bar);

    // Three quarters along the bar is half of the positive range.
    await tester.dragFrom(
      Offset(box.left + box.width * 0.75, box.center.dy),
      Offset.zero,
    );
    await tester.pump();
    expect(c.read(subtitleSyncProvider), trackDelayRangeMs ~/ 2);

    await tester.pump(const Duration(milliseconds: 200));
  });

  // The HUD can mount already visible: opened from ⋮, then PiP or minimize
  // tears PlayerScreen down while the provider stays true. ref.listen only
  // fires on a transition, so without arming on mount nothing would ever hide
  // it again — and both remaining exits (± and the value tap) change the
  // user's subtitle timing.
  testWidgets('arms the auto-hide when it mounts already visible', (
    tester,
  ) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    c
        .read(currentVideoProvider.notifier)
        .open(
          const VideoSession(
            playbackPath: '/v/a.mkv',
            displayName: 'a.mkv',
            queue: ['/v/a.mkv'],
            index: 0,
          ),
        );
    c.read(syncHudProvider.notifier).show(SyncTarget.subtitles);

    await _pump(tester, c);
    expect(find.text('0,00 s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(c.read(syncHudProvider), isNull);
  });

  // The other half of the same hole: the capsule belongs to the video that is
  // open, so leaving the player or advancing to the next one takes it away.
  testWidgets('closes itself when the open video changes', (tester) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    final videos = c.read(currentVideoProvider.notifier);
    videos.open(
      const VideoSession(
        playbackPath: '/v/a.mkv',
        displayName: 'a.mkv',
        queue: ['/v/a.mkv'],
        index: 0,
      ),
    );
    await _pump(tester, c);
    c.read(syncHudProvider.notifier).show(SyncTarget.subtitles);
    await tester.pump();
    expect(find.text('0,00 s'), findsOneWidget);

    videos.open(
      const VideoSession(
        playbackPath: '/v/b.mkv',
        displayName: 'b.mkv',
        queue: ['/v/b.mkv'],
        index: 0,
      ),
    );
    await tester.pump();
    expect(c.read(syncHudProvider), isNull);
    expect(find.text('0,00 s'), findsNothing);
  });

  testWidgets('hides itself after the idle timeout', (tester) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    c
        .read(currentVideoProvider.notifier)
        .open(
          const VideoSession(
            playbackPath: '/v/a.mkv',
            displayName: 'a.mkv',
            queue: ['/v/a.mkv'],
            index: 0,
          ),
        );
    await _pump(tester, c);
    c.read(syncHudProvider.notifier).show(SyncTarget.subtitles);
    await tester.pump();
    expect(find.text('0,00 s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(c.read(syncHudProvider), isNull);
  });
  testWidgets('the Sub|Audio switch moves which offset the buttons touch', (
    tester,
  ) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    c
        .read(currentVideoProvider.notifier)
        .open(
          const VideoSession(
            playbackPath: '/v/a.mkv',
            displayName: 'a.mkv',
            queue: ['/v/a.mkv'],
            index: 0,
          ),
        );
    await _pump(tester, c);

    c.read(syncHudProvider.notifier).show(SyncTarget.subtitles);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('subtitle-sync-plus')));
    await tester.pump();
    expect(find.text('+0,05 s'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sync-target-audio')));
    await tester.pump();
    // The audio side starts at its own value, untouched by the subtitle nudge.
    expect(find.text('0,00 s'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('subtitle-sync-minus')));
    await tester.pump();
    expect(find.text('−0,05 s'), findsOneWidget);
    expect(c.read(subtitleSyncProvider), 50);
    expect(c.read(audioSyncProvider), -50);

    // Back to Sub: its own value is still there.
    await tester.tap(find.byKey(const ValueKey('sync-target-subtitles')));
    await tester.pump();
    expect(find.text('+0,05 s'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
  });
  testWidgets('the close button dismisses it and keeps the pending value',
      (tester) async {
    final engine = FakePlaybackEngine();
    final c = await _c(engine);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0));
    await _pump(tester, c);
    c.read(syncHudProvider.notifier).show(SyncTarget.subtitles);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('subtitle-sync-plus')));
    await tester.pump();
    // Closing right away, well inside the 120 ms debounce.
    expect(engine.subtitleDelays, isEmpty);

    await tester.tap(find.byKey(const ValueKey('sync-close')));
    await tester.pump();

    expect(c.read(syncHudProvider), isNull);
    // Flushed on the way out — closing by hand must not drop the last nudge.
    expect(engine.subtitleDelays, [0.05]);
  });

  testWidgets('opening it puts the player controls away', (tester) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0));
    await _pump(tester, c);

    c.read(controlsVisibleProvider.notifier).show();
    expect(c.read(controlsVisibleProvider), true);

    c.read(syncHudProvider.notifier).show(SyncTarget.subtitles);
    await tester.pump();

    expect(c.read(controlsVisibleProvider), false);
  });

}
