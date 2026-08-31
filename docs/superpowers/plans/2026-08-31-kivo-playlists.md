# Kivo playlists — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** User-made, ordered, persistent lists of videos — create, add to, reorder, and play as a queue.

**Architecture:** A Hive box with one key per playlist, entries carrying both a MediaStore id and a display name so an entry survives either a rename or a move. Resolution against the raw media index is a pure function; playback reuses `CurrentVideoNotifier.openFromList` unchanged, so the queue, autoplay and media session are untouched.

**Tech Stack:** Flutter · Riverpod (`Notifier`/`Provider`) · Hive

**Spec:** `docs/superpowers/specs/2026-08-31-kivo-playlists-design.md`

## Global Constraints

- **No `Co-Authored-By` trailer on any commit.** User preference.
- **User-facing strings are Spanish; code comments are English.**
- **Never hardcode colours.** Use `Theme.of(context).colorScheme` or the configurable accent, `Color(ref.watch(settingsProvider).accentColor)`.
- **Resolution reads `mediaIndexProvider` (the raw scan), never `libraryIndexProvider`.** A video the user put in a playlist by hand outranks the hidden-folders view filter. This is the only place in the app that deliberately reads past that filter.
- **A missing video is greyed, never removed.** An SD card unplugged for an afternoon must not destroy a playlist.
- **No new `KV-nnn` code.** Playlist edits are local Hive writes, the same class as settings and resume, neither of which has one.
- **`Playlist.id` is the creation timestamp in ms as a string, from an injected clock** so tests are deterministic. Two playlists may share a name; duplicate entries within a playlist are legal.
- **Run `flutter analyze --no-pub` before every commit.** The repo sits at exactly 3 pre-existing infos (`grow_rect.dart` ×2 `deprecated_member_use`, `track_selection_test.dart` naming). Add no new ones.
- **Test command:** `flutter test` (full) or `flutter test <path>` (one file).

---

### Task 1: The playlist model and pure resolution

**Files:**
- Create: `lib/player/playlists/playlist.dart`
- Test: `test/player/playlists/playlist_test.dart`

**Interfaces:**
- Consumes: `VideoItem` from `lib/platform/interfaces/media_indexer.dart` (fields used: `id`, `uri`, `name`).
- Produces: `class PlaylistEntry { String mediaId; String displayName; }` · `class Playlist { String id; String name; int createdAtMs; List<PlaylistEntry> entries; Playlist copyWith({String? name, List<PlaylistEntry>? entries}); }` · `class ResolvedEntry { PlaylistEntry entry; VideoItem? video; bool get available; }` · `resolvePlaylist(Playlist, List<VideoItem>) -> List<ResolvedEntry>` · `playlistStartIndex(List<ResolvedEntry>, Set<String> playedNames) -> int`

- [ ] **Step 1: Write the failing test**

```dart
// test/player/playlists/playlist_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/playlists/playlist.dart';

VideoItem _v(String id, String name) => VideoItem(
      id: id,
      uri: 'content://$id',
      name: name,
      folder: 'Series',
      durationMs: 1000,
      sizeBytes: 10,
      dateAddedMs: 0,
    );

Playlist _list(List<PlaylistEntry> entries) =>
    Playlist(id: '1', name: 'Serie', createdAtMs: 0, entries: entries);

void main() {
  group('resolution', () {
    test('matches by media id first', () {
      final p = _list([const PlaylistEntry(mediaId: '7', displayName: 'viejo.mkv')]);
      // The file was renamed: the id still matches, the stored name no longer does.
      final resolved = resolvePlaylist(p, [_v('7', 'nuevo.mkv')]);
      expect(resolved.single.available, true);
      expect(resolved.single.video!.name, 'nuevo.mkv');
    });

    test('falls back to the display name when the id is gone', () {
      final p = _list([const PlaylistEntry(mediaId: '7', displayName: 'ep1.mkv')]);
      // The file was moved: MediaStore gave it a new row, so a new id.
      final resolved = resolvePlaylist(p, [_v('99', 'ep1.mkv')]);
      expect(resolved.single.available, true);
      expect(resolved.single.video!.id, '99');
    });

    test('an entry matching neither stays unresolved', () {
      final p = _list([const PlaylistEntry(mediaId: '7', displayName: 'ep1.mkv')]);
      final resolved = resolvePlaylist(p, [_v('99', 'otro.mkv')]);
      expect(resolved.single.available, false);
      expect(resolved.single.video, isNull);
    });

    test('keeps the playlist order, not the index order', () {
      final p = _list([
        const PlaylistEntry(mediaId: '3', displayName: 'c.mkv'),
        const PlaylistEntry(mediaId: '1', displayName: 'a.mkv'),
      ]);
      final resolved = resolvePlaylist(p, [_v('1', 'a.mkv'), _v('3', 'c.mkv')]);
      expect(resolved.map((r) => r.video!.id).toList(), ['3', '1']);
    });

    test('the same video twice is two entries, not one', () {
      final p = _list([
        const PlaylistEntry(mediaId: '1', displayName: 'a.mkv'),
        const PlaylistEntry(mediaId: '1', displayName: 'a.mkv'),
      ]);
      expect(resolvePlaylist(p, [_v('1', 'a.mkv')]).length, 2);
    });
  });

  group('where playback starts', () {
    ResolvedEntry avail(String id, String name) =>
        ResolvedEntry(PlaylistEntry(mediaId: id, displayName: name), _v(id, name));
    ResolvedEntry missing(String name) =>
        ResolvedEntry(PlaylistEntry(mediaId: 'x', displayName: name), null);

    test('is the first entry that has not been played', () {
      final entries = [avail('1', 'a.mkv'), avail('2', 'b.mkv'), avail('3', 'c.mkv')];
      expect(playlistStartIndex(entries, {'a.mkv'}), 1);
      expect(playlistStartIndex(entries, {'a.mkv', 'b.mkv'}), 2);
    });

    test('is the top when nothing has been played', () {
      final entries = [avail('1', 'a.mkv'), avail('2', 'b.mkv')];
      expect(playlistStartIndex(entries, const {}), 0);
    });

    // Otherwise finishing a series would leave it unplayable without scrolling.
    test('is the top again once everything has been played', () {
      final entries = [avail('1', 'a.mkv'), avail('2', 'b.mkv')];
      expect(playlistStartIndex(entries, {'a.mkv', 'b.mkv'}), 0);
    });

    test('skips entries that are not available', () {
      final entries = [missing('a.mkv'), avail('2', 'b.mkv')];
      expect(playlistStartIndex(entries, const {}), 1);
    });

    test('is -1 when there is nothing playable at all', () {
      expect(playlistStartIndex([missing('a.mkv')], const {}), -1);
      expect(playlistStartIndex(const [], const {}), -1);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/player/playlists/playlist_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:kivo_player/player/playlists/playlist.dart'`

- [ ] **Step 3: Write the implementation**

```dart
// lib/player/playlists/playlist.dart
import '../../platform/interfaces/media_indexer.dart';

/// One video's place in a playlist.
///
/// Both identities are stored on purpose. [mediaId] survives a rename — the
/// app renames through MediaStore, which keeps the row — but not a move, which
/// usually creates a new row. [displayName] survives a move but not a rename.
/// Keeping both means an entry only breaks if both change at once.
class PlaylistEntry {
  const PlaylistEntry({required this.mediaId, required this.displayName});

  final String mediaId;
  final String displayName;

  Map<String, dynamic> toMap() => {'i': mediaId, 'n': displayName};

  factory PlaylistEntry.fromMap(Map m) => PlaylistEntry(
        mediaId: (m['i'] as String?) ?? '',
        displayName: (m['n'] as String?) ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is PlaylistEntry &&
      other.mediaId == mediaId &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(mediaId, displayName);
}

/// A hand-made, ordered list of videos. The order of [entries] IS the playlist.
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.createdAtMs,
    required this.entries,
  });

  /// The creation timestamp in milliseconds, as a string. This is the
  /// playlist's identity, which is why two playlists may share a name.
  final String id;
  final String name;
  final int createdAtMs;
  final List<PlaylistEntry> entries;

  Playlist copyWith({String? name, List<PlaylistEntry>? entries}) => Playlist(
        id: id,
        name: name ?? this.name,
        createdAtMs: createdAtMs,
        entries: entries ?? this.entries,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'created': createdAtMs,
        'entries': entries.map((e) => e.toMap()).toList(),
      };

  factory Playlist.fromMap(Map m) => Playlist(
        id: (m['id'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        createdAtMs: (m['created'] as num?)?.toInt() ?? 0,
        entries: ((m['entries'] as List?) ?? const [])
            .whereType<Map>()
            .map(PlaylistEntry.fromMap)
            .toList(),
      );
}

/// An entry paired with the video it points at, or null when that video is
/// not on the device right now.
class ResolvedEntry {
  const ResolvedEntry(this.entry, this.video);

  final PlaylistEntry entry;
  final VideoItem? video;

  bool get available => video != null;
}

/// Pairs each entry with its video, in playlist order.
///
/// Matches by [PlaylistEntry.mediaId] first and falls back to the display
/// name. Callers pass the RAW media index: a video the user put in a playlist
/// by hand outranks the hidden-folders view filter.
List<ResolvedEntry> resolvePlaylist(Playlist playlist, List<VideoItem> index) {
  final byId = <String, VideoItem>{};
  final byName = <String, VideoItem>{};
  for (final v in index) {
    byId[v.id] = v;
    // First wins: two files can share a name in different folders, and the
    // earlier one is as good a guess as any when the id is already gone.
    byName.putIfAbsent(v.name, () => v);
  }

  return playlist.entries
      .map((e) => ResolvedEntry(e, byId[e.mediaId] ?? byName[e.displayName]))
      .toList();
}

/// Index of the entry a "play" should start on, or -1 when nothing is playable.
///
/// The first available entry that has not been played, so a series continues
/// where it was left. Falls back to the top once everything is played —
/// otherwise a finished series could not be replayed without scrolling.
///
/// Derived rather than stored: [PlayedStore] already knows what is finished,
/// so there is no second copy of the truth to drift.
int playlistStartIndex(List<ResolvedEntry> resolved, Set<String> playedNames) {
  var firstAvailable = -1;
  for (var i = 0; i < resolved.length; i++) {
    if (!resolved[i].available) continue;
    if (firstAvailable < 0) firstAvailable = i;
    if (!playedNames.contains(resolved[i].video!.name)) return i;
  }
  return firstAvailable;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/player/playlists/playlist_test.dart && flutter analyze --no-pub`
Expected: PASS, 10 tests; analyze at the 3 pre-existing infos.

- [ ] **Step 5: Commit**

```bash
git add lib/player/playlists/playlist.dart test/player/playlists/playlist_test.dart
git commit -m "feat(playlists): model, resolution and start point"
```

---

### Task 2: The playlist store

Mirrors `lib/player/resume/resume_store.dart` in shape: an abstract store, a Hive-backed implementation, and an in-memory one for tests. Read that file first — this is its sibling, not a new invention.

**Files:**
- Create: `lib/player/playlists/playlist_store.dart`
- Modify: `lib/main.dart` (open a `playlists` box, override the provider)
- Test: `test/player/playlists/playlist_store_test.dart`

**Interfaces:**
- Consumes: `Playlist`, `PlaylistEntry` (Task 1).
- Produces: `abstract class PlaylistStore { List<Playlist> all(); Future<void> put(Playlist); Future<void> remove(String id); }` · `HivePlaylistStore(Box)` · `InMemoryPlaylistStore()` · `playlistStoreProvider`

- [ ] **Step 1: Write the failing test**

```dart
// test/player/playlists/playlist_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/playlists/playlist.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';

Playlist _p(String id, String name, {List<PlaylistEntry> entries = const []}) =>
    Playlist(id: id, name: name, createdAtMs: int.parse(id), entries: entries);

void main() {
  test('round-trips a playlist with its entries in order', () async {
    final s = InMemoryPlaylistStore();
    await s.put(_p('1', 'Serie', entries: const [
      PlaylistEntry(mediaId: '7', displayName: 'ep1.mkv'),
      PlaylistEntry(mediaId: '8', displayName: 'ep2.mkv'),
    ]));

    final read = s.all().single;
    expect(read.name, 'Serie');
    expect(read.entries.map((e) => e.displayName), ['ep1.mkv', 'ep2.mkv']);
  });

  test('put replaces a playlist with the same id rather than duplicating it',
      () async {
    final s = InMemoryPlaylistStore();
    await s.put(_p('1', 'Serie'));
    await s.put(_p('1', 'Serie renombrada'));

    expect(s.all().length, 1);
    expect(s.all().single.name, 'Serie renombrada');
  });

  test('two playlists may share a name — the id is the identity', () async {
    final s = InMemoryPlaylistStore();
    await s.put(_p('1', 'Serie'));
    await s.put(_p('2', 'Serie'));
    expect(s.all().length, 2);
  });

  test('remove takes out only the one asked for', () async {
    final s = InMemoryPlaylistStore();
    await s.put(_p('1', 'A'));
    await s.put(_p('2', 'B'));
    await s.remove('1');
    expect(s.all().single.name, 'B');
  });

  test('removing an id that is not there is a no-op, not a throw', () async {
    final s = InMemoryPlaylistStore();
    await s.remove('nope');
    expect(s.all(), isEmpty);
  });

  test('playlists come back newest first', () async {
    final s = InMemoryPlaylistStore();
    await s.put(_p('1', 'vieja'));
    await s.put(_p('2', 'nueva'));
    expect(s.all().map((p) => p.name), ['nueva', 'vieja']);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/player/playlists/playlist_store_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/player/playlists/playlist_store.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'playlist.dart';

abstract class PlaylistStore {
  /// Newest first — the list people are most likely to want is the one they
  /// just made.
  List<Playlist> all();
  Future<void> put(Playlist playlist);
  Future<void> remove(String id);
}

/// One Hive key per playlist rather than one list under a single key: editing
/// one playlist then rewrites only that playlist, which matters because a
/// drag-to-reorder writes on every frame of the drag's settle.
class HivePlaylistStore implements PlaylistStore {
  HivePlaylistStore(this.box);
  final Box box;

  @override
  List<Playlist> all() {
    final out = <Playlist>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is Map) out.add(Playlist.fromMap(raw));
    }
    out.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return out;
  }

  @override
  Future<void> put(Playlist playlist) =>
      box.put(playlist.id, playlist.toMap());

  @override
  Future<void> remove(String id) => box.delete(id);
}

/// Session-only store: a valid fallback and what the tests use.
class InMemoryPlaylistStore implements PlaylistStore {
  final Map<String, Playlist> _data = {};

  @override
  List<Playlist> all() {
    final out = _data.values.toList();
    out.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return out;
  }

  @override
  Future<void> put(Playlist playlist) async => _data[playlist.id] = playlist;

  @override
  Future<void> remove(String id) async => _data.remove(id);
}

final playlistStoreProvider =
    Provider<PlaylistStore>((ref) => InMemoryPlaylistStore());
```

In `lib/main.dart`, alongside the other `Hive.openBox` calls:

```dart
  final playlistsBox = await Hive.openBox('playlists');
```

and in the `overrides:` list:

```dart
      playlistStoreProvider.overrideWithValue(HivePlaylistStore(playlistsBox)),
```

Add the import for `player/playlists/playlist_store.dart`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/player/playlists/ && flutter analyze --no-pub`
Expected: PASS, 16 tests total in the folder.

- [ ] **Step 5: Commit**

```bash
git add lib/player/playlists/playlist_store.dart lib/main.dart test/player/playlists/playlist_store_test.dart
git commit -m "feat(playlists): persistence"
```

---

### Task 3: The playlist controller

**Files:**
- Create: `lib/player/playlists/playlist_controller.dart`
- Test: `test/player/playlists/playlist_controller_test.dart`

**Interfaces:**
- Consumes: `PlaylistStore`, `playlistStoreProvider` (Task 2) · `Playlist`, `PlaylistEntry` (Task 1) · `VideoItem`.
- Produces: `playlistsProvider` (`NotifierProvider<PlaylistsNotifier, List<Playlist>>`) with `create(String name) -> Playlist`, `rename(String id, String name)`, `delete(String id)`, `addVideos(String id, List<VideoItem>)`, `removeEntryAt(String id, int index)`, `reorder(String id, int oldIndex, int newIndex)`, `renameEntry(String oldName, String newName)` · `playlistClockProvider` (`Provider<DateTime Function()>`)

- [ ] **Step 1: Write the failing test**

```dart
// test/player/playlists/playlist_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/playlists/playlist.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';

VideoItem _v(String id, String name) => VideoItem(
      id: id,
      uri: 'content://$id',
      name: name,
      folder: 'Series',
      durationMs: 1000,
      sizeBytes: 10,
      dateAddedMs: 0,
    );

ProviderContainer _c(PlaylistStore store, {DateTime Function()? clock}) {
  var tick = 0;
  return ProviderContainer(overrides: [
    playlistStoreProvider.overrideWithValue(store),
    playlistClockProvider.overrideWithValue(
        clock ?? () => DateTime.fromMillisecondsSinceEpoch(1000 + tick++)),
  ]);
}

void main() {
  test('creating a playlist persists it and returns it', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);

    final made = await c.read(playlistsProvider.notifier).create('Serie');

    expect(made.name, 'Serie');
    expect(made.entries, isEmpty);
    expect(store.all().single.id, made.id);
    expect(c.read(playlistsProvider).single.name, 'Serie');
  });

  test('the id comes from the clock, so it is deterministic in tests', () async {
    final c = _c(InMemoryPlaylistStore(),
        clock: () => DateTime.fromMillisecondsSinceEpoch(4242));
    addTearDown(c.dispose);

    final made = await c.read(playlistsProvider.notifier).create('Serie');
    expect(made.id, '4242');
    expect(made.createdAtMs, 4242);
  });

  test('adding videos appends them in the order given', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');

    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);

    expect(store.all().single.entries.map((e) => e.displayName),
        ['a.mkv', 'b.mkv']);
  });

  test('adding the same video again appends a second entry', () async {
    // Duplicates are legal: the same clip twice in one list is a real want.
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');

    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    expect(store.all().single.entries.length, 2);
  });

  test('reorder moves an entry and keeps the rest in order', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(
        p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv'), _v('3', 'c.mkv')]);

    await c.read(playlistsProvider.notifier).reorder(p.id, 2, 0);

    expect(store.all().single.entries.map((e) => e.displayName),
        ['c.mkv', 'a.mkv', 'b.mkv']);
  });

  test('removing an entry takes out that position only', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);

    await c.read(playlistsProvider.notifier).removeEntryAt(p.id, 0);

    expect(store.all().single.entries.single.displayName, 'b.mkv');
  });

  test('renaming a playlist keeps its entries and its id', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    await c.read(playlistsProvider.notifier).rename(p.id, 'Otra');

    expect(store.all().single.id, p.id);
    expect(store.all().single.name, 'Otra');
    expect(store.all().single.entries.length, 1);
  });

  test('deleting a playlist removes it everywhere', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');

    await c.read(playlistsProvider.notifier).delete(p.id);

    expect(store.all(), isEmpty);
    expect(c.read(playlistsProvider), isEmpty);
  });

  test('a video rename updates the stored name in every playlist', () async {
    // The media id survives a rename on its own; the name is the fallback that
    // covers a move, and a stale one would quietly disable it.
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);
    final a = await c.read(playlistsProvider.notifier).create('A');
    final b = await c.read(playlistsProvider.notifier).create('B');
    await c.read(playlistsProvider.notifier).addVideos(a.id, [_v('1', 'viejo.mkv')]);
    await c.read(playlistsProvider.notifier).addVideos(b.id, [_v('1', 'viejo.mkv')]);

    await c.read(playlistsProvider.notifier).renameEntry('viejo.mkv', 'nuevo.mkv');

    for (final p in store.all()) {
      expect(p.entries.single.displayName, 'nuevo.mkv');
      expect(p.entries.single.mediaId, '1');
    }
  });

  test('acting on an unknown playlist id does nothing', () async {
    final store = InMemoryPlaylistStore();
    final c = _c(store);
    addTearDown(c.dispose);

    await c.read(playlistsProvider.notifier).addVideos('nope', [_v('1', 'a.mkv')]);
    await c.read(playlistsProvider.notifier).rename('nope', 'x');
    await c.read(playlistsProvider.notifier).removeEntryAt('nope', 0);
    await c.read(playlistsProvider.notifier).reorder('nope', 0, 1);

    expect(store.all(), isEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/player/playlists/playlist_controller_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/player/playlists/playlist_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/interfaces/media_indexer.dart';
import 'playlist.dart';
import 'playlist_store.dart';

/// Injected so playlist ids are deterministic under test. Ids are creation
/// timestamps, so without this every test would produce a different one.
final playlistClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Every playlist, newest first. The single writer for the store.
class PlaylistsNotifier extends Notifier<List<Playlist>> {
  PlaylistStore get _store => ref.read(playlistStoreProvider);

  @override
  List<Playlist> build() => _store.all();

  Future<Playlist> create(String name) async {
    final now = ref.read(playlistClockProvider)();
    final playlist = Playlist(
      id: '${now.millisecondsSinceEpoch}',
      name: name,
      createdAtMs: now.millisecondsSinceEpoch,
      entries: const [],
    );
    await _store.put(playlist);
    state = _store.all();
    return playlist;
  }

  Future<void> delete(String id) async {
    await _store.remove(id);
    state = _store.all();
  }

  Future<void> rename(String id, String name) =>
      _update(id, (p) => p.copyWith(name: name));

  Future<void> addVideos(String id, List<VideoItem> videos) => _update(
        id,
        (p) => p.copyWith(entries: [
          ...p.entries,
          for (final v in videos)
            PlaylistEntry(mediaId: v.id, displayName: v.name),
        ]),
      );

  Future<void> removeEntryAt(String id, int index) => _update(id, (p) {
        if (index < 0 || index >= p.entries.length) return p;
        final entries = [...p.entries]..removeAt(index);
        return p.copyWith(entries: entries);
      });

  Future<void> reorder(String id, int oldIndex, int newIndex) => _update(id, (p) {
        if (oldIndex < 0 || oldIndex >= p.entries.length) return p;
        final entries = [...p.entries];
        final moved = entries.removeAt(oldIndex);
        entries.insert(newIndex.clamp(0, entries.length), moved);
        return p.copyWith(entries: entries);
      });

  /// Follows a renamed video across every playlist that holds it.
  ///
  /// The media id survives a rename on its own, so this is not what keeps the
  /// entry working today — it keeps the NAME fallback accurate, which is what
  /// would carry the entry through a later move.
  Future<void> renameEntry(String oldName, String newName) async {
    for (final p in _store.all()) {
      if (!p.entries.any((e) => e.displayName == oldName)) continue;
      await _store.put(p.copyWith(
        entries: p.entries
            .map((e) => e.displayName == oldName
                ? PlaylistEntry(mediaId: e.mediaId, displayName: newName)
                : e)
            .toList(),
      ));
    }
    state = _store.all();
  }

  /// Reads, transforms, writes. An unknown id falls through untouched rather
  /// than creating a playlist nobody asked for.
  Future<void> _update(String id, Playlist Function(Playlist) change) async {
    final current = _store.all().where((p) => p.id == id).firstOrNull;
    if (current == null) return;
    await _store.put(change(current));
    state = _store.all();
  }
}

final playlistsProvider =
    NotifierProvider<PlaylistsNotifier, List<Playlist>>(PlaylistsNotifier.new);
```

If `firstOrNull` is unavailable, add `import 'dart:collection';` is NOT the fix — it comes from `package:collection`. Check whether the repo already depends on `collection`; if not, replace that line with an explicit loop rather than adding a dependency for one call.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/player/playlists/ && flutter analyze --no-pub`
Expected: PASS, 26 tests in the folder.

- [ ] **Step 5: Commit**

```bash
git add lib/player/playlists/playlist_controller.dart test/player/playlists/playlist_controller_test.dart
git commit -m "feat(playlists): create, edit and reorder"
```

---

### Task 4: Resolution providers and playback

**Files:**
- Create: `lib/player/playlists/playlist_playback.dart`
- Test: `test/player/playlists/playlist_playback_test.dart`

**Interfaces:**
- Consumes: `resolvePlaylist`, `playlistStartIndex`, `ResolvedEntry` (Task 1) · `playlistsProvider` (Task 3) · existing `mediaIndexProvider` (`lib/player/library/media_index.dart`), `playedKeysProvider` (`lib/player/library/played.dart`), `currentVideoProvider` (`lib/player/open/video_source.dart`).
- Produces: `resolvedPlaylistProvider` (`Provider.family<List<ResolvedEntry>, String>`) · `PlaylistPlayback` with `play(String playlistId) -> bool` and `playAt(String playlistId, int entryIndex) -> bool` · `playlistPlaybackProvider`

- [ ] **Step 1: Write the failing test**

```dart
// test/player/playlists/playlist_playback_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_playback.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';
import '../../fakes/fakes.dart';

VideoItem _v(String id, String name) => VideoItem(
      id: id,
      uri: 'content://$id',
      name: name,
      folder: 'Series',
      durationMs: 1000,
      sizeBytes: 10,
      dateAddedMs: 0,
    );

// Copy the container-assembly pattern from the existing tests in
// test/player/library/ for mediaIndexerProvider and mediaPermissionImplProvider
// — do not invent fake names.
Future<ProviderContainer> _c(List<VideoItem> index, PlayedStore played) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  var tick = 0;
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(index)),
    playedStoreProvider.overrideWithValue(played),
    playlistStoreProvider.overrideWithValue(InMemoryPlaylistStore()),
    playlistClockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(1000 + tick++)),
  ]);
}

void main() {
  test('playing a playlist opens the first unplayed entry', () async {
    final played = InMemoryPlayedStore()..markPlayed('a.mkv');
    final c = await _c([_v('1', 'a.mkv'), _v('2', 'b.mkv')], played);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);

    expect(c.read(playlistPlaybackProvider).play(p.id), true);

    final session = c.read(currentVideoProvider)!;
    expect(session.displayName, 'b.mkv');
    // The whole playlist is the queue, so autoplay walks it.
    expect(session.queue.length, 2);
    expect(session.index, 1);
  });

  test('an unavailable entry is not in the queue', () async {
    final c = await _c([_v('2', 'b.mkv')], InMemoryPlayedStore());
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);

    expect(c.read(playlistPlaybackProvider).play(p.id), true);
    final session = c.read(currentVideoProvider)!;
    expect(session.queue.length, 1);
    expect(session.displayName, 'b.mkv');
  });

  test('a playlist with nothing playable refuses instead of opening', () async {
    final c = await _c(const [], InMemoryPlayedStore());
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    expect(c.read(playlistPlaybackProvider).play(p.id), false);
    expect(c.read(currentVideoProvider), isNull);
  });

  test('playAt opens the entry that was tapped', () async {
    final c = await _c([_v('1', 'a.mkv'), _v('2', 'b.mkv')], InMemoryPlayedStore());
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);

    expect(c.read(playlistPlaybackProvider).playAt(p.id, 1), true);
    expect(c.read(currentVideoProvider)!.displayName, 'b.mkv');
  });

  test('playAt on an unavailable entry refuses', () async {
    final c = await _c([_v('2', 'b.mkv')], InMemoryPlayedStore());
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);

    expect(c.read(playlistPlaybackProvider).playAt(p.id, 0), false);
    expect(c.read(currentVideoProvider), isNull);
  });

  test('resolution reads the raw index, past the hidden-folders filter',
      () async {
    final c = await _c([_v('1', 'a.mkv')], InMemoryPlayedStore());
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    // Hide the folder the video lives in. A playlist the user built by hand
    // must not empty itself because of a view filter.
    final s = c.read(settingsProvider);
    await c.read(settingsProvider.notifier)
        .set(s.copyWith(excludedFolders: const ['Series']));

    expect(c.read(resolvedPlaylistProvider(p.id)).single.available, true);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/player/playlists/playlist_playback_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/player/playlists/playlist_playback.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/media_index.dart';
import '../library/played.dart';
import '../open/video_source.dart';
import 'playlist.dart';
import 'playlist_controller.dart';

/// One playlist's entries paired with the videos they point at.
///
/// Reads `mediaIndexProvider` — the RAW scan — rather than the folder-filtered
/// `libraryIndexProvider`. A video the user put in a playlist by hand outranks
/// a view filter: hiding its folder must not silently empty the playlist. This
/// is the only place in the app that reads past that filter, and it is
/// deliberate.
final resolvedPlaylistProvider =
    Provider.family<List<ResolvedEntry>, String>((ref, playlistId) {
  final playlists = ref.watch(playlistsProvider);
  final index = ref.watch(mediaIndexProvider).valueOrNull ?? const [];
  for (final p in playlists) {
    if (p.id == playlistId) return resolvePlaylist(p, index);
  }
  return const [];
});

/// Starts a playlist as the player's queue.
///
/// Builds nothing of its own: `openFromList` already turns a list of videos
/// into a full session — queue, names, ids, index — so the queue, autoplay,
/// the thumbnail strip and the media session all work unchanged.
class PlaylistPlayback {
  PlaylistPlayback(this._ref);
  final Ref _ref;

  /// Starts at the first unplayed entry. False when nothing is playable.
  bool play(String playlistId) {
    final resolved = _ref.read(resolvedPlaylistProvider(playlistId));
    final start = playlistStartIndex(resolved, _ref.read(playedKeysProvider));
    if (start < 0) return false;
    return _open(resolved, start);
  }

  /// Starts at a specific entry. False when that entry is unavailable.
  bool playAt(String playlistId, int entryIndex) {
    final resolved = _ref.read(resolvedPlaylistProvider(playlistId));
    if (entryIndex < 0 || entryIndex >= resolved.length) return false;
    if (!resolved[entryIndex].available) return false;
    return _open(resolved, entryIndex);
  }

  bool _open(List<ResolvedEntry> resolved, int entryIndex) {
    // Unavailable entries cannot be queued, so the queue is the available
    // ones in playlist order — and the entry index has to be translated into
    // that shorter list.
    final available = <int, int>{}; // entry index -> queue index
    final videos = <dynamic>[];
    for (var i = 0; i < resolved.length; i++) {
      final v = resolved[i].video;
      if (v == null) continue;
      available[i] = videos.length;
      videos.add(v);
    }
    final queueIndex = available[entryIndex];
    if (queueIndex == null || videos.isEmpty) return false;

    _ref.read(currentVideoProvider.notifier).openFromList(
          videos[queueIndex],
          videos.cast(),
        );
    return true;
  }
}

final playlistPlaybackProvider =
    Provider<PlaylistPlayback>((ref) => PlaylistPlayback(ref));
```

Replace the `dynamic`/`cast()` with the real `VideoItem` type — it is imported through `playlist.dart`'s own import of `media_indexer.dart`, but import it explicitly here rather than relying on that.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/player/playlists/ && flutter analyze --no-pub`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/player/playlists/playlist_playback.dart test/player/playlists/playlist_playback_test.dart
git commit -m "feat(playlists): play a playlist as the queue"
```

---

### Task 5: Follow a renamed video into playlists

**Files:**
- Modify: `lib/player/library/video_actions.dart` (`rename` only)
- Test: `test/player/library/video_actions_playlist_test.dart`

**Interfaces:**
- Consumes: `playlistsProvider.renameEntry(String oldName, String newName)` (Task 3).
- Produces: nothing new.

`VideoActionsController` already migrates the name-keyed stores on rename (resume, played, subtitle prefs). Playlists join them. **There is deliberately NO delete hook** — a deleted video's entry stays and renders greyed, per the spec, because an unplugged SD card must not destroy a playlist.

- [ ] **Step 1: Write the failing test**

```dart
// test/player/library/video_actions_playlist_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/library/video_actions.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';

const _v = VideoItem(
  id: '1',
  uri: 'content://1',
  name: 'ep1.mkv',
  folder: 'Series',
  durationMs: 1000,
  sizeBytes: 10,
  dateAddedMs: 0,
);

void main() {
  test('renaming a video updates its name in playlists', () async {
    // Assemble the container the way test/player/library/video_actions_test.dart
    // already does — copy its overrides, do not invent provider names — and add
    // playlistStoreProvider plus playlistClockProvider.
    final store = InMemoryPlaylistStore();
    final c = await buildContainer(playlistStore: store, renameTo: 'ep1-nuevo.mkv');
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v]);

    await c.read(videoActionsProvider).rename(_v, 'ep1-nuevo');

    expect(store.all().single.entries.single.displayName, 'ep1-nuevo.mkv');
  });

  test('deleting a video leaves the playlist entry alone', () async {
    // Deliberate: the entry renders greyed instead. An SD card unplugged for
    // an afternoon must not destroy a playlist, and there is no undo for that.
    final store = InMemoryPlaylistStore();
    final c = await buildContainer(playlistStore: store);
    addTearDown(c.dispose);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v]);

    await c.read(videoActionsProvider).delete(_v);

    expect(store.all().single.entries.length, 1);
  });
}
```

Write `buildContainer` as a local helper in this file, modelled on the `_c(...)` helper in `test/player/library/video_actions_test.dart`. Copy its provider and fake names verbatim.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/player/library/video_actions_playlist_test.dart`
Expected: FAIL — the playlist entry still says `ep1.mkv`.

- [ ] **Step 3: Write the implementation**

In `lib/player/library/video_actions.dart`, add the import for `../playlists/playlist_controller.dart` and, in `rename`, after the subtitle-prefs line:

```dart
    await _ref.read(playlistsProvider.notifier).renameEntry(v.name, newName);
```

Update the class doc comment: it lists the name-keyed stores it keeps consistent, and playlists are now one of them — with the note that delete deliberately does not touch them.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/player/library/ && flutter analyze --no-pub`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/player/library/video_actions.dart test/player/library/video_actions_playlist_test.dart
git commit -m "feat(playlists): follow a renamed video into playlists"
```

---

### Task 6: The "add to playlist" sheet

**Files:**
- Create: `lib/ui/home/playlists/add_to_playlist_sheet.dart`
- Test: `test/ui/home/add_to_playlist_sheet_test.dart`

**Interfaces:**
- Consumes: `playlistsProvider` with `create`/`addVideos` (Task 3).
- Produces: `showAddToPlaylistSheet(BuildContext context, WidgetRef ref, List<VideoItem> videos) -> Future<void>`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/home/add_to_playlist_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';
import 'package:kivo_player/ui/home/playlists/add_to_playlist_sheet.dart';
import '../../fakes/fakes.dart';

const _v = VideoItem(
  id: '1',
  uri: 'content://1',
  name: 'ep1.mkv',
  folder: 'Series',
  durationMs: 1000,
  sizeBytes: 10,
  dateAddedMs: 0,
);

Future<ProviderContainer> _c(PlaylistStore store) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  var tick = 0;
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    playlistStoreProvider.overrideWithValue(store),
    playlistClockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(1000 + tick++)),
  ]);
}

Future<void> _open(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Consumer(
        builder: (ctx, ref, _) => Scaffold(
          body: Builder(
            builder: (b) => TextButton(
              onPressed: () => showAddToPlaylistSheet(b, ref, const [_v]),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the playlists and adds to the one tapped', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store);
    addTearDown(c.dispose);
    await c.read(playlistsProvider.notifier).create('Serie');

    await _open(tester, c);
    expect(find.text('Serie'), findsOneWidget);

    await tester.tap(find.text('Serie'));
    await tester.pumpAndSettle();

    expect(store.all().single.entries.single.displayName, 'ep1.mkv');
  });

  testWidgets('creating a new list from the sheet adds the videos to it',
      (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store);
    addTearDown(c.dispose);

    await _open(tester, c);
    await tester.tap(find.text('Nueva lista'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Curso');
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();

    expect(store.all().single.name, 'Curso');
    expect(store.all().single.entries.single.displayName, 'ep1.mkv');
  });

  testWidgets('a blank name is refused rather than creating «»', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store);
    addTearDown(c.dispose);

    await _open(tester, c);
    await tester.tap(find.text('Nueva lista'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();

    expect(store.all(), isEmpty);
  });

  testWidgets('with no playlists yet it says so and still offers to create one',
      (tester) async {
    final c = await _c(InMemoryPlaylistStore());
    addTearDown(c.dispose);

    await _open(tester, c);
    expect(find.textContaining('Todavía no tienes listas'), findsOneWidget);
    expect(find.text('Nueva lista'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/home/add_to_playlist_sheet_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

Build a `showModalBottomSheet` following the shape of `lib/ui/home/widgets/video_options_sheet.dart` (read it first for the row idiom and colour usage). It contains:

- a title, `Añadir a lista`
- when `playlistsProvider` is empty: the line `Todavía no tienes listas. Crea una para empezar.`
- otherwise a row per playlist showing its name and its entry count, which on tap calls `addVideos(playlist.id, videos)`, pops, and shows a SnackBar naming the playlist
- a final row `Nueva lista` which opens an `AlertDialog` with a `TextField`, a `Cancelar` and a `Crear`; `Crear` with a blank or whitespace-only name does nothing (the dialog stays open), otherwise it creates the playlist, adds the videos, and pops both

Capture the `ScaffoldMessenger` before any `await`, and never use a `BuildContext` after one — follow the pattern already used in `lib/ui/player/tracks/track_picker.dart`'s `_pickManualSubtitle`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/ui/home/add_to_playlist_sheet_test.dart && flutter analyze --no-pub`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/home/playlists/add_to_playlist_sheet.dart test/ui/home/add_to_playlist_sheet_test.dart
git commit -m "feat(playlists): add-to-playlist sheet"
```

---

### Task 7: Wire the sheet into the two entry points

**Files:**
- Modify: `lib/ui/home/widgets/selection_bottom_bar.dart`
- Modify: `lib/ui/home/widgets/video_options_sheet.dart`
- Test: `test/ui/home/playlist_entry_points_test.dart`

**Interfaces:**
- Consumes: `showAddToPlaylistSheet` (Task 6).
- Produces: nothing new.

`SelectionBottomBar` builds its actions with a local `_action(color, icon, label, onTap)` helper; the row currently holds Al Vault / Compartir / Borrar. `video_options_sheet.dart` builds rows with a local `_row(context, icon, label, color, onTap)`; it currently holds Compartir / Renombrar / Detalles / Mover al Vault / Borrar. Read both before editing and follow their existing idiom exactly.

- [ ] **Step 1: Write the failing test**

This harness is lifted from `test/ui/home/selection_bottom_bar_test.dart`, which
already mounts this widget — read that file and keep the two in step.

```dart
// test/ui/home/playlist_entry_points_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/home/state/library_selection.dart';
import 'package:kivo_player/ui/home/widgets/selection_bottom_bar.dart';
import '../../fakes/fakes.dart';

const _a = VideoItem(
    id: '1', uri: 'u1', name: 'a.mp4', folder: 'F',
    durationMs: 1, sizeBytes: 1, dateAddedMs: 0);

class _Perm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

void main() {
  testWidgets('the selection bar offers adding to a playlist', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    var tick = 0;
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaFileOpsProvider.overrideWithValue(FakeMediaFileOps()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer([_a])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      playlistStoreProvider.overrideWithValue(InMemoryPlaylistStore()),
      playlistClockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(1000 + tick++)),
    ]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    c.read(librarySelectionProvider.notifier).selectAll(['u1']);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(bottomNavigationBar: SelectionBottomBar()),
      ),
    ));
    await tester.pumpAndSettle();

    // Only that the entry point exists and is reachable — the sheet itself is
    // covered by its own test.
    expect(find.text('A lista'), findsOneWidget);
  });
}
```

Add a second test in the same file for the video `⋮` sheet, modelled on
`test/ui/home/video_options_sheet_test.dart`: open the sheet and assert
`find.text('Añadir a lista')` finds one widget.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/home/playlist_entry_points_test.dart`
Expected: FAIL — the labels are not there yet.

- [ ] **Step 3: Write the implementation**

In `selection_bottom_bar.dart`, add an action beside the existing three:

```dart
              _action(cs.onSurface, Icons.playlist_add, 'A lista', enabled ? () async {
                final items = chosen;
                sel.clear();
                await showAddToPlaylistSheet(context, ref, items);
              } : null),
```

Note the ordering: the selection is cleared *before* the sheet opens, matching the Al Vault action directly above it — the bar disappearing immediately is what stops a slow operation from inviting repeat taps.

In `video_options_sheet.dart`, add a row between Detalles and Mover al Vault:

```dart
          _row(context, Icons.playlist_add, 'Añadir a lista', cs.onSurface, onAddToPlaylist),
```

following how the sheet's other callbacks are declared and passed in — it takes them as constructor parameters, so add one more and wire it at the call site the same way `onMoveToVault` is.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test && flutter analyze --no-pub`
Expected: PASS — run the FULL suite; this touches shared widgets.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/home/widgets/selection_bottom_bar.dart lib/ui/home/widgets/video_options_sheet.dart test/ui/home/playlist_entry_points_test.dart
git commit -m "feat(playlists): add to a playlist from selection and from a video"
```

---

### Task 8: The Listas tab

**Files:**
- Create: `lib/ui/home/playlists/playlists_tab.dart`
- Modify: `lib/ui/home/library_screen.dart`
- Test: `test/ui/home/playlists_tab_test.dart`

**Interfaces:**
- Consumes: `playlistsProvider` (Task 3), `resolvedPlaylistProvider` (Task 4).
- Produces: `class PlaylistsTab extends ConsumerWidget` (const constructor).

`library_screen.dart` holds `int _tab = 0; // 0 = Todo, 1 = Carpetas`, a `_FilterChips(selected:, onChanged:, showUnwatchedToggle:, ...)` whose `_chip(context, cs, 'Todo', 0)` / `_chip(context, cs, 'Carpetas', 1)` calls define the labels, and a `PageView` with two `_KeepAlivePage` children keyed `ValueKey(0)` and `ValueKey(1)`. Add a third of each.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/home/playlists_tab_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';
import 'package:kivo_player/ui/home/playlists/playlists_tab.dart';
import '../../fakes/fakes.dart';

VideoItem _v(String id, String name) => VideoItem(
      id: id,
      uri: 'content://$id',
      name: name,
      folder: 'Series',
      durationMs: 1000,
      sizeBytes: 10,
      dateAddedMs: 0,
    );

// Copy the mediaIndexerProvider / mediaPermissionImplProvider overrides from an
// existing test in test/player/library/ — do not invent fake names.
Future<ProviderContainer> _c(PlaylistStore store, List<VideoItem> index) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  var tick = 0;
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(index)),
    playlistStoreProvider.overrideWithValue(store),
    playlistClockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(1000 + tick++)),
  ]);
}

Future<void> _pump(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: Scaffold(body: PlaylistsTab())),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with no playlists it explains what they are for', (tester) async {
    final c = await _c(InMemoryPlaylistStore(), const []);
    addTearDown(c.dispose);
    await _pump(tester, c);

    expect(find.textContaining('Todavía no tienes listas'), findsOneWidget);
  });

  testWidgets('shows each playlist with how many videos it holds',
      (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);

    await _pump(tester, c);

    expect(find.text('Serie'), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets);
  });

  testWidgets('a playlist whose videos are all missing still appears',
      (tester) async {
    // The list is the user's; an empty device does not delete it.
    final store = InMemoryPlaylistStore();
    final c = await _c(store, const []);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    await _pump(tester, c);
    expect(find.text('Serie'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/home/playlists_tab_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

`PlaylistsTab` renders:
- when `playlistsProvider` is empty, a centred empty state: `Todavía no tienes listas.` plus a line explaining that a playlist is an order you choose, and a button `Nueva lista`
- otherwise a `ListView` of playlists, each row showing the name, the count of entries (and, when some are unavailable, how many are missing), and a cover thumbnail taken from the first available entry using the existing `ThumbnailImage` widget from `lib/ui/home/widgets/thumbnail_image.dart`
- a `Nueva lista` affordance always reachable

Tapping a row pushes the playlist screen (Task 9) with `Navigator.of(context).push`.

Then in `library_screen.dart`: add `'Listas'` as `_chip(context, cs, 'Listas', 2)`, add a third `_KeepAlivePage(key: const ValueKey(2), child: const PlaylistsTab())` to the `PageView`, and confirm the `_pageController.animateToPage` call and the selection-clearing `onChanged` still behave — the existing `if (i != _tab) clear()` already covers the new tab.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test && flutter analyze --no-pub`
Expected: PASS — full suite, since `library_screen.dart` is shared.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/home/playlists/playlists_tab.dart lib/ui/home/library_screen.dart test/ui/home/playlists_tab_test.dart
git commit -m "feat(playlists): the Listas tab"
```

---

### Task 9: The playlist screen

**Files:**
- Create: `lib/ui/home/playlists/playlist_screen.dart`
- Test: `test/ui/home/playlist_screen_test.dart`

**Interfaces:**
- Consumes: `playlistsProvider` (Task 3) · `resolvedPlaylistProvider`, `playlistPlaybackProvider` (Task 4).
- Produces: `class PlaylistScreen extends ConsumerWidget` taking a `String playlistId`.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/home/playlist_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/player/playlists/playlist_store.dart';
import 'package:kivo_player/ui/home/playlists/playlist_screen.dart';
import '../../fakes/fakes.dart';

VideoItem _v(String id, String name) => VideoItem(
      id: id,
      uri: 'content://$id',
      name: name,
      folder: 'Series',
      durationMs: 1000,
      sizeBytes: 10,
      dateAddedMs: 0,
    );

// Copy the media-index overrides from an existing library test.
Future<ProviderContainer> _c(PlaylistStore store, List<VideoItem> index) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  var tick = 0;
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(index)),
    playlistStoreProvider.overrideWithValue(store),
    playlistClockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(1000 + tick++)),
  ]);
}

void main() {
  testWidgets('lists the entries in playlist order', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, [_v('1', 'a.mkv'), _v('2', 'b.mkv')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier)
        .addVideos(p.id, [_v('2', 'b.mkv'), _v('1', 'a.mkv')]);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: PlaylistScreen(playlistId: p.id)),
    ));
    await tester.pumpAndSettle();

    final rows = tester.widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(rows.indexOf('b.mkv') < rows.indexOf('a.mkv'), true);
  });

  testWidgets('a missing video is shown and marked, not hidden', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, const []); // nothing on the device
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: PlaylistScreen(playlistId: p.id)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('a.mkv'), findsOneWidget);
    expect(find.textContaining('No disponible'), findsOneWidget);
  });

  testWidgets('tapping a missing entry does not start playback', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, const []);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: PlaylistScreen(playlistId: p.id)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('a.mkv'));
    await tester.pumpAndSettle();

    expect(c.read(currentVideoProvider), isNull);
  });

  testWidgets('removing an entry takes it off the screen', (tester) async {
    final store = InMemoryPlaylistStore();
    final c = await _c(store, [_v('1', 'a.mkv')]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    final p = await c.read(playlistsProvider.notifier).create('Serie');
    await c.read(playlistsProvider.notifier).addVideos(p.id, [_v('1', 'a.mkv')]);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: PlaylistScreen(playlistId: p.id)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('playlist-remove-0')));
    await tester.pumpAndSettle();

    expect(find.text('a.mkv'), findsNothing);
    expect(store.all().single.entries, isEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/home/playlist_screen_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

`PlaylistScreen` is a `Scaffold` with:
- an `AppBar` titled with the playlist name, and an overflow menu offering `Renombrar lista` (an `AlertDialog` with a `TextField`, refusing a blank name) and `Borrar lista` (a confirm dialog, then `delete` and `Navigator.pop`)
- a play button that calls `playlistPlaybackProvider.play(playlistId)`; when it returns false, a SnackBar saying nothing in the list is available right now
- a `ReorderableListView` over `resolvedPlaylistProvider(playlistId)`, each row keyed `ValueKey('playlist-entry-$index')` showing the video name and, for an unavailable entry, the label `No disponible` with the row at reduced opacity and inert on tap
- a remove button per row keyed `ValueKey('playlist-remove-$index')` calling `removeEntryAt`
- `onReorder` calling `reorder(playlistId, oldIndex, newIndex)` — note Flutter's `ReorderableListView` reports `newIndex` one higher than the final position when moving down, so subtract one in that case before calling through

Tapping an available row calls `playAt(playlistId, index)` and, on true, pushes the player the same way the library does — read `lib/ui/home/library_screen.dart`'s open path and follow it exactly, including the `playerRoute` origin-rect argument if one is passed there.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test && flutter analyze --no-pub`
Expected: PASS, full suite.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/home/playlists/playlist_screen.dart test/ui/home/playlist_screen_test.dart
git commit -m "feat(playlists): the playlist screen"
```

---

## Final checklist

- [ ] `flutter test` — full suite green.
- [ ] `flutter analyze --no-pub` — down to the 3 pre-existing infos.
- [ ] No `Co-Authored-By` trailer on any commit in the branch.
- [ ] **Device check** (nothing here is provable in a unit test): create a playlist from a multi-selection; reorder it by dragging; play it and confirm autoplay walks the playlist order rather than the library's; rename a video in it and confirm the entry survives; unplug/hide a video and confirm the entry greys out instead of vanishing.
- [ ] Bump `pubspec.yaml`, tag, push the tag — the release workflow publishes the signed APKs and now writes real notes from the commit subjects.
