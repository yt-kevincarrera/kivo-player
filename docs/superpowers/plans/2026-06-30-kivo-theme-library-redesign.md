# Theme + Library Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a light/dark/auto theme and redesign the library to a cleaner, discreet look — logo + filter chips (Todas/Carpetas) + density icon, list-row (1-col) vs cover-grid (2/3-col) tiles with segmented gold progress, a polished + animated pinch, and tasteful animations.

**Architecture:** A real `ThemeData` light + dark behind a `themeMode` setting (auto default) on `MaterialApp`; library/chrome surfaces read `Theme.of(context)`/`ColorScheme`; the player stays dark (it uses hardcoded dark surfaces, theme-independent). The library home is redesigned (chips replace the fat tabs; tile adapts to density; pinch polished + animated reflow).

**Tech Stack:** Flutter (Material 3), Riverpod.

## Global Constraints

- Brand constants in BOTH themes: blue (`KivoColors.blue`, active/selected) + gold (`KivoColors.gold`, progress/accents). Soft palettes: dark scaffold ~`#0F1218`, surfaces `#181C24`/`#1E222B` (NOT pure black); light scaffold `#F4F4F2`, surfaces `#FFFFFF`.
- `themeMode` setting: `'auto' | 'light' | 'dark'`, default `'auto'`.
- The **player stays dark always** — do NOT re-theme `PlayerScreen`/overlays (they use hardcoded dark surfaces; just don't break them under light).
- Density `libraryColumns` 1↔2↔3 (existing setting), persisted; pinch must be one-handed-tolerant + animate the reflow; a density icon is the alternative.
- Tiles show the segmented gold progress (lit=accent, unlit theme-dim) in BOTH the 1-col list-row and the 2/3-col cover layouts when the video has resume progress.
- Library surfaces read theme colors (no hardcoded dark hex). `flutter analyze` clean; `flutter test` green (currently 94). Pure/settings logic unit-tested; the look + pinch feel are device-verified.

---

### Task 1: Theme system (light/dark) + `themeMode` setting + app wiring

**Files:**
- Modify: `lib/core/theme/kivo_theme.dart`, `lib/core/settings/kivo_settings.dart`, `lib/app.dart`
- Test: `test/core/theme/theme_mode_test.dart` (or extend a settings test)

**Interfaces:**
- Produces: `KivoTheme.light()`, `KivoTheme.dark()` (`ThemeData`); `KivoSettings.themeMode` (String, default `'auto'`); `themeModeFor(String) -> ThemeMode` helper.

- [ ] **Step 1: `kivo_theme.dart`** — keep `KivoColors` (blue/gold/etc.) and add light + dark `ThemeData`:

```dart
import 'package:flutter/material.dart';

class KivoColors {
  static const blue = Color(0xFF2D6CFF);
  static const gold = Color(0xFFE8B84B);
  // soft surfaces
  static const darkBg = Color(0xFF0F1218);
  static const darkSurface = Color(0xFF181C24);
  static const lightBg = Color(0xFFF4F4F2);
  static const lightSurface = Color(0xFFFFFFFF);
}

class KivoTheme {
  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        bg: KivoColors.darkBg,
        surface: KivoColors.darkSurface,
        onBg: const Color(0xFFF1F2F4),
        onSurfaceVariant: const Color(0xFF9AA0A8),
      );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        bg: KivoColors.lightBg,
        surface: KivoColors.lightSurface,
        onBg: const Color(0xFF15171C),
        onSurfaceVariant: const Color(0xFF6B7280),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color onBg,
    required Color onSurfaceVariant,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: KivoColors.blue,
      brightness: brightness,
    ).copyWith(
      primary: KivoColors.blue,
      secondary: KivoColors.gold,
      surface: surface,
      onSurface: onBg,
      onSurfaceVariant: onSurfaceVariant,
    );
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onBg,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }
}

ThemeMode themeModeFor(String mode) => switch (mode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
```
(If the existing `kivo_theme.dart` already defines `KivoColors` with `ink`/`panel`, KEEP those that are still referenced elsewhere and ADD the new fields/methods — grep `KivoColors.` to see what's used; don't remove fields that other files import.)

- [ ] **Step 2: Add `themeMode` to `kivo_settings.dart`** — field `final String themeMode;` (doc: `'auto' | 'light' | 'dark'`), `required this.themeMode,`, `themeMode: 'auto',` in `defaults()`, `String? themeMode,` + `themeMode: themeMode ?? this.themeMode,` in `copyWith`, `'themeMode': themeMode,` in `toMap`, `themeMode: m['themeMode'] ?? d.themeMode,` in `fromMap`.

- [ ] **Step 3: Wire `app.dart`** — read the existing app widget (`grep -n "MaterialApp" lib/app.dart`); set:
```dart
final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
return MaterialApp(
  // ... keep title/debugBanner etc ...
  theme: KivoTheme.light(),
  darkTheme: KivoTheme.dark(),
  themeMode: themeModeFor(mode),
  home: const LibraryScreen(),
);
```
(The app widget must be a `ConsumerWidget`/have a `ref` to watch the setting; if it's currently a plain `StatelessWidget`, convert to `ConsumerWidget`.) The player stays dark via its own hardcoded surfaces — do not change it.

- [ ] **Step 4: Test** — `test/core/theme/theme_mode_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';

void main() {
  test('themeMode defaults to auto and round-trips', () {
    expect(KivoSettings.defaults().themeMode, 'auto');
    final m = KivoSettings.defaults().copyWith(themeMode: 'dark').toMap();
    expect(KivoSettings.fromMap(m).themeMode, 'dark');
  });
  test('themeModeFor maps strings', () {
    expect(themeModeFor('light'), ThemeMode.light);
    expect(themeModeFor('dark'), ThemeMode.dark);
    expect(themeModeFor('auto'), ThemeMode.system);
  });
  test('themes expose brand colors', () {
    expect(KivoTheme.light().colorScheme.primary, KivoColors.blue);
    expect(KivoTheme.dark().colorScheme.secondary, KivoColors.gold);
  });
}
```

- [ ] **Step 5: Analyze + test + commit** — `feat: light/dark/auto theme system + themeMode setting`.

---

### Task 2: `VideoTile` two modes (list-row / cover) + segmented progress, theme-aware

**Files:**
- Modify: `lib/ui/home/widgets/video_tile.dart`
- Test: `test/ui/home/video_tile_test.dart` (extend)

**Interfaces:**
- Consumes: `Theme.of(context)`/`ColorScheme`, `ThumbnailImage`, `PressBounce`, `fmtDuration`, `settingsProvider.accentColor`, `VideoItem`.
- Produces: `VideoTile({VideoItem video, double? progress, required bool listRow, VoidCallback onTap, String? sizeLabel})` — `listRow` true = 1-col row layout; false = cover-grid tile.

- [ ] **Step 1: Refactor `VideoTile`** to two layouts driven by a `listRow` bool (replaces the old `compact`):
  - **listRow (1-col):** a `Row`: left = a `SizedBox(width: 132)` with a 16:9 `ClipRRect` containing `Hero` → `ThumbnailImage` + duration badge (bottom-right) + the `_SegmentedProgress` overlaid at the bottom when `progress != null`; right = `Expanded(Column)` with the title (`Theme onSurface`, 2 lines, ellipsis) + a size/meta line (`onSurfaceVariant`). Whole row wrapped in `PressBounce` + `GestureDetector(onTap)`. Use `Theme.of(context).colorScheme` for text colors (NOT hardcoded white).
  - **cover (2/3-col):** the existing cover tile (16:9 Hero thumbnail + gradient title + duration badge + `_SegmentedProgress`), but text/badge colors theme-aware where on-thumbnail text stays white (on the dark gradient) and any chrome uses the scheme.
  - `_SegmentedProgress` stays (lit = accent from `settingsProvider.accentColor`; unlit = `Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.18)`), rendered in BOTH layouts when `progress != null`.
- The `sizeLabel` (e.g. "49 MB") shows in the list-row meta; compute it where the tile is built (from `VideoItem.sizeBytes`) — add a small `fmtSize(int bytes)` helper in `core/format.dart` (e.g. `'${(bytes/1048576).toStringAsFixed(bytes >= 1048576*100 ? 0 : 2)} MB'`) and unit-test it.

- [ ] **Step 2: `fmtSize` in `core/format.dart`** + test:
```dart
String fmtSize(int bytes) {
  final mb = bytes / 1048576;
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
  return '${mb.toStringAsFixed(mb >= 100 ? 0 : 2)} MB';
}
```
Test: `expect(fmtSize(49 * 1048576), '49.00 MB');` etc. (pick exact expectations from the formula).

- [ ] **Step 3: Update `video_tile_test.dart`** — the existing test used `compact`; update to `listRow: true`/`false`. Assert: list-row shows title + size + duration + fires onTap; cover shows title + duration. Wrap in `MaterialApp(theme: KivoTheme.light())` so `Theme.of` resolves.

- [ ] **Step 4: Analyze + test + commit** — `feat: VideoTile list-row + cover modes, theme-aware, segmented progress in both; fmtSize`.

---

### Task 3: LibraryScreen redesign — logo + chips + density icon + re-theme + animations

**Files:**
- Modify: `lib/ui/home/library_screen.dart`, `lib/ui/home/widgets/continue_row.dart`, `lib/ui/home/widgets/folder_grid.dart`, `lib/ui/home/folder_screen.dart`
- Test: `test/ui/home/library_screen_test.dart` (extend)

**Interfaces:**
- Consumes: `VideoTile(listRow:)` (Task 2), theme, `groupByDay`, `continueWatchingProvider`, `groupByFolder`/`folderQueueFor`, `mediaIndexProvider`, `settings.libraryColumns`, `currentVideoProvider.openInFolder`.

- [ ] **Step 1: Top bar redesign.** Replace the `AppBar` `_DiscreetTabs` with: a `title` = `Row` of the **Kivo wordmark** (`Text('Kivo', style: titleLarge bold)`) and a trailing **density icon** `IconButton` in `actions` (cycles `libraryColumns` 1→2→3 with haptic + persist). The file-picker action stays. Remove the old segmented `_DiscreetTabs`. (Recientes/buscar icons are deferred to 2c — do NOT add dead buttons.)
- [ ] **Step 2: Filter chips row** under the app bar (a `SliverToBoxAdapter` or a fixed row above the feed): two discreet chips **`Todas`** | **`Carpetas`** — a small `_FilterChips(selected, onChanged)` (selected = blue fill + onPrimary text; unselected = `surfaceContainerHighest`/grey). State `_tab` (0 Todas / 1 Carpetas) drives the body, with a cross-fade (`AnimatedSwitcher`) between the Videos feed and the Folders grid.
- [ ] **Step 3: Theme the surfaces.** In `library_screen.dart`, `continue_row.dart`, `folder_grid.dart`, `folder_screen.dart`, replace hardcoded dark colors (`Colors.white`, `Colors.white70`, `#1C2230`, etc.) with `Theme.of(context).colorScheme` roles (`onSurface`, `onSurfaceVariant`, `surface`, `surfaceContainerHighest`). The "Continuar" label uses `onSurface` bold; section date headers use `onSurfaceVariant`. Folder capsule cards use `surfaceContainerHighest` + the gold "N vids" pill.
- [ ] **Step 4: Use the list-row tile at 1 column.** In the Videos feed's per-section sliver: when `libraryColumns == 1`, render a `SliverList` of `VideoTile(listRow: true, ...)`; when `> 1`, render the `SliverGrid` of `VideoTile(listRow: false, compact-cover)` at `libraryColumns` columns. Pass `progress` from `continueWatchingProvider` (by name) and `sizeLabel: fmtSize(v.sizeBytes)` to the list-row.
- [ ] **Step 5: Section/transition animations.** Wrap each date-section's content so it fades/slides in subtly on first build (a lightweight `TweenAnimationBuilder` opacity+offset, ~200ms, no jank); the chip switch uses `AnimatedSwitcher`. (The grid-density reflow animation is Task 4.) Keep `PressBounce` on tiles/cards.
- [ ] **Step 6: Update `library_screen_test.dart`** — wrap in `MaterialApp(theme: KivoTheme.light())`; assert the Kivo wordmark shows, a known video appears in the Todas feed, tapping the `Carpetas` chip shows a folder name. Keep the existing override setup.
- [ ] **Step 7: Analyze + test + commit** — `feat: library redesign — logo + filter chips + density icon + themed surfaces + section animations`.

---

### Task 4: Polished pinch + animated grid reflow

**Files:**
- Modify: `lib/ui/home/library_screen.dart`
- Test: device-verified (gesture/animation); keep `flutter test` green.

**Interfaces:** Consumes `settings.libraryColumns`.

- [ ] **Step 1: Polished pinch.** Replace the current `onScaleUpdate` with a one-handed-tolerant recogniser: track the cumulative `details.scale`; when it crosses `> 1.18` decrease columns (bigger tiles), `< 0.85` increase columns, then RESET the baseline (so each "notch" needs a fresh pinch, and a partial one-finger-anchored pinch still registers). Haptic on each change. Don't require a perfectly horizontal gesture — `onScaleUpdate` already responds to any two-pointer scale; just lower the threshold and reset per step so it's easy one-handed. Persist `libraryColumns`.
- [ ] **Step 2: Animated reflow.** Wrap the feed body in an `AnimatedSwitcher` (duration ~280ms, `Curves.easeOutCubic`, a `FadeThrough`-style fade+scale transitionBuilder) keyed by `libraryColumns`, so changing density cross-fades/scales between the 1/2/3-col layouts instead of snapping. (Keep scroll position reasonable — the switcher swaps the whole feed; acceptable for a density change.)
- [ ] **Step 3: Density icon** (from Task 3) shares the same `libraryColumns` setter so both the icon and the pinch animate identically.
- [ ] **Step 4: Analyze + test + commit** — `feat: polished one-handed pinch + animated grid reflow`.

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review (opus).
3. Release build to the Pixel 6: toggle light/dark/auto (player stays dark); the redesigned library (logo, discreet chips, density icon); 1-col clean list rows ↔ 2/3-col gallery with smooth animated reflow; pinch is easy one-handed; segmented progress on in-progress tiles; "Continuar" polished; section/press animations feel good in both themes.

(Next: C — mini-player; then 2c — search/sort/filters that activate the deferred recientes/buscar icons.)
