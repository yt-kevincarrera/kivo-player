import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/background/audio_only.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/audio_only/audio_only_view.dart';
import '../../fakes/fakes.dart';

void main() {
  late FakePlaybackEngine engine;
  late ProviderContainer c;

  Future<void> pumpView(WidgetTester tester) async {
    engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: AudioOnlyView())),
    ));
    await tester.pump();
  }

  testWidgets('hidden when off; center + "Ver video" ALWAYS visible when on (no controls dependency)',
      (tester) async {
    await pumpView(tester);
    expect(find.text('SOLO AUDIO'), findsNothing);
    c.read(audioOnlyProvider.notifier).toggle();
    await tester.pump();
    // Controls were never shown — the mini music-player center is visible anyway.
    expect(find.text('SOLO AUDIO'), findsOneWidget);
    expect(find.text('ep1.mkv'), findsOneWidget);
    expect(find.text('Ver video'), findsOneWidget);
    expect(engine.videoTrackEnabled, false);
  });

  testWidgets('tapping "Ver video" returns to video instantly', (tester) async {
    await pumpView(tester);
    c.read(audioOnlyProvider.notifier).toggle();
    await tester.pump();
    await tester.tap(find.text('Ver video'));
    await tester.pump();
    expect(c.read(audioOnlyProvider), false);
    expect(engine.videoTrackEnabled, true);
    expect(find.text('SOLO AUDIO'), findsNothing);
  });

  testWidgets('toggling off restores the video track and hides the view', (tester) async {
    await pumpView(tester);
    c.read(audioOnlyProvider.notifier).toggle();
    await tester.pump();
    c.read(audioOnlyProvider.notifier).toggle();
    await tester.pump();
    expect(find.text('SOLO AUDIO'), findsNothing);
    expect(engine.videoTrackEnabled, true);
  });
}
