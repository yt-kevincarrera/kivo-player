# Hito 2 / 2a — Media Index Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scan the device's videos via MediaStore behind a `MediaIndexer` interface, expose an index + folder grouping + folder-queue derivation, gate it on a media permission, and surface a basic functional video list that opens the player with the real folder queue (fixing Hito 1's single-item queue).

**Architecture:** Own MediaStore `MethodChannel('kivo/media')` behind a `MediaIndexer` interface (like `FrameExtractor`); `permission_handler` behind a `MediaPermission` interface. Pure Dart query helpers; Riverpod `AsyncNotifier`s for index + permission. `VideoSession` generalized to carry a playback path/URI + a stable display-name resume key.

**Tech Stack:** Flutter, Riverpod, Android MediaStore (Kotlin), `permission_handler`.

## Global Constraints

- Discovery via MediaStore own channel (NOT photo_manager / not raw filesystem). Permission via `permission_handler`. No other new deps.
- `VideoItem` fields: `id, uri (content://), name, folder, durationMs, sizeBytes, dateAddedMs`. Resume key = the video's display `name` (stable across content URIs and file-picker cache copies).
- Folder order is natural sort by `name` (reuse the existing `naturalCompare`).
- Lifecycle services cached in `initState`, never `ref.read` in `dispose` (known prior bug). Dispose controllers; marshal native `result.success` via `runOnUiThread`; query off the platform thread.
- `flutter analyze` clean; `flutter test` green (currently 80). Pure logic + providers unit-tested with fakes; the MediaStore query + runtime permission are device-verified.
- Android-first; iOS fills the interfaces later. minSdk 21 (handle `BUCKET_DISPLAY_NAME` availability with a DATA-parent fallback).

---

### Task 1: `MediaIndexer` interface + `VideoItem` + pure query helpers

**Files:**
- Create: `lib/platform/interfaces/media_indexer.dart`
- Create: `lib/player/library/library_query.dart`
- Modify: `test/fakes/fakes.dart` (append `FakeMediaIndexer`)
- Test: `test/player/library/library_query_test.dart`

**Interfaces:**
- Produces: `VideoItem` (fields above); `MediaIndexer.scan() -> Future<List<VideoItem>>`; `groupByFolder(List<VideoItem>) -> Map<String,List<VideoItem>>`; `folderQueueFor(List<VideoItem> all, VideoItem current) -> List<VideoItem>`.
- Consumes: the existing `naturalCompare` (find it: `grep -rn "naturalCompare" lib` — it's from the Hito 1 folder-queue work).

- [ ] **Step 1: Create `media_indexer.dart`**

```dart
class VideoItem {
  final String id;
  final String uri;
  final String name;
  final String folder;
  final int durationMs;
  final int sizeBytes;
  final int dateAddedMs;
  const VideoItem({
    required this.id,
    required this.uri,
    required this.name,
    required this.folder,
    required this.durationMs,
    required this.sizeBytes,
    required this.dateAddedMs,
  });
}

/// Discovers the device's videos. Android: MediaStore. iOS: later.
abstract class MediaIndexer {
  Future<List<VideoItem>> scan();
}
```

- [ ] **Step 2: Append `FakeMediaIndexer` to `test/fakes/fakes.dart`**

```dart
class FakeMediaIndexer implements MediaIndexer {
  List<VideoItem> items;
  int scans = 0;
  FakeMediaIndexer([this.items = const []]);
  @override
  Future<List<VideoItem>> scan() async {
    scans++;
    return items;
  }
}
```
Add `import 'package:kivo_player/platform/interfaces/media_indexer.dart';` to `fakes.dart` if absent.

- [ ] **Step 3: Write failing tests** — `test/player/library/library_query_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/library/library_query.dart';

VideoItem v(String name, String folder) => VideoItem(
    id: name, uri: 'content://$folder/$name', name: name, folder: folder,
    durationMs: 1000, sizeBytes: 1, dateAddedMs: 0);

void main() {
  test('groupByFolder groups and natural-sorts by name', () {
    final items = [v('clip2.mp4', 'A'), v('clip10.mp4', 'A'), v('z.mp4', 'B'), v('clip1.mp4', 'A')];
    final g = groupByFolder(items);
    expect(g.keys.toSet(), {'A', 'B'});
    expect(g['A']!.map((e) => e.name).toList(), ['clip1.mp4', 'clip2.mp4', 'clip10.mp4']);
    expect(g['B']!.map((e) => e.name).toList(), ['z.mp4']);
  });

  test('folderQueueFor returns same-folder siblings in natural order', () {
    final items = [v('b.mp4', 'A'), v('a.mp4', 'A'), v('x.mp4', 'B')];
    final q = folderQueueFor(items, items[0]); // b.mp4 in folder A
    expect(q.map((e) => e.name).toList(), ['a.mp4', 'b.mp4']);
  });
}
```

- [ ] **Step 4: Run — verify fail** (`flutter test test/player/library/library_query_test.dart` → undefined).

- [ ] **Step 5: Implement `library_query.dart`**

```dart
import '../../platform/interfaces/media_indexer.dart';
// Reuse the existing naturalCompare — adjust this import to its real location
// (find with: grep -rn "int naturalCompare" lib).
import '../queue/folder_queue_scanner.dart';

Map<String, List<VideoItem>> groupByFolder(List<VideoItem> items) {
  final map = <String, List<VideoItem>>{};
  for (final v in items) {
    (map[v.folder] ??= <VideoItem>[]).add(v);
  }
  for (final list in map.values) {
    list.sort((a, b) => naturalCompare(a.name, b.name));
  }
  return map;
}

List<VideoItem> folderQueueFor(List<VideoItem> all, VideoItem current) {
  final siblings = all.where((v) => v.folder == current.folder).toList()
    ..sort((a, b) => naturalCompare(a.name, b.name));
  return siblings;
}
```
NOTE: if `naturalCompare` is not exported from `folder_queue_scanner.dart`, import it from wherever it lives, or if it is private there, lift it to a shared `lib/core/natural_sort.dart` and re-import in both places (small, in-scope refactor).

- [ ] **Step 6: Run — verify pass; analyze; commit**

`flutter test test/player/library/library_query_test.dart` → PASS. `flutter analyze` clean. Commit: `feat: MediaIndexer interface + VideoItem + folder query helpers`.

---

### Task 2: Generalize `VideoSession` (playback path + display-name resume key)

**Files:**
- Modify: `lib/player/open/video_source.dart`
- Modify: `lib/ui/player/player_screen.dart`
- Modify: `test/ui/open_flow_test.dart`, `test/player/open/video_session_resume_key_test.dart`

**Interfaces:**
- Produces: `VideoSession {String playbackPath; String displayName; List<String> queue; int index; String get resumeKey => displayName}`; `CurrentVideoNotifier.openPath(String path)` (file-picker, single-item) and `CurrentVideoNotifier.openInFolder(VideoItem current, List<VideoItem> all)` (library).
- Consumes: `folderQueueFor` (Task 1), existing `basenameOf`.

- [ ] **Step 1: Rewrite `VideoSession` + notifier** (`video_source.dart`)

Replace the `VideoSession` class and `CurrentVideoNotifier`:
```dart
import '../../core/format.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../library/library_query.dart';
// ... keep existing riverpod import + resumeServiceProvider/queueScanner if still referenced ...

class VideoSession {
  final String playbackPath; // file path or content:// uri opened by media_kit
  final String displayName;  // file name — the stable resume key
  final List<String> queue;  // folder playbackPaths, natural order
  final int index;
  const VideoSession({
    required this.playbackPath,
    required this.displayName,
    required this.queue,
    required this.index,
  });
  String get resumeKey => displayName;
}

class CurrentVideoNotifier extends Notifier<VideoSession?> {
  @override
  VideoSession? build() => null;

  /// File-picker open: single-item queue (the picker gives a cache copy, no folder).
  void openPath(String path) {
    final name = basenameOf(path);
    state = VideoSession(
        playbackPath: path, displayName: name, queue: [path], index: 0);
  }

  /// Library open: queue = the current video's folder, natural order.
  void openInFolder(VideoItem current, List<VideoItem> all) {
    final folder = folderQueueFor(all, current);
    final idx = folder.indexWhere((v) => v.uri == current.uri);
    state = VideoSession(
      playbackPath: current.uri,
      displayName: current.name,
      queue: folder.map((v) => v.uri).toList(),
      index: idx < 0 ? 0 : idx,
    );
  }
}
```
(Remove the old `open(VideoSession)`/`openPath` body that used `queueScannerProvider` sibling scanning; the file-picker queue is now single-item. If `queueScannerProvider`/`FolderQueueScanner` becomes unused, leave the file in place but it's fine if unreferenced — do NOT delete other code.)

- [ ] **Step 2: Update `player_screen.dart`** — open the playback path, key resume by displayName.

In `_start`: `_resumeKey = session.resumeKey;` stays (now = displayName). Change `await engine.open(session.path, startAt: plan.startAt);` → `await engine.open(session.playbackPath, startAt: plan.startAt);` and `_frames.prepare(session.path);` → `_frames.prepare(session.playbackPath);`. No other logic changes.

- [ ] **Step 3: Update the two tests**

`test/player/open/video_session_resume_key_test.dart` — rewrite to the new model:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/player/open/video_source.dart';

void main() {
  test('openPath: file-picker session keys resume by basename', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier)
        .openPath('/data/.../cache/file_picker/1782833069003/clip.mp4');
    final s = c.read(currentVideoProvider)!;
    expect(s.displayName, 'clip.mp4');
    expect(s.resumeKey, 'clip.mp4');
    expect(s.queue, ['/data/.../cache/file_picker/1782833069003/clip.mp4']);
    expect(s.index, 0);
  });
}
```
`test/ui/open_flow_test.dart` — update the `VideoSession(...)` construction to the new fields: `VideoSession(playbackPath: '/movies/ep1.mkv', displayName: 'ep1.mkv', queue: ['/movies/ep1.mkv'], index: 0)`. The resume store still keys `'ep1.mkv'`; the assertion `engine.openedPath == '/movies/ep1.mkv'` still holds (now from `playbackPath`).

- [ ] **Step 4: Analyze + test + commit**

`flutter analyze` clean; `flutter test` green (existing suite + updated tests). Commit: `feat: generalize VideoSession (playback path + display-name resume key); folder open`.

---

### Task 3: Android MediaStore channel (`AndroidMediaIndexer`)

**Files:**
- Create: `lib/platform/android/android_media_indexer.dart`
- Create: `lib/platform/media_indexer_provider.dart`
- Modify: `android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt`
- Modify: `lib/main.dart` (override `mediaIndexerProvider`)

**Interfaces:**
- Consumes: `MediaIndexer`/`VideoItem` (Task 1).
- Produces: `AndroidMediaIndexer`; `mediaIndexerProvider` (`Provider<MediaIndexer>`, overridden in main).

No Dart unit test (native boundary — device-verified). Verify Kotlin compiles via the device build.

- [ ] **Step 1: Create `media_indexer_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/media_indexer.dart';

final mediaIndexerProvider = Provider<MediaIndexer>((ref) {
  throw UnimplementedError('mediaIndexerProvider must be overridden');
});
```

- [ ] **Step 2: Create `android_media_indexer.dart`**

```dart
import 'package:flutter/services.dart';
import '../interfaces/media_indexer.dart';

class AndroidMediaIndexer implements MediaIndexer {
  static const MethodChannel _channel = MethodChannel('kivo/media');

  @override
  Future<List<VideoItem>> scan() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('scan') ?? const [];
    return raw.map((e) {
      final m = (e as Map).cast<String, dynamic>();
      return VideoItem(
        id: m['id'] as String,
        uri: m['uri'] as String,
        name: (m['name'] as String?) ?? '',
        folder: (m['folder'] as String?) ?? '',
        durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
        dateAddedMs: (m['dateAddedMs'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }
}
```

- [ ] **Step 3: Kotlin channel in `MainActivity.kt`**

Imports to add: `import android.content.ContentUris`, `import android.provider.MediaStore`, `import java.io.File`. Add a field `private val ioExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()` (or reuse a background executor; shut it down in `onDestroy`). Register inside `configureFlutterEngine` (alongside `kivo/orientation` and `kivo/frames`):
```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kivo/media")
    .setMethodCallHandler { call, result ->
        if (call.method == "scan") {
            ioExecutor.execute {
                val out = ArrayList<HashMap<String, Any>>()
                try {
                    val col = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                    val proj = arrayOf(
                        MediaStore.Video.Media._ID,
                        MediaStore.Video.Media.DISPLAY_NAME,
                        MediaStore.Video.Media.BUCKET_DISPLAY_NAME,
                        MediaStore.Video.Media.DURATION,
                        MediaStore.Video.Media.SIZE,
                        MediaStore.Video.Media.DATE_ADDED,
                        MediaStore.Video.Media.DATA,
                    )
                    contentResolver.query(col, proj, null, null,
                        "${MediaStore.Video.Media.DATE_ADDED} DESC")?.use { c ->
                        val idC = c.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                        val nameC = c.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                        val bucketC = c.getColumnIndex(MediaStore.Video.Media.BUCKET_DISPLAY_NAME)
                        val durC = c.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                        val sizeC = c.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
                        val dateC = c.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
                        val dataC = c.getColumnIndex(MediaStore.Video.Media.DATA)
                        while (c.moveToNext()) {
                            val id = c.getLong(idC)
                            val uri = ContentUris.withAppendedId(col, id).toString()
                            var folder = if (bucketC >= 0) c.getString(bucketC) else null
                            if (folder.isNullOrEmpty() && dataC >= 0) {
                                folder = c.getString(dataC)?.let { File(it).parentFile?.name }
                            }
                            out.add(hashMapOf(
                                "id" to id.toString(),
                                "uri" to uri,
                                "name" to (c.getString(nameC) ?: ""),
                                "folder" to (folder ?: ""),
                                "durationMs" to c.getLong(durC),
                                "sizeBytes" to c.getLong(sizeC),
                                "dateAddedMs" to c.getLong(dateC) * 1000L, // DATE_ADDED is seconds
                            ))
                        }
                    }
                    runOnUiThread { result.success(out) }
                } catch (e: Exception) {
                    runOnUiThread { result.error("SCAN_FAILED", e.message, null) }
                }
            }
        } else {
            result.notImplemented()
        }
    }
```
Leave the `kivo/orientation` and `kivo/frames` channels untouched. In `onDestroy`, also `ioExecutor.shutdown()`.

- [ ] **Step 4: Override in `main.dart`**

Add imports `platform/android/android_media_indexer.dart` + `platform/media_indexer_provider.dart`; add to the `overrides` list: `mediaIndexerProvider.overrideWithValue(AndroidMediaIndexer()),`.

- [ ] **Step 5: Analyze + test + commit**

`flutter analyze` clean; `flutter test` still green (no Dart tests added; Kotlin compiles only on device build). Commit: `feat: AndroidMediaIndexer via MediaStore (kivo/media channel)`.

---

### Task 4: Media permission (`MediaPermission` + permission_handler)

**Files:**
- Modify: `pubspec.yaml` (add `permission_handler`)
- Create: `lib/platform/interfaces/media_permission.dart`
- Create: `lib/platform/android/permission_handler_media_permission.dart`
- Create: `lib/player/library/media_permission.dart` (provider)
- Modify: `lib/main.dart` (override), `android/app/src/main/AndroidManifest.xml` (verify perms)
- Test: `test/player/library/media_permission_test.dart`

**Interfaces:**
- Produces: `enum MediaAccess { granted, denied, limited }`; `MediaPermission.status()`/`request() -> Future<MediaAccess>`; `mediaPermissionProvider` (`AsyncNotifierProvider<MediaPermissionNotifier, MediaAccess>`) with `request()`.

- [ ] **Step 1: Add dependency**

In `pubspec.yaml` dependencies add `permission_handler: ^11.3.1` (pin a version compatible with the toolchain; if resolution fails, use the latest that resolves and note it). Run `flutter pub get`.

- [ ] **Step 2: Interface** — `media_permission.dart`

```dart
enum MediaAccess { granted, denied, limited }

abstract class MediaPermission {
  Future<MediaAccess> status();
  Future<MediaAccess> request();
}
```

- [ ] **Step 3: Impl** — `permission_handler_media_permission.dart`

```dart
import 'package:permission_handler/permission_handler.dart';
import '../interfaces/media_permission.dart';

class PermissionHandlerMediaPermission implements MediaPermission {
  // Request both; permission_handler ignores the one not applicable to the OS
  // version (videos = Android 13+ READ_MEDIA_VIDEO; storage = ≤12).
  MediaAccess _combine(PermissionStatus videos, PermissionStatus storage) {
    if (videos.isGranted || storage.isGranted) return MediaAccess.granted;
    if (videos.isLimited) return MediaAccess.limited; // Android 14 partial access
    return MediaAccess.denied;
  }

  @override
  Future<MediaAccess> status() async =>
      _combine(await Permission.videos.status, await Permission.storage.status);

  @override
  Future<MediaAccess> request() async {
    final res = await [Permission.videos, Permission.storage].request();
    return _combine(
      res[Permission.videos] ?? PermissionStatus.denied,
      res[Permission.storage] ?? PermissionStatus.denied,
    );
  }
}
```

- [ ] **Step 4: Provider** — `media_permission.dart` (provider, separate from the interface file)

Create `lib/player/library/media_permission.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/interfaces/media_permission.dart';
import '../../platform/media_permission_provider.dart';

final mediaPermissionProvider =
    AsyncNotifierProvider<MediaPermissionNotifier, MediaAccess>(
        MediaPermissionNotifier.new);

class MediaPermissionNotifier extends AsyncNotifier<MediaAccess> {
  @override
  Future<MediaAccess> build() => ref.read(mediaPermissionImplProvider).status();

  Future<void> request() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(mediaPermissionImplProvider).request());
  }
}
```
And create `lib/platform/media_permission_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/media_permission.dart';

final mediaPermissionImplProvider = Provider<MediaPermission>((ref) {
  throw UnimplementedError('mediaPermissionImplProvider must be overridden');
});
```

- [ ] **Step 5: Override in `main.dart` + manifest**

`main.dart` overrides add: `mediaPermissionImplProvider.overrideWithValue(PermissionHandlerMediaPermission()),` (import the impl). In `AndroidManifest.xml` confirm `<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>` (present from Hito 1) and add `<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>` for Android ≤12.

- [ ] **Step 6: Test** — `test/player/library/media_permission_test.dart` (with a fake impl)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/library/media_permission.dart';

class _FakePerm implements MediaPermission {
  MediaAccess current;
  final MediaAccess afterRequest;
  _FakePerm(this.current, this.afterRequest);
  @override
  Future<MediaAccess> status() async => current;
  @override
  Future<MediaAccess> request() async => current = afterRequest;
}

void main() {
  test('provider exposes status, then request flips it', () async {
    final c = ProviderContainer(overrides: [
      mediaPermissionImplProvider
          .overrideWithValue(_FakePerm(MediaAccess.denied, MediaAccess.granted)),
    ]);
    addTearDown(c.dispose);
    expect(await c.read(mediaPermissionProvider.future), MediaAccess.denied);
    await c.read(mediaPermissionProvider.notifier).request();
    expect(c.read(mediaPermissionProvider).value, MediaAccess.granted);
  });
}
```

- [ ] **Step 7: Analyze + test + commit**

`flutter analyze` clean; `flutter test` green. Commit: `feat: media permission flow (MediaPermission + permission_handler)`.

---

### Task 5: Media index provider + functional OpenScreen list

**Files:**
- Create: `lib/player/library/media_index.dart`
- Modify: `lib/ui/home/open_screen.dart`
- Test: `test/player/library/media_index_test.dart`, `test/ui/home/open_screen_test.dart`

**Interfaces:**
- Consumes: `mediaIndexerProvider` (Task 3), `mediaPermissionProvider` (Task 4), `MediaIndexer`/`VideoItem` (Task 1), `currentVideoProvider.openInFolder` (Task 2), `fmtDuration`.
- Produces: `mediaIndexProvider` (`AsyncNotifierProvider<MediaIndexNotifier, List<VideoItem>>`) with `refresh()`.

- [ ] **Step 1: Create `media_index.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../platform/media_indexer_provider.dart';
import 'media_permission.dart';

final mediaIndexProvider =
    AsyncNotifierProvider<MediaIndexNotifier, List<VideoItem>>(
        MediaIndexNotifier.new);

class MediaIndexNotifier extends AsyncNotifier<List<VideoItem>> {
  @override
  Future<List<VideoItem>> build() async {
    final access = await ref.watch(mediaPermissionProvider.future);
    if (access == MediaAccess.denied) return const [];
    return ref.read(mediaIndexerProvider).scan();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(mediaIndexerProvider).scan());
  }
}
```

- [ ] **Step 2: Test** — `test/player/library/media_index_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import '../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  final MediaAccess a;
  _Perm(this.a);
  @override Future<MediaAccess> status() async => a;
  @override Future<MediaAccess> request() async => a;
}

void main() {
  test('granted → scans; denied → empty, no scan', () async {
    final fake = FakeMediaIndexer([
      VideoItem(id: '1', uri: 'content://1', name: 'a.mp4', folder: 'A',
          durationMs: 1000, sizeBytes: 1, dateAddedMs: 0),
    ]);
    final granted = ProviderContainer(overrides: [
      mediaPermissionImplProvider.overrideWithValue(_Perm(MediaAccess.granted)),
      mediaIndexerProvider.overrideWithValue(fake),
    ]);
    addTearDown(granted.dispose);
    expect((await granted.read(mediaIndexProvider.future)).length, 1);
    expect(fake.scans, 1);

    final denied = ProviderContainer(overrides: [
      mediaPermissionImplProvider.overrideWithValue(_Perm(MediaAccess.denied)),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer([])),
    ]);
    addTearDown(denied.dispose);
    expect(await denied.read(mediaIndexProvider.future), isEmpty);
  });
}
```

- [ ] **Step 3: Rewrite `open_screen.dart`** — permission gate + functional list

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../../core/format.dart';
import '../../core/icons/kivo_icons.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../platform/interfaces/media_permission.dart';
import '../../player/library/media_index.dart';
import '../../player/library/media_permission.dart';
import '../../player/open/video_source.dart';
import '../player/player_screen.dart';

class OpenScreen extends ConsumerStatefulWidget {
  const OpenScreen({super.key});
  @override
  ConsumerState<OpenScreen> createState() => _OpenScreenState();
}

class _OpenScreenState extends ConsumerState<OpenScreen> {
  StreamSubscription<dynamic>? _shareSub;

  @override
  void initState() {
    super.initState();
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (!mounted) return;
      if (files.isNotEmpty) _openPath(files.first.path);
    });
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty) _openPath(files.first.path);
    });
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  void _push() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const PlayerScreen()));

  void _openPath(String path) {
    if (!mounted) return;
    ref.read(currentVideoProvider.notifier).openPath(path);
    _push();
  }

  void _openItem(VideoItem item, List<VideoItem> all) {
    ref.read(currentVideoProvider.notifier).openInFolder(item, all);
    _push();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path != null) _openPath(path);
  }

  @override
  Widget build(BuildContext context) {
    final perm = ref.watch(mediaPermissionProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kivo'),
        actions: [
          IconButton(
            tooltip: 'Abrir archivo',
            icon: KivoIcon(KivoIcons.folderOpen, size: 22),
            onPressed: _pick,
          ),
        ],
      ),
      body: perm.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _AccessPrompt(onGrant: () => ref.read(mediaPermissionProvider.notifier).request()),
        data: (access) {
          if (access == MediaAccess.denied) {
            return _AccessPrompt(onGrant: () => ref.read(mediaPermissionProvider.notifier).request());
          }
          final index = ref.watch(mediaIndexProvider);
          return index.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, __) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white))),
            data: (videos) {
              if (videos.isEmpty) {
                return const Center(child: Text('No se encontraron videos', style: TextStyle(color: Colors.white70)));
              }
              return ListView.builder(
                itemCount: videos.length,
                itemBuilder: (_, i) {
                  final v = videos[i];
                  return ListTile(
                    title: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text('${v.folder} · ${fmtDuration(Duration(milliseconds: v.durationMs))}',
                        style: const TextStyle(color: Colors.white54)),
                    onTap: () => _openItem(v, videos),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _AccessPrompt extends StatelessWidget {
  final VoidCallback onGrant;
  const _AccessPrompt({required this.onGrant});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Da acceso a tus videos para verlos aquí',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            FilledButton(onPressed: onGrant, child: const Text('Dar acceso')),
          ],
        ),
      );
}
```
(Confirm `KivoIcons.folderOpen` exists — it was used by the old OpenScreen. If not, use any existing icon.)

- [ ] **Step 4: Widget test** — `test/ui/home/open_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/open_screen.dart';
import '../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override Future<MediaAccess> status() async => MediaAccess.granted;
  @override Future<MediaAccess> request() async => MediaAccess.granted;
}

void main() {
  testWidgets('granted permission lists scanned videos', (tester) async {
    final fake = FakeMediaIndexer([
      VideoItem(id: '1', uri: 'content://1', name: 'movie.mp4', folder: 'Movies',
          durationMs: 65000, sizeBytes: 1, dateAddedMs: 0),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        mediaPermissionImplProvider.overrideWithValue(_Perm()),
        mediaIndexerProvider.overrideWithValue(fake),
      ],
      child: const MaterialApp(home: OpenScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('movie.mp4'), findsOneWidget);
  });
}
```
(If `ReceiveSharingIntent` calls fail under test, the widget test may need the plugin's platform calls to no-op — they already run in initState via a `Future`; if the test throws on the missing plugin, wrap the `getInitialMedia()`/stream in a `try` or guard with a check, the minimal change to keep the test green. Prefer not to alter behavior; if needed, the existing app already handles these on device.)

- [ ] **Step 5: Analyze + test + commit**

`flutter analyze` clean; `flutter test` green. Commit: `feat: media index provider + functional video list in OpenScreen`.

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review.
3. Release build to the Pixel 6: grant the permission, see the device's videos listed, tap one → it plays and the folder queue is the real folder (not a single item); resume still works (keyed by name); the file-picker path still works as a secondary action.

(Next sub-projects: 2b library UI — folders, continue-watching, thumbnails via a `thumbnail(id)` added to `MediaIndexer`; 2c search/sort/filters. The deferred Hito-1 thumbnail queue strip becomes buildable once the real folder queue exists.)
