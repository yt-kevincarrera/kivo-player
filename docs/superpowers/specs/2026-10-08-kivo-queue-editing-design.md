# Kivo editable queue — Design

**Date:** 2026-10-08
**Status:** Approved in chat ("solo esa sesión, dale"); the user then left and
asked to carry on to the end without stopping.

Music-player-style editing of the queue strip shown under the player controls,
plus a small polish pass on the resume toast.

## 0. Model: edits touch the play order, never the queue

`VideoSession` already carries two things: `queue` (the list the video was
opened from) and `order` (the play order — today only shuffle sets it; null
means natural order). Every consumer that decides "what plays next" already
reads `order`: `peekNext` (autoplay, both paths), `queueStep` (keys/D-pad), the
strip.

- `order` becomes "the indices of [queue] that will play, in play order" — a
  permutation of a **subset** of the queue. Every edit rewrites it; `queue`,
  `queueNames`, `queueIds` are never touched. A removed video is simply absent
  from `order`, so undo is putting its index back.
- New `VideoSession.playOrder` getter (`order ?? 0..n-1`) replaces the three
  copies of that fallback (strip, `queueStep`, `peekNext`).
- New `VideoSession.orderEdited` flag: true once the user has reordered,
  inserted or removed. Carried forward by `sessionAt`.
- Edits live only for this session. Opening from a saved playlist and
  reordering does **not** change the playlist (user decision).
- Pure functions in `queue_order.dart`, each returning a new order:
  `moveInOrder(order, from, to)`, `playNextInOrder(order, currentIndex, item)`,
  `removeFromOrder(order, item)`. The current video can never be removed.
- `CurrentVideoNotifier` gets `reorder(fromPos, toPos)`, `playNext(index)`,
  `remove(index)` and `restoreOrder(order, edited)`; each stores the previous
  order in `queueUndoProvider` before changing it.

## 1. Reorder by dragging

- Long-press a card → light haptic, the card lifts (scale 1.06 + shadow) and
  follows the finger; the others slide apart. Near an edge the strip
  auto-scrolls. Drop → `reorder`.
- Built on `ReorderableListView.builder` (horizontal) with
  `ReorderableDelayedDragStartListener` per card and `buildDefaultDragHandles:
  false`; `proxyDecorator` draws the lift.
- The current card can be dragged too; it only changes what comes after it.
- Works with shuffle on: the strip shows the effective order, and that is what
  is reordered.
- The controls must not auto-hide under a finger: `ControlsVisibilityNotifier`
  gets `hold()` / `release()` (a counter that suspends the auto-hide timer;
  the timer restarts on the last release). The strip holds from drag start
  until drop, and while its menu is open.

## 2. Long-press menu: "Reproducir a continuación" / "Quitar de la cola"

- One gesture for both: long-press and drag = move; long-press and release
  **on the same spot** = a small menu anchored above the card. Detected in
  `onReorderEnd`: if the card ends where it started, open the menu instead of
  reordering.
- Menu = dark capsule (`black` α≈0.82, radius 14 — same surface as the resume
  toast), two rows with duotone icons. **Every accent comes from
  `settingsProvider.accentColor`**, never a hard-coded gold.
- "Reproducir a continuación": moves the video right after the current one.
  Hidden for the current card and for the one already next.
- "Quitar de la cola": hidden for the current card.
- Tap outside / back closes it.

## 3. Undo toast

- After every edit (move, play next, remove) a toast at the bottom: "Movido",
  "Se reproducirá a continuación", "Quitado de la cola" · **Deshacer**. 4 s.
- Undo = `restoreOrder(previous)`. One level only; the undo is dropped when the
  current video changes (the old order may not contain the new one).
- Shuffle toggled while `orderEdited`: shuffle rebuilds from the full queue
  (removed videos come back) and the toast says "Orden de la cola
  restablecido · Deshacer"; undo restores the shuffle setting and the old order.
- Shares the toast shell of §6 (swipe to dismiss, animated).
- When the play order drops to 1 video the strip hides (as with a 1-video queue
  today); the toast stays, so a removal can still be undone.

## 4. Watched state per card

- Videos in progress: the library's segmented progress bar (16 segments, accent
  lit) along the bottom of the thumbnail. Fraction = resume seconds ÷ duration,
  same rule as "Continuar viendo".
- Videos already played with no resume point left: a small ✓ badge
  (accent-coloured) in the corner. "Played" is the same `PlayedStore` notion the
  library uses for "Nuevo" and the "No vistos" filter, so the two agree.
- `_SegmentedProgress` moves out of `video_tile.dart` into a shared widget.
- Needs durations: new `VideoSession.queueDurationsMs` (parallel list, filled by
  `openFromList` from `VideoItem.durationMs`; empty for sources that don't know).

## 5. Position and time left

- A line above the strip, small, tabular figures:
  `4 / 12 · quedan 2 h 10 min · acaba a las 23:40`.
- Position = place of the current video in the play order / play-order length.
- Time left = (duration − position of the current video) + durations of the
  videos after it in play order, divided by the playback speed. End clock in
  the device's 12/24 h format.
- Only the counter is shown when any later duration is unknown, or when repeat
  is on (there is no end).
- Pure function `queueTimeLeft(...)` in `queue_order.dart`; the widget only
  formats.

## 6. Resume toast ("Reanudado desde M:SS · Reiniciar")

- Auto-hide 1 s shorter: `undo` 5 s → 4 s. The `ask` variant (a real choice)
  keeps 8 s.
- Animated in: fade + 12 px rise, 220 ms easeOutCubic. Animated out on
  timeout: fade + 8 px drop, 180 ms.
- Swipe to dismiss in **any direction**: the toast follows the finger (pan
  offset, opacity falls with distance). Release past 56 px or with a fling
  above 600 px/s → it flies off along the drag direction and fades (200 ms);
  otherwise it springs back. The auto-hide timer pauses while the finger is
  down.
- Reduced motion (`MediaQuery.disableAnimations`): no slide, a plain fade.
- Built as a reusable `SwipeDismissToast` shell; the queue undo toast (§3)
  uses the same shell.

## i18n

Every new string goes into both `app_es.arb` and `app_en.arb` with a
description (the CI sweep forbids literals in `lib/`).

## Testing

- Unit: `moveInOrder`, `playNextInOrder`, `removeFromOrder`, `queueTimeLeft`;
  `peekNext`/`queueStep` over an edited (subset) order; undo; shuffle reset
  while edited.
- Widget: strip reorder by long-press-drag, long-press-release opens the menu,
  play next / remove + undo toast, progress bar and ✓ badges, counter/time
  line; resume toast swipe dismiss + 4 s timeout.

## Not in this round

Save queue as playlist, restore the queue on next launch, skip watched videos.
