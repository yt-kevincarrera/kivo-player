# Kivo Library Refinement v3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** "Nuevo" = never-played (via a persisted played set), deeper video-section inset, no residual tab-switch fade, instant "Continuar" updates (periodic progress save), and a smoother reflow.

**Architecture:** Two FILE-DISJOINT tasks, run SEQUENTIALLY (Task 1 then Task 2; never parallel). Task 1 owns player-side persistence (`played.dart` [new], `main.dart`, `player_screen.dart`). Task 2 owns the library UI (`library_screen.dart`, `core/format.dart`), consuming Task 1's `playedKeysProvider`.

**Tech Stack:** Flutter (Material 3), Riverpod, Hive.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-01-kivo-library-refinement-3-design.md`.
- `AnimationController`/`Timer` created in `initState`, disposed/cancelled — never a field initializer.
- Never `ref.read(...)` in `dispose()` (use cached fields, as `_saveProgress` already does).
- `withValues(alpha:)`, not `withOpacity`. Library uses `Theme.of(context)` colorScheme roles; brand `KivoColors`. Player stays dark/untouched beyond these changes.
- Resume/played key is `video.name` (== `VideoSession.displayName` == `resumeKey`).
- `flutter analyze` clean + `flutter test` green before each commit. Do not push.

---

### Task 1: Played-tracking store + mark-on-open + periodic progress save

**Files:**
- Create: `lib/player/library/played.dart`
- Modify: `lib/main.dart`, `lib/ui/player/player_screen.dart`
- Test: `test/player/library/played_test.dart` (new); extend `test/fakes/fakes.dart` if needed.

**Interfaces:**
- Produces: `PlayedStore` (`bool isPlayed(String key)`, `Future<void> markPlayed(String key)`, `Set<String> keys()`); `HivePlayedStore(Box)`, `InMemoryPlayedStore`; `playedStoreProvider` (Provider<PlayedStore>, throws until overridden); `playedKeysProvider` (Provider<Set<String>> → `ref.watch(playedStoreProvider).keys()`).

- [ ] **Step 1: Create `played.dart`.**
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

abstract class PlayedStore {
  bool isPlayed(String key);
  Future<void> markPlayed(String key);
  Set<String> keys();
}

class HivePlayedStore implements PlayedStore {
  final Box box;
  HivePlayedStore(this.box);
  @override
  bool isPlayed(String key) => box.containsKey(key);
  @override
  Future<void> markPlayed(String key) => box.put(key, true);
  @override
  Set<String> keys() => box.keys.map((k) => k.toString()).toSet();
}

class InMemoryPlayedStore implements PlayedStore {
  final Set<String> _s = {};
  @override
  bool isPlayed(String key) => _s.contains(key);
  @override
  Future<void> markPlayed(String key) async => _s.add(key);
  @override
  Set<String> keys() => Set.of(_s);
}

final playedStoreProvider = Provider<PlayedStore>((ref) {
  throw UnimplementedError('playedStoreProvider must be overridden');
});

/// The set of played (ever-opened) video keys. Invalidate on return from the
/// player so a just-played video is no longer "Nuevo".
final playedKeysProvider =
    Provider<Set<String>>((ref) => ref.watch(playedStoreProvider).keys());
```

- [ ] **Step 2: Wire the Hive box in `main.dart`.** After `final resumeBox = await Hive.openBox('resume');` add `final playedBox = await Hive.openBox('played');`. Add the import `import 'player/library/played.dart';`. In the `ProviderScope.overrides`, add `playedStoreProvider.overrideWithValue(HivePlayedStore(playedBox)),`.

- [ ] **Step 3: Mark played on open (`player_screen.dart`).** In `_start()`, right after `_resumeKey = session.resumeKey;`, add `ref.read(playedStoreProvider).markPlayed(_resumeKey!);` (fire-and-forget). Add the import for `played.dart`. (Runs in `_start`, called from a post-frame callback where `ref` is valid — not dispose.)

- [ ] **Step 4: Periodic progress save (`player_screen.dart`).** Add `Timer? _saveTimer;`. In `initState`, `_saveTimer = Timer.periodic(const Duration(seconds: 4), (_) => _saveProgress());` (`_saveProgress` already guards on `_lastDuration == 0` and `minSeconds`). In `dispose`, `_saveTimer?.cancel();` (before/with the other teardown). This keeps the resume entry fresh so "Continuar" reflects the just-watched video immediately on return, independent of dispose timing. `dart:async` is already imported.

- [ ] **Step 5: Test `played_test.dart`.** With `InMemoryPlayedStore`: `isPlayed` false initially; after `markPlayed('a')`, `isPlayed('a')` true and `keys()` contains 'a'. With a `ProviderContainer` overriding `playedStoreProvider` with an `InMemoryPlayedStore`, `playedKeysProvider` reflects marked keys after invalidation.

- [ ] **Step 6: Analyze + test + commit** — `feat: played-video tracking (store + mark-on-open) + periodic progress save`.

---

### Task 2: LibraryScreen — "Nuevo"=not-played, deeper inset, remove entrance fade, tune reflow

**Files:**
- Modify: `lib/ui/home/library_screen.dart`, `lib/core/format.dart`
- Test: `test/ui/home/library_screen_test.dart`, `test/core/format_test.dart`

**Interfaces:** Consumes `playedKeysProvider` (Task 1).

- [ ] **Step 1: "Nuevo" = not played.** In `_videosTab`, read `final played = ref.watch(playedKeysProvider);` and pass `isNew: !played.contains(v.name)` to each `VideoTile` (both SliverList and SliverGrid). Remove the `isNewVideo(v.dateAddedMs, DateTime.now())` calls.
- [ ] **Step 2: Invalidate played on return.** Wherever the screen does `.then((_) => ref.invalidate(continueWatchingProvider))` (the `_push` and `_open` navigation), also `ref.invalidate(playedKeysProvider)` so a just-played video loses its "Nuevo" badge. (Add `import '../../player/library/played.dart';`.)
- [ ] **Step 3: Remove `isNewVideo` from `core/format.dart`** and its test in `test/core/format_test.dart` (it's now unused).
- [ ] **Step 4: Deeper inset.** Change the video-section `SliverPadding` horizontal from 20 to **24**, and the section header `Padding` from `fromLTRB(20,18,20,8)` to `fromLTRB(24,18,24,8)`. Leave `ContinueRow` untouched (stays 16).
- [ ] **Step 5: Remove the entrance animation.** Delete the `TweenAnimationBuilder<double>` (opacity + `Transform.translate`) wrappers around BOTH the section header and the per-tile children in `_videosTab`. Render the header `Padding(...)` and the `VideoTile` (still inside `_reflowTile`) directly. This removes the residual fade seen when the PageView rebuilds the videos page on tab switch. Keep the `_reflowTile` wrapper.
- [ ] **Step 6: Tune the reflow.** In the `_reflowCtrl` setup change duration to **320ms**; change `_reflow`'s curve to `Curves.easeInOut`. Keep `_reflowTile`'s scale `lerpDouble(0.92, 1.0, _reflow.value)` and the at-rest identity guard. No fade.
- [ ] **Step 7: Tests.** Update `library_screen_test.dart` if the removed entrance animation affected any `pumpAndSettle`/finder (should still pass; a known video appears in the feed, chip "Todo"/"Carpetas", tapping "Carpetas" shows a folder). Keep provider overrides — ADD a `playedStoreProvider.overrideWithValue(InMemoryPlayedStore())` to the container/overrides so `playedKeysProvider` resolves. Wrap in `MaterialApp(theme: KivoTheme.light())`.
- [ ] **Step 8: Analyze + test + commit** — `feat: "Nuevo"=unplayed, deeper video inset, no tab-switch fade, smoother reflow`.

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review (opus).
3. Release build to the Pixel 6: "Nuevo" only on never-opened videos (gone after opening); video rows clearly more inset than Continuar; no fade switching Todo↔Carpetas; the just-watched video appears first in "Continuar" immediately on return; reflow feels smooth.
