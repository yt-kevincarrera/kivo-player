# Library ⋮ File-Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Activate each library video's ⋮ menu (currently a dead `onOptions: null` button) with Share, Rename, Details, and Delete, backed by Android MediaStore/scoped-storage.

**Architecture:** A new `MediaFileOps` platform interface (Android impl on the existing `kivo/media` channel, with system-consent flows for delete/rename via `onActivityResult`). A `VideoActionsController` orchestrates each op and its side effects (refresh the media index; migrate resume+played keys on rename; clear them on delete). A `VideoOptionsSheet` plus rename/details/confirm dialogs form the UI. `VideoItem` gains optional `width/height/path` for the details sheet.

**Tech Stack:** Flutter, Riverpod, Hive, Kotlin (MediaStore), `flutter_test`.

## Global Constraints

- Single configurable accent; no new hardcoded colors (Delete uses `colorScheme.error`; everything else the theme scheme).
- Platform-boundary pattern: interface in `lib/platform/interfaces/`, Android impl in `lib/platform/android/`, throws-until-overridden provider, override in `lib/main.dart`.
- No new pub dependencies (share via native `ACTION_SEND`).
- `VideoItem` new fields are OPTIONAL with defaults — no existing construction/test breaks.
- No `flutter run`. On module close: `flutter build apk --release`, then `adb install` to the Pixel 6 (device `24231FDF6006ST`; adb at `$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe`).
- Full suite stays green (`flutter test`), currently 348 tests.

---

### Task 1: `VideoItem` gains optional `width/height/path` + scan reads them

**Files:**
- Modify: `lib/platform/interfaces/media_indexer.dart`
- Modify: `lib/platform/android/android_media_indexer.dart`
- Modify: `android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt` (the `"scan"` branch, ~lines 209-242)
- Test: `test/platform/video_item_test.dart`

**Interfaces:**
- Produces: `VideoItem` with three new optional fields `int width` (default 0), `int height` (default 0), `String path` (default '').

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';

void main() {
  test('VideoItem new fields default to 0/empty and are optional', () {
    const v = VideoItem(
      id: '1', uri: 'content://v/1', name: 'a.mp4', folder: 'Movies',
      durationMs: 1000, sizeBytes: 10, dateAddedMs: 0,
    );
    expect(v.width, 0);
    expect(v.height, 0);
    expect(v.path, '');
  });

  test('VideoItem accepts explicit width/height/path', () {
    const v = VideoItem(
      id: '1', uri: 'content://v/1', name: 'a.mp4', folder: 'Movies',
      durationMs: 1000, sizeBytes: 10, dateAddedMs: 0,
      width: 1920, height: 1080, path: 'Movies/',
    );
    expect(v.width, 1920);
    expect(v.height, 1080);
    expect(v.path, 'Movies/');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/platform/video_item_test.dart`
Expected: FAIL — no named parameter `width`.

- [ ] **Step 3: Add the fields to `VideoItem`**

In `lib/platform/interfaces/media_indexer.dart`, extend the class (keep existing fields):

```dart
class VideoItem {
  final String id;
  final String uri;
  final String name;
  final String folder;
  final int durationMs;
  final int sizeBytes;
  final int dateAddedMs;
  final int width;   // px, 0 if unknown
  final int height;  // px, 0 if unknown
  final String path; // MediaStore RELATIVE_PATH, '' if unknown
  const VideoItem({
    required this.id,
    required this.uri,
    required this.name,
    required this.folder,
    required this.durationMs,
    required this.sizeBytes,
    required this.dateAddedMs,
    this.width = 0,
    this.height = 0,
    this.path = '',
  });
}
```

- [ ] **Step 4: Parse them in `AndroidMediaIndexer.scan`**

In `lib/platform/android/android_media_indexer.dart`, add to the mapping inside `scan()`:

```dart
      return VideoItem(
        id: m['id'] as String,
        uri: m['uri'] as String,
        name: (m['name'] as String?) ?? '',
        folder: (m['folder'] as String?) ?? '',
        durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
        dateAddedMs: (m['dateAddedMs'] as num?)?.toInt() ?? 0,
        width: (m['width'] as num?)?.toInt() ?? 0,
        height: (m['height'] as num?)?.toInt() ?? 0,
        path: (m['path'] as String?) ?? '',
      );
```

- [ ] **Step 5: Add the columns to the Kotlin scan**

In `MainActivity.kt`, inside the `"scan"` branch: add to `proj` (after `DATA`):

```kotlin
                                    MediaStore.Video.Media.WIDTH,
                                    MediaStore.Video.Media.HEIGHT,
                                    MediaStore.Video.Media.RELATIVE_PATH,
```

Add column lookups next to the others:

```kotlin
                                    val widthC = c.getColumnIndex(MediaStore.Video.Media.WIDTH)
                                    val heightC = c.getColumnIndex(MediaStore.Video.Media.HEIGHT)
                                    val relPathC = c.getColumnIndex(MediaStore.Video.Media.RELATIVE_PATH)
```

And add to the `hashMapOf(...)`:

```kotlin
                                            "width" to (if (widthC >= 0) c.getInt(widthC) else 0),
                                            "height" to (if (heightC >= 0) c.getInt(heightC) else 0),
                                            "path" to (if (relPathC >= 0) (c.getString(relPathC) ?: "") else ""),
```

(`RELATIVE_PATH` exists on API 29+; `getColumnIndex` returns -1 below that, handled by the `>= 0` guard.)

- [ ] **Step 6: Run test + analyze**

Run: `flutter test test/platform/video_item_test.dart`
Expected: PASS (2 tests).
Run: `flutter analyze lib/platform/interfaces/media_indexer.dart lib/platform/android/android_media_indexer.dart`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add lib/platform/interfaces/media_indexer.dart lib/platform/android/android_media_indexer.dart android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt test/platform/video_item_test.dart
git commit -m "feat(library): VideoItem gains optional width/height/path from the scan"
```

---

### Task 2: Store additions for rename migration — `PlayedStore.remove` + `ResumeService.rename`

**Files:**
- Modify: `lib/player/library/played.dart`
- Modify: `lib/player/resume/resume_service.dart`
- Test: `test/player/resume/rename_migration_test.dart`

**Interfaces:**
- Produces:
  - `PlayedStore.remove(String key) → Future<void>` (added to the abstract class, `HivePlayedStore`, and `InMemoryPlayedStore`).
  - `ResumeService.rename(String from, String to) → Future<void>` — moves the resume entry preserving its `seconds` and `updatedAtMs`; no-op if `from` has no entry.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import '../../fakes/fakes.dart';

void main() {
  test('PlayedStore.remove deletes a key', () async {
    final p = InMemoryPlayedStore();
    await p.markPlayed('a.mp4');
    expect(p.isPlayed('a.mp4'), true);
    await p.remove('a.mp4');
    expect(p.isPlayed('a.mp4'), false);
  });

  test('ResumeService.rename moves the entry preserving seconds+timestamp', () async {
    final store = InMemoryResumeStore();
    final svc = ResumeService(store);
    await store.put('old.mp4', 42, 111);
    await svc.rename('old.mp4', 'new.mp4');
    expect(svc.positionFor('old.mp4'), isNull);
    expect(svc.positionFor('new.mp4'), const Duration(seconds: 42));
    final e = svc.entries().firstWhere((x) => x.key == 'new.mp4');
    expect(e.updatedAtMs, 111); // timestamp preserved (no jump to top)
  });

  test('ResumeService.rename is a no-op when the source has no entry', () async {
    final svc = ResumeService(InMemoryResumeStore());
    await svc.rename('missing.mp4', 'x.mp4');
    expect(svc.positionFor('x.mp4'), isNull);
  });
}
```

> Confirm `InMemoryResumeStore` exists in `test/fakes/fakes.dart` with a `put(key, seconds, updatedAtMs)` matching `ResumeStore`. It is already used by other tests (`resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore()))`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/player/resume/rename_migration_test.dart`
Expected: FAIL — `remove` not defined on `PlayedStore` / `rename` not defined on `ResumeService`.

- [ ] **Step 3: Add `remove` to `PlayedStore`**

In `lib/player/library/played.dart`:

```dart
abstract class PlayedStore {
  bool isPlayed(String key);
  Future<void> markPlayed(String key);
  Future<void> remove(String key);
  Set<String> keys();
}
```

`HivePlayedStore`:

```dart
  @override
  Future<void> remove(String key) => box.delete(key);
```

`InMemoryPlayedStore`:

```dart
  @override
  Future<void> remove(String key) async => _s.remove(key);
```

- [ ] **Step 4: Add `rename` to `ResumeService`**

In `lib/player/resume/resume_service.dart`, add:

```dart
  /// Moves a resume entry from [from] to [to], preserving its recorded seconds
  /// and original timestamp (so a renamed video keeps its place in "continue
  /// watching" instead of jumping to the top). No-op if [from] has no entry.
  Future<void> rename(String from, String to) async {
    ResumeEntry? found;
    for (final e in _store.entries()) {
      if (e.key == from) { found = e; break; }
    }
    if (found == null) return;
    await _store.put(to, found.seconds, found.updatedAtMs);
    await _store.remove(from);
  }
```

- [ ] **Step 5: Run test + full suite**

Run: `flutter test test/player/resume/rename_migration_test.dart`
Expected: PASS (3 tests).
Run: `flutter test`
Expected: All green (adding an abstract method compiles because both impls now implement it; no other `PlayedStore` impls exist).

- [ ] **Step 6: Commit**

```bash
git add lib/player/library/played.dart lib/player/resume/resume_service.dart test/player/resume/rename_migration_test.dart
git commit -m "feat(library): PlayedStore.remove + ResumeService.rename for key migration"
```

---

### Task 3: `MediaFileOps` interface, provider, and fake

**Files:**
- Create: `lib/platform/interfaces/media_file_ops.dart`
- Create: `lib/platform/media_file_ops_provider.dart`
- Modify: `test/fakes/fakes.dart` (append `FakeMediaFileOps`)
- Test: `test/platform/fake_media_file_ops_test.dart`

**Interfaces:**
- Produces:
  - `enum FileOpStatus { ok, cancelled, error }`
  - `class RenameOutcome { final FileOpStatus status; final String? newName; const RenameOutcome(this.status, {this.newName}); }`
  - `abstract class MediaFileOps { Future<FileOpStatus> delete(String uri); Future<RenameOutcome> rename(String uri, String newBaseName); Future<void> share(String uri); }`
  - `final mediaFileOpsProvider = Provider<MediaFileOps>((ref) => throw UnimplementedError(...));`
  - `FakeMediaFileOps` (test): records `deletedUris`, `renamed` (list of `(uri, base)`), `sharedUris`; returns configurable `deleteResult` / `renameOutcome`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_file_ops.dart';
import '../fakes/fakes.dart';

void main() {
  test('FakeMediaFileOps records calls and returns configured results', () async {
    final ops = FakeMediaFileOps()
      ..deleteResult = FileOpStatus.ok
      ..renameOutcome = const RenameOutcome(FileOpStatus.ok, newName: 'b.mp4');

    expect(await ops.delete('content://v/1'), FileOpStatus.ok);
    expect(ops.deletedUris, ['content://v/1']);

    final r = await ops.rename('content://v/1', 'b');
    expect(r.status, FileOpStatus.ok);
    expect(r.newName, 'b.mp4');
    expect(ops.renamed.single, ('content://v/1', 'b'));

    await ops.share('content://v/1');
    expect(ops.sharedUris, ['content://v/1']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/platform/fake_media_file_ops_test.dart`
Expected: FAIL — files/types not found.

- [ ] **Step 3: Create the interface**

`lib/platform/interfaces/media_file_ops.dart`:

```dart
/// Result of a file op that may require system consent (the user can cancel
/// the OS dialog).
enum FileOpStatus { ok, cancelled, error }

class RenameOutcome {
  final FileOpStatus status;
  final String? newName; // final name incl. extension when status == ok
  const RenameOutcome(this.status, {this.newName});
}

/// Operations on a device video file (MediaStore on Android).
abstract class MediaFileOps {
  /// Deletes the file. On Android 11+ the SYSTEM shows its own confirmation;
  /// returns [FileOpStatus.cancelled] if the user declines it.
  Future<FileOpStatus> delete(String uri);

  /// Renames DISPLAY_NAME, preserving the extension. [newBaseName] is the base
  /// name only (no extension). On Android 11+ the SYSTEM asks for write consent.
  Future<RenameOutcome> rename(String uri, String newBaseName);

  /// Shares the file via ACTION_SEND (fire-and-forget; the OS chooser handles
  /// the rest).
  Future<void> share(String uri);
}
```

- [ ] **Step 4: Create the provider**

`lib/platform/media_file_ops_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/media_file_ops.dart';

final mediaFileOpsProvider = Provider<MediaFileOps>((ref) {
  throw UnimplementedError('mediaFileOpsProvider must be overridden');
});
```

- [ ] **Step 5: Append `FakeMediaFileOps` to `test/fakes/fakes.dart`**

Add the import at the top if missing (`import 'package:kivo_player/platform/interfaces/media_file_ops.dart';`) and append:

```dart
class FakeMediaFileOps implements MediaFileOps {
  final List<String> deletedUris = [];
  final List<(String, String)> renamed = []; // (uri, baseName)
  final List<String> sharedUris = [];
  FileOpStatus deleteResult = FileOpStatus.ok;
  RenameOutcome renameOutcome = const RenameOutcome(FileOpStatus.ok, newName: 'renamed.mp4');

  @override
  Future<FileOpStatus> delete(String uri) async {
    deletedUris.add(uri);
    return deleteResult;
  }

  @override
  Future<RenameOutcome> rename(String uri, String newBaseName) async {
    renamed.add((uri, newBaseName));
    return renameOutcome;
  }

  @override
  Future<void> share(String uri) async => sharedUris.add(uri);
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/platform/fake_media_file_ops_test.dart`
Expected: PASS (1 test).

- [ ] **Step 7: Commit**

```bash
git add lib/platform/interfaces/media_file_ops.dart lib/platform/media_file_ops_provider.dart test/fakes/fakes.dart test/platform/fake_media_file_ops_test.dart
git commit -m "feat(library): MediaFileOps interface, provider, and fake"
```

---

### Task 4: Rename name helpers — `sanitizeRenameTarget` + `splitNameExt`

**Files:**
- Create: `lib/player/library/rename_util.dart`
- Test: `test/player/library/rename_util_test.dart`

**Interfaces:**
- Produces:
  - `String? sanitizeRenameTarget(String input)` — trims; returns null if empty or contains `/` or `\`; else the trimmed base name.
  - `({String base, String ext}) splitNameExt(String fileName)` — splits at the last dot; `ext` includes the dot (e.g. `.mp4`), or is `''` if none; a leading-dot-only name has empty ext.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/library/rename_util.dart';

void main() {
  test('sanitizeRenameTarget trims and rejects empty / path separators', () {
    expect(sanitizeRenameTarget('  Mi Video  '), 'Mi Video');
    expect(sanitizeRenameTarget(''), isNull);
    expect(sanitizeRenameTarget('   '), isNull);
    expect(sanitizeRenameTarget('a/b'), isNull);
    expect(sanitizeRenameTarget('a\\b'), isNull);
  });

  test('splitNameExt splits at the last dot', () {
    expect(splitNameExt('movie.mp4'), (base: 'movie', ext: '.mp4'));
    expect(splitNameExt('my.home.video.mkv'), (base: 'my.home.video', ext: '.mkv'));
    expect(splitNameExt('noext'), (base: 'noext', ext: ''));
    expect(splitNameExt('.hidden'), (base: '.hidden', ext: ''));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/player/library/rename_util_test.dart`
Expected: FAIL — file/functions not found.

- [ ] **Step 3: Implement**

`lib/player/library/rename_util.dart`:

```dart
/// Validates a user-entered base name (no extension). Returns the trimmed name,
/// or null if empty or containing a path separator.
String? sanitizeRenameTarget(String input) {
  final t = input.trim();
  if (t.isEmpty) return null;
  if (t.contains('/') || t.contains('\\')) return null;
  return t;
}

/// Splits a file name into base and extension. [ext] includes the leading dot
/// (e.g. '.mp4'), or is '' when there's no extension. A name that is only a
/// leading dot (e.g. '.hidden') is treated as all-base, no extension.
({String base, String ext}) splitNameExt(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0) return (base: fileName, ext: '');
  return (base: fileName.substring(0, dot), ext: fileName.substring(dot));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/player/library/rename_util_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/player/library/rename_util.dart test/player/library/rename_util_test.dart
git commit -m "feat(library): rename name helpers (sanitize + split ext)"
```

---

### Task 5: `VideoActionsController` — orchestration + side effects

**Files:**
- Create: `lib/player/library/video_actions.dart`
- Test: `test/player/library/video_actions_test.dart`

**Interfaces:**
- Consumes: `MediaFileOps`/`FileOpStatus`/`RenameOutcome` (Task 3); `ResumeService.rename`/`clear` + `PlayedStore.remove`/`markPlayed`/`isPlayed` (Task 2); `mediaFileOpsProvider`, `resumeServiceProvider`, `playedStoreProvider`, `mediaIndexProvider`, `continueWatchingProvider`, `playedKeysProvider`; `splitNameExt` is NOT needed here (the controller receives a base name).
- Produces:
  - `class VideoActionsController` with `Future<FileOpStatus> delete(VideoItem v)`, `Future<RenameOutcome> rename(VideoItem v, String newBaseName)`, `Future<void> share(VideoItem v)`.
  - `final videoActionsProvider = Provider<VideoActionsController>((ref) => VideoActionsController(ref));`

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

const _v = VideoItem(
  id: '1', uri: 'content://v/1', name: 'old.mp4', folder: 'Movies',
  durationMs: 600000, sizeBytes: 100, dateAddedMs: 0,
);

ProviderContainer _c(FakeMediaFileOps ops, ResumeService resume, PlayedStore played) =>
    ProviderContainer(overrides: [
      mediaFileOpsProvider.overrideWithValue(ops),
      resumeServiceProvider.overrideWithValue(resume),
      playedStoreProvider.overrideWithValue(played),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
      mediaPermissionProvider.overrideWith((ref) async => MediaAccess.granted),
    ]);

void main() {
  test('delete clears resume+played and returns ok', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put('old.mp4', 30, 100);
    await played.markPlayed('old.mp4');
    final ops = FakeMediaFileOps()..deleteResult = FileOpStatus.ok;
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    final status = await c.read(videoActionsProvider).delete(_v);
    expect(status, FileOpStatus.ok);
    expect(ops.deletedUris, ['content://v/1']);
    expect(resume.positionFor('old.mp4'), isNull);
    expect(played.isPlayed('old.mp4'), false);
  });

  test('cancelled delete leaves resume+played untouched', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put('old.mp4', 30, 100);
    await played.markPlayed('old.mp4');
    final ops = FakeMediaFileOps()..deleteResult = FileOpStatus.cancelled;
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    final status = await c.read(videoActionsProvider).delete(_v);
    expect(status, FileOpStatus.cancelled);
    expect(resume.positionFor('old.mp4'), const Duration(seconds: 30));
    expect(played.isPlayed('old.mp4'), true);
  });

  test('rename migrates resume+played to the new name', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put('old.mp4', 30, 100);
    await played.markPlayed('old.mp4');
    final ops = FakeMediaFileOps()
      ..renameOutcome = const RenameOutcome(FileOpStatus.ok, newName: 'new.mp4');
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    final r = await c.read(videoActionsProvider).rename(_v, 'new');
    expect(r.status, FileOpStatus.ok);
    expect(ops.renamed.single, ('content://v/1', 'new'));
    expect(resume.positionFor('old.mp4'), isNull);
    expect(resume.positionFor('new.mp4'), const Duration(seconds: 30));
    expect(played.isPlayed('old.mp4'), false);
    expect(played.isPlayed('new.mp4'), true);
  });

  test('cancelled rename does not migrate', () async {
    final store = InMemoryResumeStore();
    final resume = ResumeService(store);
    final played = InMemoryPlayedStore();
    await store.put('old.mp4', 30, 100);
    final ops = FakeMediaFileOps()
      ..renameOutcome = const RenameOutcome(FileOpStatus.cancelled);
    final c = _c(ops, resume, played);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).rename(_v, 'new');
    expect(resume.positionFor('old.mp4'), const Duration(seconds: 30));
    expect(resume.positionFor('new.mp4'), isNull);
  });

  test('share passes the uri through', () async {
    final ops = FakeMediaFileOps();
    final c = _c(ops, ResumeService(InMemoryResumeStore()), InMemoryPlayedStore());
    addTearDown(c.dispose);
    await c.read(videoActionsProvider).share(_v);
    expect(ops.sharedUris, ['content://v/1']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/player/library/video_actions_test.dart`
Expected: FAIL — `video_actions.dart` / `videoActionsProvider` not found.

- [ ] **Step 3: Implement the controller**

`lib/player/library/video_actions.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/interfaces/media_file_ops.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../platform/media_file_ops_provider.dart';
import '../open/video_source.dart'; // resumeServiceProvider
import 'continue_watching.dart';
import 'media_index.dart';
import 'played.dart';

/// Orchestrates a library video's file operations and their side effects:
/// refreshing the media index, and keeping the resume + played stores (keyed by
/// file name) consistent — migrating them on rename, clearing them on delete.
class VideoActionsController {
  final Ref _ref;
  VideoActionsController(this._ref);

  Future<void> share(VideoItem v) =>
      _ref.read(mediaFileOpsProvider).share(v.uri);

  Future<FileOpStatus> delete(VideoItem v) async {
    final status = await _ref.read(mediaFileOpsProvider).delete(v.uri);
    if (status != FileOpStatus.ok) return status;
    await _ref.read(resumeServiceProvider).clear(v.name);
    await _ref.read(playedStoreProvider).remove(v.name);
    await _refreshLibrary();
    return status;
  }

  Future<RenameOutcome> rename(VideoItem v, String newBaseName) async {
    final outcome = await _ref.read(mediaFileOpsProvider).rename(v.uri, newBaseName);
    if (outcome.status != FileOpStatus.ok || outcome.newName == null) return outcome;
    final newName = outcome.newName!;
    await _ref.read(resumeServiceProvider).rename(v.name, newName);
    final played = _ref.read(playedStoreProvider);
    if (played.isPlayed(v.name)) {
      await played.markPlayed(newName);
      await played.remove(v.name);
    }
    await _refreshLibrary();
    return outcome;
  }

  Future<void> _refreshLibrary() async {
    await _ref.read(mediaIndexProvider.notifier).refresh();
    _ref.invalidate(continueWatchingProvider);
    _ref.invalidate(playedKeysProvider);
  }
}

final videoActionsProvider =
    Provider<VideoActionsController>((ref) => VideoActionsController(ref));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/player/library/video_actions_test.dart`
Expected: PASS (5 tests). (`FakeMediaIndexer.scan` returns its canned list; `refresh()` just re-scans — the migration assertions read the stores directly, independent of the index.)

- [ ] **Step 5: Commit**

```bash
git add lib/player/library/video_actions.dart test/player/library/video_actions_test.dart
git commit -m "feat(library): VideoActionsController orchestrates delete/rename/share side effects"
```

---

### Task 6: `AndroidMediaFileOps` + Kotlin native (delete/rename/share + onActivityResult)

**Files:**
- Create: `lib/platform/android/android_media_file_ops.dart`
- Modify: `lib/main.dart` (override `mediaFileOpsProvider`)
- Modify: `android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt`

**Interfaces:**
- Consumes: `MediaFileOps`/`FileOpStatus`/`RenameOutcome`, `mediaFileOpsProvider`.
- Produces: `AndroidMediaFileOps` (channel `kivo/media`, methods `delete`/`rename`/`share`).

**Context:** This is the native task — not unit-tested; verified by `flutter analyze`, a release build, and the device checklist (Task 9). The channel replies use the same `runOnUiThread { result.success(...) }` style as the existing `scan`/`thumbnail` handlers. `delete`/`rename` need system consent on API 30+, whose result returns via `onActivityResult`.

- [ ] **Step 1: Implement the Dart channel wrapper**

`lib/platform/android/android_media_file_ops.dart`:

```dart
import 'package:flutter/services.dart';
import '../interfaces/media_file_ops.dart';

class AndroidMediaFileOps implements MediaFileOps {
  static const MethodChannel _channel = MethodChannel('kivo/media');

  FileOpStatus _status(String? s) => switch (s) {
        'ok' => FileOpStatus.ok,
        'cancelled' => FileOpStatus.cancelled,
        _ => FileOpStatus.error,
      };

  @override
  Future<FileOpStatus> delete(String uri) async {
    try {
      final s = await _channel.invokeMethod<String>('delete', {'uri': uri});
      return _status(s);
    } catch (_) {
      return FileOpStatus.error;
    }
  }

  @override
  Future<RenameOutcome> rename(String uri, String newBaseName) async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>(
          'rename', {'uri': uri, 'name': newBaseName});
      final status = _status(m?['status'] as String?);
      return RenameOutcome(status, newName: m?['newName'] as String?);
    } catch (_) {
      return const RenameOutcome(FileOpStatus.error);
    }
  }

  @override
  Future<void> share(String uri) async {
    try {
      await _channel.invokeMethod<void>('share', {'uri': uri});
    } catch (_) {/* fire-and-forget */}
  }
}
```

- [ ] **Step 2: Override the provider in `main.dart`**

In `lib/main.dart`, add the import and the override alongside the other platform overrides (next to `mediaIndexerProvider.overrideWithValue(...)`):

```dart
      mediaFileOpsProvider.overrideWithValue(AndroidMediaFileOps()),
```
(Import: `import 'platform/android/android_media_file_ops.dart';` and `import 'platform/media_file_ops_provider.dart';` if not already pulled in.)

- [ ] **Step 3: Add Kotlin fields + companion request codes**

In `MainActivity.kt`, add fields to the class and request codes to the `companion object`:

```kotlin
    // --- kivo/media file ops (delete/rename consent) ---
    private var pendingFileOpResult: MethodChannel.Result? = null
    private var pendingRenameUri: android.net.Uri? = null
    private var pendingRenameFinalName: String? = null
```
```kotlin
    companion object {
        private const val PIP_ACTION = "dev.selector.kivo_player.PIP_ACTION"
        private const val PIP_EXTRA = "action"
        private const val REQ_DELETE = 4011
        private const val REQ_RENAME = 4012
    }
```

- [ ] **Step 4: Add the `delete`/`rename`/`share` branches to the `kivo/media` handler**

In the `"kivo/media"` `setMethodCallHandler` `when (call.method)`, before `else -> result.notImplemented()`, add:

```kotlin
                    "share" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) { result.error("INVALID_ARG", "uri required", null); return@setMethodCallHandler }
                        try {
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "video/*"
                                putExtra(Intent.EXTRA_STREAM, Uri.parse(uri))
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(send, null))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.message, null)
                        }
                    }
                    "delete" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) { result.error("INVALID_ARG", "uri required", null); return@setMethodCallHandler }
                        if (pendingFileOpResult != null) { result.success("error"); return@setMethodCallHandler }
                        val u = Uri.parse(uri)
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val pi = MediaStore.createDeleteRequest(contentResolver, listOf(u))
                                pendingFileOpResult = result
                                startIntentSenderForResult(pi.intentSender, REQ_DELETE, null, 0, 0, 0)
                            } else {
                                try {
                                    contentResolver.delete(u, null, null)
                                    result.success("ok")
                                } catch (e: RecoverableSecurityException) {
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                        pendingFileOpResult = result
                                        startIntentSenderForResult(
                                            e.userAction.actionIntent.intentSender, REQ_DELETE, null, 0, 0, 0)
                                    } else {
                                        result.success("error")
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            pendingFileOpResult = null
                            result.success("error")
                        }
                    }
                    "rename" -> {
                        val uri = call.argument<String>("uri")
                        val base = call.argument<String>("name")
                        if (uri == null || base == null) { result.error("INVALID_ARG", "uri+name required", null); return@setMethodCallHandler }
                        if (pendingFileOpResult != null) { result.success(mapOf("status" to "error")); return@setMethodCallHandler }
                        val u = Uri.parse(uri)
                        // Preserve the current extension.
                        val currentName = queryDisplayName(u) ?: ""
                        val dot = currentName.lastIndexOf('.')
                        val ext = if (dot > 0) currentName.substring(dot) else ""
                        val finalName = base + ext
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val pi = MediaStore.createWriteRequest(contentResolver, listOf(u))
                                pendingFileOpResult = result
                                pendingRenameUri = u
                                pendingRenameFinalName = finalName
                                startIntentSenderForResult(pi.intentSender, REQ_RENAME, null, 0, 0, 0)
                            } else {
                                val values = android.content.ContentValues().apply {
                                    put(MediaStore.Video.Media.DISPLAY_NAME, finalName)
                                }
                                contentResolver.update(u, values, null, null)
                                result.success(mapOf("status" to "ok", "newName" to finalName))
                            }
                        } catch (e: Exception) {
                            pendingFileOpResult = null
                            pendingRenameUri = null
                            pendingRenameFinalName = null
                            result.success(mapOf("status" to "error"))
                        }
                    }
```

- [ ] **Step 5: Add the `queryDisplayName` helper + `onActivityResult`**

Add these as methods on `MainActivity` (outside `configureFlutterEngine`):

```kotlin
    private fun queryDisplayName(uri: android.net.Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(MediaStore.Video.Media.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
        } catch (_: Exception) { null }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQ_DELETE -> {
                val r = pendingFileOpResult
                pendingFileOpResult = null
                r?.success(if (resultCode == RESULT_OK) "ok" else "cancelled")
            }
            REQ_RENAME -> {
                val r = pendingFileOpResult
                val u = pendingRenameUri
                val finalName = pendingRenameFinalName
                pendingFileOpResult = null
                pendingRenameUri = null
                pendingRenameFinalName = null
                if (resultCode != RESULT_OK || u == null || finalName == null) {
                    r?.success(mapOf("status" to "cancelled"))
                    return
                }
                try {
                    val values = android.content.ContentValues().apply {
                        put(MediaStore.Video.Media.DISPLAY_NAME, finalName)
                    }
                    contentResolver.update(u, values, null, null)
                    r?.success(mapOf("status" to "ok", "newName" to finalName))
                } catch (e: Exception) {
                    r?.success(mapOf("status" to "error"))
                }
            }
        }
    }
```

Add the import at the top of `MainActivity.kt`: `import android.app.RecoverableSecurityException`.

- [ ] **Step 6: Analyze + release build (compiles the Kotlin)**

Run: `flutter analyze lib/platform/android/android_media_file_ops.dart lib/main.dart`
Expected: No issues.
Run: `flutter build apk --release`
Expected: `Built build\app\outputs\flutter-apk\app-release.apk` (this compiles the Kotlin; a Kotlin error fails here).

- [ ] **Step 7: Commit**

```bash
git add lib/platform/android/android_media_file_ops.dart lib/main.dart android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt
git commit -m "feat(library): AndroidMediaFileOps + native delete/rename/share with consent"
```

---

### Task 7: `VideoOptionsSheet` + wire the ⋮ button

**Files:**
- Create: `lib/ui/home/widgets/video_options_sheet.dart`
- Modify: `lib/ui/home/widgets/video_density_feed.dart` (both `onOptions:` call sites, ~lines 197 and 226)
- Test: `test/ui/home/video_options_sheet_test.dart`

**Interfaces:**
- Consumes: `VideoItem`.
- Produces: `Future<void> showVideoOptions(BuildContext context, WidgetRef ref, VideoItem v)` — opens the bottom sheet; each row invokes a handler (wired in Task 8). For THIS task the row handlers call named top-level callbacks that Task 8 fills in; to keep this task self-contained and testable, the sheet takes explicit callbacks:
  - `VideoOptionsSheet({required VideoItem video, required VoidCallback onShare, required VoidCallback onRename, required VoidCallback onDetails, required VoidCallback onDelete})`.
  - `showVideoOptions` builds it with callbacks that (for now) just `Navigator.pop` then call `ref.read(videoActionsProvider)` for share, and no-op stubs for rename/details/delete that Task 8 replaces. To avoid a throwaway, `showVideoOptions` in THIS task wires **share** fully (calls `videoActionsProvider.share`) and leaves rename/details/delete calling small stub functions `_todoRename/_todoDetails/_todoDelete` that Task 8 replaces with real dialogs.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/widgets/video_options_sheet.dart';

const _v = VideoItem(
  id: '1', uri: 'content://v/1', name: 'clip.mp4', folder: 'Movies',
  durationMs: 1000, sizeBytes: 10, dateAddedMs: 0,
);

void main() {
  testWidgets('VideoOptionsSheet shows four actions and fires callbacks', (tester) async {
    final fired = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VideoOptionsSheet(
          video: _v,
          onShare: () => fired.add('share'),
          onRename: () => fired.add('rename'),
          onDetails: () => fired.add('details'),
          onDelete: () => fired.add('delete'),
        ),
      ),
    ));

    expect(find.text('clip.mp4'), findsOneWidget);
    for (final label in ['Compartir', 'Renombrar', 'Detalles', 'Borrar']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('Compartir'));
    await tester.tap(find.text('Borrar'));
    expect(fired, ['share', 'delete']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/home/video_options_sheet_test.dart`
Expected: FAIL — file/widget not found.

- [ ] **Step 3: Implement `VideoOptionsSheet`**

`lib/ui/home/widgets/video_options_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/video_actions.dart';

/// Bottom-sheet menu for a library video's ⋮ button. Rows are theme-aware.
class VideoOptionsSheet extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onShare;
  final VoidCallback onRename;
  final VoidCallback onDetails;
  final VoidCallback onDelete;
  const VideoOptionsSheet({
    super.key,
    required this.video,
    required this.onShare,
    required this.onRename,
    required this.onDetails,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(video.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          _row(context, Icons.share_outlined, 'Compartir', cs.onSurface, onShare),
          _row(context, Icons.drive_file_rename_outline, 'Renombrar', cs.onSurface, onRename),
          _row(context, Icons.info_outline, 'Detalles', cs.onSurface, onDetails),
          _row(context, Icons.delete_outline, 'Borrar', cs.error, onDelete),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 16),
          Text(label, style: TextStyle(color: color, fontSize: 15)),
        ]),
      ),
    );
  }
}

/// Opens the options sheet. Share is wired here; rename/details/delete are
/// wired in Task 8 (this task uses temporary stubs so the sheet is usable).
Future<void> showVideoOptions(BuildContext context, WidgetRef ref, VideoItem v) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) => VideoOptionsSheet(
      video: v,
      onShare: () {
        Navigator.pop(sheetContext);
        ref.read(videoActionsProvider).share(v);
      },
      onRename: () => Navigator.pop(sheetContext),
      onDetails: () => Navigator.pop(sheetContext),
      onDelete: () => Navigator.pop(sheetContext),
    ),
  );
}
```

- [ ] **Step 4: Wire the ⋮ button in `video_density_feed.dart`**

At BOTH `VideoTile(...)` call sites (list-row ~line 197 and grid ~line 226), change `onOptions: null` to:

```dart
                                  onOptions: () => showVideoOptions(context, ref, v),
```

Add the import at the top of `video_density_feed.dart`:

```dart
import 'video_options_sheet.dart';
```

(`context` and `ref` are in scope: `_VideoDensityFeedState` is a `ConsumerState`, so `ref` is available; `context` is the builder's.)

- [ ] **Step 5: Run test + analyze**

Run: `flutter test test/ui/home/video_options_sheet_test.dart`
Expected: PASS (1 test).
Run: `flutter analyze lib/ui/home/widgets/video_options_sheet.dart lib/ui/home/widgets/video_density_feed.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/home/widgets/video_options_sheet.dart lib/ui/home/widgets/video_density_feed.dart test/ui/home/video_options_sheet_test.dart
git commit -m "feat(library): VideoOptionsSheet + wire the ⋮ button (share wired)"
```

---

### Task 8: Rename dialog, Details sheet, and Delete confirm — wired to the controller

**Files:**
- Create: `lib/ui/home/widgets/rename_dialog.dart`
- Create: `lib/ui/home/widgets/video_details_sheet.dart`
- Modify: `lib/ui/home/widgets/video_options_sheet.dart` (replace the rename/details/delete stubs)
- Test: `test/ui/home/rename_dialog_test.dart`

**Interfaces:**
- Consumes: `VideoItem`; `splitNameExt`/`sanitizeRenameTarget` (Task 4); `videoActionsProvider` (Task 5); `FileOpStatus`/`RenameOutcome` (Task 3); `fmtSize`/`fmtDuration` from `lib/core/format.dart`.
- Produces:
  - `Future<String?> showRenameDialog(BuildContext, VideoItem)` → returns the sanitized new BASE name, or null if cancelled.
  - `void showVideoDetails(BuildContext, VideoItem)`.
  - Real wiring of rename/details/delete inside `showVideoOptions`.

- [ ] **Step 1: Write the failing test (rename dialog validation)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/widgets/rename_dialog.dart';

const _v = VideoItem(
  id: '1', uri: 'content://v/1', name: 'movie.mp4', folder: 'Movies',
  durationMs: 1000, sizeBytes: 10, dateAddedMs: 0,
);

void main() {
  testWidgets('rename dialog prefills base name, shows extension, validates', (tester) async {
    String? result = 'SENTINEL';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async { result = await showRenameDialog(context, _v); },
          child: const Text('go'),
        );
      })),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Prefills the base name (no extension) and shows the extension suffix.
    expect(find.widgetWithText(TextField, 'movie'), findsOneWidget);
    expect(find.text('.mp4'), findsOneWidget);

    // Clearing the field disables Save.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    final saveBtn = tester.widget<TextButton>(
        find.ancestor(of: find.text('Guardar'), matching: find.byType(TextButton)));
    expect(saveBtn.onPressed, isNull);

    // A valid new name enables Save and returns the sanitized base.
    await tester.enterText(find.byType(TextField), '  Nueva peli  ');
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(result, 'Nueva peli');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/home/rename_dialog_test.dart`
Expected: FAIL — `rename_dialog.dart` / `showRenameDialog` not found.

- [ ] **Step 3: Implement the rename dialog**

`lib/ui/home/widgets/rename_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/rename_util.dart';

/// Prompts for a new base name (extension shown, locked). Returns the sanitized
/// base name, or null if cancelled / unchanged.
Future<String?> showRenameDialog(BuildContext context, VideoItem v) {
  final split = splitNameExt(v.name);
  final controller = TextEditingController(text: split.base);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setState) {
        final sanitized = sanitizeRenameTarget(controller.text);
        final valid = sanitized != null && sanitized != split.base;
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Renombrar'),
          content: Row(children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (split.ext.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(split.ext, style: TextStyle(color: cs.onSurfaceVariant)),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            TextButton(
              onPressed: valid ? () => Navigator.pop(ctx, sanitized) : null,
              child: const Text('Guardar'),
            ),
          ],
        );
      });
    },
  );
}
```

- [ ] **Step 4: Run the rename-dialog test**

Run: `flutter test test/ui/home/rename_dialog_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Implement the details sheet**

`lib/ui/home/widgets/video_details_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import '../../../core/format.dart';
import '../../../platform/interfaces/media_indexer.dart';

void showVideoDetails(BuildContext context, VideoItem v) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (ctx) {
      final res = (v.width > 0 && v.height > 0) ? '${v.width}×${v.height}' : '—';
      final date = v.dateAddedMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(v.dateAddedMs).toString().split('.').first
          : '—';
      final folder = v.path.isNotEmpty ? v.path : v.folder;
      final rows = <(String, String)>[
        ('Nombre', v.name),
        ('Carpeta', folder),
        ('Tamaño', fmtSize(v.sizeBytes)),
        ('Duración', fmtDuration(Duration(milliseconds: v.durationMs))),
        ('Resolución', res),
        ('Agregado', date),
        ('URI', v.uri),
      ];
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Detalles',
                  style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 92,
                      child: Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    ),
                    Expanded(
                      child: SelectableText(value, style: TextStyle(color: cs.onSurface, fontSize: 13)),
                    ),
                  ]),
                ),
            ],
          ),
        ),
      );
    },
  );
}
```

- [ ] **Step 6: Wire rename/details/delete in `showVideoOptions`**

Replace the `showVideoOptions` function in `lib/ui/home/widgets/video_options_sheet.dart` with the fully-wired version, and add imports:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/interfaces/media_file_ops.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/video_actions.dart';
import 'rename_dialog.dart';
import 'video_details_sheet.dart';
```

```dart
Future<void> showVideoOptions(BuildContext context, WidgetRef ref, VideoItem v) {
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) => VideoOptionsSheet(
      video: v,
      onShare: () {
        Navigator.pop(sheetContext);
        ref.read(videoActionsProvider).share(v);
      },
      onDetails: () {
        Navigator.pop(sheetContext);
        showVideoDetails(context, v);
      },
      onRename: () async {
        Navigator.pop(sheetContext);
        final base = await showRenameDialog(context, v);
        if (base == null) return;
        final r = await ref.read(videoActionsProvider).rename(v, base);
        if (r.status == FileOpStatus.error) {
          messenger.showSnackBar(const SnackBar(content: Text('No se pudo renombrar')));
        }
      },
      onDelete: () async {
        Navigator.pop(sheetContext);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Borrar video'),
            content: Text('¿Borrar «${v.name}»? Esta acción no se puede deshacer.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Borrar', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        final status = await ref.read(videoActionsProvider).delete(v);
        if (status == FileOpStatus.ok) {
          messenger.showSnackBar(const SnackBar(content: Text('Video borrado')));
        } else if (status == FileOpStatus.error) {
          messenger.showSnackBar(const SnackBar(content: Text('No se pudo borrar')));
        }
      },
    ),
  );
}
```

- [ ] **Step 7: Run the touched tests + analyze + full suite**

Run: `flutter test test/ui/home/rename_dialog_test.dart test/ui/home/video_options_sheet_test.dart`
Expected: PASS.
Run: `flutter analyze lib/ui/home/widgets/rename_dialog.dart lib/ui/home/widgets/video_details_sheet.dart lib/ui/home/widgets/video_options_sheet.dart`
Expected: No issues.
Run: `flutter test`
Expected: All green.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/home/widgets/rename_dialog.dart lib/ui/home/widgets/video_details_sheet.dart lib/ui/home/widgets/video_options_sheet.dart test/ui/home/rename_dialog_test.dart
git commit -m "feat(library): rename dialog, details sheet, delete confirm wired to controller"
```

---

### Task 9: Build, install, and device verification

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

  - Tap ⋮ on a library video → sheet opens with the video name and Compartir · Renombrar · Detalles · Borrar (Borrar in red).
  - **Compartir** → OS chooser appears with the video.
  - **Detalles** → shows resolution (e.g. 1920×1080), size, duration, folder/path, date, URI.
  - **Renombrar** → dialog prefilled with base name + locked extension → change it → OS write-consent dialog → name updates in the list; the video keeps its "continue watching" position and does NOT reappear as "Nuevo".
  - **Borrar** → own confirm dialog → OS delete dialog → video disappears from the list; its "continue watching" entry is gone.
  - Cancel the OS consent dialog (rename or delete) → nothing changes, no error toast.
  - Rename/delete from BOTH the grid tile (⋮) and the list-row tile (⋮).

This task has no commit (verification only). Report results; a failed item becomes a fix task.

---

## Self-Review notes

- **Spec coverage:** §1 MediaFileOps→Task 3; §2 native→Task 6; §3 details fields→Task 1; §4 controller+sanitize→Tasks 4-5; §5.1 wire→Task 7; §5.2 sheet→Task 7; §5.3 rename dialog→Task 8; §5.4 details→Task 8; §5.5 delete confirm→Task 8; store additions (PlayedStore.remove, ResumeService.rename)→Task 2; testing→each task + Task 9.
- **Type consistency:** `FileOpStatus{ok,cancelled,error}`, `RenameOutcome(status,{newName})`, `MediaFileOps.delete/rename/share`, `VideoActionsController.delete/rename/share`, `videoActionsProvider`, `sanitizeRenameTarget`, `splitNameExt(({base,ext}))`, `PlayedStore.remove`, `ResumeService.rename`, `showVideoOptions/showRenameDialog/showVideoDetails` — consistent across tasks.
- **Task 7→8 handoff:** Task 7 wires Share fully and stubs rename/details/delete (each just pops); Task 8 replaces `showVideoOptions` wholesale with the fully-wired version. No throwaway logic beyond the one-line stubs.
- **Native task (6)** has no unit test by nature; it's gated by `flutter analyze` + release build (Kotlin compile) + the Task 9 device checklist.
