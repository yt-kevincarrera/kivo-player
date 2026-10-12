# Acciones al terminar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user choose, per queue session, to send each finished video to the trash and/or to close the player, close Kivo or let the screen sleep when a video ends.

**Architecture:** A pure planner (`planEnd`) decides what an ending does; both completion paths (fullscreen `PlayerScreen`, minimized `AutoplayCoordinator`) consume it. A session-scoped `endActionsProvider` holds the choice; a `trashQueueProvider` stages deletions with an undo window and commits them silently (all-files access) or in one batched system dialog when the player is left. UI: a row in «Más», a panel, a chip in the controls, a trash line on the countdown card, and an undo toast.

**Tech Stack:** Flutter, Riverpod (Notifier/StateProvider), Hive, gen-l10n ARB (es template + en).

**Spec:** `docs/superpowers/specs/2026-10-12-kivo-end-actions-design.md`

## Global Constraints

- Every new user-facing string goes into BOTH `lib/l10n/app_es.arb` and `lib/l10n/app_en.arb` with a description; run `flutter gen-l10n`. `no_hardcoded_strings_test` forbids literals in `lib/`.
- Spanish copy writes "video", never "vídeo". Talk about "el color de acento", read it from `settingsProvider.accentColor`.
- Hive store providers THROW when not overridden; override in `lib/main.dart`; add the override to every test harness that reaches it.
- Never `ref.read` inside `dispose()`.
- No new rows in the player controls (chip floats like the zoom / A-B chips).
- Commits without any AI attribution.

## Review Focus

1. Fixed sleep timer pausing mid-video must never trash or run an action — test in Task 6.
2. Sleep "end of episode" stops 300 ms early: must count as an end, exactly once (no double with a late `completed`) — Task 2 + Task 6.
3. Repeat-video + trash: the file must never be trashed — Task 1.
4. A trashed video must disappear from the play order, and come back on undo — Task 3.
5. The system dialog flush must never include the video currently loaded in the player — Task 3.

---

### Task 1: Model + planner

**Files:**
- Create: `lib/player/end_actions/end_actions.dart`
- Test: `test/player/end_actions/end_plan_test.dart`, `test/player/end_actions/end_actions_provider_test.dart`

**Produces:**
- `enum AfterEnd { keepGoing, closePlayer, closeApp, screenOff }`
- `class EndActions { bool trash; AfterEnd after; bool get isActive; copyWith }`
- `endActionsProvider` (`NotifierProvider<EndActionsNotifier, EndActions>`) with `setTrash(bool)`, `setAfter(AfterEnd)`, `clear()`; resets when `currentVideoProvider`'s `queue` is not `identical` to the previous one.
- `class EndPlan { bool trash; bool advance; AfterEnd? after; }`
- `EndPlan planEnd({required EndActions actions, required bool eligible, required bool repeatVideo, required bool loopActive, required bool autoplayGo})`

- [ ] Tests: loop → nothing; repeatVideo → no trash; ineligible → no trash; keepGoing → advance mirrors autoplayGo; other after → advance false + after; provider resets on new queue, not on `advanceTo`.
- [ ] Implement, run `flutter test test/player/end_actions`, commit.

### Task 2: Sleep "end of episode" signal

**Files:** Modify `lib/player/sleep/sleep_timer.dart`; test `test/player/sleep/sleep_episode_end_test.dart`

**Produces:** `final sleepEpisodeEndProvider = StateProvider<int>((_) => 0);` incremented in `_onPosition` when episode mode reaches its end (before `_fire`). Fixed mode never touches it.

- [ ] Test both modes with the fake clock/positions, implement, commit.

### Task 3: Pending trash store + queue controller

**Files:**
- Create: `lib/player/end_actions/pending_trash.dart` (store interface, Hive + in-memory impls, throwing provider)
- Create: `lib/player/end_actions/trash_queue.dart` (controller)
- Modify: `lib/player/open/video_source.dart` (`dropTrashed(int)`, `restoreTrashed(int item, List<int> previousOrder, bool edited)`, `clear()`)
- Modify: `lib/main.dart` (open box `pendingTrash`, override)
- Test: `test/player/end_actions/trash_queue_test.dart`

**Produces:**
- `class PendingTrash { String uri, name, id; int stagedAtMs; }`
- `pendingTrashStoreProvider` (throws), `HivePendingTrashStore`, `InMemoryPendingTrashStore`
- `trashQueueProvider` (`NotifierProvider<TrashQueue, List<PendingTrash>>`):
  `Future<void> stage(VideoItem item, {VideoSession? ended})`, `Future<void> undo(String uri)`, `Future<FileOpStatus?> flushInteractive()`, `Future<void> commitSilentlyIfPossible()`, `Future<bool> isSilent()`, `bool get busy`.
- `trashUndoProvider` (`StateProvider<TrashUndo?>`, `TrashUndo { PendingTrash entry; bool silent; bool toTrash; }`)
- `trashUndoWindowProvider` (`Provider<Duration>`, 5 s; tests override).
- `VideoItem? libraryItemFor(Ref|WidgetRef, VideoSession)` helper.
- `trashFlushRequestProvider` (`StateProvider<int>`) bumped by the mini-player close.

- [ ] Tests: stage persists + publishes undo; undo removes + restores order; silent commit after window calls `deleteMany`; non-silent stays pending; flush deletes all but the loaded video, empties the store; order drops the trashed index.
- [ ] Implement, run, commit.

### Task 4: After-end runner

**Files:** Create `lib/player/end_actions/after_end_runner.dart`; test `test/player/end_actions/after_end_runner_test.dart`

**Produces:** `screenOffProvider` (`StateProvider<bool>`), and `Future<void> runAfterEndMinimized(Ref ref, AfterEnd a)` for the coordinator; fullscreen variant lives in `PlayerScreen` (needs its Navigator). `closeApp` calls an injectable `appExitProvider` (`Provider<void Function()>`, default `SystemNavigator.pop`).

- [ ] Test minimized closePlayer/closeApp state effects with fakes; implement; commit.

### Task 5: Strings

**Files:** `lib/l10n/app_es.arb`, `lib/l10n/app_en.arb`, regenerate.

Keys: `endActionsTitle`, `endActionsMenuSubtitleNone`, `endActionsTrashTitle`, `endActionsTrashSubtitle`, `endActionsDeleteTitle`, `endActionsTrashNotLibrary`, `endActionsTrashRepeatVideo`, `endActionsAfterTitle`, `endActionsAfterKeepGoing`, `endActionsAfterClosePlayer`, `endActionsAfterCloseApp`, `endActionsAfterScreenOff`, `endActionsFinishNow`, `endActionsTrashAndNext`, `endActionsChipTrash`, `endActionsChipOff`, `endActionsCardTrashLine`, `endActionsCardDeleteLine`, `endActionsKeep`, `endActionsCountdownClosePlayer`, `endActionsCountdownCloseApp`, `endActionsCountdownScreenOff`, `endActionsNow`, `trashUndoMoved`, `trashUndoOnExit`, `trashUndoDeleteOnExit`, `pendingTrashTitle(count)`, `pendingTrashDeleteTitle(count)`, `pendingTrashMove`, `pendingTrashDelete`, `pendingTrashKeep`.

- [ ] Add, `flutter gen-l10n`, `flutter test test/l10n`, commit.

### Task 6: Wire completion paths

**Files:** Modify `lib/ui/player/player_screen.dart`, `lib/player/autoplay/autoplay_coordinator.dart`, `lib/ui/player/state/autoplay_state.dart` (`endTrashProvider`, `afterPendingProvider`, `afterConfirmProvider`), `lib/ui/mini_player/mini_player_bar.dart` (bump flush request); tests `test/ui/player/end_actions_wiring_test.dart`.

- [ ] Tests: natural end + trash → overlay → advance stages previous; Conservar keeps it; Cancelar does nothing; closePlayer countdown pops with no mini-bar; fixed sleep pause stages nothing; sleep episode end stages once.
- [ ] Implement per spec «Flujo en pantalla completa» / «Flujo minimizado», plus screenOff (save brightness, `setBrightness(0)`, `keepAwake(false)`; restore on play / controls shown).
- [ ] Run full player tests, commit.

### Task 7: UI — overlay line, action card, chip, panel, menu row, undo toast, pending sheet

**Files:**
- Modify `lib/ui/player/autoplay/autoplay_overlay.dart`
- Create `lib/ui/player/end_actions/end_actions_chip.dart`, `end_actions_panel.dart`, `trash_undo_toast.dart`
- Modify `lib/ui/player/controls/controls_overlay.dart`, `lib/ui/player/more/more_menu.dart`, `lib/ui/player/player_screen.dart` (toast layer)
- Create `lib/ui/home/pending_trash_sheet.dart`; modify `lib/ui/home/home_shell.dart` (flush on player exit / mini close request; sheet on start/resume)
- Tests under `test/ui/player/end_actions/` and `test/ui/home/pending_trash_sheet_test.dart`

- [ ] Widget tests per spec «Pruebas → Widgets», implement, `flutter analyze`, full `flutter test`, commit.

### Task 8: Release

- [ ] Whole-branch review (fresh reviewer), fix findings.
- [ ] Bump `pubspec.yaml` to 1.30.0 (+ build), PR on `yt-kevincarrera`, merge as its own step, verify merge on master, tag `v1.30.0`, watch CI, edit release notes later, re-read body.
