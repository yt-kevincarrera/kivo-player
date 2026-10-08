# Kivo editable queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user reorder, play-next and remove videos in the player's
queue strip (with undo), see per-card watched state and the queue's time left,
and make the resume toast shorter, animated and swipe-dismissable.

**Architecture:** All edits rewrite `VideoSession.order` (now a permutation of
a subset of the queue) through pure functions in `queue_order.dart`, called by
`CurrentVideoNotifier`; every "what plays next" consumer already reads the
order, so autoplay/keys/notification follow edits for free. The UI is a
`ReorderableListView` strip, a popup menu, and a shared `SwipeDismissToast`
shell used by both the resume toast and the new queue undo toast.

**Tech Stack:** Flutter, Riverpod (Notifier/StateProvider), gen-l10n ARB.

**Spec:** `docs/superpowers/specs/2026-10-08-kivo-queue-editing-design.md`

## Global Constraints

- Accent colours always from `Color(ref.watch(settingsProvider).accentColor)`; never `KivoColors.gold` directly.
- Every user-facing string in BOTH `lib/l10n/app_es.arb` and `app_en.arb` with a `@key` description; run `flutter gen-l10n`. Copy writes "video", never "vídeo".
- Haptics only when `settings.hapticsOnGestures`.
- Edits are session-only; saved playlists are never modified.
- The current video can never be removed from the order.
- Gate commits on real exit codes (`flutter test … > file; echo $?`), never `| tail &&`.
- No AI attribution in commits.

## Review Focus

1. A playlist holding the same video twice: strip keys must stay unique (key by `uri#index`, not `uri`).
2. Undo after the current video changed (autoplay advanced): must be a no-op, never an order without the current index.
3. Removing videos until one is left: strip hides, undo toast still works and brings the strip back.
4. Controls auto-hide during a long drag or with the menu open: must not happen (`hold`/`release`).
5. Shuffle toggled after edits: removed videos return, undo restores both the setting and the edited order.

---

### Task 1: Pure order operations + time left

**Files:**
- Modify: `lib/player/queue/queue_order.dart`
- Test: `test/player/queue/queue_order_test.dart`

**Interfaces — Produces:**
- `List<int> moveInOrder(List<int> order, int from, int to)` — `to` is the final position.
- `List<int> playNextInOrder(List<int> order, int current, int item)`
- `List<int> removeFromOrder(List<int> order, int current, int item)`
- `Duration? queueTimeLeft({required List<int> order, required int current, required List<int> durationsMs, required Duration currentDuration, required Duration position, required double rate})`

- [ ] **Step 1: failing tests**

```dart
group('moveInOrder', () {
  test('moves forward and back', () {
    expect(moveInOrder([0, 1, 2, 3], 0, 2), [1, 2, 0, 3]);
    expect(moveInOrder([0, 1, 2, 3], 3, 1), [0, 3, 1, 2]);
  });
  test('same position is a copy', () {
    final o = [2, 0, 1];
    final m = moveInOrder(o, 1, 1);
    expect(m, o);
    expect(identical(m, o), isFalse);
  });
});
group('playNextInOrder', () {
  test('puts item right after current', () {
    expect(playNextInOrder([0, 1, 2, 3, 4], 1, 4), [0, 1, 4, 2, 3]);
    expect(playNextInOrder([0, 1, 2, 3, 4], 3, 0), [1, 2, 3, 0, 4]);
  });
  test('re-inserts an item that was removed', () {
    expect(playNextInOrder([0, 2], 0, 1), [0, 1, 2]);
  });
  test('current itself is a no-op', () {
    expect(playNextInOrder([0, 1, 2], 1, 1), [0, 1, 2]);
  });
});
group('removeFromOrder', () {
  test('drops the item', () => expect(removeFromOrder([0, 1, 2], 0, 2), [0, 1]));
  test('never drops current', () => expect(removeFromOrder([0, 1, 2], 1, 1), [0, 1, 2]));
});
group('queueTimeLeft', () {
  test('rest of current + following, scaled by rate', () {
    expect(
      queueTimeLeft(order: [2, 0, 1], current: 0, durationsMs: [60000, 30000, 10000],
          currentDuration: const Duration(seconds: 60), position: const Duration(seconds: 20), rate: 2),
      const Duration(seconds: 35), // (40 + 30) / 2
    );
  });
  test('null when a following duration is unknown', () {
    expect(queueTimeLeft(order: [0, 1], current: 0, durationsMs: [1000, 0],
        currentDuration: const Duration(seconds: 1), position: Duration.zero, rate: 1), isNull);
    expect(queueTimeLeft(order: [0, 1], current: 0, durationsMs: const [],
        currentDuration: const Duration(seconds: 1), position: Duration.zero, rate: 1), isNull);
  });
  test('last video: just what is left of it', () {
    expect(queueTimeLeft(order: [0, 1], current: 1, durationsMs: const [],
        currentDuration: const Duration(seconds: 10), position: const Duration(seconds: 4), rate: 1),
        const Duration(seconds: 6));
  });
});
```

- [ ] **Step 2:** `flutter test test/player/queue/queue_order_test.dart` → FAIL (undefined).
- [ ] **Step 3: implement**

```dart
List<int> moveInOrder(List<int> order, int from, int to) {
  final out = [...order];
  if (from < 0 || from >= out.length) return out;
  final v = out.removeAt(from);
  out.insert(to.clamp(0, out.length), v);
  return out;
}

List<int> playNextInOrder(List<int> order, int current, int item) {
  if (item == current) return [...order];
  final out = [...order]..remove(item);
  out.insert(out.indexOf(current) + 1, item);
  return out;
}

List<int> removeFromOrder(List<int> order, int current, int item) =>
    item == current ? [...order] : ([...order]..remove(item));

Duration? queueTimeLeft({ ... }) {
  final at = order.indexOf(current);
  if (at < 0 || currentDuration <= Duration.zero) return null;
  var ms = (currentDuration - position).inMilliseconds;
  if (ms < 0) ms = 0;
  for (final i in order.skip(at + 1)) {
    final d = i < durationsMs.length ? durationsMs[i] : 0;
    if (d <= 0) return null;
    ms += d;
  }
  return Duration(milliseconds: (ms / (rate > 0 ? rate : 1)).round());
}
```

- [ ] **Step 4:** tests pass. **Step 5:** commit `feat: operaciones puras para editar el orden de la cola`.

### Task 2: Session model + notifier edits + undo

**Files:**
- Modify: `lib/player/open/video_source.dart`, `lib/ui/player/keys/player_keys.dart` (`queueStep` uses `playOrder`), `lib/ui/player/controls/bottom_bar.dart` (`hasQueue` = `playOrder.length > 1`)
- Create: `lib/player/queue/queue_undo.dart`
- Test: `test/player/open/video_source_edit_test.dart`

**Interfaces — Produces:**
- `VideoSession.playOrder` (`List<int>`), `VideoSession.orderEdited` (`bool`, default false), `VideoSession.queueDurationsMs` (`List<int>`, default const []), `VideoSession withOrder(List<int>? order, {required bool edited})`.
- `enum QueueEditKind { moved, playNext, removed, shuffleReset }`
- `class QueueUndo { final QueueEditKind kind; final int index; final List<int>? order; final bool edited; final bool? shuffle; }`
- `final queueUndoProvider = StateProvider<QueueUndo?>`
- Notifier: `void reorder(int fromPos, int toPos)`, `void playNext(int item)`, `void remove(int item)`, `Future<void> undoQueueEdit()`.
- `setShuffle` records a `shuffleReset` undo when the session was edited.
- `open`/`openPath`/`advanceTo` clear `queueUndoProvider` when the index or path changes.

- [ ] **Step 1: failing tests** (container as in `video_source_queue_test.dart`):
  - `openFromList` fills `queueDurationsMs` from `VideoItem.durationMs`.
  - `reorder(0→2)` on natural order sets `order` `[1,2,0]`-style result, `orderEdited` true, undo kind `moved`.
  - `playNext(3)` while at 0 of 4 → `order [0,3,1,2]`; `peekNext()` is index 3.
  - `remove(1)` → `order` lacks 1, `peekNext()` skips it; `remove(current)` no-op.
  - `undoQueueEdit()` restores previous order and `orderEdited`; clears undo.
  - undo after `advanceTo` to another index → no-op (undo cleared).
  - `setShuffle(true)` after `remove` → order is full-length permutation, undo kind `shuffleReset`; `undoQueueEdit()` → settings shuffle false again and edited order restored.
  - `sessionAt` carries `orderEdited` and `queueDurationsMs`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: implement** (`withOrder` copies every field; edit methods: `final s = state; if (s == null) return; ref.read(queueUndoProvider.notifier).state = QueueUndo(kind, index: s.index, order: s.order, edited: s.orderEdited); state = s.withOrder(newOrder, edited: true);`). Replace the `order ?? List.generate` fallbacks with `playOrder` in `peekNext`, `queueStep`, the strip.
- [ ] **Step 4:** run new + `test/player/open` + `test/ui/player/keys` → PASS. **Step 5:** commit `feat: la sesión admite editar el orden de la cola con deshacer`.

### Task 3: Controls hold/release

**Files:** Modify `lib/ui/player/state/controls_visibility.dart`; Test `test/ui/player/controls_visibility_test.dart`.

**Produces:** `void hold()` (shows, cancels timer, `_holds++`), `void release()` (`_holds--`; at 0 restart timer). `_restartTimer` returns early while `_holds > 0`.

- [ ] Tests: hold → wait past auto-hide → still visible; release → hides after auto-hide. Implement, pass, commit `feat: los controles no se ocultan mientras se sostiene algo`.

### Task 4: SwipeDismissToast + resume toast polish

**Files:**
- Create: `lib/ui/player/widgets/swipe_dismiss_toast.dart`
- Modify: `lib/ui/player/controls/resume_prompt.dart`
- Test: `test/ui/player/swipe_dismiss_toast_test.dart`, `test/ui/player/resume_prompt_test.dart`

**Produces:** `SwipeDismissToast({Key? key, required Widget child, required Duration autoHide, required VoidCallback onDismissed})` — owns: entry (fade + 12px rise, 220ms easeOutCubic), auto-hide timer (paused while a pointer is down), exit on timeout (fade + 8px drop, 180ms), pan in any direction (opacity `1 - dist/160`), release past 56px or velocity > 600px/s → fly off along the drag vector 200ms + fade, then `onDismissed`; else spring back 180ms. `MediaQuery.disableAnimations` → no translation, fade only. Dark capsule surface (`black` α0.82, radius 14) drawn by the shell.

- [ ] Tests: auto-hide fires `onDismissed` after `autoHide` + exit; drag 100px up → dismissed; drag 20px → springs back, not dismissed; drag left 100px dismissed too.
- [ ] `ResumePrompt` uses the shell, `undo` 4s, `ask` 8s, keyed by the prompt state instance; its own Timer is removed. Test: undo prompt gone after ~4.3s, still there at 3.5s.
- [ ] Commit `feat: el aviso de reanudar dura 1 s menos, se anima y se descarta deslizando`.

### Task 5: Shared segmented progress

**Files:** Create `lib/ui/widgets/segmented_progress.dart` (`SegmentedProgress(double fraction, {required Color accent, required Color unlit, int segments = 16, double height = 4})`); modify `video_tile.dart` to use it. Existing tile tests must stay green. Commit `refactor: barra de progreso segmentada compartida`.

### Task 6: Strip — reorder, menu, watched state

**Files:**
- Modify: `lib/ui/player/queue/queue_strip.dart`
- Create: `lib/ui/player/queue/queue_card_menu.dart`
- l10n: `playerQueuePlayNext`, `playerQueueRemove`, `playerQueueCardHint`
- Test: `test/ui/player/queue_strip_test.dart` (add resume/played store overrides)

Details:
- `ReorderableListView.builder(scrollDirection: horizontal, buildDefaultDragHandles: false, onReorderStart, onReorder, onReorderEnd, proxyDecorator)`; items keyed `ValueKey('${queue[i]}#$i')`, wrapped in `ReorderableDelayedDragStartListener(index: pos)`.
- `onReorderStart(pos)`: `_dragFrom = pos; _moved = false; hold(); haptic`. `onReorder(old, new)`: `if (new > old) new--; if (new != old) { _moved = true; notifier.reorder(old, new); }`. `onReorderEnd`: `release()`; if `!_moved` → open menu for `order[_dragFrom]`.
- `proxyDecorator`: `AnimatedBuilder` scale 1→1.06 + `BoxShadow`.
- Menu (`showQueueCardMenu(context, rect, {showPlayNext, showRemove, accent})` → `Future<QueueCardAction?>`): `showGeneralDialog(useRootNavigator: true, barrierDismissible: true, barrierColor: transparent)`, a capsule positioned above the card rect (clamped to the screen), scale/fade in 140ms. The strip holds controls while it is open. Hidden entirely when both actions are hidden (current card's menu has none → no menu, just the lift).
- Card watched state: `progress = resumeSeconds*1000/durationMs` (shown when in (0, 0.97)), `✓` badge when `playedStore.isPlayed(name)` and no resume entry; not for the active card.
- Strip hidden when `playOrder.length <= 1`; `itemCount: order.length`.
- Tests: long-press-drag `a` past `c` reorders (notifier order); long-press-release on `c` shows menu, "Reproducir a continuación" → order puts c after current; "Quitar de la cola" removes; no menu on the current card; duplicate uris don't crash; progress bar on a resumed card, ✓ on a played card.
- Commit `feat: reordenar la tira y menú de reproducir a continuación / quitar`.

### Task 7: Queue undo toast

**Files:** Create `lib/ui/player/queue/queue_undo_toast.dart`; mount in `player_screen.dart` next to `ResumePrompt`; l10n `playerQueueMovedToast`, `playerQueuePlayNextToast`, `playerQueueRemovedToast`, `playerQueueShuffleResetToast` (reuse `commonUndo`). Uses `SwipeDismissToast` (4s), keyed by the `QueueUndo` instance; dismiss → `queueUndoProvider = null`; Deshacer → `undoQueueEdit()`. Sits above the resume toast (bottom 96 + 56) so both can coexist.
- Tests: each kind shows its message; Deshacer restores; disappears after 4s. Commit `feat: aviso con deshacer al editar la cola`.

### Task 8: Position and time-left line

**Files:** Create `lib/ui/player/queue/queue_info_line.dart`; strip becomes `Column(info line, list)`; l10n `playerQueuePosition(pos,total)`, `playerQueueTimeLeft(time)`, `playerQueueEndsAt(clock)`, `playerQueueHoursMinutes(h,m)`, `playerQueueMinutes(m)`.
- Watches `positionProvider`, `durationProvider`, `rateProvider`, repeat setting; `queueTimeLeft`; minutes rounded up; clock via `MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(now + left), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))`. Repeat ≠ off or unknown → counter only. Tabular figures, 10px, white α0.6.
- Tests: counter `2 / 3`; with known durations shows "quedan" text; with repeat list only the counter.
- Commit `feat: posición y tiempo restante de la cola`.

### Task 9: Verify and ship

- [ ] `flutter analyze` clean, `flutter test` all green (real exit codes).
- [ ] PR (gh as yt-kevincarrera), merge as its own step, verify merge on master, bump minor (1.28.0), tag, watch CI, edit release notes after a pause, re-read body.
