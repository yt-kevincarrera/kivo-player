# Bug 3 — Subtitle Panel + Forced-Default Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the subtitle panel showing an empty list until the switch is toggled, and the auto-default selecting a "forced" track that displays nothing.

**Architecture:** (a) The picker's `StreamBuilder`s get `initialData` from new engine snapshot getters (`currentSubtitleTracks`/`currentAudioTracks`/`currentSubtitleTrack`/`currentAudioTrack` off `_player.state`), so they never start empty when media_kit's non-replay broadcast stream already fired. (b) `selectSubtitleTrack` deprioritizes forced tracks via a `looksForced` title/language heuristic (media_kit doesn't expose mpv's `forced` flag).

**Tech Stack:** Flutter, Riverpod, media_kit, `flutter_test`.

## Global Constraints

- Do NOT modify media_kit (it doesn't surface mpv's `forced` flag — hence the heuristic).
- No new hardcoded colors; single configurable accent.
- Engine additions follow the interface pattern (`PlaybackEngine` + `MediaKitEngine` + `FakePlaybackEngine`).
- No `flutter run`. On module close: `flutter build apk --release`, then `adb install` to the Pixel 6 (device `24231FDF6006ST`; adb at `$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe`).
- Full suite stays green (`flutter test`), currently 389 tests.
- Subtitles stay ON by default (`subtitlesEnabledByDefault` default true); the fix changes WHICH track is auto-picked, not whether subs are enabled.

---

### Task 1: Deprioritize forced tracks in the default subtitle selection

**Files:**
- Modify: `lib/player/tracks/track_selection.dart`
- Test: `test/player/tracks/track_selection_test.dart` (create if absent; otherwise append)

**Interfaces:**
- Produces:
  - `bool looksForced(MediaTrack t)` — true if the track's title or language contains "forced" or "forzad" (case-insensitive).
  - `selectSubtitleTrack({required List<MediaTrack> tracks, required bool enabledByDefault, required String? preferredLanguage})` — unchanged signature; new behavior prefers non-forced tracks.

- [ ] **Step 1: Write the failing test**

Create/append `test/player/tracks/track_selection_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/tracks/track_selection.dart';

MediaTrack _t(String id, {String? title, String? lang, bool def = false}) =>
    MediaTrack(id: id, title: title, language: lang, isDefault: def);

void main() {
  test('looksForced matches forced/forzado in title or language', () {
    expect(looksForced(_t('1', title: 'Forzado')), true);
    expect(looksForced(_t('2', title: 'Forced (SDH)')), true);
    expect(looksForced(_t('3', lang: 'spa', title: 'Español')), false);
    expect(looksForced(_t('4', title: 'English')), false);
  });

  test('selectSubtitleTrack skips a forced default in favor of a full track', () {
    final tracks = [
      _t('f', title: 'forzado', lang: 'spa', def: true), // forced + default flag
      _t('s', title: 'Español', lang: 'spa'),
      _t('e', title: 'English', lang: 'eng'),
    ];
    final pick = selectSubtitleTrack(
        tracks: tracks, enabledByDefault: true, preferredLanguage: null);
    expect(pick?.id, 's'); // first non-forced, not the forced 'f'
  });

  test('preferredLanguage is honored, preferring non-forced within it', () {
    final tracks = [
      _t('ef', title: 'English Forced', lang: 'eng'),
      _t('e', title: 'English', lang: 'eng'),
      _t('s', title: 'Español', lang: 'spa'),
    ];
    final pick = selectSubtitleTrack(
        tracks: tracks, enabledByDefault: true, preferredLanguage: 'eng');
    expect(pick?.id, 'e');
  });

  test('all-forced falls back to the first track (better than nothing)', () {
    final tracks = [_t('f1', title: 'forzado'), _t('f2', title: 'forced')];
    final pick = selectSubtitleTrack(
        tracks: tracks, enabledByDefault: true, preferredLanguage: null);
    expect(pick?.id, 'f1');
  });

  test('disabled or empty → null', () {
    expect(selectSubtitleTrack(tracks: [_t('a')], enabledByDefault: false, preferredLanguage: null), isNull);
    expect(selectSubtitleTrack(tracks: const [], enabledByDefault: true, preferredLanguage: null), isNull);
  });
}
```

> If `track_selection_test.dart` already exists, append these tests inside its `main()` and reuse any existing `MediaTrack` builder.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/player/tracks/track_selection_test.dart`
Expected: FAIL — `looksForced` undefined, and the forced-skip test fails (current code returns `f`).

- [ ] **Step 3: Implement**

In `lib/player/tracks/track_selection.dart`, add `looksForced` and rewrite `selectSubtitleTrack` (leave `selectAudioTrack` and `languageFromFilename` unchanged):

```dart
/// Heuristic: media_kit doesn't expose mpv's `forced` flag, so treat a track as
/// forced when its title or language says so. Forced subtitle tracks only show
/// forced-narrative lines (often nothing), so they're a poor auto-default.
bool looksForced(MediaTrack t) {
  final s = '${t.title ?? ''} ${t.language ?? ''}'.toLowerCase();
  return s.contains('forced') || s.contains('forzad');
}

MediaTrack? selectSubtitleTrack({
  required List<MediaTrack> tracks,
  required bool enabledByDefault,
  required String? preferredLanguage,
}) {
  if (!enabledByDefault) return null;
  if (tracks.isEmpty) return null;
  if (preferredLanguage != null) {
    final byLang = tracks.where((t) => t.language == preferredLanguage).toList();
    if (byLang.isNotEmpty) return _preferNonForced(byLang);
  }
  return _preferNonForced(tracks);
}

/// Prefer non-forced tracks; within the chosen pool, a `default`-flagged track,
/// else the first. Falls back to the full list if every track looks forced.
MediaTrack _preferNonForced(List<MediaTrack> tracks) {
  final nonForced = tracks.where((t) => !looksForced(t)).toList();
  final pool = nonForced.isNotEmpty ? nonForced : tracks;
  for (final t in pool) {
    if (t.isDefault) return t;
  }
  return pool.first;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/player/tracks/track_selection_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/player/tracks/track_selection.dart test/player/tracks/track_selection_test.dart
git commit -m "fix(subs): deprioritize forced tracks in the default subtitle pick"
```

---

### Task 2: Engine snapshot getters for the current track lists + selection

**Files:**
- Modify: `lib/player/engine/playback_engine.dart`
- Modify: `lib/player/engine/media_kit_engine.dart`
- Modify: `test/fakes/fakes.dart` (`FakePlaybackEngine`)
- Test: `test/player/engine/fake_track_snapshot_test.dart`

**Interfaces:**
- Produces (on `PlaybackEngine`):
  - `List<MediaTrack> get currentSubtitleTracks;`
  - `List<MediaTrack> get currentAudioTracks;`
  - `MediaTrack? get currentSubtitleTrack;`
  - `MediaTrack? get currentAudioTrack;`
  - `FakePlaybackEngine`: settable backing fields `subtitleTracksValue`, `audioTracksValue` (List<MediaTrack>, default `[]`), `currentSubtitleTrackValue`, `currentAudioTrackValue` (MediaTrack?, default null) exposed via those getters.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import '../../fakes/fakes.dart';

void main() {
  test('FakePlaybackEngine exposes configurable current-track snapshots', () {
    final e = FakePlaybackEngine();
    addTearDown(e.dispose);
    expect(e.currentSubtitleTracks, isEmpty);
    expect(e.currentSubtitleTrack, isNull);

    const spa = MediaTrack(id: 's', title: 'Español', language: 'spa');
    e.subtitleTracksValue = [spa];
    e.currentSubtitleTrackValue = spa;
    expect(e.currentSubtitleTracks, [spa]);
    expect(e.currentSubtitleTrack, spa);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/player/engine/fake_track_snapshot_test.dart`
Expected: FAIL — getters/fields not defined.

- [ ] **Step 3: Add the getters to the interface**

In `lib/player/engine/playback_engine.dart`, inside `abstract class PlaybackEngine`, near the track streams:

```dart
  /// Current track snapshots (what `_player.state` holds right now), used as
  /// `initialData` for the picker so it never shows empty when the underlying
  /// broadcast stream already emitted before the panel subscribed.
  List<MediaTrack> get currentSubtitleTracks;
  List<MediaTrack> get currentAudioTracks;
  MediaTrack? get currentSubtitleTrack; // null = off
  MediaTrack? get currentAudioTrack;
```

- [ ] **Step 4: Implement in `MediaKitEngine`**

In `lib/player/engine/media_kit_engine.dart`, mirror the stream mappers exactly (they reuse `_audioToMedia`/`_subtitleToMedia`):

```dart
  @override
  List<MediaTrack> get currentAudioTracks => _player.state.tracks.audio
      .where((a) => a.id != 'auto' && a.id != 'no')
      .map(_audioToMedia)
      .toList();

  @override
  List<MediaTrack> get currentSubtitleTracks => _player.state.tracks.subtitle
      .map(_subtitleToMedia)
      .whereType<MediaTrack>()
      .toList();

  @override
  MediaTrack? get currentAudioTrack => _audioToMedia(_player.state.track.audio);

  @override
  MediaTrack? get currentSubtitleTrack => _subtitleToMedia(_player.state.track.subtitle);
```

(These match `audioTracksStream`/`subtitleTracksStream`/`currentAudioTrackStream`/`currentSubtitleTrackStream` respectively — `_player.state.tracks`/`_player.state.track` are already used by `setAudioTrack`/`setSubtitleTrack`.)

- [ ] **Step 5: Implement in `FakePlaybackEngine`**

In `test/fakes/fakes.dart`, add to `FakePlaybackEngine`:

```dart
  List<MediaTrack> subtitleTracksValue = [];
  List<MediaTrack> audioTracksValue = [];
  MediaTrack? currentSubtitleTrackValue;
  MediaTrack? currentAudioTrackValue;

  @override
  List<MediaTrack> get currentSubtitleTracks => subtitleTracksValue;
  @override
  List<MediaTrack> get currentAudioTracks => audioTracksValue;
  @override
  MediaTrack? get currentSubtitleTrack => currentSubtitleTrackValue;
  @override
  MediaTrack? get currentAudioTrack => currentAudioTrackValue;
```

- [ ] **Step 6: Run test + analyze + full suite**

Run: `flutter test test/player/engine/fake_track_snapshot_test.dart`
Expected: PASS.
Run: `flutter analyze lib/player/engine/playback_engine.dart lib/player/engine/media_kit_engine.dart`
Expected: No issues.
Run: `flutter test`
Expected: All green (the new abstract getters compile because both `MediaKitEngine` and `FakePlaybackEngine` implement them; no other `PlaybackEngine` impl exists).

- [ ] **Step 7: Commit**

```bash
git add lib/player/engine/playback_engine.dart lib/player/engine/media_kit_engine.dart test/fakes/fakes.dart test/player/engine/fake_track_snapshot_test.dart
git commit -m "feat(engine): current-track snapshot getters for the picker"
```

---

### Task 3: Picker uses the snapshots as `initialData`

**Files:**
- Modify: `lib/ui/player/tracks/track_picker.dart`
- Test: `test/ui/player/tracks/track_picker_initial_test.dart`

**Interfaces:**
- Consumes: `engine.currentSubtitleTracks`/`currentAudioTracks`/`currentSubtitleTrack`/`currentAudioTrack` (Task 2).

**Context:** The body is two nested `StreamBuilder`s (list + current) at `track_picker.dart:77-96`. They start with `snapshot.data == null` → empty list until a future emission. Add `initialData` so the current snapshot shows immediately.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/tracks/track_picker.dart';
import '../../../fakes/fakes.dart';

void main() {
  testWidgets('subtitle picker shows tracks from the snapshot without any stream emission', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    engine.subtitleTracksValue = const [
      MediaTrack(id: 's', title: 'Español', language: 'spa'),
      MediaTrack(id: 'e', title: 'English', language: 'eng'),
    ];
    engine.currentSubtitleTrackValue = const MediaTrack(id: 's', title: 'Español', language: 'spa');
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/x.mkv', displayName: 'x.mkv', queue: ['/v/x.mkv'], index: 0),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(body: Builder(builder: (ctx) {
          return ElevatedButton(onPressed: () => showSubtitlePicker(ctx, ref: c.read), child: const Text('go'));
        })),
      ),
    ));
    // NOTE: adjust the showSubtitlePicker invocation to its real signature
    // (verify in track_picker.dart) — the assertion is what matters:
    // the two track titles are visible with NO stream emission having occurred.
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Español'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });
}
```

> The exact way to open the sheet (`showSubtitlePicker`'s signature / how it reads `ref` + `engine`) must be confirmed against `track_picker.dart`; adjust the harness accordingly. If mounting the modal sheet proves impractical in a widget test, SKIP this test with an explicit note and rely on Task 4's device check — do NOT write a test that asserts nothing. The load-bearing change (initialData) is small and verified on-device regardless.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/player/tracks/track_picker_initial_test.dart`
Expected: FAIL — titles not found (StreamBuilder starts empty without initialData).

- [ ] **Step 3: Add `initialData` to both StreamBuilders**

In `lib/ui/player/tracks/track_picker.dart`, the body block (~lines 77-96) becomes:

```dart
    final body = showStyle
        ? const _StyleSection()
        : StreamBuilder<List<MediaTrack>>(
            stream: widget.isSubtitles ? engine.subtitleTracksStream : engine.audioTracksStream,
            initialData: widget.isSubtitles ? engine.currentSubtitleTracks : engine.currentAudioTracks,
            builder: (context, tracksSnap) {
              final tracks = tracksSnap.data ?? const <MediaTrack>[];
              return StreamBuilder<MediaTrack?>(
                stream: widget.isSubtitles
                    ? engine.currentSubtitleTrackStream
                    : engine.currentAudioTrackStream,
                initialData: widget.isSubtitles ? engine.currentSubtitleTrack : engine.currentAudioTrack,
                builder: (context, currentSnap) {
                  final current = currentSnap.data;
                  return _TracksSection(
                    isSubtitles: widget.isSubtitles,
                    tracks: tracks,
                    current: current,
                    session: session,
                    engine: engine,
                  );
                },
              );
            },
          );
```

(Only the two `initialData:` lines are added; everything else is unchanged. `engine` is already in scope in this build method.)

- [ ] **Step 4: Run test + analyze**

Run: `flutter test test/ui/player/tracks/track_picker_initial_test.dart`
Expected: PASS (or documented-skip per Step 1's note).
Run: `flutter analyze lib/ui/player/tracks/track_picker.dart`
Expected: No issues.

- [ ] **Step 5: Full suite + commit**

Run: `flutter test`
Expected: All green.

```bash
git add lib/ui/player/tracks/track_picker.dart test/ui/player/tracks/track_picker_initial_test.dart
git commit -m "fix(subs): seed the track picker from the current snapshot (no empty list)"
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

  - Open a video with embedded subtitles (forzado / spa / eng): the tracks panel shows the full list **immediately** on first open — no need to toggle the switch — and again on every subsequent open/close.
  - By default a **full track** (spa or eng) is selected and subtitles are **visible** (not the silent forced track); the top-bar icon reflects that real track.
  - Manually picking forzado / spa / eng still works; toggling the "show subtitles" switch off then on respects the (non-forced) selection.
  - A video with NO subtitles: panel correctly shows an empty list, icon inactive (no regression).
  - A video whose only subtitle is forced: it still gets selected (fallback) — acceptable.

This task has no commit (verification only). Report results; a failed item becomes a fix task.

---

## Self-Review notes

- **Spec coverage:** §1 initialData fix→Tasks 2-3; §2 forced-deprioritization→Task 1; testing→Task 1 (pure, thorough) + Task 2 (fake getters) + Task 3 (picker, may skip-with-note) + Task 4 device.
- **Type consistency:** `looksForced(MediaTrack)`, `selectSubtitleTrack({tracks, enabledByDefault, preferredLanguage})` (unchanged signature), engine getters `currentSubtitleTracks`/`currentAudioTracks`/`currentSubtitleTrack`/`currentAudioTrack`, fake fields `subtitleTracksValue`/`audioTracksValue`/`currentSubtitleTrackValue`/`currentAudioTrackValue` — consistent across tasks.
- **Snapshot getters mirror the streams exactly** (same filters/mappers), so the picker's `initialData` and its live stream agree — no flicker/mismatch when the first real emission arrives.
- **Task 3 test** may be impractical to mount (modal sheet + providers); the plan explicitly permits a documented skip with device verification, since the `initialData` change is a two-line, low-risk edit. Task 1 (the behavior-critical forced logic) is fully unit-tested.
