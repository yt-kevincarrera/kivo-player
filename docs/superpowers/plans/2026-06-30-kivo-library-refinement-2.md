# Kivo Library Refinement v2 + Resume Bug Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Bigger/cleaner library tiles with a "Nuevo" badge and options affordance, deeper-inset video sections, pure-slide tab switch, step-wise pinch, a smooth reflow, and a fix for the restart-doesn't-persist resume bug.

**Architecture:** Three tasks on disjoint files, run SEQUENTIALLY (never parallel). Task 1 (`video_tile.dart`) → Task 2 (`library_screen.dart`, depends on Task 1's new VideoTile params) → Task 3 (resume bug: `resume_prompt.dart`, `player_screen.dart`, `player_controller.dart`).

**Tech Stack:** Flutter (Material 3), Riverpod.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-06-30-kivo-library-refinement-2-design.md`.
- `AnimationController` ALWAYS created/assigned in `initState`, disposed — never a field initializer.
- Never `ref.read(...)` in `dispose()`. `withValues(alpha:)`, not `withOpacity`.
- Library uses `Theme.of(context)` colorScheme roles; brand `KivoColors.blue`/`gold`. PLAYER stays untouched except Task 3's restart wiring in `player_screen.dart`.
- `flutter analyze` clean + `flutter test` green before each commit. Do not push.

---

### Task 1: VideoTile — bigger preview, "Nuevo" badge, options icon

**Files:** Modify `lib/ui/home/widgets/video_tile.dart`; Test `test/ui/home/video_tile_test.dart`.

**Interfaces:**
- Produces: `VideoTile({required VideoItem video, double? progress, bool listRow = false, String? sizeLabel, bool isNew = false, VoidCallback? onOptions, required VoidCallback onTap})` — adds `isNew` and `onOptions`; all prior params unchanged.

- [ ] **Step 1: Bigger list-row.** In the `listRow == true` layout: thumbnail block width **168** (was 150), 16:9. Title fontSize **16**, w600, `cs.onSurface`, 2 lines ellipsis. Size line fontSize **14**, `cs.onSurfaceVariant`. Ensure the thumbnail reads as prominent (not visually smaller than the text column). Keep `_SegmentedProgress`, `_badge`, Hero, `ThumbnailImage`. Whole row stays inside one `PressBounce(onTap:)`.
- [ ] **Step 2: "Nuevo" badge.** When `isNew == true`, show a small discreet pill labeled `Nuevo` on the thumbnail (top-left), `KivoColors.blue` background, white text ~9–10px, rounded. Cover mode (`listRow:false`) shows it too (top-left), consistent with the duration badge at top-right.
- [ ] **Step 3: Options "⋮" icon.** In the list-row, at the far right of the row, add a vertical 3-dots icon button (`Icons.more_vert`, `cs.onSurfaceVariant`, ~20px) wrapped so it does NOT trigger the row's onTap (its own `GestureDetector`/`IconButton` with `onPressed: onOptions ?? () {}`). Visual reference only for now. (Cover mode does not need the ⋮.)
- [ ] **Step 4: Tests.** Extend `video_tile_test.dart`: list-row with `isNew: true` shows `find.text('Nuevo')`; the ⋮ (`find.byIcon(Icons.more_vert)`) is present in list-row; tapping the title still fires `onTap`; tapping ⋮ does NOT fire the row `onTap` (fires `onOptions` if provided). Wrap in `MaterialApp(theme: KivoTheme.light())`.
- [ ] **Step 5: Analyze + test + commit** — `feat: bigger list-row tile + "Nuevo" badge + options affordance`.

---

### Task 2: LibraryScreen — inset, slide tabs (PageView), step pinch, smooth reflow

**Files:** Modify `lib/ui/home/library_screen.dart`; Test `test/ui/home/library_screen_test.dart`.

**Interfaces:** Consumes `VideoTile(isNew:, onOptions:)` from Task 1.

- [ ] **Step 1: Deeper horizontal inset for video sections.** The video list/grid slivers use a larger horizontal padding (~**20**) than the "Continuar" strip (which keeps ~12). Section date headers align with the video content inset. The visible result: video rows are inset more than the Continuar cards.
- [ ] **Step 2: Smaller vertical gap.** Reduce the per-list-row bottom gap from 14 to **~7px**.
- [ ] **Step 3: "Nuevo" wiring.** Compute `isNew` per video: added within the last 3 days. Add a pure helper `bool isNewVideo(int dateAddedMs, DateTime now) => now.difference(DateTime.fromMillisecondsSinceEpoch(dateAddedMs)).inDays < 3;` (put in `lib/core/format.dart` or a small util, and unit-test it). Pass `isNew: isNewVideo(v.dateAddedMs, DateTime.now())` and `onOptions: null` (placeholder) to each `VideoTile`.
- [ ] **Step 4: Tab transition = PageView slide (no fade).** Replace the `_body` `AnimatedSwitcher` with a controlled `PageView` (2 pages: videos feed, folders grid). Hold a `PageController`. A chip tap calls `_pageController.animateToPage(i, duration: 250ms, curve: Curves.easeOutCubic)`; `onPageChanged` updates `_tab` (so swiping also flips the chip). No fade — PageView slides. The chips row stays fixed above the PageView. Keep each page's content (the `_videosTab`/`_foldersTab` bodies). Dispose the `PageController`.
- [ ] **Step 5: Step-wise pinch (one step per gesture).** Rework the scale handler: add `bool _pinchStepDone = false;`. `onScaleStart`: `_pinchStepDone = false`. `onScaleUpdate`: if `_pinchStepDone` is true OR `d.pointerCount < 2`, return. Compute `rel = d.scale` (cumulative from gesture start — no baseline needed since one step per gesture). If `rel > 1.08` → `next = (cols - 1).clamp(1,3)`; else if `rel < 0.92` → `next = (cols + 1).clamp(1,3)`; else return. If `next != cols`: apply it (haptic + persist), set `_pinchStepDone = true` (locks until the gesture ends). This guarantees one column step per pinch regardless of magnitude, so 1→2→3 are each reachable.
- [ ] **Step 6: Smooth reflow (subtle, no violence).** Keep the `_reflowCtrl` (AnimationController in initState/dispose) and `ref.listen` on `libraryColumns` triggering `forward(from:0)`. Change the per-tile transform: instead of `fromScale = prevExtent/newExtent` (which is 0.5/2.0 — violent), use a **subtle fixed settle**: `scale = lerpDouble(0.92, 1.0, curved)!` (Curves.easeOutCubic, duration **300ms**), applied uniformly to tiles during the animation; at rest return the child unscaled (scale 1.0). The grid lays out at the new `cols` immediately (positions final, scroll preserved). No opacity/fade. Remove any reliance on `_prevCols` extent ratio for the scale (you may keep `_prevCols` only if still needed to detect change; the scale itself is the fixed 0.92→1.0 settle).
- [ ] **Step 7: Tests.** Update `library_screen_test.dart`: chip "Todo"/"Carpetas"; tapping "Carpetas" shows a folder (now via PageView — use `pumpAndSettle`); a known video appears in the feed. Keep provider overrides; wrap in `MaterialApp(theme: KivoTheme.light())`.
- [ ] **Step 8: Analyze + test + commit** — `feat: deeper inset, smaller row gap, PageView slide tabs, step pinch, smooth reflow, Nuevo wiring`.

---

### Task 3: Resume "Reiniciar" must persist (clear stored resume)

**Files:** Modify `lib/ui/player/controls/resume_prompt.dart`, `lib/ui/player/player_screen.dart`, `lib/player/control/player_controller.dart` (provider home); Test `test/player/control/player_controller_test.dart` or a resume test.

**Interfaces:**
- Produces: `restartRequestProvider = StateProvider<int>((ref) => 0)` (a tick incremented to request a from-zero restart).

- [ ] **Step 1: Add `restartRequestProvider`.** Put `final restartRequestProvider = StateProvider<int>((ref) => 0);` in `lib/player/control/player_controller.dart` (next to the other player StateProviders).
- [ ] **Step 2: ResumePrompt signals restart.** In `resume_prompt.dart`:
  - undo mode "Reiniciar": replace `() { ctrl.seekTo(Duration.zero); _clear(); }` with `() { ref.read(restartRequestProvider.notifier).state++; _clear(); }`.
  - ask mode "Desde el inicio": replace `_clear` with `() { ref.read(restartRequestProvider.notifier).state++; _clear(); }`.
  - ask mode "Reanudar" stays `() { ctrl.seekTo(s.savedPosition); _clear(); }`.
  - Import the provider as needed.
- [ ] **Step 3: PlayerScreen handles restart.** In `player_screen.dart`:
  - In `_start()`, add `ref.read(restartRequestProvider.notifier).state = 0;` to the per-entry resets (alongside `dismissProvider`/`resumePromptProvider`).
  - In `build`, add `ref.listen<int>(restartRequestProvider, (prev, next) { if (next > 0) { ref.read(playerControllerProvider).seekTo(Duration.zero); _resume.clear(_resumeKey!); _lastPosition = Duration.zero; } });`. (`_resume` and `_resumeKey` are the cached fields; this runs in build where `ref` is valid. `_resume.clear` returns a Future — fire-and-forget is fine.)
- [ ] **Step 4: Test.** In `player_controller_test.dart` (or a focused resume test), assert the behavior at the service level: after a resume entry exists, calling `ResumeService.clear(key)` makes `positionFor(key)` null and `planResume(null, 'auto')` yields `startAt == Duration.zero`. (The provider wiring is device-verified; keep it analyzer-clean. If a widget test for ResumePrompt is practical, assert tapping "Reiniciar" increments `restartRequestProvider`.)
- [ ] **Step 5: Analyze + test + commit** — `fix: "Reiniciar"/"Desde el inicio" clears persisted resume (restart now sticks)`.

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review (opus).
3. Release build to the Pixel 6: verify bigger tiles + "Nuevo" + ⋮; video sections inset deeper than Continuar; smaller row gap; chips pure-slide; pinch reaches 1/2/3 by steps; smooth reflow; and restart-then-exit-then-reenter starts from the beginning.
