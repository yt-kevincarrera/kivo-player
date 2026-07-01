# Kivo 2c Search/Sort/Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Activate the library's deferred search and sort icons, and add a "No vistos" (unwatched-only) toggle — all composable, backed by one pure filtering function.

**Architecture:** Task 1 is the pure data layer (a `librarySort` setting field mirroring the existing `themeMode` pattern, a `LibrarySort` enum + mapping helper, and the pure `applyLibraryFilters` function) — fully unit-testable without widgets. Task 2 wires it into `LibraryScreen`'s AppBar and body (search field, sort menu, "No vistos" chip, search-results view) and depends on Task 1.

**Tech Stack:** Flutter (Material 3), Riverpod.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-01-kivo-2c-search-sort-filter-design.md`.
- Search matches video name **or** folder name, case-insensitive; results are a flat list (no date grouping).
- Sort has 7 values; `recent` (default) groups by day like today; any other sort is a flat list (no date headers).
- "No vistos" is a toggle (not a tab): visible next to Todo|Carpetas only when the "Todo" tab is active, and also visible during search; hidden on "Carpetas".
- Search, sort, and "No vistos" compose (can combine).
- `librarySort` persists in `KivoSettings` (like `themeMode`); search query/active state and "No vistos" do NOT persist (reset each app launch).
- `flutter analyze` clean + `flutter test` green before each commit. Do not push.

---

### Task 1: `librarySort` setting + `LibrarySort` enum + `applyLibraryFilters`

**Files:**
- Modify: `lib/core/settings/kivo_settings.dart`
- Create: `lib/player/library/library_filter.dart`
- Create: `lib/ui/home/state/library_filter_state.dart`
- Test: `test/player/library/library_filter_test.dart` (new)

**Interfaces:**
- Produces: `KivoSettings.librarySort` (`String`, default `'recent'`); `enum LibrarySort { recent, nameAsc, nameDesc, durationAsc, durationDesc, sizeAsc, sizeDesc }`; `LibrarySort librarySortFor(String value)`; `List<VideoItem> applyLibraryFilters(List<VideoItem> videos, {String query = '', LibrarySort sort = LibrarySort.recent, bool unwatchedOnly = false, Set<String> playedKeys = const {}})`; `librarySearchActiveProvider` (`StateProvider<bool>`, default `false`); `librarySearchQueryProvider` (`StateProvider<String>`, default `''`); `libraryUnwatchedOnlyProvider` (`StateProvider<bool>`, default `false`).

- [ ] **Step 1: Add `librarySort` to `KivoSettings`.** This mirrors the existing `themeMode` field exactly (`lib/core/settings/kivo_settings.dart`). Add in these 5 places:
  1. Field declaration, right after `final String themeMode; // 'auto' | 'light' | 'dark'`:
     ```dart
     final String librarySort; // LibrarySort enum name — see lib/player/library/library_filter.dart
     ```
  2. Constructor: add `required this.librarySort,` right after `required this.themeMode,`.
  3. `defaults()` factory: add `librarySort: 'recent',` right after `themeMode: 'auto',`.
  4. `copyWith`: add `String? librarySort,` to the parameter list (after `String? themeMode,`) and `librarySort: librarySort ?? this.librarySort,` in the returned `KivoSettings(...)` (after `themeMode: themeMode ?? this.themeMode,`).
  5. `toMap()`: add `'librarySort': librarySort,` after `'themeMode': themeMode,`.
  6. `fromMap()`: add `librarySort: m['librarySort'] ?? d.librarySort,` after `themeMode: m['themeMode'] ?? d.themeMode,`.

- [ ] **Step 2: Create `lib/player/library/library_filter.dart`.**
```dart
import '../../platform/interfaces/media_indexer.dart';

enum LibrarySort {
  recent,
  nameAsc,
  nameDesc,
  durationAsc,
  durationDesc,
  sizeAsc,
  sizeDesc,
}

/// Maps a persisted `KivoSettings.librarySort` string (the enum's `.name`)
/// back to [LibrarySort], defaulting to [LibrarySort.recent] for anything
/// unrecognized (e.g. a future rollback reading an unknown value).
LibrarySort librarySortFor(String value) => LibrarySort.values.firstWhere(
      (s) => s.name == value,
      orElse: () => LibrarySort.recent,
    );

/// The single source of truth for "what videos show, in what order" in the
/// Todo tab and in search results. Pure — no Riverpod, no widgets.
List<VideoItem> applyLibraryFilters(
  List<VideoItem> videos, {
  String query = '',
  LibrarySort sort = LibrarySort.recent,
  bool unwatchedOnly = false,
  Set<String> playedKeys = const {},
}) {
  var out = videos;
  if (query.trim().isNotEmpty) {
    final q = query.trim().toLowerCase();
    out = out
        .where((v) =>
            v.name.toLowerCase().contains(q) ||
            v.folder.toLowerCase().contains(q))
        .toList();
  }
  if (unwatchedOnly) {
    out = out.where((v) => !playedKeys.contains(v.name)).toList();
  }
  out = [...out];
  switch (sort) {
    case LibrarySort.recent:
      out.sort((a, b) => b.dateAddedMs.compareTo(a.dateAddedMs));
    case LibrarySort.nameAsc:
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    case LibrarySort.nameDesc:
      out.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    case LibrarySort.durationAsc:
      out.sort((a, b) => a.durationMs.compareTo(b.durationMs));
    case LibrarySort.durationDesc:
      out.sort((a, b) => b.durationMs.compareTo(a.durationMs));
    case LibrarySort.sizeAsc:
      out.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
    case LibrarySort.sizeDesc:
      out.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
  }
  return out;
}
```

- [ ] **Step 3: Create `lib/ui/home/state/library_filter_state.dart`.**
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while the library's search field is expanded in the AppBar
/// (replacing the "Kivo" title). Reset to false (and the query cleared)
/// when the user taps the close (X) button.
final librarySearchActiveProvider = StateProvider<bool>((ref) => false);

/// The current search text. Not persisted — resets on app restart, like
/// closing search does.
final librarySearchQueryProvider = StateProvider<String>((ref) => '');

/// "No vistos" toggle — shows only never-played videos when true. Not
/// persisted (unlike `KivoSettings.librarySort`).
final libraryUnwatchedOnlyProvider = StateProvider<bool>((ref) => false);
```

- [ ] **Step 4: Write `test/player/library/library_filter_test.dart`.**
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/library/library_filter.dart';

const _beta = VideoItem(id: '1', uri: 'content://1', name: 'Beta.mp4', folder: 'Movies', durationMs: 60000, sizeBytes: 500, dateAddedMs: 100);
const _alpha = VideoItem(id: '2', uri: 'content://2', name: 'Alpha.mp4', folder: 'Trips', durationMs: 120000, sizeBytes: 200, dateAddedMs: 300);
const _gamma = VideoItem(id: '3', uri: 'content://3', name: 'Gamma.mp4', folder: 'Movies', durationMs: 30000, sizeBytes: 900, dateAddedMs: 200);

void main() {
  final videos = [_beta, _alpha, _gamma];

  test('KivoSettings.librarySort defaults to recent and round-trips', () {
    expect(KivoSettings.defaults().librarySort, 'recent');
    final m = KivoSettings.defaults().copyWith(librarySort: 'nameAsc').toMap();
    expect(KivoSettings.fromMap(m).librarySort, 'nameAsc');
  });

  test('librarySortFor maps known strings and falls back to recent', () {
    expect(librarySortFor('nameAsc'), LibrarySort.nameAsc);
    expect(librarySortFor('sizeDesc'), LibrarySort.sizeDesc);
    expect(librarySortFor('not-a-real-value'), LibrarySort.recent);
  });

  group('applyLibraryFilters sort', () {
    test('recent: newest dateAddedMs first', () {
      final out = applyLibraryFilters(videos, sort: LibrarySort.recent);
      expect(out.map((v) => v.name), ['Alpha.mp4', 'Gamma.mp4', 'Beta.mp4']);
    });
    test('nameAsc: alphabetical', () {
      final out = applyLibraryFilters(videos, sort: LibrarySort.nameAsc);
      expect(out.map((v) => v.name), ['Alpha.mp4', 'Beta.mp4', 'Gamma.mp4']);
    });
    test('nameDesc: reverse alphabetical', () {
      final out = applyLibraryFilters(videos, sort: LibrarySort.nameDesc);
      expect(out.map((v) => v.name), ['Gamma.mp4', 'Beta.mp4', 'Alpha.mp4']);
    });
    test('durationAsc: shortest first', () {
      final out = applyLibraryFilters(videos, sort: LibrarySort.durationAsc);
      expect(out.map((v) => v.name), ['Gamma.mp4', 'Beta.mp4', 'Alpha.mp4']);
    });
    test('durationDesc: longest first', () {
      final out = applyLibraryFilters(videos, sort: LibrarySort.durationDesc);
      expect(out.map((v) => v.name), ['Alpha.mp4', 'Beta.mp4', 'Gamma.mp4']);
    });
    test('sizeAsc: lightest first', () {
      final out = applyLibraryFilters(videos, sort: LibrarySort.sizeAsc);
      expect(out.map((v) => v.name), ['Alpha.mp4', 'Beta.mp4', 'Gamma.mp4']);
    });
    test('sizeDesc: heaviest first', () {
      final out = applyLibraryFilters(videos, sort: LibrarySort.sizeDesc);
      expect(out.map((v) => v.name), ['Gamma.mp4', 'Beta.mp4', 'Alpha.mp4']);
    });
  });

  group('applyLibraryFilters query', () {
    test('matches by file name, case-insensitive', () {
      final out = applyLibraryFilters(videos, query: 'ALPHA');
      expect(out.map((v) => v.name), ['Alpha.mp4']);
    });
    test('matches by folder name, case-insensitive', () {
      final out = applyLibraryFilters(videos, query: 'movies');
      expect(out.map((v) => v.name).toSet(), {'Beta.mp4', 'Gamma.mp4'});
    });
    test('no match returns an empty list', () {
      expect(applyLibraryFilters(videos, query: 'zzz'), isEmpty);
    });
  });

  test('applyLibraryFilters unwatchedOnly excludes played keys', () {
    final out = applyLibraryFilters(videos, unwatchedOnly: true, playedKeys: {'Alpha.mp4'});
    expect(out.map((v) => v.name).toSet(), {'Beta.mp4', 'Gamma.mp4'});
  });

  test('applyLibraryFilters composes query + unwatchedOnly + sort', () {
    final out = applyLibraryFilters(
      videos,
      query: 'movies',
      unwatchedOnly: true,
      playedKeys: {'Gamma.mp4'},
      sort: LibrarySort.nameAsc,
    );
    expect(out.map((v) => v.name), ['Beta.mp4']);
  });
}
```

- [ ] **Step 5: Run the test to verify it fails, then implement until it passes.**

Run: `flutter test test/player/library/library_filter_test.dart -v`
Expected before Steps 1-3: FAIL (files/fields don't exist).
After Steps 1-3: Expected PASS (17 tests).

- [ ] **Step 6: Run the full suite and analyze.**

Run: `flutter analyze` — expect "No issues found!"
Run: `flutter test` — expect all tests pass (128 prior + 17 new).

- [ ] **Step 7: Commit**

```bash
git add lib/core/settings/kivo_settings.dart lib/player/library/library_filter.dart lib/ui/home/state/library_filter_state.dart test/player/library/library_filter_test.dart
git commit -m "feat: librarySort setting + LibrarySort enum + applyLibraryFilters (pure)"
```

---

### Task 2: Wire search, sort, and "No vistos" into `LibraryScreen`

**Files:**
- Modify: `lib/ui/home/library_screen.dart`
- Test: `test/ui/home/library_screen_test.dart` (extend)

**Interfaces:**
- Consumes (Task 1): `librarySortFor`, `applyLibraryFilters`, `LibrarySort` (`lib/player/library/library_filter.dart`); `librarySearchActiveProvider`, `librarySearchQueryProvider`, `libraryUnwatchedOnlyProvider` (`lib/ui/home/state/library_filter_state.dart`); `settings.librarySort` (String).

- [ ] **Step 1: Read the current `lib/ui/home/library_screen.dart` in full** before editing — it has `_LibraryScreenState` with `_tab`, `_shareSub`, `_pageController`; methods `_push`/`_openPath`/`_open`/`_pick`/`_cycleDensity`/`_setColumns`; `build()` (Scaffold/AppBar with density+file-picker icons, title "Kivo"); `_body()` (chips + PageView); `_videosTab(videos)` (returns `VideoDensityFeed(videos, onOpen, groupByDate: true, showContinueRow: true)`); `_foldersTab(videos)`; `_accessPrompt()`; `_FilterChips` (Todo|Carpetas segmented chips); `_KeepAlivePage` (AutomaticKeepAliveClientMixin wrapper — do not touch).

- [ ] **Step 2: Add imports.** At the top of `library_screen.dart`, add:
```dart
import '../../player/library/library_filter.dart';
import 'state/library_filter_state.dart';
```

- [ ] **Step 3: Add a search text controller.** In `_LibraryScreenState`, add a field and wire its lifecycle:
```dart
final _searchController = TextEditingController();
```
In `dispose()`, add `_searchController.dispose();` (alongside the existing `_shareSub?.cancel();`/`_pageController.dispose();`).

- [ ] **Step 4: Add search open/close methods.** Add to `_LibraryScreenState`:
```dart
void _openSearch() {
  ref.read(librarySearchActiveProvider.notifier).state = true;
}

void _closeSearch() {
  ref.read(librarySearchActiveProvider.notifier).state = false;
  ref.read(librarySearchQueryProvider.notifier).state = '';
  _searchController.clear();
}
```

- [ ] **Step 5: Rewrite `build()`'s AppBar.** Replace the current `AppBar(...)` with:
```dart
appBar: AppBar(
  titleSpacing: 12,
  title: ref.watch(librarySearchActiveProvider)
      ? TextField(
          controller: _searchController,
          autofocus: true,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: const InputDecoration(
            hintText: 'Buscar videos o carpetas',
            border: InputBorder.none,
          ),
          onChanged: (q) =>
              ref.read(librarySearchQueryProvider.notifier).state = q,
        )
      : Text(
          'Kivo',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
  actions: [
    if (ref.watch(librarySearchActiveProvider))
      IconButton(
        tooltip: 'Cerrar búsqueda',
        icon: const Icon(Icons.close),
        onPressed: _closeSearch,
      )
    else
      IconButton(
        tooltip: 'Buscar',
        icon: const Icon(Icons.search),
        onPressed: _openSearch,
      ),
    if (ref.watch(librarySearchActiveProvider) || _tab == 0)
      const _SortMenuButton(),
    if (!ref.watch(librarySearchActiveProvider)) ...[
      IconButton(
        tooltip: 'Cambiar densidad',
        icon: const Icon(Icons.grid_view),
        onPressed: _cycleDensity,
      ),
      IconButton(
        tooltip: 'Abrir archivo',
        icon: KivoIcon(KivoIcons.folderOpen, size: 22),
        onPressed: _pick,
      ),
    ],
  ],
),
```
(Density and file-picker icons hide while searching to keep the search app bar uncluttered — a minor UI call within the spec's "mantén la barra limpia" intent; the sort icon stays available since sort composes with search.)

- [ ] **Step 6: Rewrite `_body()`** to branch on search-active, and thread sort/unwatched into the Todo tab:
```dart
Widget _body() {
  final index = ref.watch(mediaIndexProvider);
  return index.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (e, __) => Center(
      child: Text(
        'Error: $e',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
    data: (videos) {
      if (ref.watch(librarySearchActiveProvider)) {
        return _searchResults(videos);
      }
      return Column(
        children: [
          _FilterChips(
            selected: _tab,
            onChanged: (i) {
              setState(() => _tab = i);
              _pageController.animateToPage(
                i,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
              );
            },
            showUnwatchedToggle: _tab == 0,
            unwatchedOnly: ref.watch(libraryUnwatchedOnlyProvider),
            onToggleUnwatched: () {
              final notifier = ref.read(libraryUnwatchedOnlyProvider.notifier);
              notifier.state = !notifier.state;
            },
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _KeepAlivePage(key: const ValueKey(0), child: _videosTab(videos)),
                _KeepAlivePage(key: const ValueKey(1), child: _foldersTab(videos)),
              ],
            ),
          ),
        ],
      );
    },
  );
}

Widget _searchResults(List<VideoItem> videos) {
  final query = ref.watch(librarySearchQueryProvider);
  final sort = librarySortFor(ref.watch(settingsProvider).librarySort);
  final unwatchedOnly = ref.watch(libraryUnwatchedOnlyProvider);
  final played = ref.watch(playedKeysProvider);
  final filtered = applyLibraryFilters(
    videos,
    query: query,
    sort: sort,
    unwatchedOnly: unwatchedOnly,
    playedKeys: played,
  );
  final cs = Theme.of(context).colorScheme;
  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          children: [
            _UnwatchedChip(
              active: unwatchedOnly,
              onTap: () => ref
                  .read(libraryUnwatchedOnlyProvider.notifier)
                  .state = !unwatchedOnly,
            ),
          ],
        ),
      ),
      Expanded(
        child: query.trim().isEmpty || filtered.isNotEmpty
            ? VideoDensityFeed(
                videos: filtered,
                onOpen: (v, all) => _open(v, all),
                groupByDate: sort == LibrarySort.recent,
                showContinueRow: false,
              )
            : Center(
                child: Text(
                  'No se encontraron videos para "$query"',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
      ),
    ],
  );
}
```
Add `import '../../platform/interfaces/media_indexer.dart';` if `VideoItem` isn't already imported directly (check — `library_screen.dart` already imports it for `_open(VideoItem v, ...)`'s signature, so this should already be present).

- [ ] **Step 7: Apply sort + "No vistos" in `_videosTab`.** Change:
```dart
Widget _videosTab(List<VideoItem> videos) => VideoDensityFeed(
      videos: videos,
      onOpen: (v, all) => _open(v, all),
      groupByDate: true,
      showContinueRow: true,
    );
```
to:
```dart
Widget _videosTab(List<VideoItem> videos) {
  final sort = librarySortFor(ref.watch(settingsProvider).librarySort);
  final unwatchedOnly = ref.watch(libraryUnwatchedOnlyProvider);
  final played = ref.watch(playedKeysProvider);
  final filtered = applyLibraryFilters(
    videos,
    sort: sort,
    unwatchedOnly: unwatchedOnly,
    playedKeys: played,
  );
  return VideoDensityFeed(
    videos: filtered,
    onOpen: (v, all) => _open(v, all),
    groupByDate: sort == LibrarySort.recent,
    showContinueRow: true,
  );
}
```
(`settingsProvider` and `playedKeysProvider` are already imported in this file — verify with `flutter analyze`, both are used elsewhere already: `settingsProvider` by `_cycleDensity`/`_setColumns`, `playedKeysProvider` was added in an earlier round for `isNew` wiring inside `VideoDensityFeed` itself, not directly in `library_screen.dart` — add the import `import '../../player/library/played.dart';` if `flutter analyze` flags `playedKeysProvider` as undefined here.)

- [ ] **Step 8: Extend `_FilterChips`** to accept the "No vistos" toggle and render it conditionally:
```dart
class _FilterChips extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  final bool showUnwatchedToggle;
  final bool unwatchedOnly;
  final VoidCallback onToggleUnwatched;

  const _FilterChips({
    required this.selected,
    required this.onChanged,
    required this.showUnwatchedToggle,
    required this.unwatchedOnly,
    required this.onToggleUnwatched,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          _chip(context, cs, 'Todo', 0),
          const SizedBox(width: 8),
          _chip(context, cs, 'Carpetas', 1),
          if (showUnwatchedToggle) ...[
            const SizedBox(width: 8),
            _UnwatchedChip(active: unwatchedOnly, onTap: onToggleUnwatched),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, ColorScheme cs, String label, int i) {
    final active = selected == i;
    return GestureDetector(
      onTap: () => onChanged(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? KivoColors.blue : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : cs.onSurfaceVariant,
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
```
(This is the existing `_FilterChips` with the 3 new required params and the conditional `_UnwatchedChip` added — the `_chip` helper is unchanged.)

- [ ] **Step 9: Add `_UnwatchedChip` and `_SortMenuButton`** at the bottom of the file (after `_FilterChips`, before `_KeepAlivePage`):
```dart
// ---------------------------------------------------------------------------
// "No vistos" toggle — a filter, not a tab (visually distinct from _chip).
// ---------------------------------------------------------------------------
class _UnwatchedChip extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _UnwatchedChip({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? KivoColors.blue : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility_off_outlined,
              size: 14,
              color: active ? Colors.white : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              'No vistos',
              style: TextStyle(
                color: active ? Colors.white : cs.onSurfaceVariant,
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sort menu — reads/writes settings.librarySort directly (like libraryColumns).
// ---------------------------------------------------------------------------
class _SortMenuButton extends ConsumerWidget {
  const _SortMenuButton();

  static const _labels = {
    LibrarySort.recent: 'Más reciente',
    LibrarySort.nameAsc: 'Nombre A-Z',
    LibrarySort.nameDesc: 'Nombre Z-A',
    LibrarySort.durationDesc: 'Duración: más larga',
    LibrarySort.durationAsc: 'Duración: más corta',
    LibrarySort.sizeDesc: 'Tamaño: más pesado',
    LibrarySort.sizeAsc: 'Tamaño: más liviano',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = librarySortFor(ref.watch(settingsProvider).librarySort);
    return PopupMenuButton<LibrarySort>(
      tooltip: 'Ordenar',
      icon: const Icon(Icons.sort),
      onSelected: (sort) {
        final s = ref.read(settingsProvider);
        ref.read(settingsProvider.notifier).set(s.copyWith(librarySort: sort.name));
      },
      itemBuilder: (context) => _labels.entries.map((e) {
        return PopupMenuItem<LibrarySort>(
          value: e.key,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: e.key == current ? const Icon(Icons.check, size: 18) : null,
              ),
              const SizedBox(width: 6),
              Text(e.value),
            ],
          ),
        );
      }).toList(),
    );
  }
}
```

- [ ] **Step 10: Update `test/ui/home/library_screen_test.dart`.** Read the current file first — it has a `_buildApp(tester)` helper (with `_videos` = `[Inception.mp4 in Movies, Avatar.mp4 in Downloads]`, both `dateAddedMs: 1`) and 6 existing `testWidgets`. Add these new tests at the end of `main()`, inside the existing `void main() { ... }` block:
```dart
  testWidgets('tapping search shows a text field and hides the title',
      (tester) async {
    await _buildApp(tester);
    expect(find.text('Kivo'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();

    expect(find.text('Kivo'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('typing a query filters to matching videos', (tester) async {
    await _buildApp(tester);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'inception');
    await tester.pump();

    expect(find.text('Inception.mp4'), findsOneWidget);
    expect(find.text('Avatar.mp4'), findsNothing);
  });

  testWidgets('search matches by folder name too', (tester) async {
    await _buildApp(tester);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'downloads');
    await tester.pump();

    expect(find.text('Avatar.mp4'), findsOneWidget);
    expect(find.text('Inception.mp4'), findsNothing);
  });

  testWidgets('closing search restores the title and clears the query',
      (tester) async {
    await _buildApp(tester);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'inception');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.text('Kivo'), findsOneWidget);
    expect(find.text('Inception.mp4'), findsOneWidget);
    expect(find.text('Avatar.mp4'), findsOneWidget);
  });

  testWidgets('no search matches shows the empty message', (tester) async {
    await _buildApp(tester);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'zzz-no-match');
    await tester.pump();

    expect(find.text('No se encontraron videos para "zzz-no-match"'), findsOneWidget);
  });

  testWidgets('sort menu changes order to alphabetical', (tester) async {
    await _buildApp(tester);
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nombre A-Z'));
    await tester.pumpAndSettle();

    final avatarCenter = tester.getCenter(find.text('Avatar.mp4'));
    final inceptionCenter = tester.getCenter(find.text('Inception.mp4'));
    expect(avatarCenter.dy, lessThan(inceptionCenter.dy));
  });

  testWidgets('"No vistos" chip is hidden on the Carpetas tab', (tester) async {
    await _buildApp(tester);
    expect(find.text('No vistos'), findsOneWidget);

    await tester.tap(find.text('Carpetas'));
    await tester.pumpAndSettle();

    expect(find.text('No vistos'), findsNothing);
  });
```
Add `import 'package:flutter/material.dart';` if `TextField`/`Icons` aren't already resolved via an existing import (the file already imports `package:flutter/material.dart` per its current header — verify, don't duplicate).

- [ ] **Step 11: Run the tests to verify they fail, then implement/fix until they pass.**

Run: `flutter test test/ui/home/library_screen_test.dart -v`
Expected before Steps 2-9: FAIL (icons/fields don't exist).
After Steps 2-9: Expected PASS (13 tests: 6 existing + 7 new).

- [ ] **Step 12: Run the full suite and analyze.**

Run: `flutter analyze` — expect "No issues found!"
Run: `flutter test` — expect all tests pass (145 prior + new from this task).

- [ ] **Step 13: Commit**

```bash
git add lib/ui/home/library_screen.dart test/ui/home/library_screen_test.dart
git commit -m "feat: library search, sort menu, and No vistos filter"
```

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review (opus).
3. Release build to the Pixel 6: search finds a video by its own name and by its folder's name; closing search clears it; sort menu reorders the Todo feed and drops date headers for non-"reciente" orders; "No vistos" hides played videos and disappears on the Carpetas tab; all three compose (e.g. search + "No vistos" + a custom sort together).
