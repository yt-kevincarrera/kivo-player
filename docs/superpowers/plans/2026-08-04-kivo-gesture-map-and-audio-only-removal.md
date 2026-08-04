# Gesture Map + "Solo audio" Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the "Solo audio" mode, fix the black screen that can survive a return to video, and teach the player's gestures and buttons with a 3-page gesture map shown on the first-ever video open.

**Architecture:** The map is a non-opaque `PageRouteBuilder` pushed on top of the player (not another overlay in the player's `Stack`), so the same screen works when reopened from Settings and the back button pops only the map. Its content is a pure function over `KivoSettings`, and its zone geometry comes from the same constants the real gestures use, promoted to public consts in `gesture_math.dart`. The black-cover fix moves the "has a decoded frame" decision into a pure stream transform that ignores width events while the video output is intentionally off.

**Tech Stack:** Flutter, Riverpod (`NotifierProvider`/`StateProvider`), media_kit 1.2.6 / media_kit_video 2.0.1, `flutter_test`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-04-kivo-gesture-map-and-audio-only-removal-design.md`.
- All user-facing strings are in **Spanish**; code, comments and commit messages in **English**.
- **Never add a `Co-Authored-By` trailer** to commits.
- **No new synchronous mpv calls on the UI thread.** Everything touching `NativePlayer.setProperty` stays `async` and un-awaited by UI code — the confirmed ANR path is `mpv_set_property_string` → `pthread_cond_wait`.
- Styling follows the existing player language: `black54` scrims, accent-outlined boxes/pills, accent from `settingsProvider.accentColor`, icons via `KivoIcon(KivoIcons.x, size: …, color: …)`.
- Run the full suite with `flutter test` (the project has ~395 tests; every task must leave it green).
- Do not delegate to further subagents.

---

### Task 1: Remove "Solo audio"

Mechanical but must be atomic — a partial removal does not compile.

**Files:**
- Delete: `lib/player/background/audio_only.dart`
- Delete: `lib/ui/player/audio_only/audio_only_view.dart`
- Delete: `test/player/background/audio_only_test.dart`
- Delete: `test/ui/player/audio_only_view_test.dart`
- Modify: `lib/core/icons/kivo_icons.dart:106` (remove `audioOnly`)
- Modify: `lib/ui/player/controls/bottom_bar.dart`
- Modify: `lib/ui/player/controls/controls_overlay.dart`
- Modify: `lib/ui/player/controls/top_bar.dart:76-88`
- Modify: `lib/ui/player/controls/info_overlay.dart:34`
- Modify: `lib/ui/player/gestures/player_gestures.dart:96-99`
- Modify: `lib/ui/player/player_screen.dart` (lines 18, 28, 69, 93, 367, 434-441, 528)
- Modify: `lib/player/background/background_playback.dart`
- Test: `test/player/background/should_have_media_session_test.dart:17-25`
- Test: `test/player/background/background_playback_test.dart`
- Test: `test/ui/player/player_gestures_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `bool shouldReleaseVideoForBackground({required bool hasVideo, required bool inPip})` — the `audioOnly` parameter is gone. Task 2 calls this same function.

- [x] **Step 1: Update the pure-function test first (it defines the new signature)**

In `test/player/background/should_have_media_session_test.dart`, replace the `shouldReleaseVideoForBackground` test with:

```dart
  test('shouldReleaseVideoForBackground: release the vo on background except in PiP', () {
    // A loaded video going to the background: release the vo before Android
    // tears the surface down.
    expect(shouldReleaseVideoForBackground(hasVideo: true, inPip: false), true);
    // Nothing loaded → nothing to release.
    expect(shouldReleaseVideoForBackground(hasVideo: false, inPip: false), false);
    // PiP shows the video → keep the vo alive.
    expect(shouldReleaseVideoForBackground(hasVideo: true, inPip: true), false);
  });
```

- [x] **Step 2: Run it to verify it fails**

Run: `flutter test test/player/background/should_have_media_session_test.dart`
Expected: FAIL — the call passes 2 named args to a function that requires 3 (`audioOnly` missing).

- [x] **Step 3: Change the function and the coordinator**

In `lib/player/background/background_playback.dart`:

```dart
/// Whether to release mpv's video output when going to the background. mpv
/// otherwise keeps the (about-to-be-destroyed) Android surface bound to its
/// video-output thread; when Android tears that surface down under a live vo,
/// mpv's core wedges and the next SYNCHRONOUS mpv call from the UI thread
/// deadlocks the app (confirmed ANR: main thread stuck in
/// `mpv_set_property_string`→`pthread_cond_wait`). Releasing the output while
/// mpv is still healthy — and reattaching on resume — keeps the surface from
/// being yanked out from under a live vo. Skip in PiP (video is shown there).
bool shouldReleaseVideoForBackground({
  required bool hasVideo,
  required bool inPip,
}) =>
    hasVideo && !inPip;
```

Update the call site in `didChangeAppLifecycleState`:

```dart
      if (shouldReleaseVideoForBackground(
        hasVideo: _ref.read(currentVideoProvider) != null,
        inPip: _ref.read(pipModeProvider),
      )) {
```

Remove the `import 'audio_only.dart';` line.

- [x] **Step 4: Strip the ducking path from the coordinator**

Ducking existed only to serve audio-only ("music-player listening"). Every other case pauses. In `lib/player/background/background_playback.dart`:

- Delete the fields `bool _ducking = false;` and `bool _duckUserAdjusted = false;`.
- Delete the whole `_ref.listen(volumePercentProvider, …)` block in `init()`.
- Delete `_restoreDuckIfActive()` and its calls in `_onFocusLoss` / `_onFocusTransientLoss`.
- Delete the `double get _userPlayerVolume` getter.
- In the `playingProvider` listener, drop the `&& !_ducking` term:

```dart
      } else if (!p && was && !_pausedByFocus) {
        _bridge.releaseAudioFocus();
      }
```

- Replace `_onDuckStart` / `_onDuckEnd` with:

```dart
  void _onDuckStart() {
    if (!_playing) return;
    // Ducking — lowering the volume but keeping playback — loses content for a
    // video just like a muted audiobook would, and a phone-call ring arrives as
    // a CAN_DUCK loss. Pause instead, and auto-resume when the duck ends.
    _pausedByFocus = true;
    _ref.read(playbackEngineProvider).pause();
  }

  void _onDuckEnd() {
    if (_pausedByFocus) {
      _ref.read(playbackEngineProvider).play();
      _pausedByFocus = false;
    }
  }
```

- Remove the now-unused imports: `../../core/settings/settings_provider.dart` and `../control/gesture_math.dart`. Keep `../control/player_controller.dart` (used by `onSkip`/`onSeek`).

- [x] **Step 5: Delete the mode's own files**

```bash
git rm lib/player/background/audio_only.dart lib/ui/player/audio_only/audio_only_view.dart test/player/background/audio_only_test.dart test/ui/player/audio_only_view_test.dart
```

Then remove the `audioOnly` icon from `lib/core/icons/kivo_icons.dart` (the `static final String audioOnly = _wrap(...)` block at line 106).

- [x] **Step 6: Collapse the UI branches**

`lib/ui/player/controls/controls_overlay.dart` — drop the `audio_only.dart` import, the `audioOnly` local, and the layout fork:

```dart
    final visible = ref.watch(controlsVisibleProvider);
```

and replace the `if (audioOnly) Positioned(…) else const Center(child: CenterControls())` block with just:

```dart
                    const Center(child: CenterControls()),
```

`lib/ui/player/controls/bottom_bar.dart` — drop the import and the `audioOnly` local; the aspect and rotate buttons become unconditional (remove the `if (!audioOnly) ...[` wrapper and its closing `]`), and the whole "Solo audio" `IconButton` (lines 78-98) is deleted. Also delete the stale comment at lines 25-26.

`lib/ui/player/controls/top_bar.dart` — drop the import and the `audioOnly` local; the PiP gate becomes:

```dart
            final supported = ref.watch(_pipSupportedProvider).value ?? false;
            if (!supported) return const SizedBox.shrink();
```

`lib/ui/player/controls/info_overlay.dart:34` — becomes:

```dart
    if (!settings.showInfoOverlay) {
```

(drop the import too).

`lib/ui/player/gestures/player_gestures.dart` — the center rotate band loses its guard:

```dart
    // Center band → swipe-to-rotate (discrete; fires on end), and only while the
    // controls are hidden so it can't steal a drag from someone aiming at them.
    _isCenterRotate =
        !ref.read(controlsVisibleProvider) && inCenterRotateZone(dx, _width);
```

(drop the `audio_only.dart` import).

`lib/ui/player/player_screen.dart` — remove: the two imports (lines 18 and 28), the `late final AudioOnlyNotifier _audioOnly;` field, its assignment in `initState`, the `_audioOnly.disable();` line in `dispose`, the whole `ref.listen(audioOnlyProvider, …)` block in `build`, and the `const Positioned.fill(child: AudioOnlyView()),` entry with its two comment lines.

- [x] **Step 7: Fix the remaining tests**

Run `flutter test` and fix every compile error from the removed symbols:
- `test/player/background/background_playback_test.dart` — drop the `audio_only.dart` import and any audio-only test; add a duck test:

```dart
  test('a duck request pauses and auto-resumes when the duck ends', () async {
    await setUpAll_();
    engine.emitPlaying(true);
    await pump();
    bridge.duckStart();
    await pump();
    expect(engine.lastPlayingCommand, false);
    bridge.duckEnd();
    await pump();
    expect(engine.lastPlayingCommand, true);
  });
```

If `FakeMediaSessionBridge` has no `duckStart()`/`duckEnd()` helpers, add them next to its existing callback-firing helpers in `test/fakes/fakes.dart` (they invoke the stored `MediaSessionCallbacks.onDuckStart` / `onDuckEnd`).

- `test/ui/player/player_gestures_test.dart` — drop the "center band is inert in audio-only" case and the import.

- [x] **Step 8: Run the full suite**

Run: `flutter test`
Expected: PASS, with 4+ fewer tests than before and zero references to `audioOnly` left:

```bash
git grep -n "audioOnly\|audio_only" -- lib test
```

Expected: no output.

- [x] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor(player): remove the Solo audio mode

Background playback and the mini-player already cover its use cases, and it
cost three bugs: overlapping centered overlays, a permanently black PiP window
(the coordinator only reattaches video it released itself), and a black screen
on return. Removing it leaves a single owner of mpv's vid property.

Ducking existed only for audio-only listening; a duck now always pauses and
auto-resumes, which was already the behavior for every other case."
```

---

### Task 2: Frame-ready gate + video-output reattach

**Files:**
- Create: `lib/player/engine/frame_ready.dart`
- Create: `test/player/engine/frame_ready_test.dart`
- Modify: `lib/player/engine/media_kit_engine.dart:40-42,160-165`
- Modify: `lib/player/engine/playback_engine.dart:29-34` (doc + new method)
- Modify: `lib/player/background/background_playback.dart` (resume + PiP reattach)
- Modify: `test/fakes/fakes.dart` (`FakePlaybackEngine.ensureVideoOutputAttached`)
- Test: `test/player/background/background_playback_test.dart`

**Interfaces:**
- Consumes: `shouldReleaseVideoForBackground({hasVideo, inPip})` from Task 1.
- Produces: `Stream<bool> frameReadyStream(Stream<int?> widthStream, bool Function() videoOutputEnabled)`, `bool shouldRetryVideoAttach({required bool enabled, required bool hasVideoSize})`, and `PlaybackEngine.ensureVideoOutputAttached() → Future<void>`.

- [x] **Step 1: Write the failing tests**

Create `test/player/engine/frame_ready_test.dart`:

```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/engine/frame_ready.dart';

void main() {
  test('a positive width means the open media has a decoded frame', () async {
    final widths = StreamController<int?>();
    final seen = <bool>[];
    frameReadyStream(widths.stream, () => true).listen(seen.add);
    widths.add(null);
    widths.add(1920);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [false, true]);
    await widths.close();
  });

  test('width events are dropped while the video output is intentionally off', () async {
    final widths = StreamController<int?>();
    var enabled = true;
    final seen = <bool>[];
    frameReadyStream(widths.stream, () => enabled).listen(seen.add);
    widths.add(1920);
    await Future<void>.delayed(Duration.zero);
    // vid=no: mpv nulls the width, but the cover belongs to the open sequence —
    // this must NOT arm it.
    enabled = false;
    widths.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [true]);
    // Reattached: real events flow again.
    enabled = true;
    widths.add(1280);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [true, true]);
    await widths.close();
  });

  test('shouldRetryVideoAttach: only when enabled and mpv reports no size', () {
    expect(shouldRetryVideoAttach(enabled: true, hasVideoSize: false), true);
    expect(shouldRetryVideoAttach(enabled: true, hasVideoSize: true), false);
    expect(shouldRetryVideoAttach(enabled: false, hasVideoSize: false), false);
  });
}
```

- [x] **Step 2: Run to verify it fails**

Run: `flutter test test/player/engine/frame_ready_test.dart`
Expected: FAIL — `frame_ready.dart` does not exist.

- [x] **Step 3: Write the pure helpers**

Create `lib/player/engine/frame_ready.dart`:

```dart
/// Maps mpv's video-width events to "the open media has a decoded frame".
///
/// The UI uses this to cover the shared texture's stale last frame across an
/// open. `vid=no` — how the video output is released before Android tears the
/// surface down, see `shouldReleaseVideoForBackground` — also nulls the width,
/// which is indistinguishable from "a fresh open has not decoded yet". Events
/// that arrive while the output is intentionally off are therefore DROPPED: the
/// cover belongs to the open sequence (PlayerScreen re-arms it explicitly on
/// every open), never to the `vid` property. Without this, returning from the
/// background could leave the black cover armed forever.
Stream<bool> frameReadyStream(
  Stream<int?> widthStream,
  bool Function() videoOutputEnabled,
) =>
    widthStream.where((_) => videoOutputEnabled()).map((w) => (w ?? 0) > 0);

/// Whether a just-reattached video output needs a nudge. mpv can fail to bring
/// its output back after the Android surface it held was destroyed, leaving a
/// black texture with no width ever reported. True → re-apply `vid=auto` and
/// force a frame.
bool shouldRetryVideoAttach({
  required bool enabled,
  required bool hasVideoSize,
}) =>
    enabled && !hasVideoSize;
```

- [x] **Step 4: Run to verify it passes**

Run: `flutter test test/player/engine/frame_ready_test.dart`
Expected: PASS (3 tests).

- [x] **Step 5: Add `ensureVideoOutputAttached` to the interface**

In `lib/player/engine/playback_engine.dart`, update the `hasVideoFrameStream` doc (drop the "Stays false for audio-only" sentence) and add:

```dart
  /// Safety net for the background round-trip: if mpv has not brought its video
  /// output back shortly after [setVideoTrackEnabled]`(true)`, nudge it once.
  /// Fire-and-forget — never await this from UI code.
  Future<void> ensureVideoOutputAttached();
```

- [x] **Step 6: Wire the engine**

In `lib/player/engine/media_kit_engine.dart`, add the import `import 'frame_ready.dart';`, the field, and replace the two members:

```dart
  /// Mirrors our own `vid` intent so [hasVideoFrameStream] can ignore the width
  /// events that `vid=no` produces (see [frameReadyStream]).
  bool _videoOutputEnabled = true;

  @override
  Stream<bool> get hasVideoFrameStream =>
      frameReadyStream(_player.stream.width, () => _videoOutputEnabled);

  @override
  Future<void> setVideoTrackEnabled(bool enabled) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    // Flip the gate BEFORE the property write, so no width event can slip
    // through with the flag in the wrong state.
    _videoOutputEnabled = enabled;
    await native.setProperty('vid', enabled ? 'auto' : 'no');
  }

  @override
  Future<void> ensureVideoOutputAttached() async {
    if (!_videoOutputEnabled) return;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!shouldRetryVideoAttach(
      enabled: _videoOutputEnabled,
      hasVideoSize: videoSize != null,
    )) {
      return;
    }
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    // One retry, no loops: re-apply the property and force a frame.
    await native.setProperty('vid', 'auto');
    await _player.seek(_player.state.position);
  }
```

- [x] **Step 7: Add the fake's override**

In `test/fakes/fakes.dart`, next to `videoTrackEnabled`:

```dart
  int ensureAttachCalls = 0;

  @override
  Future<void> ensureVideoOutputAttached() async => ensureAttachCalls++;
```

- [x] **Step 8: Write the failing coordinator test**

In `test/player/background/background_playback_test.dart`:

```dart
  test('returning from the background reattaches the video output and nudges mpv', () async {
    await setUpAll_();
    engine.emitPlaying(true);
    await pump();
    coord.didChangeAppLifecycleState(AppLifecycleState.paused);
    await pump();
    expect(engine.videoTrackEnabled, false);
    coord.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pump();
    expect(engine.videoTrackEnabled, true);
    expect(engine.ensureAttachCalls, 1);
  });
```

- [x] **Step 9: Run to verify it fails**

Run: `flutter test test/player/background/background_playback_test.dart`
Expected: FAIL — `ensureAttachCalls` is 0 (the coordinator does not call it yet).

- [x] **Step 10: Call it from the coordinator**

In `lib/player/background/background_playback.dart`, in `didChangeAppLifecycleState`'s `resumed` branch:

```dart
      if (_videoReleasedForBackground) {
        final engine = _ref.read(playbackEngineProvider);
        engine.setVideoTrackEnabled(true);
        // Safety net if mpv does not bring its output back on its own.
        engine.ensureVideoOutputAttached();
        _videoReleasedForBackground = false;
      }
```

And in the `pipModeProvider` listener's reattach (same failure mode — a black PiP window):

```dart
      if (inPip && _videoReleasedForBackground) {
        final engine = _ref.read(playbackEngineProvider);
        engine.setVideoTrackEnabled(true);
        engine.ensureVideoOutputAttached();
        _videoReleasedForBackground = false;
      }
```

- [x] **Step 11: Run the full suite**

Run: `flutter test`
Expected: PASS — including `test/ui/player/video_ready_test.dart` **unchanged** (a fresh open still re-arms the cover, because `_openSession` seeds it explicitly).

- [x] **Step 12: Commit**

```bash
git add -A
git commit -m "fix(player): stop vid=no from arming the stale-frame cover forever

The black cover was driven by mpv's width, which vid=no nulls — so releasing
the video output for the background could leave the player black after a
return, with nothing to lower it again. The cover now belongs to the open
sequence: frameReadyStream drops width events that arrive while the output is
intentionally off. Adds a one-shot reattach nudge for the case where mpv itself
fails to bring its output back."
```

---

### Task 3: Persisted `gestureMapShown` flag

**Files:**
- Modify: `lib/core/settings/kivo_settings.dart` (lines ~46, ~95, ~145, ~197, ~250, ~303, ~355)
- Test: `test/core/settings/kivo_settings_test.dart` (create if absent)

**Interfaces:**
- Produces: `KivoSettings.gestureMapShown` (bool, default `false`), settable via `copyWith(gestureMapShown: true)`.

- [x] **Step 1: Write the failing test**

Add to the settings test file (create it with the usual imports if it does not exist):

```dart
  test('gestureMapShown defaults to false and survives a JSON round-trip', () {
    final d = KivoSettings.defaults();
    expect(d.gestureMapShown, false);
    final shown = d.copyWith(gestureMapShown: true);
    expect(KivoSettings.fromJson(shown.toJson()).gestureMapShown, true);
    // A settings blob written before this flag existed reads as "not shown".
    final legacy = Map<String, Object?>.from(d.toJson())..remove('gestureMapShown');
    expect(KivoSettings.fromJson(legacy).gestureMapShown, false);
  });
```

If the existing file uses different constructor/serialization helper names, match them — check the top of `kivo_settings.dart` first.

- [x] **Step 2: Run to verify it fails**

Run: `flutter test test/core/settings/kivo_settings_test.dart`
Expected: FAIL — `gestureMapShown` is not defined.

- [x] **Step 3: Add the field in all six places**

Follow `offeredAllFilesAccess` exactly. Field declaration next to the other one-shot flags:

```dart
  final bool gestureMapShown;
```

constructor `required this.gestureMapShown,` · `defaults()` → `gestureMapShown: false,` · `copyWith` param `bool? gestureMapShown,` and body `gestureMapShown: gestureMapShown ?? this.gestureMapShown,` · `toJson` → `'gestureMapShown': gestureMapShown,` · `fromJson` → `gestureMapShown: m['gestureMapShown'] ?? d.gestureMapShown,`.

- [x] **Step 4: Run to verify it passes**

Run: `flutter test test/core/settings/kivo_settings_test.dart`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(settings): add the gestureMapShown one-shot flag"
```

---

### Task 4: Public gesture-zone constants

The map must draw the zones the gestures actually use, so both read one source.

**Files:**
- Modify: `lib/player/control/gesture_math.dart:3,97-108`
- Modify: `lib/ui/player/gestures/player_gestures.dart:51-52`
- Test: `test/player/control/gesture_math_test.dart`

**Interfaces:**
- Produces: `kTapCenterStart = 0.33`, `kTapCenterEnd = 0.67`, `kCenterRotateFraction = 0.30`, `kLateralEdgeMargin = 38.0`, `kVerticalDeadMargin = 24.0`.

- [x] **Step 1: Write the failing test**

Add to `test/player/control/gesture_math_test.dart`:

```dart
  test('zone constants are the ones the zone functions use', () {
    // The gesture map draws from these; a drift here would draw a lie.
    expect(tapZoneOf(kTapCenterStart + 0.01), TapZone.center);
    expect(tapZoneOf(kTapCenterStart - 0.01), TapZone.left);
    expect(tapZoneOf(kTapCenterEnd + 0.01), TapZone.right);
    // Rotate band: inside at the center, outside just past half the fraction.
    expect(inCenterRotateZone(50, 100), true);
    expect(inCenterRotateZone(50 + 100 * kCenterRotateFraction / 2 + 1, 100), false);
    // Lateral edges and vertical dead zone.
    expect(inLateralDeadZone(kLateralEdgeMargin - 1, 400, kLateralEdgeMargin), true);
    expect(inLateralDeadZone(200, 400, kLateralEdgeMargin), false);
    expect(inVerticalDeadZone(kVerticalDeadMargin - 1, 800, 0, 0, kVerticalDeadMargin), true);
  });
```

- [x] **Step 2: Run to verify it fails**

Run: `flutter test test/player/control/gesture_math_test.dart`
Expected: FAIL — the `k…` constants are undefined.

- [x] **Step 3: Add the constants and use them as the defaults**

In `lib/player/control/gesture_math.dart`:

```dart
/// Tap zones as fractions of the width: the double-tap bands are THIRDS.
const double kTapCenterStart = 0.33;
const double kTapCenterEnd = 0.67;

/// Width fraction of the center band that owns swipe-to-rotate.
const double kCenterRotateFraction = 0.30;

/// Lateral strip (logical px) that owns swipe-to-minimize.
const double kLateralEdgeMargin = 38.0;

/// Top/bottom strip (logical px) where vertical drags are ignored so they
/// cannot fight the system gesture areas or the control bars.
const double kVerticalDeadMargin = 24.0;

TapZone tapZoneOf(double dxFraction,
    {double centerStart = kTapCenterStart, double centerEnd = kTapCenterEnd}) {
```

and in `inCenterRotateZone`, make the default `[double fraction = kCenterRotateFraction]`.

In `lib/ui/player/gestures/player_gestures.dart`, replace the two private fields with the shared constants:

```dart
  static const _deadMargin = kVerticalDeadMargin;
  static const _lateralMargin = kLateralEdgeMargin;
```

- [x] **Step 4: Run to verify it passes**

Run: `flutter test test/player/control/gesture_math_test.dart && flutter test test/ui/player/player_gestures_test.dart`
Expected: PASS both.

- [x] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(gestures): promote the zone constants so the gesture map can draw them"
```

---

### Task 5: Gesture map content (pure)

**Files:**
- Create: `lib/ui/player/tutorial/gesture_map_content.dart`
- Create: `test/ui/player/tutorial/gesture_map_content_test.dart`

**Interfaces:**
- Consumes: `KivoSettings` (Task 3's field is not needed here).
- Produces: `enum MapZone { leftThird, centerThird, rightThird, leftHalf, rightHalf, centerBand, lateralEdges, fullWidth, footer, topBar, bottomBar }`, `enum HintArrow { vertical, horizontal, down }`, `enum MapIcon { back, info, subtitles, pip, audio, more, speed, lock, aspect, rotate }`, `class GestureHint { MapZone zone; String label; HintArrow? arrow; MapIcon? icon; }`, `class GestureMapPage { String title; List<GestureHint> hints; }`, and `List<GestureMapPage> gestureMapPages(KivoSettings s, {required bool pipSupported})`.

- [x] **Step 1: Write the failing tests**

Create `test/ui/player/tutorial/gesture_map_content_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/ui/player/tutorial/gesture_map_content.dart';

void main() {
  KivoSettings base() => KivoSettings.defaults();

  List<String> labelsOf(GestureMapPage p) => p.hints.map((h) => h.label).toList();

  test('three pages, in teaching order', () {
    final pages = gestureMapPages(base(), pipSupported: true);
    expect(pages.length, 3);
    expect(pages[0].title, 'Toques');
    expect(pages[1].title, 'Arrastres');
    expect(pages[2].title, 'Botones');
  });

  test('tap labels use the configured skip amounts', () {
    final pages = gestureMapPages(
        base().copyWith(doubleTapSkipLeft: 15, doubleTapSkipRight: 30),
        pipSupported: true);
    expect(labelsOf(pages[0]), contains('Doble toque · −15 s'));
    expect(labelsOf(pages[0]), contains('Doble toque · +30 s'));
  });

  test('the center-pause hint disappears when the setting is off', () {
    final on = gestureMapPages(base().copyWith(doubleTapCenterPause: true), pipSupported: true);
    final off = gestureMapPages(base().copyWith(doubleTapCenterPause: false), pipSupported: true);
    expect(on[0].hints.any((h) => h.zone == MapZone.centerThird), true);
    expect(off[0].hints.any((h) => h.zone == MapZone.centerThird), false);
  });

  test('the seek hint disappears when horizontal seek is off', () {
    final off = gestureMapPages(base().copyWith(horizontalSeek: false), pipSupported: true);
    expect(labelsOf(off[1]).any((l) => l.contains('Buscar')), false);
  });

  test('drag labels use the configured boost cap and hold speed', () {
    final pages = gestureMapPages(
        base().copyWith(volumeBoostMax: 150, holdLeftSpeed: 2.5),
        pipSupported: true);
    expect(labelsOf(pages[1]), contains('Arrastra · Volumen (hasta 150%)'));
    expect(labelsOf(pages[1]).any((l) => l.contains('2.5×')), true);
  });

  test('PiP is only listed when the device supports it', () {
    final yes = gestureMapPages(base(), pipSupported: true);
    final no = gestureMapPages(base(), pipSupported: false);
    expect(yes[2].hints.any((h) => h.icon == MapIcon.pip), true);
    expect(no[2].hints.any((h) => h.icon == MapIcon.pip), false);
  });

  test('every button hint carries an icon and a bar zone', () {
    final buttons = gestureMapPages(base(), pipSupported: true)[2].hints;
    for (final h in buttons.where((h) => h.zone != MapZone.footer)) {
      expect(h.icon, isNotNull, reason: h.label);
      expect(h.zone, anyOf(MapZone.topBar, MapZone.bottomBar));
    }
  });
}
```

- [x] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/player/tutorial/gesture_map_content_test.dart`
Expected: FAIL — `gesture_map_content.dart` does not exist.

- [x] **Step 3: Write the content**

Create `lib/ui/player/tutorial/gesture_map_content.dart`:

```dart
import '../../../core/settings/kivo_settings.dart';

/// Where a hint is anchored. The thirds and the halves are BOTH real: double
/// taps use thirds (`tapZoneOf`) while brightness/volume drags split the screen
/// down the middle — which is exactly why the map separates them by page.
enum MapZone {
  leftThird,
  centerThird,
  rightThird,
  leftHalf,
  rightHalf,
  centerBand,
  lateralEdges,
  fullWidth,
  footer,
  topBar,
  bottomBar,
}

/// The arrow drawn inside a zone, if any.
enum HintArrow { vertical, horizontal, down }

/// Icon slots the map page maps to [KivoIcons]. Kept as an enum so this file
/// stays pure Dart with no Flutter dependency.
enum MapIcon { back, info, subtitles, pip, audio, more, speed, lock, aspect, rotate }

class GestureHint {
  final MapZone zone;
  final String label;
  final HintArrow? arrow;
  final MapIcon? icon;
  const GestureHint(this.zone, this.label, {this.arrow, this.icon});
}

class GestureMapPage {
  final String title;
  final List<GestureHint> hints;
  const GestureMapPage(this.title, this.hints);
}

String _speed(double v) =>
    '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)}×';

/// The whole tutorial, derived from what the user actually has configured: the
/// numbers come from [s], and a gesture the user turned OFF is not taught.
List<GestureMapPage> gestureMapPages(
  KivoSettings s, {
  required bool pipSupported,
}) =>
    [
      GestureMapPage('Toques', [
        GestureHint(MapZone.leftThird, 'Doble toque · −${s.doubleTapSkipLeft} s'),
        if (s.doubleTapCenterPause)
          const GestureHint(MapZone.centerThird, 'Doble toque · Pausa'),
        GestureHint(MapZone.rightThird, 'Doble toque · +${s.doubleTapSkipRight} s'),
        const GestureHint(
            MapZone.footer, 'Un toque · Mostrar u ocultar los controles'),
      ]),
      GestureMapPage('Arrastres', [
        const GestureHint(MapZone.leftHalf, 'Arrastra · Brillo',
            arrow: HintArrow.vertical),
        GestureHint(MapZone.rightHalf,
            'Arrastra · Volumen (hasta ${s.volumeBoostMax}%)',
            arrow: HintArrow.vertical),
        if (s.horizontalSeek)
          const GestureHint(
              MapZone.fullWidth, 'Arrastra · Buscar con vista previa',
              arrow: HintArrow.horizontal),
        const GestureHint(MapZone.lateralEdges,
            'Arrastra en el borde · Minimizar',
            arrow: HintArrow.down),
        const GestureHint(MapZone.centerBand,
            'Arrastra en el centro · Girar (con los controles ocultos)',
            arrow: HintArrow.vertical),
        GestureHint(MapZone.footer,
            'Mantén pulsado a la izquierda · ${_speed(s.holdLeftSpeed)}'),
        const GestureHint(MapZone.footer,
            'Mantén y desliza arriba o abajo a la derecha · Escalera de velocidad'),
      ]),
      GestureMapPage('Botones', [
        const GestureHint(MapZone.topBar, 'Minimizar a la mini-barra',
            icon: MapIcon.back),
        const GestureHint(MapZone.topBar, 'Información en pantalla',
            icon: MapIcon.info),
        const GestureHint(MapZone.topBar, 'Subtítulos', icon: MapIcon.subtitles),
        if (pipSupported)
          const GestureHint(MapZone.topBar, 'Imagen en imagen', icon: MapIcon.pip),
        const GestureHint(MapZone.topBar, 'Pistas de audio', icon: MapIcon.audio),
        const GestureHint(MapZone.topBar,
            'Más opciones · temporizador y bucle A-B',
            icon: MapIcon.more),
        const GestureHint(MapZone.bottomBar, 'Velocidad', icon: MapIcon.speed),
        const GestureHint(MapZone.bottomBar, 'Bloquear la pantalla',
            icon: MapIcon.lock),
        const GestureHint(MapZone.bottomBar, 'Relación de aspecto',
            icon: MapIcon.aspect),
        const GestureHint(MapZone.bottomBar, 'Rotar', icon: MapIcon.rotate),
        const GestureHint(MapZone.footer,
            'Con más de un video en la carpeta aparece la cola sobre los botones'),
      ]),
    ];
```

- [x] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/player/tutorial/gesture_map_content_test.dart`
Expected: PASS (7 tests).

- [x] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(tutorial): pure content for the gesture map, derived from the user's settings"
```

---

### Task 6: Gesture map page and route

**Files:**
- Create: `lib/ui/player/tutorial/gesture_map_page.dart`
- Create: `lib/ui/player/tutorial/gesture_map_route.dart`
- Create: `test/ui/player/tutorial/gesture_map_page_test.dart`
- Modify: `lib/platform/pip_controller_provider.dart` (add the public provider)
- Modify: `lib/ui/player/controls/top_bar.dart:14,77` (use it)

**Interfaces:**
- Consumes: Task 5's content types; `kTapCenterStart`, `kTapCenterEnd`, `kCenterRotateFraction`, `kLateralEdgeMargin` from Task 4.
- Produces: `Route<void> gestureMapRoute()`, `class GestureMapScreen extends ConsumerStatefulWidget`, `final pipSupportedProvider = FutureProvider<bool>(…)`.

- [x] **Step 1: Write the failing widget test**

Create `test/ui/player/tutorial/gesture_map_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/pip_controller_provider.dart';
import 'package:kivo_player/ui/player/tutorial/gesture_map_route.dart';
import '../../../fakes/fakes.dart';

void main() {
  testWidgets('pages through the map and Entendido closes it', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    var popped = false;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
        pipControllerProvider.overrideWithValue(FakePipController()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              await Navigator.of(context).push(gestureMapRoute());
              popped = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Page 1.
    expect(find.text('Toques'), findsOneWidget);
    expect(find.textContaining('Doble toque · −10 s'), findsOneWidget);

    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Arrastres'), findsOneWidget);

    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Botones'), findsOneWidget);

    // Last page closes.
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(popped, true);
    expect(find.text('Botones'), findsNothing);
  });
}
```

- [x] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/player/tutorial/gesture_map_page_test.dart`
Expected: FAIL — `gesture_map_route.dart` does not exist.

- [x] **Step 3: Promote the PiP-support provider**

The page needs it and it is currently private to the top bar. In `lib/platform/pip_controller_provider.dart` add:

```dart
/// Whether the device supports picture-in-picture. Shared by the player's top
/// bar and the gesture map (both hide PiP when it is unavailable).
final pipSupportedProvider =
    FutureProvider<bool>((ref) => ref.read(pipControllerProvider).isSupported());
```

In `lib/ui/player/controls/top_bar.dart`, delete the private `_pipSupportedProvider` (line 14) and read the shared one at line 77:

```dart
            final supported = ref.watch(pipSupportedProvider).value ?? false;
```

- [x] **Step 4: Write the page**

Create `lib/ui/player/tutorial/gesture_map_page.dart`. Requirements, all verifiable from the test above plus the Global Constraints:

- `GestureMapScreen` is a `ConsumerStatefulWidget` holding a `PageController` and the current page index.
- Content comes from `gestureMapPages(ref.watch(settingsProvider), pipSupported: ref.watch(pipSupportedProvider).value ?? false)`.
- Root is a `Scaffold(backgroundColor: Colors.transparent)` over a `ColoredBox(color: Colors.black.withValues(alpha: 0.72))` scrim, so the paused video shows through.
- Each page is a `Stack` of zone boxes sized from the shared constants against `LayoutBuilder`'s width/height:
  - `leftThird` → `0 … kTapCenterStart × w`; `centerThird` → `kTapCenterStart × w … kTapCenterEnd × w`; `rightThird` → `kTapCenterEnd × w … w`.
  - `leftHalf` → `0 … w/2`; `rightHalf` → `w/2 … w`.
  - `centerBand` → centered, width `kCenterRotateFraction × w`.
  - `lateralEdges` → two strips of `kLateralEdgeMargin` at both edges.
  - `fullWidth` → the full width, drawn as a band across the vertical middle.
  - `topBar` / `bottomBar` → a mock bar pinned top / bottom containing the hints' icons in order (`MapIcon` → `KivoIcons.back/info/subtitles/pip/audio/more/speed/lock/aspect/rotate`) with the label beneath each.
  - `footer` → plain rows in a column above the buttons.
- A zone box is an accent-outlined rounded rect (`Border.all(color: accent.withValues(alpha: 0.5))`, `BorderRadius.circular(14)`, fill `accent.withValues(alpha: 0.06)`) with the label centered inside; `HintArrow` draws `Icons.swap_vert` (vertical), `Icons.swap_horiz` (horizontal) or `Icons.south` (down) above the label.
- Header: the page title in the accent color, uppercase, matching `_label` in the settings sections (`fontSize: 10.5, letterSpacing: 1.4, fontWeight: FontWeight.w700`).
- Footer: page dots (filled = current) and one button — `Siguiente` on pages 1-2, `Entendido` on the last — which advances the `PageController` or `Navigator.of(context).pop()`s.
- Everything wrapped in `SafeArea`.

- [x] **Step 5: Write the route**

Create `lib/ui/player/tutorial/gesture_map_route.dart`:

```dart
import 'package:flutter/material.dart';
import 'gesture_map_page.dart';

/// Route for the gesture map. **Non-opaque** so the paused video (or the
/// settings screen, when reopened from there) keeps painting behind the scrim.
///
/// It is a route and not another entry in PlayerScreen's overlay Stack on
/// purpose: the back button then pops only the map — the player's PopScope
/// (which minimizes to the mini-bar) never sees it — and the exact same screen
/// works with no player underneath.
Route<void> gestureMapRoute() => PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) => const GestureMapScreen(),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );
```

- [x] **Step 6: Run to verify it passes**

Run: `flutter test test/ui/player/tutorial/gesture_map_page_test.dart`
Expected: PASS.

- [x] **Step 7: Run the full suite**

Run: `flutter test`
Expected: PASS (the top-bar change must not break its tests).

- [x] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(tutorial): the gesture map screen and its non-opaque route

Zones are drawn from the same constants the real gestures use, so the drawing
cannot drift from the behavior."
```

---

### Task 7: Show it on the first-ever video

**Files:**
- Modify: `lib/ui/player/player_screen.dart` (`_start`)
- Test: `test/ui/player/gesture_map_first_open_test.dart`

**Interfaces:**
- Consumes: `gestureMapRoute()` (Task 6), `KivoSettings.gestureMapShown` (Task 3).
- Produces: nothing.

- [x] **Step 1: Write the failing test**

Create `test/ui/player/gesture_map_first_open_test.dart`, reusing the container setup from `test/ui/player/video_ready_test.dart` (copy its `NoopControls` and `_container` helpers verbatim — same overrides):

```dart
  testWidgets('the first ever open pauses and shows the gesture map, then resumes', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final store = InMemorySettingsStore();
    final s = await SettingsService.load(store);
    final c = _container(engine, s);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: PlayerScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Toques'), findsOneWidget);
    expect(engine.lastPlayingCommand, false); // paused for the tutorial

    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();

    expect(find.text('Botones'), findsNothing);
    expect(engine.lastPlayingCommand, true); // resumed
    expect(c.read(settingsProvider).gestureMapShown, true); // persisted on close

    await tester.pump(const Duration(seconds: 4)); // drain timers
  });

  testWidgets('a later open does not show the map', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(gestureMapShown: true));
    final c = _container(engine, s);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: PlayerScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Toques'), findsNothing);

    await tester.pump(const Duration(seconds: 4));
  });
```

Add the imports the helpers need plus `package:kivo_player/ui/player/tutorial/gesture_map_route.dart` is **not** needed (the map is reached through the screen). If `SettingsService.update` has a different name, match the real API.

- [x] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/player/gesture_map_first_open_test.dart`
Expected: FAIL on the first test — "Toques" is not found (nothing pushes the map).

- [x] **Step 3: Add the trigger**

In `lib/ui/player/player_screen.dart`, add the import `import 'tutorial/gesture_map_route.dart';` and, at the end of `_start()` (after the rate is applied), append:

```dart
    await _maybeShowGestureMap();
  }

  /// First video ever: teach the gestures before the user pokes at random. The
  /// map is a route on top of the player, so the back button closes only it.
  /// The flag is persisted on CLOSE, not on show — a force-kill mid-tutorial
  /// must not cost the user the tutorial forever.
  Future<void> _maybeShowGestureMap() async {
    if (!mounted) return;
    if (ref.read(settingsProvider).gestureMapShown) return;
    _engine.pause();
    await Navigator.of(context).push(gestureMapRoute());
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    await ref
        .read(settingsProvider.notifier)
        .set(settings.copyWith(gestureMapShown: true));
    if (!mounted) return;
    _engine.play();
  }
```

- [x] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/player/gesture_map_first_open_test.dart`
Expected: PASS (2 tests).

- [x] **Step 5: Run the full suite**

Run: `flutter test`
Expected: PASS. If other player-screen widget tests now find an unexpected map (they use fresh `InMemorySettingsStore`s, so `gestureMapShown` is false), fix them by seeding `gestureMapShown: true` in their settings — the map is expected behavior on a virgin install, so the tests must opt out, not the feature.

- [x] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(tutorial): show the gesture map on the first ever video open"
```

---

### Task 8: Reopen it from Settings

**Files:**
- Modify: `lib/ui/settings/sections/playback_gestures_section.dart`
- Test: `test/ui/settings/gesture_map_entry_test.dart`

**Interfaces:**
- Consumes: `gestureMapRoute()` (Task 6).
- Produces: nothing.

- [x] **Step 1: Write the failing test**

Create `test/ui/settings/gesture_map_entry_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/pip_controller_provider.dart';
import 'package:kivo_player/ui/settings/sections/playback_gestures_section.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('the settings row opens the gesture map', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
        pipControllerProvider.overrideWithValue(FakePipController()),
      ],
      child: const MaterialApp(home: PlaybackGesturesSection()),
    ));

    await tester.tap(find.text('Ver el mapa de gestos'));
    await tester.pumpAndSettle();
    expect(find.text('Toques'), findsOneWidget);
  });
}
```

If the row sits below the fold, scroll to it first with
`await tester.scrollUntilVisible(find.text('Ver el mapa de gestos'), 300);`.

- [x] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/settings/gesture_map_entry_test.dart`
Expected: FAIL — no widget with that text.

- [x] **Step 3: Add the row**

In `lib/ui/settings/sections/playback_gestures_section.dart`, add the imports (`../../player/tutorial/gesture_map_route.dart`, `../../../core/icons/kivo_icons.dart`) and, as the FIRST card in the `ListView` (before `Doble toque` — it is the overview of everything below it):

```dart
          _label(context, 'Aprender'),
          SettingsCard(children: [
            SettingNavRow(
              icon: KivoIcons.info,
              title: 'Ver el mapa de gestos',
              subtitle: 'Toques, arrastres y botones del reproductor',
              onTap: () => Navigator.of(context).push(gestureMapRoute()),
            ),
          ]),
          const SizedBox(height: 16),
```

Check `SettingNavRow`'s constructor at `lib/ui/settings/widgets/setting_tiles.dart:34` and match the `icon` parameter's real type (a `KivoIcons` SVG string vs an `IconData`).

- [x] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/settings/gesture_map_entry_test.dart`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(settings): reopen the gesture map from Reproducción y gestos"
```

---

### Task 9: Verify and ship to the device

**Files:** none (verification only).

- [x] **Step 1: Full suite + analyzer**

Run: `flutter analyze && flutter test`
Expected: no analyzer issues (dead imports from Task 1 would show here), all tests pass.

- [x] **Step 2: Confirm the mode is really gone**

Run: `git grep -n "audioOnly\|audio_only\|Solo audio" -- lib test`
Expected: no output.

- [x] **Step 3: Build and install the release APK on the Pixel 6**

```bash
flutter build apk --release && adb -s 24231FDF6006ST install -r build/app/outputs/flutter-apk/app-release.apk
```

Expected: `Success`.

- [x] **Step 4: Hand the device checklist to the user**

Report these as the things only a human on the device can confirm:
1. First open on a fresh install (clear app data) shows the map, pauses, and resumes on `Entendido`; a second open does not show it.
2. Ajustes › Reproducción y gestos › Ver el mapa de gestos reopens it.
3. The labels match their configured skip/boost/hold values.
4. No "Solo audio" button in the bottom bar; aspect and rotate always present.
5. Minimize → background → return: the video comes back (no black screen), including from PiP.

---

## Self-Review

**Spec coverage:** §1 removal → Task 1. §2a cover fix → Task 2 (steps 1-6, 11). §2b reattach net → Task 2 (steps 5-10). §3 route-not-overlay → Task 6. §3 geometry from truth → Task 4 + Task 6 step 4. §3 content/3 pages/settings-derived labels → Task 5. §3 files → Tasks 5-6. §3 trigger + persist-on-close → Task 7. §3 Settings entry → Task 8. §4 tests → distributed across each task, plus Task 9 for the suite and device checks.

**Type consistency:** `shouldReleaseVideoForBackground({hasVideo, inPip})` is defined in Task 1 and consumed in Task 2. `frameReadyStream`/`shouldRetryVideoAttach` are defined in Task 2 step 3 and used in step 6. `MapZone`/`HintArrow`/`MapIcon`/`GestureHint`/`GestureMapPage`/`gestureMapPages` are defined in Task 5 and consumed in Task 6. `gestureMapRoute()` is defined in Task 6 and consumed in Tasks 7 and 8. `pipSupportedProvider` is defined in Task 6 step 3 and used in the same task's page and in `top_bar`. `gestureMapShown` is defined in Task 3 and used in Task 7.

**Known lookups left to the implementer** (each with the file:line to check, not a guess to invent): `SettingNavRow`'s `icon` parameter type (Task 8 step 3), `FakeMediaSessionBridge`'s duck helpers (Task 1 step 7), the settings test file's existing helper names (Task 3 step 1).
