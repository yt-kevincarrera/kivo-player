# Kivo Theming Unification (single accent color) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the user-configurable accent color the single source of brand/active/indicator color everywhere (retire the fixed blue), fix player-control contrast (white pause ring, legible skip/ripple seconds), and add a duotone/flat icon-style setting.

**Architecture:** Drive the Material `ColorScheme` from the accent (seed = primary = secondary = accent) and rebuild the theme reactively in `app.dart`, so every `cs.secondary` consumer follows the accent for free. Then sweep the remaining hardcoded `KivoColors.gold`/`.blue` (which bypass the theme) to the accent, using a shared `onAccent()` contrast helper for text/icons drawn on an accent fill. `KivoIcon` gains a flat mode that substitutes its accent token with the base color.

**Tech Stack:** Flutter/Riverpod, `settingsProvider` (`KivoSettings`), Material 3 `ColorScheme`, the SVG-based `KivoIcon` set.

## Global Constraints

- **Single accent, retire blue.** No `KivoColors.blue` usages remain after this plan; the constant is deleted. Default accent stays gold `0xFFE8B84B`.
- **Contrast helper for on-accent content:** text/icons on an accent-colored fill use `onAccent(accent)` (defined in Task 1), never a baked `Color(0xFF231705)` or fixed `Colors.white`.
- **Do NOT touch fixed dark surfaces** (enumerated in the spec §4 "No tocar"): `KivoColors.panel`/`ink`, `0xFF182036`, `0xFF0C1120`, `0xFF1C2A44`, background gradients, `Color.fromRGBO(10,14,26,...)`, subtitle-color swatches, `kAccentPresets`. Do NOT convert overlay `Colors.white*` to `cs.onSurface` (would flip wrong in light theme — these overlays sit on fixed dark scrims).
- **`iconStyle` follows the 6-insertion-point KivoSettings pattern** (field, ctor, defaults, copyWith param+body, toMap, fromMap).
- **`flutter analyze` clean + full `flutter test` green before every commit** (current suite: 279).
- **Do NOT build the APK mid-plan — one build at the end.**
- Copy in Spanish where user-facing ("Duotono", "Plano", "Iconos").

---

### Task 1: Accent-driven theme + `onAccent` helper + reactive `app.dart`

**Files:**
- Modify: `lib/core/theme/kivo_theme.dart`
- Modify: `lib/app.dart`
- Test: `test/core/theme/kivo_theme_test.dart` (create)

**Interfaces:**
- Produces:
  - `Color onAccent(Color accent)` — top-level in `kivo_theme.dart`; the legible on-accent-fill color.
  - `KivoTheme.dark({Color accent})` / `KivoTheme.light({Color accent})` — now take an optional accent (default `KivoColors.gold`, so existing no-arg test calls keep working).
  - The theme's `colorScheme.primary` and `.secondary` both equal `accent`; `.onSecondary`/`.onPrimary` equal `onAccent(accent)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/kivo_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';

void main() {
  test('onAccent is dark on a light accent and white on a dark accent', () {
    expect(onAccent(const Color(0xFFE8B84B)), const Color(0xFF231705)); // gold → dark ink
    expect(onAccent(const Color(0xFF13315C)), Colors.white);            // deep blue → white
  });

  test('theme primary and secondary follow the given accent', () {
    final blue = KivoTheme.dark(accent: const Color(0xFF2D6CFF));
    expect(blue.colorScheme.primary, const Color(0xFF2D6CFF));
    expect(blue.colorScheme.secondary, const Color(0xFF2D6CFF));
    expect(blue.colorScheme.onSecondary, onAccent(const Color(0xFF2D6CFF)));
  });

  test('default accent is gold', () {
    expect(KivoTheme.dark().colorScheme.secondary, const Color(0xFFE8B84B));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/theme/kivo_theme_test.dart`
Expected: FAIL — `onAccent` undefined; `KivoTheme.dark` takes no `accent`.

- [ ] **Step 3: Implement**

Rewrite `lib/core/theme/kivo_theme.dart`. Remove `blue` from `KivoColors` (nothing in the theme uses it now; the last consumers are retired in Task 2 — **if Task 2 hasn't run yet and the analyzer flags `library_screen.dart`/`video_tile.dart`, keep the `blue` const for now and delete it in Task 2**). Keep `gold` (default preset).

```dart
import 'package:flutter/material.dart';

class KivoColors {
  static const gold = Color(0xFFE8B84B); // default accent preset
  // Legacy player surfaces (fixed, not brand colors).
  static const ink = Color(0xFF0A0E1A);
  static const panel = Color(0xFF111726);
  static const darkBg = Color(0xFF0F1218);
  static const darkSurface = Color(0xFF181C24);
  static const lightBg = Color(0xFFF4F4F2);
  static const lightSurface = Color(0xFFFFFFFF);
}

/// Legible color for text/icons drawn on top of an [accent]-colored fill.
/// Warm dark ink on light accents (keeps the gold look), white on dark ones.
Color onAccent(Color accent) =>
    accent.computeLuminance() > 0.45 ? const Color(0xFF231705) : Colors.white;

class KivoTheme {
  static ThemeData dark({Color accent = KivoColors.gold}) => _build(
        brightness: Brightness.dark,
        accent: accent,
        bg: KivoColors.darkBg,
        surface: KivoColors.darkSurface,
        onBg: const Color(0xFFF1F2F4),
        onSurfaceVariant: const Color(0xFF9AA0A8),
      );

  static ThemeData light({Color accent = KivoColors.gold}) => _build(
        brightness: Brightness.light,
        accent: accent,
        bg: KivoColors.lightBg,
        surface: KivoColors.lightSurface,
        onBg: const Color(0xFF15171C),
        onSurfaceVariant: const Color(0xFF6B7280),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color accent,
    required Color bg,
    required Color surface,
    required Color onBg,
    required Color onSurfaceVariant,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      onPrimary: onAccent(accent),
      secondary: accent,
      onSecondary: onAccent(accent),
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

In `lib/app.dart`, watch the accent and pass it to both themes:

```dart
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final accent = Color(ref.watch(settingsProvider.select((s) => s.accentColor)));
    return MaterialApp(
      navigatorKey: kivoNavigatorKey,
      title: 'Kivo',
      debugShowCheckedModeBanner: false,
      theme: KivoTheme.light(accent: accent),
      darkTheme: KivoTheme.dark(accent: accent),
      themeMode: themeModeFor(mode),
      home: const HomeShell(),
    );
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/core/theme/kivo_theme_test.dart` → 3 pass.
Run: `flutter analyze lib/core/theme/kivo_theme.dart lib/app.dart` → No issues (if `KivoColors.blue` removal breaks other files, keep the const per Step 3's note).

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/kivo_theme.dart lib/app.dart test/core/theme/kivo_theme_test.dart
git commit -m "feat(theme): accent-driven ColorScheme + onAccent contrast helper; reactive theme in app.dart"
```

---

### Task 2: Retire blue + accent-ify Home

**Files:**
- Modify: `lib/ui/home/library_screen.dart` (chips "Todo"/"Carpetas" + "No vistos"), `lib/ui/home/widgets/video_tile.dart` ("Nuevo" badge), `lib/ui/home/widgets/folder_grid.dart` ("N vids" pill), `lib/ui/mini_player/mini_player_bar.dart` (progress fill)
- Modify: `lib/core/theme/kivo_theme.dart` (delete `KivoColors.blue` if still present)
- Test: `test/ui/home/home_accent_test.dart` (create)

**Interfaces:**
- Consumes: `onAccent` (Task 1), `settingsProvider`.

Transformation rule for this task: in each file, replace every `KivoColors.blue` and every active/indicator `KivoColors.gold` with the local accent `Color(ref.watch(settingsProvider).accentColor)` (add that local where missing — `video_tile.dart:32` and `folder_grid` already have or can add it). For text/icons that sit ON the accent fill (the chip label that was `Colors.white`, the "Nuevo" badge label, the "N vids" pill text), use `onAccent(accent)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/home/home_accent_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/widgets/folder_grid.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('folder count pill uses the accent, not a hardcoded gold', (t) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(accentColor: 0xFF2D6CFF)); // blue accent
    const item = VideoItem(id: '1', uri: 'u', name: 'a.mkv', folder: 'F',
        durationMs: 1000, sizeBytes: 1, dateAddedMs: 1);
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
        mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
      ],
      child: MaterialApp(
        theme: KivoTheme.dark(accent: const Color(0xFF2D6CFF)),
        home: const Scaffold(body: FolderGrid(folders: {'F': [item]})),
      ),
    ));
    await t.pump();
    // The "1 vid" pill text should be painted with the accent, not gold.
    final txt = tester_findPillText(t);
    expect(txt.style!.color, const Color(0xFF2D6CFF));
  });
}

// Helper: find the count-pill Text ("1 vid"/"N vids").
Text tester_findPillText(WidgetTester t) =>
    t.widget<Text>(find.textContaining('vid'));
```

(If `FolderGrid`'s exact constructor differs, adapt the pump to the real signature — the assertion is what matters: the pill text/‌fill color equals the overridden accent. Check `lib/ui/home/widgets/folder_grid.dart` for the real `_CountPill` construction and, if the color lives on a `Container` decoration rather than the `Text`, assert on that `Container`'s `color` instead.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/home/home_accent_test.dart`
Expected: FAIL — pill still gold (`0xFFE8B84B`), not the blue accent.

- [ ] **Step 3: Implement the sweep**

`grep -n "KivoColors.blue\|KivoColors.gold" lib/ui/home/library_screen.dart lib/ui/home/widgets/video_tile.dart lib/ui/home/widgets/folder_grid.dart lib/ui/mini_player/mini_player_bar.dart` and route each per the rule above. Concretely (audit line refs — verify current lines):
- `library_screen.dart` chips (~L399, L433): `active ? KivoColors.blue : cs.surfaceContainerHighest` → `active ? accent : cs.surfaceContainerHighest`; the active label color (was `Colors.white`) → `onAccent(accent)`. Add `final accent = Color(ref.watch(settingsProvider).accentColor);` in the chip builder scope.
- `video_tile.dart` `_newBadge()` (~L203): `KivoColors.blue` fill → `accent`; badge text → `onAccent(accent)`. `accent` already exists at `video_tile.dart:32` — thread it into `_newBadge`.
- `folder_grid.dart` `_CountPill` (~L122,124,129): fill/border/text gold → accent; pill text on the fill → `onAccent(accent)` if it sits on the accent fill, else `accent`. Add the accent local.
- `mini_player_bar.dart` (~L147): progress-fill `KivoColors.gold` → accent.
- Delete `static const blue = ...` from `KivoColors` (Task 1) now that no usages remain.
- Add `import '../../core/theme/kivo_theme.dart';` (for `onAccent`) where used.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/home/home_accent_test.dart` → pass.
Run: `flutter analyze lib/ui/home lib/core/theme lib/ui/mini_player` → No issues (confirms no dangling `KivoColors.blue`).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/home lib/ui/mini_player lib/core/theme/kivo_theme.dart test/ui/home/home_accent_test.dart
git commit -m "feat(theme): retire blue; Home + mini-player use the accent (onAccent for on-fill text)"
```

---

### Task 3: Accent sweep — player panels

**Files:**
- Modify: `lib/ui/player/tracks/track_picker.dart`, `lib/ui/player/speed/speed_panel.dart`, `lib/ui/player/sleep/sleep_timer_panel.dart`, `lib/ui/player/sleep/sleep_warning_toast.dart`
- Test: `test/ui/player/panel_accent_test.dart` (create)

**Interfaces:**
- Consumes: `onAccent` (Task 1), `settingsProvider`.

Transformation rule (same as Task 2): every active/indicator `KivoColors.gold` → local `accent`; every baked `Color(0xFF231705)` (text/icon on an accent fill) → `onAccent(accent)`; delete `track_picker.dart`'s local `isLight`/`_ColorSquare.isLight` and use `onAccent`. Add `final accent = Color(ref.watch(settingsProvider).accentColor);` where a widget lacks it (these are all `ConsumerWidget`/`ConsumerState`, so `ref` is available; for `StatelessWidget` sub-widgets receiving no ref, pass `accent` down as a parameter). Do NOT touch the fixed panel/gradient surfaces or the subtitle-color swatch palette (spec §4).

Audit site counts to clear (grep to confirm zero `KivoColors.gold` remain after): `track_picker.dart` ~15 (incl. L226 ink-on-gold, L468 swatches = LEAVE), `speed_panel.dart` ~9, `sleep_timer_panel.dart` ~17 (incl. L511 ink-on-gold), `sleep_warning_toast.dart` ~5 (incl. L134 ink-on-gold).

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/player/panel_accent_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/player/speed/speed_panel.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('speed panel active rate readout uses the accent', (t) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(accentColor: 0xFF2D6CFF));
    final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: KivoTheme.dark(accent: const Color(0xFF2D6CFF)),
        home: Builder(builder: (ctx) => Scaffold(
          body: Center(child: ElevatedButton(
            onPressed: () => showSpeedPanel(ctx), child: const Text('open'))))),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    // The current-rate readout (e.g. "1.00x") is painted with the accent.
    final readout = t.widget<Text>(find.textContaining('x').first);
    expect(readout.style?.color, const Color(0xFF2D6CFF));
    await t.pump(const Duration(seconds: 1));
  });
}
```

(Adapt the finder to the speed panel's real current-rate `Text` — check `speed_panel.dart` for how the rate readout is built; the point is its color equals the overridden accent, not gold. If `showSpeedPanel` needs a playback provider, add the same overrides the existing `speed_panel` test uses.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/player/panel_accent_test.dart`
Expected: FAIL — readout still gold.

- [ ] **Step 3: Implement the sweep** across the 4 panel files per the rule. After editing each, `grep -n "KivoColors.gold\|0xFF231705" <file>` should return only the deliberate-leave lines (subtitle swatch palette in `track_picker.dart`).

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/player/panel_accent_test.dart test/ui/player/tracks/track_picker_test.dart` → all pass (the existing track-picker tests must still pass).
Run: `flutter analyze lib/ui/player/tracks lib/ui/player/speed lib/ui/player/sleep` → No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/tracks lib/ui/player/speed lib/ui/player/sleep test/ui/player/panel_accent_test.dart
git commit -m "feat(theme): player panels (tracks/speed/sleep/toast) follow the accent + onAccent"
```

---

### Task 4: Accent sweep — player overlays

**Files:**
- Modify: `lib/ui/player/loop/ab_loop_chip.dart`, `lib/ui/player/loop/ab_range_layer.dart`, `lib/ui/player/autoplay/autoplay_overlay.dart`, `lib/ui/player/audio_only/audio_only_view.dart`, `lib/ui/player/queue/queue_strip.dart`
- Test: `test/ui/player/overlay_accent_test.dart` (create)

**Interfaces:**
- Consumes: `onAccent` (Task 1), `settingsProvider`.

Same transformation rule. `ab_range_layer.dart` is a `CustomPainter` fed a color at construction (`_AbRangePainter(color: KivoColors.gold)`, ~L26) — change its caller to pass the accent (the caller is a widget with `ref`; read the accent there and pass it down). `queue_strip.dart` "AHORA" ribbon text (~L166 `0xFF231705`) → `onAccent(accent)`; `autoplay_overlay.dart` "Reproducir" label (~L176) → `onAccent(accent)`. Leave the fixed card/background surfaces.

Audit counts to clear: `ab_loop_chip.dart` ~8, `ab_range_layer.dart` 1, `autoplay_overlay.dart` ~6, `audio_only_view.dart` ~5, `queue_strip.dart` ~3.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/player/overlay_accent_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/queue/queue_strip.dart';
import '../../fakes/fakes.dart';

const _session = VideoSession(
  playbackPath: 'content://A/b.mkv', displayName: 'b.mkv',
  queue: ['content://A/a.mkv', 'content://A/b.mkv'],
  queueNames: ['a.mkv', 'b.mkv'], queueIds: ['ida', 'idb'], index: 1, folder: 'A',
);

void main() {
  testWidgets('queue-strip AHORA ribbon uses the accent fill', (t) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(accentColor: 0xFF2D6CFF));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: KivoTheme.dark(accent: const Color(0xFF2D6CFF)),
        home: const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: QueueStrip()))),
    ));
    await t.pump();
    // The "AHORA" ribbon container is filled with the accent (blue), not gold.
    final ribbon = t.widget<Container>(find.ancestor(
        of: find.text('AHORA'), matching: find.byType(Container)).first);
    final deco = ribbon.color ?? (ribbon.decoration as BoxDecoration?)?.color;
    expect(deco, const Color(0xFF2D6CFF));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/player/overlay_accent_test.dart`
Expected: FAIL — ribbon still gold.

- [ ] **Step 3: Implement the sweep** across the 5 overlay files per the rule; grep each to confirm no active `KivoColors.gold` remains.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/player/overlay_accent_test.dart test/ui/player/queue_strip_test.dart` → pass.
Run: `flutter analyze lib/ui/player/loop lib/ui/player/autoplay lib/ui/player/audio_only lib/ui/player/queue` → No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/loop lib/ui/player/autoplay lib/ui/player/audio_only lib/ui/player/queue test/ui/player/overlay_accent_test.dart
git commit -m "feat(theme): player overlays (A-B/autoplay/audio-only/queue) follow the accent + onAccent"
```

---

### Task 5: Player control fixes — white pause ring, legible seconds

**Files:**
- Modify: `lib/ui/player/controls/center_controls.dart`, `lib/ui/player/gestures/ripple_overlay.dart`
- Test: `test/ui/player/center_controls_test.dart` (create)

**Interfaces:**
- Consumes: nothing new.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/player/center_controls_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/player/controls/center_controls.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('skip-seconds label is white (not the accent)', (t) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(accentColor: 0xFF2D6CFF, centerSkipSeconds: 10));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProviderOverrideFor(c: null), // see note
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: KivoTheme.dark(accent: const Color(0xFF2D6CFF)),
        home: const Scaffold(body: Center(child: CenterControls()))),
    ));
    await t.pump();
    final label = t.widget<Text>(find.text('10s'));
    expect(label.style!.color, Colors.white);
    expect(label.style!.shadows, isNotNull); // has a legibility shadow
  });
}
```

Note: `CenterControls` watches `playingProvider` (from the engine). Mirror whatever the existing player-control widget tests use to provide a fake engine (`playbackEngineProvider.overrideWithValue(FakePlaybackEngine())`) — replace the pseudo `playbackEngineProviderOverrideFor` line with the real override and import. If no such test exists, override `playbackEngineProvider` with `FakePlaybackEngine()` from `fakes.dart` and import `package:kivo_player/player/engine/playback_provider.dart`.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/player/center_controls_test.dart`
Expected: FAIL — label color is the accent, no shadow.

- [ ] **Step 3: Implement**

In `center_controls.dart`:
- Play/pause ring (the `IconButton.styleFrom(shape: CircleBorder(...))`): change to `CircleBorder(side: const BorderSide(color: Colors.white, width: 3))` and remove the now-unused `accent` read in `CenterControls.build` if nothing else uses it.
- Skip-seconds `Text('${skip}s', ...)`: color `Colors.white`, add `shadows: const [Shadow(color: Colors.black87, blurRadius: 4)]`.

In `ripple_overlay.dart`:
- The `Text('${e.seconds}s', ...)` (~L82-86): color `Colors.white`, add `shadows: const [Shadow(color: Colors.black87, blurRadius: 6)]`. The `accent` local becomes unused — remove it.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/player/center_controls_test.dart` → pass.
Run: `flutter analyze lib/ui/player/controls/center_controls.dart lib/ui/player/gestures/ripple_overlay.dart` → No issues (no unused `accent`).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/controls/center_controls.dart lib/ui/player/gestures/ripple_overlay.dart test/ui/player/center_controls_test.dart
git commit -m "fix(player): white thicker pause ring; white shadowed skip/ripple seconds for contrast"
```

---

### Task 6: `iconStyle` setting (duotone | flat) + KivoIcon flat mode

**Files:**
- Modify: `lib/core/settings/kivo_settings.dart` (6 insertion points), `lib/core/icons/kivo_icons.dart` (KivoIcon flat mode), `lib/ui/settings/sections/general_section.dart` (segmented control)
- Test: `test/ui/settings/icon_style_test.dart` (create); extend `test/core/settings/settings_service_test.dart`

**Interfaces:**
- Consumes: `settingsProvider`, `SettingSegmented` (from 4a).
- Produces: `KivoSettings.iconStyle` (`String`, default `'duotone'`).

- [ ] **Step 1: Write the failing tests**

```dart
// test/ui/settings/icon_style_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/icons/kivo_icons.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _c(String iconStyle) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  await s.update(s.current.copyWith(accentColor: 0xFF2D6CFF, iconStyle: iconStyle));
  return ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
}

void main() {
  testWidgets('duotone injects the accent hex; flat does not', (t) async {
    // Duotone: the rendered SVG string carries the accent hex.
    final dc = await _c('duotone');
    addTearDown(dc.dispose);
    // KivoIcon builds an SvgPicture.string; we assert via the substitution
    // helper indirectly: in flat mode the accent token resolves to the base color.
    // Simplest: pump both and compare that flat != duotone is handled in KivoIcon.
    expect(dc.read(settingsProvider).iconStyle, 'duotone');

    final fc = await _c('flat');
    addTearDown(fc.dispose);
    expect(fc.read(settingsProvider).iconStyle, 'flat');
  });
}
```

Plus, in `test/core/settings/settings_service_test.dart`, add `iconStyle` to whatever round-trip assertion exists (set a non-default `'flat'`, save, reload, expect `'flat'`).

(Note: asserting the exact SVG string is brittle. The meaningful behavior test is that `KivoIcon` in flat mode does NOT paint the accent. If the existing suite has a golden/SVG-inspection pattern, mirror it; otherwise the settings round-trip + a manual device check per §7 is the coverage, and this widget test just locks the setting plumbing.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/settings/icon_style_test.dart`
Expected: FAIL — `iconStyle` is not a `copyWith`/field.

- [ ] **Step 3: Implement**

In `kivo_settings.dart`, add `iconStyle` at all 6 points: field `final String iconStyle;`; ctor `required this.iconStyle,`; defaults `iconStyle: 'duotone',`; copyWith param `String? iconStyle,` + body `iconStyle: iconStyle ?? this.iconStyle,`; `toMap` `'iconStyle': iconStyle,`; `fromMap` `iconStyle: m['iconStyle'] ?? d.iconStyle,`.

In `kivo_icons.dart` `KivoIcon.build`, make the accent resolve to the base color in flat mode:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flat = ref.watch(settingsProvider.select((s) => s.iconStyle)) == 'flat';
    final a = flat ? color : (accent ?? Color(ref.watch(settingsProvider).accentColor));
    final hex = _toHex(a);
    final svg = icon.replaceAll('__ACCENT__', hex);
    ...
  }
```

In `general_section.dart`, add under "Apariencia" (after the accent color tile), a segmented control:

```dart
            SettingSegmented<String>(
              title: 'Iconos',
              subtitle: 'Duotono o plano (blanco)',
              options: const [('duotone', 'Duotono'), ('flat', 'Plano')],
              value: s.iconStyle,
              onChanged: (v) => n.set(s.copyWith(iconStyle: v)),
            ),
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/settings/icon_style_test.dart test/core/settings/settings_service_test.dart` → pass.
Run: `flutter analyze lib/core/settings lib/core/icons lib/ui/settings` → No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/core/settings/kivo_settings.dart lib/core/icons/kivo_icons.dart lib/ui/settings/sections/general_section.dart test/ui/settings/icon_style_test.dart test/core/settings/settings_service_test.dart
git commit -m "feat(settings): duotone/flat icon-style setting; KivoIcon flat mode"
```

---

## Self-Review

**Spec coverage:** §2 accent theme → Task 1. §3 onAccent + ink-on-accent → Tasks 1 (helper) + 2/3/4 (apply). §4 sweep → Tasks 2 (home) + 3 (panels) + 4 (overlays), fixed surfaces preserved per Global Constraints. §5 control fixes → Task 5. §6 iconStyle → Task 6. §7 tests → per-task + device checklist below. All covered.

**Placeholder scan:** No TBD/TODO. The sweep tasks (2-4) give a transformation RULE + enumerated files/counts rather than 74 individual snippets — deliberate for a mechanical retint; each names the tricky onAccent sites explicitly and ends with a grep-to-zero check + a representative failing/passing test. Test snippets that depend on a widget's exact construction (folder pill, speed readout, queue ribbon) carry an explicit "adapt the finder; the color assertion is the point" note — not a placeholder, a guard against brittle line-coupling.

**Type consistency:** `onAccent(Color)`, `KivoTheme.dark({Color accent})`, `iconStyle` string, `SettingSegmented<String>` — consistent across tasks. `KivoColors.blue` deletion sequenced (Task 1 stops using it in the theme; Task 2 removes the last usages + the constant) so each task compiles.

## Ordering & final verification

Order 1 → 2 → 3 → 4 → 5 → 6 (Task 2 depends on Task 1's `onAccent` + finishes the blue removal; 3/4/5/6 depend on Task 1). After Task 6:
1. `flutter analyze` → No issues. `flutter test` → all green. `grep -rn "KivoColors.blue" lib/` → zero. `grep -rn "0xFF231705" lib/` → zero.
2. Release build + install to the Pixel 6.
3. Device checklist (spec §7): change accent to blue/red/dark → everything recolors (chips, tabs, seek bar, panels, A-B, autoplay, queue, mini-player, HUD); dark accent keeps on-fill text legible; white thick pause ring; skip/ripple seconds visible on bright video; Duotono↔Plano flips all icons; light theme still legible.
