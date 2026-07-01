# Kivo Library Refinement v4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Fix the tab-switch thumbnail flicker (PageView disposing offscreen pages), fix "Continuar viendo" staleness (save-before-pop race), and unify the folder views with the main library's look via a shared density-feed widget.

**Architecture:** Three tasks, run SEQUENTIALLY (Task 1 is file-disjoint from 2/3, but keep the established one-implementer-at-a-time discipline anyway). Task 1: `player_screen.dart` only (the staleness fix — dispatch first, it's the highest-value bug). Task 2: `library_screen.dart` only (flicker fix, keep-alive wrapper). Task 3: extract `VideoDensityFeed` (new file) from `library_screen.dart`, wire into `folder_screen.dart`, polish `folder_grid.dart` (depends on Task 2 already being in `library_screen.dart`).

**Tech Stack:** Flutter (Material 3), Riverpod.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-01-kivo-library-refinement-4-design.md`.
- `AnimationController` created/assigned in `initState`, disposed — never a field initializer.
- Never `ref.read(...)` in `dispose()`.
- `withValues(alpha:)`, not `withOpacity`. Theme `colorScheme` roles; brand `KivoColors`.
- `flutter analyze` clean + `flutter test` green before each commit. Do not push.

---

### Task 1: Fix "Continuar viendo" staleness — save progress before pop, one choke point

**Files:** Modify `lib/ui/player/player_screen.dart`. Test: extend `test/ui/player/player_screen_controls_test.dart` or a focused test if practical.

**Interfaces:** No public API change — internal behavior only.

**Context:** All 3 exit paths (top bar back button `top_bar.dart:21`, system back, and the swipe-down dismiss gesture in `player_gestures.dart:168`) call `Navigator.of(context).maybePop()`. The caller screen's `.then((_) => invalidate(...))` fires as soon as `pop()` runs — well before `PlayerScreen.dispose()` executes (Flutter defers `dispose()` until the exit transition animation completes, ~300ms later). `dispose()` is where the most accurate final `_saveProgress()` write happens, so the invalidate can race ahead of it. Intercepting the pop and awaiting the save first, in ONE place, fixes all 3 exit paths without touching `top_bar.dart` or `player_gestures.dart`.

- [ ] **Step 1: Wrap the build's returned widget in a `PopScope`.** In `player_screen.dart`'s `build()`, change the current `return Scaffold(...)` to:
```dart
return PopScope(
  canPop: false,
  onPopInvokedWithResult: (didPop, result) async {
    if (didPop) return;
    await _saveProgress();
    if (mounted) Navigator.of(context).pop();
  },
  child: Scaffold(
    // ...unchanged existing Scaffold body...
  ),
);
```
  `_saveProgress()` already exists and is idempotent-safe (guards on `_lastDuration == Duration.zero`, and `ResumeService.record` is safe to call repeatedly — confirmed in the prior round's review). This makes the ACTUAL pop (and therefore the caller's `.then`) wait until the write has landed.

- [ ] **Step 2: Keep the `dispose()` call to `_saveProgress()` as a safety net** (unchanged) — it's now a no-op in the common case (already saved by the `PopScope` path) but still protects against any exit that bypasses normal pop (e.g., the app being killed while `WidgetsBindingObserver.didChangeAppLifecycleState` already handles backgrounding separately — leave that as-is too).

- [ ] **Step 3: Verify the swipe-down dismiss gesture still works end-to-end.** `player_gestures.dart`'s `_onVerticalEnd` calls `_dismissAnim.animateTo(1.0).then((_) { ... Navigator.of(context).maybePop(); ... })`. With `PopScope(canPop:false)`, this `maybePop()` call now triggers `onPopInvokedWithResult(false, null)` instead of immediately popping — our handler awaits the save then calls `Navigator.of(context).pop()` itself, which THEN actually removes the route. This should be visually seamless (the dismiss animation already finished; the extra delay is a fast in-memory Hive write, imperceptible). No changes needed to `player_gestures.dart` — just confirm behavior with a manual read-through, no code change required there.

- [ ] **Step 4: Test.** In `test/ui/player/player_screen_controls_test.dart` (or a new focused test), verify: pump `PlayerScreen`, simulate enough playback that `_lastPosition`/`_lastDuration` are non-zero (the existing test setup likely already exercises this via `FakePlaybackEngine`), trigger a pop (e.g., `Navigator.of(tester.element(find.byType(PlayerScreen))).pop()` or simulate back), and assert the resume store has the expected entry BEFORE the pop's future completes / immediately after `pumpAndSettle`. If wiring a precise pop-vs-save ordering test is impractical with the existing fakes, it's acceptable to instead add a simpler test asserting that popping the route results in `resumeService.entries()` reflecting the last known position (end-to-end behavioral proof), and note in your report if a stricter ordering assertion wasn't feasible.

- [ ] **Step 5: Analyze + test + commit** — `feat: save progress before pop so Continuar updates instantly on any exit`.

---

### Task 2: Fix Todo<->Carpetas thumbnail flicker (PageView keep-alive)

**Files:** Modify `lib/ui/home/library_screen.dart`. Test: extend `test/ui/home/library_screen_test.dart` if a meaningful assertion is practical (this is primarily a device-verified visual/behavioral fix).

**Context:** `PageView(children: [...])` disposes offscreen page Elements once they exceed the viewport's cache extent (a few hundred px, much less than a full page width). Since `ThumbnailImage` watches an `autoDispose` `FutureProvider`, every video tile's thumbnail re-fetches and re-plays its placeholder→image fade-in each time the Todo page is rebuilt from scratch after returning from Carpetas. The standard Flutter fix is `AutomaticKeepAliveClientMixin`.

- [ ] **Step 1: Add a small keep-alive wrapper widget** at the bottom of `library_screen.dart` (private, file-local):
```dart
class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});
  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return widget.child;
  }
}
```
- [ ] **Step 2: Wrap both PageView children in `_body()`.** Change:
```dart
children: [
  _videosTab(videos, key: const ValueKey(0)),
  _foldersTab(videos, key: const ValueKey(1)),
],
```
to:
```dart
children: [
  _KeepAlivePage(key: const ValueKey(0), child: _videosTab(videos)),
  _KeepAlivePage(key: const ValueKey(1), child: _foldersTab(videos)),
],
```
(Move the `ValueKey` to the wrapper; `_videosTab`/`_foldersTab` no longer need their own `key` parameter for this purpose — if removing the `{Key? key}` param from those methods entirely is cleaner, do so, but only if nothing else relies on it. Check call sites before removing the parameter.)

- [ ] **Step 3: Verify no regression.** The pinch `GestureDetector` and `CustomScrollView` inside `_videosTab` are unaffected — only the page's lifecycle (kept mounted) changes. Confirm `flutter analyze` is clean and existing tests in `library_screen_test.dart` still pass (they don't rely on page disposal).

- [ ] **Step 4: Analyze + test + commit** — `fix: keep PageView pages alive to stop thumbnail flicker on tab switch`.

---

### Task 3: Extract shared `VideoDensityFeed`; use it in FolderScreen; polish FolderGrid

**Files:**
- Create: `lib/ui/home/widgets/video_density_feed.dart`
- Modify: `lib/ui/home/library_screen.dart` (use the extracted widget in `_videosTab`), `lib/ui/home/folder_screen.dart` (use the extracted widget), `lib/ui/home/widgets/folder_grid.dart` (inset/typography polish only)
- Test: `test/ui/home/video_density_feed_test.dart` (new), keep `library_screen_test.dart` and add/extend a `folder_screen_test.dart` if one exists (check `test/ui/home/` for an existing folder screen test; create one if none exists and it's cheap to do so).

**Interfaces:**
- Produces: `VideoDensityFeed({required List<VideoItem> videos, required void Function(VideoItem current, List<VideoItem> all) onOpen, bool groupByDate = true, bool showContinueRow = true})` — a `ConsumerStatefulWidget` encapsulating pinch-to-resize, animated reflow, list-row/cover switching, and per-tile "Nuevo"/progress/size wiring.

- [ ] **Step 1: Read the CURRENT `library_screen.dart`** (after Task 2 lands) to get the exact `_onScaleUpdate`/`_reflowCtrl`/`_reflowTile`/`_videosTab` code before extracting — do not guess at line numbers; the keep-alive change from Task 2 will have shifted things slightly.

- [ ] **Step 2: Create `lib/ui/home/widgets/video_density_feed.dart`.** Move into this new `ConsumerStatefulWidget` (`_VideoDensityFeedState extends ConsumerState<VideoDensityFeed>`):
  - Fields: `bool _pinchStepDone`, `late final AnimationController _reflowCtrl`, `late final Animation<double> _reflow` — created in `initState` (duration 320ms, `Curves.easeInOut`, `value: 1.0` at rest) and disposed in `dispose`.
  - `_onScaleUpdate`, `_setColumns`, the `ref.listen` on `settingsProvider.select((s) => s.libraryColumns)` (move this into `build()` of the new widget), `_reflowTile`.
  - The `build()` method: read `final cols = ref.watch(settingsProvider).libraryColumns;`, `final played = ref.watch(playedKeysProvider);` (import `../../../player/library/played.dart`), `final continueItems = { for (final c in ref.watch(continueWatchingProvider)) c.video.name: c };` (import `../../../player/library/continue_watching.dart`), `final cs = Theme.of(context).colorScheme;`, `final accentColor = Color(ref.watch(settingsProvider).accentColor);`.
  - `final sections = widget.groupByDate ? groupByDay(widget.videos, DateTime.now()) : [DaySection(label: '', items: widget.videos)];` — check the actual `DaySection`/`groupByDay` signature in `lib/player/library/library_grouping.dart` first (read it) and adapt so the `groupByDate: false` case produces a single implicit "section" with no visible header. If `DaySection` isn't easily constructible directly (e.g., private constructor), instead special-case the sliver-building loop: when `!widget.groupByDate`, skip the header sliver entirely and iterate `widget.videos` directly in one `SliverList`/`SliverGrid` (don't force it through the day-grouping data structure if it doesn't fit cleanly — prefer a small `if (widget.groupByDate) { ...sectioned... } else { ...flat... }` split in the sliver-building code over fighting the data type).
  - `SliverToBoxAdapter(child: ContinueRow(...))` only appears `if (widget.showContinueRow)`.
  - Each tile: `isNew: !played.contains(v.name)`, `onOptions: null`, `sizeLabel`/`listRow` exactly as today, `onTap: () => widget.onOpen(v, widget.videos)`.
  - The outer `GestureDetector(onScaleStart, onScaleUpdate, child: CustomScrollView(...))` wraps everything, same as today.
  - Keep the horizontal inset at **24** (the `_sectionPad`/`SliverPadding` constant) for both grouped and flat modes.

- [ ] **Step 3: `library_screen.dart` uses the extracted widget.** Replace the body of `_videosTab` with: `VideoDensityFeed(videos: videos, onOpen: (v, all) => _open(v, all), groupByDate: true, showContinueRow: true)`. Remove the now-moved fields/methods (`_pinchStepDone`, `_reflowCtrl`, `_reflow`, `_onScaleUpdate`, `_setColumns`, `_reflowTile`, the `ref.listen` for columns) from `_LibraryScreenState` — but KEEP `_cycleDensity()` (the AppBar icon action) since it just writes to `settingsProvider`, which `VideoDensityFeed` reactively picks up. Keep the `_KeepAlivePage` wrapper from Task 2 wrapping the (now much thinner) `_videosTab(videos)` call.

- [ ] **Step 4: `folder_screen.dart` uses the extracted widget.** Replace the `GridView.builder` body with:
```dart
body: VideoDensityFeed(
  videos: videos,
  onOpen: (v, all) => _open(context, ref, v),
  groupByDate: false,
  showContinueRow: false,
),
```
(`FolderScreen` is currently a `ConsumerWidget`, not stateful — that's fine, `VideoDensityFeed` owns its own state internally regardless of the parent's type.) Remove now-unused imports (`format.dart`'s `fmtSize` if no longer directly used, `settingsProvider` if no longer directly used — check before removing).

- [ ] **Step 5: Polish `folder_grid.dart`.** Change `GridView.builder`'s `padding: const EdgeInsets.all(12)` to `const EdgeInsets.all(24)`. In `_FolderCard`, bump the folder-name `Text` `fontSize` from `11` to `13`.

- [ ] **Step 6: Tests.** New `test/ui/home/video_density_feed_test.dart`: pump `VideoDensityFeed` with 2-3 fake `VideoItem`s (reuse whatever fake/provider-override pattern `library_screen_test.dart` uses — read it first), assert: with `groupByDate: false` no date-section header text appears; with `showContinueRow: false` no "Continuar" text appears; a video title is tappable and fires `onOpen`. Keep `library_screen_test.dart` passing (update provider overrides if the extraction changes what's watched — it shouldn't, since the same providers are still read, just from a different widget). Check `test/ui/home/` for an existing `folder_screen_test.dart`; if none exists, skip creating one unless it's a trivial addition (a smoke test rendering `FolderScreen` with 1-2 videos and asserting a title shows) — don't force it if it requires excessive scaffolding.

- [ ] **Step 7: Analyze + test + commit** — `feat: extract VideoDensityFeed shared widget; use in FolderScreen; polish FolderGrid spacing`.

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review (opus).
3. Release build to the Pixel 6: switching Todo↔Carpetas repeatedly shows no thumbnail flicker and preserves scroll; watching a video and exiting via the back button, system back, AND swipe-down all make it appear first in "Continuar" instantly; opening a folder looks and behaves like the Todo tab (pinch, reflow, Nuevo, inset); the folder-picker grid feels more spacious.
