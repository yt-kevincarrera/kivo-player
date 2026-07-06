# Kivo Hito 4d — Advanced-playback settings section — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the "Reproducción avanzada" settings section (the last of Hito 4): wire resume/autoplay/subtitle-default/preferred-language settings, add a new configurable `pipAutoOnHome`, and let preferred languages reset to "Automático".

**Architecture:** Task 1 changes the `KivoSettings` model (new `pipAutoOnHome` field; make the two nullable preferred-language fields resettable-to-null in `copyWith` via a sentinel) and gates the new field in `player_screen._armPip`. Task 2 builds `AdvancedPlaybackSection` (mirrors the other sections) using the toolkit + `SettingChoice`, reached from a new `SettingNavRow`.

**Tech Stack:** Flutter/Riverpod, `settingsProvider` (`KivoSettings`), the toolkit (`SettingsCard`, `SettingSwitch`, `SettingStepper`, `SettingChoice`).

## Global Constraints

- **Immediate apply:** `ref.read(settingsProvider.notifier).set(s.copyWith(field: v))`, watching `settingsProvider`.
- **Theme-aware** via the toolkit.
- **Do NOT re-add `queueStripVisible`** — the strip stays always-on, no toggle.
- **Subtitle style is NOT in 4d** — it stays in the track picker.
- **Preferred languages in 4d only reset to Automático (null)** — setting a concrete language stays in the track picker.
- `pipAutoOnHome` default `true`, all 6 KivoSettings insertion points.
- Toolkit signatures (verbatim): `SettingSwitch({required String title, String? subtitle, required bool value, required ValueChanged<bool> onChanged})`, `SettingStepper({required String title, String? subtitle, required int value, required int min, required int max, int step = 1, required String Function(int) label, required ValueChanged<int> onChanged})`, `SettingChoice<T>({required String title, String? subtitle, required List<(T,String)> options, required T value, required ValueChanged<T> onChanged})`, `SettingsCard`, `SettingNavRow`.
- **`flutter analyze` clean + full `flutter test` green before every commit** (current suite: 311).
- **Do NOT build the APK mid-plan.** Spanish copy.

---

### Task 1: model — `pipAutoOnHome` + resettable languages + PiP gate

**Files:**
- Modify: `lib/core/settings/kivo_settings.dart` (add `pipAutoOnHome` at all 6 points; sentinel-clearable `preferredSubtitleLanguage`/`preferredAudioLanguage` in `copyWith`)
- Modify: `lib/ui/player/player_screen.dart` (`_armPip` gate)
- Test: `test/core/settings/kivo_settings_4d_test.dart` (create)

**Interfaces:**
- Produces: `KivoSettings.pipAutoOnHome` (`bool`, default `true`); `copyWith` where `preferredSubtitleLanguage`/`preferredAudioLanguage` can be set to a value, omitted (kept), OR set to `null` (cleared).

- [ ] **Step 1: Write the failing test**

```dart
// test/core/settings/kivo_settings_4d_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('pipAutoOnHome defaults true and round-trips through the map', () {
    final d = KivoSettings.defaults();
    expect(d.pipAutoOnHome, true);
    final off = d.copyWith(pipAutoOnHome: false);
    expect(off.pipAutoOnHome, false);
    expect(KivoSettings.fromMap(off.toMap()).pipAutoOnHome, false);
  });

  test('copyWith sets, keeps, and CLEARS preferred languages', () {
    final d = KivoSettings.defaults(); // languages null by default
    final en = d.copyWith(preferredSubtitleLanguage: 'en');
    expect(en.preferredSubtitleLanguage, 'en');
    // omitting the arg keeps the value
    expect(en.copyWith(pipAutoOnHome: false).preferredSubtitleLanguage, 'en');
    // passing null CLEARS it (the sentinel change)
    expect(en.copyWith(preferredSubtitleLanguage: null).preferredSubtitleLanguage, isNull);
    // audio language behaves the same
    final es = d.copyWith(preferredAudioLanguage: 'es');
    expect(es.preferredAudioLanguage, 'es');
    expect(es.copyWith(preferredAudioLanguage: null).preferredAudioLanguage, isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/settings/kivo_settings_4d_test.dart`
Expected: FAIL — `pipAutoOnHome` doesn't exist; and `copyWith(preferredSubtitleLanguage: null)` currently keeps the old value (so the clear assertion fails).

- [ ] **Step 3: Implement the model changes**

In `lib/core/settings/kivo_settings.dart`:

1. Add the field (near the other bools):
```dart
  final bool pipAutoOnHome;
```
2. Add to the constructor:
```dart
    required this.pipAutoOnHome,
```
3. Add to `KivoSettings.defaults()`:
```dart
        pipAutoOnHome: true,
```
4. Add a sentinel constant to the class (e.g. just before `copyWith`):
```dart
  static const Object _unset = Object();
```
5. In `copyWith`, add the `pipAutoOnHome` param, and CHANGE the two language params to sentinel-typed:
```dart
    bool? pipAutoOnHome,
    Object? preferredSubtitleLanguage = _unset,
    Object? preferredAudioLanguage = _unset,
```
   (Replace the existing `String? preferredSubtitleLanguage,` / `String? preferredAudioLanguage,` param lines.)
6. In the `copyWith` body (the `return KivoSettings(...)`), add / change:
```dart
      pipAutoOnHome: pipAutoOnHome ?? this.pipAutoOnHome,
      preferredSubtitleLanguage: identical(preferredSubtitleLanguage, _unset)
          ? this.preferredSubtitleLanguage
          : preferredSubtitleLanguage as String?,
      preferredAudioLanguage: identical(preferredAudioLanguage, _unset)
          ? this.preferredAudioLanguage
          : preferredAudioLanguage as String?,
```
   (Replace the existing `preferredSubtitleLanguage: preferredSubtitleLanguage ?? this.preferredSubtitleLanguage,` / audio lines.)
7. Add to `toMap()`:
```dart
        'pipAutoOnHome': pipAutoOnHome,
```
8. Add to `fromMap(...)`:
```dart
      pipAutoOnHome: m['pipAutoOnHome'] ?? d.pipAutoOnHome,
```

In `lib/ui/player/player_screen.dart`, gate `_armPip`:
```dart
  void _armPip() {
    // PiP-auto-on-Home is user-configurable: when off, keep PiP disarmed so
    // onUserLeaveHint (native) won't float the player when leaving to Home.
    if (!ref.read(settingsProvider).pipAutoOnHome) {
      _pip.disarm();
      return;
    }
    final playing = ref.read(playingProvider).value ?? false;
    _pip.arm(width: _pipSize.width, height: _pipSize.height, playing: playing);
  }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/core/settings/kivo_settings_4d_test.dart` → pass.
Run: `flutter analyze lib/core/settings/kivo_settings.dart lib/ui/player/player_screen.dart` → No issues. Then the full suite `flutter test` → green (the sentinel change must not break existing `copyWith` callers — the track picker passes a `String`, which still works).

- [ ] **Step 5: Commit**

```bash
git add lib/core/settings/kivo_settings.dart lib/ui/player/player_screen.dart test/core/settings/kivo_settings_4d_test.dart
git commit -m "feat(settings): pipAutoOnHome field + resettable preferred languages + PiP gate"
```

---

### Task 2: `AdvancedPlaybackSection` + nav row

**Files:**
- Create: `lib/ui/settings/sections/advanced_playback_section.dart`
- Modify: `lib/ui/settings/settings_screen.dart` (nav row before "Acerca de")
- Test: `test/ui/settings/advanced_playback_section_test.dart`, extend `test/ui/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `SettingsCard`, `SettingSwitch`, `SettingStepper`, `SettingChoice` (toolkit); `settingsProvider`; the resettable `copyWith` (Task 1).
- Produces: `AdvancedPlaybackSection` (`ConsumerWidget`).

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/settings/advanced_playback_section_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/sections/advanced_playback_section.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _pump(WidgetTester t, {String? subLang}) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  if (subLang != null) await s.update(s.current.copyWith(preferredSubtitleLanguage: subLang));
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: KivoTheme.dark(), home: const AdvancedPlaybackSection()),
  ));
  await t.pump();
  return c;
}

void main() {
  testWidgets('resume behavior choice persists', (t) async {
    final c = await _pump(t);
    await t.tap(find.text('Desactivado'));
    await t.pump();
    expect(c.read(settingsProvider).resumeBehavior, 'off');
  });

  testWidgets('toggling PiP-auto persists pipAutoOnHome', (t) async {
    final c = await _pump(t);
    final before = c.read(settingsProvider).pipAutoOnHome;
    final pipRow = find.ancestor(
      of: find.text('Miniatura flotante (PiP) al salir al inicio'),
      matching: find.byType(Row)).first;
    await t.tap(find.descendant(of: pipRow, matching: find.byType(Switch)));
    await t.pump();
    expect(c.read(settingsProvider).pipAutoOnHome, !before);
  });

  testWidgets('resetting subtitle language to Automático clears it', (t) async {
    final c = await _pump(t, subLang: 'en');
    expect(c.read(settingsProvider).preferredSubtitleLanguage, 'en');
    await t.tap(find.text('Automático').first);
    await t.pump();
    expect(c.read(settingsProvider).preferredSubtitleLanguage, isNull);
  });
}
```

(Note: the section is a lazy `ListView`; if a target is below the fold, `await t.drag(find.byType(Scrollable).first, const Offset(0, -400)); await t.pump();` before locating it. Keep the assertion — persistence — as the point.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/settings/advanced_playback_section_test.dart`
Expected: FAIL — `AdvancedPlaybackSection` doesn't exist.

- [ ] **Step 3: Implement the section**

```dart
// lib/ui/settings/sections/advanced_playback_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../widgets/setting_tiles.dart';
import '../widgets/setting_choice.dart';

class AdvancedPlaybackSection extends ConsumerWidget {
  const AdvancedPlaybackSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);

    List<(String?, String)> langOptions(String? current) => [
          (null, 'Automático'),
          if (current != null) (current, '$current (elegido)'),
        ];

    return Scaffold(
      appBar: AppBar(title: const Text('Reproducción avanzada')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _label(context, 'Continuar viendo'),
          SettingsCard(children: [
            SettingChoice<String>(
              title: 'Al reabrir un video', value: s.resumeBehavior,
              options: const [('auto', 'Automático'), ('ask', 'Preguntar'), ('off', 'Desactivado')],
              onChanged: (v) => n.set(s.copyWith(resumeBehavior: v))),
            SettingStepper(
              title: 'Mínimo para recordar posición', value: s.resumeMinSeconds,
              min: 0, max: 120, step: 5, label: (v) => '$v s',
              onChanged: (v) => n.set(s.copyWith(resumeMinSeconds: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Reproducción'),
          SettingsCard(children: [
            SettingSwitch(
              title: 'Reproducir el siguiente automáticamente', value: s.autoplayNext,
              onChanged: (v) => n.set(s.copyWith(autoplayNext: v))),
            SettingSwitch(
              title: 'Miniatura flotante (PiP) al salir al inicio', value: s.pipAutoOnHome,
              onChanged: (v) => n.set(s.copyWith(pipAutoOnHome: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Subtítulos y audio'),
          SettingsCard(children: [
            SettingSwitch(
              title: 'Activar subtítulos por defecto', value: s.subtitlesEnabledByDefault,
              onChanged: (v) => n.set(s.copyWith(subtitlesEnabledByDefault: v))),
            SettingChoice<String?>(
              title: 'Idioma de subtítulos preferido',
              subtitle: 'Se fija al elegir una pista; aquí puedes volver a Automático',
              value: s.preferredSubtitleLanguage, options: langOptions(s.preferredSubtitleLanguage),
              onChanged: (v) => n.set(s.copyWith(preferredSubtitleLanguage: v))),
            SettingChoice<String?>(
              title: 'Idioma de audio preferido',
              subtitle: 'Se fija al elegir una pista; aquí puedes volver a Automático',
              value: s.preferredAudioLanguage, options: langOptions(s.preferredAudioLanguage),
              onChanged: (v) => n.set(s.copyWith(preferredAudioLanguage: v))),
          ]),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 10.5, letterSpacing: 1.4, fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.secondary)),
      );
}
```

In `lib/ui/settings/settings_screen.dart`, add the import:
```dart
import 'sections/advanced_playback_section.dart';
```
Insert this `SettingNavRow` in the root `SettingsCard` BETWEEN the "Interfaz" row and the "Acerca de" row:
```dart
            SettingNavRow(
              icon: Icons.play_circle_outline,
              title: 'Reproducción avanzada',
              subtitle: 'Continuar, autoplay, subtítulos, PiP',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdvancedPlaybackSection()))),
```

- [ ] **Step 4: Extend the root-screen test**

Add to `test/ui/settings/settings_screen_test.dart` (use its existing `_pump` helper):
```dart
  testWidgets('root lists Reproducción avanzada and navigates', (t) async {
    await _pump(t);
    expect(find.text('Reproducción avanzada'), findsOneWidget);
    await t.tap(find.text('Reproducción avanzada'));
    await t.pumpAndSettle();
    expect(find.text('CONTINUAR VIENDO'), findsWidgets); // an uppercased group label
  });
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/ui/settings/advanced_playback_section_test.dart test/ui/settings/settings_screen_test.dart` → pass.
Run: `flutter analyze lib/ui/settings` → No issues. Then full suite `flutter test` → green.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/settings/sections/advanced_playback_section.dart lib/ui/settings/settings_screen.dart test/ui/settings/advanced_playback_section_test.dart test/ui/settings/settings_screen_test.dart
git commit -m "feat(settings): Reproducción avanzada section + nav row"
```

---

## Self-Review

**Spec coverage:** §2 controls → Task 2. §3 model (pipAutoOnHome + resettable langs) → Task 1. §4 PiP gate → Task 1. §5 nav row → Task 2. §6 tests → per-task + device checklist. Strip toggle NOT added, subtitle style NOT duplicated (per Global Constraints). All covered.

**Placeholder scan:** No TBD/TODO; complete code in every step. The lazy-ListView note is a caveat, not a placeholder. The PiP gate is device-verified (a 3-line guard not unit-testable against the full PlayerScreen) — called out explicitly.

**Type consistency:** `SettingChoice<String>` (resume), `SettingChoice<String?>` (languages — the sentinel `copyWith` from Task 1 lets `onChanged(null)` clear). `copyWith` fields match `KivoSettings` (resumeBehavior, resumeMinSeconds, autoplayNext, pipAutoOnHome, subtitlesEnabledByDefault, preferredSubtitleLanguage, preferredAudioLanguage). Task 2's language-clear test depends on Task 1's sentinel change — ordered 1→2.

## Final verification (after Task 2)

1. `flutter analyze` → No issues. `flutter test` → all green.
2. Release build + install to the Pixel 6.
3. Device checklist (spec §6): Ajustes → Reproducción avanzada; set resume to "Preguntar" and reopen a video (prompt appears); turn autoplay off (no auto-advance at end); **turn PiP-auto off and press Home → the player does NOT float into PiP** (with it on, it does); reset a remembered subtitle language to Automático. Light + dark legible. Confirm the full section list now reads General → Reproducción y gestos → Interfaz → Reproducción avanzada → Acerca de.
