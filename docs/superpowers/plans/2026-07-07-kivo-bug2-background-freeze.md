# Bug 2 — Background Freeze Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the freeze/ANR/SIGABRT on returning from background by keeping the process foreground-protected while a video is open (playing OR paused), so Android never partially reclaims it and desyncs the native mpv `Player` from the Dart isolate.

**Architecture:** A media session (foreground service) exists exactly while `inBackground && hasVideo && !inPip` — gated by a pure `shouldHaveMediaSession` helper. Native side starts the FGS on any background update and never drops foreground protection while paused (removes `stopForeground(DETACH)`). A defensive guard nulls the native→Dart channel on engine teardown. media_kit is NOT touched.

**Tech Stack:** Flutter, Riverpod, Kotlin (foreground Service, MediaSessionCompat), `flutter_test`.

## Global Constraints

- Do NOT touch media_kit or dispose the engine (approach B is out of scope).
- `START_NOT_STICKY` stays as-is (out of scope).
- No new hardcoded colors; the notification style is unchanged aside from `ongoing`.
- No new pub dependencies.
- No `flutter run`. On module close: `flutter build apk --release`, then `adb install` to the Pixel 6 (device `24231FDF6006ST`; adb at `$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe`).
- Full suite stays green (`flutter test`), currently 388 tests.
- Do NOT regress background playback while PLAYING, the audio-focus/phone-call flow, or PiP (session must stay excluded in PiP).

---

### Task 1: Session gate — `shouldHaveMediaSession` + paused-in-background creates a session

**Files:**
- Modify: `lib/player/background/background_playback.dart`
- Test: `test/player/background/should_have_media_session_test.dart`

**Interfaces:**
- Produces: `bool shouldHaveMediaSession({required bool inBackground, required bool hasVideo, required bool inPip})` → `inBackground && hasVideo && !inPip` (top-level function in `background_playback.dart`).

**Context:** Today `_push` returns early on `final relevant = _playing || _sessionActive;` and gates session creation on `_inBackground && _playing`. For a video paused BEFORE backgrounding, both `_playing` and `_sessionActive` are false, so `_push` returns before ever creating a session — no foreground protection. This task makes the gate depend on `hasVideo` (a current video is loaded) instead of `_playing`, and fixes the early `relevant` gate so the paused case reaches session creation.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/background/background_playback.dart';

void main() {
  test('shouldHaveMediaSession: only when backgrounded, has a video, and not in PiP', () {
    expect(shouldHaveMediaSession(inBackground: true, hasVideo: true, inPip: false), true);
    // paused-in-background with a loaded video → still true (the bug-2 case)
    expect(shouldHaveMediaSession(inBackground: true, hasVideo: true, inPip: false), true);
    // foreground → no session
    expect(shouldHaveMediaSession(inBackground: false, hasVideo: true, inPip: false), false);
    // no video loaded → no session
    expect(shouldHaveMediaSession(inBackground: true, hasVideo: false, inPip: false), false);
    // PiP owns the controls → no session
    expect(shouldHaveMediaSession(inBackground: true, hasVideo: true, inPip: true), false);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/player/background/should_have_media_session_test.dart`
Expected: FAIL — `shouldHaveMediaSession` not defined.

- [ ] **Step 3: Add the helper**

In `lib/player/background/background_playback.dart`, add a top-level function (above or below the class):

```dart
/// Whether a foreground media session should exist right now. It must exist
/// while a video is loaded and we're backgrounded (playing OR paused) so the
/// process stays foreground-protected and Android can't partially reclaim it —
/// except in PiP, where the floating window owns the controls.
bool shouldHaveMediaSession({
  required bool inBackground,
  required bool hasVideo,
  required bool inPip,
}) =>
    inBackground && hasVideo && !inPip;
```

- [ ] **Step 4: Rewrite `_push` to use it (and fix the early gate)**

Replace the body of `_push` (currently lines ~124-146) with:

```dart
  void _push({bool force = false}) {
    final shouldHaveSession = shouldHaveMediaSession(
      inBackground: _inBackground,
      hasVideo: _ref.read(currentVideoProvider) != null,
      inPip: _ref.read(pipModeProvider),
    );
    // Relevant when a session exists/should-exist, or we're playing in the
    // foreground (audio focus is held there too). Otherwise nothing to do.
    if (!shouldHaveSession && !_sessionActive && !_playing) return;
    final second = _position.inSeconds;
    if (!force && second == _lastSentSecond) return;
    // In the foreground with no session there is nothing to keep updated.
    if (!shouldHaveSession && !_sessionActive) return;
    _lastSentSecond = second;
    if (shouldHaveSession && !_sessionActive) {
      _sessionActive = true;
    }
    final session = _ref.read(currentVideoProvider);
    _bridge.updateSession(
      title: session?.displayName ?? 'Kivo',
      mediaUri: session?.playbackPath ?? '',
      position: _position,
      duration: _duration,
      playing: _playing,
      inBackground: _inBackground,
    );
  }
```

(The `didChangeAppLifecycleState`, `_end`, focus callbacks, and the `pipModeProvider` listener that calls `_end()` when entering PiP are all UNCHANGED. On `resumed`, `_end()` still tears the session down — foreground needs no notification.)

- [ ] **Step 5: Run test + full suite**

Run: `flutter test test/player/background/should_have_media_session_test.dart`
Expected: PASS.
Run: `flutter test`
Expected: All green (no existing test asserts the old paused-no-session behavior; if one does, it is asserting the bug — stop and surface it).

- [ ] **Step 6: Analyze + commit**

Run: `flutter analyze lib/player/background/background_playback.dart`
Expected: No issues.

```bash
git add lib/player/background/background_playback.dart test/player/background/should_have_media_session_test.dart
git commit -m "fix(bg): keep a media session while a video is open in background (incl. paused)"
```

---

### Task 2: Native — keep the FGS foreground-protected while paused + null channel on teardown

**Files:**
- Modify: `android/app/src/main/kotlin/dev/selector/kivo_player/PlaybackSessionHub.kt`
- Modify: `android/app/src/main/kotlin/dev/selector/kivo_player/PlaybackSessionService.kt`
- Modify: `android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt`

**Interfaces:**
- Consumes: nothing new from Task 1 at the Kotlin level (Dart already pushes `inBackground`/`playing` via the `update` channel call). Task 1 is what makes Dart PUSH a background update while paused; this task makes the native side keep foreground protection when it receives one.

**Context:** No unit test (native/OS behavior). Verified by `flutter analyze` clean + a successful `flutter build apk --release` (Kotlin compile gate) + the Task 3 device checklist.

- [ ] **Step 1: Start the FGS on any background update (`PlaybackSessionHub.kt`)**

In `PlaybackSessionHub.update(...)`, change the start condition from `inBackground && playing` to `inBackground` (Dart only pushes background updates when a session should exist; `start()` is idempotent):

```kotlin
        this.playing = playing
        if (playing) requestFocus(context)
        if (inBackground) {
            PlaybackSessionService.start(context)
        }
        PlaybackSessionService.refresh()
```

- [ ] **Step 2: Keep foreground protection while paused (`PlaybackSessionService.kt`)**

Replace the `updateFromHub()` foreground block (currently the `if (playing) { ... } else { ...stopForeground(DETACH)... }` at lines ~191-213) with a single path that stays foreground whether playing or paused:

```kotlin
        val notification = buildNotification(playing)
        // A session only exists while a video is open in the background (Dart's
        // shouldHaveMediaSession gate). Stay foreground-protected the whole time
        // — playing OR paused — so Android's cached-app freezer can't freeze the
        // process and desync the native mpv Player from the Dart isolate (bug 2).
        if (!_foregrounded) {
            if (!safeStartForeground(notification)) return
            _foregrounded = true
        } else {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIFICATION_ID, notification)
        }
```

- [ ] **Step 3: Make the notification ongoing (`PlaybackSessionService.kt`)**

In `buildNotification(...)`, change `.setOngoing(playing)` to `.setOngoing(true)` — a foreground-service notification is non-dismissable regardless, and the session now persists (protected) while paused. The Stop action (delete intent) still ends it.

- [ ] **Step 4: Null the channel on engine teardown (`MainActivity.kt`)**

`PlaybackSessionHub.channel` is set in `configureFlutterEngine` (line ~479) and never cleared, so a late audio-focus callback could `invokeMethod` on a dead engine's channel. Add an override to clear it when the engine is cleaned up:

```kotlin
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        PlaybackSessionHub.channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
```

Add the import if missing: `import io.flutter.embedding.engine.FlutterEngine` (already imported in `MainActivity.kt`). If `cleanUpFlutterEngine` is not available/overridable in this Flutter embedding version, null it in `onDestroy()` instead (before `super.onDestroy()`), and note which was used.

- [ ] **Step 5: Analyze + release build (Kotlin compile gate)**

Run: `flutter analyze`
Expected: No issues.
Run: `flutter build apk --release`
Expected: `Built build\app\outputs\flutter-apk\app-release.apk` (a Kotlin error fails here).

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/kotlin/dev/selector/kivo_player/PlaybackSessionHub.kt android/app/src/main/kotlin/dev/selector/kivo_player/PlaybackSessionService.kt android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt
git commit -m "fix(bg): keep foreground service protected while paused; null session channel on teardown"
```

---

### Task 3: Build, install, and device verification

**Files:** none (verification only).

- [ ] **Step 1: Full suite**

Run: `flutter test`
Expected: All green.

- [ ] **Step 2: Release build**

Run: `flutter build apk --release`
Expected: `Built build\app\outputs\flutter-apk\app-release.apk`.

- [ ] **Step 3: Install to the Pixel 6**

Run: `& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" -s 24231FDF6006ST install -r build\app\outputs\flutter-apk\app-release.apk`
Expected: `Success`.

- [ ] **Step 4: Device checklist** (report pass/fail per item)

  - Open a video → **pause** → Home (background): a Kivo notification appears (paused, persistent), and the process holds a foreground service.
  - With the video paused in the background, open many other apps / apply memory pressure for a good while, then return to Kivo → **it resumes and can open other videos with no freeze** (the bug is gone). Optionally confirm via `adb shell dumpsys activity services dev.selector.kivo_player` that the service is still running while paused-backgrounded.
  - Background while **playing**: unchanged — notification, controls, audio focus, phone-call pause/resume all still work (no regression).
  - Return to foreground: notification is removed (`_end`), player normal.
  - **Stop** from the notification: session ends, audio stops.
  - **PiP**: no session notification appears (gate excludes PiP) — no regression.

This task has no commit (verification only). Report results; a failed item becomes a fix task.

---

## Self-Review notes

- **Spec coverage:** §1 gate→Task 1; §2 FGS start→Task 2 Step 1; §3 no-detach-in-pause + ongoing→Task 2 Steps 2-3; §4 channel-null guard→Task 2 Step 4; testing→Task 1 unit + Task 3 device.
- **Early-gate fix:** Task 1 Step 4 rewrites `_push` so the `relevant` early-return also accounts for `shouldHaveSession` — otherwise a paused-in-background video (both `_playing` and `_sessionActive` false) would return before creating the session, and the fix would silently do nothing. This is the load-bearing detail.
- **Type consistency:** `shouldHaveMediaSession({inBackground, hasVideo, inPip})` used identically in Task 1's test, helper, and `_push`. Native `update(... inBackground ...)` already carries the flag; no signature change needed.
- **Native task (2)** has no unit test by nature; gated by analyze + release build + Task 3 device checklist. The change is minimal and additive on the pause branch (stop dropping foreground) plus a one-line start condition and a teardown guard.
- **No-regression focus:** the playing-in-background path is unchanged except that its start condition widened from `inBackground && playing` to `inBackground` (still starts for playing); PiP stays excluded via the gate; audio focus handling untouched.
