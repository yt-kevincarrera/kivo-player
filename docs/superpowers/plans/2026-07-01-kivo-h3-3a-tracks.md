# Kivo H3/3a Tracks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Activate the player's disabled "Subtítulos"/"Audio" buttons — track selection (embedded + folder-discovered external subtitles), a "show subtitles by default unless turned off" policy with remembered language preference, and real subtitle styling (size/color/background) via libmpv properties.

**Architecture:** Five sequential tasks, each depending on the previous. Task 1 extends the `PlaybackEngine` abstraction with a track model + media_kit implementation. Task 2 adds settings fields and pure track-selection/filename-parsing logic (no Flutter/media_kit deps, fully unit-testable). Task 3 adds native external-subtitle discovery (Kotlin + Dart interface) and a `folder` field on `VideoSession`. Task 4 wires auto-selection + style application into `PlayerScreen`. Task 5 builds the picker UI and activates the top-bar buttons.

**Tech Stack:** Flutter, Riverpod, media_kit (libmpv) ^1.1.11 (resolved 1.2.6), Kotlin/Android (MediaStore.Files).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-01-kivo-h3-3a-tracks-design.md`.
- `PlaybackEngine`'s public API never leaks media_kit types (`AudioTrack`/`SubtitleTrack`/`Tracks`) — only the project's own `MediaTrack`.
- Subtitles show by default whenever a video has them, UNLESS the user's last explicit choice was "off" (persisted, sticky across videos). A remembered language preference is applied when it matches an available track.
- External subtitle discovery only for videos opened from the library (a known MediaStore folder) — never for file-picker/share-intent opens.
- Subtitle styling applies via libmpv's `sub-font-size`/`sub-color`/`sub-back-color` properties with `sub-ass-override=force`, so it overrides even ASS-styled embedded tracks.
- `flutter analyze` clean + `flutter test` green before each commit. Do not push. Native (Kotlin) and `MediaKitEngine`'s real mapping are device-verified, not unit-tested (matches the project's existing pattern for other native/plugin wrappers) — only the injectable/fake-testable layers get automated tests.

---

### Task 1: `MediaTrack` model + `PlaybackEngine` track/style API + `MediaKitEngine` implementation

**Files:**
- Modify: `lib/player/engine/playback_engine.dart`
- Modify: `lib/player/engine/media_kit_engine.dart`
- Modify: `test/fakes/fakes.dart` (extend `FakePlaybackEngine`)
- Test: `test/player/engine/media_track_test.dart` (new — the `MediaTrack` value type only; the engine wiring itself is exercised indirectly by Task 4's tests via the fake)

**Interfaces:**
- Produces: `class MediaTrack {String id, String? title, String? language, bool isDefault}` (value-equality by `id`); `PlaybackEngine` additions: `Stream<List<MediaTrack>> audioTracksStream`, `Stream<List<MediaTrack>> subtitleTracksStream`, `Stream<MediaTrack?> currentAudioTrackStream`, `Stream<MediaTrack?> currentSubtitleTrackStream` (null = off), `Future<void> setAudioTrack(String id)`, `Future<void> setSubtitleTrack(String? id)` (null = turn off; `id` must come from `subtitleTracksStream`), `Future<void> setExternalSubtitle(String uri, {String? title})` (for a file NOT in `subtitleTracksStream`, e.g. discovered in the folder), `Future<void> setSubtitleStyle({required double fontSize, required int textColorArgb, required int backgroundColorArgb})`.

- [ ] **Step 1: Read the current `lib/player/engine/playback_engine.dart` and `lib/player/engine/media_kit_engine.dart` in full** before editing (both are small, ~20-55 lines — confirm they still match: `PlaybackEngine` has `nativePlayer`, `positionStream`/`durationStream`/`playingStream`/`bufferingStream`, `createVideoController()`, `open`/`play`/`pause`/`seek`/`setRate`/`setVolume`/`dispose`; `MediaKitEngine` wraps a single `Player _player` and a cached `VideoController?`).

- [ ] **Step 2: Add `MediaTrack` and the new abstract members to `playback_engine.dart`.** Add near the top, before `abstract class PlaybackEngine`:
```dart
/// A single audio or subtitle track, decoupled from media_kit's own
/// [AudioTrack]/[SubtitleTrack] types so they never leak past this file.
class MediaTrack {
  final String id;
  final String? title;
  final String? language;
  final bool isDefault;
  const MediaTrack({
    required this.id,
    this.title,
    this.language,
    this.isDefault = false,
  });

  @override
  bool operator ==(Object other) => other is MediaTrack && other.id == id;
  @override
  int get hashCode => id.hashCode;
}
```
Then add these members inside `abstract class PlaybackEngine { ... }` (alongside the existing streams/methods):
```dart
  Stream<List<MediaTrack>> get audioTracksStream;
  Stream<List<MediaTrack>> get subtitleTracksStream;
  Stream<MediaTrack?> get currentAudioTrackStream;
  Stream<MediaTrack?> get currentSubtitleTrackStream; // null = off

  Future<void> setAudioTrack(String id);
  Future<void> setSubtitleTrack(String? id); // null = turn off
  Future<void> setExternalSubtitle(String uri, {String? title});

  Future<void> setSubtitleStyle({
    required double fontSize,
    required int textColorArgb,
    required int backgroundColorArgb,
  });
```

- [ ] **Step 3: Implement the new members in `media_kit_engine.dart`.** Media_kit's `Player` (confirmed by reading the installed package source, `media_kit-1.2.6`) exposes: `stream.tracks` (`Stream<Tracks>`, with `.audio`: `List<AudioTrack>`, `.subtitle`: `List<SubtitleTrack>`), `stream.track` (`Stream<Track>`, current selection, `.audio`/`.subtitle`), `state.tracks`/`state.track` (sync snapshot), `setAudioTrack(AudioTrack)`, `setSubtitleTrack(SubtitleTrack)`, and `SubtitleTrack.no()`/`SubtitleTrack.uri(uri, title: ...)` factories. Raw libmpv property access (`sub-font-size`, `sub-color`, `sub-back-color`, `sub-ass-override`) is on the concrete `NativePlayer` class (exported from `package:media_kit/media_kit.dart`) via `Future<void> setProperty(String property, String value)` — NOT on the abstract `PlatformPlayer` — so it needs a cast: `(_player.platform as NativePlayer?)?.setProperty(...)`.

Add these private helpers and public overrides to `MediaKitEngine`:
```dart
  MediaTrack _audioToMedia(AudioTrack t) => MediaTrack(
        id: t.id,
        title: t.title,
        language: t.language,
        isDefault: t.isDefault ?? false,
      );

  MediaTrack? _subtitleToMedia(SubtitleTrack t) {
    if (t.id == 'no') return null; // media_kit's own "off" sentinel
    return MediaTrack(
      id: t.id,
      title: t.title,
      language: t.language,
      isDefault: t.isDefault ?? false,
    );
  }

  @override
  Stream<List<MediaTrack>> get audioTracksStream =>
      _player.stream.tracks.map((t) => t.audio.map(_audioToMedia).toList());

  @override
  Stream<List<MediaTrack>> get subtitleTracksStream => _player.stream.tracks
      .map((t) => t.subtitle.map(_subtitleToMedia).whereType<MediaTrack>().toList());

  @override
  Stream<MediaTrack?> get currentAudioTrackStream =>
      _player.stream.track.map((t) => _audioToMedia(t.audio));

  @override
  Stream<MediaTrack?> get currentSubtitleTrackStream =>
      _player.stream.track.map((t) => _subtitleToMedia(t.subtitle));

  @override
  Future<void> setAudioTrack(String id) async {
    final track = _player.state.tracks.audio.firstWhere(
      (t) => t.id == id,
      orElse: () => AudioTrack.auto(),
    );
    await _player.setAudioTrack(track);
  }

  @override
  Future<void> setSubtitleTrack(String? id) async {
    if (id == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final track = _player.state.tracks.subtitle.firstWhere(
      (t) => t.id == id,
      orElse: () => SubtitleTrack.no(),
    );
    await _player.setSubtitleTrack(track);
  }

  @override
  Future<void> setExternalSubtitle(String uri, {String? title}) async {
    await _player.setSubtitleTrack(SubtitleTrack.uri(uri, title: title));
  }

  @override
  Future<void> setSubtitleStyle({
    required double fontSize,
    required int textColorArgb,
    required int backgroundColorArgb,
  }) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    await native.setProperty('sub-ass-override', 'force');
    await native.setProperty('sub-font-size', fontSize.toStringAsFixed(0));
    await native.setProperty('sub-color', _toMpvColor(textColorArgb));
    await native.setProperty('sub-back-color', _toMpvColor(backgroundColorArgb));
  }

  String _toMpvColor(int argb) {
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    String hex(int v) => v.toRadixString(16).padLeft(2, '0');
    return '#${hex(a)}${hex(r)}${hex(g)}${hex(b)}';
  }
```
`AudioTrack`, `SubtitleTrack`, `NativePlayer` are all exported from `package:media_kit/media_kit.dart`, which the file already imports (verify with `flutter analyze` — add the import only if missing; `media_kit_video.dart`'s import in this file is a different package).

- [ ] **Step 4: Extend `FakePlaybackEngine` in `test/fakes/fakes.dart`** so later tasks' tests can exercise the new surface without real media_kit:
```dart
  final _audioTracks = StreamController<List<MediaTrack>>.broadcast();
  final _subtitleTracks = StreamController<List<MediaTrack>>.broadcast();
  final _currentAudio = StreamController<MediaTrack?>.broadcast();
  final _currentSubtitle = StreamController<MediaTrack?>.broadcast();
  String? currentAudioTrackId;
  String? currentSubtitleTrackId; // null = off
  String? externalSubtitleUri;

  @override
  Stream<List<MediaTrack>> get audioTracksStream => _audioTracks.stream;
  @override
  Stream<List<MediaTrack>> get subtitleTracksStream => _subtitleTracks.stream;
  @override
  Stream<MediaTrack?> get currentAudioTrackStream => _currentAudio.stream;
  @override
  Stream<MediaTrack?> get currentSubtitleTrackStream => _currentSubtitle.stream;

  void emitAudioTracks(List<MediaTrack> t) => _audioTracks.add(t);
  void emitSubtitleTracks(List<MediaTrack> t) => _subtitleTracks.add(t);
  void emitCurrentAudio(MediaTrack? t) => _currentAudio.add(t);
  void emitCurrentSubtitle(MediaTrack? t) => _currentSubtitle.add(t);

  @override
  Future<void> setAudioTrack(String id) async {
    currentAudioTrackId = id;
  }

  @override
  Future<void> setSubtitleTrack(String? id) async {
    currentSubtitleTrackId = id;
  }

  @override
  Future<void> setExternalSubtitle(String uri, {String? title}) async {
    externalSubtitleUri = uri;
    currentSubtitleTrackId = uri;
  }

  double? lastSubtitleFontSize;
  int? lastSubtitleTextColorArgb;
  int? lastSubtitleBackgroundColorArgb;

  @override
  Future<void> setSubtitleStyle({
    required double fontSize,
    required int textColorArgb,
    required int backgroundColorArgb,
  }) async {
    lastSubtitleFontSize = fontSize;
    lastSubtitleTextColorArgb = textColorArgb;
    lastSubtitleBackgroundColorArgb = backgroundColorArgb;
  }
```
Add `import 'package:kivo_player/player/engine/playback_engine.dart' show MediaTrack;` is unnecessary since `fakes.dart` already `import 'package:kivo_player/player/engine/playback_engine.dart';` (verify — it does, for `PlaybackEngine` itself). Also update `FakePlaybackEngine.dispose()` to close the 4 new stream controllers, alongside the existing `_pos`/`_dur`/`_playing`/`_buffering`.

- [ ] **Step 5: Write `test/player/engine/media_track_test.dart`** (the value type only — the engine mapping itself is device-verified since it needs real media_kit):
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';

void main() {
  test('MediaTrack equality is by id only', () {
    const a = MediaTrack(id: '1', title: 'A', language: 'en');
    const b = MediaTrack(id: '1', title: 'Different', language: 'es');
    const c = MediaTrack(id: '2', title: 'A', language: 'en');
    expect(a, b);
    expect(a, isNot(c));
    expect(a.hashCode, b.hashCode);
  });
}
```

- [ ] **Step 6: Run the tests to verify they fail, then implement until they pass.**

Run: `flutter test test/player/engine/media_track_test.dart -v`
Expected before Step 2: FAIL (`MediaTrack` undefined).
After Step 2: Expected PASS.

- [ ] **Step 7: Run the full suite and analyze.**

Run: `flutter analyze` — expect "No issues found!" (this will catch any `FakePlaybackEngine` member missing from the interface — every `PlaybackEngine` implementer must implement ALL abstract members, so a mistake here surfaces immediately as a compile error).
Run: `flutter test` — expect all tests pass (149 prior + 1 new).

- [ ] **Step 8: Commit**

```bash
git add lib/player/engine/playback_engine.dart lib/player/engine/media_kit_engine.dart test/fakes/fakes.dart test/player/engine/media_track_test.dart
git commit -m "feat: MediaTrack model + PlaybackEngine track/style API + MediaKitEngine impl"
```

---

### Task 2: `KivoSettings` fields + pure track-selection and filename-language logic

**Files:**
- Modify: `lib/core/settings/kivo_settings.dart`
- Create: `lib/player/tracks/track_selection.dart`
- Test: `test/player/tracks/track_selection_test.dart` (new)

**Interfaces:**
- Consumes (Task 1): `MediaTrack` (`lib/player/engine/playback_engine.dart`).
- Produces: `KivoSettings` fields `subtitlesEnabledByDefault` (`bool`, default `true`), `preferredSubtitleLanguage` (`String?`, default `null`), `preferredAudioLanguage` (`String?`, default `null`), `subtitleFontSize` (`double`, default `26.0`), `subtitleTextColor` (`int`, default `0xFFFFFFFF`), `subtitleBackgroundColor` (`int`, default `0xB3000000`); `MediaTrack? selectSubtitleTrack({required List<MediaTrack> tracks, required bool enabledByDefault, required String? preferredLanguage})`; `MediaTrack? selectAudioTrack({required List<MediaTrack> tracks, required String? preferredLanguage})`; `String? languageFromFilename(String filename)`.

- [ ] **Step 1: Add the 6 fields to `KivoSettings`.** Read the current file first (it has ~29 fields; the most recently added is `themeMode`/`librarySort` — mirror the SAME exact pattern in all 5 spots for EACH of the 6 new fields):
  1. Field declarations (after the last existing field, e.g. `librarySort`):
     ```dart
     final bool subtitlesEnabledByDefault;
     final String? preferredSubtitleLanguage;
     final String? preferredAudioLanguage;
     final double subtitleFontSize;
     final int subtitleTextColor;
     final int subtitleBackgroundColor; // ARGB, default is semi-opaque black
     ```
  2. Constructor: add `required this.subtitlesEnabledByDefault, required this.preferredSubtitleLanguage, required this.preferredAudioLanguage, required this.subtitleFontSize, required this.subtitleTextColor, required this.subtitleBackgroundColor,`.
  3. `defaults()`: add `subtitlesEnabledByDefault: true, preferredSubtitleLanguage: null, preferredAudioLanguage: null, subtitleFontSize: 26.0, subtitleTextColor: 0xFFFFFFFF, subtitleBackgroundColor: 0xB3000000,`.
  4. `copyWith`: add params `bool? subtitlesEnabledByDefault, String? preferredSubtitleLanguage, String? preferredAudioLanguage, double? subtitleFontSize, int? subtitleTextColor, int? subtitleBackgroundColor,` and in the returned `KivoSettings(...)`: `subtitlesEnabledByDefault: subtitlesEnabledByDefault ?? this.subtitlesEnabledByDefault, preferredSubtitleLanguage: preferredSubtitleLanguage ?? this.preferredSubtitleLanguage, preferredAudioLanguage: preferredAudioLanguage ?? this.preferredAudioLanguage, subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize, subtitleTextColor: subtitleTextColor ?? this.subtitleTextColor, subtitleBackgroundColor: subtitleBackgroundColor ?? this.subtitleBackgroundColor,`. (The `?? this.x` pattern means a preferred-language can never be reset back to `null` via `copyWith` once set — this is intentional: the app only ever WRITES a new language when the user picks a track with a known language, never clears it, so this limitation doesn't affect any real code path.)
  5. `toMap()`: add `'subtitlesEnabledByDefault': subtitlesEnabledByDefault, 'preferredSubtitleLanguage': preferredSubtitleLanguage, 'preferredAudioLanguage': preferredAudioLanguage, 'subtitleFontSize': subtitleFontSize, 'subtitleTextColor': subtitleTextColor, 'subtitleBackgroundColor': subtitleBackgroundColor,`.
  6. `fromMap()`: add `subtitlesEnabledByDefault: m['subtitlesEnabledByDefault'] ?? d.subtitlesEnabledByDefault, preferredSubtitleLanguage: m['preferredSubtitleLanguage'] ?? d.preferredSubtitleLanguage, preferredAudioLanguage: m['preferredAudioLanguage'] ?? d.preferredAudioLanguage, subtitleFontSize: (m['subtitleFontSize'] ?? d.subtitleFontSize).toDouble(), subtitleTextColor: m['subtitleTextColor'] ?? d.subtitleTextColor, subtitleBackgroundColor: m['subtitleBackgroundColor'] ?? d.subtitleBackgroundColor,`.

- [ ] **Step 2: Create `lib/player/tracks/track_selection.dart`.**
```dart
import '../engine/playback_engine.dart';

/// Picks which subtitle track (if any) should be active when a video opens.
/// Returns null for "no subtitle" — either because [enabledByDefault] is
/// false (the user's last explicit choice), or the video has no tracks.
MediaTrack? selectSubtitleTrack({
  required List<MediaTrack> tracks,
  required bool enabledByDefault,
  required String? preferredLanguage,
}) {
  if (!enabledByDefault) return null;
  if (tracks.isEmpty) return null;
  if (preferredLanguage != null) {
    for (final t in tracks) {
      if (t.language == preferredLanguage) return t;
    }
  }
  for (final t in tracks) {
    if (t.isDefault) return t;
  }
  return tracks.first;
}

/// Picks which audio track should be active. Unlike subtitles, audio has no
/// "off" state — returns null only when [tracks] is empty.
MediaTrack? selectAudioTrack({
  required List<MediaTrack> tracks,
  required String? preferredLanguage,
}) {
  if (tracks.isEmpty) return null;
  if (preferredLanguage != null) {
    for (final t in tracks) {
      if (t.language == preferredLanguage) return t;
    }
  }
  for (final t in tracks) {
    if (t.isDefault) return t;
  }
  return tracks.first;
}

/// Extracts a language code from a common external-subtitle filename
/// convention like "Movie.en.srt" or "Movie.spa.srt" — the segment right
/// before the extension, if it looks like a short (2-3 letter) language
/// code. Returns null if the filename doesn't follow this pattern.
String? languageFromFilename(String filename) {
  final parts = filename.split('.');
  if (parts.length < 3) return null; // need at least name.lang.ext
  final candidate = parts[parts.length - 2].toLowerCase();
  if (candidate.length < 2 || candidate.length > 3) return null;
  if (!RegExp(r'^[a-z]+$').hasMatch(candidate)) return null;
  return candidate;
}
```

- [ ] **Step 3: Write `test/player/tracks/track_selection_test.dart`.**
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/tracks/track_selection.dart';

const _en = MediaTrack(id: '1', title: 'English', language: 'en');
const _es = MediaTrack(id: '2', title: 'Español', language: 'es', isDefault: true);
const _fr = MediaTrack(id: '3', title: 'Français', language: 'fr');

void main() {
  test('KivoSettings subtitle/audio fields default correctly and round-trip', () {
    final d = KivoSettings.defaults();
    expect(d.subtitlesEnabledByDefault, true);
    expect(d.preferredSubtitleLanguage, isNull);
    expect(d.preferredAudioLanguage, isNull);
    expect(d.subtitleFontSize, 26.0);
    expect(d.subtitleTextColor, 0xFFFFFFFF);
    expect(d.subtitleBackgroundColor, 0xB3000000);

    final m = d
        .copyWith(
          subtitlesEnabledByDefault: false,
          preferredSubtitleLanguage: 'es',
          subtitleFontSize: 32.0,
        )
        .toMap();
    final back = KivoSettings.fromMap(m);
    expect(back.subtitlesEnabledByDefault, false);
    expect(back.preferredSubtitleLanguage, 'es');
    expect(back.subtitleFontSize, 32.0);
  });

  group('selectSubtitleTrack', () {
    test('returns null when disabled by default', () {
      expect(
        selectSubtitleTrack(tracks: [_en, _es], enabledByDefault: false, preferredLanguage: null),
        isNull,
      );
    });
    test('returns null when there are no tracks', () {
      expect(
        selectSubtitleTrack(tracks: const [], enabledByDefault: true, preferredLanguage: 'en'),
        isNull,
      );
    });
    test('prefers a track matching the preferred language', () {
      expect(
        selectSubtitleTrack(tracks: [_en, _es, _fr], enabledByDefault: true, preferredLanguage: 'fr'),
        _fr,
      );
    });
    test('falls back to the container default track when no language match', () {
      expect(
        selectSubtitleTrack(tracks: [_en, _es, _fr], enabledByDefault: true, preferredLanguage: 'de'),
        _es,
      );
    });
    test('falls back to the first track when nothing is marked default and no language match', () {
      expect(
        selectSubtitleTrack(tracks: [_en, _fr], enabledByDefault: true, preferredLanguage: 'de'),
        _en,
      );
    });
    test('shows a subtitle by default (enabled, no preference yet) via the default/first track', () {
      expect(
        selectSubtitleTrack(tracks: [_en, _es], enabledByDefault: true, preferredLanguage: null),
        _es, // _es is isDefault: true
      );
    });
  });

  group('selectAudioTrack', () {
    test('never returns null when tracks exist, even with no language match', () {
      expect(
        selectAudioTrack(tracks: [_en, _fr], preferredLanguage: 'de'),
        _en,
      );
    });
    test('prefers a track matching the preferred language', () {
      expect(
        selectAudioTrack(tracks: [_en, _es, _fr], preferredLanguage: 'es'),
        _es,
      );
    });
  });

  group('languageFromFilename', () {
    test('extracts a 2-letter code before the extension', () {
      expect(languageFromFilename('Movie.en.srt'), 'en');
    });
    test('extracts a 3-letter code before the extension', () {
      expect(languageFromFilename('Movie.spa.srt'), 'spa');
    });
    test('returns null when there is no language segment', () {
      expect(languageFromFilename('Movie.srt'), isNull);
    });
    test('returns null when the segment before the extension is not a short alpha code', () {
      expect(languageFromFilename('My.Movie.2024.srt'), isNull);
    });
  });
}
```

- [ ] **Step 4: Run the tests to verify they fail, then implement until they pass.**

Run: `flutter test test/player/tracks/track_selection_test.dart -v`
Expected before Steps 1-2: FAIL (fields/file don't exist).
After Steps 1-2: Expected PASS (14 tests).

- [ ] **Step 5: Run the full suite and analyze.**

Run: `flutter analyze` — expect "No issues found!"
Run: `flutter test` — expect all tests pass (150 prior + 14 new).

- [ ] **Step 6: Commit**

```bash
git add lib/core/settings/kivo_settings.dart lib/player/tracks/track_selection.dart test/player/tracks/track_selection_test.dart
git commit -m "feat: subtitle/audio settings fields + pure track-selection logic"
```

---

### Task 3: Native external-subtitle discovery + `VideoSession.folder`

**Files:**
- Modify: `android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt`
- Create: `lib/platform/interfaces/subtitle_finder.dart`
- Create: `lib/platform/android/android_subtitle_finder.dart`
- Modify: `lib/player/open/video_source.dart`
- Modify: `test/fakes/fakes.dart` (add `FakeSubtitleFinder`)
- Test: none automated for the native Kotlin query itself (device-verified, matches the project's existing pattern for `kivo/media`'s `scan`/`thumbnail`); a widget/unit test for `VideoSession.folder` plumbing lands in Task 4.

**Interfaces:**
- Produces: `class ExternalSubtitle {final String uri; final String displayName;}`; `abstract class SubtitleFinder {Future<List<ExternalSubtitle>> findNear(String folder);}`; `AndroidSubtitleFinder implements SubtitleFinder` (calls `kivo/media`'s new `findSubtitles` method); `VideoSession.folder` (`String?`, null unless opened via `openInFolder`).

- [ ] **Step 1: Read the current `MainActivity.kt` in full** before editing (it has 3 channels: `kivo/orientation`, `kivo/frames`, `kivo/media` with `scan`/`thumbnail`, plus `kivo/volume`).

- [ ] **Step 2: Add a `findSubtitles` case to the existing `kivo/media` channel handler.** Inside the `when (call.method) { "scan" -> {...}; "thumbnail" -> {...}` block, add a new branch:
```kotlin
                    "findSubtitles" -> {
                        val folder = call.argument<String>("folder")
                        if (folder == null) { result.error("INVALID_ARG", "folder required", null); return@setMethodCallHandler }
                        ioExecutor.execute {
                            val out = ArrayList<HashMap<String, Any>>()
                            try {
                                val col = MediaStore.Files.getContentUri("external")
                                val proj = arrayOf(
                                    MediaStore.Files.FileColumns._ID,
                                    MediaStore.Files.FileColumns.DISPLAY_NAME,
                                )
                                val exts = listOf("srt", "vtt", "ass", "ssa", "sub")
                                val likeClauses = exts.joinToString(" OR ") {
                                    "${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?"
                                }
                                val selection = "${MediaStore.Files.FileColumns.BUCKET_DISPLAY_NAME} = ? AND ($likeClauses)"
                                val args = arrayOf(folder) + exts.map { "%.$it" }.toTypedArray()
                                contentResolver.query(col, proj, selection, args, null)?.use { c ->
                                    val idC = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
                                    val nameC = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
                                    while (c.moveToNext()) {
                                        val id = c.getLong(idC)
                                        val uri = ContentUris.withAppendedId(col, id).toString()
                                        out.add(hashMapOf(
                                            "uri" to uri,
                                            "displayName" to (c.getString(nameC) ?: ""),
                                        ))
                                    }
                                }
                                runOnUiThread { result.success(out) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("FIND_SUBTITLES_FAILED", e.message, null) }
                            }
                        }
                    }
```
(This reuses the file's existing `ioExecutor` and `MediaStore`/`ContentUris` imports — already present at the top of the file.)

- [ ] **Step 3: Create `lib/platform/interfaces/subtitle_finder.dart`.**
```dart
class ExternalSubtitle {
  final String uri;
  final String displayName;
  const ExternalSubtitle({required this.uri, required this.displayName});
}

/// Finds subtitle files sitting in the same folder as a library video.
/// Android-only for now (uses MediaStore.Files, unavailable for videos
/// opened outside the library — see VideoSession.folder).
abstract class SubtitleFinder {
  Future<List<ExternalSubtitle>> findNear(String folder);
}
```

- [ ] **Step 4: Create `lib/platform/android/android_subtitle_finder.dart`.**
```dart
import 'package:flutter/services.dart';
import '../interfaces/subtitle_finder.dart';

class AndroidSubtitleFinder implements SubtitleFinder {
  static const _channel = MethodChannel('kivo/media');

  @override
  Future<List<ExternalSubtitle>> findNear(String folder) async {
    final result = await _channel.invokeMethod('findSubtitles', {'folder': folder});
    final list = (result as List?) ?? const [];
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map((m) => ExternalSubtitle(
              uri: m['uri'] as String,
              displayName: m['displayName'] as String,
            ))
        .toList();
  }
}
```

- [ ] **Step 5: Add `folder` to `VideoSession` and populate it.** Read `lib/player/open/video_source.dart` first (it has `class VideoSession {playbackPath, displayName, queue, index}` with a `const` constructor, and `CurrentVideoNotifier` with `open`/`openPath`/`openInFolder`). Change:
```dart
class VideoSession {
  final String playbackPath;
  final String displayName;
  final List<String> queue;
  final int index;
  const VideoSession({
    required this.playbackPath,
    required this.displayName,
    required this.queue,
    required this.index,
  });
  String get resumeKey => displayName;
}
```
to:
```dart
class VideoSession {
  final String playbackPath;
  final String displayName;
  final List<String> queue;
  final int index;
  final String? folder; // set only when opened from the library — enables external-subtitle discovery
  const VideoSession({
    required this.playbackPath,
    required this.displayName,
    required this.queue,
    required this.index,
    this.folder,
  });
  String get resumeKey => displayName;
}
```
In `CurrentVideoNotifier.openInFolder(VideoItem current, List<VideoItem> all)`, add `folder: current.folder,` to the constructed `VideoSession(...)`. Leave `openPath`/`open` unchanged (their sessions keep `folder: null` by omission).

- [ ] **Step 6: Add `FakeSubtitleFinder` to `test/fakes/fakes.dart`.**
```dart
class FakeSubtitleFinder implements SubtitleFinder {
  Map<String, List<ExternalSubtitle>> byFolder = {};
  List<String> requestedFolders = [];
  @override
  Future<List<ExternalSubtitle>> findNear(String folder) async {
    requestedFolders.add(folder);
    return byFolder[folder] ?? const [];
  }
}
```
Add `import 'package:kivo_player/platform/interfaces/subtitle_finder.dart';` to the top of `fakes.dart`.

- [ ] **Step 7: Run analyze + the existing suite** (no new automated tests in this task beyond compile-checking; `VideoSession`'s new optional field must not break any existing call site).

Run: `flutter analyze` — expect "No issues found!"
Run: `flutter test` — expect all tests pass (164 prior, no new tests added by this task itself).

- [ ] **Step 8: Commit**

```bash
git add android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt lib/platform/interfaces/subtitle_finder.dart lib/platform/android/android_subtitle_finder.dart lib/player/open/video_source.dart test/fakes/fakes.dart
git commit -m "feat: native external-subtitle discovery (MediaStore.Files) + VideoSession.folder"
```

---

### Task 4: `PlayerScreen` wiring — auto-select tracks, apply style, discover external subtitles

**Files:**
- Modify: `lib/ui/player/player_screen.dart`
- Modify: `lib/main.dart` (wire `AndroidSubtitleFinder` provider override)
- Create: `lib/platform/subtitle_finder_provider.dart`
- Test: extend `test/ui/player/player_screen_controls_test.dart`

**Interfaces:**
- Consumes (Tasks 1-3): `PlaybackEngine.{audioTracksStream, subtitleTracksStream, setAudioTrack, setSubtitleTrack, setExternalSubtitle, setSubtitleStyle}`; `selectSubtitleTrack`/`selectAudioTrack` (`lib/player/tracks/track_selection.dart`); `KivoSettings.{subtitlesEnabledByDefault, preferredSubtitleLanguage, preferredAudioLanguage, subtitleFontSize, subtitleTextColor, subtitleBackgroundColor}`; `SubtitleFinder.findNear`; `VideoSession.folder`.
- Produces: `subtitleFinderProvider` (`Provider<SubtitleFinder>`, throws until overridden — same pattern as `frameExtractorProvider`/`mediaIndexerProvider`).

- [ ] **Step 1: Create `lib/platform/subtitle_finder_provider.dart`.**
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/subtitle_finder.dart';

final subtitleFinderProvider = Provider<SubtitleFinder>((ref) {
  throw UnimplementedError('subtitleFinderProvider must be overridden');
});
```

- [ ] **Step 2: Wire the override in `lib/main.dart`.** Read the file first (it overrides `frameExtractorProvider`/`mediaIndexerProvider`/etc. in `ProviderScope(overrides: [...])`). Add the import `import 'platform/android/android_subtitle_finder.dart'; import 'platform/subtitle_finder_provider.dart';` and add `subtitleFinderProvider.overrideWithValue(AndroidSubtitleFinder()),` to the overrides list.

- [ ] **Step 3: Read the current `lib/ui/player/player_screen.dart` in full** before editing (it has `_PlayerScreenState` with cached `_deviceControls`/`_engine`/`_resume`/`_frames`; `_start()` resets per-entry state then either reconnects [mini-bar expand] or calls `engine.open(...)`; `dispose()`/`PopScope` handler already exist — do not disturb those).

- [ ] **Step 4: Cache the subtitle finder and apply subtitle style + track auto-selection in `_start()`.** Add a field `late final SubtitleFinder _subtitleFinder;` next to the other cached fields, assigned in `initState()`: `_subtitleFinder = ref.read(subtitleFinderProvider);`. Add the imports: `import '../../platform/interfaces/subtitle_finder.dart'; import '../../platform/subtitle_finder_provider.dart'; import '../../player/tracks/track_selection.dart';`.

In `_start()`, AFTER the existing `if (expandingFromMini) {...} else {...}` block (i.e., after the video is confirmed open, whether by reconnecting or by `engine.open`), add:
```dart
    final settings = ref.read(settingsProvider);
    await engine.setSubtitleStyle(
      fontSize: settings.subtitleFontSize,
      textColorArgb: settings.subtitleTextColor,
      backgroundColorArgb: settings.subtitleBackgroundColor,
    );
    if (!expandingFromMini) {
      _applyDefaultTracks(engine, settings, session);
    }
```
Add a new private method (fire-and-forget — does not block `_start()`'s own await chain, matching the existing pattern for `_frames.prepare(...)`):
```dart
  void _applyDefaultTracks(PlaybackEngine engine, KivoSettings settings, VideoSession session) {
    () async {
      final audioTracks = await engine.audioTracksStream.first.timeout(
        const Duration(seconds: 2),
        onTimeout: () => const <MediaTrack>[],
      );
      final audioPick = selectAudioTrack(
        tracks: audioTracks,
        preferredLanguage: settings.preferredAudioLanguage,
      );
      if (audioPick != null) await engine.setAudioTrack(audioPick.id);

      final subtitleTracks = await engine.subtitleTracksStream.first.timeout(
        const Duration(seconds: 2),
        onTimeout: () => const <MediaTrack>[],
      );
      final subtitlePick = selectSubtitleTrack(
        tracks: subtitleTracks,
        enabledByDefault: settings.subtitlesEnabledByDefault,
        preferredLanguage: settings.preferredSubtitleLanguage,
      );
      if (subtitlePick != null) await engine.setSubtitleTrack(subtitlePick.id);
    }();
  }
```
(A `.timeout` guards against a video whose track list stream never emits — e.g. no tracks at all; falls back to an empty list, which both `select*Track` functions handle by returning `null`/leaving the default.) Add `import '../../core/settings/kivo_settings.dart';` if not already present (it likely is, indirectly — verify with `flutter analyze`; add explicitly if needed since `KivoSettings` is now a named parameter type here).

- [ ] **Step 5: Extend `test/ui/player/player_screen_controls_test.dart`.** Read the current file first (it already has a `NoopControls` fake and an established push-then-drive-frames pumping pattern — reuse it). Add two new imports at the top: `import 'package:kivo_player/platform/subtitle_finder_provider.dart';` and `import 'package:kivo_player/player/engine/playback_engine.dart' show MediaTrack;` (the file likely already imports `playback_engine.dart` for `PlaybackEngine`-adjacent types — add the `MediaTrack` show-clause to that existing import instead of a duplicate import line if one is already present). `FakeSubtitleFinder` comes from `'../../fakes/fakes.dart'`, already imported. Add a new test:
```dart
  testWidgets('opening a video auto-selects the preferred subtitle language',
      (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(preferredSubtitleLanguage: 'es'));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: PlayerScreen()),
    ));
    await tester.pump();

    engine.emitSubtitleTracks(const [
      MediaTrack(id: 'sub-en', language: 'en'),
      MediaTrack(id: 'sub-es', language: 'es'),
    ]);
    await tester.pump();
    // Drain the async _applyDefaultTracks chain (the .first futures resolve
    // on the next microtask/pump after the stream emits).
    await tester.pump();

    expect(engine.currentSubtitleTrackId, 'sub-es');

    await tester.pump(const Duration(seconds: 4)); // drain the periodic save timer
  });
```
(`SettingsService` confirmed: `KivoSettings get current`, `Future<void> update(KivoSettings next)` — the call above is the correct, real API, not a guess.)

- [ ] **Step 6: Run the test to verify it fails, then implement/fix until it passes.**

Run: `flutter test test/ui/player/player_screen_controls_test.dart -v`
Expected before Step 4: FAIL (`_subtitleFinder`/track auto-selection not wired).
After Step 4: Expected PASS.

- [ ] **Step 7: Run the full suite and analyze.**

Run: `flutter analyze` — expect "No issues found!"
Run: `flutter test` — expect all tests pass (164 prior + 1 new).

- [ ] **Step 8: Commit**

```bash
git add lib/platform/subtitle_finder_provider.dart lib/main.dart lib/ui/player/player_screen.dart test/ui/player/player_screen_controls_test.dart
git commit -m "feat: PlayerScreen applies subtitle style and auto-selects tracks on open"
```

---

### Task 5: Track-picker UI + activate the top-bar buttons

**Files:**
- Create: `lib/ui/player/tracks/track_picker.dart`
- Modify: `lib/ui/player/controls/top_bar.dart`
- Test: `test/ui/player/tracks/track_picker_test.dart` (new)

**Interfaces:**
- Consumes (Tasks 1-4): `PlaybackEngine.{audioTracksStream, subtitleTracksStream, currentAudioTrackStream, currentSubtitleTrackStream, setAudioTrack, setSubtitleTrack, setExternalSubtitle, setSubtitleStyle}`; `subtitleFinderProvider`; `KivoSettings.{subtitlesEnabledByDefault, preferredSubtitleLanguage, preferredAudioLanguage, subtitleFontSize, subtitleTextColor, subtitleBackgroundColor}`; `VideoSession.folder`; `languageFromFilename` (`lib/player/tracks/track_selection.dart`).
- Produces: `Future<void> showSubtitlePicker(BuildContext context, WidgetRef ref)`, `Future<void> showAudioPicker(BuildContext context, WidgetRef ref)` — both bottom sheets, same visual pattern as `showSpeedPanel`/`SpeedPanel` (`lib/ui/player/speed/speed_panel.dart`: `showModalBottomSheet` with `KivoColors.panel` background, rounded top, a drag handle).

- [ ] **Step 1: Read `lib/ui/player/speed/speed_panel.dart` and `lib/ui/player/controls/top_bar.dart` in full** before writing (already read during design — re-verify nothing changed: `top_bar.dart` has a `Row` with back/info/subtitles(disabled)/pip(disabled)/audio(disabled)/more(disabled) `IconButton`s inside a `TopBar extends ConsumerWidget`).

- [ ] **Step 2: Create `lib/ui/player/tracks/track_picker.dart`.**
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../platform/interfaces/subtitle_finder.dart';
import '../../../platform/subtitle_finder_provider.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../../../player/engine/playback_engine.dart';
import '../../../player/open/video_source.dart';
import '../../../player/tracks/track_selection.dart';

Future<void> showSubtitlePicker(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    isScrollControlled: true,
    builder: (_) => const _TrackPickerSheet(isSubtitles: true),
  );
}

Future<void> showAudioPicker(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => const _TrackPickerSheet(isSubtitles: false),
  );
}

class _TrackPickerSheet extends ConsumerWidget {
  final bool isSubtitles;
  const _TrackPickerSheet({required this.isSubtitles});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(playbackEngineProvider);
    final session = ref.watch(currentVideoProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            StreamBuilder<List<MediaTrack>>(
              stream: isSubtitles ? engine.subtitleTracksStream : engine.audioTracksStream,
              builder: (context, tracksSnap) {
                final tracks = tracksSnap.data ?? const <MediaTrack>[];
                return StreamBuilder<MediaTrack?>(
                  stream: isSubtitles
                      ? engine.currentSubtitleTrackStream
                      : engine.currentAudioTrackStream,
                  builder: (context, currentSnap) {
                    final current = currentSnap.data;
                    return _buildList(context, ref, tracks, current, session, engine);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<MediaTrack> tracks,
    MediaTrack? current,
    VideoSession? session,
    PlaybackEngine engine,
  ) {
    return FutureBuilder<List<ExternalSubtitle>>(
      future: (isSubtitles && session?.folder != null)
          ? ref.read(subtitleFinderProvider).findNear(session!.folder!)
          : Future.value(const []),
      builder: (context, externalSnap) {
        final external = externalSnap.data ?? const <ExternalSubtitle>[];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSubtitles)
              _OptionTile(
                label: 'Desactivado',
                active: current == null,
                onTap: () {
                  engine.setSubtitleTrack(null);
                  final s = ref.read(settingsProvider);
                  ref.read(settingsProvider.notifier).set(s.copyWith(subtitlesEnabledByDefault: false));
                  Navigator.of(context).pop();
                },
              ),
            for (final t in tracks)
              _OptionTile(
                label: t.title ?? t.language ?? t.id,
                active: current?.id == t.id,
                onTap: () {
                  if (isSubtitles) {
                    engine.setSubtitleTrack(t.id);
                    final s = ref.read(settingsProvider);
                    ref.read(settingsProvider.notifier).set(s.copyWith(
                          subtitlesEnabledByDefault: true,
                          preferredSubtitleLanguage: t.language ?? s.preferredSubtitleLanguage,
                        ));
                  } else {
                    engine.setAudioTrack(t.id);
                    final s = ref.read(settingsProvider);
                    ref.read(settingsProvider.notifier).set(s.copyWith(
                          preferredAudioLanguage: t.language ?? s.preferredAudioLanguage,
                        ));
                  }
                  Navigator.of(context).pop();
                },
              ),
            for (final e in external)
              _OptionTile(
                label: e.displayName,
                active: current?.id == e.uri,
                onTap: () {
                  engine.setExternalSubtitle(e.uri, title: e.displayName);
                  final lang = languageFromFilename(e.displayName);
                  final s = ref.read(settingsProvider);
                  ref.read(settingsProvider.notifier).set(s.copyWith(
                        subtitlesEnabledByDefault: true,
                        preferredSubtitleLanguage: lang ?? s.preferredSubtitleLanguage,
                      ));
                  Navigator.of(context).pop();
                },
              ),
            if (isSubtitles) ...[
              const Divider(color: Colors.white24, height: 24),
              const _SubtitleStylePanel(),
            ],
          ],
        );
      },
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _OptionTile({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(
        label,
        style: TextStyle(
          color: active ? KivoColors.gold : Colors.white,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      trailing: active ? const Icon(Icons.check, color: KivoColors.gold) : null,
    );
  }
}

class _SubtitleStylePanel extends ConsumerWidget {
  const _SubtitleStylePanel();

  static const _swatches = [0xFFFFFFFF, 0xFF000000, 0xFFFFEB3B, 0xFF2D6CFF, 0xFFE8B84B];

  void _apply(WidgetRef ref, KivoSettingsPatch patch) {
    final s = ref.read(settingsProvider);
    final updated = s.copyWith(
      subtitleFontSize: patch.fontSize ?? s.subtitleFontSize,
      subtitleTextColor: patch.textColor ?? s.subtitleTextColor,
      subtitleBackgroundColor: patch.backgroundColor ?? s.subtitleBackgroundColor,
    );
    ref.read(settingsProvider.notifier).set(updated);
    ref.read(playbackEngineProvider).setSubtitleStyle(
          fontSize: updated.subtitleFontSize,
          textColorArgb: updated.subtitleTextColor,
          backgroundColorArgb: updated.subtitleBackgroundColor,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tamaño', style: TextStyle(color: Colors.white70, fontSize: 12)),
        Slider(
          min: 16,
          max: 48,
          value: s.subtitleFontSize.clamp(16, 48),
          activeColor: KivoColors.gold,
          onChanged: (v) => _apply(ref, KivoSettingsPatch(fontSize: v)),
        ),
        const Text('Color de texto', style: TextStyle(color: Colors.white70, fontSize: 12)),
        Row(
          children: [
            for (final c in _swatches)
              _ColorSwatch(
                color: c,
                active: s.subtitleTextColor == c,
                onTap: () => _apply(ref, KivoSettingsPatch(textColor: c)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Color de fondo', style: TextStyle(color: Colors.white70, fontSize: 12)),
        Row(
          children: [
            _ColorSwatch(
              color: 0xB3000000,
              active: s.subtitleBackgroundColor == 0xB3000000,
              onTap: () => _apply(ref, KivoSettingsPatch(backgroundColor: 0xB3000000)),
            ),
            _ColorSwatch(
              color: 0x00000000,
              active: s.subtitleBackgroundColor == 0x00000000,
              onTap: () => _apply(ref, KivoSettingsPatch(backgroundColor: 0x00000000)),
            ),
            _ColorSwatch(
              color: 0xFF000000,
              active: s.subtitleBackgroundColor == 0xFF000000,
              onTap: () => _apply(ref, KivoSettingsPatch(backgroundColor: 0xFF000000)),
            ),
          ],
        ),
      ],
    );
  }
}

class KivoSettingsPatch {
  final double? fontSize;
  final int? textColor;
  final int? backgroundColor;
  const KivoSettingsPatch({this.fontSize, this.textColor, this.backgroundColor});
}

class _ColorSwatch extends StatelessWidget {
  final int color;
  final bool active;
  final VoidCallback onTap;
  const _ColorSwatch({required this.color, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? KivoColors.gold : Colors.white24,
            width: active ? 2.5 : 1,
          ),
        ),
      ),
    );
  }
}
```
Note: `KivoSettingsPatch` is a small internal helper (not part of the public settings model) so `_apply` can pass "which field changed" without repeating three near-identical methods — it is NOT persisted or serialized, just a local parameter bundle.

- [ ] **Step 3: Activate the buttons in `top_bar.dart`.** Change:
```dart
        // Disabled until later plans (Plan 3 / Hito 3)
        IconButton(color: Colors.white38, tooltip: 'Subtítulos', icon: KivoIcon(KivoIcons.subtitles, size: 24, opacity: 0.38), onPressed: null),
        IconButton(color: Colors.white38, tooltip: 'Imagen en imagen', icon: KivoIcon(KivoIcons.pip, size: 24, opacity: 0.38), onPressed: null),
        IconButton(color: Colors.white38, tooltip: 'Audio', icon: KivoIcon(KivoIcons.audio, size: 24, opacity: 0.38), onPressed: null),
        IconButton(color: Colors.white38, tooltip: 'Más opciones', icon: KivoIcon(KivoIcons.more, size: 24, opacity: 0.38), onPressed: null),
```
to:
```dart
        Builder(
          builder: (context) {
            final subsOn = ref.watch(settingsProvider).subtitlesEnabledByDefault;
            return IconButton(
              color: subsOn ? accent : Colors.white,
              tooltip: 'Subtítulos',
              icon: KivoIcon(KivoIcons.subtitles, size: 24, color: subsOn ? accent : Colors.white),
              onPressed: () => showSubtitlePicker(context, ref),
            );
          },
        ),
        // PiP lands in 3d — still disabled here.
        IconButton(color: Colors.white38, tooltip: 'Imagen en imagen', icon: KivoIcon(KivoIcons.pip, size: 24, opacity: 0.38), onPressed: null),
        Builder(
          builder: (context) => IconButton(
            color: Colors.white,
            tooltip: 'Audio',
            icon: KivoIcon(KivoIcons.audio, size: 24, color: Colors.white),
            onPressed: () => showAudioPicker(context, ref),
          ),
        ),
        IconButton(color: Colors.white38, tooltip: 'Más opciones', icon: KivoIcon(KivoIcons.more, size: 24, opacity: 0.38), onPressed: null),
```
(`Builder` gives each button its own `context` that's a descendant of the `TopBar`'s `Scaffold`/`Navigator` — needed because `showModalBottomSheet` requires a context with a `Navigator` ancestor; `TopBar.build`'s own outer `context` parameter already satisfies this in practice since `TopBar` is built inside `PlayerScreen`'s `Scaffold`, but wrapping in `Builder` is a defensive, zero-cost habit matching how bottom sheets are typically triggered from deep in a widget tree — skip the `Builder` and use the outer `context` directly if `flutter analyze`/testing shows it already works, to avoid unnecessary nesting.) Add the import `import '../tracks/track_picker.dart';` to `top_bar.dart`.

- [ ] **Step 4: Write `test/ui/player/tracks/track_picker_test.dart`.**
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/tracks/track_picker.dart';
import '../../../fakes/fakes.dart';

Future<ProviderContainer> _pumpAndOpenSheet(
  WidgetTester tester, {
  required bool subtitles,
}) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(
    const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
  );

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: KivoTheme.dark(),
      home: Scaffold(
        body: Center(
          // Consumer (not a plain Builder) is what gives this callback a
          // real WidgetRef — showSubtitlePicker/showAudioPicker take
          // (BuildContext, WidgetRef), not a raw ProviderContainer.
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () =>
                  subtitles ? showSubtitlePicker(context, ref) : showAudioPicker(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();

  if (subtitles) {
    engine.emitSubtitleTracks(const [MediaTrack(id: 'sub-en', title: 'English', language: 'en')]);
  } else {
    engine.emitAudioTracks(const [MediaTrack(id: 'aud-en', title: 'English', language: 'en')]);
  }
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('subtitle sheet lists "Desactivado" plus tracks', (tester) async {
    await _pumpAndOpenSheet(tester, subtitles: true);
    expect(find.text('Desactivado'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('audio sheet lists tracks without "Desactivado"', (tester) async {
    await _pumpAndOpenSheet(tester, subtitles: false);
    expect(find.text('Desactivado'), findsNothing);
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('tapping "Desactivado" turns subtitles off and persists the choice',
      (tester) async {
    final c = await _pumpAndOpenSheet(tester, subtitles: true);
    await tester.tap(find.text('Desactivado'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).subtitlesEnabledByDefault, false);
  });
}
```
- [ ] **Step 5: Run the tests to verify they fail, then implement/fix until they pass.**

Run: `flutter test test/ui/player/tracks/track_picker_test.dart -v`
Expected before Step 2-3: FAIL (file/buttons don't exist).
After Step 2-3: Expected PASS (3 tests).

- [ ] **Step 6: Run the full suite and analyze.**

Run: `flutter analyze` — expect "No issues found!"
Run: `flutter test` — expect all tests pass (165 prior + 3 new).

- [ ] **Step 7: Commit**

```bash
git add lib/ui/player/tracks/track_picker.dart lib/ui/player/controls/top_bar.dart test/ui/player/tracks/track_picker_test.dart
git commit -m "feat: subtitle/audio track picker UI + activate top-bar buttons"
```

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review (opus) — this round touches native Kotlin, a third-party engine's raw-property API, and multiple layers; give it extra scrutiny on the media_kit API usage (Step 3 of Task 1) and the native MediaStore.Files query (Step 2 of Task 3), since neither can be automatically tested and both were written from source-reading rather than a working example.
3. Release build to the Pixel 6: a video with embedded subtitles shows them automatically on open; turning them off is remembered for the next video; picking a language is remembered and auto-applied when available; a loose .srt file in a library video's folder appears in the picker and can be applied; changing size/text color/background color visibly changes the rendered subtitle immediately, including over an ASS-styled track; the audio picker lists and switches embedded audio tracks; the "Subtítulos" icon tints when active.
