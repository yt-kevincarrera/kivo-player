# Library Multi-Select Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Long-press a library tile to enter selection mode, with per-tile and per-day-header checkboxes, and a contextual app bar offering batch Share and Delete.

**Architecture:** A `librarySelectionProvider` (set of selected URIs; active ⇔ non-empty) drives everything. `VideoTile` gains long-press + a selected overlay; the shared `VideoDensityFeed` routes tap→toggle when selecting (else open), and renders a tri-state checkbox on each day header. A shared `SelectionAppBar` replaces each screen's AppBar during selection. Batch ops go through new `VideoActionsController.deleteMany/shareMany` → `MediaFileOps.deleteMany/shareMany` → native `createDeleteRequest`(batch) / `ACTION_SEND_MULTIPLE`.

**Tech Stack:** Flutter, Riverpod, Kotlin (MediaStore), `flutter_test`.

## Global Constraints

- Single configurable accent; no new hardcoded colors (Delete/`error`; selection check tinted with the accent via `onAccent`).
- Platform-boundary pattern: interface in `lib/platform/interfaces/`, Android impl in `lib/platform/android/`, override in `main.dart`.
- No new pub dependencies.
- Selection state lives in a Riverpod provider (no global mutable state outside providers).
- Reuse sub-project A's silent-delete + `maybeOfferAllFilesAccess`; do NOT re-implement permissions.
- No `flutter run`. On module close: `flutter build apk --release`, then `adb install` to the Pixel 6 (device `24231FDF6006ST`; adb at `$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe`).
- Full suite stays green (`flutter test`), currently 375 tests.

---

### Task 1: Selection state + `groupCheckState`

**Files:**
- Create: `lib/ui/home/state/library_selection.dart`
- Test: `test/ui/home/library_selection_test.dart`

**Interfaces:**
- Produces:
  - `class LibrarySelectionNotifier extends StateNotifier<Set<String>>` with `bool isSelected(String)`, `bool get active`, `void toggle(String)`, `void toggleAll(Iterable<String>)`, `void selectAll(Iterable<String>)`, `void clear()`.
  - `final librarySelectionProvider = StateNotifierProvider<LibrarySelectionNotifier, Set<String>>(...)`.
  - `enum GroupCheckState { none, some, all }`
  - `GroupCheckState groupCheckState(Iterable<String> groupUris, Set<String> selected)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/home/state/library_selection.dart';

void main() {
  test('toggle adds then removes; active tracks non-empty', () {
    final n = LibrarySelectionNotifier();
    expect(n.active, false);
    n.toggle('a');
    expect(n.state, {'a'});
    expect(n.active, true);
    expect(n.isSelected('a'), true);
    n.toggle('a');
    expect(n.state, isEmpty);
    expect(n.active, false);
  });

  test('toggleAll selects the whole group, then clears it when all present', () {
    final n = LibrarySelectionNotifier();
    n.toggle('a'); // partial
    n.toggleAll(['a', 'b', 'c']); // not all present → add the rest
    expect(n.state, {'a', 'b', 'c'});
    n.toggleAll(['a', 'b', 'c']); // all present → remove them
    expect(n.state, isEmpty);
  });

  test('selectAll replaces; clear empties', () {
    final n = LibrarySelectionNotifier();
    n.toggle('x');
    n.selectAll(['a', 'b']);
    expect(n.state, {'a', 'b'});
    n.clear();
    expect(n.state, isEmpty);
  });

  test('groupCheckState: none / some / all / empty', () {
    expect(groupCheckState(['a', 'b'], {}), GroupCheckState.none);
    expect(groupCheckState(['a', 'b'], {'a'}), GroupCheckState.some);
    expect(groupCheckState(['a', 'b'], {'a', 'b'}), GroupCheckState.all);
    expect(groupCheckState([], {'a'}), GroupCheckState.none);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/home/library_selection_test.dart`
Expected: FAIL — symbols not found.

- [ ] **Step 3: Implement**

`lib/ui/home/state/library_selection.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Library multi-select: the set of selected video URIs. Selection mode is
/// active ⇔ the set is non-empty (deselecting the last item exits the mode).
class LibrarySelectionNotifier extends StateNotifier<Set<String>> {
  LibrarySelectionNotifier() : super(const {});

  bool isSelected(String uri) => state.contains(uri);
  bool get active => state.isNotEmpty;

  void toggle(String uri) {
    final next = Set<String>.of(state);
    if (!next.remove(uri)) next.add(uri);
    state = next;
  }

  /// Toggle a whole group (a day): remove them all if every one is already
  /// selected, otherwise add the missing ones.
  void toggleAll(Iterable<String> uris) {
    final group = uris.toSet();
    if (group.isEmpty) return;
    final next = Set<String>.of(state);
    if (group.every(next.contains)) {
      next.removeAll(group);
    } else {
      next.addAll(group);
    }
    state = next;
  }

  /// Select exactly [uris] (for "select all" with the visible list).
  void selectAll(Iterable<String> uris) => state = uris.toSet();

  void clear() => state = const {};
}

final librarySelectionProvider =
    StateNotifierProvider<LibrarySelectionNotifier, Set<String>>(
        (ref) => LibrarySelectionNotifier());

enum GroupCheckState { none, some, all }

/// Tri-state for a day header's checkbox given the group's URIs and the
/// current selection.
GroupCheckState groupCheckState(Iterable<String> groupUris, Set<String> selected) {
  final group = groupUris.toSet();
  if (group.isEmpty) return GroupCheckState.none;
  final n = group.where(selected.contains).length;
  if (n == 0) return GroupCheckState.none;
  if (n == group.length) return GroupCheckState.all;
  return GroupCheckState.some;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/home/library_selection_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/home/state/library_selection.dart test/ui/home/library_selection_test.dart
git commit -m "feat(library): selection state + groupCheckState helper"
```

---

### Task 2: `VideoTile` long-press + selected overlay

**Files:**
- Modify: `lib/ui/home/widgets/video_tile.dart`
- Test: `test/ui/home/video_tile_select_test.dart`

**Interfaces:**
- Produces: `VideoTile` gains `final VoidCallback? onLongPress;`, `final bool selected;` (default false), `final bool selecting;` (default false). Long-press fires `onLongPress`. When `selected`, an accent check overlay is shown; when `selecting && !selected`, an empty outline circle.

**Context:** `_VideoTileState` builds `_buildCover`/`_buildListRow`, each wrapping the 16:9 thumbnail in a `Stack` (`_thumbKey` is on the `ClipRRect`). Add the overlay inside that Stack. `PressBounce` wraps the tile — add `onLongPress` to it. Check `PressBounce`'s constructor for an `onLongPress` param; if it lacks one, wrap the tile in a `GestureDetector(onLongPress: ...)` around/inside `PressBounce` instead (verify in implementation — see `lib/ui/widgets/press_bounce.dart`).

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

const _v = VideoItem(
  id: '1', uri: 'content://v/1', name: 'clip.mp4', folder: 'Movies',
  durationMs: 1000, sizeBytes: 10, dateAddedMs: 0,
);

Widget _host(SettingsService s, {required bool selected, required VoidCallback onLong}) {
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  return UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(width: 300, child: VideoTile(
        video: _v, listRow: false, selected: selected, selecting: true,
        onTap: (_) {}, onLongPress: onLong,
      )))),
    ),
  );
}

void main() {
  testWidgets('long-press fires onLongPress', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    var longPressed = false;
    await tester.pumpWidget(_host(s, selected: false, onLong: () => longPressed = true));
    await tester.longPress(find.byType(VideoTile));
    await tester.pump(const Duration(milliseconds: 400));
    expect(longPressed, true);
  });

  testWidgets('selected tile shows the check overlay', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await tester.pumpWidget(_host(s, selected: true, onLong: () {}));
    await tester.pump();
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
```

> Note: adjust `find.byIcon(Icons.check)` to whatever check icon the implementation uses; keep the assertion on the presence of a selected-state check marker.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/home/video_tile_select_test.dart`
Expected: FAIL — `onLongPress`/`selected`/`selecting` not defined.

- [ ] **Step 3: Add the fields + overlay**

In `lib/ui/home/widgets/video_tile.dart`, add to the widget:

```dart
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selecting;
```
and to the constructor: `this.onLongPress, this.selected = false, this.selecting = false,`.

Wrap the tile's `PressBounce` with long-press support (per the Context note). Add an overlay to the thumbnail `Stack` in BOTH layouts (as the last child):

```dart
                    if (widget.selecting)
                      Positioned(
                        top: 6, right: 6,
                        child: _selectionBadge(accent),
                      ),
                    if (widget.selected)
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Color(0x552D6CFF)),
                        ),
                      ),
```

Wait — no hardcoded colors. Use the accent scrim:

```dart
                    if (widget.selected)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: accent.withValues(alpha: 0.28)),
                        ),
                      ),
                    if (widget.selecting)
                      Positioned(
                        top: 6, right: 6,
                        child: _selectionBadge(accent, widget.selected),
                      ),
```

Add the badge builder to `_VideoTileState`:

```dart
  Widget _selectionBadge(Color accent, bool selected) => Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? accent : Colors.black.withValues(alpha: 0.35),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: selected
            ? Icon(Icons.check, size: 14, color: onAccent(accent))
            : null,
      );
```

(`onAccent` is imported from `core/theme/kivo_theme.dart`, already used in this file. The white border + black scrim are on-thumbnail chrome over imagery, consistent with the existing duration badge's `Colors.black.withValues(...)` — not theme surfaces.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/home/video_tile_select_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Analyze + commit**

Run: `flutter analyze lib/ui/home/widgets/video_tile.dart`
Expected: No issues.

```bash
git add lib/ui/home/widgets/video_tile.dart test/ui/home/video_tile_select_test.dart
git commit -m "feat(library): VideoTile long-press + selected overlay"
```

---

### Task 3: Feed wiring — tap/long-press + day-header checkbox

**Files:**
- Modify: `lib/ui/home/widgets/video_density_feed.dart`
- Test: `test/ui/home/feed_selection_test.dart`

**Interfaces:**
- Consumes: `librarySelectionProvider`, `groupCheckState`, `GroupCheckState` (Task 1); `VideoTile` selection props (Task 2).
- Produces: the feed toggles selection on tap when active (else opens), enters selection via long-press, and shows a tri-state day-header checkbox.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/state/library_selection.dart';
import 'package:kivo_player/ui/home/widgets/video_density_feed.dart';
import 'package:kivo_player/ui/home/widgets/video_tile.dart';
import '../../fakes/fakes.dart';

const _a = VideoItem(id: '1', uri: 'u1', name: 'a.mp4', folder: 'F', durationMs: 1000, sizeBytes: 1, dateAddedMs: 0);
const _b = VideoItem(id: '2', uri: 'u2', name: 'b.mp4', folder: 'F', durationMs: 1000, sizeBytes: 1, dateAddedMs: 0);

void main() {
  testWidgets('long-press enters selection; tap then toggles instead of opening', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    ]);
    addTearDown(c.dispose);
    var opens = 0;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: Scaffold(body: VideoDensityFeed(
        videos: const [_a, _b], groupByDate: false, showContinueRow: false,
        onOpen: (_, __, ___) => opens++,
      ))),
    ));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(VideoTile).first);
    await tester.pumpAndSettle();
    expect(c.read(librarySelectionProvider), {'u1'});

    // Now a tap toggles, does not open.
    await tester.tap(find.byType(VideoTile).at(1));
    await tester.pumpAndSettle();
    expect(c.read(librarySelectionProvider), {'u1', 'u2'});
    expect(opens, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/home/feed_selection_test.dart`
Expected: FAIL — tiles don't wire long-press/toggle yet (opens or no selection change).

- [ ] **Step 3: Wire selection in the feed**

In `_VideoDensityFeedState.build`, after `final cs = ...`:

```dart
    final selected = ref.watch(librarySelectionProvider);
    final selecting = selected.isNotEmpty;
    final sel = ref.read(librarySelectionProvider.notifier);
```

For BOTH `VideoTile` call sites (list `~line 197`, grid `~line 226`), replace their props with:

```dart
                                  selected: selected.contains(v.uri),
                                  selecting: selecting,
                                  onLongPress: () => sel.toggle(v.uri),
                                  onTap: (origin) => selecting
                                      ? sel.toggle(v.uri)
                                      : widget.onOpen(v, widget.videos, origin),
```

- [ ] **Step 4: Add the day-header checkbox**

Replace the day-header `Row` (lines ~160-171) so it prepends a tri-state checkbox when selecting:

```dart
                  child: Row(children: [
                    if (selecting) ...[
                      _DayCheckbox(
                        state: groupCheckState(s.items.map((v) => v.uri), selected),
                        accent: accentColor,
                        onTap: () => sel.toggleAll(s.items.map((v) => v.uri)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(width: 3, height: 13, color: accentColor),
                    const SizedBox(width: 7),
                    Text(
                      s.label,
                      style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ]),
```

Add a small `_DayCheckbox` widget at the bottom of the file:

```dart
class _DayCheckbox extends StatelessWidget {
  final GroupCheckState state;
  final Color accent;
  final VoidCallback onTap;
  const _DayCheckbox({required this.state, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filled = state == GroupCheckState.all;
    final partial = state == GroupCheckState.some;
    return InkResponse(
      onTap: onTap,
      child: Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled || partial ? accent : Colors.transparent,
          border: Border.all(
            color: filled || partial ? accent : cs.onSurfaceVariant,
            width: 2),
        ),
        child: filled
            ? Icon(Icons.check, size: 13, color: onAccent(accent))
            : partial
                ? Icon(Icons.remove, size: 13, color: onAccent(accent))
                : null,
      ),
    );
  }
}
```

Add the import `import '../../../core/theme/kivo_theme.dart';` (for `onAccent`) and `import '../state/library_selection.dart';` to the feed file. (`ContinueRow`'s internal `VideoTile`s keep the new defaults — `selected:false, selecting:false, onLongPress:null` — so the continue strip stays open-only; no change needed there.)

- [ ] **Step 5: Run test + analyze**

Run: `flutter test test/ui/home/feed_selection_test.dart`
Expected: PASS.
Run: `flutter analyze lib/ui/home/widgets/video_density_feed.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/home/widgets/video_density_feed.dart test/ui/home/feed_selection_test.dart
git commit -m "feat(library): feed wiring for selection + day-header checkbox"
```

---

### Task 4: Batch native ops — `MediaFileOps.deleteMany/shareMany` + Kotlin

**Files:**
- Modify: `lib/platform/interfaces/media_file_ops.dart`
- Modify: `lib/platform/android/android_media_file_ops.dart`
- Modify: `android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt`
- Modify: `test/fakes/fakes.dart` (extend `FakeMediaFileOps`)
- Test: `test/platform/fake_media_file_ops_many_test.dart`

**Interfaces:**
- Produces:
  - `MediaFileOps.deleteMany(List<String> uris) → Future<FileOpStatus>` and `shareMany(List<String> uris) → Future<void>`.
  - `FakeMediaFileOps`: `deletedManyUris` (List<List<String>>), `sharedManyUris` (List<List<String>>), `deleteManyResult` (FileOpStatus, default ok).

- [ ] **Step 1: Write the failing test (fake contract)**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_file_ops.dart';
import '../fakes/fakes.dart';

void main() {
  test('FakeMediaFileOps records batch calls', () async {
    final ops = FakeMediaFileOps()..deleteManyResult = FileOpStatus.ok;
    expect(await ops.deleteMany(['u1', 'u2']), FileOpStatus.ok);
    expect(ops.deletedManyUris.single, ['u1', 'u2']);
    await ops.shareMany(['u1', 'u2']);
    expect(ops.sharedManyUris.single, ['u1', 'u2']);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/platform/fake_media_file_ops_many_test.dart`
Expected: FAIL — methods not defined.

- [ ] **Step 3: Add to the interface**

In `lib/platform/interfaces/media_file_ops.dart`, add to `abstract class MediaFileOps`:

```dart
  /// Deletes several files. On Android 11+ without all-files-access, the SYSTEM
  /// shows ONE consent dialog for the whole batch. Returns cancelled if declined.
  Future<FileOpStatus> deleteMany(List<String> uris);

  /// Shares several files at once (ACTION_SEND_MULTIPLE).
  Future<void> shareMany(List<String> uris);
```

- [ ] **Step 4: Implement in `AndroidMediaFileOps`**

Add to `lib/platform/android/android_media_file_ops.dart`:

```dart
  @override
  Future<FileOpStatus> deleteMany(List<String> uris) async {
    try {
      final s = await _channel.invokeMethod<String>('deleteMany', {'uris': uris});
      return _status(s);
    } catch (_) {
      return FileOpStatus.error;
    }
  }

  @override
  Future<void> shareMany(List<String> uris) async {
    try {
      await _channel.invokeMethod<void>('shareMany', {'uris': uris});
    } catch (_) {/* fire-and-forget */}
  }
```

- [ ] **Step 5: Implement the native branches**

In `MainActivity.kt`, in the `kivo/media` handler `when`, before `else -> result.notImplemented()`:

```kotlin
                    "shareMany" -> {
                        val uris = call.argument<List<String>>("uris")
                        if (uris == null) { result.error("INVALID_ARG", "uris required", null); return@setMethodCallHandler }
                        try {
                            val list = ArrayList<Uri>(uris.map { Uri.parse(it) })
                            val send = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                                type = "video/*"
                                putParcelableArrayListExtra(Intent.EXTRA_STREAM, list)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(send, null))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.message, null)
                        }
                    }
                    "deleteMany" -> {
                        val uris = call.argument<List<String>>("uris")
                        if (uris == null) { result.error("INVALID_ARG", "uris required", null); return@setMethodCallHandler }
                        if (pendingFileOpResult != null) { result.success("error"); return@setMethodCallHandler }
                        val us = uris.map { Uri.parse(it) }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                                Environment.isExternalStorageManager()) {
                                for (u in us) contentResolver.delete(u, null, null)
                                result.success("ok")
                                return@setMethodCallHandler
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val pi = MediaStore.createDeleteRequest(contentResolver, us)
                                pendingFileOpResult = result
                                startIntentSenderForResult(pi.intentSender, REQ_DELETE, null, 0, 0, 0)
                            } else {
                                for (u in us) contentResolver.delete(u, null, null)
                                result.success("ok")
                            }
                        } catch (e: Exception) {
                            pendingFileOpResult = null
                            result.success("error")
                        }
                    }
```

(`onActivityResult`'s `REQ_DELETE` handler already replies `"ok"`/`"cancelled"` — the batch request reuses it unchanged.)

- [ ] **Step 6: Extend `FakeMediaFileOps`**

In `test/fakes/fakes.dart`, add to `FakeMediaFileOps`:

```dart
  final List<List<String>> deletedManyUris = [];
  final List<List<String>> sharedManyUris = [];
  FileOpStatus deleteManyResult = FileOpStatus.ok;

  @override
  Future<FileOpStatus> deleteMany(List<String> uris) async {
    deletedManyUris.add(List.of(uris));
    return deleteManyResult;
  }

  @override
  Future<void> shareMany(List<String> uris) async => sharedManyUris.add(List.of(uris));
```

- [ ] **Step 7: Run test + analyze + release build**

Run: `flutter test test/platform/fake_media_file_ops_many_test.dart`
Expected: PASS.
Run: `flutter analyze lib/platform/interfaces/media_file_ops.dart lib/platform/android/android_media_file_ops.dart`
Expected: No issues.
Run: `flutter build apk --release`
Expected: `Built ...apk` (compiles the Kotlin).

- [ ] **Step 8: Commit**

```bash
git add lib/platform/interfaces/media_file_ops.dart lib/platform/android/android_media_file_ops.dart android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt test/fakes/fakes.dart test/platform/fake_media_file_ops_many_test.dart
git commit -m "feat(library): batch deleteMany/shareMany (native + fake)"
```

---

### Task 5: `VideoActionsController.deleteMany/shareMany`

**Files:**
- Modify: `lib/player/library/video_actions.dart`
- Test: `test/player/library/video_actions_many_test.dart`

**Interfaces:**
- Consumes: `MediaFileOps.deleteMany/shareMany` (Task 4); existing stores + `_refreshLibrary`.
- Produces: `VideoActionsController.deleteMany(List<VideoItem>) → Future<FileOpStatus>`, `shareMany(List<VideoItem>) → Future<void>`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_file_ops.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/player/library/media_permission.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/library/video_actions.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import '../../fakes/fakes.dart';

const _a = VideoItem(id: '1', uri: 'u1', name: 'a.mp4', folder: 'F', durationMs: 1000, sizeBytes: 1, dateAddedMs: 0);
const _b = VideoItem(id: '2', uri: 'u2', name: 'b.mp4', folder: 'F', durationMs: 1000, sizeBytes: 1, dateAddedMs: 0);

ProviderContainer _c(FakeMediaFileOps ops, ResumeService r, PlayedStore p) => ProviderContainer(overrides: [
      mediaFileOpsProvider.overrideWithValue(ops),
      resumeServiceProvider.overrideWithValue(r),
      playedStoreProvider.overrideWithValue(p),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
      mediaPermissionImplProvider.overrideWithValue(FakeMediaPermission(MediaAccess.granted)),
    ]);

void main() {
  test('deleteMany clears resume+played for each and returns ok', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put('a.mp4', 5, 1);
    await played.markPlayed('b.mp4');
    final ops = FakeMediaFileOps()..deleteManyResult = FileOpStatus.ok;
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    final status = await c.read(videoActionsProvider).deleteMany([_a, _b]);
    expect(status, FileOpStatus.ok);
    expect(ops.deletedManyUris.single, ['u1', 'u2']);
    expect(resume.positionFor('a.mp4'), isNull);
    expect(played.isPlayed('b.mp4'), false);
  });

  test('cancelled deleteMany leaves stores untouched', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put('a.mp4', 5, 1);
    final ops = FakeMediaFileOps()..deleteManyResult = FileOpStatus.cancelled;
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).deleteMany([_a, _b]);
    expect(resume.positionFor('a.mp4'), const Duration(seconds: 5));
  });

  test('shareMany passes the uris', () async {
    final ops = FakeMediaFileOps();
    final c = _c(ops, ResumeService(InMemoryResumeStore()), InMemoryPlayedStore());
    addTearDown(c.dispose);
    await c.read(videoActionsProvider).shareMany([_a, _b]);
    expect(ops.sharedManyUris.single, ['u1', 'u2']);
  });
}
```

> Confirm `FakeMediaPermission` + `mediaPermissionImplProvider` names against `test/player/library/video_actions_test.dart` (same override used there); adjust if the fake/provider names differ.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/player/library/video_actions_many_test.dart`
Expected: FAIL — `deleteMany`/`shareMany` not defined.

- [ ] **Step 3: Implement**

Add to `VideoActionsController` in `lib/player/library/video_actions.dart`:

```dart
  Future<FileOpStatus> deleteMany(List<VideoItem> videos) async {
    final status = await _ref.read(mediaFileOpsProvider).deleteMany(
        videos.map((v) => v.uri).toList());
    if (status != FileOpStatus.ok) return status;
    final resume = _ref.read(resumeServiceProvider);
    final played = _ref.read(playedStoreProvider);
    for (final v in videos) {
      await resume.clear(v.name);
      await played.remove(v.name);
    }
    await _refreshLibrary();
    return status;
  }

  Future<void> shareMany(List<VideoItem> videos) =>
      _ref.read(mediaFileOpsProvider).shareMany(videos.map((v) => v.uri).toList());
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/player/library/video_actions_many_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/player/library/video_actions.dart test/player/library/video_actions_many_test.dart
git commit -m "feat(library): VideoActionsController deleteMany/shareMany"
```

---

### Task 6: `SelectionAppBar` + wire into library & folder screens

**Files:**
- Create: `lib/ui/home/widgets/selection_app_bar.dart`
- Modify: `lib/ui/home/library_screen.dart`
- Modify: `lib/ui/home/folder_screen.dart`
- Test: `test/ui/home/selection_app_bar_test.dart`

**Interfaces:**
- Consumes: `librarySelectionProvider` (Task 1); `videoActionsProvider.deleteMany/shareMany` (Task 5); `maybeOfferAllFilesAccess` (`video_options_sheet.dart`); `FileOpStatus`.
- Produces: `SelectionAppBar` (`ConsumerWidget implements PreferredSizeWidget`) taking `final List<VideoItem> allVisible;` — the current screen's visible list (used for "select all" and to resolve selected URIs → `VideoItem`s for batch ops).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/state/library_selection.dart';
import 'package:kivo_player/ui/home/widgets/selection_app_bar.dart';

const _a = VideoItem(id: '1', uri: 'u1', name: 'a.mp4', folder: 'F', durationMs: 1, sizeBytes: 1, dateAddedMs: 0);
const _b = VideoItem(id: '2', uri: 'u2', name: 'b.mp4', folder: 'F', durationMs: 1, sizeBytes: 1, dateAddedMs: 0);

void main() {
  testWidgets('shows count, select-all fills, X clears', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(librarySelectionProvider.notifier).toggle('u1');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(appBar: SelectionAppBar(allVisible: [_a, _b])),
      ),
    ));
    await tester.pump();

    expect(find.text('1 seleccionado'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pump();
    expect(c.read(librarySelectionProvider), {'u1', 'u2'});

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(c.read(librarySelectionProvider), isEmpty);
  });
}
```

> The count string may be "1 seleccionado" / "N seleccionados" (singular/plural) — match whatever the implementation renders; keep the assertion meaningful.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/home/selection_app_bar_test.dart`
Expected: FAIL — `SelectionAppBar` not found.

- [ ] **Step 3: Implement `SelectionAppBar`**

`lib/ui/home/widgets/selection_app_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/interfaces/media_file_ops.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/video_actions.dart';
import '../state/library_selection.dart';
import 'video_options_sheet.dart'; // maybeOfferAllFilesAccess

class SelectionAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final List<VideoItem> allVisible;
  const SelectionAppBar({super.key, required this.allVisible});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(librarySelectionProvider);
    final sel = ref.read(librarySelectionProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final chosen = allVisible.where((v) => selected.contains(v.uri)).toList();
    final messenger = ScaffoldMessenger.of(context);

    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cancelar', onPressed: sel.clear),
      title: Text('${selected.length} seleccionado${selected.length == 1 ? '' : 's'}'),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all), tooltip: 'Seleccionar todo',
          onPressed: () => sel.selectAll(allVisible.map((v) => v.uri)),
        ),
        IconButton(
          icon: const Icon(Icons.share), tooltip: 'Compartir',
          onPressed: chosen.isEmpty ? null : () async {
            await ref.read(videoActionsProvider).shareMany(chosen);
            sel.clear();
          },
        ),
        IconButton(
          icon: Icon(Icons.delete, color: cs.error), tooltip: 'Borrar',
          onPressed: chosen.isEmpty ? null : () async {
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
          },
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the SelectionAppBar test**

Run: `flutter test test/ui/home/selection_app_bar_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire into `library_screen.dart`**

In `library_screen.dart`'s `build`, compute selection + the visible list, swap the AppBar, and wrap in `PopScope`. The visible list is `filtered` (the list already passed to `VideoDensityFeed` in `_videosTab`/search body). Add near the top of `build`:

```dart
    final selecting = ref.watch(librarySelectionProvider).isNotEmpty;
```

Change the `Scaffold(appBar: AppBar(...))` to `Scaffold(appBar: selecting ? SelectionAppBar(allVisible: <visibleList>) : AppBar(...))`. Because the visible list depends on the current tab/filter, expose it: compute the same `filtered` list used by the feed at `build` scope (or pass the currently-displayed list). If `filtered` is computed inside `_videosTab`, lift the visible-list computation so both the feed and the SelectionAppBar use it. Then wrap the returned `Scaffold` in:

```dart
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(librarySelectionProvider.notifier).clear();
      },
      child: Scaffold(...),
    );
```

Add imports for `SelectionAppBar` and `librarySelectionProvider`.

> Implementation note: `library_screen` has "Todo"/"Carpetas" tabs and a search mode. Selection is only meaningful for the video list (the "Todo"/search feed). Use the same filtered video list that feeds `VideoDensityFeed` as `allVisible`. If the "Carpetas" tab is active (folder grid, not videos), selection won't be entered there (no `VideoTile` long-press), so the normal AppBar stays; guard so `SelectionAppBar` only replaces the bar when `selecting` is true (which can only happen from a video long-press).

- [ ] **Step 6: Wire into `folder_screen.dart`**

`folder_screen.dart` is a `ConsumerWidget` with `Scaffold(appBar: AppBar(title: folder), body: VideoDensityFeed(videos: vids, ...))` (vids = the live folder list from Task earlier). Change to:

```dart
    final selecting = ref.watch(librarySelectionProvider).isNotEmpty;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(librarySelectionProvider.notifier).clear();
      },
      child: Scaffold(
        appBar: selecting
            ? SelectionAppBar(allVisible: vids)
            : AppBar(title: Text(folder, ...)),
        body: VideoDensityFeed(videos: vids, ...),
      ),
    );
```

Add imports for `SelectionAppBar` and `librarySelectionProvider`.

- [ ] **Step 7: Analyze + full suite**

Run: `flutter analyze lib/ui/home/widgets/selection_app_bar.dart lib/ui/home/library_screen.dart lib/ui/home/folder_screen.dart`
Expected: No issues.
Run: `flutter test`
Expected: All green.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/home/widgets/selection_app_bar.dart lib/ui/home/library_screen.dart lib/ui/home/folder_screen.dart test/ui/home/selection_app_bar_test.dart
git commit -m "feat(library): SelectionAppBar wired into library + folder with PopScope"
```

---

### Task 7: Build, install, and device verification

**Files:** none (verification only).

- [ ] **Step 1: Full suite**

Run: `flutter test`
Expected: All green (375 baseline + new tests).

- [ ] **Step 2: Release build**

Run: `flutter build apk --release`
Expected: `Built build\app\outputs\flutter-apk\app-release.apk`.

- [ ] **Step 3: Install to the Pixel 6**

Run: `& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" -s 24231FDF6006ST install -r build\app\outputs\flutter-apk\app-release.apk`
Expected: `Success`.

- [ ] **Step 4: Device checklist** (report pass/fail per item)

  - Long-press a tile → selection mode: tiles show check circles, day headers show tri-state checkboxes, top bar becomes "N seleccionado(s)".
  - Tap tiles to toggle; deselecting the last exits selection mode.
  - A day-header checkbox selects/deselects the whole day; shows indeterminate (–) when partial, full check when all.
  - Seleccionar todo selects every visible video; X and system Back both clear (without leaving the screen).
  - Borrar N → one confirm → (all-files-access granted) no OS dialog / (not granted) ONE system dialog for the whole batch → videos gone, their "continue watching" gone, selection exits.
  - Compartir N → chooser with multiple videos.
  - Inside a folder (flat feed): tile selection + batch work; no day-header checkboxes (no date groups).
  - "Continuar viendo" strip tiles do NOT enter/participate in selection.

This task has no commit (verification only). Report results; a failed item becomes a fix task.

---

## Self-Review notes

- **Spec coverage:** §1 state/groupCheckState→Task 1; §2 tile→Task 2; §3 feed wiring + day checkbox→Task 3; §4 SelectionAppBar→Task 6; §5 batch ops (native+controller)→Tasks 4-5; §6 units→all; §7 tests→each + Task 7 device.
- **Type consistency:** `LibrarySelectionNotifier{toggle,toggleAll,selectAll,clear,isSelected,active}`, `librarySelectionProvider`, `groupCheckState`→`GroupCheckState`, `VideoTile{onLongPress,selected,selecting}`, `MediaFileOps.deleteMany/shareMany`, `VideoActionsController.deleteMany/shareMany`, `SelectionAppBar{allVisible}`, `FakeMediaFileOps{deletedManyUris,sharedManyUris,deleteManyResult}` — consistent across tasks.
- **Native task (4)** has no unit test for the Kotlin; gated by analyze + release build + Task 7 device checklist. The batch delete reuses the existing `REQ_DELETE`/`onActivityResult`/`pendingFileOpResult` machinery (one dialog for the whole `createDeleteRequest(us)`).
- **PopScope caveat (Task 6):** library lives in a tab navigator; `canPop: !selecting` lets normal back through when not selecting (tabs/exit unaffected) and only intercepts to clear selection. Verify on device that back still unwinds tabs/folder normally when nothing is selected.
- **Post-merge:** after Task 7, the controller creates a feature branch retroactively is NOT possible — so the executor MUST branch BEFORE Task 1 (see execution note) so the PR contains these commits.
