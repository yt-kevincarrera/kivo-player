# Hito 2 / 2b — Library UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the temporary OpenScreen list with the real library: a date-grouped all-videos feed (pinch density 1↔2↔3), a "Continue watching" row, cinematic tiles with segmented gold progress + MediaStore thumbnails, and a secondary Folders tab — with hero open into the player.

**Architecture:** Pure helpers (date grouping) + data extensions (resume `updatedAt`/`entries`, MediaStore `thumbnail`) + Riverpod providers (continue-watching, thumbnail family) + widgets (tile, continue row, folder grid) composed in a tabbed `LibraryScreen`. Cinematic layout + the player's segmented dark+gold language.

**Tech Stack:** Flutter, Riverpod, Android MediaStore (Kotlin).

## Global Constraints

- Builds on 2a (`MediaIndexer`/`VideoItem`/`mediaIndexProvider`/`folderQueueFor`/`currentVideoProvider.openInFolder`). No new pub deps.
- Tabs are a **discreet** segmented control (small, ~28px tall, not full-width-dominant): blue active (`KivoColors.blue`), grey inactive. Default Videos.
- Feed grouped by day with relative labels: **Hoy**, **Ayer**, "`d mmm`" (this year), "`mmm yyyy`" (older); newest first by `dateAddedMs`. Spanish month abbreviations.
- Pinch density 1↔2↔3 columns, default 1, persisted in `settings.libraryColumns`; haptic on change.
- Progress = `seconds*1000 / durationMs`; "finished" ≥ 0.97 (matches resume). Segmented gold progress (lit=accent, unlit=`white@0.18`), accent configurable.
- Thumbnails via MediaStore (NOT FrameExtractor); shimmer placeholder + fade-in.
- Inject `now`/`nowMs` into pure date logic and resume `record` (no bare `DateTime.now()` in pure code).
- AnimationControllers init in `initState` (never lazy `late final` field-init — known test-teardown crash). Dispose them.
- `flutter analyze` clean; `flutter test` green (currently 84). Pure logic + providers + widgets unit-tested with fakes; MediaStore thumbnails + hero + pinch feel device-verified.

---

### Task 1: Date grouping helper + `libraryColumns` setting

**Files:**
- Create: `lib/player/library/library_grouping.dart`
- Modify: `lib/core/settings/kivo_settings.dart`
- Test: `test/player/library/library_grouping_test.dart`, `test/core/settings/library_columns_test.dart` (or extend existing settings test)

**Interfaces:**
- Produces: `DaySection {String label; List<VideoItem> items}`; `List<DaySection> groupByDay(List<VideoItem> items, DateTime now)`; `KivoSettings.libraryColumns` (int, default 1).

- [ ] **Step 1: Failing test** — `library_grouping_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/library/library_grouping.dart';

VideoItem at(String name, int ms) => VideoItem(
    id: name, uri: 'content://$name', name: name, folder: 'F',
    durationMs: 1000, sizeBytes: 1, dateAddedMs: ms);

void main() {
  final now = DateTime(2026, 6, 30, 12); // Tue 30 Jun 2026
  int day(int y, int m, int d) => DateTime(y, m, d, 9).millisecondsSinceEpoch;

  test('groups by relative day, newest first', () {
    final items = [
      at('today.mp4', day(2026, 6, 30)),
      at('yest.mp4', day(2026, 6, 29)),
      at('thisyear.mp4', day(2026, 6, 12)),
      at('old.mp4', day(2024, 3, 5)),
    ];
    final s = groupByDay(items, now);
    expect(s.map((e) => e.label).toList(), ['Hoy', 'Ayer', '12 jun', 'mar 2024']);
    expect(s.first.items.single.name, 'today.mp4');
  });

  test('same-day items share a section', () {
    final items = [at('a.mp4', day(2026, 6, 30) + 100), at('b.mp4', day(2026, 6, 30))];
    final s = groupByDay(items, now);
    expect(s.length, 1);
    expect(s.first.label, 'Hoy');
    expect(s.first.items.map((e) => e.name).toList(), ['a.mp4', 'b.mp4']); // newest first
  });
}
```

- [ ] **Step 2: Run — fail.** `flutter test test/player/library/library_grouping_test.dart`

- [ ] **Step 3: Implement** — `library_grouping.dart`

```dart
import '../../platform/interfaces/media_indexer.dart';

class DaySection {
  final String label;
  final List<VideoItem> items;
  const DaySection(this.label, this.items);
}

const _mes = ['', 'ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// Groups [items] into ordered day sections (newest first) with relative
/// labels: Hoy, Ayer, "d mmm" (same year), "mmm yyyy" (older). [now] injected.
List<DaySection> groupByDay(List<VideoItem> items, DateTime now) {
  final sorted = [...items]..sort((a, b) => b.dateAddedMs.compareTo(a.dateAddedMs));
  final today = DateTime(now.year, now.month, now.day);
  String labelFor(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    if (day.year == now.year) return '${day.day} ${_mes[day.month]}';
    return '${_mes[day.month]} ${day.year}';
  }

  final sections = <DaySection>[];
  String? cur;
  for (final v in sorted) {
    final l = labelFor(v.dateAddedMs);
    if (l != cur) {
      cur = l;
      sections.add(DaySection(l, <VideoItem>[]));
    }
    sections.last.items.add(v);
  }
  return sections;
}
```

- [ ] **Step 4: Run — pass.**

- [ ] **Step 5: Add `libraryColumns` to `kivo_settings.dart`** — field `final int libraryColumns;`, `required this.libraryColumns,` in ctor, `libraryColumns: 1,` in `defaults()`, `int? libraryColumns,` + `libraryColumns: libraryColumns ?? this.libraryColumns,` in `copyWith`, `'libraryColumns': libraryColumns,` in `toMap`, `libraryColumns: m['libraryColumns'] ?? d.libraryColumns,` in `fromMap`.

- [ ] **Step 6: Settings test** — add to a settings test file:

```dart
test('libraryColumns defaults to 1 and round-trips', () {
  final d = KivoSettings.defaults();
  expect(d.libraryColumns, 1);
  final m = d.copyWith(libraryColumns: 3).toMap();
  expect(KivoSettings.fromMap(m).libraryColumns, 3);
});
```

- [ ] **Step 7: Analyze + test + commit** — `feat: groupByDay helper + libraryColumns setting`.

---

### Task 2: Resume `updatedAt` + `entries()` (continue-watching data)

**Files:**
- Modify: `lib/player/resume/resume_store.dart`, `lib/player/resume/resume_service.dart`, `lib/ui/player/player_screen.dart`
- Modify: `test/fakes/fakes.dart` (InMemoryResumeStore new signature), existing resume tests + `open_flow_test.dart`
- Test: `test/player/resume/resume_entries_test.dart`

**Interfaces:**
- Produces: `ResumeEntry {String key; int seconds; int updatedAtMs}`; `ResumeStore.put(String key, int seconds, int updatedAtMs)`, `ResumeStore.entries() -> List<ResumeEntry>`; `ResumeService.record(String key, Duration position, Duration total, int nowMs)`, `ResumeService.entries() -> List<ResumeEntry>`.
- Consumes: existing Hive box.

- [ ] **Step 1: `resume_store.dart`** — add ResumeEntry + entries + updatedAt; migrate old int records.

```dart
import 'package:hive/hive.dart';

class ResumeEntry {
  final String key;
  final int seconds;
  final int updatedAtMs;
  const ResumeEntry(this.key, this.seconds, this.updatedAtMs);
}

abstract class ResumeStore {
  int? secondsFor(String key);
  Future<void> put(String key, int seconds, int updatedAtMs);
  Future<void> remove(String key);
  List<ResumeEntry> entries();
}

class HiveResumeStore implements ResumeStore {
  final Box box;
  HiveResumeStore(this.box);

  int? _seconds(dynamic raw) {
    if (raw is int) return raw; // legacy: bare seconds
    if (raw is Map) return (raw['s'] as num?)?.toInt();
    return null;
  }

  @override
  int? secondsFor(String key) => _seconds(box.get(key));

  @override
  Future<void> put(String key, int seconds, int updatedAtMs) =>
      box.put(key, {'s': seconds, 'u': updatedAtMs});

  @override
  Future<void> remove(String key) => box.delete(key);

  @override
  List<ResumeEntry> entries() {
    final out = <ResumeEntry>[];
    for (final k in box.keys) {
      final raw = box.get(k);
      final s = _seconds(raw);
      if (s == null) continue;
      final u = raw is Map ? ((raw['u'] as num?)?.toInt() ?? 0) : 0; // legacy → 0
      out.add(ResumeEntry(k.toString(), s, u));
    }
    return out;
  }
}
```

- [ ] **Step 2: `resume_service.dart`** — `record` takes `nowMs`; add `entries()` passthrough.

```dart
Future<void> record(String key, Duration position, Duration total, int nowMs) async {
  final finishedThreshold = total.inMilliseconds * finishedTailFraction;
  if (total.inMilliseconds > 0 && position.inMilliseconds >= finishedThreshold) {
    await _store.remove(key);
    return;
  }
  if (position.inSeconds < minSeconds) return;
  await _store.put(key, position.inSeconds, nowMs);
}

List<ResumeEntry> entries() => _store.entries();
```
(Keep `positionFor`/`clear` unchanged.)

- [ ] **Step 3: `player_screen._saveProgress`** — pass now:

```dart
await _resume.record(key, _lastPosition, _lastDuration,
    DateTime.now().millisecondsSinceEpoch);
```

- [ ] **Step 4: Update `InMemoryResumeStore` (fakes.dart)** to the new interface:

```dart
class InMemoryResumeStore implements ResumeStore {
  final Map<String, ResumeEntry> _m = {};
  @override
  int? secondsFor(String key) => _m[key]?.seconds;
  @override
  Future<void> put(String key, int seconds, int updatedAtMs) async =>
      _m[key] = ResumeEntry(key, seconds, updatedAtMs);
  @override
  Future<void> remove(String key) async => _m.remove(key);
  @override
  List<ResumeEntry> entries() => _m.values.toList();
}
```
Update existing callers: `open_flow_test.dart` `resumeStore.put('ep1.mkv', 120)` → `put('ep1.mkv', 120, 0)`. Any `ResumeService...record(k,p,t)` in tests → add a `nowMs` arg (e.g. `0`). Grep `\.record(` and `\.put(` in `test/` and fix all.

- [ ] **Step 5: Test** — `resume_entries_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import '../../fakes/fakes.dart';

void main() {
  test('record stores updatedAt; entries lists them', () async {
    final store = InMemoryResumeStore();
    final svc = ResumeService(store);
    await svc.record('a.mp4', const Duration(seconds: 30), const Duration(minutes: 10), 1000);
    final e = svc.entries();
    expect(e.single.key, 'a.mp4');
    expect(e.single.seconds, 30);
    expect(e.single.updatedAtMs, 1000);
  });
}
```
(If a Hive-migration test is wanted, it needs a real Box — skip; the legacy `int` path is covered by the `_seconds`/`entries` logic and exercised on device. Optionally add a tiny pure test of the migration by constructing the store over a fake Box if one exists.)

- [ ] **Step 6: Analyze + test + commit** — `feat: resume entries() + updatedAt (continue-watching data)`.

---

### Task 3: MediaStore thumbnails (`thumbnail(id)` + cache + `ThumbnailImage`)

**Files:**
- Modify: `lib/platform/interfaces/media_indexer.dart` (+ `thumbnail`), `lib/platform/android/android_media_indexer.dart`, `android/.../MainActivity.kt`, `test/fakes/fakes.dart` (FakeMediaIndexer thumbnail)
- Create: `lib/player/library/thumbnails.dart` (provider), `lib/ui/home/widgets/thumbnail_image.dart`
- Test: `test/ui/home/thumbnail_image_test.dart`

**Interfaces:**
- Produces: `MediaIndexer.thumbnail(String id) -> Future<Uint8List?>`; `thumbnailProvider` (`FutureProvider.autoDispose.family<Uint8List?, String>`); `ThumbnailImage(id, {width, height})` widget.

- [ ] **Step 1: Interface + fake.** Add to `MediaIndexer`: `Future<Uint8List?> thumbnail(String id);`. In `FakeMediaIndexer`, add `Uint8List? thumb;` and `@override Future<Uint8List?> thumbnail(String id) async => thumb;`.

- [ ] **Step 2: `android_media_indexer.dart`** — add:
```dart
@override
Future<Uint8List?> thumbnail(String id) async =>
    _channel.invokeMethod<Uint8List>('thumbnail', {'id': id});
```

- [ ] **Step 3: Kotlin** — in the `kivo/media` handler, handle `"thumbnail"` alongside `"scan"`:
```kotlin
"thumbnail" -> {
    val id = call.argument<String>("id")
    if (id == null) { result.error("INVALID_ARG", "id required", null); return@setMethodCallHandler }
    ioExecutor.execute {
        var bytes: ByteArray? = null
        try {
            val uri = ContentUris.withAppendedId(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id.toLong())
            val bmp = if (Build.VERSION.SDK_INT >= 29) {
                contentResolver.loadThumbnail(uri, android.util.Size(320, 180), null)
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Video.Thumbnails.getThumbnail(
                    contentResolver, id.toLong(),
                    MediaStore.Video.Thumbnails.MINI_KIND, null)
            }
            if (bmp != null) {
                val bos = java.io.ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.JPEG, 80, bos)
                bytes = bos.toByteArray()
            }
        } catch (_: Exception) {}
        runOnUiThread { result.success(bytes) }
    }
}
```
Change the existing `if (call.method == "scan")` to a `when (call.method) { "scan" -> {...}; "thumbnail" -> {...}; else -> result.notImplemented() }`. Add `import android.os.Build` if not present (it is). Leave orientation/frames untouched.

- [ ] **Step 4: `thumbnails.dart`** — provider:
```dart
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/media_indexer_provider.dart';

/// Per-id thumbnail; autoDispose frees off-screen ones (MediaStore re-fetch is
/// cheap/system-cached). Returns null if unavailable.
final thumbnailProvider =
    FutureProvider.autoDispose.family<Uint8List?, String>((ref, id) {
  return ref.read(mediaIndexerProvider).thumbnail(id);
});
```

- [ ] **Step 5: `thumbnail_image.dart`** — shimmer + fade-in:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../player/library/thumbnails.dart';

class ThumbnailImage extends ConsumerWidget {
  final String id;
  final BoxFit fit;
  const ThumbnailImage(this.id, {super.key, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(thumbnailProvider(id));
    final bytes = async.valueOrNull;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: bytes == null
          ? Container(key: const ValueKey('ph'), color: const Color(0xFF1C2230))
          : Image.memory(bytes, key: ValueKey(id), fit: fit, gaplessPlayback: true),
    );
  }
}
```
(A static dark placeholder is the shimmer base; a moving shimmer can be layered later — keep YAGNI, the fade-in is the key effect.)

- [ ] **Step 6: Widget test** — `thumbnail_image_test.dart`

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/ui/home/widgets/thumbnail_image.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('shows placeholder then image when bytes arrive', (tester) async {
    final fake = FakeMediaIndexer()..thumb = Uint8List.fromList(
      // 1x1 transparent PNG
      [0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
       0,0,0,1,0,0,0,1,8,6,0,0,0,0x1F,0x15,0xC4,0x89,0,0,0,0x0A,0x49,0x44,0x41,0x54,
       0x78,0x9C,0x63,0,1,0,0,5,0,1,0x0D,0x0A,0x2D,0xB4,0,0,0,0,0x49,0x45,0x4E,0x44,0xAE,0x42,0x60,0x82]);
    await tester.pumpWidget(ProviderScope(
      overrides: [mediaIndexerProvider.overrideWithValue(fake)],
      child: const MaterialApp(home: SizedBox(width: 100, height: 100, child: ThumbnailImage('1'))),
    ));
    expect(find.byType(Container), findsOneWidget); // placeholder first
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget); // image after load
  });
}
```

- [ ] **Step 7: Analyze + test + commit** — `feat: MediaStore thumbnails (thumbnail channel + cache provider + ThumbnailImage)`.

---

### Task 4: `continueWatchingProvider`

**Files:**
- Create: `lib/player/library/continue_watching.dart`
- Test: `test/player/library/continue_watching_test.dart`

**Interfaces:**
- Produces: `ContinueItem {VideoItem video; int seconds; double fraction}`; `continueWatchingProvider -> List<ContinueItem>`.
- Consumes: `mediaIndexProvider` (2a), `resumeServiceProvider.entries()` (Task 2).

- [ ] **Step 1: Failing test** — `continue_watching_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/library/continue_watching.dart';
import '../../fakes/fakes.dart';

class _Granted implements MediaPermission {
  @override Future<MediaAccess> status() async => MediaAccess.granted;
  @override Future<MediaAccess> request() async => MediaAccess.granted;
}
VideoItem v(String n, int dur) => VideoItem(id: n, uri: 'content://$n', name: n,
    folder: 'F', durationMs: dur, sizeBytes: 1, dateAddedMs: 0);

void main() {
  test('joins resume entries with index, drops finished, newest first', () async {
    final store = InMemoryResumeStore();
    await store.put('a.mp4', 30, 100); // 30s of 100s = 30%
    await store.put('b.mp4', 95, 200); // 95s of 100s = 95% (keep; <97%)
    await store.put('c.mp4', 99, 300); // 99% finished → drop
    await store.put('ghost.mp4', 10, 400); // not in index → drop
    final c = ProviderContainer(overrides: [
      mediaPermissionImplProvider.overrideWithValue(_Granted()),
      mediaIndexerProvider.overrideWithValue(
          FakeMediaIndexer([v('a.mp4', 100000), v('b.mp4', 100000), v('c.mp4', 100000)])),
      resumeServiceProvider.overrideWithValue(_Svc(store)),
    ]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProviderForTest(c)); // ensure index loaded (see note)
    final list = c.read(continueWatchingProvider);
    expect(list.map((e) => e.video.name).toList(), ['b.mp4', 'a.mp4']); // updatedAt desc
    expect(list.first.fraction, closeTo(0.95, 0.001));
  });
}
```
NOTE to implementer: the test needs the index resolved before reading `continueWatchingProvider`. Simplest: make `continueWatchingProvider` read `ref.watch(mediaIndexProvider).valueOrNull ?? []` and in the test `await c.read(mediaIndexProvider.future)` first, then `c.read(continueWatchingProvider)`. Replace the pseudo `mediaIndexProviderForTest` line with `await c.read(mediaIndexProvider.future);`. `_Svc` is a tiny `ResumeService` subclass/wrapper exposing `entries()` from the store — actually just use `ResumeService(store)` directly (it has `entries()`), so `resumeServiceProvider.overrideWithValue(ResumeService(store))`. Fix the test accordingly before running.

- [ ] **Step 2: Implement** — `continue_watching.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../library/media_index.dart';
import '../open/video_source.dart'; // resumeServiceProvider

class ContinueItem {
  final VideoItem video;
  final int seconds;
  final double fraction;
  const ContinueItem(this.video, this.seconds, this.fraction);
}

final continueWatchingProvider = Provider<List<ContinueItem>>((ref) {
  final index = ref.watch(mediaIndexProvider).valueOrNull ?? const [];
  if (index.isEmpty) return const [];
  final byName = {for (final v in index) v.name: v};
  final entries = ref.read(resumeServiceProvider).entries()
    ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
  final out = <ContinueItem>[];
  for (final e in entries) {
    final v = byName[e.key];
    if (v == null || v.durationMs <= 0) continue;
    final frac = (e.seconds * 1000) / v.durationMs;
    if (frac >= 0.97) continue;
    out.add(ContinueItem(v, e.seconds, frac.clamp(0.0, 1.0)));
  }
  return out;
});
```

- [ ] **Step 3: Run — pass; analyze; commit** — `feat: continueWatchingProvider (resume × index join)`.

---

### Task 5: `VideoTile` + `ContinueRow` widgets

**Files:**
- Create: `lib/ui/home/widgets/video_tile.dart`, `lib/ui/home/widgets/continue_row.dart`
- Test: `test/ui/home/video_tile_test.dart`

**Interfaces:**
- Produces: `VideoTile({VideoItem video, double? progress, bool compact, VoidCallback onTap})`; `ContinueRow()` (reads `continueWatchingProvider`).
- Consumes: `ThumbnailImage` (Task 3), `fmtDuration`, `settingsProvider.accentColor`, `currentVideoProvider.openInFolder` + `mediaIndexProvider` (for the row's tap).

- [ ] **Step 1: `video_tile.dart`** — cinematic tile (thumbnail + title overlay + duration badge + segmented gold progress). `_PressBounce` reused (extract it to a shared file if not already public — it's currently private in `center_controls.dart`; create `lib/ui/widgets/press_bounce.dart` with the same widget and import it in both places).

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../widgets/press_bounce.dart';
import 'thumbnail_image.dart';

class VideoTile extends ConsumerWidget {
  final VideoItem video;
  final double? progress; // 0..1 watched, or null
  final bool compact;     // multi-column dense layout
  final VoidCallback onTap;
  const VideoTile({super.key, required this.video, required this.onTap, this.progress, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Color(ref.watch(settingsProvider).accentColor);
    return PressBounce(
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              Hero(tag: 'video-${video.id}', child: ThumbnailImage(video.id)),
              // duration badge
              Positioned(top: 6, right: 6, child: _badge(fmtDuration(Duration(milliseconds: video.durationMs)))),
              // title gradient + text
              Positioned(left: 0, right: 0, bottom: 0, child: Container(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, progress != null ? 8 : 6),
                decoration: const BoxDecoration(gradient: LinearGradient(
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent])),
                child: Text(video.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: compact ? 11 : 13, fontWeight: FontWeight.w600)),
              )),
              if (progress != null)
                Positioned(left: 0, right: 0, bottom: 0, child: _SegmentedProgress(progress!, accent)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _badge(String t) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
      child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 9, fontFeatures: [FontFeature.tabularFigures()])));
}

class _SegmentedProgress extends StatelessWidget {
  final double fraction;
  final Color accent;
  const _SegmentedProgress(this.fraction, this.accent);
  @override
  Widget build(BuildContext context) {
    const n = 16;
    final lit = (fraction * n).round();
    return Row(children: [
      for (var i = 0; i < n; i++)
        Expanded(child: Container(
          height: 4, margin: const EdgeInsets.symmetric(horizontal: 0.5),
          color: i < lit ? accent : Colors.white.withValues(alpha: 0.18),
        )),
    ]);
  }
}
```
(Need `import 'dart:ui' show FontFeature;` if unresolved.) Extract `PressBounce` to `lib/ui/widgets/press_bounce.dart` (public `class PressBounce`) and update `center_controls.dart` to import it (replace its private `_PressBounce`). 

- [ ] **Step 2: `continue_row.dart`** — horizontal snap row of in-progress videos.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../player/library/continue_watching.dart';
import '../../../player/library/media_index.dart';
import '../../../player/open/video_source.dart';
import '../player_open.dart'; // openVideo helper (see Task 6) OR inline the push
import 'video_tile.dart';

class ContinueRow extends ConsumerWidget {
  final void Function(WidgetRef, dynamic) onOpen; // (ref, VideoItem)
  const ContinueRow({super.key, required this.onOpen});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueWatchingProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text('Continuar viendo', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
      SizedBox(height: 120, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const PageScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => SizedBox(width: 190, child: VideoTile(
          video: items[i].video, progress: items[i].fraction,
          onTap: () => onOpen(ref, items[i].video))),
      )),
    ]);
  }
}
```
NOTE: to avoid a circular dependency / keep open logic in one place, the `onOpen` callback is passed in by `LibraryScreen` (Task 6) — it calls `currentVideoProvider.openInFolder(video, allVideos)` + pushes the player. Drop the `player_open.dart` import; the callback signature is `void Function(VideoItem)` — fix the import line accordingly (the tile/row don't import the player).

- [ ] **Step 3: Widget test** — `video_tile_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/widgets/video_tile.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('tile shows title, duration, and fires onTap', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    var tapped = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
        mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
      ],
      child: MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 200, child: VideoTile(
        video: VideoItem(id: '1', uri: 'content://1', name: 'cool.mkv', folder: 'F',
            durationMs: 65000, sizeBytes: 1, dateAddedMs: 0),
        progress: 0.5, onTap: () => tapped = true))))),
    ));
    await tester.pump();
    expect(find.text('cool.mkv'), findsOneWidget);
    expect(find.text('01:05'), findsOneWidget);
    await tester.tap(find.byType(VideoTile));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 4: Analyze + test + commit** — `feat: VideoTile (cinematic + segmented progress) + ContinueRow; extract PressBounce`.

---

### Task 6: `LibraryScreen` — tabs + date feed + pinch + folders + open

**Files:**
- Create: `lib/ui/home/library_screen.dart`, `lib/ui/home/widgets/folder_grid.dart`, `lib/ui/home/folder_screen.dart`
- Modify: `lib/app.dart` (or wherever `OpenScreen` is the home) to use `LibraryScreen`; keep `OpenScreen`'s file-picker/share-intent by folding those into `LibraryScreen` (AppBar action + intent listener) OR keep OpenScreen as a thin shell. Simplest: move the file-picker action + share-intent + permission gate into `LibraryScreen`, delete the now-redundant list from OpenScreen (or replace OpenScreen entirely).
- Test: `test/ui/home/library_screen_test.dart`

**Interfaces:**
- Consumes: `groupByDay` (T1), `settings.libraryColumns` (T1), `continueWatchingProvider` (T4), `ContinueRow`/`VideoTile` (T5), `mediaIndexProvider` + `groupByFolder`/`folderQueueFor` (2a), `mediaPermissionProvider` (2a), `currentVideoProvider.openInFolder`.

- [ ] **Step 1: `library_screen.dart`** — permission gate, discreet tabs, Videos feed (CustomScrollView: continue row + date sections as alternating header/grid slivers), pinch density, Carpetas tab.

Structure (full code; the implementer fills the obvious bits, but this is the load-bearing skeleton):
```dart
class LibraryScreen extends ConsumerStatefulWidget { const LibraryScreen({super.key}); ... }
class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  int _tab = 0; // 0 Videos, 1 Carpetas
  double _scaleStart = 1; // for pinch

  void _open(VideoItem v, List<VideoItem> all) {
    ref.read(currentVideoProvider.notifier).openInFolder(v, all);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlayerScreen()))
        .then((_) => ref.invalidate(continueWatchingProvider)); // refresh on return
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final cols = ref.read(settingsProvider).libraryColumns;
    int next = cols;
    if (d.scale > 1.25) next = (cols - 1).clamp(1, 3);      // pinch out → fewer cols (bigger)
    else if (d.scale < 0.8) next = (cols + 1).clamp(1, 3);  // pinch in → more cols
    if (next != cols) {
      HapticFeedback.selectionClick();
      final s = ref.read(settingsProvider);
      ref.read(settingsProvider.notifier).set(s.copyWith(libraryColumns: next));
    }
  }

  @override
  Widget build(BuildContext context) {
    final perm = ref.watch(mediaPermissionProvider);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: _DiscreetTabs(index: _tab, onChanged: (i) => setState(() => _tab = i)),
        actions: [ /* file-picker IconButton (KivoIcons.folderOpen) */ ],
      ),
      body: perm.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _accessPrompt(),
        data: (a) => a == MediaAccess.denied ? _accessPrompt() : _body(),
      ),
    );
  }

  Widget _body() {
    final index = ref.watch(mediaIndexProvider);
    return index.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, __) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white70))),
      data: (videos) => _tab == 0 ? _videosTab(videos) : _foldersTab(videos),
    );
  }

  Widget _videosTab(List<VideoItem> videos) {
    final cols = ref.watch(settingsProvider).libraryColumns;
    final sections = groupByDay(videos, DateTime.now());
    final continueItems = {for (final c in ref.watch(continueWatchingProvider)) c.video.name: c};
    return GestureDetector(
      onScaleStart: (_) {}, onScaleUpdate: _onScaleUpdate,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: ContinueRow(onOpen: (v) => _open(v, videos))),
        for (final s in sections) ...[
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Row(children: [Container(width: 3, height: 13, color: Color(ref.watch(settingsProvider).accentColor)),
                const SizedBox(width: 7),
                Text(s.label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))]))),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols, childAspectRatio: 16 / 9, crossAxisSpacing: 8, mainAxisSpacing: 8),
              delegate: SliverChildBuilderDelegate((_, i) {
                final v = s.items[i];
                return VideoTile(video: v, compact: cols > 1,
                    progress: continueItems[v.name]?.fraction, onTap: () => _open(v, videos));
              }, childCount: s.items.length),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }

  Widget _foldersTab(List<VideoItem> videos) => FolderGrid(
      videos: videos, onOpenFolder: (folder, items) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => FolderScreen(folder: folder, videos: items))));
  // _accessPrompt(): same access UI as 2a; the file-picker + share-intent move here from OpenScreen.
}
```
Implement `_DiscreetTabs` (a small segmented control: a `Row` of two `GestureDetector` text chips ~28px tall, active one with `KivoColors.blue` bg pill, inactive grey — keep it compact). Implement `_accessPrompt()` reusing 2a's prompt. Fold the file-picker (`_pick`) + `ReceiveSharingIntent` handling (with the try/catch) in from `OpenScreen`. The `_open` for the continue row passes the FULL `videos` list (so the folder queue is derived correctly inside `openInFolder`).

- [ ] **Step 2: `folder_grid.dart`** — Carpetas tab: `groupByFolder(videos)` → grid of capsule cards (thumbnail of first video, name, gold "N vids" pill), `onOpenFolder(name, items)`.

```dart
class FolderGrid extends ConsumerWidget {
  final List<VideoItem> videos;
  final void Function(String folder, List<VideoItem> items) onOpenFolder;
  const FolderGrid({super.key, required this.videos, required this.onOpenFolder});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = groupByFolder(videos); // from library_query.dart (2a)
    final folders = groups.keys.toList()..sort();
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.25),
      itemCount: folders.length,
      itemBuilder: (_, i) {
        final name = folders[i];
        final items = groups[name]!;
        return PressBounce(child: GestureDetector(
          onTap: () => onOpenFolder(name, items),
          child: _folderCard(ref, name, items),
        ));
      },
    );
  }
  // _folderCard: capsule (black/#161A21 + subtle border), ThumbnailImage(items.first.id) cover,
  // name + gold pill 'N vids' (N = items.length), per the spec/mockup B style.
}
```

- [ ] **Step 3: `folder_screen.dart`** — a folder's videos in a grid (same density setting, `VideoTile`, natural order; tap → `_open(v, items)`). A simple `Scaffold` + the same density grid (no date sections inside a folder).

- [ ] **Step 4: Make `LibraryScreen` the home.** In `lib/app.dart` (find the `home:`/initial route — `grep -rn "OpenScreen" lib`), point the home to `LibraryScreen`. Decide: either delete `OpenScreen` (folding its file-picker + intent into `LibraryScreen`) or keep it unused. Prefer folding in + removing OpenScreen's now-dead list to avoid two homes. Update any test that pumped `OpenScreen` to `LibraryScreen` (or keep `open_screen_test` if OpenScreen is retained as a shell — but cleanest is LibraryScreen is the home and OpenScreen is removed; migrate its widget test to `library_screen_test`).

- [ ] **Step 5: Widget test** — `library_screen_test.dart`

```dart
// Granted permission + FakeMediaIndexer with videos across two folders/dates.
// Assert: Videos tab shows a date header + the video titles; tapping the
// Carpetas tab shows folder names; pinch (or directly setting libraryColumns)
// changes the grid. Use ProviderScope overrides:
//   settingsServiceProvider, mediaPermissionImplProvider(granted),
//   mediaIndexerProvider(fake), resumeServiceProvider(InMemory), playbackEngineProvider(fake)
// Keep it focused: at minimum assert the feed lists a known video name under a
// date header, and that switching to Carpetas shows the folder name.
```
Write a concrete test asserting: a known video `name` is found in the Videos tab; tapping the "Carpetas" tab label shows the folder name; (optionally) `settingsProvider` libraryColumns change rebuilds. Use `tester.pumpAndSettle()` after permission/index resolve.

- [ ] **Step 6: Analyze + test + commit** — `feat: LibraryScreen — tabs, date feed, pinch density, folders, hero open`.

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review (opus).
3. Release build to the Pixel 6: Videos feed grouped by date with real MediaStore thumbnails; pinch changes 1↔2↔3 columns and persists; Continue-watching row reflects in-progress videos; Folders tab + drill-in; tapping a tile hero-expands into the player with the folder queue; press-bounce + fade-in feel smooth.

(Next: 2c — search, sort, filters layered onto this library.)
