# Kivo playlists — Design

**Date:** 2026-08-31
**Status:** Approved for implementation

## Goal

User-made, ordered, persistent lists of videos: create one, add videos to it,
reorder it, and play it as a queue.

## Why now

Kivo's queue is implicit — it is whatever the library happened to be showing
when you tapped a video (`CurrentVideoNotifier.openFromList(current, shown)`).
That is right for browsing and useless for anything you watch deliberately in
an order: a series spread across folders, a course, a set of clips. There is no
way to say "these, in this order" and come back to it tomorrow.

## Non-goals

- **Shuffle.** Cheap to add and probably the first follow-up request, but
  nobody has asked. Better requested than guessed.
- **Smart/auto playlists** (by folder, by tag, by unwatched). A different
  feature with different persistence — these are hand-made lists.
- **Nested playlists.**
- **M3U import/export.** Kivo is local-only with no interop story, and M3U
  stores paths, which is the one identity that breaks on both rename and move.
- **Removing entries automatically when a video disappears.** Deliberate — see
  §4.

## 1. Storage

A Hive box, `playlists`, with **one key per playlist** rather than one list
under a single key. Reordering or renaming one playlist then rewrites only that
playlist, which is also why this does not live in the settings blob: settings
is written whole on every change, so a drag-to-reorder would rewrite every
setting the user has.

```dart
class PlaylistEntry {
  final String mediaId;      // MediaStore _ID
  final String displayName;  // the file name
}

class Playlist {
  final String id;           // generated once, never reused
  final String name;
  final int createdAtMs;
  final List<PlaylistEntry> entries;  // order IS the playlist
}
```

**Both identities are stored on purpose.** `mediaId` survives a rename (the
app renames through MediaStore, which keeps the row) but not a move (a moved
file is usually a new row). `displayName` survives a move but not a rename.
Keeping both and resolving by id first, name second, means an entry survives
either — and only loses if both change at once.

`Playlist.id` is the creation timestamp in milliseconds as a string, taken from
an injected clock so tests are deterministic. It is the playlist's identity, so
**two playlists may share a name** — a user who wants "Serie" twice is not
wrong, and forcing unique names would mean rejecting a create for a reason that
does not matter. Names are for reading; ids are for referring.

Duplicate entries within one playlist are allowed too: the same video twice in
a list is a legitimate thing to want.

## 2. Resolution, and which index it resolves against

```dart
List<ResolvedEntry> resolvePlaylist(Playlist p, List<VideoItem> index);
// ResolvedEntry = (PlaylistEntry entry, VideoItem? video)
```

Pure, testable, no Riverpod. `video == null` means unavailable.

**It resolves against `mediaIndexProvider` — the raw scan — not
`libraryIndexProvider`.** A video the user put in a playlist by hand outranks a
view filter: hiding its folder from the library should not silently empty a
playlist. This is the one place in the app that reads past the folder
exclusion, and it is deliberate.

## 3. Playing: no new queue code

`openFromList(current, shown)` already takes a `List<VideoItem>` and builds the
whole session — queue, names, ids, index. Playing a playlist is resolving it
and calling that. **The queue, autoplay, the thumbnail strip and the media
session are untouched.**

Unavailable entries are simply not in the list handed to `openFromList`, so
they cannot be queued or auto-advanced into. They remain visible in the
playlist screen.

## 4. Missing videos stay, greyed

An entry whose video does not resolve renders greyed and does not play. It is
**not** removed.

The reason is recoverability: an SD card unplugged for an afternoon would
otherwise destroy a playlist permanently, and there is no undo for that. Greyed
also tells the user *what* is missing, where a silently shrinking list tells
them nothing. If the card comes back, so does the entry, with no action needed.

## 5. Where playback starts

The first available entry **not marked played**; if every entry is played, the
top.

This stores nothing new. `PlayedStore.isPlayed(name)` already knows which
videos are finished, and `ResumeService` already restores the position inside
whichever video opens. So "continue where you left off" is derived, not
persisted — it cannot drift out of sync with reality, because there is no
second copy of the truth.

## 6. Renames and deletes

`VideoActionsController` already keeps the name-keyed stores consistent
(resume, played, subtitle prefs). Playlists join that list, with one asymmetry:

- **Rename:** update the entry's `displayName`. The `mediaId` survives on its
  own, but leaving a stale name would quietly disable the fallback that exists
  for moves.
- **Delete:** **no hook.** The entry stays and becomes unavailable, per §4.

## 7. UI

**A third sub-tab in Videos: `Todo · Carpetas · Listas`.** Same weight as
Carpetas, which is also just another way of grouping the same videos. The
bottom bar is untouched.

- **Listas tab** — the playlists, each with a cover (the first available
  entry's thumbnail) and a count. Create from a button in the tab. Empty state
  explains what a playlist is for and how to make one.
- **Playlist screen** — the entries in order, drag to reorder, remove, rename
  the playlist, delete the playlist, and play. Greyed rows are inert but
  removable.
- **Adding** — "Añadir a lista" in `SelectionBottomBar` (beside Compartir /
  Borrar / Mover al Vault) and in the video `⋮` sheet. Both open the same sheet:
  your playlists plus "Nueva lista". This covers both natural modes — building
  a list in one go, and adding one video you happen to be looking at.

## 8. Error codes

Playlist edits are Hive writes to a local box, the same class of operation as
settings and resume, neither of which has a code. A failed write leaves the
in-memory list correct for the session and the next write retries. No new
`KV-nnn`.

## 9. Testing

Pure logic, no widget pumping:

- `resolvePlaylist`: by id, fallback by name, unresolved stays unresolved,
  order preserved, duplicates allowed (the same video twice in one playlist is
  legal).
- Start-point selection: first unplayed, all-played falls to the top,
  unavailable entries skipped.
- Reorder, add, remove, rename round-trip through the store.
- The rename hook updating `displayName`, and the deliberate absence of a
  delete hook.

Widget-level: the Listas tab renders playlists and its empty state; the
add-to-playlist sheet lists playlists and creates a new one; a greyed row does
not start playback.

## 10. Files

**New:** `lib/player/playlists/playlist.dart` (model + pure resolution and
start-point logic) · `lib/player/playlists/playlist_store.dart` ·
`lib/player/playlists/playlist_controller.dart` ·
`lib/ui/home/playlists/playlists_tab.dart` ·
`lib/ui/home/playlists/playlist_screen.dart` ·
`lib/ui/home/playlists/add_to_playlist_sheet.dart`

**Modified:** `lib/ui/home/library_screen.dart` (third sub-tab) ·
`lib/ui/home/widgets/selection_bottom_bar.dart` ·
`lib/ui/home/widgets/video_options_sheet.dart` ·
`lib/player/library/video_actions.dart` (rename hook) · `lib/main.dart` (the
`playlists` Hive box).
