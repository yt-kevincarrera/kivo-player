import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/media_session_provider.dart';
import 'package:kivo_player/player/background/background_playback.dart';
import 'package:kivo_player/player/control/player_controller.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import '../../fakes/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePlaybackEngine engine;
  late FakeMediaSessionBridge bridge;
  late ProviderContainer c;
  late BackgroundPlaybackCoordinator coord;

  Future<void> setUpAll_() async {
    engine = FakePlaybackEngine();
    bridge = FakeMediaSessionBridge();
    final s = await SettingsService.load(InMemorySettingsStore());
    c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      mediaSessionProvider.overrideWithValue(bridge),
    ]);
    addTearDown(c.dispose);
    addTearDown(engine.dispose);
    coord = c.read(backgroundPlaybackProvider);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
    );
  }

  Future<void> pump() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('backgrounding while playing starts a session with title and state', () async {
    await setUpAll_();
    engine.emitPlaying(true);
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 2));
    await pump();
    coord.didChangeAppLifecycleState(AppLifecycleState.paused);
    await pump();
    expect(bridge.updates, isNotEmpty);
    final u = bridge.updates.last;
    expect(u['title'], 'ep1.mkv');
    expect(u['playing'], true);
    expect(u['inBackground'], true);
    expect(bridge.permissionRequests, greaterThan(0));
  });

  test('backgrounding while paused starts no session', () async {
    await setUpAll_();
    engine.emitPlaying(false);
    await pump();
    bridge.updates.clear();
    coord.didChangeAppLifecycleState(AppLifecycleState.paused);
    await pump();
    expect(bridge.updates.where((u) => u['inBackground'] == true && u['playing'] == true), isEmpty);
    expect(bridge.endCount, 0);
  });

  test('returning to the foreground ends the session', () async {
    await setUpAll_();
    engine.emitPlaying(true);
    await pump();
    coord.didChangeAppLifecycleState(AppLifecycleState.paused);
    await pump();
    coord.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pump();
    expect(bridge.endCount, 1);
  });

  test('position updates while backgrounded push one update per second of media time', () async {
    await setUpAll_();
    engine.emitPlaying(true);
    engine.emitDuration(const Duration(minutes: 10));
    await pump();
    coord.didChangeAppLifecycleState(AppLifecycleState.paused);
    await pump();
    bridge.updates.clear();
    engine.emitPosition(const Duration(seconds: 30));
    engine.emitPosition(const Duration(seconds: 30, milliseconds: 400));
    engine.emitPosition(const Duration(seconds: 31));
    await pump();
    // 30.0 and 30.4 share second 30 → one update; 31 → another.
    expect(bridge.updates.length, 2);
  });

  test('bridge callbacks drive the engine/controller', () async {
    await setUpAll_();
    await pump();
    final cb = bridge.callbacks!;
    cb.onPlay();
    expect(engine.lastPlayingCommand, true);
    cb.onPause();
    expect(engine.lastPlayingCommand, false);
    engine.emitPosition(const Duration(minutes: 5));
    engine.emitDuration(const Duration(minutes: 10));
    await pump();
    cb.onSeek(const Duration(minutes: 4));
    expect(engine.lastSeek, const Duration(minutes: 4));
    cb.onSkip(10);
    expect(engine.lastSeek, isNotNull);
    cb.onStop();
    expect(engine.lastPlayingCommand, false);
    expect(bridge.endCount, greaterThan(0));
  });

  test('permanent focus loss pauses and never auto-resumes', () async {
    await setUpAll_();
    engine.emitPlaying(true);
    await pump();
    bridge.callbacks!.onFocusLoss();
    expect(engine.lastPlayingCommand, false);
    engine.emitPlaying(false);
    await pump();
    bridge.callbacks!.onFocusRegained();
    expect(engine.lastPlayingCommand, false); // still paused
  });

  test('transient focus loss pauses and auto-resumes on regain', () async {
    await setUpAll_();
    engine.emitPlaying(true);
    await pump();
    bridge.callbacks!.onFocusTransientLoss();
    expect(engine.lastPlayingCommand, false);
    engine.emitPlaying(false);
    await pump();
    bridge.callbacks!.onFocusRegained();
    expect(engine.lastPlayingCommand, true); // resumed
  });

  test('transient focus loss does NOT auto-resume if the user paused first', () async {
    await setUpAll_();
    engine.emitPlaying(false); // user-paused state
    await pump();
    bridge.callbacks!.onFocusTransientLoss(); // nothing playing → no focus pause
    bridge.callbacks!.onFocusRegained();
    expect(engine.lastPlayingCommand, isNot(true));
  });

  test('duck lowers player volume to 30% and restores on duck end', () async {
    await setUpAll_();
    c.read(volumePercentProvider.notifier).state = 100;
    engine.emitPlaying(true);
    await pump();
    bridge.callbacks!.onDuckStart();
    expect(engine.volume, closeTo(30, 0.01));
    bridge.callbacks!.onDuckEnd();
    expect(engine.volume, 100);
  });

  test('manual volume change during duck cancels the restore', () async {
    await setUpAll_();
    c.read(volumePercentProvider.notifier).state = 100;
    engine.emitPlaying(true);
    await pump();
    bridge.callbacks!.onDuckStart();
    expect(engine.volume, closeTo(30, 0.01));
    c.read(volumePercentProvider.notifier).state = 60;
    engine.volume = 77; // whatever the user's gesture applied
    bridge.callbacks!.onDuckEnd();
    expect(engine.volume, 77); // duck end must not clobber the user's level
  });
}
