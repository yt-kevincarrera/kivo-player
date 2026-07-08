# Multi-Select UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a press indicator + haptic when marking a tile, and move the batch Share/Delete actions from the top app bar to a thumb-reachable bottom bar during selection.

**Architecture:** `VideoTile` scales down while long-pressed; the feed fires a haptic on every selection toggle. Batch actions move from `SelectionAppBar` (top, now context-only) into a new `SelectionBottomBar`; `HomeShell` swaps its `bottomNavigationBar` (tabs → action bar) and hides the mini-player while `librarySelectionProvider` is active. `chosen` is resolved from `mediaIndexProvider ∩ selected`.

**Tech Stack:** Flutter, Riverpod, `flutter_test`.

## Global Constraints

- Single configurable accent; no new hardcoded colors (Delete uses `colorScheme.error`).
- Reuse `videoActionsProvider.deleteMany/shareMany`, `maybeOfferAllFilesAccess`, `librarySelectionProvider` — don't re-implement.
- Selection observed via Riverpod; no global mutable state outside providers.
- No `flutter run`. On module close: `flutter build apk --release`, then `adb install` to the Pixel 6 (device `24231FDF6006ST`; adb at `$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe`).
- Full suite stays green (`flutter test`), currently 395 tests.
- Don't regress: normal tab navigation (no selection), system-back clearing selection, the top context bar.

---

### Task 1: Press indicator + haptic on marking

**Files:**
- Modify: `lib/ui/home/widgets/video_tile.dart` (long-press press-scale)
- Modify: `lib/ui/home/widgets/video_density_feed.dart` (haptic on toggle)
- Test: `test/ui/home/video_tile_select_test.dart` (append a press-scale test)

**Interfaces:**
- Consumes: existing `onLongPress`, `librarySelectionProvider` toggle sites.
- Produces: no new public API — behavioral (visual scale + haptic).

**Context:** `VideoTile` (`ConsumerStatefulWidget`) has, in BOTH `_buildListRow` (~line 63) and `_buildCover` (~line 179): `GestureDetector(behavior: ..., onLongPress: widget.onLongPress, child: PressBounce(...))`. Add press state + `AnimatedScale`. The feed toggles at `video_density_feed.dart` lines ~181 (`sel.toggleAll`), ~226/228 and ~258/260 (`sel.toggle`).

- [ ] **Step 1: Write the failing test**

Append to `test/ui/home/video_tile_select_test.dart` (reuse its existing `_host`/`_v` helpers; if the harness differs, adapt):

```dart
  testWidgets('tile scales down while long-pressed', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await tester.pumpWidget(_host(s, selected: false, onLong: () {}));

    AnimatedScale scaleOf() => tester.widget<AnimatedScale>(
        find.descendant(of: find.byType(VideoTile), matching: find.byType(AnimatedScale)).first);
    expect(scaleOf().scale, 1.0);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(VideoTile)));
    await tester.pump(const Duration(milliseconds: 50)); // long-press-down registered
    await tester.pump(const Duration(milliseconds: 250)); // AnimatedScale settles
    expect(scaleOf().scale, lessThan(1.0)); // pressed → scaled down
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(scaleOf().scale, 1.0); // released → back
  });
```

> If `VideoTile` already contains an `AnimatedScale` (e.g. from another layer), scope the finder to the new press-scale (give it a `key: const Key('tile-press-scale')` in Step 3 and find by that key). Adjust the test to the key.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/home/video_tile_select_test.dart`
Expected: FAIL — no press-scale AnimatedScale reacts to long-press.

- [ ] **Step 3: Add the press-scale to `VideoTile`**

In `_VideoTileState`, add a field `bool _pressing = false;`. In BOTH `_buildListRow` and `_buildCover`, change the outer `GestureDetector` to drive press state and wrap `PressBounce` in an `AnimatedScale`:

```dart
    return GestureDetector(
      behavior: HitTestBehavior.opaque, // (keep whatever behavior is already there)
      onLongPress: widget.onLongPress,
      onLongPressDown: (_) => setState(() => _pressing = true),
      onLongPressCancel: () => setState(() => _pressing = false),
      onLongPressUp: () => setState(() => _pressing = false),
      child: AnimatedScale(
        key: const Key('tile-press-scale'),
        scale: _pressing ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: PressBounce(
          // ... unchanged ...
        ),
      ),
    );
```

(Apply to both layouts. `onLongPressUp` fires after `onLongPress`; both reset `_pressing`. A quick tap triggers `onLongPressDown`+`onLongPressUp` in <100ms, far shorter than the 220ms scale, so the scale barely moves — no flash.)

- [ ] **Step 4: Add the haptic on toggle in the feed**

In `video_density_feed.dart`, add `import 'package:flutter/services.dart';`. Wrap every selection toggle with a haptic. At the two `VideoTile` call sites:

```dart
                                onLongPress: () {
                                  HapticFeedback.selectionClick();
                                  sel.toggle(v.uri);
                                },
                                onTap: (origin) => selecting
                                    ? (() {
                                        HapticFeedback.selectionClick();
                                        sel.toggle(v.uri);
                                      })()
                                    : widget.onOpen(v, widget.videos, origin),
```

And at the day-header `_DayCheckbox`:

```dart
                          onTap: () {
                            HapticFeedback.selectionClick();
                            sel.toggleAll(s.items.map((v) => v.uri));
                          },
```

- [ ] **Step 5: Run test + analyze**

Run: `flutter test test/ui/home/video_tile_select_test.dart`
Expected: PASS.
Run: `flutter analyze lib/ui/home/widgets/video_tile.dart lib/ui/home/widgets/video_density_feed.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/home/widgets/video_tile.dart lib/ui/home/widgets/video_density_feed.dart test/ui/home/video_tile_select_test.dart
git commit -m "feat(library): long-press press indicator + haptic on selection toggle"
```

---

### Task 2: `SelectionBottomBar` + move batch actions off the top bar

**Files:**
- Create: `lib/ui/home/widgets/selection_bottom_bar.dart`
- Modify: `lib/ui/home/widgets/selection_app_bar.dart` (remove Share/Delete)
- Test: `test/ui/home/selection_bottom_bar_test.dart`
- Test: `test/ui/home/selection_app_bar_test.dart` (adjust: actions gone)

**Interfaces:**
- Consumes: `librarySelectionProvider`, `videoActionsProvider` (`shareMany`/`deleteMany`), `maybeOfferAllFilesAccess` (`video_options_sheet.dart`), `mediaIndexProvider`, `FileOpStatus`.
- Produces: `SelectionBottomBar` (`ConsumerWidget`) — no ctor args (resolves `chosen` from `mediaIndexProvider ∩ selected`). `SelectionAppBar` keeps `allVisible` (for select-all) but no longer renders Share/Delete.

- [ ] **Step 1: Write the failing test**

`test/ui/home/selection_bottom_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/player/library/media_permission.dart';
import 'package:kivo_player/platform/interfaces/media_file_ops.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/ui/home/state/library_selection.dart';
import 'package:kivo_player/ui/home/widgets/selection_bottom_bar.dart';
import '../../fakes/fakes.dart';

const _a = VideoItem(id: '1', uri: 'u1', name: 'a.mp4', folder: 'F', durationMs: 1, sizeBytes: 1, dateAddedMs: 0);
const _b = VideoItem(id: '2', uri: 'u2', name: 'b.mp4', folder: 'F', durationMs: 1, sizeBytes: 1, dateAddedMs: 0);

class _Perm implements MediaPermission {
  @override Future<MediaAccess> status() async => MediaAccess.granted;
  @override Future<MediaAccess> request() async => MediaAccess.granted;
}

void main() {
  testWidgets('bottom bar shares the selected videos resolved from the index', (tester) async {
    final ops = FakeMediaFileOps();
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaFileOpsProvider.overrideWithValue(ops),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer([_a, _b])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    ]);
    addTearDown(c.dispose);
    // Prime the index + a selection.
    await c.read(mediaIndexProvider.future);
    c.read(librarySelectionProvider.notifier).selectAll(['u1']);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(bottomNavigationBar: SelectionBottomBar())),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.share));
    await tester.pump();
    expect(ops.sharedManyUris.single, ['u1']);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/home/selection_bottom_bar_test.dart`
Expected: FAIL — `SelectionBottomBar` not found.

- [ ] **Step 3: Implement `SelectionBottomBar`**

`lib/ui/home/widgets/selection_bottom_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/interfaces/media_file_ops.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/media_index.dart';
import '../../../player/library/video_actions.dart';
import '../state/library_selection.dart';
import 'video_options_sheet.dart'; // maybeOfferAllFilesAccess

/// Bottom action bar shown during selection (thumb-reachable). Resolves the
/// chosen videos from the media index ∩ selected uris, so it works in both the
/// library and a folder without needing the visible list.
class SelectionBottomBar extends ConsumerWidget implements PreferredSizeWidget {
  const SelectionBottomBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(librarySelectionProvider);
    final sel = ref.read(librarySelectionProvider.notifier);
    final index = ref.watch(mediaIndexProvider).valueOrNull ?? const <VideoItem>[];
    final chosen = index.where((v) => selected.contains(v.uri)).toList();
    final cs = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final enabled = chosen.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _action(cs.onSurface, Icons.share_outlined, 'Compartir', enabled ? () async {
                await ref.read(videoActionsProvider).shareMany(chosen);
                sel.clear();
              } : null),
              _action(cs.error, Icons.delete_outline, 'Borrar', enabled ? () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Borrar videos'),
                    content: Text('¿Borrar ${chosen.length} videos? Esta acción no se puede deshacer.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Borrar', style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                await maybeOfferAllFilesAccess(context, ref);
                if (!context.mounted) return;
                final status = await ref.read(videoActionsProvider).deleteMany(chosen);
                if (status == FileOpStatus.ok) {
                  messenger.showSnackBar(SnackBar(content: Text('${chosen.length} videos borrados')));
                  sel.clear();
                } else if (status == FileOpStatus.error) {
                  messenger.showSnackBar(const SnackBar(content: Text('No se pudieron borrar')));
                }
              } : null),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(Color color, IconData icon, String label, VoidCallback? onTap) {
    final c = onTap == null ? color.withValues(alpha: 0.4) : color;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: c),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 11, color: c)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Remove Share/Delete from `SelectionAppBar`**

In `lib/ui/home/widgets/selection_app_bar.dart`, delete the two `IconButton`s for Share and Delete from `actions`, leaving the leading X, the count title, and the Seleccionar todo action. Remove the now-unused imports (`media_file_ops`, `video_actions`, `video_options_sheet`, `maybeOfferAllFilesAccess`) and the `messenger`/`chosen` locals if they become unused. `allVisible` stays (used by Seleccionar todo).

- [ ] **Step 5: Adjust the SelectionAppBar test**

In `test/ui/home/selection_app_bar_test.dart`, update the expectations: assert the count + X clear + select-all still work, and that `find.byIcon(Icons.share)` / `find.byIcon(Icons.delete)` now find **nothing** in the app bar. (Adjust any prior assertion that tapped Share/Delete there.)

- [ ] **Step 6: Run tests + analyze**

Run: `flutter test test/ui/home/selection_bottom_bar_test.dart test/ui/home/selection_app_bar_test.dart`
Expected: PASS.
Run: `flutter analyze lib/ui/home/widgets/selection_bottom_bar.dart lib/ui/home/widgets/selection_app_bar.dart`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/home/widgets/selection_bottom_bar.dart lib/ui/home/widgets/selection_app_bar.dart test/ui/home/selection_bottom_bar_test.dart test/ui/home/selection_app_bar_test.dart
git commit -m "feat(library): move batch actions to a bottom SelectionBottomBar"
```

---

### Task 3: `HomeShell` swaps to the bottom action bar during selection

**Files:**
- Modify: `lib/ui/home/home_shell.dart`
- Test: `test/ui/home/home_shell_selection_test.dart`

**Interfaces:**
- Consumes: `librarySelectionProvider` (Task 1 existing), `SelectionBottomBar` (Task 2).

**Context:** `HomeShell` is a `StatefulWidget` with `Scaffold(body: Column([Expanded(IndexedStack), MiniPlayerBar()]), bottomNavigationBar: _BottomTabBar)`. Make it a `ConsumerStatefulWidget` and swap the bottom + hide the mini-player when selection is active.

- [ ] **Step 1: Write the failing test**

`test/ui/home/home_shell_selection_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/ui/home/state/library_selection.dart';
import 'package:kivo_player/ui/home/widgets/selection_bottom_bar.dart';
// NOTE: HomeShell pulls in many providers (media index, permission, engine, etc.).
// Reuse the override set from an existing HomeShell/library test harness; the
// assertion is what matters: SelectionBottomBar appears when selection is active.

void main() {
  testWidgets('HomeShell shows the bottom action bar when selection is active', (tester) async {
    // Build a ProviderContainer with the same overrides used by library_screen_test.dart
    // (settingsService, mediaIndexer, mediaPermissionImpl, engine, resume, played, etc.).
    // ... (compose overrides) ...
    // Pump HomeShell, then:
    //   expect(find.byType(SelectionBottomBar), findsNothing);
    //   container.read(librarySelectionProvider.notifier).selectAll(['u1']);
    //   await tester.pump();
    //   expect(find.byType(SelectionBottomBar), findsOneWidget);
  });
}
```

> HomeShell has a broad provider dependency surface. If assembling a working harness is impractical, SKIP this widget test with an explicit note (device-verified in Task 4) rather than writing a vacuous one. The change itself is a small conditional in `build`.

- [ ] **Step 2: Run to verify it fails (or document the skip)**

Run: `flutter test test/ui/home/home_shell_selection_test.dart`
Expected: FAIL (bottom bar not swapped) — or a documented skip.

- [ ] **Step 3: Implement the swap**

In `lib/ui/home/home_shell.dart`:
1. Change `class HomeShell extends StatefulWidget` → `extends ConsumerStatefulWidget`, and `State<HomeShell>` → `ConsumerState<HomeShell>` (import `flutter_riverpod`).
2. Add the selection import: `import 'state/library_selection.dart';` and `import 'widgets/selection_bottom_bar.dart';`.
3. In `build`, compute `final selecting = ref.watch(librarySelectionProvider).isNotEmpty;` and swap:

```dart
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  _tab(0, const LibraryScreen()),
                  _tab(1, const SettingsScreen()),
                ],
              ),
            ),
            if (!selecting) const MiniPlayerBar(),
          ],
        ),
        bottomNavigationBar: selecting
            ? const SelectionBottomBar()
            : _BottomTabBar(index: _index, onTap: _select),
      ),
```

(The `PopScope` wrapper and everything else stay. `ref` is available since it's now a `ConsumerState`.)

- [ ] **Step 4: Run test + analyze + full suite**

Run: `flutter test test/ui/home/home_shell_selection_test.dart` (if added)
Expected: PASS (or documented skip).
Run: `flutter analyze lib/ui/home/home_shell.dart`
Expected: No issues.
Run: `flutter test`
Expected: All green.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/home/home_shell.dart test/ui/home/home_shell_selection_test.dart
git commit -m "feat(library): HomeShell shows bottom action bar (hides mini-player/tabs) during selection"
```

---

### Task 4: Build, install, and device verification

**Files:** none (verification only).

- [ ] **Step 1: Full suite**

Run: `flutter test`
Expected: All green.

- [ ] **Step 2: Release build**

Run: `flutter build apk --release`
Expected: `Built build\app\outputs\flutter-apk\app-release.apk`.

- [ ] **Step 3: Install to the Pixel 6**

Run: `& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" -s 24231FDF6006ST install -r build\app\outputs\flutter-apk\app-release.apk`
Expected: `Success`.

- [ ] **Step 4: Device checklist** (report pass/fail per item)

  - Long-press a tile: it visibly scales down during the hold, and a haptic tick fires when it marks. Tapping tiles to toggle also gives a haptic.
  - In selection mode: the bottom tabs are replaced by a bottom bar with Compartir + Borrar (thumb-reachable), the mini-player is hidden; the top bar shows X + "N seleccionados" + Seleccionar todo (no Share/Delete up top).
  - Compartir N / Borrar N from the bottom bar work (chooser / confirm→delete); on completion selection exits and tabs + mini-player return.
  - Inside a folder: same bottom action bar.
  - Deselecting the last item / X / system-back all exit selection and restore tabs + mini-player.
  - Normal browsing (no selection): tabs + mini-player unchanged.

This task has no commit (verification only). Report results.

---

## Self-Review notes

- **Spec coverage:** §1 press indicator→Task 1; §2 haptic→Task 1; §3.1 strip top bar→Task 2; §3.2 SelectionBottomBar→Task 2; §3.3 HomeShell swap→Task 3; testing→each + Task 4 device.
- **Type consistency:** `SelectionBottomBar` (no-arg `ConsumerWidget`), `chosen = index ∩ selected`, `SelectionAppBar` keeps `allVisible` minus actions, `HomeShell` → `ConsumerStatefulWidget`/`ConsumerState`. `librarySelectionProvider`/`videoActionsProvider`/`maybeOfferAllFilesAccess` reused as-is.
- **`chosen` source moved** from `allVisible ∩ selected` (SelectionAppBar) to `index ∩ selected` (SelectionBottomBar) — equivalent for share/delete (index is fresh; stale/vanished uris drop out either way), and lets the bottom bar be screen-agnostic (works in HomeShell without the visible list).
- **Widget tests that need HomeShell's full provider surface** may be skipped-with-note (Task 3) per the plan; the load-bearing SelectionBottomBar action logic is unit-tested in Task 2, and the press-scale in Task 1.
