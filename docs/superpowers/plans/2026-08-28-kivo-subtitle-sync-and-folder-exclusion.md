# Kivo subtitle sync, manual subtitles & folder exclusion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user fix out-of-sync subtitles from a floating HUD, load a subtitle file by hand, and hide noisy folders from the library — with both per-video memories sharing one store.

**Architecture:** A pure-maths module drives a HUD whose taps never reach mpv directly: a 120 ms trailing debounce collapses bursts into one `sub-delay` call, because that call is the one in the open ANR trace. Per-video offset and hand-picked subtitle live in one new Hive box keyed by the resume key. Folder exclusion is a pure derived provider over the existing index — no native work, no rescan.

**Tech Stack:** Flutter · Riverpod (`Notifier`/`Provider`) · Hive · media_kit (`NativePlayer.setProperty`) · file_picker · path_provider

**Spec:** `docs/superpowers/specs/2026-08-28-kivo-subtitle-sync-and-folder-exclusion-design.md`

## Global Constraints

- **No `Co-Authored-By` trailer on any commit.** User preference, applies to every commit in this plan.
- **User-facing strings are Spanish; code comments are English.** Matches the whole codebase.
- **Never hardcode colors.** Use `Theme.of(context).colorScheme`, `KivoColors`, or `Color(ref.watch(settingsProvider).accentColor)`. Unlit meter segments are `onSurface @ alpha 0.18`.
- **`KivoSettings` has six insertion points** for every new field: field declaration, constructor, `defaults()`, `copyWith`, `toMap`, `fromMap`. Missing one compiles but loses the value silently.
- **The error catalog is append-only.** Never renumber or reuse a `KV-nnn`.
- **`sub-delay` is in seconds, positive = subtitles appear later.** The UI's `+0,50 s` maps directly.
- **Run `flutter analyze --no-pub` before every commit.** The suite must stay at 3 pre-existing infos (`grow_rect` ×2, `track_selection` naming) — no new ones.
- **Test command:** `flutter test` (full suite) or `flutter test <path>` (one file).

---

### Task 1: Pure subtitle-delay maths

No Riverpod, no widgets, no mpv — just the numbers the HUD renders.

**Files:**
- Create: `lib/player/tracks/subtitle_delay.dart`
- Test: `test/player/tracks/subtitle_delay_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `subtitleDelayStepMs` (`int`, 50) · `subtitleDelayMeterRangeMs` (`int`, 1500) · `subtitleDelaySegments` (`int`, 13) · `nudgeSubtitleDelay(int currentMs, int steps) -> int` · `formatSubtitleDelay(int ms) -> String` · `class SubtitleMeter { int centerIndex; int firstLit; int lastLit; }` · `subtitleMeter(int delayMs) -> SubtitleMeter`

- [ ] **Step 1: Write the failing test**

```dart
// test/player/tracks/subtitle_delay_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/tracks/subtitle_delay.dart';

void main() {
  test('nudging moves by whole steps in both directions', () {
    expect(nudgeSubtitleDelay(0, 1), 50);
    expect(nudgeSubtitleDelay(0, -1), -50);
    expect(nudgeSubtitleDelay(500, 3), 650);
  });

  test('formatting uses a Spanish decimal comma and an explicit sign', () {
    expect(formatSubtitleDelay(0), '0,00 s');
    expect(formatSubtitleDelay(500), '+0,50 s');
    expect(formatSubtitleDelay(-250), '−0,25 s');
    expect(formatSubtitleDelay(2000), '+2,00 s');
  });

  test('zero delay lights only the centre segment', () {
    final m = subtitleMeter(0);
    expect(m.centerIndex, 6);
    expect(m.firstLit, 6);
    expect(m.lastLit, 6);
  });

  test('a positive delay lights outward to the right', () {
    final m = subtitleMeter(500); // 500/1500 of 6 segments = 2
    expect(m.firstLit, 6);
    expect(m.lastLit, 8);
  });

  test('a negative delay lights outward to the left', () {
    final m = subtitleMeter(-500);
    expect(m.firstLit, 4);
    expect(m.lastLit, 6);
  });

  test('beyond the meter range the bar pins instead of overflowing', () {
    final m = subtitleMeter(9000);
    expect(m.lastLit, subtitleDelaySegments - 1);
    expect(m.firstLit, 6);
    final n = subtitleMeter(-9000);
    expect(n.firstLit, 0);
    expect(n.lastLit, 6);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/player/tracks/subtitle_delay_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:kivo_player/player/tracks/subtitle_delay.dart'`

- [ ] **Step 3: Write the implementation**

```dart
// lib/player/tracks/subtitle_delay.dart

/// Pure maths for the subtitle-sync HUD. No Riverpod, no widgets, no mpv —
/// everything here is a function of a single integer offset in milliseconds.

/// One tap of the HUD's − / + buttons.
const int subtitleDelayStepMs = 50;

/// What the full width of the meter represents, in each direction. Offsets
/// beyond this pin the meter; the number keeps counting.
const int subtitleDelayMeterRangeMs = 1500;

/// Odd, so there is a true centre segment for "no offset".
const int subtitleDelaySegments = 13;

int nudgeSubtitleDelay(int currentMs, int steps) =>
    currentMs + steps * subtitleDelayStepMs;

/// `+0,50 s` — Spanish decimal comma, explicit sign, U+2212 for the minus so
/// it matches the HUD's − button rather than a hyphen.
String formatSubtitleDelay(int ms) {
  final seconds = (ms.abs() / 1000).toStringAsFixed(2).replaceAll('.', ',');
  final sign = ms == 0
      ? ''
      : ms > 0
          ? '+'
          : '−';
  return '$sign$seconds s';
}

/// Which segments of the meter are lit, as an inclusive index range that
/// always contains [centerIndex].
class SubtitleMeter {
  const SubtitleMeter({
    required this.centerIndex,
    required this.firstLit,
    required this.lastLit,
  });
  final int centerIndex;
  final int firstLit;
  final int lastLit;
}

SubtitleMeter subtitleMeter(int delayMs) {
  const center = (subtitleDelaySegments - 1) ~/ 2;
  final perSide = center;
  final ratio = delayMs.abs() / subtitleDelayMeterRangeMs;
  final lit = (ratio * perSide).round().clamp(0, perSide);
  if (delayMs >= 0) {
    return SubtitleMeter(
        centerIndex: center, firstLit: center, lastLit: center + lit);
  }
  return SubtitleMeter(
      centerIndex: center, firstLit: center - lit, lastLit: center);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/player/tracks/subtitle_delay_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/player/tracks/subtitle_delay.dart test/player/tracks/subtitle_delay_test.dart
git commit -m "feat(subtitles): pure maths for the sync HUD"
```

---

### Task 2: `setSubtitleDelay` on the playback engine

**Files:**
- Modify: `lib/player/engine/playback_engine.dart` (add to the abstract interface, next to `setSubtitleStyle`)
- Modify: `lib/player/engine/media_kit_engine.dart` (implement next to `setSubtitleStyle`, ~line 152)
- Modify: `test/fakes/fakes.dart` (`FakePlaybackEngine`, ~line 170 next to `setExternalSubtitle`)
- Test: `test/player/tracks/subtitle_delay_engine_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `PlaybackEngine.setSubtitleDelay(double seconds) -> Future<void>` · `FakePlaybackEngine.subtitleDelays` (`List<double>`, every value the engine was asked to apply, in order)

- [ ] **Step 1: Write the failing test**

```dart
// test/player/tracks/subtitle_delay_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import '../../fakes/fakes.dart';

void main() {
  test('the fake engine records every delay it is handed', () async {
    final engine = FakePlaybackEngine();
    await engine.setSubtitleDelay(0.5);
    await engine.setSubtitleDelay(-0.25);
    expect(engine.subtitleDelays, [0.5, -0.25]);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/player/tracks/subtitle_delay_engine_test.dart`
Expected: FAIL — `The method 'setSubtitleDelay' isn't defined for the type 'FakePlaybackEngine'`

- [ ] **Step 3: Write the implementation**

In `lib/player/engine/playback_engine.dart`, directly after `Future<void> setExternalSubtitle(String uri, {String? title});`:

```dart
  /// Shifts subtitle timing. Positive = subtitles appear later, matching
  /// mpv's own `sub-delay` sign.
  Future<void> setSubtitleDelay(double seconds);
```

In `lib/player/engine/media_kit_engine.dart`, after the `setSubtitleStyle` method:

```dart
  @override
  Future<void> setSubtitleDelay(double seconds) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    // Callers MUST debounce: this is a synchronous mpv call on the UI thread,
    // the same one at the top of the open background-hang ANR trace. One call
    // per gesture burst, never one per tap.
    await native.setProperty('sub-delay', seconds.toStringAsFixed(3));
  }
```

In `test/fakes/fakes.dart`, inside `FakePlaybackEngine` next to `setExternalSubtitle`:

```dart
  final List<double> subtitleDelays = [];

  @override
  Future<void> setSubtitleDelay(double seconds) async =>
      subtitleDelays.add(seconds);
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/player/tracks/subtitle_delay_engine_test.dart && flutter analyze --no-pub`
Expected: PASS. Analyze must report only the 3 pre-existing infos — a missing `@override` in any other `PlaybackEngine` implementation shows up here.

- [ ] **Step 5: Commit**

```bash
git add lib/player/engine/playback_engine.dart lib/player/engine/media_kit_engine.dart test/fakes/fakes.dart test/player/tracks/subtitle_delay_engine_test.dart
git commit -m "feat(subtitles): engine can shift subtitle timing"
```

---

### Task 3: The per-video subtitle prefs store

Mirrors `HiveResumeStore` exactly — same box-of-maps shape, same key (the video's display name).

**Files:**
- Create: `lib/player/tracks/subtitle_prefs_store.dart`
- Modify: `lib/main.dart` (open the box at ~line 55, override the provider at ~line 78)
- Test: `test/player/tracks/subtitle_prefs_store_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class VideoSubtitlePrefs { int delayMs; String? subtitlePath; bool get isEmpty; VideoSubtitlePrefs copyWith({int? delayMs, Object? subtitlePath}); }` · `abstract class SubtitlePrefsStore { VideoSubtitlePrefs? forKey(String key); Future<void> put(String key, VideoSubtitlePrefs prefs); Future<void> remove(String key); Future<void> rename(String oldKey, String newKey); }` · `HiveSubtitlePrefsStore(Box box)` · `InMemorySubtitlePrefsStore()` · `subtitlePrefsStoreProvider`

- [ ] **Step 1: Write the failing test**

```dart
// test/player/tracks/subtitle_prefs_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/tracks/subtitle_prefs_store.dart';

void main() {
  test('round-trips a delay and a subtitle path', () async {
    final s = InMemorySubtitlePrefsStore();
    await s.put('ep1.mkv', const VideoSubtitlePrefs(delayMs: 500, subtitlePath: '/subs/ep1.srt'));
    expect(s.forKey('ep1.mkv')!.delayMs, 500);
    expect(s.forKey('ep1.mkv')!.subtitlePath, '/subs/ep1.srt');
  });

  test('an unknown key reads as null, not as an empty record', () {
    expect(InMemorySubtitlePrefsStore().forKey('nope.mkv'), isNull);
  });

  test('storing an empty record deletes the key instead of keeping junk', () async {
    final s = InMemorySubtitlePrefsStore();
    await s.put('ep1.mkv', const VideoSubtitlePrefs(delayMs: 500));
    await s.put('ep1.mkv', const VideoSubtitlePrefs());
    expect(s.forKey('ep1.mkv'), isNull);
  });

  test('rename carries the record to the new key', () async {
    final s = InMemorySubtitlePrefsStore();
    await s.put('old.mkv', const VideoSubtitlePrefs(delayMs: 300));
    await s.rename('old.mkv', 'new.mkv');
    expect(s.forKey('old.mkv'), isNull);
    expect(s.forKey('new.mkv')!.delayMs, 300);
  });

  test('renaming a key with nothing stored is a no-op, not a crash', () async {
    final s = InMemorySubtitlePrefsStore();
    await s.rename('ghost.mkv', 'new.mkv');
    expect(s.forKey('new.mkv'), isNull);
  });

  test('copyWith can clear the subtitle path', () {
    const p = VideoSubtitlePrefs(delayMs: 100, subtitlePath: '/a.srt');
    expect(p.copyWith(subtitlePath: null).subtitlePath, isNull);
    expect(p.copyWith(delayMs: 200).subtitlePath, '/a.srt');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/player/tracks/subtitle_prefs_store_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/player/tracks/subtitle_prefs_store.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

/// What one video remembers about its subtitles: how far its timing was
/// nudged, and which file the user loaded by hand.
///
/// These two live together because they are the same thing to the user — "the
/// subtitle setup for this video" — and because they must be migrated and
/// cleared together when the file is renamed or deleted.
class VideoSubtitlePrefs {
  const VideoSubtitlePrefs({this.delayMs = 0, this.subtitlePath});

  final int delayMs;

  /// An app-owned copy, never the raw file-picker path — those go stale.
  final String? subtitlePath;

  bool get isEmpty => delayMs == 0 && subtitlePath == null;

  static const _unset = Object();

  VideoSubtitlePrefs copyWith({int? delayMs, Object? subtitlePath = _unset}) =>
      VideoSubtitlePrefs(
        delayMs: delayMs ?? this.delayMs,
        subtitlePath: identical(subtitlePath, _unset)
            ? this.subtitlePath
            : subtitlePath as String?,
      );

  Map<String, dynamic> toMap() => {'d': delayMs, 'p': subtitlePath};

  factory VideoSubtitlePrefs.fromMap(Map m) => VideoSubtitlePrefs(
        delayMs: (m['d'] as num?)?.toInt() ?? 0,
        subtitlePath: m['p'] as String?,
      );
}

abstract class SubtitlePrefsStore {
  VideoSubtitlePrefs? forKey(String key);
  Future<void> put(String key, VideoSubtitlePrefs prefs);
  Future<void> remove(String key);
  Future<void> rename(String oldKey, String newKey);
}

class HiveSubtitlePrefsStore implements SubtitlePrefsStore {
  HiveSubtitlePrefsStore(this.box);
  final Box box;

  @override
  VideoSubtitlePrefs? forKey(String key) {
    final raw = box.get(key);
    return raw is Map ? VideoSubtitlePrefs.fromMap(raw) : null;
  }

  @override
  Future<void> put(String key, VideoSubtitlePrefs prefs) =>
      // An all-defaults record is indistinguishable from having none, so don't
      // let resetting a delay leave a row behind forever.
      prefs.isEmpty ? box.delete(key) : box.put(key, prefs.toMap());

  @override
  Future<void> remove(String key) => box.delete(key);

  @override
  Future<void> rename(String oldKey, String newKey) async {
    final existing = forKey(oldKey);
    if (existing == null) return;
    await put(newKey, existing);
    await box.delete(oldKey);
  }
}

/// Session-only store: a valid fallback and what the tests use.
class InMemorySubtitlePrefsStore implements SubtitlePrefsStore {
  final Map<String, VideoSubtitlePrefs> _data = {};

  @override
  VideoSubtitlePrefs? forKey(String key) => _data[key];

  @override
  Future<void> put(String key, VideoSubtitlePrefs prefs) async {
    if (prefs.isEmpty) {
      _data.remove(key);
    } else {
      _data[key] = prefs;
    }
  }

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<void> rename(String oldKey, String newKey) async {
    final existing = _data[oldKey];
    if (existing == null) return;
    _data[newKey] = existing;
    _data.remove(oldKey);
  }
}

final subtitlePrefsStoreProvider = Provider<SubtitlePrefsStore>(
    (ref) => InMemorySubtitlePrefsStore());
```

In `lib/main.dart`, after `final errorsBox = await Hive.openBox('errors');`:

```dart
  final subtitlePrefsBox = await Hive.openBox('subtitlePrefs');
```

and in the `overrides:` list, after the `errorLogProvider` line:

```dart
      subtitlePrefsStoreProvider
          .overrideWithValue(HiveSubtitlePrefsStore(subtitlePrefsBox)),
```

Add the import: `import 'player/tracks/subtitle_prefs_store.dart';`

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/player/tracks/subtitle_prefs_store_test.dart && flutter analyze --no-pub`
Expected: PASS, 6 tests; analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/player/tracks/subtitle_prefs_store.dart lib/main.dart test/player/tracks/subtitle_prefs_store_test.dart
git commit -m "feat(subtitles): per-video subtitle prefs store"
```

---

### Task 4: The sync controller, with the debounce that protects mpv

**Files:**
- Create: `lib/player/tracks/subtitle_sync_controller.dart`
- Test: `test/player/tracks/subtitle_sync_controller_test.dart`

**Interfaces:**
- Consumes: `nudgeSubtitleDelay` (Task 1) · `PlaybackEngine.setSubtitleDelay` (Task 2) · `subtitlePrefsStoreProvider`, `VideoSubtitlePrefs` (Task 3) · existing `currentVideoProvider` (`lib/player/open/video_source.dart`) and `playbackEngineProvider`
- Produces: `subtitleSyncDebounce` (`Duration`, 120 ms) · `class SubtitleSyncNotifier extends Notifier<int>` with `nudge(int steps)`, `reset()`, `flush()` · `subtitleSyncProvider` (`NotifierProvider<SubtitleSyncNotifier, int>`, state is the offset in ms)

- [ ] **Step 1: Write the failing test**

```dart
// test/player/tracks/subtitle_sync_controller_test.dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/subtitle_prefs_store.dart';
import 'package:kivo_player/player/tracks/subtitle_sync_controller.dart';
import '../../fakes/fakes.dart';

VideoSession _session(String name) =>
    VideoSession(playbackPath: '/v/$name', displayName: name, queue: ['/v/$name'], index: 0);

ProviderContainer _c(FakePlaybackEngine engine, SubtitlePrefsStore store) =>
    ProviderContainer(overrides: [
      playbackEngineProvider.overrideWithValue(engine),
      subtitlePrefsStoreProvider.overrideWithValue(store),
    ]);

void main() {
  test('a burst of nudges reaches mpv exactly once, with the last value', () {
    fakeAsync((async) {
      final engine = FakePlaybackEngine();
      final c = _c(engine, InMemorySubtitlePrefsStore());
      addTearDown(c.dispose);
      c.read(currentVideoProvider.notifier).open(_session('ep1.mkv'));

      final sync = c.read(subtitleSyncProvider.notifier);
      for (var i = 0; i < 12; i++) {
        sync.nudge(1);
      }
      // The UI already shows the final value before mpv has heard anything.
      expect(c.read(subtitleSyncProvider), 600);
      expect(engine.subtitleDelays, isEmpty);

      async.elapse(const Duration(milliseconds: 200));
      expect(engine.subtitleDelays, [0.6]);
    });
  });

  test('the settled offset is persisted for that video', () {
    fakeAsync((async) {
      final store = InMemorySubtitlePrefsStore();
      final c = _c(FakePlaybackEngine(), store);
      addTearDown(c.dispose);
      c.read(currentVideoProvider.notifier).open(_session('ep1.mkv'));

      c.read(subtitleSyncProvider.notifier).nudge(4);
      async.elapse(const Duration(milliseconds: 200));
      expect(store.forKey('ep1.mkv')!.delayMs, 200);
    });
  });

  test('opening a video restores its stored offset', () async {
    final store = InMemorySubtitlePrefsStore();
    await store.put('ep2.mkv', const VideoSubtitlePrefs(delayMs: -750));
    final c = _c(FakePlaybackEngine(), store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('ep2.mkv'));
    expect(c.read(subtitleSyncProvider), -750);
  });

  test('reset returns to zero and clears the stored offset', () {
    fakeAsync((async) {
      final store = InMemorySubtitlePrefsStore();
      final c = _c(FakePlaybackEngine(), store);
      addTearDown(c.dispose);
      c.read(currentVideoProvider.notifier).open(_session('ep1.mkv'));

      c.read(subtitleSyncProvider.notifier).nudge(4);
      async.elapse(const Duration(milliseconds: 200));
      c.read(subtitleSyncProvider.notifier).reset();
      async.elapse(const Duration(milliseconds: 200));

      expect(c.read(subtitleSyncProvider), 0);
      expect(store.forKey('ep1.mkv'), isNull);
    });
  });

  test('flush applies a pending nudge immediately instead of losing it', () async {
    final engine = FakePlaybackEngine();
    final c = _c(engine, InMemorySubtitlePrefsStore());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('ep1.mkv'));

    c.read(subtitleSyncProvider.notifier).nudge(2);
    await c.read(subtitleSyncProvider.notifier).flush();
    expect(engine.subtitleDelays, [0.1]);
  });

  test('nudging with no video open does nothing', () {
    final engine = FakePlaybackEngine();
    final c = _c(engine, InMemorySubtitlePrefsStore());
    addTearDown(c.dispose);
    c.read(subtitleSyncProvider.notifier).nudge(1);
    expect(c.read(subtitleSyncProvider), 0);
    expect(engine.subtitleDelays, isEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/player/tracks/subtitle_sync_controller_test.dart`
Expected: FAIL — URI doesn't exist. If `fake_async` is not resolvable, add it under `dev_dependencies:` in `pubspec.yaml` as `fake_async: ^1.3.1` and run `flutter pub get` (it ships transitively with `flutter_test`, so check before adding).

- [ ] **Step 3: Write the implementation**

```dart
// lib/player/tracks/subtitle_sync_controller.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/playback_engine.dart';
import '../open/video_source.dart';
import 'subtitle_delay.dart';
import 'subtitle_prefs_store.dart';

/// How long the controller waits for the taps to stop before telling mpv.
///
/// `setSubtitleDelay` is a synchronous mpv call on the UI thread — the same
/// one wedged at the top of the open background-hang ANR trace. Holding the
/// taps here means a dozen presses cost one native call, not a dozen.
const subtitleSyncDebounce = Duration(milliseconds: 120);

/// The subtitle offset, in milliseconds, for the video that is open.
///
/// The state is authoritative for the UI and updates on every tap; mpv and
/// Hive are brought in line on the trailing edge of [subtitleSyncDebounce].
class SubtitleSyncNotifier extends Notifier<int> {
  Timer? _debounce;

  @override
  int build() {
    ref.onDispose(() => _debounce?.cancel());
    final session = ref.watch(currentVideoProvider);
    if (session == null) return 0;
    return ref.read(subtitlePrefsStoreProvider)
            .forKey(session.resumeKey)
            ?.delayMs ??
        0;
  }

  void nudge(int steps) {
    if (ref.read(currentVideoProvider) == null) return;
    state = nudgeSubtitleDelay(state, steps);
    _schedule();
  }

  void reset() {
    if (ref.read(currentVideoProvider) == null) return;
    state = 0;
    _schedule();
  }

  /// Applies whatever is pending right now. Called when the HUD closes so the
  /// last nudge is never dropped on the floor.
  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    await _apply();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(subtitleSyncDebounce, () {
      _debounce = null;
      _apply();
    });
  }

  Future<void> _apply() async {
    final session = ref.read(currentVideoProvider);
    if (session == null) return;
    final ms = state;
    await ref.read(playbackEngineProvider).setSubtitleDelay(ms / 1000);
    final store = ref.read(subtitlePrefsStoreProvider);
    final existing = store.forKey(session.resumeKey) ?? const VideoSubtitlePrefs();
    await store.put(session.resumeKey, existing.copyWith(delayMs: ms));
  }
}

final subtitleSyncProvider =
    NotifierProvider<SubtitleSyncNotifier, int>(SubtitleSyncNotifier.new);
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/player/tracks/subtitle_sync_controller_test.dart && flutter analyze --no-pub`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/player/tracks/subtitle_sync_controller.dart test/player/tracks/subtitle_sync_controller_test.dart
git commit -m "feat(subtitles): debounced sync controller"
```

---

### Task 5: The sync HUD

**Files:**
- Create: `lib/ui/player/tracks/subtitle_sync_hud.dart`
- Modify: `lib/ui/player/player_screen.dart` (add `const Positioned.fill(child: SubtitleSyncHud())` to the overlay list at ~line 597, after `AutoplayOverlay()`)
- Test: `test/ui/player/subtitle_sync_hud_test.dart`

**Interfaces:**
- Consumes: `subtitleSyncProvider`, `formatSubtitleDelay`, `subtitleMeter`, `subtitleDelaySegments` (Tasks 1, 4)
- Produces: `subtitleSyncVisibleProvider` (`NotifierProvider<SubtitleSyncVisibleNotifier, bool>`) with `show()` and `hide()` · `class SubtitleSyncHud extends ConsumerStatefulWidget` (const constructor)

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/player/subtitle_sync_hud_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/subtitle_prefs_store.dart';
import 'package:kivo_player/player/tracks/subtitle_sync_controller.dart';
import 'package:kivo_player/ui/player/tracks/subtitle_sync_hud.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _c(FakePlaybackEngine engine) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    playbackEngineProvider.overrideWithValue(engine),
    subtitlePrefsStoreProvider.overrideWithValue(InMemorySubtitlePrefsStore()),
  ]);
}

Future<void> _pump(WidgetTester tester, ProviderContainer c) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: SubtitleSyncHud())),
      ),
    );

void main() {
  testWidgets('stays out of the way until it is shown', (tester) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    await _pump(tester, c);
    expect(find.text('0,00 s'), findsNothing);
  });

  testWidgets('shows the offset and moves it a step per tap', (tester) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(VideoSession(
        playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0));
    await _pump(tester, c);

    c.read(subtitleSyncVisibleProvider.notifier).show();
    await tester.pump();
    expect(find.text('0,00 s'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('subtitle-sync-plus')));
    await tester.pump();
    expect(find.text('+0,05 s'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('subtitle-sync-minus')));
    await tester.tap(find.byKey(const ValueKey('subtitle-sync-minus')));
    await tester.pump();
    expect(find.text('−0,05 s'), findsOneWidget);
  });

  testWidgets('tapping the value resets it to zero', (tester) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(VideoSession(
        playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0));
    await _pump(tester, c);
    c.read(subtitleSyncVisibleProvider.notifier).show();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('subtitle-sync-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('subtitle-sync-value')));
    await tester.pump();
    expect(find.text('0,00 s'), findsOneWidget);
  });

  testWidgets('hides itself after the idle timeout', (tester) async {
    final c = await _c(FakePlaybackEngine());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(VideoSession(
        playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0));
    await _pump(tester, c);
    c.read(subtitleSyncVisibleProvider.notifier).show();
    await tester.pump();
    expect(find.text('0,00 s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(c.read(subtitleSyncVisibleProvider), false);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/player/subtitle_sync_hud_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/ui/player/tracks/subtitle_sync_hud.dart
import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../player/tracks/subtitle_delay.dart';
import '../../../player/tracks/subtitle_sync_controller.dart';

/// Whether the sync capsule is on screen. Opened from the ⋮ menu and from the
/// track picker; closes itself after [_idleTimeout].
class SubtitleSyncVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void show() => state = true;
  void hide() => state = false;
}

final subtitleSyncVisibleProvider =
    NotifierProvider<SubtitleSyncVisibleNotifier, bool>(
        SubtitleSyncVisibleNotifier.new);

const _idleTimeout = Duration(seconds: 3);

/// Top-centre because subtitles render at the bottom: the whole point is
/// watching the subtitle move while you nudge it, so the control must not sit
/// on top of it.
class SubtitleSyncHud extends ConsumerStatefulWidget {
  const SubtitleSyncHud({super.key});

  @override
  ConsumerState<SubtitleSyncHud> createState() => _SubtitleSyncHudState();
}

class _SubtitleSyncHudState extends ConsumerState<SubtitleSyncHud> {
  Timer? _idle;

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  void _touch() {
    _idle?.cancel();
    _idle = Timer(_idleTimeout, () {
      if (!mounted) return;
      // Push the last nudge through before the capsule goes away.
      ref.read(subtitleSyncProvider.notifier).flush();
      ref.read(subtitleSyncVisibleProvider.notifier).hide();
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(subtitleSyncVisibleProvider);
    if (!visible) {
      _idle?.cancel();
      _idle = null;
      return const SizedBox.shrink();
    }
    _idle ??= Timer(_idleTimeout, () {
      if (!mounted) return;
      ref.read(subtitleSyncProvider.notifier).flush();
      ref.read(subtitleSyncVisibleProvider.notifier).hide();
    });

    final ms = ref.watch(subtitleSyncProvider);
    final accent = Color(ref.watch(settingsProvider.select((s) => s.accentColor)));
    final sync = ref.read(subtitleSyncProvider.notifier);

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StepButton(
                  key: const ValueKey('subtitle-sync-minus'),
                  glyph: '−',
                  onStep: () { sync.nudge(-1); _touch(); },
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  key: const ValueKey('subtitle-sync-value'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () { sync.reset(); _touch(); },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatSubtitleDelay(ms),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 5),
                      _Meter(delayMs: ms, accent: accent),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _StepButton(
                  key: const ValueKey('subtitle-sync-plus'),
                  glyph: '+',
                  onStep: () { sync.nudge(1); _touch(); },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Long-press repeats, so cuadrar a two-second offset is one gesture.
class _StepButton extends StatefulWidget {
  const _StepButton({super.key, required this.glyph, required this.onStep});
  final String glyph;
  final VoidCallback onStep;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  Timer? _repeat;

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onStep,
      onLongPressStart: (_) {
        widget.onStep();
        _repeat = Timer.periodic(
            const Duration(milliseconds: 90), (_) => widget.onStep());
      },
      onLongPressEnd: (_) {
        _repeat?.cancel();
        _repeat = null;
      },
      child: SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: Text(widget.glyph,
              style: const TextStyle(color: Colors.white, fontSize: 18)),
        ),
      ),
    );
  }
}

/// Kivo's signature meter, lit outward from a brighter centre tick.
class _Meter extends StatelessWidget {
  const _Meter({required this.delayMs, required this.accent});
  final int delayMs;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final m = subtitleMeter(delayMs);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < subtitleDelaySegments; i++)
          Container(
            width: 5,
            height: i == m.centerIndex ? 9 : 5,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            color: i == m.centerIndex
                ? (delayMs == 0
                    ? Colors.white.withValues(alpha: 0.42)
                    : accent)
                : (i >= m.firstLit && i <= m.lastLit
                    ? accent
                    : Colors.white.withValues(alpha: 0.18)),
          ),
      ],
    );
  }
}
```

In `lib/ui/player/player_screen.dart`, add the import and insert into the overlay list right after `const Positioned.fill(child: AutoplayOverlay()),`:

```dart
                        const Positioned.fill(child: SubtitleSyncHud()),
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/ui/player/subtitle_sync_hud_test.dart && flutter analyze --no-pub`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/tracks/subtitle_sync_hud.dart lib/ui/player/player_screen.dart test/ui/player/subtitle_sync_hud_test.dart
git commit -m "feat(subtitles): the sync HUD"
```

---

### Task 6: Open the HUD from the ⋮ menu and the track picker

**Files:**
- Modify: `lib/ui/player/more/more_menu.dart` (a third `_MenuRow` after the A-B loop row)
- Modify: `lib/ui/player/tracks/track_picker.dart` (a row in `_TracksSection`, subtitles only)
- Test: `test/ui/player/subtitle_sync_entry_test.dart`

**Interfaces:**
- Consumes: `subtitleSyncVisibleProvider` (Task 5), `subtitleSyncProvider` (Task 4)
- Produces: nothing new.

Both hosts are bottom sheets and both must `Navigator.pop` **before** showing the HUD — a sheet left up covers the subtitle and defeats the placement.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/player/subtitle_sync_entry_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/tracks/subtitle_prefs_store.dart';
import 'package:kivo_player/ui/player/more/more_menu.dart';
import 'package:kivo_player/ui/player/tracks/subtitle_sync_hud.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('the more menu opens the sync HUD and closes itself', (tester) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
      subtitlePrefsStoreProvider.overrideWithValue(InMemorySubtitlePrefsStore()),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Consumer(builder: (ctx, ref, _) {
          return Scaffold(body: Builder(builder: (b) {
            return TextButton(
              onPressed: () => showMoreMenu(b, ref),
              child: const Text('open'),
            );
          }));
        }),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Sincronizar subtítulos'), findsOneWidget);

    await tester.tap(find.text('Sincronizar subtítulos'));
    await tester.pumpAndSettle();

    expect(c.read(subtitleSyncVisibleProvider), true);
    // The sheet is gone — it would otherwise cover the subtitle being adjusted.
    expect(find.text('Bucle A-B'), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/player/subtitle_sync_entry_test.dart`
Expected: FAIL — `Expected: exactly one matching candidate / Actual: _TextFinder:<zero widgets with text "Sincronizar subtítulos">`

- [ ] **Step 3: Write the implementation**

In `lib/ui/player/more/more_menu.dart`, add the import for `subtitle_sync_hud.dart`, and after the A-B loop `_MenuRow` (before the closing `],`):

```dart
                const SizedBox(height: 8),
                _MenuRow(
                  icon: Icons.compare_arrows_rounded,
                  title: 'Sincronizar subtítulos',
                  subtitle: 'Ajustar el desfase mientras se reproduce',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    ref.read(subtitleSyncVisibleProvider.notifier).show();
                  },
                ),
```

In `lib/ui/player/tracks/track_picker.dart`, inside `_TracksSection`'s children list, immediately after the `if (tracks.isNotEmpty) ...[ ... ]` block, add a subtitles-only row. It is gated on there being an active subtitle track — with subs off, `sub-delay` changes nothing and an inert control reads as broken:

```dart
            if (isSubtitles && current != null) ...[
              const _SectionEyebrow(label: 'Sincronía'),
              _TrackCard(
                icon: Icons.compare_arrows_rounded,
                label: 'Sincronizar subtítulos',
                sublabel: 'Ajustar el desfase mientras se reproduce',
                active: false,
                accent: accent,
                onTap: () {
                  Navigator.of(context).pop();
                  ref.read(subtitleSyncVisibleProvider.notifier).show();
                },
              ),
            ],
```

Add the matching import to `track_picker.dart`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/ui/player/subtitle_sync_entry_test.dart && flutter analyze --no-pub`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/more/more_menu.dart lib/ui/player/tracks/track_picker.dart test/ui/player/subtitle_sync_entry_test.dart
git commit -m "feat(subtitles): open the sync HUD from the menu and the picker"
```

---

### Task 7: Apply the stored prefs when a video opens

**Files:**
- Modify: `lib/player/tracks/apply_default_tracks.dart`
- Modify: `lib/ui/player/player_screen.dart:280` (pass the new argument)
- Modify: `lib/player/autoplay/autoplay_coordinator.dart:77` (pass the new argument)
- Test: `test/player/tracks/apply_default_tracks_prefs_test.dart`

**Interfaces:**
- Consumes: `VideoSubtitlePrefs`, `SubtitlePrefsStore` (Task 3) · `PlaybackEngine.setSubtitleDelay` (Task 2)
- Produces: `applyDefaultTracks` gains a required named parameter `SubtitlePrefsStore subtitlePrefs`.

**Both call sites must be updated.** Missing the autoplay one means the prefs apply on a manual open but silently not when the queue advances — exactly the kind of half-working the user would report as flaky.

- [ ] **Step 1: Write the failing test**

```dart
// test/player/tracks/apply_default_tracks_prefs_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/apply_default_tracks.dart';
import 'package:kivo_player/player/tracks/subtitle_prefs_store.dart';
import '../../fakes/fakes.dart';

VideoSession _session() => VideoSession(
    playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0);

void main() {
  test('a remembered offset is applied on open', () async {
    final engine = FakePlaybackEngine();
    final store = InMemorySubtitlePrefsStore();
    await store.put('ep1.mkv', const VideoSubtitlePrefs(delayMs: -750));

    applyDefaultTracks(
      engine: engine,
      settings: KivoSettings.defaults(),
      session: _session(),
      subtitleFinder: FakeSubtitleFinder(),
      subtitlePrefs: store,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(engine.subtitleDelays, [-0.75]);
  });

  test('a remembered subtitle file is loaded before the offset', () async {
    final engine = FakePlaybackEngine();
    final store = InMemorySubtitlePrefsStore();
    await store.put('ep1.mkv',
        const VideoSubtitlePrefs(delayMs: 500, subtitlePath: '/subs/ep1.srt'));

    applyDefaultTracks(
      engine: engine,
      settings: KivoSettings.defaults(),
      session: _session(),
      subtitleFinder: FakeSubtitleFinder(),
      subtitlePrefs: store,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(engine.externalSubtitles.single, '/subs/ep1.srt');
    expect(engine.subtitleDelays, [0.5]);
  });

  test('a video with nothing remembered touches neither', () async {
    final engine = FakePlaybackEngine();
    applyDefaultTracks(
      engine: engine,
      settings: KivoSettings.defaults(),
      session: _session(),
      subtitleFinder: FakeSubtitleFinder(),
      subtitlePrefs: InMemorySubtitlePrefsStore(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(engine.subtitleDelays, isEmpty);
    expect(engine.externalSubtitles, isEmpty);
  });
}
```

If `FakePlaybackEngine` has no `externalSubtitles` list, add one in `test/fakes/fakes.dart` alongside `subtitleDelays`, recording the `uri` in `setExternalSubtitle`. If `FakeSubtitleFinder` does not exist, add a minimal one returning `const []` from `findNear`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/player/tracks/apply_default_tracks_prefs_test.dart`
Expected: FAIL — `No named parameter with the name 'subtitlePrefs'`

- [ ] **Step 3: Write the implementation**

In `lib/player/tracks/apply_default_tracks.dart`, add the import for `subtitle_prefs_store.dart`, add the parameter, and append the prefs block at the end of the async body (after the existing external-subtitle `else if`):

```dart
void applyDefaultTracks({
  required PlaybackEngine engine,
  required KivoSettings settings,
  required VideoSession session,
  required SubtitleFinder subtitleFinder,
  required SubtitlePrefsStore subtitlePrefs,
}) {
```

```dart
    // What this video remembers wins over the language defaults above: the
    // user picked it for this file specifically. The file is loaded before the
    // offset so the delay lands on the track it was measured against.
    final prefs = subtitlePrefs.forKey(session.resumeKey);
    if (prefs != null) {
      final path = prefs.subtitlePath;
      if (path != null) {
        try {
          await engine.setExternalSubtitle(path);
        } catch (_) {
          // The copy may be gone (storage cleared). Degrade to the embedded
          // tracks already applied rather than failing the open.
        }
      }
      if (prefs.delayMs != 0) {
        await engine.setSubtitleDelay(prefs.delayMs / 1000);
      }
    }
```

Then update both call sites to pass `subtitlePrefs: ref.read(subtitlePrefsStoreProvider),` — `lib/ui/player/player_screen.dart:280` and `lib/player/autoplay/autoplay_coordinator.dart:77`, adding the import to each.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/player/tracks/ && flutter analyze --no-pub`
Expected: PASS. Analyze catches any call site left unupdated.

- [ ] **Step 5: Commit**

```bash
git add lib/player/tracks/apply_default_tracks.dart lib/ui/player/player_screen.dart lib/player/autoplay/autoplay_coordinator.dart test/player/tracks/apply_default_tracks_prefs_test.dart test/fakes/fakes.dart
git commit -m "feat(subtitles): restore the remembered subtitle setup on open"
```

---

### Task 8: Keep the prefs consistent on rename and delete

**Files:**
- Modify: `lib/player/library/video_actions.dart` (`delete`, `rename`, `deleteMany`)
- Test: `test/player/library/video_actions_subtitle_prefs_test.dart`

**Interfaces:**
- Consumes: `subtitlePrefsStoreProvider`, `SubtitlePrefsStore.rename/remove` (Task 3)
- Produces: nothing new.

The controller's own doc comment says it keeps the name-keyed stores consistent. This store is now one of them; without these hooks, renaming an episode silently loses its sync and the user blames the sync feature.

- [ ] **Step 1: Write the failing test**

```dart
// test/player/library/video_actions_subtitle_prefs_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/player/library/video_actions.dart';
import 'package:kivo_player/player/tracks/subtitle_prefs_store.dart';
import '../../fakes/fakes.dart';

const _v = VideoItem(
    id: '1', uri: 'content://1', name: 'ep1.mkv', folder: 'Series',
    durationMs: 1000, sizeBytes: 10, dateAddedMs: 0);

void main() {
  test('rename carries the subtitle prefs to the new name', () async {
    final store = InMemorySubtitlePrefsStore();
    await store.put('ep1.mkv', const VideoSubtitlePrefs(delayMs: 500));
    final c = await buildVideoActionsContainer(
        subtitlePrefs: store, renameTo: 'ep1-renamed.mkv');
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).rename(_v, 'ep1-renamed');

    expect(store.forKey('ep1.mkv'), isNull);
    expect(store.forKey('ep1-renamed.mkv')!.delayMs, 500);
  });

  test('delete clears the subtitle prefs', () async {
    final store = InMemorySubtitlePrefsStore();
    await store.put('ep1.mkv', const VideoSubtitlePrefs(delayMs: 500));
    final c = await buildVideoActionsContainer(subtitlePrefs: store);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).delete(_v);

    expect(store.forKey('ep1.mkv'), isNull);
  });

  test('deleteMany clears the prefs of every video in the batch', () async {
    final store = InMemorySubtitlePrefsStore();
    await store.put('ep1.mkv', const VideoSubtitlePrefs(delayMs: 500));
    final c = await buildVideoActionsContainer(subtitlePrefs: store);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).deleteMany([_v]);

    expect(store.forKey('ep1.mkv'), isNull);
  });
}
```

Look at the existing `test/player/library/` tests for how a `VideoActionsController` container is currently assembled (fake `mediaFileOpsProvider`, `resumeServiceProvider`, `playedStoreProvider`, `mediaIndexerProvider`). Write `buildVideoActionsContainer` as a local helper in this test file following that same pattern, adding `subtitlePrefsStoreProvider.overrideWithValue(subtitlePrefs)`. Do not invent provider names — copy them from the existing test.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/player/library/video_actions_subtitle_prefs_test.dart`
Expected: FAIL — the prefs survive the rename / delete.

- [ ] **Step 3: Write the implementation**

In `lib/player/library/video_actions.dart`, add the import for `../tracks/subtitle_prefs_store.dart` and three calls:

In `delete`, after `await _ref.read(playedStoreProvider).remove(v.name);`:

```dart
    await _ref.read(subtitlePrefsStoreProvider).remove(v.name);
```

In `rename`, after `await _ref.read(resumeServiceProvider).rename(v.name, newName);`:

```dart
    await _ref.read(subtitlePrefsStoreProvider).rename(v.name, newName);
```

In `deleteMany`, inside the `for (final v in videos)` loop:

```dart
      await _ref.read(subtitlePrefsStoreProvider).remove(v.name);
```

Also update the class doc comment so the next reader knows there are now three name-keyed stores, not two.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/player/library/ && flutter analyze --no-pub`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/player/library/video_actions.dart test/player/library/video_actions_subtitle_prefs_test.dart
git commit -m "feat(subtitles): migrate and clear subtitle prefs with the file"
```

---

### Task 9: KV-502 and the subtitle file importer

Copies a picked subtitle into app-owned storage, because file-picker paths go stale between launches.

**Files:**
- Modify: `lib/core/errors/kivo_failure.dart` (new `KivoOp.subtitleLoad` + catalog entry)
- Create: `lib/player/tracks/subtitle_importer.dart`
- Test: `test/player/tracks/subtitle_importer_test.dart`

**Interfaces:**
- Consumes: `errorLogProvider`, `KivoFailure`, `KivoOp` (existing)
- Produces: `KivoOp.subtitleLoad` (`KV-502`) · `abstract class SubtitleImporter { Future<String?> importFor(String videoKey, String sourcePath); }` · `FileSubtitleImporter(Directory targetDir, {ErrorLog? log})` · `subtitleImporterProvider`

- [ ] **Step 1: Write the failing test**

```dart
// test/player/tracks/subtitle_importer_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/player/tracks/subtitle_importer.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('kivo_subs'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('KV-502 exists for a failed subtitle load', () {
    expect(kivoErrorCatalog[KivoOp.subtitleLoad]!.code, 'KV-502');
  });

  test('copies the picked file into app storage, keyed by the video', () async {
    final src = File('${tmp.path}/whatever.srt')..writeAsStringSync('1\n');
    final dest = Directory('${tmp.path}/subs');
    final importer = FileSubtitleImporter(dest);

    final path = await importer.importFor('ep1.mkv', src.path);

    expect(path, isNotNull);
    expect(File(path!).existsSync(), true);
    expect(path.endsWith('.srt'), true);
    expect(path.contains('ep1.mkv'), true);
    expect(File(path).readAsStringSync(), '1\n');
  });

  test('re-importing for the same video replaces the previous copy', () async {
    final dest = Directory('${tmp.path}/subs');
    final importer = FileSubtitleImporter(dest);
    final a = File('${tmp.path}/a.srt')..writeAsStringSync('A');
    final b = File('${tmp.path}/b.srt')..writeAsStringSync('B');

    await importer.importFor('ep1.mkv', a.path);
    final second = await importer.importFor('ep1.mkv', b.path);

    expect(File(second!).readAsStringSync(), 'B');
    expect(dest.listSync().length, 1);
  });

  test('a missing source degrades to null instead of throwing', () async {
    final importer = FileSubtitleImporter(Directory('${tmp.path}/subs'));
    expect(await importer.importFor('ep1.mkv', '${tmp.path}/ghost.srt'), isNull);
  });

  test('discard removes the copy', () async {
    final dest = Directory('${tmp.path}/subs');
    final importer = FileSubtitleImporter(dest);
    final src = File('${tmp.path}/a.srt')..writeAsStringSync('A');
    final path = await importer.importFor('ep1.mkv', src.path);

    await importer.discard(path!);
    expect(File(path).existsSync(), false);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/player/tracks/subtitle_importer_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

In `lib/core/errors/kivo_failure.dart`, add `subtitleLoad,` to the `KivoOp` enum after `openVideo,` and the catalog entry after the `openVideo` one:

```dart
  KivoOp.subtitleLoad:
      (code: 'KV-502', message: 'No pudimos cargar el subtítulo'),
```

```dart
// lib/player/tracks/subtitle_importer.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_log.dart';
import '../../core/errors/kivo_failure.dart';

/// Takes a subtitle the user picked and returns a path that will still be
/// valid next week.
abstract class SubtitleImporter {
  /// Returns the app-owned path, or null when the import failed.
  Future<String?> importFor(String videoKey, String sourcePath);

  Future<void> discard(String importedPath);
}

/// The file picker hands back paths into a cache the OS is free to clear, so
/// storing one and re-reading it on the next launch is a broken association
/// waiting to happen. Subtitles are kilobytes — copying is what makes the
/// association actually survive.
class FileSubtitleImporter implements SubtitleImporter {
  FileSubtitleImporter(this.targetDir, {ErrorLog? log}) : _log = log;

  final Directory targetDir;
  final ErrorLog? _log;

  @override
  Future<String?> importFor(String videoKey, String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!source.existsSync()) {
        throw FileSystemException('subtitle source is gone', sourcePath);
      }
      if (!targetDir.existsSync()) targetDir.createSync(recursive: true);

      final dot = sourcePath.lastIndexOf('.');
      final ext = dot == -1 ? '.srt' : sourcePath.substring(dot);
      // Keyed by video, so one video owns at most one imported subtitle and a
      // re-import can never pile up orphans.
      for (final existing in targetDir.listSync()) {
        if (existing is File &&
            existing.path.split(Platform.pathSeparator).last.startsWith('$videoKey.')) {
          existing.deleteSync();
        }
      }
      final dest = File('${targetDir.path}${Platform.pathSeparator}$videoKey$ext');
      await source.copy(dest.path);
      return dest.path;
    } catch (e) {
      _log?.record(KivoFailure(KivoOp.subtitleLoad, e));
      debugPrint('FileSubtitleImporter.importFor failed: $e');
      return null;
    }
  }

  @override
  Future<void> discard(String importedPath) async {
    try {
      final f = File(importedPath);
      if (f.existsSync()) await f.delete();
    } catch (e) {
      debugPrint('FileSubtitleImporter.discard failed: $e');
    }
  }
}

final subtitleImporterProvider = Provider<SubtitleImporter>((ref) {
  throw UnimplementedError('subtitleImporterProvider must be overridden');
});
```

In `lib/main.dart`, build it from the same external files dir the FileProvider already maps, and override the provider:

```dart
  final subsDir = Directory('${(await getExternalStorageDirectory())!.path}/subs');
```

```dart
      subtitleImporterProvider
          .overrideWithValue(FileSubtitleImporter(subsDir, log: errorLog)),
```

Add `import 'dart:io';` to `main.dart` if it is not already there.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/player/tracks/subtitle_importer_test.dart test/core/errors/ && flutter analyze --no-pub`
Expected: PASS. The error-catalog integrity test must still pass — it checks every `KivoOp` has an entry.

- [ ] **Step 5: Commit**

```bash
git add lib/core/errors/kivo_failure.dart lib/player/tracks/subtitle_importer.dart lib/main.dart test/player/tracks/subtitle_importer_test.dart
git commit -m "feat(subtitles): KV-502 and the subtitle file importer"
```

- [ ] **Step 6: Write the failing test for discarding an orphaned copy**

Task 8 cleared the *prefs* on delete but left the imported `.srt` on disk
forever. Now that the importer exists, close that.

```dart
// append to test/player/library/video_actions_subtitle_prefs_test.dart
  test('deleting a video also deletes its imported subtitle copy', () async {
    final store = InMemorySubtitlePrefsStore();
    await store.put('ep1.mkv',
        const VideoSubtitlePrefs(subtitlePath: '/app/subs/ep1.mkv.srt'));
    final importer = FakeSubtitleImporter();
    final c = await buildVideoActionsContainer(
        subtitlePrefs: store, importer: importer);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).delete(_v);

    expect(importer.discarded, ['/app/subs/ep1.mkv.srt']);
  });

  test('a video with no imported copy discards nothing', () async {
    final store = InMemorySubtitlePrefsStore();
    await store.put('ep1.mkv', const VideoSubtitlePrefs(delayMs: 500));
    final importer = FakeSubtitleImporter();
    final c = await buildVideoActionsContainer(
        subtitlePrefs: store, importer: importer);
    addTearDown(c.dispose);

    await c.read(videoActionsProvider).delete(_v);

    expect(importer.discarded, isEmpty);
  });
```

Add `FakeSubtitleImporter` to `test/fakes/fakes.dart` (Task 10 reuses it from
there):

```dart
class FakeSubtitleImporter implements SubtitleImporter {
  /// What [importFor] hands back; set to null to simulate a failed copy.
  String? result = '/app/subs/ep1.mkv.srt';
  final List<(String, String)> imported = [];
  final List<String> discarded = [];

  @override
  Future<String?> importFor(String videoKey, String sourcePath) async {
    imported.add((videoKey, sourcePath));
    return result;
  }

  @override
  Future<void> discard(String importedPath) async => discarded.add(importedPath);
}
```

Extend `buildVideoActionsContainer` with an `importer` parameter overriding
`subtitleImporterProvider`.

Run: `flutter test test/player/library/video_actions_subtitle_prefs_test.dart`
Expected: FAIL — `importer.discarded` is empty.

- [ ] **Step 7: Wire the discard into the delete paths**

In `lib/player/library/video_actions.dart`, add the `subtitle_importer.dart`
import and a private helper, then call it from `delete` and from the
`deleteMany` loop, **before** removing the prefs entry — the stored path is
where the file name comes from:

```dart
  /// Deletes the app-owned subtitle copy, if this video had one. Rename does
  /// NOT need this: the stored path is absolute and stays valid, and the next
  /// import for that video cleans up after itself.
  Future<void> _discardImportedSubtitle(String key) async {
    final path = _ref.read(subtitlePrefsStoreProvider).forKey(key)?.subtitlePath;
    if (path == null) return;
    await _ref.read(subtitleImporterProvider).discard(path);
  }
```

In `delete`, immediately before `await _ref.read(subtitlePrefsStoreProvider).remove(v.name);`:

```dart
    await _discardImportedSubtitle(v.name);
```

And the same line inside the `deleteMany` loop, before its `remove` call.

- [ ] **Step 8: Run the tests to verify they pass**

Run: `flutter test test/player/library/ test/player/tracks/ && flutter analyze --no-pub`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/player/library/video_actions.dart test/player/library/video_actions_subtitle_prefs_test.dart test/fakes/fakes.dart
git commit -m "feat(subtitles): delete the imported subtitle copy with its video"
```

---

### Task 10: "Cargar subtítulo…" in the track picker

**Files:**
- Modify: `lib/ui/player/tracks/track_picker.dart` (`_TracksSection`, subtitles only)
- Create: `lib/player/tracks/manual_subtitle_controller.dart`
- Test: `test/player/tracks/manual_subtitle_controller_test.dart`

**Interfaces:**
- Consumes: `SubtitleImporter` (Task 9) · `SubtitlePrefsStore`, `VideoSubtitlePrefs` (Task 3) · `PlaybackEngine.setExternalSubtitle` (existing) · `currentVideoProvider`
- Produces: `class ManualSubtitleController { Future<bool> load(String pickedPath); }` · `manualSubtitleProvider`

The picker itself stays thin: it opens `file_picker` and hands the path to the controller, which is what the test drives.

- [ ] **Step 1: Write the failing test**

```dart
// test/player/tracks/manual_subtitle_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/manual_subtitle_controller.dart';
import 'package:kivo_player/player/tracks/subtitle_importer.dart';
import 'package:kivo_player/player/tracks/subtitle_prefs_store.dart';
import '../../fakes/fakes.dart'; // FakeSubtitleImporter lives here, added in Task 9

ProviderContainer _c(FakePlaybackEngine engine, FakeSubtitleImporter importer,
        SubtitlePrefsStore store) =>
    ProviderContainer(overrides: [
      playbackEngineProvider.overrideWithValue(engine),
      subtitleImporterProvider.overrideWithValue(importer),
      subtitlePrefsStoreProvider.overrideWithValue(store),
    ]);

void main() {
  test('a picked subtitle is copied, applied and remembered', () async {
    final engine = FakePlaybackEngine();
    final store = InMemorySubtitlePrefsStore();
    final c = _c(engine, FakeSubtitleImporter(), store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(VideoSession(
        playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0));

    expect(await c.read(manualSubtitleProvider).load('/picked/foo.srt'), true);

    expect(engine.externalSubtitles.single, '/app/subs/ep1.mkv.srt');
    expect(store.forKey('ep1.mkv')!.subtitlePath, '/app/subs/ep1.mkv.srt');
  });

  test('a failed copy applies nothing and remembers nothing', () async {
    final engine = FakePlaybackEngine();
    final store = InMemorySubtitlePrefsStore();
    final c = _c(engine, FakeSubtitleImporter()..result = null, store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(VideoSession(
        playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0));

    expect(await c.read(manualSubtitleProvider).load('/picked/foo.srt'), false);
    expect(engine.externalSubtitles, isEmpty);
    expect(store.forKey('ep1.mkv'), isNull);
  });

  test('an existing delay survives loading a new subtitle', () async {
    final store = InMemorySubtitlePrefsStore();
    await store.put('ep1.mkv', const VideoSubtitlePrefs(delayMs: 400));
    final c = _c(FakePlaybackEngine(), FakeSubtitleImporter(), store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(VideoSession(
        playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0));

    await c.read(manualSubtitleProvider).load('/picked/foo.srt');
    expect(store.forKey('ep1.mkv')!.delayMs, 400);
  });

  test('loading with no video open is refused', () async {
    final c = _c(FakePlaybackEngine(), FakeSubtitleImporter(), InMemorySubtitlePrefsStore());
    addTearDown(c.dispose);
    expect(await c.read(manualSubtitleProvider).load('/picked/foo.srt'), false);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/player/tracks/manual_subtitle_controller_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/player/tracks/manual_subtitle_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/playback_engine.dart';
import '../open/video_source.dart';
import 'subtitle_importer.dart';
import 'subtitle_prefs_store.dart';

/// Loads a subtitle the user picked by hand: copy it somewhere durable, hand
/// it to mpv, and remember it for this video.
class ManualSubtitleController {
  ManualSubtitleController(this._ref);
  final Ref _ref;

  /// Returns false when nothing was loaded — the caller shows KV-502.
  Future<bool> load(String pickedPath) async {
    final session = _ref.read(currentVideoProvider);
    if (session == null) return false;

    final stored = await _ref
        .read(subtitleImporterProvider)
        .importFor(session.resumeKey, pickedPath);
    if (stored == null) return false;

    await _ref.read(playbackEngineProvider).setExternalSubtitle(stored);

    final store = _ref.read(subtitlePrefsStoreProvider);
    final existing =
        store.forKey(session.resumeKey) ?? const VideoSubtitlePrefs();
    // copyWith, not a fresh record: a delay already cuadrado for this video
    // must survive swapping the subtitle file.
    await store.put(session.resumeKey, existing.copyWith(subtitlePath: stored));
    return true;
  }
}

final manualSubtitleProvider =
    Provider<ManualSubtitleController>((ref) => ManualSubtitleController(ref));
```

In `lib/ui/player/tracks/track_picker.dart`, inside `_TracksSection`, add a subtitles-only row at the foot of the children list (after the empty-state `if`):

```dart
            if (isSubtitles) ...[
              const _SectionEyebrow(label: 'Desde tu dispositivo'),
              _TrackCard(
                icon: Icons.upload_file_outlined,
                label: 'Cargar subtítulo…',
                sublabel: 'Elegir un archivo .srt, .ass o .vtt',
                active: false,
                accent: accent,
                onTap: () => _pickManualSubtitle(context, ref),
              ),
            ],
```

and the handler as a method on `_TracksSection`:

```dart
  Future<void> _pickManualSubtitle(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt', 'sub'],
    );
    final path = result?.files.single.path;
    if (path == null) return; // cancelled
    final ok = await ref.read(manualSubtitleProvider).load(path);
    navigator.pop();
    if (!ok) showFailureSnackBar(context, KivoOp.subtitleLoad);
    messenger.hideCurrentSnackBar();
  }
```

Add imports: `package:file_picker/file_picker.dart`, `manual_subtitle_controller.dart`, `../../widgets/failure_snack_bar.dart`, `../../../core/errors/kivo_failure.dart`. Check `showFailureSnackBar`'s real signature in `lib/ui/widgets/failure_snack_bar.dart` and match it — do not guess. If it needs a context that survives the `pop`, capture the player's context before popping.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/player/tracks/ && flutter analyze --no-pub`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/player/tracks/manual_subtitle_controller.dart lib/ui/player/tracks/track_picker.dart test/player/tracks/manual_subtitle_controller_test.dart
git commit -m "feat(subtitles): load a subtitle file by hand"
```

---

### Task 11: `excludedFolders` and the filtered library index

**Files:**
- Modify: `lib/core/settings/kivo_settings.dart` (all six insertion points)
- Modify: `lib/player/library/media_index.dart` (add `libraryIndexProvider`)
- Modify: `lib/player/library/continue_watching.dart:14`, `lib/ui/home/folder_screen.dart:45`, `lib/ui/home/library_screen.dart:132`, `lib/ui/home/library_screen.dart:261`, `lib/ui/home/widgets/selection_bottom_bar.dart:23`
- Test: `test/player/library/library_index_test.dart`, `test/core/settings/settings_service_test.dart` (add a round-trip case)

**Interfaces:**
- Consumes: `mediaIndexProvider` (existing), `settingsProvider`
- Produces: `KivoSettings.excludedFolders` (`List<String>`, default `const []`) · `libraryIndexProvider` (`Provider<AsyncValue<List<VideoItem>>>`)

**Do not** filter inside `MediaIndexNotifier.build()`. Watching settings there re-runs `build()` and publishes a data-less `AsyncLoading`, which is exactly the spinner the notifier's own comment says throws the user back to the top of the list.

`lib/ui/home/library_screen.dart:432` (`refresh()`) and `lib/player/library/video_actions.dart:61` **stay on `mediaIndexProvider`** — they drive the scan itself rather than reading it. `lib/vault/vault_providers.dart` also stays: it invalidates the raw index.

- [ ] **Step 1: Write the failing test**

```dart
// test/player/library/library_index_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/library/media_index.dart';
import '../../fakes/fakes.dart';

VideoItem _v(String name, String folder) => VideoItem(
    id: name, uri: 'content://$name', name: name, folder: folder,
    durationMs: 1000, sizeBytes: 10, dateAddedMs: 0);

Future<ProviderContainer> _c(List<VideoItem> videos) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(videos)),
    mediaPermissionImplProvider.overrideWithValue(FakeMediaPermission()),
  ]);
}

void main() {
  test('with nothing excluded the library is the whole index', () async {
    final c = await _c([_v('a.mkv', 'Series'), _v('b.mp4', 'WhatsApp')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    expect(c.read(libraryIndexProvider).value!.length, 2);
  });

  test('an excluded folder disappears from the library', () async {
    final c = await _c([_v('a.mkv', 'Series'), _v('b.mp4', 'WhatsApp')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final s = c.read(settingsProvider);
    await c.read(settingsProvider.notifier)
        .set(s.copyWith(excludedFolders: const ['WhatsApp']));

    final visible = c.read(libraryIndexProvider).value!;
    expect(visible.map((v) => v.folder), ['Series']);
    // The raw scan is untouched — nothing was deleted.
    expect(c.read(mediaIndexProvider).value!.length, 2);
  });

  test('an exclusion for a folder that no longer exists is harmless', () async {
    final c = await _c([_v('a.mkv', 'Series')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final s = c.read(settingsProvider);
    await c.read(settingsProvider.notifier)
        .set(s.copyWith(excludedFolders: const ['Ghost']));

    expect(c.read(libraryIndexProvider).value!.length, 1);
  });

  test('the loading and error states pass straight through', () async {
    final c = await _c([_v('a.mkv', 'Series')]);
    addTearDown(c.dispose);
    expect(c.read(libraryIndexProvider).isLoading, true);
  });
}
```

If `FakeMediaIndexer` / `FakeMediaPermission` do not exist with those exact names, copy whatever the existing library tests use (check `test/player/library/`) rather than inventing them.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/player/library/library_index_test.dart`
Expected: FAIL — `libraryIndexProvider` and `excludedFolders` undefined.

- [ ] **Step 3: Write the implementation**

In `lib/core/settings/kivo_settings.dart`, all six insertion points, following the existing `List<double> speedPresets` field as the pattern for a list:

```dart
  /// Bucket display names hidden from the library. A view filter only — the
  /// files are never touched, unlike the vault.
  final List<String> excludedFolders;
```
```dart
    required this.excludedFolders,
```
```dart
        excludedFolders: const [],
```
```dart
    List<String>? excludedFolders,
```
```dart
      excludedFolders: excludedFolders ?? this.excludedFolders,
```
```dart
        'excludedFolders': excludedFolders,
```
```dart
      excludedFolders: (m['excludedFolders'] as List?)?.cast<String>() ??
          d.excludedFolders,
```

In `lib/player/library/media_index.dart`, append:

```dart
/// The index minus the folders the user hid — what every library surface must
/// read.
///
/// Deliberately a derived provider rather than a filter inside
/// [MediaIndexNotifier]: watching settings there would re-run `build()` and
/// publish a data-less `AsyncLoading`, which unmounts the scroll view. This
/// re-filters with no rescan and no loading flash.
final libraryIndexProvider = Provider<AsyncValue<List<VideoItem>>>((ref) {
  final raw = ref.watch(mediaIndexProvider);
  final excluded =
      ref.watch(settingsProvider.select((s) => s.excludedFolders)).toSet();
  if (excluded.isEmpty) return raw;
  return raw.whenData(
      (videos) => videos.where((v) => !excluded.contains(v.folder)).toList());
});
```

Add the `settingsProvider` import.

Then switch each read-only consumer from `mediaIndexProvider` to `libraryIndexProvider`:
`continue_watching.dart:14` · `folder_screen.dart:45` · `library_screen.dart:132` · `library_screen.dart:261` · `selection_bottom_bar.dart:23`.

Leave `library_screen.dart:266` (`ref.invalidate(mediaIndexProvider)`), `library_screen.dart:432` (`refresh()`), `video_actions.dart:61` and `vault_providers.dart` pointing at the raw provider.

Add to `test/core/settings/settings_service_test.dart`:

```dart
  test('excludedFolders defaults to empty and round-trips', () async {
    final store = InMemorySettingsStore();
    final svc = await SettingsService.load(store);
    expect(svc.current.excludedFolders, isEmpty);
    await svc.update(svc.current.copyWith(excludedFolders: const ['WhatsApp']));
    final reloaded = await SettingsService.load(store);
    expect(reloaded.current.excludedFolders, ['WhatsApp']);
  });
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test && flutter analyze --no-pub`
Expected: PASS — run the FULL suite here; this task rewires shared providers and a missed consumer shows up as a failure elsewhere.

- [ ] **Step 5: Commit**

```bash
git add lib/core/settings/kivo_settings.dart lib/player/library/media_index.dart lib/player/library/continue_watching.dart lib/ui/home/folder_screen.dart lib/ui/home/library_screen.dart lib/ui/home/widgets/selection_bottom_bar.dart test/player/library/library_index_test.dart test/core/settings/settings_service_test.dart
git commit -m "feat(library): folders can be excluded from the index"
```

---

### Task 12: Hiding a folder, and getting it back

**Files:**
- Create: `lib/ui/home/widgets/folder_options_sheet.dart`
- Create: `lib/ui/settings/sections/hidden_folders_section.dart`
- Modify: `lib/ui/home/widgets/folder_grid.dart` (long-press on the card)
- Modify: `lib/ui/settings/sections/general_section.dart` (a nav row)
- Test: `test/ui/home/folder_exclusion_test.dart`

**Interfaces:**
- Consumes: `KivoSettings.excludedFolders`, `libraryIndexProvider` (Task 11)
- Produces: `showFolderOptionsSheet(BuildContext, WidgetRef, String folder)` · `class HiddenFoldersSection extends ConsumerWidget`

Folder cards have no `⋮` and no long-press today, so the gesture is free. Copy must say the files are untouched, or users who know the vault will assume this moves them.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/home/folder_exclusion_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/ui/home/widgets/folder_options_sheet.dart';
import 'package:kivo_player/ui/settings/sections/hidden_folders_section.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _c() async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  return ProviderContainer(
      overrides: [settingsServiceProvider.overrideWithValue(svc)]);
}

void main() {
  testWidgets('hiding a folder stores it and says the files are untouched',
      (tester) async {
    final c = await _c();
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Consumer(builder: (ctx, ref, _) => Scaffold(
              body: Builder(
                builder: (b) => TextButton(
                  onPressed: () => showFolderOptionsSheet(b, ref, 'WhatsApp'),
                  child: const Text('open'),
                ),
              ),
            )),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se borra ni se mueve nada'), findsOneWidget);

    await tester.tap(find.text('Ocultar de la biblioteca'));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).excludedFolders, ['WhatsApp']);
    expect(find.text('Deshacer'), findsOneWidget);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).excludedFolders, isEmpty);
  });

  testWidgets('hiding the same folder twice does not duplicate it', (tester) async {
    final c = await _c();
    addTearDown(c.dispose);
    final s = c.read(settingsProvider);
    await c.read(settingsProvider.notifier)
        .set(s.copyWith(excludedFolders: const ['WhatsApp']));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Consumer(builder: (ctx, ref, _) => Scaffold(
              body: Builder(
                builder: (b) => TextButton(
                  onPressed: () => showFolderOptionsSheet(b, ref, 'WhatsApp'),
                  child: const Text('open'),
                ),
              ),
            )),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ocultar de la biblioteca'));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).excludedFolders, ['WhatsApp']);
  });

  testWidgets('the settings screen lists hidden folders and restores them',
      (tester) async {
    final c = await _c();
    addTearDown(c.dispose);
    final s = c.read(settingsProvider);
    await c.read(settingsProvider.notifier)
        .set(s.copyWith(excludedFolders: const ['WhatsApp', 'Telegram']));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: HiddenFoldersSection()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Telegram'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('restore-WhatsApp')));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).excludedFolders, ['Telegram']);
  });

  testWidgets('with nothing hidden the settings screen explains itself',
      (tester) async {
    final c = await _c();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: HiddenFoldersSection()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('No has ocultado'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/home/folder_exclusion_test.dart`
Expected: FAIL — URIs don't exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/ui/home/widgets/folder_options_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';

/// Long-press on a folder card. Hiding is a view filter, and the copy has to
/// say so — someone who knows the vault will otherwise assume this moves files.
Future<void> showFolderOptionsSheet(
    BuildContext context, WidgetRef ref, String folder) {
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final cs = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(folder,
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: Icon(Icons.visibility_off_outlined,
                  color: cs.onSurfaceVariant),
              title: const Text('Ocultar de la biblioteca'),
              subtitle: const Text(
                  'No se borra ni se mueve nada: solo deja de aparecer en Kivo.'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final s = ref.read(settingsProvider);
                if (s.excludedFolders.contains(folder)) return;
                await ref.read(settingsProvider.notifier).set(s.copyWith(
                    excludedFolders: [...s.excludedFolders, folder]));
                messenger.showSnackBar(SnackBar(
                  content: Text('$folder oculta'),
                  action: SnackBarAction(
                    label: 'Deshacer',
                    onPressed: () {
                      final now = ref.read(settingsProvider);
                      ref.read(settingsProvider.notifier).set(now.copyWith(
                          excludedFolders: now.excludedFolders
                              .where((f) => f != folder)
                              .toList()));
                    },
                  ),
                ));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
```

```dart
// lib/ui/settings/sections/hidden_folders_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';

class HiddenFoldersSection extends ConsumerWidget {
  const HiddenFoldersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final hidden = ref.watch(settingsProvider.select((s) => s.excludedFolders));

    return Scaffold(
      appBar: AppBar(title: const Text('Carpetas ocultas')),
      body: hidden.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No has ocultado ninguna carpeta.\n'
                  'Mantén pulsada una carpeta en Videos para ocultarla.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                for (final folder in hidden)
                  ListTile(
                    leading:
                        Icon(Icons.folder_off_outlined, color: cs.onSurfaceVariant),
                    title: Text(folder),
                    trailing: TextButton(
                      key: ValueKey('restore-$folder'),
                      onPressed: () {
                        final s = ref.read(settingsProvider);
                        ref.read(settingsProvider.notifier).set(s.copyWith(
                            excludedFolders: s.excludedFolders
                                .where((f) => f != folder)
                                .toList()));
                      },
                      child: const Text('Mostrar'),
                    ),
                  ),
              ],
            ),
    );
  }
}
```

In `lib/ui/home/widgets/folder_grid.dart`, wrap the card's `PressBounce` so a long-press opens the sheet. `PressBounce` may not expose `onLongPress` — if it does not, wrap it in a `GestureDetector`:

```dart
        return GestureDetector(
          onLongPress: () => showFolderOptionsSheet(context, ref, name),
          child: PressBounce(
            onTap: () => onOpenFolder(name, items),
            child: _FolderCard(name: name, items: items, accent: accent),
          ),
        );
```

In `lib/ui/settings/sections/general_section.dart`, add a `SettingNavRow` inside an existing `SettingsCard` (match the surrounding rows' shape — check `SettingNavRow`'s real parameters in `lib/ui/settings/widgets/setting_tiles.dart`):

```dart
            SettingNavRow(
              icon: Icons.folder_off_outlined,
              title: 'Carpetas ocultas',
              subtitle: 'Carpetas que no aparecen en tu biblioteca',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const HiddenFoldersSection())),
            ),
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test && flutter analyze --no-pub`
Expected: PASS, full suite.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/home/widgets/folder_options_sheet.dart lib/ui/settings/sections/hidden_folders_section.dart lib/ui/home/widgets/folder_grid.dart lib/ui/settings/sections/general_section.dart test/ui/home/folder_exclusion_test.dart
git commit -m "feat(library): hide folders from the library and restore them"
```

---

## Final checklist

- [ ] `flutter test` — full suite green.
- [ ] `flutter analyze --no-pub` — down to the 3 pre-existing infos.
- [ ] `cd android && ./gradlew :app:compileDebugKotlin` — no new warnings (this plan touches no Kotlin, so this is a regression check only).
- [ ] No `Co-Authored-By` trailer on any commit in the branch.
- [ ] **Device check** (nothing here is provable in a unit test): a subtitle nudged +0,5 s visibly shifts; the offset survives closing and reopening the video; a hand-picked `.srt` survives a full app restart; renaming that video keeps both; a hidden folder disappears from Todo, Carpetas, the search results and "Continuar viendo" at once, and Deshacer brings it back.
- [ ] Bump `pubspec.yaml` to `1.6.0+2011`, tag `v1.6.0`, push the tag — the release workflow publishes the signed APKs.
