# Seek Frame Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show an on-demand thumbnail of the target frame in a bubble above the seek bar while the user scrubs (Hito 1 §9), without thrashing live playback.

**Architecture:** A `FrameExtractor` platform interface (Android `MediaMetadataRetriever` via `MethodChannel('kivo/frames')`) supplies frames. A pure-Dart `SeekPreviewController` buckets scrub positions to 1 s, caches frames (LRU 30), and coalesces in-flight requests. The seek bar drives the controller on `onChanged` (no live seek) and commits the seek on `onChangeEnd`. A bubble widget renders the current frame.

**Tech Stack:** Flutter, Riverpod, media_kit (unchanged), Android Kotlin (MediaMetadataRetriever).

## Global Constraints

- Android-first; iOS fills the interface later. Frame extraction is Android-only for now.
- No new pub dependency (use native `MediaMetadataRetriever`, not `media_kit screenshot()` nor a thumbnail package).
- Thumbnail target width 240 px, JPEG; `OPTION_CLOSEST_SYNC`; extraction off the platform thread.
- Bucket scrub positions to whole seconds; LRU cache capacity 30; at most one extraction in flight (coalesce to the latest pending).
- Lifecycle services are cached in `initState` and used in `dispose` — NEVER `ref.read(...)` in `dispose` (it throws "ref used after dispose" and silently drops the call; this is a known prior bug).
- `flutter analyze` clean; `flutter test` green (currently 70/70). Pure logic is unit-tested with a fake extractor; native extraction is verified on the Pixel 6.
- Accent is configurable: `Color(ref.watch(settingsProvider).accentColor)`; on-brand dark surfaces (`Colors.black` ~0.8), `fmtDuration` for timestamps.

---

### Task 1: FrameExtractor interface + SeekPreviewController (pure logic)

**Files:**
- Create: `lib/platform/interfaces/frame_extractor.dart`
- Create: `lib/platform/frame_extractor_provider.dart`
- Create: `lib/ui/player/seek/seek_preview.dart`
- Modify: `test/fakes/fakes.dart` (append `FakeFrameExtractor`)
- Test: `test/ui/player/seek/seek_preview_test.dart`

**Interfaces:**
- Produces: `FrameExtractor` (`prepare(String)`, `frameAt(Duration) -> Future<Uint8List?>`, `release()`); `frameExtractorProvider` (`Provider<FrameExtractor>`, overridden in `main`); `scrubProvider` (`StateProvider<Duration?>`); `seekPreviewFrameProvider` (`StateProvider<Uint8List?>`); `seekPreviewControllerProvider` (`Provider<SeekPreviewController>`); `SeekPreviewController.request(Duration)`.
- Consumes: nothing (pure + injected fake in tests).

- [ ] **Step 1: Create the interface** — `lib/platform/interfaces/frame_extractor.dart`

```dart
import 'dart:typed_data';

/// Extracts still frames from the current video for the seek-preview bubble.
/// Android-only for now (MediaMetadataRetriever); iOS fills this in later.
abstract class FrameExtractor {
  /// Prepare/reuse an extractor for [path]. Idempotent for the same path.
  Future<void> prepare(String path);

  /// Nearest (keyframe) frame to [position] as JPEG bytes, or null.
  Future<Uint8List?> frameAt(Duration position);

  /// Release native resources (call on close or when switching videos).
  Future<void> release();
}
```

- [ ] **Step 2: Create the provider** — `lib/platform/frame_extractor_provider.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/frame_extractor.dart';

/// Overridden in main() with the Android implementation.
final frameExtractorProvider = Provider<FrameExtractor>((ref) {
  throw UnimplementedError('frameExtractorProvider must be overridden');
});
```

- [ ] **Step 3: Append `FakeFrameExtractor` to `test/fakes/fakes.dart`**

```dart
class FakeFrameExtractor implements FrameExtractor {
  final List<Duration> requested = [];
  String? preparedPath;
  bool released = false;
  bool autoComplete = true;
  final List<Completer<Uint8List?>> _pending = [];

  @override
  Future<void> prepare(String path) async => preparedPath = path;

  @override
  Future<void> release() async => released = true;

  @override
  Future<Uint8List?> frameAt(Duration position) {
    requested.add(position);
    if (autoComplete) {
      return Future.value(Uint8List.fromList([position.inSeconds & 0xff]));
    }
    final c = Completer<Uint8List?>();
    _pending.add(c);
    return c.future;
  }

  /// Complete the oldest outstanding manual request with bytes tagged [tag].
  void completeNext(int tag) => _pending.removeAt(0).complete(Uint8List.fromList([tag & 0xff]));
}
```
Add `import 'dart:async';`, `import 'dart:typed_data';`, and `import 'package:kivo_player/platform/interfaces/frame_extractor.dart';` to `fakes.dart` if not present.

- [ ] **Step 4: Write the failing tests** — `test/ui/player/seek/seek_preview_test.dart`

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/seek/seek_preview.dart';
import '../../../fakes/fakes.dart';

void main() {
  late FakeFrameExtractor fake;
  late List<Uint8List?> shown;
  SeekPreviewController make({int capacity = 30}) {
    fake = FakeFrameExtractor();
    shown = [];
    return SeekPreviewController(
        extractor: fake, onFrame: shown.add, capacity: capacity);
  }

  test('buckets sub-second positions to the same 1s bucket (one extraction)', () async {
    final c = make();
    c.request(const Duration(milliseconds: 1200));
    await Future<void>.delayed(Duration.zero);
    c.request(const Duration(milliseconds: 1800)); // same 1s bucket -> cache hit
    await Future<void>.delayed(Duration.zero);
    expect(fake.requested.map((d) => d.inSeconds), [1]); // only one extraction
    expect(shown.last, isNotNull);
  });

  test('LRU evicts the oldest beyond capacity', () async {
    final c = make(capacity: 2);
    for (final s in [0, 1, 2]) {
      c.request(Duration(seconds: s));
      await Future<void>.delayed(Duration.zero);
    }
    fake.requested.clear();
    c.request(const Duration(seconds: 0)); // 0 was evicted -> re-extract
    await Future<void>.delayed(Duration.zero);
    expect(fake.requested.map((d) => d.inSeconds), [0]);
    fake.requested.clear();
    c.request(const Duration(seconds: 2)); // 2 still cached -> no extraction
    await Future<void>.delayed(Duration.zero);
    expect(fake.requested, isEmpty);
  });

  test('coalesces: only one in flight, drains to the latest pending', () async {
    final c = make();
    fake.autoComplete = false;
    c.request(const Duration(seconds: 10)); // in flight (bucket 10)
    c.request(const Duration(seconds: 11)); // pending
    c.request(const Duration(seconds: 12)); // replaces pending -> 12
    expect(fake.requested.map((d) => d.inSeconds), [10]); // only first in flight
    fake.completeNext(10);
    await Future<void>.delayed(Duration.zero);
    expect(fake.requested.map((d) => d.inSeconds), [10, 12]); // drained latest, skipped 11
    fake.completeNext(12);
    await Future<void>.delayed(Duration.zero);
    expect(shown.last, Uint8List.fromList([12])); // shows the latest frame
  });
}
```

- [ ] **Step 5: Run the tests — verify they fail**

Run: `flutter test test/ui/player/seek/seek_preview_test.dart`
Expected: FAIL (`seek_preview.dart` / `SeekPreviewController` not defined).

- [ ] **Step 6: Implement** — `lib/ui/player/seek/seek_preview.dart`

```dart
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/frame_extractor_provider.dart';
import '../../../platform/interfaces/frame_extractor.dart';

/// Current scrub target while dragging the seek bar; null when not dragging.
final scrubProvider = StateProvider<Duration?>((ref) => null);

/// Latest preview frame bytes for the bubble (null = none/loading).
final seekPreviewFrameProvider = StateProvider<Uint8List?>((ref) => null);

final seekPreviewControllerProvider = Provider<SeekPreviewController>((ref) {
  return SeekPreviewController(
    extractor: ref.read(frameExtractorProvider),
    onFrame: (b) => ref.read(seekPreviewFrameProvider.notifier).state = b,
  );
});

/// Buckets scrub positions to 1 s, LRU-caches the last [capacity] frames, and
/// coalesces requests so at most one extraction runs at a time — a newer
/// position arriving mid-flight replaces the pending one (intermediates drop).
class SeekPreviewController {
  SeekPreviewController(
      {required FrameExtractor extractor,
      required this.onFrame,
      this.capacity = 30})
      : _extractor = extractor;

  final FrameExtractor _extractor;
  final void Function(Uint8List? bytes) onFrame;
  final int capacity;

  final LinkedHashMap<int, Uint8List> _cache = LinkedHashMap<int, Uint8List>();
  bool _inFlight = false;
  int? _pendingBucket;

  void request(Duration position) {
    final bucket = position.inSeconds;
    final cached = _get(bucket);
    if (cached != null) {
      onFrame(cached);
      return;
    }
    _pendingBucket = bucket;
    if (!_inFlight) _drain();
  }

  Future<void> _drain() async {
    while (_pendingBucket != null) {
      final bucket = _pendingBucket!;
      _pendingBucket = null;
      final cached = _get(bucket);
      if (cached != null) {
        onFrame(cached);
        continue;
      }
      _inFlight = true;
      final bytes = await _extractor.frameAt(Duration(seconds: bucket));
      _inFlight = false;
      if (bytes != null) {
        _put(bucket, bytes);
        // Only surface if no newer request superseded this one mid-flight.
        if (_pendingBucket == null) onFrame(bytes);
      }
    }
  }

  Uint8List? _get(int bucket) {
    final v = _cache.remove(bucket);
    if (v != null) _cache[bucket] = v; // promote to most-recently-used
    return v;
  }

  void _put(int bucket, Uint8List bytes) {
    _cache.remove(bucket);
    _cache[bucket] = bytes;
    if (_cache.length > capacity) _cache.remove(_cache.keys.first);
  }
}
```

- [ ] **Step 7: Run the tests — verify they pass**

Run: `flutter test test/ui/player/seek/seek_preview_test.dart`
Expected: PASS (3/3). Then `flutter analyze` — clean.

- [ ] **Step 8: Commit**

```bash
git add lib/platform/interfaces/frame_extractor.dart lib/platform/frame_extractor_provider.dart lib/ui/player/seek/seek_preview.dart test/fakes/fakes.dart test/ui/player/seek/seek_preview_test.dart
git commit -m "feat: FrameExtractor interface + SeekPreviewController (bucket/LRU/coalesce)"
```

---

### Task 2: Android FrameExtractor (native MediaMetadataRetriever)

**Files:**
- Create: `lib/platform/android/android_frame_extractor.dart`
- Modify: `android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt`
- Modify: `lib/main.dart` (override `frameExtractorProvider`)

**Interfaces:**
- Consumes: `FrameExtractor` (Task 1), `frameExtractorProvider` (Task 1).
- Produces: `AndroidFrameExtractor` (concrete), wired in `main()`.

No Dart unit test (native boundary — verified by the device build, like the orientation channel). Verify Kotlin compiles via the release build.

- [ ] **Step 1: Dart implementation** — `lib/platform/android/android_frame_extractor.dart`

```dart
import 'package:flutter/services.dart';
import '../interfaces/frame_extractor.dart';

class AndroidFrameExtractor implements FrameExtractor {
  static const MethodChannel _channel = MethodChannel('kivo/frames');

  @override
  Future<void> prepare(String path) =>
      _channel.invokeMethod('prepare', {'path': path});

  @override
  Future<Uint8List?> frameAt(Duration position) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
        'frameAt', {'ms': position.inMilliseconds});
    return bytes;
  }

  @override
  Future<void> release() => _channel.invokeMethod('release');
}
```

- [ ] **Step 2: Kotlin channel** — add to `MainActivity.kt`'s `configureFlutterEngine` (after the existing `kivo/orientation` channel), plus fields/imports.

Imports to add at the top:
```kotlin
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
```

Add fields in the `MainActivity` class body:
```kotlin
private val frameExecutor = Executors.newSingleThreadExecutor()
private var retriever: MediaMetadataRetriever? = null
private var retrieverPath: String? = null
```

Register the channel inside `configureFlutterEngine` (after `super` + the orientation channel):
```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kivo/frames")
    .setMethodCallHandler { call, result ->
        when (call.method) {
            "prepare" -> {
                val path = call.argument<String>("path")
                frameExecutor.execute {
                    try {
                        if (path != null && path != retrieverPath) {
                            retriever?.release()
                            retriever = MediaMetadataRetriever().apply { setDataSource(path) }
                            retrieverPath = path
                        }
                        runOnUiThread { result.success(null) }
                    } catch (e: Exception) {
                        runOnUiThread { result.success(null) }
                    }
                }
            }
            "frameAt" -> {
                val ms = (call.argument<Number>("ms") ?: 0).toLong()
                frameExecutor.execute {
                    val bytes = frameAtMicros(ms * 1000)
                    runOnUiThread { result.success(bytes) }
                }
            }
            "release" -> {
                frameExecutor.execute {
                    retriever?.release()
                    retriever = null
                    retrieverPath = null
                    runOnUiThread { result.success(null) }
                }
            }
            else -> result.notImplemented()
        }
    }
```

Add the helper method to the `MainActivity` class:
```kotlin
private fun frameAtMicros(us: Long): ByteArray? {
    val r = retriever ?: return null
    return try {
        val targetW = 240
        val bmp: Bitmap? = if (Build.VERSION.SDK_INT >= 27) {
            // Pre-scale where supported; height 0 keeps aspect ratio.
            r.getScaledFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, targetW, 0)
        } else {
            val full = r.getFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            if (full == null) null else {
                val h = (full.height * targetW / full.width.toFloat()).toInt().coerceAtLeast(1)
                Bitmap.createScaledBitmap(full, targetW, h, true)
            }
        }
        if (bmp == null) return null
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 75, out)
        out.toByteArray()
    } catch (e: Exception) {
        null
    }
}
```
(Note: `getScaledFrameAtTime(us, option, width, 0)` — a height of 0 makes Android preserve the aspect ratio. Leave the existing orientation channel exactly as-is.)

- [ ] **Step 3: Override the provider in `main.dart`**

Add the import `import 'platform/android/android_frame_extractor.dart';` and `import 'platform/frame_extractor_provider.dart';`, then add to the `overrides` list in `runApp(ProviderScope(overrides: [...]))`:
```dart
frameExtractorProvider.overrideWithValue(AndroidFrameExtractor()),
```

- [ ] **Step 4: Build, analyze, commit**

`flutter analyze` clean; `flutter test` still 70/70 (+ the 3 from Task 1 → 73). The Kotlin compiles only via a device/release build (the controller will run it); commit after analyze + tests pass.
```bash
git add lib/platform/android/android_frame_extractor.dart android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt lib/main.dart
git commit -m "feat: AndroidFrameExtractor via MediaMetadataRetriever (kivo/frames channel)"
```

---

### Task 3: Seek bar preview behavior + bubble UI + lifecycle

**Files:**
- Modify: `lib/ui/player/controls/seek_bar.dart`
- Create: `lib/ui/player/seek/seek_preview_bubble.dart`
- Modify: `lib/ui/player/controls/bottom_bar.dart` (mount the bubble above the seek bar)
- Modify: `lib/ui/player/player_screen.dart` (prepare/release lifecycle)
- Test: `test/ui/player/seek/seek_preview_bubble_test.dart`

**Interfaces:**
- Consumes: `scrubProvider`, `seekPreviewFrameProvider`, `seekPreviewControllerProvider`, `SeekPreviewController.request` (Task 1); `frameExtractorProvider` (Task 1); `playerControllerProvider.seekTo`, `controlsVisibleProvider.show`, `positionProvider`, `durationProvider`, `settingsProvider`, `fmtDuration` (existing).
- Produces: `SeekPreviewBubble` widget.

- [ ] **Step 1: Update `seek_bar.dart`** — scrub on change (no live seek), commit on end, show scrub time on the left.

Replace the `Slider` and the left time `Text` so the build reads:
```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final accent = Color(ref.watch(settingsProvider).accentColor);
  final pos = ref.watch(positionProvider).value ?? Duration.zero;
  final total = ref.watch(durationProvider).value ?? Duration.zero;
  final scrub = ref.watch(scrubProvider);
  final maxMs = total.inMilliseconds == 0 ? 1.0 : total.inMilliseconds.toDouble();
  final shownPos = scrub ?? pos;
  return Row(
    children: [
      Text(fmtDuration(shownPos), style: const TextStyle(color: Colors.white, fontSize: 12)),
      Expanded(
        child: Slider(
          min: 0,
          max: maxMs,
          value: (scrub ?? pos).inMilliseconds.clamp(0, maxMs.toInt()).toDouble(),
          activeColor: accent,
          inactiveColor: Colors.white24,
          onChanged: (v) {
            final d = Duration(milliseconds: v.round());
            ref.read(scrubProvider.notifier).state = d;
            ref.read(controlsVisibleProvider.notifier).show();
            ref.read(seekPreviewControllerProvider).request(d);
          },
          onChangeEnd: (v) {
            ref.read(playerControllerProvider).seekTo(Duration(milliseconds: v.round()));
            ref.read(scrubProvider.notifier).state = null;
          },
        ),
      ),
      GestureDetector(
        onTap: () => ref.read(showRemainingProvider.notifier).update((s) => !s),
        behavior: HitTestBehavior.opaque,
        child: Text(
          ref.watch(showRemainingProvider)
              ? '-${fmtDuration(total - shownPos < Duration.zero ? Duration.zero : total - shownPos)}'
              : fmtDuration(total),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    ],
  );
}
```
Add imports: `import '../seek/seek_preview.dart';` and `import '../../../player/control/player_controller.dart';` (already imported — verify). `showRemainingProvider` is already defined in this file.

- [ ] **Step 2: Create the bubble** — `lib/ui/player/seek/seek_preview_bubble.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/engine/playback_provider.dart';
import 'seek_preview.dart';

/// Floating preview shown above the seek bar while scrubbing: the target frame
/// (gold-bordered) over its timestamp. Horizontally anchored to the scrub
/// fraction. Renders nothing when not scrubbing.
class SeekPreviewBubble extends ConsumerWidget {
  const SeekPreviewBubble({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrub = ref.watch(scrubProvider);
    if (scrub == null) return const SizedBox.shrink();
    final total = ref.watch(durationProvider).value ?? Duration.zero;
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final bytes = ref.watch(seekPreviewFrameProvider);
    final frac = total.inMilliseconds == 0
        ? 0.0
        : (scrub.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    // Map fraction 0..1 to Alignment x -1..1.
    final alignX = (frac * 2 - 1).clamp(-1.0, 1.0);

    return Align(
      alignment: Alignment(alignX, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 160,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent, width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes == null
                  ? const SizedBox.shrink()
                  : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(fmtDuration(scrub),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Mount the bubble in `bottom_bar.dart`** — directly above the `SeekBar` so it anchors to the bar width.

Wrap the existing `Column`'s `SeekBar()` so the bubble floats above it. Change the `Column`'s first child from `const SeekBar()` to:
```dart
Stack(
  clipBehavior: Clip.none,
  children: [
    const SeekBar(),
    Positioned(
      left: 0, right: 0, bottom: 28, // sit above the bar
      child: const SeekPreviewBubble(),
    ),
  ],
),
```
Add `import '../seek/seek_preview_bubble.dart';`. (The bubble renders `SizedBox.shrink()` when not scrubbing, so it costs nothing then.)

- [ ] **Step 4: Lifecycle in `player_screen.dart`** — cache the extractor, prepare on open, release on dispose.

Add field `late final FrameExtractor _frames;` and import `'../../player/.../frame_extractor.dart'`? Use `import '../../platform/interfaces/frame_extractor.dart';` and `import '../../platform/frame_extractor_provider.dart';`. In `initState` (next to `_engine = ref.read(playbackEngineProvider);`): `_frames = ref.read(frameExtractorProvider);`. In `_start`, after `await engine.open(...)`: `_frames.prepare(session.path);`. In `dispose` (with the other cached-service calls, NEVER via `ref`): `_frames.release();`.

- [ ] **Step 5: Widget test** — `test/ui/player/seek/seek_preview_bubble_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/ui/player/seek/seek_preview.dart';
import 'package:kivo_player/ui/player/seek/seek_preview_bubble.dart';
import '../../../fakes/fakes.dart';

void main() {
  testWidgets('bubble hidden when not scrubbing, shown with timestamp when scrubbing',
      (tester) async {
    final settings = await SettingsService.load(InMemorySettingsStore());
    final engine = FakePlaybackEngine();
    final container = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(settings),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SeekPreviewBubble())),
    ));
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining(':'), findsNothing);

    container.read(scrubProvider.notifier).state = const Duration(seconds: 75);
    await tester.pump();
    expect(find.text('01:15'), findsOneWidget); // timestamp shown
  });
}
```
(If `FakePlaybackEngine`/`InMemorySettingsStore` need duration/position seeding for this test, the bubble only reads `durationProvider` defensively (`?? Duration.zero`), so the defaults are fine.)

- [ ] **Step 6: Run tests + analyze**

Run: `flutter test` — expect green (73 + 1 = 74). If `seek_bar_test.dart` asserted a live `seekTo` on drag (`onChanged`), update it to assert the seek fires on `onChangeEnd` instead (drag-to-scrub no longer seeks live; release commits). `flutter analyze` — clean.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/player/controls/seek_bar.dart lib/ui/player/seek/seek_preview_bubble.dart lib/ui/player/controls/bottom_bar.dart lib/ui/player/player_screen.dart test/ui/player/seek/seek_preview_bubble_test.dart
git commit -m "feat: seek bar preview bubble + scrub-on-drag/commit-on-release + lifecycle"
```

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review.
3. Release build to the Pixel 6: verify the frame bubble appears above the bar while dragging, tracks the thumb, shows the correct frame + timestamp, is smooth (no jank), and that releasing commits the seek. Confirm extraction doesn't stutter playback.

(Deferred, unchanged: thumbnail queue strip — needs real folder access, Hito 2; preview on the horizontal-drag gesture; double-tap ripple.)
