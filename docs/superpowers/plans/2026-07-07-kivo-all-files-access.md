# All-Files-Access (Silent Delete/Rename) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user grant `MANAGE_EXTERNAL_STORAGE` once so library delete/rename run without Android's per-operation consent dialog, keeping the consent flow as a fallback.

**Architecture:** A new `AllFilesAccess` platform capability (permission_handler-backed) exposes grant status + request. The native `kivo/media` delete/rename branch silently on `Environment.isExternalStorageManager()`, else uses the existing consent flow. The UI offers the permission once on first delete/rename (persisted via a new `KivoSettings.offeredAllFilesAccess` flag) and permanently via a Settings row.

**Tech Stack:** Flutter, Riverpod, Hive, `permission_handler`, Kotlin (MediaStore), `flutter_test`.

## Global Constraints

- Single configurable accent; no new hardcoded colors.
- Platform-boundary pattern: interface in `lib/platform/interfaces/`, Android impl in `lib/platform/android/`, throws-until-overridden provider, override in `lib/main.dart`.
- No new pub dependencies (`permission_handler: ^11.3.1` is already present).
- `KivoSettings` new field uses the 6 insertion points (field, ctor param, `defaults()`, `copyWith` param + body, `toMap`, `fromMap`).
- Delete/rename must NEVER break when the permission is absent: the OS-consent flow remains a working fallback.
- No `flutter run`. On module close: `flutter build apk --release`, then `adb install` to the Pixel 6 (device `24231FDF6006ST`; adb at `$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe`).
- Full suite stays green (`flutter test`), currently 364 tests.

---

### Task 1: `AllFilesAccess` capability + `shouldOfferAllFilesAccess` + providers + fake

**Files:**
- Create: `lib/platform/interfaces/all_files_access.dart`
- Create: `lib/platform/android/android_all_files_access.dart`
- Create: `lib/platform/all_files_access_provider.dart`
- Modify: `lib/main.dart` (override the provider)
- Modify: `test/fakes/fakes.dart` (append `FakeAllFilesAccess`)
- Test: `test/platform/all_files_access_test.dart`

**Interfaces:**
- Produces:
  - `abstract class AllFilesAccess { Future<bool> isGranted(); Future<bool> request(); }`
  - `bool shouldOfferAllFilesAccess(bool granted, bool offered)` → `!granted && !offered`.
  - `final allFilesAccessProvider = Provider<AllFilesAccess>((ref) => throw UnimplementedError(...));`
  - `final allFilesAccessGrantedProvider = FutureProvider.autoDispose<bool>((ref) => ref.read(allFilesAccessProvider).isGranted());`
  - `FakeAllFilesAccess` (test): `bool granted` (mutable), `int requestCount`; `request()` sets `granted = grantOnRequest` (default true) and increments the counter.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/all_files_access.dart';
import '../fakes/fakes.dart';

void main() {
  test('shouldOfferAllFilesAccess: only when not granted and not yet offered', () {
    expect(shouldOfferAllFilesAccess(false, false), true);
    expect(shouldOfferAllFilesAccess(true, false), false);  // already granted
    expect(shouldOfferAllFilesAccess(false, true), false);  // already offered once
    expect(shouldOfferAllFilesAccess(true, true), false);
  });

  test('FakeAllFilesAccess reports and flips on request', () async {
    final a = FakeAllFilesAccess();
    expect(await a.isGranted(), false);
    expect(await a.request(), true);
    expect(a.requestCount, 1);
    expect(await a.isGranted(), true);
  });

  test('FakeAllFilesAccess can simulate a declined request', () async {
    final a = FakeAllFilesAccess()..grantOnRequest = false;
    expect(await a.request(), false);
    expect(await a.isGranted(), false);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/platform/all_files_access_test.dart`
Expected: FAIL — symbols not found.

- [ ] **Step 3: Create the interface + pure helper**

`lib/platform/interfaces/all_files_access.dart`:

```dart
/// "All files access" (Android MANAGE_EXTERNAL_STORAGE). When granted, the app
/// can delete/rename media without the per-operation system consent dialog.
abstract class AllFilesAccess {
  /// Whether the permission is granted right now.
  Future<bool> isGranted();

  /// Opens the special settings screen to grant it. Resolves (with the
  /// resulting granted state) when the user returns.
  Future<bool> request();
}

/// Whether to show the one-time "grant all-files-access" offer: only when the
/// permission isn't granted and we haven't offered it before.
bool shouldOfferAllFilesAccess(bool granted, bool offered) => !granted && !offered;
```

- [ ] **Step 4: Create the Android impl**

`lib/platform/android/android_all_files_access.dart`:

```dart
import 'package:permission_handler/permission_handler.dart';
import '../interfaces/all_files_access.dart';

class AndroidAllFilesAccess implements AllFilesAccess {
  @override
  Future<bool> isGranted() async =>
      (await Permission.manageExternalStorage.status).isGranted;

  @override
  Future<bool> request() async =>
      (await Permission.manageExternalStorage.request()).isGranted;
}
```

> Implementation note: on Android 11+, `Permission.manageExternalStorage.request()` (permission_handler ^11) navigates to the "All files access" special-access settings screen and resolves after the user returns. If a device/version fails to navigate, fall back to `openAppSettings()` — verify on the device checklist.

- [ ] **Step 5: Create the providers**

`lib/platform/all_files_access_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/all_files_access.dart';

final allFilesAccessProvider = Provider<AllFilesAccess>((ref) {
  throw UnimplementedError('allFilesAccessProvider must be overridden');
});

/// Current grant status for the Settings row; autoDispose so re-entering the
/// screen re-queries, and `ref.invalidate` refreshes it after returning from
/// the system settings screen.
final allFilesAccessGrantedProvider = FutureProvider.autoDispose<bool>(
    (ref) => ref.read(allFilesAccessProvider).isGranted());
```

- [ ] **Step 6: Override in main.dart**

In `lib/main.dart`, add the imports and the override next to `mediaFileOpsProvider.overrideWithValue(...)`:

```dart
      allFilesAccessProvider.overrideWithValue(AndroidAllFilesAccess()),
```
(Imports: `import 'platform/all_files_access_provider.dart';` and `import 'platform/android/android_all_files_access.dart';`.)

- [ ] **Step 7: Append `FakeAllFilesAccess` to `test/fakes/fakes.dart`**

Add the import if missing (`import 'package:kivo_player/platform/interfaces/all_files_access.dart';`) and append:

```dart
class FakeAllFilesAccess implements AllFilesAccess {
  bool granted;
  bool grantOnRequest;
  int requestCount = 0;
  FakeAllFilesAccess({this.granted = false, this.grantOnRequest = true});

  @override
  Future<bool> isGranted() async => granted;

  @override
  Future<bool> request() async {
    requestCount++;
    granted = grantOnRequest;
    return granted;
  }
}
```

- [ ] **Step 8: Run test + analyze**

Run: `flutter test test/platform/all_files_access_test.dart`
Expected: PASS (3 tests).
Run: `flutter analyze lib/platform/interfaces/all_files_access.dart lib/platform/android/android_all_files_access.dart lib/platform/all_files_access_provider.dart lib/main.dart`
Expected: No issues.

- [ ] **Step 9: Commit**

```bash
git add lib/platform/interfaces/all_files_access.dart lib/platform/android/android_all_files_access.dart lib/platform/all_files_access_provider.dart lib/main.dart test/fakes/fakes.dart test/platform/all_files_access_test.dart
git commit -m "feat(library): AllFilesAccess capability + providers + fake"
```

---

### Task 2: `KivoSettings.offeredAllFilesAccess` flag

**Files:**
- Modify: `lib/core/settings/kivo_settings.dart` (6 insertion points)
- Test: `test/core/settings/offered_all_files_access_test.dart`

**Interfaces:**
- Produces: `KivoSettings.offeredAllFilesAccess` (`bool`, default `false`), settable via `copyWith`, persisted in `toMap`/`fromMap`.

**Context:** `KivoSettings` requires touching 6 spots per field — mirror the existing `pipAutoOnHome` (field ~41, ctor ~83, `defaults()` ~126, `copyWith` param ~171 + body ~217, `toMap` ~261, `fromMap` ~306). Line numbers are approximate; match the surrounding pattern.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('offeredAllFilesAccess defaults to false', () {
    expect(KivoSettings.defaults().offeredAllFilesAccess, false);
  });

  test('offeredAllFilesAccess round-trips through toMap/fromMap', () {
    final s = KivoSettings.defaults().copyWith(offeredAllFilesAccess: true);
    final restored = KivoSettings.fromMap(s.toMap());
    expect(restored.offeredAllFilesAccess, true);
  });

  test('fromMap defaults the flag to false when absent (older persisted map)', () {
    final map = KivoSettings.defaults().toMap()..remove('offeredAllFilesAccess');
    expect(KivoSettings.fromMap(map).offeredAllFilesAccess, false);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/settings/offered_all_files_access_test.dart`
Expected: FAIL — no `offeredAllFilesAccess`.

- [ ] **Step 3: Add the field at all 6 points**

In `lib/core/settings/kivo_settings.dart`, following the `pipAutoOnHome` pattern exactly:

1. Field: `final bool offeredAllFilesAccess;`
2. Constructor: `required this.offeredAllFilesAccess,`
3. `defaults()`: `offeredAllFilesAccess: false,`
4. `copyWith` param: `bool? offeredAllFilesAccess,`
5. `copyWith` body: `offeredAllFilesAccess: offeredAllFilesAccess ?? this.offeredAllFilesAccess,`
6. `toMap`: `'offeredAllFilesAccess': offeredAllFilesAccess,`
7. `fromMap`: `offeredAllFilesAccess: m['offeredAllFilesAccess'] ?? d.offeredAllFilesAccess,`

(That's the field + 6 map/ctor touch-points, same as `pipAutoOnHome`.)

- [ ] **Step 4: Run test + full suite**

Run: `flutter test test/core/settings/offered_all_files_access_test.dart`
Expected: PASS (3 tests).
Run: `flutter test`
Expected: All green (existing settings round-trip tests still pass).

- [ ] **Step 5: Commit**

```bash
git add lib/core/settings/kivo_settings.dart test/core/settings/offered_all_files_access_test.dart
git commit -m "feat(settings): offeredAllFilesAccess flag (one-time permission offer)"
```

---

### Task 3: Manifest permission + native silent delete/rename path

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt`

**Interfaces:**
- Consumes: nothing from earlier Dart tasks (pure native).
- Produces: silent MediaStore delete/rename when `Environment.isExternalStorageManager()`.

**Context:** No unit test (native / real permission). Verified by `flutter analyze` clean + a successful `flutter build apk --release` (Kotlin compile) + the Task 6 device checklist. The current `delete` branch is at `MainActivity.kt:343-371`, `rename` at `:372-403`, inside the `kivo/media` handler.

- [ ] **Step 1: Add the manifest permission**

In `android/app/src/main/AndroidManifest.xml`, next to the other `<uses-permission>` lines:

```xml
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />
```

- [ ] **Step 2: Add the Environment import**

At the top of `MainActivity.kt` (with the other `android.os` imports):

```kotlin
import android.os.Environment
```

- [ ] **Step 3: Add the silent path to `delete`**

In the `"delete"` branch, inside `try {` — as the FIRST thing after `val u = Uri.parse(uri)` and the `pendingFileOpResult != null` guard — add a silent fast-path before the existing `if (Build.VERSION.SDK_INT >= R) { createDeleteRequest ... }`:

```kotlin
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                                Environment.isExternalStorageManager()) {
                                contentResolver.delete(u, null, null)
                                result.success("ok")
                                return@setMethodCallHandler
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val pi = MediaStore.createDeleteRequest(contentResolver, listOf(u))
                                // ... (existing consent flow unchanged) ...
```

(Leave the rest of the existing `delete` body exactly as-is; only the silent `if` block is inserted at the top of the `try`.)

- [ ] **Step 4: Add the silent path to `rename`**

In the `"rename"` branch, `finalName` is already computed before `try {`. Inside `try {`, as the FIRST thing, add before the existing `if (Build.VERSION.SDK_INT >= R) { createWriteRequest ... }`:

```kotlin
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                                Environment.isExternalStorageManager()) {
                                val values = android.content.ContentValues().apply {
                                    put(MediaStore.Video.Media.DISPLAY_NAME, finalName)
                                }
                                contentResolver.update(u, values, null, null)
                                result.success(mapOf("status" to "ok", "newName" to finalName))
                                return@setMethodCallHandler
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val pi = MediaStore.createWriteRequest(contentResolver, listOf(u))
                                // ... (existing consent flow unchanged) ...
```

(Leave the rest of the existing `rename` body as-is.)

- [ ] **Step 5: Analyze + release build (Kotlin compile gate)**

Run: `flutter analyze`
Expected: No issues.
Run: `flutter build apk --release`
Expected: `Built build\app\outputs\flutter-apk\app-release.apk` (a Kotlin error fails here).

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt
git commit -m "feat(library): silent delete/rename when All-files-access is granted"
```

---

### Task 4: Settings row for All-files-access

**Files:**
- Modify: `lib/ui/settings/sections/advanced_playback_section.dart`
- Test: `test/ui/settings/all_files_access_row_test.dart`

**Interfaces:**
- Consumes: `allFilesAccessProvider`, `allFilesAccessGrantedProvider` (Task 1); `SettingNavRow`/`SettingsCard` (`lib/ui/settings/widgets/setting_tiles.dart`).
- Produces: a "Acceso a todos los archivos" row whose subtitle reflects grant status and whose tap requests it.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/all_files_access_provider.dart';
import 'package:kivo_player/ui/settings/sections/advanced_playback_section.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('all-files-access row shows granted state', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      allFilesAccessProvider.overrideWithValue(FakeAllFilesAccess(granted: true)),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: AdvancedPlaybackSection()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Acceso a todos los archivos'), findsOneWidget);
    expect(find.text('Concedido'), findsOneWidget);
  });

  testWidgets('tapping the row requests access when not granted', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final fake = FakeAllFilesAccess(granted: false);
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      allFilesAccessProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: AdvancedPlaybackSection()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Acceso a todos los archivos'));
    await tester.pumpAndSettle();
    expect(fake.requestCount, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/settings/all_files_access_row_test.dart`
Expected: FAIL — the row/text doesn't exist yet.

- [ ] **Step 3: Add the row**

In `advanced_playback_section.dart`, add the imports:

```dart
import '../../../platform/all_files_access_provider.dart';
```

Add a new section before the closing `]` of the `ListView` children (after the "Subtítulos y audio" card):

```dart
          const SizedBox(height: 16),
          _label(context, 'Almacenamiento'),
          SettingsCard(children: [
            Builder(builder: (context) {
              final granted = ref.watch(allFilesAccessGrantedProvider).valueOrNull ?? false;
              return SettingNavRow(
                icon: Icons.folder_open_outlined,
                title: 'Acceso a todos los archivos',
                subtitle: granted
                    ? 'Concedido'
                    : 'Toca para borrar y renombrar sin confirmación',
                onTap: () async {
                  await ref.read(allFilesAccessProvider).request();
                  ref.invalidate(allFilesAccessGrantedProvider);
                },
              );
            }),
          ]),
```

- [ ] **Step 4: Run test + analyze**

Run: `flutter test test/ui/settings/all_files_access_row_test.dart`
Expected: PASS (2 tests).
Run: `flutter analyze lib/ui/settings/sections/advanced_playback_section.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/sections/advanced_playback_section.dart test/ui/settings/all_files_access_row_test.dart
git commit -m "feat(settings): All-files-access row in advanced playback"
```

---

### Task 5: Offer the permission on first delete/rename

**Files:**
- Modify: `lib/ui/home/widgets/video_options_sheet.dart` (add `maybeOfferAllFilesAccess`, call it in `onRename`/`onDelete`)
- Test: `test/ui/home/offer_all_files_access_test.dart`

**Interfaces:**
- Consumes: `allFilesAccessProvider`, `shouldOfferAllFilesAccess` (Task 1); `settingsProvider` + `offeredAllFilesAccess` (Task 2).
- Produces: `Future<void> maybeOfferAllFilesAccess(BuildContext context, WidgetRef ref)` — shows the one-time offer dialog when `shouldOfferAllFilesAccess(granted, offered)`, marks the flag, and (on accept) calls `request()`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/all_files_access_provider.dart';
import 'package:kivo_player/ui/home/widgets/video_options_sheet.dart';
import '../../fakes/fakes.dart';

Widget _host(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(body: Consumer(builder: (context, ref, _) {
          return ElevatedButton(
            onPressed: () => maybeOfferAllFilesAccess(context, ref),
            child: const Text('go'),
          );
        })),
      ),
    );

void main() {
  testWidgets('offers once when not granted and not yet offered', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final fake = FakeAllFilesAccess(granted: false);
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      allFilesAccessProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(_host(c));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Offer dialog shows; the flag is now set.
    expect(find.text('Dar acceso'), findsOneWidget);
    expect(c.read(settingsProvider).offeredAllFilesAccess, true);

    // Accept → requests access.
    await tester.tap(find.text('Dar acceso'));
    await tester.pumpAndSettle();
    expect(fake.requestCount, 1);
  });

  testWidgets('does not offer when already offered', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(offeredAllFilesAccess: true));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      allFilesAccessProvider.overrideWithValue(FakeAllFilesAccess(granted: false)),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(_host(c));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Dar acceso'), findsNothing);
  });

  testWidgets('does not offer when already granted', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      allFilesAccessProvider.overrideWithValue(FakeAllFilesAccess(granted: true)),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(_host(c));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Dar acceso'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/home/offer_all_files_access_test.dart`
Expected: FAIL — `maybeOfferAllFilesAccess` not defined.

- [ ] **Step 3: Add `maybeOfferAllFilesAccess` and call it**

In `lib/ui/home/widgets/video_options_sheet.dart`, add imports:

```dart
import '../../../core/settings/settings_provider.dart';
import '../../../platform/all_files_access_provider.dart';
import '../../../platform/interfaces/all_files_access.dart';
```

Add the top-level function:

```dart
/// One-time offer to grant All-files-access so future delete/rename skip the
/// system consent dialog. Shows at most once (persisted via
/// [KivoSettings.offeredAllFilesAccess]); on accept it opens the settings
/// screen. The caller then proceeds with the op regardless — the native side
/// decides silent-vs-consent from the current permission.
Future<void> maybeOfferAllFilesAccess(BuildContext context, WidgetRef ref) async {
  final access = ref.read(allFilesAccessProvider);
  final granted = await access.isGranted();
  final settings = ref.read(settingsProvider);
  if (!shouldOfferAllFilesAccess(granted, settings.offeredAllFilesAccess)) return;
  ref.read(settingsProvider.notifier).set(settings.copyWith(offeredAllFilesAccess: true));
  if (!context.mounted) return;
  final give = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sin confirmaciones de Android'),
      content: const Text(
          'Para borrar y renombrar sin que Android te pida confirmación cada '
          'vez, dale a Kivo acceso a los archivos.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ahora no')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dar acceso')),
      ],
    ),
  );
  if (give == true) await access.request();
}
```

Then call it inside `showVideoOptions`, in `onRename` after the rename dialog returns a name and before the controller call, and in `onDelete` after the confirm and before the controller call:

`onRename` (after `if (!context.mounted) return;` following `showRenameDialog`, before `ref.read(videoActionsProvider).rename`):

```dart
        final base = await showRenameDialog(context, v);
        if (base == null) return;
        if (!context.mounted) return;
        await maybeOfferAllFilesAccess(context, ref);
        if (!context.mounted) return;
        final r = await ref.read(videoActionsProvider).rename(v, base);
```

`onDelete` (after `if (confirmed != true) return;` + `if (!context.mounted) return;`, before `ref.read(videoActionsProvider).delete`):

```dart
        if (confirmed != true) return;
        if (!context.mounted) return;
        await maybeOfferAllFilesAccess(context, ref);
        if (!context.mounted) return;
        final status = await ref.read(videoActionsProvider).delete(v);
```

- [ ] **Step 4: Run test + analyze + full suite**

Run: `flutter test test/ui/home/offer_all_files_access_test.dart`
Expected: PASS (3 tests).
Run: `flutter analyze lib/ui/home/widgets/video_options_sheet.dart`
Expected: No issues.
Run: `flutter test`
Expected: All green.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/home/widgets/video_options_sheet.dart test/ui/home/offer_all_files_access_test.dart
git commit -m "feat(library): offer All-files-access on first delete/rename"
```

---

### Task 6: Build, install, and device verification

**Files:** none (verification only).

- [ ] **Step 1: Full suite**

Run: `flutter test`
Expected: All green (364 baseline + new tests).

- [ ] **Step 2: Release build**

Run: `flutter build apk --release`
Expected: `Built build\app\outputs\flutter-apk\app-release.apk`.

- [ ] **Step 3: Install to the Pixel 6**

Run: `& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" -s 24231FDF6006ST install -r build\app\outputs\flutter-apk\app-release.apk`
Expected: `Success`.

- [ ] **Step 4: Device checklist** (report pass/fail per item)

  - Fresh (permission NOT granted): ⋮ → Borrar → own confirm → **offer dialog appears once** ("Dar acceso" / "Ahora no"). Choosing "Ahora no" → the OS consent dialog appears (fallback) and the delete completes.
  - Do a second delete without granting → the offer dialog does NOT appear again (flag persisted); OS consent still shows.
  - Ajustes › Reproducción avanzada → "Acceso a todos los archivos" row shows "Toca para..."; tap → system "All files access" screen → enable → back → row shows "Concedido".
  - With access granted: ⋮ → Borrar → own confirm → **no OS dialog** → video gone. ⋮ → Renombrar → text dialog → **no OS dialog** → name changes.
  - Revoke access in system settings → delete/rename fall back to the OS consent flow (no crash).
  - Rename still preserves progress ("continue watching") and the file extension.

This task has no commit (verification only). Report results; a failed item becomes a fix task.

---

## Self-Review notes

- **Spec coverage:** §1 interface/impl/provider→Task 1; §2 manifest→Task 3; §3 native silent path→Task 3; §4.1 first-use offer→Task 5 (+flag Task 2); §4.2 settings row→Task 4; §5 confirm-resulting behavior→unchanged (existing delete confirm + rename dialog stay); §6 offer lives in UI→Task 5; §8 tests→each task + Task 6.
- **Type consistency:** `AllFilesAccess.isGranted/request`, `shouldOfferAllFilesAccess(bool,bool)`, `allFilesAccessProvider`, `allFilesAccessGrantedProvider`, `KivoSettings.offeredAllFilesAccess`, `maybeOfferAllFilesAccess(BuildContext,WidgetRef)`, `FakeAllFilesAccess{granted,grantOnRequest,requestCount}` — consistent across tasks.
- **Native task (3)** has no unit test by nature; gated by analyze + release build + Task 6 device checklist. The silent `if` blocks are additive inserts at the top of each existing `try`; the consent flow below is untouched (fallback intact).
- **Fallback guarantee:** the native branch runs the consent flow whenever `!Environment.isExternalStorageManager()`, so ops never break without the permission.
