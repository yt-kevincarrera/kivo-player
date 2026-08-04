# Kivo Gesture Map + "Solo audio" Removal — Design

**Date:** 2026-08-04
**Status:** Approved for implementation

## Goal

Three changes, one spec, because they share the same code:

1. **Teach the player.** The first time a video is ever opened, show a full-screen
   "gesture map" that labels the *real* zones of the player screen, plus a page
   for the control buttons. Re-openable from Settings.
2. **Delete "Solo audio".** The mode overlaps other overlays, produces a black
   PiP window, and is a second layout of the player screen that taxes every
   future feature. Background playback and the mini-player already cover its use
   cases.
3. **Fix the black screen on return to video.** The "stale frame cover" is driven
   by mpv's reported width, which `vid=no` zeroes — so releasing the video output
   (for background, or for audio-only) can leave the cover armed forever.

## 1. Remove "Solo audio"

### Rationale

- Its niche is already covered twice, better: screen-off listening by background
  playback (media session + notification), in-app listening by the mini-player
  bar, which has its own play/pause and persists progress while minimized
  ([mini_player_bar.dart:171](../../../lib/ui/mini_player/mini_player_bar.dart)).
  Audio-only only wins the "screen ON showing black" case, and the player holds
  `keepAwake(true)`, so it does not even save real battery.
- It is a bug factory: the reported overlap, the black-screen-on-return, and a
  third latent bug — entering **PiP while audio-only is on shows a permanently
  black PiP window**, because the coordinator only reattaches video when it was
  the one that released it (`if (inPip && _videoReleasedForBackground)`,
  [background_playback.dart:133](../../../lib/player/background/background_playback.dart)),
  and audio-only deliberately skips that release. `AudioOnlyView` is not mounted
  in PiP either, so there is not even an explanation on screen.
- The overlap is structural, not cosmetic: `AudioOnlyView` owns the center of the
  screen while `ControlsOverlay`, `HudOverlay`, `AutoplayOverlay`, `ResumePrompt`,
  `GestureSeekPreview` and `SpeedLadderOverlay` are all centered too — and in
  audio-only the controls **never auto-hide**
  ([controls_overlay.dart:21](../../../lib/ui/player/controls/controls_overlay.dart)),
  so the clash is permanent.
- It touches the most dangerous code in the app. The only reason
  `shouldReleaseVideoForBackground` takes an `audioOnly` parameter is this mode,
  and that function is part of the still-unconfirmed background-freeze fix.
  Removing the mode leaves a **single owner of mpv's `vid` property**.

The good version of this idea is a dedicated audio screen with its own layout,
not a second mode layered onto the video player's overlay stack. That is a
separate project, not a patch.

### Deleted

- `lib/player/background/audio_only.dart`
- `lib/ui/player/audio_only/audio_only_view.dart`
- `KivoIcons.audioOnly` ([kivo_icons.dart:106](../../../lib/core/icons/kivo_icons.dart))
- `test/player/background/audio_only_test.dart`
- `test/ui/player/audio_only_view_test.dart`
- The bottom-bar toggle button ([bottom_bar.dart:78-98](../../../lib/ui/player/controls/bottom_bar.dart))

### Branches collapsed to the "always video" behavior

| File | Change |
|---|---|
| `ui/player/controls/controls_overlay.dart` | `visible` no longer OR-ed with audio-only (controls auto-hide again, always). `CenterControls` returns to `Center(...)` unconditionally; the scaled `bottom: 118` variant is deleted. |
| `ui/player/controls/bottom_bar.dart` | Aspect-ratio and rotate buttons are unconditional; `audioOnly` local and the toggle button go. |
| `ui/player/controls/top_bar.dart` | The PiP button hides only on `!supported` ([top_bar.dart:80](../../../lib/ui/player/controls/top_bar.dart)). |
| `ui/player/controls/info_overlay.dart` | Gated only by `showInfoOverlay`. |
| `ui/player/gestures/player_gestures.dart` | The center rotate band loses the `!audioOnly` guard ([player_gestures.dart:98](../../../lib/ui/player/gestures/player_gestures.dart)). |
| `ui/player/player_screen.dart` | Delete the `_audioOnly` field, its `disable()` in `dispose`, and the `ref.listen(audioOnlyProvider)` that forced portrait. |
| `player/background/background_playback.dart` | `shouldReleaseVideoForBackground({hasVideo, inPip})` — the `audioOnly` parameter is gone. `_onDuckStart` always pauses (the video behavior, which was already every case but this mode), so the `_ducking`/`_duckUserAdjusted`/`_restoreDuckIfActive` volume-lowering path becomes dead code and is removed with it. |

`_onDuckStart` simplification detail: with no audio-only, a duck request always
means "pause and auto-resume on duck end" — `_pausedByFocus = true; pause()`.
`_onDuckEnd` keeps only the resume half. Removed with it: the `_ducking` /
`_duckUserAdjusted` fields, `_restoreDuckIfActive()` and its two call sites in
`_onFocusLoss` / `_onFocusTransientLoss`, the `volumePercentProvider` listener
that detected a user volume change *during* a duck, and the now-unused
`_userPlayerVolume` getter. The `_playing && !_pausedByFocus && !_ducking`
condition in the `playingProvider` listener loses its `_ducking` term.

### Tests updated

- `test/player/background/background_playback_test.dart` — drop the `audioOnly`
  cases of `shouldReleaseVideoForBackground`; add/adjust a duck case asserting
  "duck always pauses".
- `test/ui/player/player_gestures_test.dart` — drop the "center band is inert in
  audio-only" case.
- `test/player/background/should_have_media_session_test.dart` — check for
  audio-only references and clean if present.

## 2. Fix the black screen on return to video

Two candidate causes; both are addressed, in order of certainty.

### 2a. Ours (certain)

The stale-frame cover must belong to the **open sequence**, not to the `vid`
property. Today `hasVideoFrameStream = _player.stream.width.map((w) => (w ?? 0) > 0)`
([media_kit_engine.dart:41](../../../lib/player/engine/media_kit_engine.dart)) and
`PlayerScreen` mirrors it straight into `videoFrameReadyProvider`
([player_screen.dart:89](../../../lib/ui/player/player_screen.dart)), so any
`width→null` arms the black cover — and `vid=no` produces exactly that.

**Fix, in the engine (single place, no UI change):** `MediaKitEngine` tracks its
own intent in `setVideoTrackEnabled` (`bool _videoOutputEnabled = true`), and
`hasVideoFrameStream` does not emit while the output is intentionally off:

```dart
Stream<bool> get hasVideoFrameStream => _player.stream.width
    .where((_) => _videoOutputEnabled)
    .map((w) => (w ?? 0) > 0);
```

Re-arming the cover between videos keeps working because `_openSession` already
seeds it explicitly before `engine.open()`
([player_screen.dart:216](../../../lib/ui/player/player_screen.dart)), so the
existing `video_ready_test.dart` semantics hold.

Ordering requirement: `_videoOutputEnabled` is set to `false` **before** awaiting
the `vid=no` property write, and back to `true` **before** awaiting `vid=auto`,
so no width event can slip through with the flag in the wrong state.

### 2b. mpv's (safety net, one retry)

If mpv fails to reattach its video output on return from background, the texture
is black no matter what our cover does. On re-enable, if mpv still reports no
video size after ~700 ms, retry **once**: re-apply `vid=auto` and `seek` to the
current position to force a frame.

- Lives in the engine, next to `setVideoTrackEnabled`, as
  `Future<void> ensureVideoOutputAttached()` — the coordinator calls it after
  re-enabling on `resumed`.
- Strictly asynchronous and fire-and-forget. **No new synchronous mpv calls on
  the UI thread** — that is the confirmed ANR path
  (`mpv_set_property_string` → `pthread_cond_wait`).
- One retry, no loops, no timers left running: a single `Future.delayed` guarded
  by a "still enabled and still no size" check.

## 3. Gesture map

### It is a route, not an overlay

A non-opaque `PageRouteBuilder` pushed with `Navigator.push`, following the
`player_route.dart` pattern:

- It paints over the paused, dimmed video.
- The back button pops only the map; the player's `PopScope`
  (`canPop: false` → minimize) never sees it.
- The same screen works unchanged when opened from Settings, where there is no
  player behind it.
- Zero coexistence with the player's overlay stack — which is precisely what
  broke audio-only.

### Geometry copied from the truth, not eyeballed

Zones are drawn from the same constants the gestures use, imported from
`player/control/gesture_math.dart`:

- Double taps: thirds — `tapZoneOf` (`< 0.33` left, `0.33–0.67` center, `> 0.67` right).
- Brightness / volume: **exact halves** — `dx < width / 2` in `player_gestures`.
- Rotate: central 30% band — `inCenterRotateZone`.
- Minimize: 38 px lateral edges — `inLateralDeadZone` with `_lateralMargin`.

The thirds-vs-halves difference is real and is the reason the split by gesture
type works: page 1 shows thirds, page 2 shows halves. Any constant the map needs
that currently lives as a private field in `_PlayerGesturesState`
(`_lateralMargin`, `_deadMargin`) moves to `gesture_math.dart` as a public const
so both the gestures and the map read one source.

### Content — 3 pages

**Page 1 — Toques (thirds):**

- Left third: `Doble toque · −{doubleTapSkipLeft} s`
- Center third: `Doble toque · Pausa` — only when `doubleTapCenterPause`
- Right third: `Doble toque · +{doubleTapSkipRight} s`
- Full-width footer hint: `Un toque · Mostrar u ocultar los controles`

**Page 2 — Arrastres (halves + bands):**

- Left half, vertical arrow: `Arrastra ↕ · Brillo`
- Right half, vertical arrow: `Arrastra ↕ · Volumen (hasta {volumeBoostMax}%)`
- Full width, horizontal arrow: `Arrastra ↔ · Buscar con vista previa` — only
  when `horizontalSeek`
- Lateral edge strips: `Arrastra ↓ en el borde · Minimizar`
- Center band: `Arrastra ↕ en el centro · Girar (con los controles ocultos)`
- Footer legend (two rows, not zones — they share the same halves as
  brightness/volume): `Mantén pulsado a la izquierda · {holdLeftSpeed}×` and
  `Mantén y desliza ↕ a la derecha · Escalera de velocidad`

**Page 3 — Botones:** the top and bottom bars rendered visible with short labels.
Top: subtítulos, audio (pistas), imagen en imagen, información en pantalla,
⋮ más opciones. Bottom: velocidad, bloqueo, relación de aspecto, rotar, cola.
Static labelled diagram — it does not mount the real `TopBar`/`BottomBar`
widgets (they read player state that does not exist from Settings); it draws the
same icons from `KivoIcons` in the same order.

### Labels read the user's real configuration

Every number comes from `KivoSettings`, and a hint whose setting is **off is not
taught at all** (no `horizontalSeek` → no seek hint; no `doubleTapCenterPause`
→ no center-pause hint). PiP is listed on page 3 only when the device supports
it, mirroring `top_bar`'s own gate.

### Files

| File | Contents |
|---|---|
| `lib/ui/player/tutorial/gesture_map_content.dart` | **Pure** — imports only `KivoSettings`, no Flutter. `List<GestureMapPage> gestureMapPages(KivoSettings s, {required bool pipSupported})`, with `GestureMapPage { String title; List<GestureHint> hints; }`, `GestureHint { MapZone zone; String label; HintArrow? arrow; }`, `enum MapZone { leftThird, centerThird, rightThird, leftHalf, rightHalf, centerBand, lateralEdges, fullWidth, topBar, bottomBar }` and `enum HintArrow { vertical, horizontal, down }`. This is where the tests live. |
| `lib/ui/player/tutorial/gesture_map_page.dart` | The widget: scrim, zone rendering from `MapZone` + `gesture_math` constants, `PageView`, page dots, `Siguiente` / `Entendido`. |
| `lib/ui/player/tutorial/gesture_map_route.dart` | `Route gestureMapRoute()` — non-opaque `PageRouteBuilder` with a fade transition. |

Styling follows the existing "segmented dark + accent" control language:
accent-outlined zone boxes over a `black54` scrim, accent-tinted labels, the
same pill shapes used elsewhere in the player.

### Trigger and persistence

- New persisted flag `gestureMapShown` (bool, default `false`) in `KivoSettings`,
  following `offeredAllFilesAccess` exactly: field, constructor, `defaults()`,
  `copyWith`, `toJson`, `fromJson`.
- In `PlayerScreen._start()`, after `_openSession` returns: if
  `!settings.gestureMapShown`, `_engine.pause()`, push `gestureMapRoute()`, and
  when it pops → persist `gestureMapShown: true` and `_engine.play()`.
- **The flag is written on close, not on show**, so a force-kill mid-tutorial
  does not cost the user the tutorial forever.
- Guarded by `mounted` before pushing and before resuming (the trigger runs from
  a post-frame callback, and the user can minimize meanwhile).
- Re-opened from **Settings › Reproducción y gestos** (`playback_gestures_section.dart`)
  with a `Ver el mapa de gestos` row — that is where those same gestures are
  configured. Not in the player's ⋮ menu, which is for session tools (sleep
  timer, A-B loop).

## 4. Tests

**Pure / unit**

- `gestureMapPages`: 3 pages in order; labels interpolate `doubleTapSkipLeft/Right`,
  `volumeBoostMax`, `holdLeftSpeed`; the seek hint disappears when
  `horizontalSeek` is off; the center-pause hint disappears when
  `doubleTapCenterPause` is off; the PiP entry disappears when unsupported.
- `hasVideoFrameStream`: does not emit `false` when the video output is turned
  off intentionally; a fresh open still re-arms the cover (existing
  `video_ready_test.dart` must keep passing unchanged).
- `shouldReleaseVideoForBackground(hasVideo, inPip)` after the signature change.
- Duck: a duck request always pauses and sets the auto-resume flag.

**Widget**

- The map pages through 1 → 2 → 3 and `Entendido` pops the route.
- First-ever open: the player pauses and pushes the map; with
  `gestureMapShown: true`, it does not.
- On close: the flag is persisted and playback resumes.

**Deleted:** `audio_only_test.dart`, `audio_only_view_test.dart`. **Updated:**
`background_playback_test.dart`, `player_gestures_test.dart`, and any audio-only
reference in `should_have_media_session_test.dart`.

## Out of scope

- The background freeze / ANR bug itself (`pending-bugs`) — untouched here beyond
  simplifying `vid` ownership to one owner, which reduces its surface.
- A dedicated audio-playback screen. If audio-only is ever missed, it should be
  built as its own screen, not as a second mode of the video player.
