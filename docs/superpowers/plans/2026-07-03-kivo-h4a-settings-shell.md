# Kivo Hito 4a — Settings Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the settings-panel shell (master-detail navigation), a reusable row-widget toolkit, a "General" section (theme / accent color / haptics), an "About" section, and reset-to-defaults — reachable from a gear in the library AppBar.

**Architecture:** A normal `Scaffold` route (`SettingsScreen`) pushed from `LibraryScreen`'s AppBar. The root lists sections as `SettingNavRow`s (data-driven list) and pushes each to its own section screen. Reusable tiles (`setting_tiles.dart`) take value + `onChanged` callbacks; sections wire them to `settingsProvider` (immediate apply via the existing `set(copyWith(...))`). All UI is **theme-aware** (`Theme.of(context).colorScheme`) so it renders correctly in light mode too — theme is itself a setting here.

**Tech Stack:** Flutter/Riverpod, existing `settingsProvider` (`NotifierProvider<SettingsNotifier, KivoSettings>`), `KivoColors` (`gold = 0xFFE8B84B`), Material 3 `ColorScheme` tonal roles.

## Global Constraints

- **Immediate apply, no save button:** every control writes via `ref.read(settingsProvider.notifier).set(s.copyWith(field: v))`. Never a local buffer.
- **Theme-aware surfaces:** use `Theme.of(context).colorScheme` (cards = `colorScheme.surfaceContainerHighest`, text = `onSurface`/`onSurfaceVariant`). Do NOT hardcode the player's dark navy palette — the settings screen must look right in light mode. Accent for active/selected states = `Color(ref.watch(settingsProvider).accentColor)`.
- **Card language:** grouped tiles sit in a rounded container, `BorderRadius.circular(13)`, thin divider `Divider(height: 1, color: colorScheme.outlineVariant)` between rows within a card.
- **No "coming soon" rows:** the root section list contains only built sections (4a: General, About). 4b/4c/4d insert their entry later. Keep the list data-driven so adding one is a one-line change.
- **`flutter analyze` clean + full `flutter test` green before every commit** (current suite: 263).
- **Do NOT build the APK mid-plan — one build at the end.**
- Copy in Spanish, matching the app (e.g. "Ajustes", "General", "Acerca de", "Restablecer valores").

---

### Task 1: Reusable input tiles (switch / slider / stepper / segmented / nav row)

**Files:**
- Create: `lib/ui/settings/widgets/setting_tiles.dart`
- Test: `test/ui/settings/setting_tiles_test.dart`

**Interfaces:**
- Produces (all `StatelessWidget`, theme-aware, no provider coupling):
  - `SettingNavRow({required IconData icon, required String title, String? subtitle, required VoidCallback onTap})`
  - `SettingSwitch({required String title, String? subtitle, required bool value, required ValueChanged<bool> onChanged})`
  - `SettingSlider({required String title, required double value, required double min, required double max, int? divisions, required String Function(double) label, required ValueChanged<double> onChanged})`
  - `SettingStepper({required String title, String? subtitle, required int value, required int min, required int max, int step = 1, required String Function(int) label, required ValueChanged<int> onChanged})`
  - `SettingSegmented<T>({required String title, String? subtitle, required List<(T, String)> options, required T value, required ValueChanged<T> onChanged})`
  - `SettingsCard({required List<Widget> children})` — wraps rows with the card decoration + dividers.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/settings/setting_tiles_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/widgets/setting_tiles.dart';

Future<void> _host(WidgetTester t, Widget child) => t.pumpWidget(
      MaterialApp(theme: KivoTheme.dark(), home: Scaffold(body: child)),
    );

void main() {
  testWidgets('SettingNavRow shows title/subtitle and fires onTap', (t) async {
    var tapped = false;
    await _host(t, SettingNavRow(icon: Icons.tune, title: 'General', subtitle: 'Tema', onTap: () => tapped = true));
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Tema'), findsOneWidget);
    await t.tap(find.text('General'));
    expect(tapped, isTrue);
  });

  testWidgets('SettingSwitch reflects value and toggles', (t) async {
    bool? got;
    await _host(t, SettingSwitch(title: 'Háptica', value: true, onChanged: (v) => got = v));
    await t.tap(find.byType(Switch));
    expect(got, isFalse);
  });

  testWidgets('SettingSlider shows the formatted label and reports changes', (t) async {
    double? got;
    await _host(t, SettingSlider(
      title: 'Sensibilidad', value: 1.0, min: 0.5, max: 2.0, label: (v) => v.toStringAsFixed(1), onChanged: (v) => got = v));
    expect(find.text('1.0'), findsOneWidget);
    await t.drag(find.byType(Slider), const Offset(60, 0));
    expect(got, isNotNull);
    expect(got, greaterThan(1.0));
  });

  testWidgets('SettingStepper clamps at min/max and steps', (t) async {
    int? got;
    await _host(t, SettingStepper(
      title: 'Salto', value: 10, min: 5, max: 30, step: 5, label: (v) => '$v s', onChanged: (v) => got = v));
    expect(find.text('10 s'), findsOneWidget);
    await t.tap(find.text('+'));
    expect(got, 15);
  });

  testWidgets('SettingStepper disables + at max', (t) async {
    int? got;
    await _host(t, SettingStepper(
      title: 'Salto', value: 30, min: 5, max: 30, step: 5, label: (v) => '$v s', onChanged: (v) => got = v));
    await t.tap(find.text('+'));
    expect(got, isNull); // at max, no change
  });

  testWidgets('SettingSegmented highlights the active option and switches', (t) async {
    String? got;
    await _host(t, SettingSegmented<String>(
      title: 'Tema',
      options: const [('auto', 'Auto'), ('dark', 'Oscuro'), ('light', 'Claro')],
      value: 'dark',
      onChanged: (v) => got = v));
    expect(find.text('Oscuro'), findsOneWidget);
    await t.tap(find.text('Claro'));
    expect(got, 'light');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/settings/setting_tiles_test.dart`
Expected: FAIL — `setting_tiles.dart` / the widgets don't exist (compile error).

- [ ] **Step 3: Implement the tiles**

```dart
// lib/ui/settings/widgets/setting_tiles.dart
import 'package:flutter/material.dart';

/// Rounded card that groups setting rows with hairline dividers between them.
class SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const SettingsCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, thickness: 1, color: cs.outlineVariant.withValues(alpha: 0.5)));
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(13),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

class SettingNavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const SettingNavRow({super.key, required this.icon, required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: cs.secondary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: cs.secondary),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class SettingSwitch extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SettingSwitch({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 6, 10, 6),
      child: Row(
        children: [
          Expanded(child: _titleBlock(context, title, subtitle)),
          Switch(value: value, activeColor: cs.secondary, onChanged: onChanged),
        ],
      ),
    );
  }
}

class SettingSlider extends StatelessWidget {
  final String title;
  final double value, min, max;
  final int? divisions;
  final String Function(double) label;
  final ValueChanged<double> onChanged;
  const SettingSlider({super.key, required this.title, required this.value, required this.min,
      required this.max, this.divisions, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface))),
            Text(label(value), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700,
                color: cs.secondary, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(overlayShape: SliderComponentShape.noOverlay),
            child: Slider(
              value: value.clamp(min, max), min: min, max: max, divisions: divisions,
              activeColor: cs.secondary, inactiveColor: cs.onSurfaceVariant.withValues(alpha: 0.3),
              onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

class SettingStepper extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int value, min, max, step;
  final String Function(int) label;
  final ValueChanged<int> onChanged;
  const SettingStepper({super.key, required this.title, this.subtitle, required this.value,
      required this.min, required this.max, this.step = 1, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canDown = value - step >= min;
    final canUp = value + step <= max;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 8, 12, 8),
      child: Row(
        children: [
          Expanded(child: _titleBlock(context, title, subtitle)),
          Container(
            decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(9)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _stepBtn(context, '−', canDown ? () => onChanged(value - step) : null),
              SizedBox(
                width: 44,
                child: Text(label(value), textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cs.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              _stepBtn(context, '+', canUp ? () => onChanged(value + step) : null),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(BuildContext context, String glyph, VoidCallback? onTap) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 34, height: 32,
        child: Center(child: Text(glyph, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
            color: onTap == null ? cs.onSurfaceVariant.withValues(alpha: 0.35) : cs.secondary))),
      ),
    );
  }
}

class SettingSegmented<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const SettingSegmented({super.key, required this.title, this.subtitle,
      required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 11, 15, 11),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titleBlock(context, title, subtitle),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              for (final (v, lbl) in options)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(v),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: v == value ? cs.secondary : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(lbl, textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                              color: v == value ? cs.onSecondary : cs.onSurfaceVariant)),
                    ),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

Widget _titleBlock(BuildContext context, String title, String? subtitle) {
  final cs = Theme.of(context).colorScheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
      if (subtitle != null)
        Padding(
          padding: const EdgeInsets.only(top: 3, right: 8),
          child: Text(subtitle, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant, height: 1.35)),
        ),
    ],
  );
}
```

Note: `FontFeature` is from `dart:ui`; add `import 'dart:ui' show FontFeature;` at the top (Flutter's `material.dart` does not re-export it).

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/settings/setting_tiles_test.dart`
Expected: PASS (6 tests). Then `flutter analyze lib/ui/settings/widgets/setting_tiles.dart` → No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/widgets/setting_tiles.dart test/ui/settings/setting_tiles_test.dart
git commit -m "feat(settings): reusable setting tiles (nav/switch/slider/stepper/segmented + card)"
```

---

### Task 2: Color picker sheet + `SettingColor` tile

**Files:**
- Create: `lib/ui/settings/widgets/color_picker_sheet.dart`
- Modify: `lib/ui/settings/widgets/setting_tiles.dart` (add `SettingColor`)
- Test: `test/ui/settings/color_picker_test.dart`

**Interfaces:**
- Consumes: `SettingsCard` (Task 1, for the test host only).
- Produces:
  - `SettingColor({required String title, required int value, required ValueChanged<int> onChanged})` — preset swatches + a "Personalizado" swatch that opens the sheet.
  - `Future<int?> showColorPickerSheet(BuildContext context, int initialArgb)` — HSV bottom sheet; returns the chosen ARGB or null on cancel.
  - `const kAccentPresets = <int>[0xFFE8B84B, 0xFF5B9BE8, 0xFFE86B6B, 0xFF57C08A, 0xFFB77BE8];`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/settings/color_picker_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/widgets/setting_tiles.dart';
import 'package:kivo_player/ui/settings/widgets/color_picker_sheet.dart';

void main() {
  testWidgets('SettingColor shows a swatch per preset and reports a preset tap', (t) async {
    int? got;
    await t.pumpWidget(MaterialApp(
      theme: KivoTheme.dark(),
      home: Scaffold(body: SettingColor(title: 'Acento', value: kAccentPresets.first, onChanged: (v) => got = v)),
    ));
    // one dot per preset + one "custom" dot
    expect(find.byKey(const ValueKey('accent-preset-1')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('accent-preset-1')));
    expect(got, kAccentPresets[1]);
  });

  testWidgets('the custom swatch opens the HSV sheet', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: KivoTheme.dark(),
      home: Scaffold(body: SettingColor(title: 'Acento', value: kAccentPresets.first, onChanged: (_) {})),
    ));
    await t.tap(find.byKey(const ValueKey('accent-custom')));
    await t.pumpAndSettle();
    expect(find.text('Personalizado'), findsOneWidget); // sheet header
    expect(find.text('Aplicar'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/settings/color_picker_test.dart`
Expected: FAIL — `SettingColor` / `showColorPickerSheet` / `kAccentPresets` don't exist.

- [ ] **Step 3: Implement the sheet + tile**

```dart
// lib/ui/settings/widgets/color_picker_sheet.dart
import 'package:flutter/material.dart';

/// HSV picker (hue + saturation + value sliders, no external package/network).
/// Returns the chosen ARGB, or null on cancel.
Future<int?> showColorPickerSheet(BuildContext context, int initialArgb) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ColorPickerSheet(initial: Color(initialArgb)),
  );
}

class _ColorPickerSheet extends StatefulWidget {
  final Color initial;
  const _ColorPickerSheet({required this.initial});
  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv;
  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
  }

  Color get _color => _hsv.toColor();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Text('Personalizado',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface))),
            const SizedBox(height: 16),
            Container(height: 54, decoration: BoxDecoration(
                color: _color, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant))),
            const SizedBox(height: 14),
            _channel(context, 'Matiz', _hsv.hue, 360, (v) => setState(() => _hsv = _hsv.withHue(v))),
            _channel(context, 'Saturación', _hsv.saturation, 1, (v) => setState(() => _hsv = _hsv.withSaturation(v))),
            _channel(context, 'Brillo', _hsv.value, 1, (v) => setState(() => _hsv = _hsv.withValue(v))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: cs.secondary, foregroundColor: cs.onSecondary),
                onPressed: () => Navigator.of(context).pop(
                    _color.value | 0xFF000000), // force opaque
                child: const Text('Aplicar'))),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _channel(BuildContext context, String name, double value, double max, ValueChanged<double> onChanged) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      SizedBox(width: 86, child: Text(name, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
      Expanded(child: Slider(value: value, min: 0, max: max, activeColor: cs.secondary, onChanged: onChanged)),
    ]);
  }
}
```

```dart
// APPEND to lib/ui/settings/widgets/setting_tiles.dart
// (add at top:  import 'color_picker_sheet.dart';)

const kAccentPresets = <int>[0xFFE8B84B, 0xFF5B9BE8, 0xFFE86B6B, 0xFF57C08A, 0xFFB77BE8];

class SettingColor extends StatelessWidget {
  final String title;
  final int value;
  final ValueChanged<int> onChanged;
  const SettingColor({super.key, required this.title, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onPreset = kAccentPresets.contains(value);
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 12),
          Row(children: [
            for (var i = 0; i < kAccentPresets.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _dot(
                  key: ValueKey('accent-preset-$i'),
                  color: Color(kAccentPresets[i]),
                  selected: value == kAccentPresets[i],
                  ring: cs.onSurface,
                  onTap: () => onChanged(kAccentPresets[i]),
                ),
              ),
            // Custom: a color-wheel-ish gradient dot that opens the HSV sheet.
            _dot(
              key: const ValueKey('accent-custom'),
              gradient: const SweepGradient(colors: [
                Color(0xFFE86B6B), Color(0xFFE8B84B), Color(0xFF57C08A),
                Color(0xFF5B9BE8), Color(0xFFB77BE8), Color(0xFFE86B6B),
              ]),
              selected: !onPreset,
              ring: cs.onSurface,
              onTap: () async {
                final picked = await showColorPickerSheet(context, value);
                if (picked != null) onChanged(picked);
              },
            ),
          ]),
        ],
      ),
    );
  }

  Widget _dot({Key? key, Color? color, Gradient? gradient, required bool selected,
      required Color ring, required VoidCallback onTap}) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: color, gradient: gradient, shape: BoxShape.circle,
          border: Border.all(color: selected ? ring : Colors.transparent, width: 2.5),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/settings/color_picker_test.dart`
Expected: PASS (2 tests). `flutter analyze lib/ui/settings/widgets/` → No issues. (`Color.value` is deprecated-soft in newer SDKs but present; if analyze flags it, use `(_color.a*... )` — but the repo already uses `.value`/ARGB ints, so `| 0xFF000000` on `.value` is consistent.)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/widgets/ test/ui/settings/color_picker_test.dart
git commit -m "feat(settings): SettingColor tile + HSV custom color sheet"
```

---

### Task 3: Root `SettingsScreen` (section list + reset) + About + route

**Files:**
- Create: `lib/ui/settings/settings_route.dart`, `lib/ui/settings/settings_screen.dart`, `lib/ui/settings/sections/about_section.dart`
- Test: `test/ui/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `SettingNavRow`, `SettingsCard` (Task 1); `settingsProvider`, `KivoSettings.defaults()`.
- Produces:
  - `Route<T> settingsRoute<T>()` → `MaterialPageRoute` to `SettingsScreen`.
  - `SettingsScreen` (`ConsumerWidget`) — root list. A private `List<_SectionEntry>` drives the rows; 4a has `General` and (rendered separately at bottom) About. `GeneralSettingsSection` is referenced but only added in Task 4 — for Task 3, the General row navigates to a minimal placeholder built in Task 4; to keep Task 3 self-contained, its row pushes `AboutSection`-style nav is NOT acceptable. **Resolution:** Task 3 wires the General row to push a `const SizedBox`-bodied `Scaffold` stub named `GeneralSettingsSection` created in Task 4; so Task 3 depends on Task 4's class existing. To avoid a forward dependency, Task 3 defines the section list with ONLY the About entry, and Task 4 inserts the General entry. The reset row and shell are fully testable with just About.
  - `AboutSection` (`StatelessWidget`) — app name, version string (hardcoded `'1.0'` constant `kAppVersion` — no new dependency), credit line.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/settings/settings_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/settings_screen.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _pump(WidgetTester t) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: KivoTheme.dark(), home: const SettingsScreen()),
  ));
  return c;
}

void main() {
  testWidgets('root lists Acerca de and Restablecer', (t) async {
    await _pump(t);
    expect(find.text('Acerca de'), findsOneWidget);
    expect(find.text('Restablecer valores'), findsOneWidget);
  });

  testWidgets('tapping Acerca de navigates to the about screen', (t) async {
    await _pump(t);
    await t.tap(find.text('Acerca de'));
    await t.pumpAndSettle();
    expect(find.text('Kivo'), findsWidgets);
    expect(find.textContaining('1.0'), findsOneWidget);
  });

  testWidgets('reset asks for confirmation, then restores defaults', (t) async {
    final c = await _pump(t);
    // Put a non-default value.
    final n = c.read(settingsProvider.notifier);
    n.set(c.read(settingsProvider).copyWith(accentColor: 0xFF5B9BE8));
    await t.pump();
    await t.tap(find.text('Restablecer valores'));
    await t.pumpAndSettle();
    expect(find.text('Restablecer'), findsOneWidget); // dialog confirm button
    await t.tap(find.text('Restablecer').last);
    await t.pumpAndSettle();
    expect(c.read(settingsProvider).accentColor, KivoSettings.defaults().accentColor);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/settings/settings_screen_test.dart`
Expected: FAIL — `SettingsScreen` doesn't exist.

- [ ] **Step 3: Implement route, screen, about**

```dart
// lib/ui/settings/settings_route.dart
import 'package:flutter/material.dart';
import 'settings_screen.dart';

Route<T> settingsRoute<T>() =>
    MaterialPageRoute<T>(builder: (_) => const SettingsScreen());
```

```dart
// lib/ui/settings/sections/about_section.dart
import 'package:flutter/material.dart';

const kAppVersion = '1.0';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Acerca de')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Kivo', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 6),
            Text('Versión $kAppVersion', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('Reproductor de video local', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
```

```dart
// lib/ui/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/kivo_settings.dart';
import '../../core/settings/settings_provider.dart';
import 'sections/about_section.dart';
import 'sections/general_section.dart';
import 'widgets/setting_tiles.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        children: [
          SettingsCard(children: [
            SettingNavRow(
              icon: Icons.tune, title: 'General', subtitle: 'Tema, color de acento, háptica',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GeneralSettingsSection()))),
            SettingNavRow(
              icon: Icons.info_outline, title: 'Acerca de', subtitle: 'Versión $kAppVersion',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutSection()))),
          ]),
          const SizedBox(height: 18),
          _ResetTile(
            onReset: () => ref.read(settingsProvider.notifier).set(KivoSettings.defaults()),
          ),
        ],
      ),
    );
  }
}

class _ResetTile extends StatelessWidget {
  final VoidCallback onReset;
  const _ResetTile({required this.onReset});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Restablecer valores'),
            content: const Text('¿Restablecer todos los ajustes a sus valores por defecto?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Restablecer')),
            ],
          ),
        );
        if (ok == true) onReset();
      },
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text('Restablecer valores',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.error)),
      ),
    );
  }
}
```

Note: `settings_screen.dart` imports `sections/general_section.dart` and references `GeneralSettingsSection` — that class is created in **Task 4**. Implement Task 4 immediately after Task 3 (they compile together). If running Task 3's test before Task 4 exists, temporarily comment the General row + import; the plan's reviewer runs them as a pair. **Simpler: do Task 4 in the same working session and run both test files together.**

- [ ] **Step 4: Run to verify it passes** (after Task 4's `GeneralSettingsSection` exists, or with the General row temporarily removed)

Run: `flutter test test/ui/settings/settings_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/settings_route.dart lib/ui/settings/settings_screen.dart lib/ui/settings/sections/about_section.dart test/ui/settings/settings_screen_test.dart
git commit -m "feat(settings): root SettingsScreen (section list + reset) + About + route"
```

---

### Task 4: General section (theme / accent / haptics)

**Files:**
- Create: `lib/ui/settings/sections/general_section.dart`
- Test: `test/ui/settings/general_section_test.dart`

**Interfaces:**
- Consumes: `SettingSegmented`, `SettingColor`, `SettingSwitch`, `SettingsCard` (Tasks 1-2); `settingsProvider`.
- Produces: `GeneralSettingsSection` (`ConsumerWidget`) — referenced by `SettingsScreen` (Task 3).

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/settings/general_section_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/settings/sections/general_section.dart';
import 'package:kivo_player/ui/settings/widgets/setting_tiles.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _pump(WidgetTester t) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: KivoTheme.dark(), home: const GeneralSettingsSection()),
  ));
  return c;
}

void main() {
  testWidgets('changing the theme segment persists themeMode', (t) async {
    final c = await _pump(t);
    await t.tap(find.text('Claro'));
    await t.pump();
    expect(c.read(settingsProvider).themeMode, 'light');
  });

  testWidgets('toggling haptics persists hapticsOnGestures', (t) async {
    final c = await _pump(t);
    final before = c.read(settingsProvider).hapticsOnGestures;
    await t.tap(find.byType(Switch));
    await t.pump();
    expect(c.read(settingsProvider).hapticsOnGestures, !before);
  });

  testWidgets('choosing an accent preset persists accentColor', (t) async {
    final c = await _pump(t);
    await t.tap(find.byKey(const ValueKey('accent-preset-1')));
    await t.pump();
    expect(c.read(settingsProvider).accentColor, kAccentPresets[1]);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/settings/general_section_test.dart`
Expected: FAIL — `GeneralSettingsSection` doesn't exist.

- [ ] **Step 3: Implement the section**

```dart
// lib/ui/settings/sections/general_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../widgets/setting_tiles.dart';

class GeneralSettingsSection extends ConsumerWidget {
  const GeneralSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('General')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _label(context, 'Apariencia'),
          SettingsCard(children: [
            SettingSegmented<String>(
              title: 'Tema',
              subtitle: 'Claro, oscuro o según el sistema',
              options: const [('auto', 'Auto'), ('dark', 'Oscuro'), ('light', 'Claro')],
              value: s.themeMode,
              onChanged: (v) => n.set(s.copyWith(themeMode: v)),
            ),
            SettingColor(
              title: 'Color de acento',
              value: s.accentColor,
              onChanged: (v) => n.set(s.copyWith(accentColor: v)),
            ),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Interacción'),
          SettingsCard(children: [
            SettingSwitch(
              title: 'Háptica en gestos',
              subtitle: 'Vibración sutil al cruzar umbrales',
              value: s.hapticsOnGestures,
              onChanged: (v) => n.set(s.copyWith(hapticsOnGestures: v)),
            ),
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

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/settings/general_section_test.dart test/ui/settings/settings_screen_test.dart`
Expected: PASS (3 + 3). `flutter analyze lib/ui/settings/` → No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/sections/general_section.dart test/ui/settings/general_section_test.dart
git commit -m "feat(settings): General section — theme / accent color / haptics"
```

---

### Task 5: Entry point — gear in the library AppBar

**Files:**
- Modify: `lib/ui/home/library_screen.dart` (add gear IconButton to AppBar actions; import `settings_route.dart`)
- Test: `test/ui/home/library_settings_entry_test.dart`

**Interfaces:**
- Consumes: `settingsRoute()` (Task 3), `SettingsScreen`.

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/home/library_settings_entry_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/ui/home/library_screen.dart';
import 'package:kivo_player/ui/settings/settings_screen.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('the gear opens the settings screen', (t) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
        mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
        playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      ],
      child: MaterialApp(theme: KivoTheme.dark(), home: const LibraryScreen()),
    ));
    await t.pump();
    await t.tap(find.byTooltip('Ajustes'));
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
```

(If `LibraryScreen` needs more provider overrides to pump — check `library_screen_test.dart` for the exact set and mirror it. Use the same `playedStoreProvider`/`mediaIndexerProvider` overrides that existing library tests use.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/home/library_settings_entry_test.dart`
Expected: FAIL — no widget with tooltip 'Ajustes'.

- [ ] **Step 3: Add the gear to the AppBar**

In `lib/ui/home/library_screen.dart`, add the import:
```dart
import '../settings/settings_route.dart';
```
In the `AppBar.actions`, inside the `if (!ref.watch(librarySearchActiveProvider)) ...[` block, add as the FIRST action in that list (before "Cambiar densidad"):
```dart
            IconButton(
              tooltip: 'Ajustes',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(settingsRoute()),
            ),
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/home/library_settings_entry_test.dart`
Expected: PASS. Then full suite: `flutter test` → all green (263 + new). `flutter analyze` → No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/home/library_screen.dart test/ui/home/library_settings_entry_test.dart
git commit -m "feat(settings): open the settings panel from a gear in the library AppBar"
```

---

## Self-Review

**Spec coverage:**
- §2 entry point → Task 5. ✓
- §2 root master-detail + reset → Task 3. ✓
- §2 About subscreen → Task 3. ✓
- §3 toolkit (nav/switch/slider/stepper/segmented/color + card) → Tasks 1-2. ✓ (all built; slider/stepper unit-tested, not mounted in General — matches spec §3.)
- §4 General (theme/accent/haptics) → Task 4. ✓
- §6 theming note (theme-aware surfaces; accent reactive) → Global Constraints + all tiles use `colorScheme`. ✓
- §7 tests → each task carries its tests; device checklist runs at plan end. ✓

**Placeholder scan:** No TBD/TODO; every code step is complete. The one cross-task coupling (Task 3 ↔ Task 4's `GeneralSettingsSection`) is called out explicitly with a resolution (run 3+4 as a pair / temporarily drop the General row). Not a placeholder.

**Type consistency:** `settingsProvider.notifier.set(...)`, `copyWith`, `KivoSettings.defaults()`, `kAccentPresets`, tile signatures — all consistent across tasks. `Color.value | 0xFF000000` used once for opacity; matches the repo's ARGB-int convention.

## Ordering note for the executor

Tasks 3 and 4 compile together (Task 3's `SettingsScreen` imports Task 4's `GeneralSettingsSection`). Implement Task 3 then Task 4 back-to-back and run their test files together at the end of Task 4. All other tasks are independent and ordered by dependency (1 → 2 → 3 → 4 → 5).

## Final verification (after Task 5)

1. `flutter analyze` → No issues. `flutter test` → all green.
2. Release build + install to the Pixel 6 (`flutter build apk --release`; `adb install -r`; launch).
3. Device checklist: gear opens Ajustes; General ↔ back; Tema → Claro flips the whole app to light instantly, → Oscuro back; accent → azul recolors library tiles/section bars and player accents; háptica on/off; Restablecer valores → confirm → theme back to Auto, accent back to gold; About shows version.
