# Kivo subtitle sync, manual subtitles & folder exclusion — Design

**Date:** 2026-08-28
**Status:** Approved for implementation

## Goal

Three gaps a user hits with ordinary content, shipped as one module because two
of them share a store:

1. **Subtitle sync** — nudge `sub-delay` from a floating HUD while the video
   plays, and remember the offset per video.
2. **Load a subtitle by hand** — pick a `.srt` the auto-discovery can't find,
   and have that video remember it.
3. **Exclude folders from the library** — hide the WhatsApp/Telegram/screen-
   recording noise without touching a single file.

## Why now

Kivo has subtitle *selection* and subtitle *styling* but no subtitle *timing*.
An external `.srt` that runs two seconds late ruins the whole film and the app
offers no way out — that is the single most-felt hole in an otherwise complete
player. The manual load is nearly free: `MediaKitEngine.setExternalSubtitle`
([media_kit_engine.dart:147](../../../lib/player/engine/media_kit_engine.dart))
is already implemented and **nobody calls it with a user-chosen file** —
auto-discovery only fires for a sidecar file named after the video, in the same
folder ([apply_default_tracks.dart:37](../../../lib/player/tracks/apply_default_tracks.dart)).
Folder exclusion rides along because the library is the other surface people
complain about, and it turns out to need no native work at all.

## Non-goals

- **Audio delay.** The plumbing is identical to `sub-delay`, but local files
  are almost never audio-desynced, and supporting it forces a Sub/Audio toggle
  onto the HUD — a mode to remember in 100% of uses to serve maybe 2%. Deferred
  deliberately, not forgotten; adding it later is one engine method and one row.
- **Online subtitle search.** Kivo is local-only. Downloading subtitles would
  be the first feature to make that untrue.
- **Subtitle re-encoding or charset override.** mpv guesses; a charset picker
  is its own design.
- **Excluding individual files.** Folder granularity only. The vault already
  covers "hide this specific video".
- **Deleting or moving anything on exclusion.** Excluding is a view filter. The
  vault is the feature that moves files, and the copy must keep them distinct.

## 1. The constraint that shapes the HUD: mpv on the UI thread

`sub-delay` is set through `NativePlayer.setProperty`. That is the *exact* call
sitting at the top of the ANR trace for the still-open background-freeze bug
(`.superpowers/sdd/kivo-anr-hang-trace.txt`):

```
"main" tid=1 Native
  #02 pthread_cond_wait
  #04 mpv_set_property+80
  #05 mpv_set_property_string   ← synchronous mpv call from the UI thread
```

A naive `−`/`+` stepper that calls `setProperty` on every tap would fire a dozen
synchronous mpv calls in two seconds, on the thread that must not block. That is
the same shape as the known hang.

So the HUD is **optimistic and coalesced**:

- Tapping `−`/`+` mutates only the notifier's own integer. The capsule repaints
  at frame rate; mpv is not involved.
- A **trailing debounce of 120 ms** collapses a burst of taps into one
  `setSubtitleDelay` call. Twelve taps → one mpv call.
- The debounce timer is cancelled on dispose, and the pending value is flushed
  once on close so the last nudge is never lost.

This is not a micro-optimisation. It is the difference between a control that
is safe on the one code path we know can wedge and one that is not.

## 2. The sync HUD

**Placement:** top-centre capsule. This is forced by the content: subtitles
render at the bottom, and the entire point of the control is watching the
subtitle move while you nudge it. A bottom-anchored control would cover the
thing being adjusted.

**Anatomy** (design language: dark capsule, gold accent, segmented meter):

- `−` · value · `+`, value in tabular figures as `+0,50 s`.
- A **13-segment meter** under the value, lit outward from a brighter centre
  tick, spanning −1.5 s … +1.5 s. Past that range the meter pins at the end and
  the number keeps counting — honest about being out of range without lying
  about the value.
- Segments use `settings.accentColor`, unlit `onSurface @ 0.18`, matching
  `_SegmentedProgress` and the volume/brightness HUD.

**Interaction:**

- Step: 50 ms. Long-press on `−`/`+` auto-repeats.
- Tap the value → reset to 0.
- Auto-hides after 3 s without interaction; any tap restarts the timer.

**Invocation:** the `⋮` more-menu (which today holds only two entries, sleep
timer and A-B loop) and the track picker's Pistas tab. Both are bottom sheets,
so both **dismiss themselves before showing the HUD** — leaving the sheet up
would cover the subtitle and defeat the whole placement argument.

**Gating:** offered only when a subtitle track is actually active. With subs
off, `sub-delay` changes nothing, and a control that visibly does nothing reads
as broken.

## 3. One store for both per-video memories

The offset and the hand-picked `.srt` are both "something this video
remembers", so they share one Hive box rather than growing two.

```dart
class VideoSubtitlePrefs {
  final int delayMs;        // 0 when never adjusted
  final String? subtitlePath;  // app-owned copy, see §4
}

abstract class SubtitlePrefsStore {
  VideoSubtitlePrefs? forKey(String key);
  Future<void> put(String key, VideoSubtitlePrefs prefs);
  Future<void> remove(String key);
}
```

Keyed by the same video key as resume (the display name), so the two stay
addressable together.

Applied on open inside `applyDefaultTracks`: load the external subtitle first
if one is remembered, then apply the delay, so the delay lands on the track it
was measured against.

**The part that gets forgotten:** `VideoActionsController` already migrates
resume on rename and clears resume + played on delete
([video_actions.dart:29](../../../lib/player/library/video_actions.dart)). This
store needs the same two hooks. Without them, renaming an episode silently
loses its sync — and the user would blame the sync feature, not the rename.

## 4. Manual external subtitle

A "Cargar subtítulo…" row at the foot of the track picker's Pistas tab opens
`file_picker` filtered to `srt ass ssa vtt sub`, then calls the existing
`setExternalSubtitle(uri)`.

**Paths from the file picker are volatile** — a cached picker path can be dead
by the next launch. So the chosen file is **copied into app-owned storage**
(`getExternalStorageDirectory()/subs/<key>.<ext>`) and *that* path is what gets
stored and re-applied. Subtitle files are kilobytes; the copy is the only thing
that makes the association survive a reboot.

Cleanup: the copy is deleted alongside the prefs entry when the video is
deleted, and moved with the key on rename.

Failure (unreadable pick, failed copy, mpv refuses the file) surfaces as a new
code, and is recorded through `errorLogProvider` like every other failure.

## 5. Folder exclusion

Pure Dart. `VideoItem.folder` is the bucket display name and the library
already groups on it (`groupByFolder`), so the key the user sees and the key we
store are the same string. No native change.

**Where the filter lives.** Not inside `MediaIndexNotifier.build()`: that would
need `ref.watch` on settings, and a watched-dependency change re-runs `build()`,
publishing a data-less `AsyncLoading` — the exact spinner the notifier's own
comment says "unmounts the scroll view and throws the user back to the top of
the list" ([media_index.dart:19](../../../lib/player/library/media_index.dart)).

Instead a derived provider:

```dart
final libraryIndexProvider = Provider<AsyncValue<List<VideoItem>>>((ref) {
  final raw = ref.watch(mediaIndexProvider);
  final excluded = ref.watch(settingsProvider.select((s) => s.excludedFolders));
  return raw.whenData((v) => v.where((i) => !excluded.contains(i.folder)).toList());
});
```

Pure derivation: toggling a folder re-filters instantly, with no rescan and no
loading flash.

**Consumers to migrate** — every surface that shows the library must read the
derived provider, or they desync:

| Surface | Provider |
| --- | --- |
| Library "Todo" + search + sort | `libraryIndexProvider` |
| Carpetas grid | `libraryIndexProvider` |
| Folder screen contents | `libraryIndexProvider` |
| Continuar viendo | `libraryIndexProvider` |
| Autoplay queue | `libraryIndexProvider` |
| `VideoActionsController` refresh | **stays on `mediaIndexProvider`** — it acts on one known item and must not be filtered |

**Entry point:** long-press on a folder tile. Folder tiles have no `⋮` and no
long-press today, so the gesture is free. It opens a sheet with "Ocultar de la
biblioteca"; the resulting snackbar carries **Deshacer**.

**Exit point:** Ajustes › General → "Carpetas ocultas (N)" → a list of the
stored names, each restorable. The settings screen reads the stored names, not
the index, so a folder stays recoverable even after it is filtered out.

**Copy:** the sheet and the settings row must both say the files are not
touched. Users who know the vault will otherwise assume this moves them.

**Setting:** `excludedFolders` as `List<String>` — the sixth insertion-point
pattern (field, ctor, defaults, copyWith, toMap, fromMap), defaulting to `[]`.
No auto-excluded defaults: guessing for the user contradicts the project's
configurable-by-default principle, and the long-press makes hiding a folder a
two-second job.

## 6. Error codes

The catalog is append-only. 5xx is playback and 501 is `openVideo`, so:

```
KV-502  subtitleLoad   'No pudimos cargar el subtítulo'
```

Covers the manual-load path only. A failed `sub-delay` is not user-visible
enough to warrant a code — it is logged, and the HUD simply shows the value it
could not apply.

## 7. Testing

Pure logic, no widget pumping needed:

- `subtitleDelayStep` / clamping / reset-to-zero, and the meter's lit-segment
  count from a delay (including the pinned out-of-range case).
- The debounce: N rapid nudges produce exactly one engine call, carrying the
  **last** value.
- `SubtitlePrefsStore` round-trip, plus the rename-migration and delete-clear
  hooks in `VideoActionsController`.
- `libraryIndexProvider` filtering, including a folder name that no longer
  exists in the index (stale exclusion must not throw).
- The subtitle copy: extension preserved, key-named destination, failure
  degrades to a recorded KV-502 rather than an exception.

Widget-level: the HUD only renders with an active subtitle track; the folder
sheet's Deshacer restores the exclusion.

## 8. Files touched

**New:** `lib/player/tracks/subtitle_delay.dart` (pure step/clamp/meter maths) ·
`lib/player/tracks/subtitle_prefs_store.dart` ·
`lib/player/tracks/subtitle_prefs_controller.dart` ·
`lib/ui/player/tracks/subtitle_sync_hud.dart` ·
`lib/ui/home/widgets/folder_options_sheet.dart` ·
`lib/ui/settings/sections/hidden_folders_section.dart`

**Modified:** `media_kit_engine.dart` + its `PlaybackEngine` interface
(`setSubtitleDelay`) · `apply_default_tracks.dart` · `video_actions.dart` ·
`kivo_settings.dart` · `kivo_failure.dart` · `media_index.dart` ·
`track_picker.dart` · `more_menu.dart` · `folder_grid.dart` ·
`general_section.dart` · `main.dart` (a new `subtitlePrefs` Hive box, opened alongside the other six) · plus every consumer in the
migration table above.
