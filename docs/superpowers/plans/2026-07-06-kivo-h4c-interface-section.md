# Kivo Hito 4c — Interface settings section — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the "Interfaz" settings section, wiring the UI-related `KivoSettings` fields through the toolkit plus two new reusable controls: `SettingChoice<T>` (radio list) and `SettingCornerPicker` (2×2).

**Architecture:** Two new theme-aware widgets, then an `InterfaceSettingsSection` subscreen (mirrors `GeneralSettingsSection`/`PlaybackGesturesSection`: a `Scaffold`+`ListView` of `SettingsCard` groups, each control reading `settingsProvider` and writing `set(copyWith(...))`), reached from a new `SettingNavRow` in `SettingsScreen`. The info-overlay content/corner controls show only when `showInfoOverlay` is on.

**Tech Stack:** Flutter/Riverpod, `settingsProvider` (`KivoSettings`), the toolkit in `lib/ui/settings/widgets/setting_tiles.dart` (`SettingsCard`, `SettingSwitch`, `SettingSegmented`, `SettingStepper`, `SettingNavRow`).

## Global Constraints

- **Immediate apply:** every control does `ref.read(settingsProvider.notifier).set(s.copyWith(field: v))`, watching `settingsProvider`.
- **Theme-aware:** new widgets use `Theme.of(context).colorScheme` only (no hardcoded colors).
- **Do NOT expose the `clock` info-overlay mode** (unimplemented in `info_overlay.dart`). Content options are the 3 working modes only.
- **Aspect** options are `fit`/`fill`/`stretch` only.
- **`controlsAutoHideMs` is milliseconds** — the stepper shows seconds and multiplies by 1000.
- Toolkit signatures (verbatim): `SettingSwitch({required String title, String? subtitle, required bool value, required ValueChanged<bool> onChanged})`, `SettingSegmented<T>({required String title, String? subtitle, required List<(T,String)> options, required T value, required ValueChanged<T> onChanged})`, `SettingStepper({required String title, String? subtitle, required int value, required int min, required int max, int step = 1, required String Function(int) label, required ValueChanged<int> onChanged})`, `SettingsCard({required List<Widget> children})`, `SettingNavRow({required IconData icon, required String title, String? subtitle, required VoidCallback onTap})`.
- **`flutter analyze` clean + full `flutter test` green before every commit** (current suite: 303).
- **Do NOT build the APK mid-plan.** Spanish user-facing copy.

---

### Task 1: `SettingChoice<T>` + `SettingCornerPicker`

**Files:**
- Create: `lib/ui/settings/widgets/setting_choice.dart`, `lib/ui/settings/widgets/setting_corner_picker.dart`
- Test: `test/ui/settings/setting_choice_test.dart`, `test/ui/settings/setting_corner_picker_test.dart`

**Interfaces:**
- Produces:
  - `SettingChoice<T>({required String title, String? subtitle, required List<(T,String)> options, required T value, required ValueChanged<T> onChanged})`
  - `SettingCornerPicker({required String title, required String value /* 'tl'|'tr'|'bl'|'br' */, required ValueChanged<String> onChanged})`

- [ ] **Step 1: Write the failing tests**

```dart
// test/ui/settings/setting_choice_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/widgets/setting_choice.dart';

Future<void> _host(WidgetTester t, Widget child) => t.pumpWidget(
      MaterialApp(theme: KivoTheme.dark(), home: Scaffold(body: child)));

void main() {
  testWidgets('shows a row per option; selected has the checked radio', (t) async {
    await _host(t, SettingChoice<String>(
      title: 'Contenido', value: 'name',
      options: const [('name_time', 'Nombre y tiempo'), ('name', 'Solo nombre'), ('remaining', 'Tiempo restante')],
      onChanged: (_) {}));
    expect(find.text('Nombre y tiempo'), findsOneWidget);
    expect(find.text('Solo nombre'), findsOneWidget);
    expect(find.text('Tiempo restante'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget); // exactly the selected
  });

  testWidgets('tapping another option reports its value', (t) async {
    String? got;
    await _host(t, SettingChoice<String>(
      title: 'Contenido', value: 'name',
      options: const [('name_time', 'Nombre y tiempo'), ('name', 'Solo nombre'), ('remaining', 'Tiempo restante')],
      onChanged: (v) => got = v));
    await t.tap(find.text('Tiempo restante'));
    expect(got, 'remaining');
  });
}
```

```dart
// test/ui/settings/setting_corner_picker_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/widgets/setting_corner_picker.dart';

Future<void> _host(WidgetTester t, Widget child) => t.pumpWidget(
      MaterialApp(theme: KivoTheme.dark(), home: Scaffold(body: child)));

void main() {
  testWidgets('has four corners; tapping one reports its code', (t) async {
    String? got;
    await _host(t, SettingCornerPicker(title: 'Esquina', value: 'tl', onChanged: (v) => got = v));
    for (final c in ['tl', 'tr', 'bl', 'br']) {
      expect(find.byKey(ValueKey('corner-$c')), findsOneWidget);
    }
    await t.tap(find.byKey(const ValueKey('corner-br')));
    expect(got, 'br');
  });
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/ui/settings/setting_choice_test.dart test/ui/settings/setting_corner_picker_test.dart`
Expected: FAIL — the widgets don't exist.

- [ ] **Step 3: Implement**

```dart
// lib/ui/settings/widgets/setting_choice.dart
import 'package:flutter/material.dart';

/// A titled radio-style list: one selectable row per option.
class SettingChoice<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const SettingChoice({super.key, required this.title, this.subtitle,
      required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
          if (subtitle != null)
            Padding(padding: const EdgeInsets.only(top: 3),
              child: Text(subtitle!, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant))),
          const SizedBox(height: 4),
          for (final (v, lbl) in options)
            InkWell(
              onTap: () => onChanged(v),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(children: [
                  Icon(v == value ? Icons.radio_button_checked : Icons.radio_button_off,
                      size: 20, color: v == value ? cs.secondary : cs.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(child: Text(lbl, style: TextStyle(fontSize: 13.5,
                      color: v == value ? cs.onSurface : cs.onSurfaceVariant,
                      fontWeight: v == value ? FontWeight.w600 : FontWeight.w500))),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
```

```dart
// lib/ui/settings/widgets/setting_corner_picker.dart
import 'package:flutter/material.dart';

/// Picks one of the four corners ('tl'/'tr'/'bl'/'br') on a mini rectangle.
class SettingCornerPicker extends StatelessWidget {
  final String title;
  final String value;
  final ValueChanged<String> onChanged;
  const SettingCornerPicker({super.key, required this.title, required this.value, required this.onChanged});

  static const _corners = <(String, Alignment)>[
    ('tl', Alignment.topLeft), ('tr', Alignment.topRight),
    ('bl', Alignment.bottomLeft), ('br', Alignment.bottomRight),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
      child: Row(children: [
        Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface))),
        Container(
          width: 110, height: 64,
          decoration: BoxDecoration(
            color: cs.surface, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Stack(children: [
            for (final (code, align) in _corners)
              Align(
                alignment: align,
                child: GestureDetector(
                  key: ValueKey('corner-$code'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(code),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Container(
                      width: 20, height: 13,
                      decoration: BoxDecoration(
                        color: code == value ? cs.secondary : Colors.transparent,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: code == value ? cs.secondary : cs.onSurfaceVariant.withValues(alpha: 0.6)),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `flutter test test/ui/settings/setting_choice_test.dart test/ui/settings/setting_corner_picker_test.dart` → all pass.
Run: `flutter analyze lib/ui/settings/widgets/setting_choice.dart lib/ui/settings/widgets/setting_corner_picker.dart` → No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/widgets/setting_choice.dart lib/ui/settings/widgets/setting_corner_picker.dart test/ui/settings/setting_choice_test.dart test/ui/settings/setting_corner_picker_test.dart
git commit -m "feat(settings): SettingChoice radio list + SettingCornerPicker 2x2"
```

---

### Task 2: `InterfaceSettingsSection` + nav row

**Files:**
- Create: `lib/ui/settings/sections/interface_section.dart`
- Modify: `lib/ui/settings/settings_screen.dart` (nav row before "Acerca de")
- Test: `test/ui/settings/interface_section_test.dart`, extend `test/ui/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `SettingsCard`, `SettingSwitch`, `SettingSegmented`, `SettingStepper` (toolkit); `SettingChoice`, `SettingCornerPicker` (Task 1); `settingsProvider`.
- Produces: `InterfaceSettingsSection` (`ConsumerWidget`).

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/settings/interface_section_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/sections/interface_section.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _pump(WidgetTester t) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: KivoTheme.dark(), home: const InterfaceSettingsSection()),
  ));
  await t.pump();
  return c;
}

void main() {
  testWidgets('aspect segmented persists defaultAspectMode', (t) async {
    final c = await _pump(t);
    await t.tap(find.text('Llenar'));
    await t.pump();
    expect(c.read(settingsProvider).defaultAspectMode, 'fill');
  });

  testWidgets('info-overlay content/corner hide when the overlay is off', (t) async {
    final c = await _pump(t);
    // Default showInfoOverlay is true → the content choice is present.
    expect(find.text('Contenido'), findsOneWidget);
    // Turn the overlay off (its switch) → content/corner disappear.
    final showRow = find.ancestor(of: find.text('Mostrar overlay de info'), matching: find.byType(Row)).first;
    await t.tap(find.descendant(of: showRow, matching: find.byType(Switch)));
    await t.pump();
    expect(c.read(settingsProvider).showInfoOverlay, isFalse);
    expect(find.text('Contenido'), findsNothing);
  });

  testWidgets('choosing a content mode persists infoOverlayContent', (t) async {
    final c = await _pump(t);
    await t.tap(find.text('Solo nombre'));
    await t.pump();
    expect(c.read(settingsProvider).infoOverlayContent, 'name');
  });

  testWidgets('columns segmented persists libraryColumns', (t) async {
    final c = await _pump(t);
    await t.tap(find.text('2'));
    await t.pump();
    expect(c.read(settingsProvider).libraryColumns, 2);
  });
}
```

(Note: the section is a lazy `ListView`; if a target is below the fold, add `await t.drag(find.byType(Scrollable).first, const Offset(0, -400)); await t.pump();` before locating it. Keep the assertion — persistence — as the point.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/settings/interface_section_test.dart`
Expected: FAIL — `InterfaceSettingsSection` doesn't exist.

- [ ] **Step 3: Implement the section**

```dart
// lib/ui/settings/sections/interface_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../widgets/setting_tiles.dart';
import '../widgets/setting_choice.dart';
import '../widgets/setting_corner_picker.dart';

class InterfaceSettingsSection extends ConsumerWidget {
  const InterfaceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Interfaz')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _label(context, 'Controles'),
          SettingsCard(children: [
            SettingStepper(
              title: 'Auto-ocultar controles',
              value: (s.controlsAutoHideMs / 1000).round().clamp(1, 10),
              min: 1, max: 10, step: 1, label: (v) => '$v s',
              onChanged: (v) => n.set(s.copyWith(controlsAutoHideMs: v * 1000))),
            SettingSwitch(
              title: 'Recordar orientación entre videos', value: s.rememberOrientationLock,
              onChanged: (v) => n.set(s.copyWith(rememberOrientationLock: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Video'),
          SettingsCard(children: [
            SettingSegmented<String>(
              title: 'Aspecto por defecto', value: s.defaultAspectMode,
              options: const [('fit', 'Ajustar'), ('fill', 'Llenar'), ('stretch', 'Estirar')],
              onChanged: (v) => n.set(s.copyWith(defaultAspectMode: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Overlay de información'),
          SettingsCard(children: [
            SettingSwitch(
              title: 'Mostrar overlay de info', value: s.showInfoOverlay,
              onChanged: (v) => n.set(s.copyWith(showInfoOverlay: v))),
            if (s.showInfoOverlay) ...[
              SettingChoice<String>(
                title: 'Contenido', value: s.infoOverlayContent,
                options: const [('name_time', 'Nombre y tiempo'), ('name', 'Solo nombre'), ('remaining', 'Tiempo restante')],
                onChanged: (v) => n.set(s.copyWith(infoOverlayContent: v))),
              SettingCornerPicker(
                title: 'Esquina', value: s.infoOverlayCorner,
                onChanged: (v) => n.set(s.copyWith(infoOverlayCorner: v))),
            ],
          ]),
          const SizedBox(height: 16),
          _label(context, 'Biblioteca'),
          SettingsCard(children: [
            SettingSegmented<int>(
              title: 'Columnas por defecto', value: s.libraryColumns,
              options: const [(1, '1'), (2, '2'), (3, '3')],
              onChanged: (v) => n.set(s.copyWith(libraryColumns: v))),
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
import 'sections/interface_section.dart';
```
Insert this `SettingNavRow` in the root `SettingsCard` BETWEEN the "Reproducción y gestos" row and the "Acerca de" row:
```dart
            SettingNavRow(
              icon: Icons.dashboard_customize_outlined,
              title: 'Interfaz',
              subtitle: 'Controles, overlay, aspecto, columnas',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InterfaceSettingsSection()))),
```

- [ ] **Step 4: Extend the root-screen test**

Add to `test/ui/settings/settings_screen_test.dart` (use its existing `_pump` helper):
```dart
  testWidgets('root lists Interfaz and navigates', (t) async {
    await _pump(t);
    expect(find.text('Interfaz'), findsOneWidget);
    await t.tap(find.text('Interfaz'));
    await t.pumpAndSettle();
    expect(find.text('CONTROLES'), findsWidgets); // an uppercased group label on the section
  });
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/ui/settings/interface_section_test.dart test/ui/settings/settings_screen_test.dart` → pass.
Run: `flutter analyze lib/ui/settings` → No issues. Then full suite `flutter test` → green.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/settings/sections/interface_section.dart lib/ui/settings/settings_screen.dart test/ui/settings/interface_section_test.dart test/ui/settings/settings_screen_test.dart
git commit -m "feat(settings): Interfaz section + nav row"
```

---

## Self-Review

**Spec coverage:** §2 widgets → Task 1. §3 section controls (auto-hide ms×1000, orientation, aspect, overlay show + conditional content/corner, columns) → Task 2. §4 nav row → Task 2. §5 tests → per-task + device checklist. `clock` not exposed (Global Constraints). All covered.

**Placeholder scan:** No TBD/TODO; complete code in every step. The lazy-ListView finder note is a caveat, not a placeholder.

**Type consistency:** `SettingChoice<T>` and `SettingCornerPicker` signatures match between Task 1 (definition) and Task 2 (use). `SettingSegmented<int>` for columns, `<String>` for aspect. `copyWith` fields match `KivoSettings` (controlsAutoHideMs, rememberOrientationLock, defaultAspectMode, showInfoOverlay, infoOverlayContent, infoOverlayCorner, libraryColumns). Stepper value clamped to [1,10] to satisfy the ±enable logic.

## Final verification (after Task 2)

1. `flutter analyze` → No issues. `flutter test` → all green.
2. Release build + install to the Pixel 6.
3. Device checklist (spec §5): Ajustes → Interfaz; change default aspect and open a fresh video in it; lower auto-hide to 1s and see controls hide faster; toggle the info overlay off (content/corner vanish) and on; move the corner and see the overlay reposition; change default columns and see the library density. Light + dark legible.
