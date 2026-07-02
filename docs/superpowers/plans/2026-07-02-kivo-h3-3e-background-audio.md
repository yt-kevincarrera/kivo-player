# Kivo H3/3e — Background Playback + Audio-Only Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Audio keeps playing automatically when the app backgrounds (media notification with play/pause/±10s/seek, full audio-focus handling), plus a minimal in-app "Solo audio" mode (video track off, black surface, controls intact).

**Architecture:** A Dart `BackgroundPlaybackCoordinator` (app-level lifecycle observer) pushes playback state through a `MediaSessionBridge` platform interface to a Kotlin side consisting of a shared `PlaybackSessionHub` (channel + audio focus) and a `PlaybackSessionService` (foreground `mediaPlayback` service with `MediaSessionCompat` + MediaStyle notification). Notification/focus actions flow back over the same channel into the existing `PlaybackEngine`/`PlayerController` paths. Audio-only is a tiny `AudioOnlyNotifier` toggling mpv's video track via a new `PlaybackEngine.setVideoTrackEnabled`.

**Tech Stack:** Flutter/Riverpod, MethodChannel `kivo/media_session`, Kotlin (`MediaSessionCompat`, `NotificationCompat.MediaStyle`, `AudioFocusRequest`), androidx.media, permission_handler (POST_NOTIFICATIONS).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-02-kivo-h3-3e-background-audio-design.md` — authoritative.
- Background playback is AUTOMATIC: remove `_engine.pause(); // no background playback in Hito 1` from `PlayerScreen.didChangeAppLifecycleState` — keep the `_saveProgress()` calls exactly as they are. In-app navigation pause (dispose) unchanged.
- If PAUSED when the app backgrounds → no session, no notification, no service.
- Notification actions route through EXISTING paths: play/pause → `PlaybackEngine`; ±10s → `PlayerController.skipBy`; seek → `PlayerController.seekTo` (so a notification seek outside an active A-B range cancels the loop, consistent with 3c).
- Audio focus: permanent loss → pause, never auto-resume; transient loss → pause + auto-resume ONLY if the pause was focus-caused; duck → player volume to 30% of the user level (`volumeMapping(...).playerPercent * 0.3`), restore on duck end unless the user adjusted volume during the duck. NEVER touch system volume.
- "Solo audio": menu ⋮ third row with a gold Switch (row toggles, does not navigate); copy "Solo audio" / "Apagar el video, seguir escuchando"; ON → `vid=no`, black surface + static gold waves + title + "SOLO AUDIO" (center follows `controlsVisibleProvider` show/hide; black fill is permanent); OFF/video change/player exit → `vid=auto`. NO persistence, NO settings field.
- Platform boundary pattern (like `SubtitleFinder`): interface in `lib/platform/interfaces/`, Android impl in `lib/platform/android/`, throws-until-overridden provider, override in `main.dart`. No media_kit types past `PlaybackEngine`.
- Spanish copy exact where given. Notification channel name: "Reproducción".
- `flutter analyze` clean and full `flutter test` green before every commit. Current suite: 211 tests. Task 3 (Kotlin) additionally requires `flutter build apk --debug` to compile clean.
- Do NOT build/install the release APK mid-plan — one build at the very end.

---

### Task 1: PlaybackEngine.setVideoTrackEnabled + AudioOnlyNotifier

**Files:**
- Modify: `lib/player/engine/playback_engine.dart` (new method on the abstract class)
- Modify: `lib/player/engine/media_kit_engine.dart` (impl)
- Create: `lib/player/background/audio_only.dart`
- Modify: `test/fakes/fakes.dart` (fake mirror)
- Test: `test/player/background/audio_only_test.dart`

**Interfaces:**
- Consumes: `playbackEngineProvider`; `currentVideoProvider`; `NativePlayer.setProperty` (already used by `setSubtitleStyle` in `media_kit_engine.dart`).
- Produces: `Future<void> setVideoTrackEnabled(bool enabled)` on `PlaybackEngine`; `final audioOnlyProvider = NotifierProvider<AudioOnlyNotifier, bool>(AudioOnlyNotifier.new);` with methods `void toggle()`, `void disable()`; `FakePlaybackEngine.videoTrackEnabled` (bool, default true).

- [ ] **Step 1: Write the failing tests**

Create `test/player/background/audio_only_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/background/audio_only.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import '../../fakes/fakes.dart';

void main() {
  late FakePlaybackEngine engine;
  late ProviderContainer c;

  Future<void> setUpContainer() async {
    engine = FakePlaybackEngine();
    final s = await SettingsService.load(InMemorySettingsStore());
    c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);
    addTearDown(engine.dispose);
    c.listen(audioOnlyProvider, (_, __) {});
  }

  test('toggle turns the video track off and back on', () async {
    await setUpContainer();
    final n = c.read(audioOnlyProvider.notifier);
    expect(c.read(audioOnlyProvider), false);
    expect(engine.videoTrackEnabled, true);
    n.toggle();
    expect(c.read(audioOnlyProvider), true);
    expect(engine.videoTrackEnabled, false);
    n.toggle();
    expect(c.read(audioOnlyProvider), false);
    expect(engine.videoTrackEnabled, true);
  });

  test('changing video resets audio-only and re-enables the video track', () async {
    await setUpContainer();
    c.read(audioOnlyProvider.notifier).toggle();
    expect(engine.videoTrackEnabled, false);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep2.mkv', displayName: 'ep2.mkv', queue: ['/v/ep2.mkv'], index: 0),
    );
    await Future<void>.delayed(Duration.zero);
    expect(c.read(audioOnlyProvider), false);
    expect(engine.videoTrackEnabled, true);
  });

  test('disable is a no-op when already off, otherwise restores video', () async {
    await setUpContainer();
    final n = c.read(audioOnlyProvider.notifier);
    n.disable(); // no-op
    expect(engine.videoTrackEnabled, true);
    n.toggle();
    n.disable();
    expect(c.read(audioOnlyProvider), false);
    expect(engine.videoTrackEnabled, true);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/player/background/audio_only_test.dart`
Expected: FAIL — `audio_only.dart` / `setVideoTrackEnabled` don't exist.

- [ ] **Step 3: Implement**

In `lib/player/engine/playback_engine.dart`, add to the abstract class (next to `setSubtitleStyle`):

```dart
  /// Turns the video track off ([enabled] = false → mpv `vid=no`, audio-only)
  /// or back to automatic selection (true → `vid=auto`).
  Future<void> setVideoTrackEnabled(bool enabled);
```

In `lib/player/engine/media_kit_engine.dart` (mirroring `setSubtitleStyle`'s NativePlayer pattern):

```dart
  @override
  Future<void> setVideoTrackEnabled(bool enabled) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    await native.setProperty('vid', enabled ? 'auto' : 'no');
  }
```

In `test/fakes/fakes.dart`, add to `FakePlaybackEngine`:

```dart
  bool videoTrackEnabled = true;

  @override
  Future<void> setVideoTrackEnabled(bool enabled) async {
    videoTrackEnabled = enabled;
  }
```

Create `lib/player/background/audio_only.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/playback_provider.dart';
import '../open/video_source.dart';

/// In-app "Solo audio" mode: video track off, black surface, controls intact.
/// A tool of the moment — dies on video change and on player exit; never
/// persisted.
final audioOnlyProvider =
    NotifierProvider<AudioOnlyNotifier, bool>(AudioOnlyNotifier.new);

class AudioOnlyNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(currentVideoProvider, (prev, next) {
      if (state && prev != next) {
        _setVideo(true);
        state = false;
      }
    });
    return false;
  }

  void _setVideo(bool on) =>
      ref.read(playbackEngineProvider).setVideoTrackEnabled(on);

  void toggle() {
    final next = !state;
    _setVideo(!next);
    state = next;
  }

  /// Called from PlayerScreen's dispose (via a notifier cached in initState —
  /// never ref.read in dispose).
  void disable() {
    if (!state) return;
    _setVideo(true);
    state = false;
  }
}
```

- [ ] **Step 4: Run tests, analyze, full suite**

Run: `flutter test test/player/background/audio_only_test.dart` → PASS (3 tests).
Run: `flutter analyze` → clean. Run: `flutter test` → 214 passing (211 + 3).

- [ ] **Step 5: Commit**

```bash
git add lib/player/engine/playback_engine.dart lib/player/engine/media_kit_engine.dart lib/player/background/audio_only.dart test/fakes/fakes.dart test/player/background/audio_only_test.dart
git commit -m "feat: audio-only mode core — PlaybackEngine.setVideoTrackEnabled + AudioOnlyNotifier"
```

---

### Task 2: MediaSessionBridge + BackgroundPlaybackCoordinator

**Files:**
- Create: `lib/platform/interfaces/media_session.dart`
- Create: `lib/platform/android/android_media_session.dart`
- Create: `lib/platform/media_session_provider.dart`
- Create: `lib/player/background/background_playback.dart`
- Modify: `test/fakes/fakes.dart` (FakeMediaSessionBridge)
- Test: `test/player/background/background_playback_test.dart`

**Interfaces:**
- Consumes: `playingProvider`/`positionProvider`/`durationProvider` (StreamProviders); `currentVideoProvider` (`VideoSession.displayName`); `playbackEngineProvider`; `playerControllerProvider` (`skipBy(int)`, `seekTo(Duration)`); `volumePercentProvider`; `volumeMapping(percent, boostMax)`; `settingsProvider.volumeBoostMax`.
- Produces (Tasks 3–4 rely on these exact names):
  - `class MediaSessionCallbacks { final void Function() onPlay, onPause, onStop, onFocusLoss, onFocusTransientLoss, onFocusRegained, onDuckStart, onDuckEnd; final void Function(int seconds) onSkip; final void Function(Duration position) onSeek; }` (const ctor, all named required).
  - `abstract class MediaSessionBridge { void setCallbacks(MediaSessionCallbacks callbacks); Future<void> ensureNotificationPermission(); Future<void> updateSession({required String title, required Duration position, required Duration duration, required bool playing, required bool inBackground}); Future<void> endSession(); }`
  - `final mediaSessionProvider = Provider<MediaSessionBridge>((ref) => throw UnimplementedError(...));`
  - `final backgroundPlaybackProvider = Provider<BackgroundPlaybackCoordinator>(...)` — instantiating it wires everything; `BackgroundPlaybackCoordinator` exposes `didChangeAppLifecycleState(AppLifecycleState)` (it's a `WidgetsBindingObserver`).
  - Channel protocol (Task 3 implements the other side): Dart→native method `update` args `{title: String, positionMs: int, durationMs: int, playing: bool, inBackground: bool}`; method `end` no args. Native→Dart methods: `play`, `pause`, `skip` args `{seconds: int}`, `seekTo` args `{ms: int}`, `stop`, `focusLoss`, `focusTransientLoss`, `focusRegained`, `duckStart`, `duckEnd`.

- [ ] **Step 1: Create the interface**

`lib/platform/interfaces/media_session.dart`:

```dart
/// Callbacks the native media session / audio-focus side invokes on Dart.
class MediaSessionCallbacks {
  final void Function() onPlay;
  final void Function() onPause;
  final void Function(int seconds) onSkip;
  final void Function(Duration position) onSeek;
  final void Function() onStop;
  final void Function() onFocusLoss;
  final void Function() onFocusTransientLoss;
  final void Function() onFocusRegained;
  final void Function() onDuckStart;
  final void Function() onDuckEnd;
  const MediaSessionCallbacks({
    required this.onPlay,
    required this.onPause,
    required this.onSkip,
    required this.onSeek,
    required this.onStop,
    required this.onFocusLoss,
    required this.onFocusTransientLoss,
    required this.onFocusRegained,
    required this.onDuckStart,
    required this.onDuckEnd,
  });
}

/// Boundary to the Android media session + notification + audio focus.
abstract class MediaSessionBridge {
  void setCallbacks(MediaSessionCallbacks callbacks);

  /// Android 13+ runtime notification permission. Safe to call repeatedly.
  Future<void> ensureNotificationPermission();

  /// Pushed on every playing-state change, every new position second while
  /// relevant, and every lifecycle change. Native decides from [playing] +
  /// [inBackground] whether a foreground service/notification must exist.
  Future<void> updateSession({
    required String title,
    required Duration position,
    required Duration duration,
    required bool playing,
    required bool inBackground,
  });

  Future<void> endSession();
}
```

- [ ] **Step 2: Create the Android impl and provider**

`lib/platform/android/android_media_session.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../interfaces/media_session.dart';

class AndroidMediaSessionBridge implements MediaSessionBridge {
  static const _channel = MethodChannel('kivo/media_session');
  MediaSessionCallbacks? _callbacks;
  bool _permissionRequested = false;

  AndroidMediaSessionBridge() {
    _channel.setMethodCallHandler((call) async {
      final cb = _callbacks;
      if (cb == null) return;
      switch (call.method) {
        case 'play':
          cb.onPlay();
        case 'pause':
          cb.onPause();
        case 'skip':
          cb.onSkip((call.arguments as Map)['seconds'] as int);
        case 'seekTo':
          cb.onSeek(Duration(milliseconds: (call.arguments as Map)['ms'] as int));
        case 'stop':
          cb.onStop();
        case 'focusLoss':
          cb.onFocusLoss();
        case 'focusTransientLoss':
          cb.onFocusTransientLoss();
        case 'focusRegained':
          cb.onFocusRegained();
        case 'duckStart':
          cb.onDuckStart();
        case 'duckEnd':
          cb.onDuckEnd();
      }
    });
  }

  @override
  void setCallbacks(MediaSessionCallbacks callbacks) => _callbacks = callbacks;

  @override
  Future<void> ensureNotificationPermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    // Denial is non-fatal: background audio still works, only the
    // notification is missing.
    await Permission.notification.request();
  }

  @override
  Future<void> updateSession({
    required String title,
    required Duration position,
    required Duration duration,
    required bool playing,
    required bool inBackground,
  }) {
    return _channel.invokeMethod('update', {
      'title': title,
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'playing': playing,
      'inBackground': inBackground,
    });
  }

  @override
  Future<void> endSession() => _channel.invokeMethod('end');
}
```

`lib/platform/media_session_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/media_session.dart';

/// Overridden in main() with the Android implementation.
final mediaSessionProvider = Provider<MediaSessionBridge>((ref) {
  throw UnimplementedError('mediaSessionProvider must be overridden');
});
```

- [ ] **Step 3: Add FakeMediaSessionBridge to `test/fakes/fakes.dart`**

```dart
class FakeMediaSessionBridge implements MediaSessionBridge {
  MediaSessionCallbacks? callbacks;
  final List<Map<String, Object>> updates = [];
  int endCount = 0;
  int permissionRequests = 0;

  @override
  void setCallbacks(MediaSessionCallbacks cb) => callbacks = cb;

  @override
  Future<void> ensureNotificationPermission() async => permissionRequests++;

  @override
  Future<void> updateSession({
    required String title,
    required Duration position,
    required Duration duration,
    required bool playing,
    required bool inBackground,
  }) async {
    updates.add({
      'title': title,
      'position': position,
      'duration': duration,
      'playing': playing,
      'inBackground': inBackground,
    });
  }

  @override
  Future<void> endSession() async => endCount++;
}
```

(Add the import `import 'package:kivo_player/platform/interfaces/media_session.dart';` at the top of fakes.dart.)

- [ ] **Step 4: Write the failing coordinator tests**

Create `test/player/background/background_playback_test.dart`:

```dart
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
```

- [ ] **Step 5: Run to verify failure**

Run: `flutter test test/player/background/background_playback_test.dart`
Expected: FAIL — coordinator doesn't exist.

- [ ] **Step 6: Implement `lib/player/background/background_playback.dart`**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/interfaces/media_session.dart';
import '../../platform/media_session_provider.dart';
import '../control/gesture_math.dart';
import '../control/player_controller.dart';
import '../engine/playback_provider.dart';
import '../open/video_source.dart';

/// App-level coordinator: keeps the native media session fed while playback
/// is relevant, reacts to notification/focus events, and owns the duck.
/// Instantiate by watching [backgroundPlaybackProvider] once (KivoApp does).
final backgroundPlaybackProvider = Provider<BackgroundPlaybackCoordinator>((ref) {
  final coordinator = BackgroundPlaybackCoordinator(ref);
  coordinator.init();
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

class BackgroundPlaybackCoordinator with WidgetsBindingObserver {
  final Ref _ref;
  BackgroundPlaybackCoordinator(this._ref);

  bool _inBackground = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _lastSentSecond = -1;
  bool _sessionActive = false;

  bool _pausedByFocus = false;
  bool _ducking = false;
  bool _duckUserAdjusted = false;

  MediaSessionBridge get _bridge => _ref.read(mediaSessionProvider);

  void init() {
    WidgetsBinding.instance.addObserver(this);
    _bridge.setCallbacks(MediaSessionCallbacks(
      onPlay: () => _ref.read(playbackEngineProvider).play(),
      onPause: () => _ref.read(playbackEngineProvider).pause(),
      onSkip: (s) => _ref.read(playerControllerProvider).skipBy(s),
      onSeek: (p) => _ref.read(playerControllerProvider).seekTo(p),
      onStop: () {
        _ref.read(playbackEngineProvider).pause();
        _end();
      },
      onFocusLoss: _onFocusLoss,
      onFocusTransientLoss: _onFocusTransientLoss,
      onFocusRegained: _onFocusRegained,
      onDuckStart: _onDuckStart,
      onDuckEnd: _onDuckEnd,
    ));
    _ref.listen(playingProvider, (_, next) {
      final p = next.value;
      if (p == null) return;
      _playing = p;
      _push(force: true);
    });
    _ref.listen(positionProvider, (_, next) {
      final d = next.value;
      if (d == null) return;
      _position = d;
      _push();
    });
    _ref.listen(durationProvider, (_, next) {
      _duration = next.value ?? Duration.zero;
    });
    _ref.listen(volumePercentProvider, (_, __) {
      if (_ducking) _duckUserAdjusted = true;
    });
    _ref.listen(currentVideoProvider, (_, next) {
      // Ask for the notification permission at first video open — a request
      // from the background (session start) would never show the dialog.
      if (next != null && !_permissionAsked) {
        _permissionAsked = true;
        _bridge.ensureNotificationPermission();
      }
    });
  }

  bool _permissionAsked = false;

  void dispose() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _inBackground = true;
      _push(force: true);
    } else if (state == AppLifecycleState.resumed) {
      _inBackground = false;
      if (_sessionActive) _end();
    }
  }

  void _push({bool force = false}) {
    final relevant = _playing || _sessionActive;
    if (!relevant) return;
    final second = _position.inSeconds;
    if (!force && second == _lastSentSecond) return;
    // Only feed the channel when a session exists or should start — in the
    // foreground with no session there is nothing to keep updated.
    final shouldHaveSession = _inBackground && _playing;
    if (!shouldHaveSession && !_sessionActive) return;
    _lastSentSecond = second;
    if (shouldHaveSession && !_sessionActive) {
      _sessionActive = true;
    }
    final title = _ref.read(currentVideoProvider)?.displayName ?? 'Kivo';
    _bridge.updateSession(
      title: title,
      position: _position,
      duration: _duration,
      playing: _playing,
      inBackground: _inBackground,
    );
  }

  void _end() {
    _sessionActive = false;
    _lastSentSecond = -1;
    _bridge.endSession();
  }

  // ── audio focus ──────────────────────────────────────────────────────────

  void _onFocusLoss() {
    if (_playing) _ref.read(playbackEngineProvider).pause();
    _pausedByFocus = false; // permanent: never auto-resume
  }

  void _onFocusTransientLoss() {
    if (_playing) {
      _ref.read(playbackEngineProvider).pause();
      _pausedByFocus = true;
    }
  }

  void _onFocusRegained() {
    if (_pausedByFocus) {
      _ref.read(playbackEngineProvider).play();
      _pausedByFocus = false;
    }
  }

  double get _userPlayerVolume {
    final boost = _ref.read(settingsProvider).volumeBoostMax.toDouble();
    return volumeMapping(_ref.read(volumePercentProvider), boost).playerPercent;
  }

  void _onDuckStart() {
    if (!_playing) return;
    _ducking = true;
    _duckUserAdjusted = false;
    _ref.read(playbackEngineProvider).setVolume(_userPlayerVolume * 0.3);
  }

  void _onDuckEnd() {
    if (_ducking && !_duckUserAdjusted) {
      _ref.read(playbackEngineProvider).setVolume(_userPlayerVolume);
    }
    _ducking = false;
    _duckUserAdjusted = false;
  }
}
```

- [ ] **Step 7: Run tests, analyze, full suite**

Run: `flutter test test/player/background/background_playback_test.dart` → PASS (10 tests).
Run: `flutter analyze` → clean. Run: `flutter test` → 224 passing (214 + 10).

- [ ] **Step 8: Commit**

```bash
git add lib/platform/interfaces/media_session.dart lib/platform/android/android_media_session.dart lib/platform/media_session_provider.dart lib/player/background/background_playback.dart test/fakes/fakes.dart test/player/background/background_playback_test.dart
git commit -m "feat: media session bridge + background playback coordinator with focus/duck"
```

---

### Task 3: Native Kotlin — PlaybackSessionHub, PlaybackSessionService, manifest

**Files:**
- Create: `android/app/src/main/kotlin/dev/selector/kivo_player/PlaybackSessionHub.kt`
- Create: `android/app/src/main/kotlin/dev/selector/kivo_player/PlaybackSessionService.kt`
- Modify: `android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt` (register the channel)
- Modify: `android/app/src/main/AndroidManifest.xml` (permissions + service)
- Modify: `android/app/build.gradle` OR `android/app/build.gradle.kts` (whichever exists — check first): add `androidx.media:media:1.7.0`

**Interfaces:**
- Consumes: the channel protocol from Task 2 (`update`/`end` in; `play/pause/skip/seekTo/stop/focus*` out).
- Produces: a working notification + audio focus on-device. No Dart-visible API.

- [ ] **Step 1: Add the androidx.media dependency**

Check which gradle file exists (`android/app/build.gradle` or `.gradle.kts`) and add to its `dependencies` block:
`implementation("androidx.media:media:1.7.0")` (Kotlin DSL) or `implementation 'androidx.media:media:1.7.0'` (Groovy).

- [ ] **Step 2: Manifest**

In `android/app/src/main/AndroidManifest.xml`, next to the existing `uses-permission` lines add:

```xml
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

and inside `<application>` (next to the activity):

```xml
        <service
            android:name=".PlaybackSessionService"
            android:exported="false"
            android:foregroundServiceType="mediaPlayback">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </service>
```

(The MEDIA_BUTTON intent-filter is REQUIRED: `MediaButtonReceiver.buildMediaButtonPendingIntent` resolves its target by looking for the unique service handling that action and throws at runtime without it; `onStartCommand` already routes those intents via `MediaButtonReceiver.handleIntent`.)

- [ ] **Step 3: Create `PlaybackSessionHub.kt`**

```kotlin
package dev.selector.kivo_player

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Process-wide hub between the Dart coordinator, the foreground service and
 * audio focus. MainActivity owns the MethodChannel and registers it here;
 * the service reads state and reports actions back through [invokeDart].
 */
object PlaybackSessionHub {
    @Volatile var channel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Latest state pushed from Dart.
    @Volatile var title: String = "Kivo"
    @Volatile var positionMs: Long = 0
    @Volatile var durationMs: Long = 0
    @Volatile var playing: Boolean = false

    private var focusRequest: AudioFocusRequest? = null
    private var focusHeld = false

    fun invokeDart(method: String, args: Map<String, Any?>? = null) {
        mainHandler.post { channel?.invokeMethod(method, args) }
    }

    fun update(context: Context, title: String, positionMs: Long, durationMs: Long, playing: Boolean, inBackground: Boolean) {
        this.title = title
        this.positionMs = positionMs
        this.durationMs = durationMs
        this.playing = playing
        if (playing) requestFocus(context) 
        if (inBackground && playing) {
            PlaybackSessionService.start(context)
        }
        PlaybackSessionService.refresh()
    }

    fun end(context: Context) {
        abandonFocus(context)
        PlaybackSessionService.stop(context)
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> { focusHeld = false; invokeDart("focusLoss") }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> invokeDart("focusTransientLoss")
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> invokeDart("duckStart")
            AudioManager.AUDIOFOCUS_GAIN -> {
                // A gain after a duck ends the duck; after a transient loss it resumes.
                invokeDart("duckEnd")
                invokeDart("focusRegained")
            }
        }
    }

    private fun requestFocus(context: Context) {
        if (focusHeld) return
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val granted: Int
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build()
                )
                .setOnAudioFocusChangeListener(focusListener)
                .build()
            focusRequest = req
            granted = am.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            granted = am.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
        focusHeld = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonFocus(context: Context) {
        if (!focusHeld) return
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { am.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(focusListener)
        }
        focusHeld = false
    }
}
```

- [ ] **Step 4: Create `PlaybackSessionService.kt`**

```kotlin
package dev.selector.kivo_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.session.MediaButtonReceiver

/**
 * Foreground mediaPlayback service: owns the MediaSessionCompat and the
 * MediaStyle notification while audio plays in the background. All state
 * comes from [PlaybackSessionHub]; all actions go back to Dart through it.
 */
class PlaybackSessionService : Service() {
    companion object {
        private const val CHANNEL_ID = "kivo_playback"
        private const val NOTIFICATION_ID = 1001
        @Volatile private var instance: PlaybackSessionService? = null

        fun start(context: Context) {
            if (instance != null) { refresh(); return }
            val intent = Intent(context, PlaybackSessionService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun refresh() = instance?.updateFromHub()

        fun stop(context: Context) {
            instance?.let {
                // Boolean overload works on every supported API level (minSdk 21);
                // stopForeground(int) only exists from API 24.
                @Suppress("DEPRECATION")
                it.stopForeground(true)
                it.stopSelf()
            }
        }
    }

    private var session: MediaSessionCompat? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
        session = MediaSessionCompat(this, "KivoSession").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() = PlaybackSessionHub.invokeDart("play")
                override fun onPause() = PlaybackSessionHub.invokeDart("pause")
                override fun onSeekTo(pos: Long) =
                    PlaybackSessionHub.invokeDart("seekTo", mapOf("ms" to pos))
                override fun onRewind() =
                    PlaybackSessionHub.invokeDart("skip", mapOf("seconds" to -10))
                override fun onFastForward() =
                    PlaybackSessionHub.invokeDart("skip", mapOf("seconds" to 10))
                override fun onStop() = PlaybackSessionHub.invokeDart("stop")
            })
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        MediaButtonReceiver.handleIntent(session, intent)
        updateFromHub()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        session?.release()
        session = null
        instance = null
        super.onDestroy()
    }

    fun updateFromHub() {
        val s = session ?: return
        val playing = PlaybackSessionHub.playing
        s.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, PlaybackSessionHub.title)
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, PlaybackSessionHub.durationMs)
                .build()
        )
        s.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY or
                        PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_PLAY_PAUSE or
                        PlaybackStateCompat.ACTION_SEEK_TO or
                        PlaybackStateCompat.ACTION_REWIND or
                        PlaybackStateCompat.ACTION_FAST_FORWARD or
                        PlaybackStateCompat.ACTION_STOP
                )
                .setState(
                    if (playing) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                    PlaybackSessionHub.positionMs,
                    if (playing) 1.0f else 0.0f
                )
                .build()
        )
        val notification = buildNotification(playing)
        if (playing) {
            startForeground(NOTIFICATION_ID, notification)
        } else {
            // Paused: keep the notification but let the user swipe it away.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_DETACH)
            } else {
                @Suppress("DEPRECATION") stopForeground(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(playing: Boolean): Notification {
        val contentIntent = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val deleteIntent = MediaButtonReceiver.buildMediaButtonPendingIntent(
            this, PlaybackStateCompat.ACTION_STOP
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(PlaybackSessionHub.title)
            .setContentText(if (playing) "Reproduciendo" else "En pausa")
            .setContentIntent(contentIntent)
            .setDeleteIntent(deleteIntent)
            .setOngoing(playing)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(
                android.R.drawable.ic_media_rew, "-10s",
                MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_REWIND)
            )
            .addAction(
                if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (playing) "Pausa" else "Reproducir",
                MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_PLAY_PAUSE)
            )
            .addAction(
                android.R.drawable.ic_media_ff, "+10s",
                MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_FAST_FORWARD)
            )
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setMediaSession(session?.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Reproducción", NotificationManager.IMPORTANCE_LOW
            )
            channel.setShowBadge(false)
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }
}
```

- [ ] **Step 5: Register the channel in `MainActivity.kt`**

Inside `configureFlutterEngine`, next to the other channel registrations, add:

```kotlin
        // ── kivo/media_session ────────────────────────────────────────────────
        val sessionChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kivo/media_session")
        PlaybackSessionHub.channel = sessionChannel
        sessionChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    PlaybackSessionHub.update(
                        applicationContext,
                        call.argument<String>("title") ?: "Kivo",
                        (call.argument<Number>("positionMs") ?: 0).toLong(),
                        (call.argument<Number>("durationMs") ?: 0).toLong(),
                        call.argument<Boolean>("playing") ?: false,
                        call.argument<Boolean>("inBackground") ?: false,
                    )
                    result.success(null)
                }
                "end" -> {
                    PlaybackSessionHub.end(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
```

- [ ] **Step 6: Verify it compiles and nothing regressed**

Run: `flutter build apk --debug` → must complete with "Built build\app\outputs\flutter-apk\app-debug.apk".
Run: `flutter analyze` → clean. Run: `flutter test` → 224 passing (unchanged — no Dart changes in this task).

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/kotlin/dev/selector/kivo_player/PlaybackSessionHub.kt android/app/src/main/kotlin/dev/selector/kivo_player/PlaybackSessionService.kt android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt android/app/src/main/AndroidManifest.xml android/app/build.gradle*
git commit -m "feat: native media session — foreground service, MediaStyle notification, audio focus"
```

---

### Task 4: UI wiring — menu switch, AudioOnlyView, lifecycle unlock, main.dart

**Files:**
- Create: `lib/ui/player/audio_only/audio_only_view.dart`
- Modify: `lib/ui/player/more/more_menu.dart` (third row with Switch)
- Modify: `lib/ui/player/player_screen.dart` (remove background pause; mount AudioOnlyView; reset audio-only on dispose via cached notifier)
- Modify: `lib/app.dart` (instantiate the coordinator)
- Modify: `lib/main.dart` (mediaSessionProvider override)
- Test: `test/ui/player/audio_only_view_test.dart`

**Interfaces:**
- Consumes: `audioOnlyProvider`/`AudioOnlyNotifier.toggle()/.disable()` (Task 1); `backgroundPlaybackProvider` + `mediaSessionProvider`/`AndroidMediaSessionBridge` (Task 2); `controlsVisibleProvider`; `currentVideoProvider.displayName`; `KivoColors.gold`.
- Produces: `class AudioOnlyView extends ConsumerWidget` (black fill + waves/title center; `SizedBox.shrink()` when off).

- [ ] **Step 1: Create `lib/ui/player/audio_only/audio_only_view.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/background/audio_only.dart';
import '../../../player/open/video_source.dart';
import '../state/controls_visibility.dart';

/// Black surface shown over the (disabled) video while "Solo audio" is on.
/// The center content follows the controls' show/hide; the black fill is
/// permanent so a hidden-controls state is a near-black OLED-friendly screen.
class AudioOnlyView extends ConsumerWidget {
  const AudioOnlyView({super.key});

  static const _waveHeights = [12.0, 22.0, 34.0, 18.0, 26.0, 10.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(audioOnlyProvider);
    if (!on) return const SizedBox.shrink();
    final visible = ref.watch(controlsVisibleProvider);
    final title = ref.watch(currentVideoProvider)?.displayName ?? '';
    return IgnorePointer(
      child: Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final h in _waveHeights)
                    Container(
                      width: 5,
                      height: h,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: KivoColors.gold.withValues(
                            alpha: 0.5 + 0.5 * (h / 34.0)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'SOLO AUDIO',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.42),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Menu third row in `lib/ui/player/more/more_menu.dart`**

Inside the existing `Consumer` (added in 3c), after the "Bucle A-B" `_MenuRow`, add (plus the import `import '../../../player/background/audio_only.dart';`):

```dart
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF182036),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: sheetRef.watch(audioOnlyProvider)
                              ? const Color(0x29E8B84B)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(Icons.headphones_rounded,
                            size: 16,
                            color: sheetRef.watch(audioOnlyProvider)
                                ? KivoColors.gold
                                : Colors.white70),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Solo audio',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 1),
                            Text('Apagar el video, seguir escuchando',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.42), fontSize: 11)),
                          ],
                        ),
                      ),
                      Switch(
                        value: sheetRef.watch(audioOnlyProvider),
                        activeThumbColor: KivoColors.gold,
                        onChanged: (_) => ref.read(audioOnlyProvider.notifier).toggle(),
                      ),
                    ],
                  ),
                ),
```

(Requires `import '../../../core/theme/kivo_theme.dart';` — already imported there.)

- [ ] **Step 3: PlayerScreen changes (surgical — 3 edits only)**

In `lib/ui/player/player_screen.dart`:

1. In `didChangeAppLifecycleState`, DELETE only these lines (keep the `_saveProgress()` block above them intact):
```dart
    if (state == AppLifecycleState.paused) {
      _engine.pause(); // no background playback in Hito 1
    }
```
2. In the overlay `Stack`, add right AFTER the video `Positioned.fill` (the one containing the `Hero`/`Video`) and BEFORE the `PlayerGestures` line:
```dart
                      const Positioned.fill(child: AudioOnlyView()),
```
with the import `import 'audio_only/audio_only_view.dart';`.
3. Reset audio-only when leaving the player, per the never-`ref.read`-in-dispose rule: in `initState` (next to the other cached fields) add `_audioOnly = ref.read(audioOnlyProvider.notifier);` with the field `late final AudioOnlyNotifier _audioOnly;` (import `../../player/background/audio_only.dart`), and in `dispose()` add `_audioOnly.disable();` next to the existing `_engine.pause();` line.

- [ ] **Step 4: App wiring**

In `lib/app.dart` (`KivoApp.build`, first line of the method body): add

```dart
    ref.watch(backgroundPlaybackProvider); // instantiate the coordinator once
```

with the import `import 'player/background/background_playback.dart';`.

In `lib/main.dart`: add the override `mediaSessionProvider.overrideWithValue(AndroidMediaSessionBridge()),` to the `ProviderScope.overrides` list, with imports `import 'platform/android/android_media_session.dart';` and `import 'platform/media_session_provider.dart';`.

NOTE: instantiating the coordinator in every widget test that pumps `KivoApp` would require the bridge override — check whether any existing test pumps `KivoApp` directly (`grep -rn "KivoApp" test/`); if one does, add `mediaSessionProvider.overrideWithValue(FakeMediaSessionBridge())` to its overrides.

- [ ] **Step 5: Write the widget tests**

Create `test/ui/player/audio_only_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/background/audio_only.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/audio_only/audio_only_view.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
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

  testWidgets('hidden when audio-only is off; black surface + title when on', (tester) async {
    await pumpView(tester);
    expect(find.text('SOLO AUDIO'), findsNothing);
    c.read(audioOnlyProvider.notifier).toggle();
    c.read(controlsVisibleProvider.notifier).show();
    await tester.pump();
    expect(find.text('SOLO AUDIO'), findsOneWidget);
    expect(find.text('ep1.mkv'), findsOneWidget);
    expect(engine.videoTrackEnabled, false);
    // Drain the controls auto-hide timer.
    await tester.pump(const Duration(seconds: 4));
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
```

- [ ] **Step 6: Run tests, analyze, full suite**

Run: `flutter test test/ui/player/audio_only_view_test.dart` → PASS (2 tests).
Run: `flutter analyze` → clean. Run: `flutter test` → 226 passing (224 + 2). If PlayerScreen/mini-player/open-flow tests break because PlayerScreen now touches `audioOnlyProvider` (it shouldn't need new overrides — audioOnly only reads `playbackEngineProvider`, already overridden everywhere), make the minimal test-only fix and report it.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/player/audio_only/audio_only_view.dart lib/ui/player/more/more_menu.dart lib/ui/player/player_screen.dart lib/app.dart lib/main.dart test/ui/player/audio_only_view_test.dart
git commit -m "feat: audio-only view + menu switch + background playback unlocked"
```

---

## After all tasks

1. Whole-branch review (opus model) with extra scrutiny on: coordinator lifecycle (observer removed on dispose; `ref.listen` in provider body correctness; `_sessionActive` state machine can't leak a stuck notification); the native Hub/Service state sharing (`@Volatile` fields, service instance lifecycle, focus request/abandon pairing); the duck-vs-sleep-timer-fade volume interplay (both restore via `volumeMapping` — verify no clobber sequence worse than the spec's accepted edge case); and that `player_screen.dart` received only the three surgical edits.
2. Fix Critical/Important findings; record Minors in the ledger.
3. Build + install per the standing rule (`flutter build apk --release` + `adb install -r` + `am start`), then report the device checklist from spec §3 — the native side is ONLY verifiable on-device, so the checklist is the real acceptance gate here.
