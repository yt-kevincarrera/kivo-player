# Kivo accessibility (tanda 6) — Design

**Date:** 2026-10-01
**Status:** Implemented under the standing autonomy ("decide tú… vale para
todas las tandas").

Found by auditing every main screen with Flutter's accessibility guidelines
(labelled tap targets, 48 dp targets, text contrast) and reading the
semantics tree TalkBack gets; fixed what a TalkBack user would trip on.

## Player

- **Controls stay up under TalkBack.** `MediaQuery.accessibleNavigation`
  (synced from `PlayerGestures`) turns the auto-hide off and shows the
  controls; they hide only on purpose (tapping the video), and auto-hide
  comes back when TalkBack is turned off. Moving through the controls one by
  one, a fading bar would vanish from under the user.
- **The video area** is one node: "Video — double-tap to show or hide the
  controls". Swipes, double taps and holds stay touch-only; every one of them
  has a button TalkBack reaches.
- **Seek bar:** says "1 minuto 30 segundos de 10 minutos" (spoken, not
  "1:30", which is read as a time of day; `spokenDuration`), and volume-key /
  swipe up-down steps it by the skip-button jump (default 10 s) instead of
  the slider's 5 % (six minutes of a two-hour film).
- The right-hand time is a button: "Duración: 10 minutos" / "Quedan …",
  hint "cambiar entre duración y tiempo restante".
- Skip buttons no longer read "10s" twice; the frame-step label is not read
  (the buttons say it).
- **Locked screen:** hold-to-unlock is a touch gesture; TalkBack gets a plain
  "Desbloquear pantalla" button that unlocks on double-tap.
- Zoom chip ("Zoom 1.5×, double-tap to reset the zoom"), A-B loop chip,
  queue thumbnails and the More menu's segmented options are buttons with
  their selected state.

## Library and the rest

- **Video tiles** are one node with what the picture shows: "cool.mkv,
  1 minuto 5 segundos, visto al 40 %, Nuevo, 49 MB" (+ selected state while
  selecting). The ⋮ keeps its own node, now labelled "Opciones", with a
  48 dp target.
- **Folders:** "Series, 12 videos".
- **Filter chips** read their name once (the visible text doubled it) with
  their selected state; "No vistos" is a toggle. Bottom tabs say which is
  selected.
- **Mini-player** play/pause and close are labelled.
- **Vault PIN pad:** "2 de 4 dígitos" as a live region — how many, never
  which — and a labelled backspace.

## Motion and text size

- With "Quitar animaciones" on, the player fades in instead of flying out of
  the tile.
- Checked at 200 % system text, portrait and landscape: no overflow in the
  library, settings, player or PIN pad.

## Accepted

The library's filter chips (31 dp tall), the "Kivo" title and the player's
time label are under 48 dp. Growing them changes the layout for everyone,
and TalkBack users reach them by swiping, not by aiming.

## Testing

`test/ui/a11y/guidelines_test.dart` holds the main screens to the
labelled-target and contrast guidelines; `talkback_test.dart` covers the
spoken duration, controls staying up, the seek bar's value and steps, the
tile label, the PIN progress, unlocking and reduced motion.
