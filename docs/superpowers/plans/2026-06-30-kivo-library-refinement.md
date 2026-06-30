# Kivo Library Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the redesigned library spacious and reliably tactile, with a gallery-style pinch and an animated tile reflow (no weird fades).

**Architecture:** Two file-disjoint tasks. Task 1 owns the tile/press widgets (`press_bounce.dart`, `video_tile.dart`, `folder_grid.dart` press call-site). Task 2 owns the screen (`library_screen.dart`, `continue_row.dart`). Run sequentially (Task 1 then Task 2) — never in parallel.

**Tech Stack:** Flutter (Material 3), Riverpod. Implicit animations + a single `AnimationController` for the reflow.

## Global Constraints

- Source of truth: `docs/superpowers/specs/2026-06-30-kivo-library-refinement-design.md`.
- Every `AnimationController` MUST be created in `initState` and disposed — NEVER a `late final` field initializer (crashes test teardown).
- Never `ref.read(...)` in `dispose()`. Use `withValues(alpha:)`, never `withOpacity`.
- Library/chrome surfaces use `Theme.of(context).colorScheme` roles; brand accents `KivoColors.blue` (active) / `KivoColors.gold` (progress/pills). The PLAYER stays untouched.
- `flutter analyze` clean + `flutter test` green before each commit. Do not push.

---

### Task 1: Tap-pulse PressBounce + bigger tappable list-row tile

**Files:**
- Modify: `lib/ui/widgets/press_bounce.dart`
- Modify: `lib/ui/home/widgets/video_tile.dart`
- Modify: `lib/ui/home/widgets/folder_grid.dart` (migrate its `PressBounce` call-site)
- Test: `test/ui/home/video_tile_test.dart` (keep green; the list-row tap test must still pass)

**Interfaces:**
- Produces: `PressBounce({required VoidCallback onTap, required Widget child})` — a confirmed-tap pulse wrapper. It owns the tap detection internally (a `GestureDetector(onTap:)`), so a touch that becomes a scroll does NOT pulse. On a confirmed tap it plays a quick scale pulse (1.0→1.04→1.0) and then calls `onTap`.
- `VideoTile` public constructor is UNCHANGED: `VideoTile({required VideoItem video, double? progress, bool listRow = false, String? sizeLabel, required VoidCallback onTap})`.

- [ ] **Step 1: Rewrite `PressBounce` as a confirmed-tap pulse.** Make it a `StatefulWidget` with an `AnimationController` created in `initState` (duration ~150ms) and disposed in `dispose`. New API: `const PressBounce({super.key, required this.onTap, required this.child})`. Build a `GestureDetector(onTap: _handleTap, child: ScaleTransition(scale: _pulse, child: child))` where `_pulse` is a `TweenSequence` 1.0→1.04→1.0 (`Curves.easeOut`). `_handleTap()` runs `_controller.forward(from: 0)` then calls `widget.onTap()`. Because the pulse is driven by the confirmed `onTap` (not `onTapDown`), it never fires while scrolling. Remove the old press-hold scale-down behavior entirely.

- [ ] **Step 2: Run/adjust any PressBounce test** (`flutter test` — if a test references the old API, update it to pass an `onTap`). Verify it compiles.

- [ ] **Step 3: Migrate `video_tile.dart` to the new PressBounce + bigger tappable list-row.** Both layouts wrap in `PressBounce(onTap: onTap, child: ...)` (remove any inner `GestureDetector(onTap:)` — PressBounce now carries the tap). 
  - **List-row (`listRow == true`):** the WHOLE row is the PressBounce child (thumbnail + text), so tapping the text opens the video. Thumbnail block width **150** (was ~132), 16:9 `ClipRRect` with `Hero` + `ThumbnailImage` + duration badge + `_SegmentedProgress` when `progress != null`. Right side `Expanded(Column)`: title `cs.onSurface`, **fontSize 15**, `FontWeight.w600`, 2 lines ellipsis; spacer; size line `sizeLabel` `cs.onSurfaceVariant`, **fontSize 13**. Add internal vertical padding so the row has height/air (e.g. row content padding `EdgeInsets.symmetric(vertical: 4)` plus the screen-level row gap from Task 2).
  - **Cover (`listRow == false`):** unchanged layout, just wrapped in the new `PressBounce(onTap:)`.
  - Keep `_SegmentedProgress` and `_badge` and the theme-aware colors from the prior round.

- [ ] **Step 4: Migrate `folder_grid.dart` press call-site** — change `PressBounce(child: GestureDetector(onTap: () => onOpenFolder(...), child: _FolderCard(...)))` to `PressBounce(onTap: () => onOpenFolder(...), child: _FolderCard(...))`. No other folder_grid changes required here.

- [ ] **Step 5: Update `video_tile_test.dart`** so the list-row tap test taps the TITLE text (not the thumbnail) and asserts `onTap` fires — proving the whole row is tappable. Keep the cover test. Wrap in `MaterialApp(theme: KivoTheme.light())`.

- [ ] **Step 6: Analyze + test + commit** — `feat: confirmed-tap pulse PressBounce; bigger fully-tappable list-row tile`.

---

### Task 2: LibraryScreen — spacing, "Todo", chip slide, gallery pinch + animated reflow

**Files:**
- Modify: `lib/ui/home/library_screen.dart`
- Modify: `lib/ui/home/widgets/continue_row.dart`
- Test: `test/ui/home/library_screen_test.dart` (extend/keep green)

**Interfaces:**
- Consumes: `VideoTile(listRow:)` (Task 1), `settings.libraryColumns`, `continueWatchingProvider`, `groupByDay`, `FolderGrid`.

- [ ] **Step 1: Spacing.** List feed at `cols == 1`: add ~**14px** vertical gap between rows (e.g. wrap each list tile in `Padding(EdgeInsets.only(bottom: 14))`, or use a `SliverList` with separator-like padding). Page horizontal padding ~**16**. Section header padding more generous (`EdgeInsets.fromLTRB(16, 18, 16, 8)`). "Continuar" strip gets more top/bottom air. Grid (`cols > 1`) keep `crossAxisSpacing`/`mainAxisSpacing` ~10–12.

- [ ] **Step 2: Rename chip "Todas" → "Todo".** Update `_FilterChips` label and the test expectations.

- [ ] **Step 3: Chip transition = fast horizontal slide.** Replace the body `AnimatedSwitcher` cross-fade between `_videosTab`/`_foldersTab` with a slide: use `AnimatedSwitcher(duration: 200ms, switchInCurve: Curves.easeOutCubic, transitionBuilder:)` returning a `SlideTransition` (offset Tween from `Offset(±0.15, 0)` → `Offset.zero`) combined minimally — direction depends on whether `_tab` increased (slide in from right) or decreased (from left). Track `_prevTab` to pick direction. NO opacity cross-fade as the primary effect (a tiny fade is OK to avoid a hard edge, but the motion is the slide).

- [ ] **Step 4: Gallery pinch (any direction + reach 2 columns).** Keep the feed wrapped in a `GestureDetector(onScaleStart/onScaleUpdate)`. Make it claim 2-finger scale in any direction: set `onScaleStart` to reset `_scaleBaseline = 1.0`; in `_onScaleUpdate`, only act when `d.pointerCount >= 2` (ensures it's a real pinch, not a pan), compute `rel = d.scale / _scaleBaseline`, and step ONE column per notch — `rel > 1.15` → `cols-1` (clamp 1..3), `rel < 0.87` → `cols+1` (clamp 1..3) — then reset `_scaleBaseline = d.scale` so the next notch needs a fresh pinch. This makes 1↔2↔3 each reachable (no 1→3 skip). Haptic + persist on each change. (The any-direction behavior comes for free from `ScaleGestureRecognizer` once we gate on `pointerCount >= 2` rather than expecting horizontal movement.)

- [ ] **Step 5: Animated reflow (stepwise, no fade).** Add `late final AnimationController _reflowCtrl;` created in `initState` (duration **260ms**, `Curves.easeOutCubic`) and disposed. Track `int _prevCols` (init to current `libraryColumns`). When `libraryColumns` changes (detect via `ref.listen(settingsProvider...)` on `libraryColumns`, or compare in build), set `_prevCols = old; _reflowCtrl.forward(from: 0)`. In the feed builder, wrap each grid/list tile in an `AnimatedBuilder(animation: _reflowCtrl, ...)` that applies a scale from the tile's previous relative extent to its new one: `fromScale = prevTileExtent / newTileExtent` where `tileExtent = (usableWidth / cols)`; the tile starts at `fromScale` and animates to `1.0` via `_reflowCtrl.value` (eased). The grid lays out IMMEDIATELY at the new `cols` (so positions are final); only the per-tile scale animates → the "reacomodado" settle, no fade. For the 1↔2 boundary (list↔grid layout-type change) the same scale settle applies to whatever tile is shown; a tiny opacity 0.9→1.0 is acceptable but not a full cross-fade. Remove the old `AnimatedSwitcher(key: ValueKey(cols))` that wrapped the whole `CustomScrollView` (that caused the fade + scroll-reset).
  - Reconcile with the existing per-section/tile entrance `TweenAnimationBuilder`: the entrance fade-in should play once on first appearance; the reflow scale is a separate wrapper. Don't let a density change re-trigger the full entrance fade for every tile (keep entrance keyed/guarded so it doesn't restart on reflow). If they conflict, prefer keeping the reflow scale and making the entrance animation play only on first build.

- [ ] **Step 6: `continue_row.dart` spacing/sizes** — give the "Continuar" label and the horizontal cards coherent padding/sizing with the rest (label `cs.onSurface`, comfortable padding). Cards already use `VideoTile(listRow:false)`.

- [ ] **Step 7: Update `library_screen_test.dart`** — chip says "Todo"; tapping "Carpetas" shows a folder; a known video appears in the Todo feed. Wrap in `MaterialApp(theme: KivoTheme.light())`. Keep existing override setup. (The slide/reflow are device-verified; just keep widget tests green — `pumpAndSettle` where transitions run.)

- [ ] **Step 8: Analyze + test + commit** — `feat: library spacing, Todo chip slide, gallery pinch (any-dir, reaches 2 cols), animated reflow`.

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review (opus) over the refinement commits.
3. Release build to the Pixel 6: comfortable spacing; whole-row taps work; bigger thumbs/text; tap pulse (no scale-down on scroll); fast chip slide; pinch any-direction reaching 1/2/3; reflow looks like a reacomodado (no fade).
