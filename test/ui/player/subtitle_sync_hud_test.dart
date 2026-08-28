import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/subtitle_prefs_store.dart';
import 'package:kivo_player/ui/player/tracks/subtitle_sync_hud.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _c(FakePlaybackEngine engine) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    playbackEngineProvider.overrideWithValue(engine),
    subtitlePrefsStoreProvider.overrideWithValue(InMemorySubtitlePrefsStore()),
  ]);
}

Future<void> _pump(WidgetTester tester, ProviderContainer c) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: SubtitleSyncHud())),
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
    c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0));
    await _pump(tester, c);

    c.read(subtitleSyncVisibleProvider.notifier).show();
    await tester.pump();
    expect(find.text('0,00 s'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('subtitle-sync-plus')));
    await tester.pump();
    expect(find.text('+0,05 s'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('subtitle-sync-minus')));
    await tester.tap(find.byKey(const ValueKey('subtitle-sync-minus')));
    await tester.pump();
    expect(find.text('−0,05 s'), findsOneWidget);

    // Drain subtitleSyncProvider's trailing debounce (subtitle_sync_controller.dart)
    // so its Timer isn't still pending when the widget tree tears down.
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('tapping the value resets it to zero', (tester) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0));
    await _pump(tester, c);
    c.read(subtitleSyncVisibleProvider.notifier).show();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('subtitle-sync-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('subtitle-sync-value')));
    await tester.pump();
    expect(find.text('0,00 s'), findsOneWidget);

    // Drain subtitleSyncProvider's trailing debounce (subtitle_sync_controller.dart)
    // so its Timer isn't still pending when the widget tree tears down.
    await tester.pump(const Duration(milliseconds: 200));
  });

  // The HUD can mount already visible: opened from ⋮, then PiP or minimize
  // tears PlayerScreen down while the provider stays true. ref.listen only
  // fires on a transition, so without arming on mount nothing would ever hide
  // it again — and both remaining exits (± and the value tap) change the
  // user's subtitle timing.
  testWidgets('arms the auto-hide when it mounts already visible', (tester) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0));
    c.read(subtitleSyncVisibleProvider.notifier).show();

    await _pump(tester, c);
    expect(find.text('0,00 s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(c.read(subtitleSyncVisibleProvider), false);
  });

  // The other half of the same hole: the capsule belongs to the video that is
  // open, so leaving the player or advancing to the next one takes it away.
  testWidgets('closes itself when the open video changes', (tester) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    final videos = c.read(currentVideoProvider.notifier);
    videos.open(const VideoSession(
        playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0));
    await _pump(tester, c);
    c.read(subtitleSyncVisibleProvider.notifier).show();
    await tester.pump();
    expect(find.text('0,00 s'), findsOneWidget);

    videos.open(const VideoSession(
        playbackPath: '/v/b.mkv', displayName: 'b.mkv', queue: ['/v/b.mkv'], index: 0));
    await tester.pump();
    expect(c.read(subtitleSyncVisibleProvider), false);
    expect(find.text('0,00 s'), findsNothing);
  });

  testWidgets('hides itself after the idle timeout', (tester) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0));
    await _pump(tester, c);
    c.read(subtitleSyncVisibleProvider.notifier).show();
    await tester.pump();
    expect(find.text('0,00 s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(c.read(subtitleSyncVisibleProvider), false);
  });
}
