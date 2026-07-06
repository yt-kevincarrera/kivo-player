# Player Transitions Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the "grow from the tapped tile" open animation (lost when the player moved to the root navigator) and unify the shrink-to-mini-player exit so the top-bar back and system back animate identically to the swipe-down.

**Architecture:** (A) `playerRoute` takes an optional global `originRect`; its `transitionsBuilder` grows the player from that rect on push (`GrowFromRect`) and falls back to a fade when there's no rect or on any close. The tile's thumbnail rect is captured at tap via a `GlobalKey` and plumbed through the existing `onOpen` callbacks. (B) The dismiss `AnimationController` moves from `PlayerGestures` into `PlayerScreen`, which publishes a `PlayerDismissApi` (`complete()`/`cancel()`) through a Riverpod provider; the swipe release, the top-bar back, and the system back all funnel to `complete()`.

**Tech Stack:** Flutter, Riverpod, `flutter_test`.

## Global Constraints

- A single configurable accent color (gold by default); introduce **no new hardcoded colors** in these transitions.
- No `flutter run`. After a module closes: `flutter build apk --release`, then `adb install` to the Pixel 6 (device id `24231FDF6006ST`; adb at `$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe`).
- Keep the Riverpod provider pattern; introduce no global mutable state outside providers.
- Close still minimizes to the mini-player (never flies back to the tile).
- Full test suite must stay green (`flutter test`), currently 323 tests.

---

### Task 1: `growRect` pure interpolation helper

**Files:**
- Create: `lib/ui/player/transition/grow_rect.dart`
- Test: `test/ui/player/transition/grow_rect_test.dart`

**Interfaces:**
- Produces: `Rect growRect(Rect origin, Rect full, double t)` — the interpolated rect of the tile→screen grow. `t` is the (already-curved) progress; clamped to [0,1]. Returns `full` if `Rect.lerp` yields null.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/transition/grow_rect.dart';

void main() {
  const origin = Rect.fromLTWH(20, 100, 168, 94.5);
  const full = Rect.fromLTWH(0, 0, 400, 800);

  test('growRect at t=0 is the origin rect', () {
    expect(growRect(origin, full, 0), origin);
  });

  test('growRect at t=1 is the full rect', () {
    expect(growRect(origin, full, 1), full);
  });

  test('growRect at t=0.5 is the midpoint lerp', () {
    expect(growRect(origin, full, 0.5), Rect.lerp(origin, full, 0.5));
  });

  test('growRect clamps t outside [0,1]', () {
    expect(growRect(origin, full, -1), origin);
    expect(growRect(origin, full, 2), full);
  });

  test('growRect with a degenerate origin does not throw', () {
    expect(growRect(Rect.zero, full, 0.5), Rect.lerp(Rect.zero, full, 0.5));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/player/transition/grow_rect_test.dart`
Expected: FAIL — `grow_rect.dart` / `growRect` not found.

- [ ] **Step 3: Write minimal implementation**

Create `lib/ui/player/transition/grow_rect.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Interpolated rect of the tile→screen grow. [t] is the (already-curved)
/// progress: 0 = tile, 1 = full screen. Returns [full] if the lerp is null.
Rect growRect(Rect origin, Rect full, double t) {
  final c = t.clamp(0.0, 1.0);
  return Rect.lerp(origin, full, c) ?? full;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/player/transition/grow_rect_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/transition/grow_rect.dart test/ui/player/transition/grow_rect_test.dart
git commit -m "feat(player): growRect interpolation helper for the open transition"
```

---

### Task 2: `GrowFromRect` widget + `playerRoute(originRect:)`

**Files:**
- Modify: `lib/ui/player/transition/grow_rect.dart` (add the widget)
- Modify: `lib/ui/player/player_route.dart`
- Test: `test/ui/player/transition/grow_from_rect_test.dart`

**Interfaces:**
- Consumes: `growRect(Rect, Rect, double)` from Task 1.
- Produces:
  - `class GrowFromRect extends StatelessWidget` with a const ctor `GrowFromRect({Key? key, required Animation<double> animation, required Rect origin, required Widget child})`.
  - `Route<T> playerRoute<T>({Rect? originRect})` — the existing `playerRoute` gains an optional named `originRect`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/transition/grow_rect.dart';

Widget _harness(double value) => MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GrowFromRect(
          animation: AlwaysStoppedAnimation<double>(value),
          origin: const Rect.fromLTWH(20, 100, 168, 94.5),
          child: const SizedBox.expand(child: ColoredBox(color: Color(0xFF000000))),
        ),
      ),
    );

void main() {
  testWidgets('GrowFromRect is fully transparent at t=0', (tester) async {
    await tester.pumpWidget(_harness(0));
    final op = tester.widget<Opacity>(find.byType(Opacity));
    expect(op.opacity, 0.0);
  });

  testWidgets('GrowFromRect is fully opaque at t=1', (tester) async {
    await tester.pumpWidget(_harness(1));
    final op = tester.widget<Opacity>(find.byType(Opacity));
    expect(op.opacity, 1.0);
  });

  testWidgets('GrowFromRect clips and transforms its child', (tester) async {
    await tester.pumpWidget(_harness(0.5));
    expect(find.byType(ClipRect), findsOneWidget);
    expect(find.byType(Transform), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/player/transition/grow_from_rect_test.dart`
Expected: FAIL — `GrowFromRect` not defined.

- [ ] **Step 3: Add `GrowFromRect` to `grow_rect.dart`**

Append to `lib/ui/player/transition/grow_rect.dart`:

```dart
/// Grows [child] from [origin] (a global rect) to the full screen as
/// [animation] runs 0→1, with a fade. Used by the player route's open flight.
/// The scale is non-uniform (screen aspect ≠ tile aspect); the momentary
/// distortion is imperceptible over the ~300ms grow and is standard for a
/// container-transform.
class GrowFromRect extends StatelessWidget {
  final Animation<double> animation;
  final Rect origin;
  final Widget child;
  const GrowFromRect({
    super.key,
    required this.animation,
    required this.origin,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final full = Offset.zero & size;
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      builder: (context, _) {
        final t = curve.value;
        final rect = growRect(origin, full, t);
        final sx = full.width == 0 ? 1.0 : rect.width / full.width;
        final sy = full.height == 0 ? 1.0 : rect.height / full.height;
        final m = Matrix4.identity()
          ..translate(rect.left, rect.top)
          ..scale(sx, sy);
        return Opacity(
          // Content reaches full opacity a bit before full size.
          opacity: (t * 1.4).clamp(0.0, 1.0),
          child: ClipRect(
            child: Transform(
              transform: m,
              transformHitTests: false,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Wire `originRect` into `playerRoute`**

Replace the whole body of `lib/ui/player/player_route.dart` with:

```dart
import 'package:flutter/material.dart';
import 'player_screen.dart';
import 'transition/grow_rect.dart';

/// Route for the player. It is deliberately **non-opaque** so the library
/// (the route beneath) keeps painting and shows through while the swipe-down
/// dismiss shrinks/fades the player — instead of a black void behind it.
///
/// On open, when [originRect] (the tapped tile's global rect) is given, the
/// player grows from that rect ([GrowFromRect]); otherwise (file-picker,
/// mini-player expand) it fades in. Every close fades — the close is carried by
/// the shrink-to-mini-player, so the route must not fly back to the tile.
Route<T> playerRoute<T>({Rect? originRect}) => PageRouteBuilder<T>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) => const PlayerScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // At rest: no wrappers, so the dismiss transforms in PlayerScreen are
        // undisturbed.
        if (animation.isCompleted) return child;
        if (originRect == null || animation.status == AnimationStatus.reverse) {
          return FadeTransition(opacity: animation, child: child);
        }
        return GrowFromRect(animation: animation, origin: originRect, child: child);
      },
    );
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/ui/player/transition/grow_from_rect_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/player/transition/grow_rect.dart lib/ui/player/player_route.dart test/ui/player/transition/grow_from_rect_test.dart
git commit -m "feat(player): GrowFromRect open transition + playerRoute(originRect:)"
```

---

### Task 3: Plumb the tile's global rect from tap to `playerRoute`

**Files:**
- Modify: `lib/ui/home/widgets/video_tile.dart` (→ `ConsumerStatefulWidget`, `GlobalKey`, `onTap` signature)
- Modify: `lib/ui/home/widgets/video_density_feed.dart` (`onOpen` signature + tile call sites)
- Modify: `lib/ui/home/widgets/continue_row.dart` (`onOpen` signature + tile call site)
- Modify: `lib/ui/home/library_screen.dart` (`_open` signature + `onOpen` closures)
- Modify: `lib/ui/home/folder_screen.dart` (`_open` signature + `onOpen` closure)
- Test: `test/ui/home/video_tile_origin_test.dart`

**Interfaces:**
- Consumes: `playerRoute({Rect? originRect})` from Task 2.
- Produces (all callbacks change shape — every call site in the files above must be updated together so the project compiles):
  - `VideoTile.onTap` : `void Function(Rect? origin)` (was `VoidCallback`).
  - `VideoDensityFeed.onOpen` : `void Function(VideoItem current, List<VideoItem> all, Rect? origin)`.
  - `ContinueRow.onOpen` : `void Function(VideoItem video, Rect? origin)`.
  - `LibraryScreen._open(VideoItem v, List<VideoItem> all, Rect? origin)`.
  - `FolderScreen._open(BuildContext, WidgetRef, VideoItem, List<VideoItem>, Rect? origin)`.

**Context:** `VideoTile.onTap` is consumed by `video_density_feed.dart` (cover + list-row tiles) and `continue_row.dart`. Changing its type breaks compilation until all consumers are updated — do them in this one task.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/widgets/video_tile.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('VideoTile.onTap emits the thumbnail global rect', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
    ]);
    addTearDown(c.dispose);

    const video = VideoItem(
      id: 1, uri: 'content://v/1', name: 'clip.mp4', durationMs: 1000,
      sizeBytes: 10, dateAddedSec: 0, folder: 'f', width: 1920, height: 1080,
    );

    Rect? captured;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: VideoTile(
                video: video,
                listRow: false,
                onTap: (origin) => captured = origin,
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.byType(VideoTile));
    await tester.pump(const Duration(milliseconds: 400)); // PressBounce settle
    expect(captured, isNotNull);
    expect(captured!.width, greaterThan(0));
    expect(captured!.height, greaterThan(0));
  });
}
```

> Note: confirm the `VideoItem` constructor argument names against `lib/platform/interfaces/media_indexer.dart` before running; adjust the literal to match the real fields (the test only needs a valid `VideoItem` with a non-empty `uri` and `id`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/home/video_tile_origin_test.dart`
Expected: FAIL — `onTap` expects `VoidCallback` / argument type mismatch (compile error).

- [ ] **Step 3: Convert `VideoTile` to a stateful widget that emits the rect**

In `lib/ui/home/widgets/video_tile.dart`:

1. Change the class declaration and the `onTap` field:

```dart
class VideoTile extends ConsumerStatefulWidget {
  final VideoItem video;
  final double? progress; // 0..1 watched, or null
  final bool listRow;     // true = 1-col list row; false = cover-grid tile
  final void Function(Rect? origin) onTap;
  final String? sizeLabel; // e.g. "49 MB" — shown in list-row meta line
  final bool isNew;
  final VoidCallback? onOptions;

  const VideoTile({
    super.key,
    required this.video,
    required this.onTap,
    this.progress,
    this.listRow = false,
    this.sizeLabel,
    this.isNew = false,
    this.onOptions,
  });

  @override
  ConsumerState<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends ConsumerState<VideoTile> {
  final GlobalKey _thumbKey = GlobalKey();

  void _handleTap() {
    final box = _thumbKey.currentContext?.findRenderObject() as RenderBox?;
    Rect? origin;
    if (box != null && box.hasSize) {
      final topLeft = box.localToGlobal(Offset.zero);
      origin = topLeft & box.size;
    }
    widget.onTap(origin);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(ref.watch(settingsProvider).accentColor);
    return widget.listRow
        ? _buildListRow(context, accent)
        : _buildCover(context, accent);
  }
```

2. Throughout `_buildListRow` and `_buildCover`, replace references to the old widget fields with `widget.` (`widget.progress`, `widget.video`, `widget.isNew`, `widget.sizeLabel`, `widget.onOptions`). Change both `PressBounce(onTap: onTap ...)` to `PressBounce(onTap: _handleTap ...)`.

3. Attach `_thumbKey` to the 16:9 thumbnail `ClipRRect` in **both** layouts:
   - In `_buildListRow`, the `ClipRRect(borderRadius: BorderRadius.circular(8), ...)` becomes `ClipRRect(key: _thumbKey, borderRadius: BorderRadius.circular(8), ...)`.
   - In `_buildCover`, the `ClipRRect(borderRadius: BorderRadius.circular(12), ...)` becomes `ClipRRect(key: _thumbKey, borderRadius: BorderRadius.circular(12), ...)`.

4. The private `_SegmentedProgress` / `_badge` / `_newBadge` helpers were instance methods on the old widget class. Move `_badge`, `_newBadge` into `_VideoTileState` (they use no widget state, but must live where `_buildCover`/`_buildListRow` are). `_SegmentedProgress` is already a separate class — leave it.

- [ ] **Step 4: Update `VideoDensityFeed` (`onOpen` signature + call sites)**

In `lib/ui/home/widgets/video_density_feed.dart`:

1. Change the field type (line ~23):

```dart
  final void Function(VideoItem current, List<VideoItem> all, Rect? origin) onOpen;
```

2. The `ContinueRow` call site (line ~150):

```dart
              child: ContinueRow(
                onOpen: (v, origin) => widget.onOpen(v, widget.videos, origin),
              ),
```

3. Both `VideoTile` call sites (lines ~198 and ~227):

```dart
                                  onTap: (origin) => widget.onOpen(v, widget.videos, origin),
```

- [ ] **Step 5: Update `ContinueRow` (`onOpen` signature + call site)**

In `lib/ui/home/widgets/continue_row.dart`:

```dart
  final void Function(VideoItem video, Rect? origin) onOpen;
```

and the tile:

```dart
              onTap: (origin) => onOpen(items[i].video, origin),
```

- [ ] **Step 6: Update `library_screen.dart` (`_open` + closures)**

In `lib/ui/home/library_screen.dart`:

1. `_open` gains the rect and forwards it:

```dart
  void _open(VideoItem v, List<VideoItem> all, Rect? origin) {
    ref.read(currentVideoProvider.notifier).openFromList(v, all);
    Navigator.of(context, rootNavigator: true)
        .push(playerRoute(originRect: origin))
        .then((_) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(playedKeysProvider);
    });
  }
```

2. Both `VideoDensityFeed(... onOpen: ...)` closures (lines ~290 and ~317):

```dart
                  onOpen: (v, all, origin) => _open(v, all, origin),
```

3. `_openPath` and `_pick` are unchanged — they call `_push()` which uses `playerRoute()` with no rect (fade fallback).

- [ ] **Step 7: Update `folder_screen.dart` (`_open` + closure)**

In `lib/ui/home/folder_screen.dart`:

```dart
  void _open(
    BuildContext context,
    WidgetRef ref,
    VideoItem current,
    List<VideoItem> all,
    Rect? origin,
  ) {
    ref.read(resumePromptProvider.notifier).state = null;
    ref.read(currentVideoProvider.notifier).openFromList(current, all);
    Navigator.of(context, rootNavigator: true)
        .push(playerRoute(originRect: origin))
        .then((_) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(playedKeysProvider);
    });
  }
```

and the feed:

```dart
        onOpen: (v, all, origin) => _open(context, ref, v, all, origin),
```

- [ ] **Step 8: Run the origin test + analyzer**

Run: `flutter test test/ui/home/video_tile_origin_test.dart`
Expected: PASS (1 test).

Run: `flutter analyze`
Expected: No issues (all `onOpen`/`onTap` call sites updated).

- [ ] **Step 9: Run the full suite (guard the callback-shape ripple)**

Run: `flutter test`
Expected: All green (existing home/player tests still compile with the new signatures).

- [ ] **Step 10: Commit**

```bash
git add lib/ui/home/widgets/video_tile.dart lib/ui/home/widgets/video_density_feed.dart lib/ui/home/widgets/continue_row.dart lib/ui/home/library_screen.dart lib/ui/home/folder_screen.dart test/ui/home/video_tile_origin_test.dart
git commit -m "feat(player): plumb the tapped tile's global rect into playerRoute"
```

---

### Task 4: Remove the now-inert cross-navigator Hero

**Files:**
- Modify: `lib/ui/home/widgets/video_tile.dart` (remove both `Hero` wrappers)
- Modify: `lib/ui/player/player_screen.dart` (remove the `Hero` around `videoBox` + the `heroTag` local)

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new. Behavior-preserving cleanup — the grow now comes from the route (Task 2/3); the Hero never flew (tile lives in a nested navigator, player in the root).

- [ ] **Step 1: Remove the Hero from both tile layouts**

In `lib/ui/home/widgets/video_tile.dart`, in `_buildListRow` and `_buildCover`, replace:

```dart
Hero(tag: 'libhero-${widget.video.uri}', child: ThumbnailImage(widget.video.id)),
```

with:

```dart
ThumbnailImage(widget.video.id),
```

(Both occurrences. Note `video.` became `widget.video.` in Task 3.)

- [ ] **Step 2: Remove the Hero from the player**

In `lib/ui/player/player_screen.dart`:

1. Delete the `heroTag` local (around line 407):

```dart
final heroTag = 'libhero-${ref.watch(currentVideoProvider)?.playbackPath ?? ''}';
```

2. Replace the `Positioned.fill(child: Hero(... child: videoBox))` block (around lines 448-464) with:

```dart
                      Positioned.fill(child: videoBox),
```

- [ ] **Step 3: Analyze + full suite**

Run: `flutter analyze`
Expected: No issues, no "unused" warnings for `heroTag` or `HeroFlightDirection`.

Run: `flutter test`
Expected: All green.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/home/widgets/video_tile.dart lib/ui/player/player_screen.dart
git commit -m "refactor(player): drop the inert cross-navigator Hero (grow comes from the route now)"
```

---

### Task 5: `PlayerDismissApi` provider + `dismissDurationMs` helper

**Files:**
- Create: `lib/ui/player/state/player_dismiss_state.dart`
- Test: `test/ui/player/state/player_dismiss_state_test.dart`

**Interfaces:**
- Produces:
  - `class PlayerDismissApi { final void Function() complete; final void Function() cancel; const PlayerDismissApi({required this.complete, required this.cancel}); }`
  - `final playerDismissProvider = StateProvider<PlayerDismissApi?>((ref) => null);`
  - `int dismissDurationMs(double progress)` — grow-to-close duration: `240 * (1 - progress)`, clamped to `[80, 240]` ms.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/state/player_dismiss_state.dart';

void main() {
  test('dismissDurationMs is 240ms from a resting player (progress 0)', () {
    expect(dismissDurationMs(0), 240);
  });

  test('dismissDurationMs shrinks with progress', () {
    expect(dismissDurationMs(0.5), 120);
  });

  test('dismissDurationMs clamps to a floor of 80ms near completion', () {
    expect(dismissDurationMs(0.9), 80);
    expect(dismissDurationMs(1.0), 80);
  });

  test('PlayerDismissApi holds its callbacks', () {
    var completed = false;
    var cancelled = false;
    final api = PlayerDismissApi(
      complete: () => completed = true,
      cancel: () => cancelled = true,
    );
    api.complete();
    api.cancel();
    expect(completed, isTrue);
    expect(cancelled, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/player/state/player_dismiss_state_test.dart`
Expected: FAIL — file / symbols not found.

- [ ] **Step 3: Implement**

Create `lib/ui/player/state/player_dismiss_state.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The player's shrink-to-mini-player exit, published by PlayerScreen (which
/// owns the AnimationController) so the swipe release, the top-bar back, and the
/// system back all trigger the same animation. Null while no PlayerScreen is
/// mounted.
class PlayerDismissApi {
  final void Function() complete; // shrink → minimize → pop
  final void Function() cancel;   // return to 0 (drag not committed)
  const PlayerDismissApi({required this.complete, required this.cancel});
}

final playerDismissProvider = StateProvider<PlayerDismissApi?>((ref) => null);

/// Duration of the programmatic shrink: a back-press from a resting player
/// (progress 0) takes 240ms; a nearly-complete swipe finishes fast. Clamped to
/// an 80ms floor so it never feels instantaneous.
int dismissDurationMs(double progress) =>
    (240 * (1.0 - progress)).round().clamp(80, 240);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/player/state/player_dismiss_state_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/state/player_dismiss_state.dart test/ui/player/state/player_dismiss_state_test.dart
git commit -m "feat(player): PlayerDismissApi provider + dismissDurationMs helper"
```

---

### Task 6: PlayerScreen owns the dismiss controller; back funnels to `complete()`

**Files:**
- Modify: `lib/ui/player/player_screen.dart`

**Interfaces:**
- Consumes: `PlayerDismissApi`, `playerDismissProvider`, `dismissDurationMs(double)` from Task 5; `dismissProvider` from `lib/ui/player/state/dismiss_state.dart`; existing `_captureMiniPreview()`, `_saveProgress()`, `_engine`, `_resumeKey`, `_previewCaptured`, `minimizedSessionKeyProvider`, `playerMinimizedProvider`.
- Produces: publishes a `PlayerDismissApi` on `playerDismissProvider` while mounted. Adds `_dismissCtl` (0..1 `AnimationController`) whose listener writes `dismissProvider`. Later consumed by Task 7.

**Context:** The dismiss `AnimationController` currently lives in `PlayerGestures`; Task 7 removes it there. This task establishes the single controller in `PlayerScreen` and routes the two back paths through it. After this task, the swipe still works via the OLD gestures controller (both write `dismissProvider`) — that's fine transitionally; Task 7 flips the swipe over.

- [ ] **Step 1: Add the ticker mixin and fields**

In `lib/ui/player/player_screen.dart`, add imports:

```dart
import 'state/dismiss_state.dart';
import 'state/player_dismiss_state.dart';
```

(Confirm `dismiss_state.dart` isn't already imported; if it is, don't duplicate.)

Change the State declaration (line ~55-56) to add `SingleTickerProviderStateMixin`:

```dart
class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
```

Add fields near the other `late final` controllers (around line 72):

```dart
  late final AnimationController _dismissCtl;
  bool _dismissing = false; // guards complete() against re-entry (swipe + back)
```

- [ ] **Step 2: Create the controller and publish the API in `initState`**

In `initState` (after `_engine`/controllers are assigned, before the method ends), add:

```dart
    _dismissCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))
      ..addListener(() {
        ref.read(dismissProvider.notifier).state = _dismissCtl.value;
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(playerDismissProvider.notifier).state = PlayerDismissApi(
        complete: _completeDismiss,
        cancel: _cancelDismiss,
      );
    });
```

- [ ] **Step 3: Add the `_completeDismiss` / `_cancelDismiss` methods**

Add these methods to `_PlayerScreenState` (near `_saveProgress`/`_captureMiniPreview`):

```dart
  void _completeDismiss() {
    if (_dismissing) return;
    _dismissing = true;
    if (!_previewCaptured) _captureMiniPreview();
    _dismissCtl.value = ref.read(dismissProvider);
    _dismissCtl
        .animateTo(1.0, duration: Duration(milliseconds: dismissDurationMs(_dismissCtl.value)))
        .then((_) {
      if (!mounted) return;
      _engine.pause();
      _saveProgress();
      ref.read(minimizedSessionKeyProvider.notifier).state = _resumeKey;
      ref.read(playerMinimizedProvider.notifier).state = true;
      Navigator.of(context).pop(); // unconditional pop — does not re-enter PopScope
    });
  }

  void _cancelDismiss() {
    _dismissCtl.value = ref.read(dismissProvider);
    _dismissCtl.animateBack(0.0);
  }
```

- [ ] **Step 4: Dispose the controller and clear the API**

In `dispose()` (around line 308), add before `super.dispose()`:

```dart
    _dismissCtl.dispose();
    ref.read(playerDismissProvider.notifier).state = null;
```

- [ ] **Step 5: Route `PopScope` through `complete()`**

Replace the body of `onPopInvokedWithResult` (lines ~381-398) with:

```dart
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final api = ref.read(playerDismissProvider);
        if (api != null) {
          api.complete();
        } else {
          // 1-frame window before the API is registered: fall back to the
          // previous immediate minimize+pop.
          _engine.pause();
          _saveProgress();
          if (!_previewCaptured) _captureMiniPreview();
          ref.read(minimizedSessionKeyProvider.notifier).state = _resumeKey;
          ref.read(playerMinimizedProvider.notifier).state = true;
          Navigator.of(context).pop();
        }
      },
```

The top-bar back button (`top_bar.dart` → `Navigator.maybePop()`) is unchanged: `canPop:false` routes it through this same handler.

- [ ] **Step 6: Reset the guard on (re)start**

In `_start()` (where `dismissProvider` is reset to 0, line ~158), add right after that line:

```dart
    _dismissing = false;
```

so reusing the same PlayerScreen for a new session re-arms `complete()`.

- [ ] **Step 7: Analyze + full suite**

Run: `flutter analyze`
Expected: No issues.

Run: `flutter test`
Expected: All green (existing player tests unaffected; the API is published post-frame and read defensively).

- [ ] **Step 8: Commit**

```bash
git add lib/ui/player/player_screen.dart
git commit -m "feat(player): PlayerScreen owns the dismiss controller; back funnels to complete()"
```

---

### Task 7: `PlayerGestures` delegates the dismiss to the shared API

**Files:**
- Modify: `lib/player/control/gesture_math.dart` (add `dismissCommit`)
- Modify: `lib/ui/player/gestures/player_gestures.dart` (remove its controller; delegate)
- Test: `test/player/control/gesture_math_test.dart` (add `dismissCommit` cases)
- Test: `test/ui/player/gestures/player_dismiss_delegation_test.dart`

**Interfaces:**
- Consumes: `playerDismissProvider` / `PlayerDismissApi` from Task 5.
- Produces: `bool dismissCommit(double progress, double velocityY)` — the swipe-release commit decision (`progress >= 0.25 || velocityY > 700`).

- [ ] **Step 1: Add the `dismissCommit` test**

Append to `test/player/control/gesture_math_test.dart` (inside `main()`):

```dart
  test('dismissCommit: commits past 25% progress or on a fast fling', () {
    expect(dismissCommit(0.30, 0), isTrue);   // dragged far enough
    expect(dismissCommit(0.10, 800), isTrue); // fast downward fling
    expect(dismissCommit(0.10, 0), isFalse);  // small, slow → snap back
    expect(dismissCommit(0.25, 0), isTrue);   // exactly at threshold
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/player/control/gesture_math_test.dart`
Expected: FAIL — `dismissCommit` not defined.

- [ ] **Step 3: Implement `dismissCommit`**

Append to `lib/player/control/gesture_math.dart`:

```dart
/// True when a vertical dismiss drag should commit (minimize) on release:
/// either dragged at least 25% down, or flung down faster than 700 px/s.
bool dismissCommit(double progress, double velocityY) =>
    progress >= 0.25 || velocityY > 700;
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/player/control/gesture_math_test.dart`
Expected: PASS (new case green, all existing gesture_math cases still green).

- [ ] **Step 5: Write the delegation widget test**

Create `test/ui/player/gestures/player_dismiss_delegation_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/ui/player/gestures/player_gestures.dart';
import 'package:kivo_player/ui/player/state/player_dismiss_state.dart';
import '../../../fakes/fakes.dart';

class NoopControls implements DeviceControls {
  @override Future<double> currentBrightness() async => 0.5;
  @override Future<void> setBrightness(double v) async {}
  @override Future<double> currentVolume() async => 0.5;
  @override Future<void> setSystemVolume(double v) async {}
  @override Future<void> setOrientation(List<DeviceOrientationLock> o) async {}
  @override Future<void> keepAwake(bool on) async {}
  @override Future<void> setImmersive(bool on) async {}
  @override Future<void> resetBrightness() async {}
  @override Stream<double> get systemVolumeStream => const Stream<double>.empty();
  @override Future<void> setVolumeKeyInterception(bool on) async {}
}

void main() {
  testWidgets('a committed dismiss drag calls PlayerDismissApi.complete', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    var completed = 0;
    var cancelled = 0;
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
    ]);
    addTearDown(c.dispose);
    c.read(playerDismissProvider.notifier).state = PlayerDismissApi(
      complete: () => completed++,
      cancel: () => cancelled++,
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(body: PlayerGestures(child: SizedBox.expand())),
      ),
    ));

    // Drag from center downward well past the 25% threshold.
    final size = tester.getSize(find.byType(PlayerGestures));
    final start = Offset(size.width / 2, size.height * 0.35);
    await tester.dragFrom(start, Offset(0, size.height * 0.5));
    await tester.pump();

    expect(completed, 1);
    expect(cancelled, 0);
  });

  testWidgets('a tiny dismiss drag calls cancel, not complete', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    var completed = 0;
    var cancelled = 0;
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
    ]);
    addTearDown(c.dispose);
    c.read(playerDismissProvider.notifier).state = PlayerDismissApi(
      complete: () => completed++,
      cancel: () => cancelled++,
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(body: PlayerGestures(child: SizedBox.expand())),
      ),
    ));

    final size = tester.getSize(find.byType(PlayerGestures));
    final start = Offset(size.width / 2, size.height * 0.5);
    await tester.dragFrom(start, const Offset(0, 20)); // small, slow
    await tester.pump();

    expect(completed, 0);
    expect(cancelled, 1);
  });
}
```

> Note: the drag must begin outside the top rotate strip (`_topRotateMargin = 90`) and the lateral/vertical dead zones. Starting at `height*0.35`–`0.5`, center X, satisfies that. If the committed-drag test lands in the rotate strip or dead zone on the default test surface (800×600), nudge the start Y toward center and keep the delta downward.

- [ ] **Step 6: Run to verify it fails**

Run: `flutter test test/ui/player/gestures/player_dismiss_delegation_test.dart`
Expected: FAIL — gestures still drive the old `_dismissAnim` + `maybePop()`, not the API, so `completed`/`cancelled` stay 0.

- [ ] **Step 7: Remove the gestures' own controller**

In `lib/ui/player/gestures/player_gestures.dart`:

1. Delete the field (line ~58): `late final AnimationController _dismissAnim;`
2. Delete its creation in `initState` (lines ~63-69, the `_dismissAnim = AnimationController(...)..addListener(...)` block). If `initState` becomes empty apart from `super.initState()`, keep `super.initState()`.
3. Delete `_dismissAnim.dispose();` from `dispose()`.
4. Check the State's `with` clause: if `SingleTickerProviderStateMixin` (or `TickerProviderStateMixin`) is now unused by any other controller in this file, remove it. If another controller uses it, keep it. (Verify by searching the file for `vsync: this`.)

- [ ] **Step 8: Delegate in `_onVerticalEnd`**

Add the import at the top of the file:

```dart
import '../state/player_dismiss_state.dart';
```

Replace the dismiss branch of `_onVerticalEnd` (the block from `if (!_isDismiss) return;` through the `else { ... animateBack ... }`, lines ~185-208) with:

```dart
    if (!_isDismiss) return;
    _isDismiss = false;
    final progress = ref.read(dismissProvider);
    final velocityY = d.primaryVelocity ?? 0;
    final api = ref.read(playerDismissProvider);
    if (dismissCommit(progress, velocityY)) {
      if (api != null) {
        api.complete();
      } else {
        // Defensive fallback if no PlayerScreen published the API.
        ref.read(dismissProvider.notifier).state = 0;
        Navigator.of(context).maybePop();
      }
    } else {
      api?.cancel();
    }
```

Confirm `gesture_math.dart` (which exports `dismissCommit`) and `dismiss_state.dart` (which exports `dismissProvider`) are already imported in this file; both are used elsewhere in `player_gestures.dart`, so they should be. Add whichever is missing.

- [ ] **Step 9: Run the delegation test + full suite**

Run: `flutter test test/ui/player/gestures/player_dismiss_delegation_test.dart`
Expected: PASS (2 tests).

Run: `flutter test`
Expected: All green.

Run: `flutter analyze`
Expected: No issues (no unused `_dismissAnim`, no unused mixin).

- [ ] **Step 10: Commit**

```bash
git add lib/player/control/gesture_math.dart lib/ui/player/gestures/player_gestures.dart test/player/control/gesture_math_test.dart test/ui/player/gestures/player_dismiss_delegation_test.dart
git commit -m "feat(player): gestures delegate the dismiss to the shared PlayerDismissApi"
```

---

### Task 8: Build, install, and device verification

**Files:** none (verification only).

- [ ] **Step 1: Full suite**

Run: `flutter test`
Expected: All green (baseline 323 + new tests).

- [ ] **Step 2: Release build**

Run: `flutter build apk --release`
Expected: `Built build\app\outputs\flutter-apk\app-release.apk`.

- [ ] **Step 3: Install to the Pixel 6**

Run: `& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" -s 24231FDF6006ST install -r build\app\outputs\flutter-apk\app-release.apk`
Expected: `Success`.

- [ ] **Step 4: Device checklist** (report pass/fail per item)

  - Open from a **library cover tile** → the player grows from that thumbnail.
  - Open from a **folder tile** → grows from that thumbnail.
  - Open from a **"Continuar viendo"** tile → grows from that thumbnail.
  - Open from a **list-row** (pinch to 1 column) tile → grows from the left thumbnail, not the whole row.
  - Open via **file-picker** and via **expanding the mini-player** → smooth fade (no jump/no grow-from-corner).
  - Exit via **swipe-down**, **top-bar back**, and **system back** → all three shrink identically toward the mini-player.
  - Scroll the origin tile out of view, open another, exit → no visual glitch; mini-player thumbnail correct.
  - Toggle the accent color in Ajustes → transitions carry no stray hardcoded color.

This task has no commit (verification only). Report results; if any item fails, treat it as a defect and open a fix task.

---

## Self-Review notes

- **Spec coverage:** A1→Task 2; A2/A3 (`growRect`/`GrowFromRect`)→Tasks 1–2; A4 (plumbing)→Task 3; A5 (retire Hero)→Task 4; A6 (push sites)→Task 3. B1 (provider/api)→Task 5; B2 (controller+publish)→Task 6; B3 (PopScope)→Task 6; B4 (gestures delegate)→Task 7. Testing + device checklist→Tasks 1,2,3,5,7,8.
- **Extra vs spec:** `dismissDurationMs` (Task 5) and `dismissCommit` (Task 7) are extractions of logic the spec described inline, pulled out to be unit-testable — no behavior added.
- **Type consistency:** `onTap(Rect? origin)`, `onOpen(VideoItem, List<VideoItem>, Rect?)`, `onOpen(VideoItem, Rect?)` (ContinueRow), `_open(..., Rect? origin)`, `playerRoute({Rect? originRect})`, `PlayerDismissApi{complete,cancel}`, `dismissDurationMs(double)`, `dismissCommit(double,double)` — consistent across tasks.
```
