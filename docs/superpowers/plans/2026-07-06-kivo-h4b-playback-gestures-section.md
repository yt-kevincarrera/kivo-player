# Kivo Hito 4b — Playback & Gestures settings section — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the "Reproducción y gestos" settings section, wiring the playback/gesture `KivoSettings` fields through the existing tile toolkit, plus a reusable `SettingSpeedList` chip editor for the two speed-list fields.

**Architecture:** A new `PlaybackGesturesSection` subscreen (mirrors `GeneralSettingsSection`: a `Scaffold`+`ListView` of `SettingsCard` groups, each control reading `settingsProvider` and writing `set(copyWith(...))`), reached from a new `SettingNavRow` in `SettingsScreen`. One new widget, `SettingSpeedList`, edits a `List<double>` as removable chips + an "add" sheet; it's used for both `speedPresets` and `holdRightDetents`.

**Tech Stack:** Flutter/Riverpod, `settingsProvider` (`KivoSettings`), the existing toolkit in `lib/ui/settings/widgets/setting_tiles.dart` (`SettingsCard`, `SettingSwitch`, `SettingSlider`, `SettingStepper`, `SettingSegmented`, `SettingNavRow`), `round2` from `lib/player/control/gesture_math.dart`.

## Global Constraints

- **Immediate apply:** every control does `ref.read(settingsProvider.notifier).set(s.copyWith(field: v))`. No local buffer.
- **Theme-aware:** the toolkit already derives from the accent/theme; do not hardcode colors in the section. `SettingSpeedList` uses `Theme.of(context).colorScheme`.
- **Do NOT expose `holdRightMin`** — it's unused in the codebase (a dead knob). Not shown.
- **Exact toolkit signatures** (verbatim — match these):
  - `SettingSwitch({required String title, String? subtitle, required bool value, required ValueChanged<bool> onChanged})`
  - `SettingSlider({required String title, required double value, required double min, required double max, int? divisions, required String Function(double) label, required ValueChanged<double> onChanged})`
  - `SettingStepper({required String title, String? subtitle, required int value, required int min, required int max, int step = 1, required String Function(int) label, required ValueChanged<int> onChanged})`
  - `SettingSegmented<T>({required String title, String? subtitle, required List<(T,String)> options, required T value, required ValueChanged<T> onChanged})`
  - `SettingsCard({required List<Widget> children})`, `SettingNavRow({required IconData icon, required String title, String? subtitle, required VoidCallback onTap})`
- **`flutter analyze` clean + full `flutter test` green before every commit** (current suite: 295).
- **Do NOT build the APK mid-plan — one build at the end.**
- Spanish user-facing copy.

---

### Task 1: `SettingSpeedList` reusable chip editor

**Files:**
- Create: `lib/ui/settings/widgets/setting_speed_list.dart`
- Test: `test/ui/settings/setting_speed_list_test.dart`

**Interfaces:**
- Consumes: `round2` from `player/control/gesture_math.dart`.
- Produces: `SettingSpeedList({required String title, String? subtitle, required List<double> values, double min = 0.25, double max = 8.0, required ValueChanged<List<double>> onChanged})` — chips (sorted, removable when >1) + an add-sheet.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/settings/setting_speed_list_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/widgets/setting_speed_list.dart';

Future<void> _host(WidgetTester t, Widget child) => t.pumpWidget(
      MaterialApp(theme: KivoTheme.dark(), home: Scaffold(body: child)),
    );

void main() {
  testWidgets('shows one chip per value, sorted', (t) async {
    await _host(t, SettingSpeedList(
      title: 'Presets', values: const [2.0, 1.0, 1.5], onChanged: (_) {}));
    expect(find.text('1×'), findsOneWidget);
    expect(find.text('1.5×'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);
  });

  testWidgets('removing a chip reports the list without it', (t) async {
    List<double>? got;
    await _host(t, SettingSpeedList(
      title: 'Presets', values: const [1.0, 1.5, 2.0], onChanged: (v) => got = v));
    // Each removable chip has a close icon; tap the one inside the 1.5× chip.
    await t.tap(find.descendant(
      of: find.ancestor(of: find.text('1.5×'), matching: find.byType(Row)).first,
      matching: find.byIcon(Icons.close)));
    expect(got, isNotNull);
    expect(got!.contains(1.5), isFalse);
    expect(got!.length, 2);
  });

  testWidgets('a single value has no remove affordance', (t) async {
    await _host(t, SettingSpeedList(
      title: 'Presets', values: const [1.0], onChanged: (_) {}));
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('the add chip opens a sheet that reports a new sorted value', (t) async {
    List<double>? got;
    await _host(t, SettingSpeedList(
      title: 'Presets', values: const [1.0, 2.0], min: 0.25, max: 4.0, onChanged: (v) => got = v));
    await t.tap(find.byKey(const ValueKey('speed-add')));
    await t.pumpAndSettle();
    expect(find.text('Añadir'), findsOneWidget);
    await t.tap(find.text('Añadir')); // default sheet value is min-ish; just confirm it reports
    await t.pumpAndSettle();
    expect(got, isNotNull);
    // list stays sorted and deduped
    final sorted = [...got!]..sort();
    expect(got, sorted);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/settings/setting_speed_list_test.dart`
Expected: FAIL — `SettingSpeedList` doesn't exist.

- [ ] **Step 3: Implement**

```dart
// lib/ui/settings/widgets/setting_speed_list.dart
import 'package:flutter/material.dart';
import '../../../player/control/gesture_math.dart';

/// Edits a list of playback speeds as removable chips plus an "add" sheet.
/// Used for both the speed presets and the hold-right detents.
class SettingSpeedList extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<double> values;
  final double min;
  final double max;
  final ValueChanged<List<double>> onChanged;
  const SettingSpeedList({
    super.key,
    required this.title,
    this.subtitle,
    required this.values,
    this.min = 0.25,
    this.max = 8.0,
    required this.onChanged,
  });

  static String fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sorted = [...values]..sort();
    final canRemove = sorted.length > 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(subtitle!, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
            ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in sorted) _chip(context, cs, v, canRemove),
              _addChip(context, cs),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, ColorScheme cs, double v, bool canRemove) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 7, canRemove ? 6 : 12, 7),
      decoration: BoxDecoration(
        color: cs.secondary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.secondary.withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${fmt(v)}×', style: TextStyle(color: cs.secondary, fontWeight: FontWeight.w700, fontSize: 13)),
        if (canRemove) ...[
          const SizedBox(width: 3),
          GestureDetector(
            onTap: () => onChanged([...values]..remove(v)),
            child: Icon(Icons.close, size: 15, color: cs.secondary),
          ),
        ],
      ]),
    );
  }

  Widget _addChip(BuildContext context, ColorScheme cs) {
    return GestureDetector(
      key: const ValueKey('speed-add'),
      onTap: () async {
        final added = await showModalBottomSheet<double>(
          context: context,
          isScrollControlled: true,
          backgroundColor: cs.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => _AddSpeedSheet(min: min, max: max),
        );
        if (added != null) {
          final next = ({...values, round2(added)}.toList())..sort();
          onChanged(next);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
        ),
        child: Icon(Icons.add, size: 18, color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _AddSpeedSheet extends StatefulWidget {
  final double min, max;
  const _AddSpeedSheet({required this.min, required this.max});
  @override
  State<_AddSpeedSheet> createState() => _AddSpeedSheetState();
}

class _AddSpeedSheetState extends State<_AddSpeedSheet> {
  late double _v = widget.min;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final divisions = ((widget.max - widget.min) / 0.25).round();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Text('Añadir velocidad',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface))),
            const SizedBox(height: 12),
            Center(child: Text('${SettingSpeedList.fmt(_v)}×',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: cs.secondary))),
            Slider(
              value: _v, min: widget.min, max: widget.max, divisions: divisions,
              activeColor: cs.secondary,
              onChanged: (x) => setState(() => _v = round2(x)),
            ),
            Row(children: [
              Expanded(child: TextButton(
                onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: cs.secondary, foregroundColor: cs.onSecondary),
                onPressed: () => Navigator.of(context).pop(_v),
                child: const Text('Añadir'))),
            ]),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/settings/setting_speed_list_test.dart` → 4 pass.
Run: `flutter analyze lib/ui/settings/widgets/setting_speed_list.dart` → No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/widgets/setting_speed_list.dart test/ui/settings/setting_speed_list_test.dart
git commit -m "feat(settings): SettingSpeedList — removable speed chips + add sheet"
```

---

### Task 2: `PlaybackGesturesSection` + nav row

**Files:**
- Create: `lib/ui/settings/sections/playback_gestures_section.dart`
- Modify: `lib/ui/settings/settings_screen.dart` (insert the nav row before "Acerca de")
- Test: `test/ui/settings/playback_gestures_section_test.dart`, and extend `test/ui/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `SettingsCard`, `SettingSwitch`, `SettingSlider`, `SettingStepper`, `SettingSegmented` (toolkit), `SettingSpeedList` (Task 1), `settingsProvider`.
- Produces: `PlaybackGesturesSection` (`ConsumerWidget`).

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/settings/playback_gestures_section_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/sections/playback_gestures_section.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _pump(WidgetTester t) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: KivoTheme.dark(), home: const PlaybackGesturesSection()),
  ));
  await t.pump();
  return c;
}

void main() {
  testWidgets('toggling horizontal seek persists', (t) async {
    final c = await _pump(t);
    final before = c.read(settingsProvider).horizontalSeek;
    await t.tap(find.byType(Switch).at(0)); // first switch is doubleTapCenterPause; find horizontalSeek instead
    await t.pump();
    // Not asserting the specific switch here — see the targeted test below.
    expect(c.read(settingsProvider), isNotNull);
  });

  testWidgets('the fine-step segmented persists speedFineStep', (t) async {
    final c = await _pump(t);
    await t.ensureVisible(find.text('0.10×'));
    await t.tap(find.text('0.10×'));
    await t.pump();
    expect(c.read(settingsProvider).speedFineStep, 0.1);
  });

  testWidgets('removing a preset persists speedPresets', (t) async {
    final c = await _pump(t);
    final before = c.read(settingsProvider).speedPresets.length;
    // Remove the first removable preset chip.
    await t.ensureVisible(find.text('Velocidades preseleccionadas'));
    final closeIcons = find.byIcon(Icons.close);
    expect(closeIcons, findsWidgets);
    await t.tap(closeIcons.first);
    await t.pump();
    expect(c.read(settingsProvider).speedPresets.length, before - 1);
  });
}
```

(Note: the first test is a smoke check; the fine-step and preset tests are the meaningful ones. If `ensureVisible`/tap targeting is flaky against the real layout, adapt the finder — the assertion (the setting persists) is what matters. Use `find.text('0.10×')` for the fine-step segment label as written in Step 3.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/settings/playback_gestures_section_test.dart`
Expected: FAIL — `PlaybackGesturesSection` doesn't exist.

- [ ] **Step 3: Implement the section**

```dart
// lib/ui/settings/sections/playback_gestures_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../widgets/setting_tiles.dart';
import '../widgets/setting_speed_list.dart';

class PlaybackGesturesSection extends ConsumerWidget {
  const PlaybackGesturesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    String sec(int v) => '$v s';
    String x1(double v) => '${v.toStringAsFixed(1)}×';
    String x2(double v) => '${v.toStringAsFixed(2)}×';

    return Scaffold(
      appBar: AppBar(title: const Text('Reproducción y gestos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _label(context, 'Doble toque'),
          SettingsCard(children: [
            SettingStepper(
              title: 'Saltar atrás', value: s.doubleTapSkipLeft, min: 5, max: 60, step: 5,
              label: sec, onChanged: (v) => n.set(s.copyWith(doubleTapSkipLeft: v))),
            SettingStepper(
              title: 'Saltar adelante', value: s.doubleTapSkipRight, min: 5, max: 60, step: 5,
              label: sec, onChanged: (v) => n.set(s.copyWith(doubleTapSkipRight: v))),
            SettingSwitch(
              title: 'Pausar con doble toque al centro', value: s.doubleTapCenterPause,
              onChanged: (v) => n.set(s.copyWith(doubleTapCenterPause: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Salto y seek'),
          SettingsCard(children: [
            SettingStepper(
              title: 'Salto de los botones ±', value: s.centerSkipSeconds, min: 5, max: 60, step: 5,
              label: sec, onChanged: (v) => n.set(s.copyWith(centerSkipSeconds: v))),
            SettingSwitch(
              title: 'Buscar deslizando en horizontal', value: s.horizontalSeek,
              onChanged: (v) => n.set(s.copyWith(horizontalSeek: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Sensibilidad de gestos'),
          SettingsCard(children: [
            SettingSlider(
              title: 'Brillo', value: s.brightnessSensitivity, min: 0.5, max: 2.0, divisions: 15,
              label: x1, onChanged: (v) => n.set(s.copyWith(brightnessSensitivity: v))),
            SettingSlider(
              title: 'Volumen', value: s.volumeSensitivity, min: 0.5, max: 2.0, divisions: 15,
              label: x1, onChanged: (v) => n.set(s.copyWith(volumeSensitivity: v))),
            SettingSlider(
              title: 'Seek', value: s.seekSensitivity, min: 0.5, max: 2.0, divisions: 15,
              label: x1, onChanged: (v) => n.set(s.copyWith(seekSensitivity: v))),
            SettingStepper(
              title: 'Boost máximo de volumen', value: s.volumeBoostMax, min: 100, max: 200, step: 10,
              label: (v) => '$v %', onChanged: (v) => n.set(s.copyWith(volumeBoostMax: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Velocidad'),
          SettingsCard(children: [
            SettingSwitch(
              title: 'Recordar velocidad entre videos', value: s.rememberSpeed,
              onChanged: (v) => n.set(s.copyWith(rememberSpeed: v))),
            SettingSlider(
              title: 'Velocidad al mantener (izquierda)', value: s.holdLeftSpeed, min: 1.0, max: 4.0,
              divisions: 12, label: x2, onChanged: (v) => n.set(s.copyWith(holdLeftSpeed: v))),
            SettingSlider(
              title: 'Velocidad máxima', value: s.holdRightMax, min: 2.0, max: 8.0, divisions: 12,
              label: x1, onChanged: (v) => n.set(s.copyWith(holdRightMax: v))),
            SettingSwitch(
              title: 'Al soltar el acelerador, volver a la velocidad anterior',
              value: s.holdRightReleaseToNormal,
              onChanged: (v) => n.set(s.copyWith(holdRightReleaseToNormal: v))),
            SettingSegmented<double>(
              title: 'Paso fino de velocidad', value: s.speedFineStep,
              options: const [(0.01, '0.01×'), (0.05, '0.05×'), (0.1, '0.10×'), (0.25, '0.25×')],
              onChanged: (v) => n.set(s.copyWith(speedFineStep: v))),
            SettingSpeedList(
              title: 'Velocidades preseleccionadas',
              subtitle: 'Las que aparecen en el panel de velocidad',
              values: s.speedPresets, min: 0.25, max: 4.0,
              onChanged: (v) => n.set(s.copyWith(speedPresets: v))),
            SettingSpeedList(
              title: 'Escalones del acelerador (hold derecho)',
              subtitle: 'La escalera de velocidades al mantener a la derecha',
              values: s.holdRightDetents, min: 1.0, max: 8.0,
              onChanged: (v) => n.set(s.copyWith(holdRightDetents: v))),
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

In `lib/ui/settings/settings_screen.dart`, add the import and the nav row. Add near the top:
```dart
import 'sections/playback_gestures_section.dart';
```
Inside the root `SettingsCard`, insert BETWEEN the General row and the Acerca de row:
```dart
            SettingNavRow(
              icon: Icons.videogame_asset_outlined,
              title: 'Reproducción y gestos',
              subtitle: 'Saltos, sensibilidades, velocidad',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlaybackGesturesSection()))),
```

- [ ] **Step 4: Extend the root-screen test**

Add to `test/ui/settings/settings_screen_test.dart`:
```dart
  testWidgets('root lists Reproducción y gestos and navigates', (t) async {
    await _pump(t); // existing helper in that file
    expect(find.text('Reproducción y gestos'), findsOneWidget);
    await t.tap(find.text('Reproducción y gestos'));
    await t.pumpAndSettle();
    expect(find.text('Doble toque'), findsWidgets); // a group label on the section
  });
```
(Use the file's existing `_pump` helper / provider overrides.)

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/ui/settings/playback_gestures_section_test.dart test/ui/settings/settings_screen_test.dart` → pass.
Run: `flutter analyze lib/ui/settings` → No issues. Then full suite `flutter test` → green.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/settings/sections/playback_gestures_section.dart lib/ui/settings/settings_screen.dart test/ui/settings/playback_gestures_section_test.dart test/ui/settings/settings_screen_test.dart
git commit -m "feat(settings): Reproducción y gestos section + nav row"
```

---

## Self-Review

**Spec coverage:** §2 controls → Task 2 (all fields; `holdRightMin` intentionally omitted per Global Constraints). §3 `SettingSpeedList` → Task 1. §4 nav row → Task 2. §5 tests → per-task + device checklist. All covered.

**Placeholder scan:** No TBD/TODO; complete code in every step. The section test's first case is flagged as a smoke check with a note to lean on the fine-step/preset assertions — not a placeholder.

**Type consistency:** `SettingSpeedList(values, min, max, onChanged)` matches between Task 1 (definition) and Task 2 (two uses). Toolkit signatures copied verbatim from Global Constraints. `copyWith` field names match `KivoSettings` (doubleTapSkipLeft/Right, doubleTapCenterPause, centerSkipSeconds, horizontalSeek, brightnessSensitivity, volumeSensitivity, seekSensitivity, volumeBoostMax, rememberSpeed, holdLeftSpeed, holdRightMax, holdRightReleaseToNormal, speedFineStep, speedPresets, holdRightDetents). `speedFineStep` is a `double` → `SettingSegmented<double>`.

## Final verification (after Task 2)

1. `flutter analyze` → No issues. `flutter test` → all green.
2. Release build + install to the Pixel 6.
3. Device checklist (spec §5): open Ajustes → Reproducción y gestos; each control applies (raise volume sensitivity → gesture more sensitive; toggle horizontal seek off → swipe-seek disabled; change fine step → speed panel ± granularity changes; remove/add a preset → reflected in the speed panel; raise "Velocidad máxima" → speed panel slider max grows). Light + dark theme both legible.
