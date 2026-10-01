# Kivo large screens & remote (tanda 7) — Design

**Date:** 2026-10-01
**Status:** Implemented under the standing autonomy ("decide tú… vale para
todas las tandas").

## Android TV

- Manifest: `LEANBACK_LAUNCHER` entry, `android:banner` (`tv_banner.xml`:
  the launcher icon centred on its background colour, 320×180dp), and
  `leanback` / `touchscreen` declared **not required**, so the same APK
  installs on TV and phones. No separate TV UI: the phone UI with D-pad
  focus (below) and the wide-screen layouts.

## Remote, game pad, keyboard

- **Player** (`PlayerKeys`, under the app's shortcuts so it sees keys
  first and claims only the ones it acts on):
  - Media keys always: play/pause, play, pause, fast-forward / rewind (the
    skip jump), next / previous in the queue — even locked.
  - Controls hidden: ←/→ seek by the skip jump (held: repeats), OK / Enter /
    A play-pause, ↑/↓ bring the controls up with the focus on play/pause.
  - Controls up: the D-pad moves between the buttons and OK presses the
    focused one; any key keeps them up. Shown by a tap, the first D-pad press
    lands on play/pause. Space is play/pause either way.
  - Locked: media keys, and any D-pad press brings up the unlock button with
    the focus on it; OK there unlocks (holding is a touch gesture).
  - Next / previous go to the neighbour in play order (shuffle included),
    wrapping only under repeat-list; repeat-one does not hold them.
  - Hidden controls are excluded from focus, and the player takes the focus
    back when they fade: an invisible button never keeps it.
  - The seek bar's Slider never takes focus (on a D-pad it steps 5 % on all
    four arrows and traps ↑/↓); the bar has its own focus with ←/→ = the
    skip jump and ↑/↓ left to traversal.
  - The subtitle/audio sync panel: the D-pad steps into it and through its
    buttons and target chips.
- **Everywhere else**: Material buttons were already focusable; the custom
  gesture-only controls were not. `KivoFocusable` / `FocusableTap` add focus,
  OK/Enter to activate, the menu key (or Shift+Enter / game-pad X) for what a
  long press does, and an accent ring — shown only in keyboard navigation, so
  touch looks exactly as before. Applied to video tiles (menu = options, or
  selection where there is no ⋮), folder cards (menu = folder options),
  library filter chips, the Vault grid (menu = select), and the custom chips,
  segments, swatches and steppers in Settings, the speed panel, the track
  picker and the More menu.

## Tablets and wide screens

Only on a tablet or a TV (shortest side ≥ 600dp): a phone, in either
orientation, looks exactly as before.

- Library grid: the column setting (1–3) is what you get on a phone; wider
  screens get proportionally more at the same tile size, up to 8
  (`adaptiveColumns`). The one-column list stays a list, centred within
  720dp.
- Folders: as many 240dp-wide cards as fit (two on a phone, as before).
- Settings (root and every section): content centred within 720dp.

## Not in this tanda

Foldable hinge-aware layouts; a dedicated TV home (rows of posters). The
phone UI with focus works on TV; a TV-first layout is a product decision
of its own.

## Testing

`test/ui/large_screens/remote_and_layout_test.dart`: the key map, the
player's keys end to end (seek, play/pause, reveal with focus), adaptive
columns, readable width, and a tile opened with OK / options with the menu
key.
