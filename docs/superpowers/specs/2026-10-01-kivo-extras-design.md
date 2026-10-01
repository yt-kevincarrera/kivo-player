# Kivo extras (tanda 5) — Design

**Date:** 2026-10-01
**Status:** Implemented under the standing autonomy ("decide tú… vale para
todas las tandas").

## 1. Fotograma a fotograma

- mpv `frame-step` / `frame-back-step` (both leave playback paused).
- A small capsule under the play button, **only while paused** (stepping
  frames is what you do on a paused picture; while playing it would be
  noise): ‹ previous frame · › next frame. A tap steps once; holding repeats
  at up to ~8 steps/s with a light haptic per step, each step waiting for
  the previous frame to land. The engine hides the brief unpause mpv does
  while stepping forward, so the controls don't flicker.
- Backwards is slower on long-GOP files (mpv decodes from the previous
  keyframe); accepted.

## 2. Modo incógnito

- `KivoSettings.incognito` (default off). While on, watching leaves no trace:
  no resume position saved, nothing marked as played, so nothing new in
  "Continuar viendo", the widget or the launcher shortcuts. Explicit actions
  (bookmarks, playlists, captures) still work — the user asked for them.
- Existing history is left alone (like a browser's private window).
- Toggle: Ajustes › Reproducción avanzada › Continuar viendo. While on, the
  library's app bar shows an incognito chip; tapping it turns it off.
- Gated where playback writes history: the player's open (`markPlayed`) and
  periodic save (`record`), the mini-player's save, and the minimized
  autoplay advance.

## 3. Launcher shortcuts and 4. "Continuar viendo" widget

Both are fed from the same list: the first 3 entries of
`continueWatchingProvider`, pushed to native whenever it changes (debounced)
over a new `kivo/launch` channel (`updateContinue` with id, uri, name,
formatted position, fraction).

- **Shortcuts** (long-press the icon): one dynamic shortcut per entry,
  labelled with the video name, icon = its MediaStore thumbnail.
- **Widget** (`ContinueWidgetProvider`, RemoteViews): the newest entry's
  thumbnail, name, "Continuar en 12:34" and a progress bar; empty state
  "Nada a medias". Resizable.
- Tapping either sends `MainActivity` an intent with the MediaStore id; the
  activity forwards it over `kivo/launch` (initial intent and `onNewIntent`),
  and the library opens it **as a library item** — its folder as the queue,
  so folder subtitles and autoplay work, and resume picks up the position.
- With a player already on screen, the tap switches it in place (the same
  path as autoplay's next video) instead of stacking or replacing the route.
- Native keeps a tap that arrives before Dart asked for it; after that, taps
  are pushed (the engine outlives the activity). A Recents relaunch replays
  the old intent and is ignored.
- Nothing is pushed while the library is still scanning (the list is empty
  then, and would wipe the shortcuts and the widget on every start).
- Thumbnails: `ContentResolver.loadThumbnail` (API 29+), else
  `MediaStore.Video.Thumbnails.getThumbnail`, on the IO executor.
- A video no longer in the library (deleted, hidden in the Vault) is ignored
  quietly; the list refreshes on the next library scan.
- Android-rendered strings (widget, shortcut fallback) in
  `res/values{,-es}/strings.xml`.

## Testing

Frame-step capsule visibility, tap and hold-repeat; incognito gating at each
write site and the chip; continue-list → native payload mapping (pure); the
launch handler opening the right item with its folder queue; Kotlin is
compiled by the release build.
