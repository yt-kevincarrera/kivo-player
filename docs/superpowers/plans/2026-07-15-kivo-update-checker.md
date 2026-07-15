# Kivo In-App Update Checker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Check GitHub Releases for a newer version (auto, throttled, configurable + manual) and, when found, download the ABI-matching APK and launch Android's installer — one tap.

**Architecture:** Pure semver compare + a `UpdateChecker` (dart:io GET of the GitHub API) decide if an update exists; an `AppInstaller` platform interface (native `kivo/update` channel) reports the real app version / ABI and drives DownloadManager + the install intent. An `UpdateController` orchestrates check/throttle/skip/start. UI: an update dialog + a manual "Buscar actualizaciones" row and auto-check toggle in Settings › Acerca de, plus a throttled on-launch auto-check.

**Tech Stack:** Flutter, Riverpod, Hive, Android MethodChannel (Kotlin), Android DownloadManager + FileProvider. No new pub dependencies (dart:io for HTTP, native for install/open-url/version).

## Global Constraints

- Android-first; platform boundary pattern: interface in `lib/platform/interfaces/`, Android impl in `lib/platform/android/`, throws-until-overridden provider, overridden in `lib/main.dart`.
- **No new pub dependencies** — HTTP via `dart:io HttpClient`, version/ABI/install/open-url via the native channel.
- Single version source of truth: read `BuildConfig.VERSION_NAME` natively; remove the hardcoded `kAppVersion`.
- GitHub repo: `yt-kevincarrera/kivo-player` (public; `/releases/latest` needs no auth).
- KivoSettings pattern: every new field touches 6 points (field, ctor, defaults(), copyWith, toMap, fromMap); nullable String fields use the existing `_unset` sentinel in copyWith.
- Accent via `Theme.of(context).colorScheme.secondary`; error via `colorScheme.error`. No literal colors.
- Spanish UI copy.
- **Commit messages: NO `Co-Authored-By` trailer** (user preference).
- TDD: failing test → minimal impl → pass → commit. Frequent commits.

---

### Task 1: Pure semver comparison

**Files:**
- Create: `lib/core/update/version_compare.dart`
- Test: `test/core/update/version_compare_test.dart`

**Interfaces:**
- Produces: `int compareVersions(String a, String b)` (>0 if a newer, 0 equal, <0 older); `bool isNewer(String candidate, String current)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/update/version_compare_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/update/version_compare.dart';

void main() {
  test('equal versions compare to 0 (ignoring v prefix and +build)', () {
    expect(compareVersions('1.0.0', '1.0.0'), 0);
    expect(compareVersions('v1.0.0', '1.0.0'), 0);
    expect(compareVersions('1.0.0+5', '1.0.0+9'), 0);
  });

  test('orders by major, then minor, then patch', () {
    expect(compareVersions('1.0.1', '1.0.0') > 0, true);
    expect(compareVersions('1.1.0', '1.0.9') > 0, true);
    expect(compareVersions('2.0.0', '1.9.9') > 0, true);
    expect(compareVersions('1.0.0', '1.0.1') < 0, true);
  });

  test('missing segments are treated as 0', () {
    expect(compareVersions('1.2', '1.2.0'), 0);
    expect(compareVersions('1', '1.0.0'), 0);
    expect(compareVersions('1.3', '1.2.9') > 0, true);
  });

  test('non-numeric / garbage segments degrade to 0, never throw', () {
    expect(compareVersions('v1.0.0-beta', '1.0.0'), 0); // -beta stripped with build
    expect(() => compareVersions('', ''), returnsNormally);
    expect(compareVersions('', '1.0.0') < 0, true);
  });

  test('isNewer wraps compareVersions', () {
    expect(isNewer('1.0.1', '1.0.0'), true);
    expect(isNewer('1.0.0', '1.0.0'), false);
    expect(isNewer('0.9.9', '1.0.0'), false);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/update/version_compare_test.dart`
Expected: FAIL — `version_compare.dart` not found.

- [ ] **Step 3: Implement**

```dart
// lib/core/update/version_compare.dart

/// Compares two semver-ish strings. Returns >0 if [a] is newer than [b], 0 if
/// equal, <0 if older. Tolerant: strips a leading `v`, ignores anything from a
/// `+` or `-` onward (build/pre-release), missing segments count as 0, and
/// non-numeric segments degrade to 0 (never throws).
int compareVersions(String a, String b) {
  final pa = _parse(a);
  final pb = _parse(b);
  for (var i = 0; i < 3; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return 0;
}

bool isNewer(String candidate, String current) =>
    compareVersions(candidate, current) > 0;

List<int> _parse(String v) {
  var s = v.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  // Drop build (+...) and pre-release (-...) suffixes.
  final plus = s.indexOf('+');
  if (plus >= 0) s = s.substring(0, plus);
  final dash = s.indexOf('-');
  if (dash >= 0) s = s.substring(0, dash);
  final parts = s.split('.');
  final out = <int>[0, 0, 0];
  for (var i = 0; i < 3 && i < parts.length; i++) {
    out[i] = int.tryParse(parts[i].trim()) ?? 0;
  }
  return out;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/core/update/version_compare_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/update/version_compare.dart test/core/update/version_compare_test.dart
git commit -m "feat(update): pure semver version comparison"
```

---

### Task 2: UpdateInfo model + APK asset picker

**Files:**
- Create: `lib/core/update/update_info.dart`
- Test: `test/core/update/update_info_test.dart`

**Interfaces:**
- Produces:
  - `class UpdateInfo { final String version; final String tagName; final String? apkUrl; final String releaseUrl; final String notes; const UpdateInfo({required this.version, required this.tagName, required this.apkUrl, required this.releaseUrl, required this.notes}); }`
  - `String? pickApkAsset(List<Map<String, dynamic>> assets, String abi)` — from GitHub release `assets` (each has `name`, `browser_download_url`), returns the download URL whose name contains [abi]; else the `arm64-v8a` one; else the first `.apk`; else null.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/update/update_info_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/update/update_info.dart';

List<Map<String, dynamic>> _assets() => [
      {'name': 'kivo-1.0.1-armeabi-v7a.apk', 'browser_download_url': 'u-v7a'},
      {'name': 'kivo-1.0.1-arm64-v8a.apk', 'browser_download_url': 'u-arm64'},
      {'name': 'kivo-1.0.1-x86_64.apk', 'browser_download_url': 'u-x64'},
    ];

void main() {
  test('picks the asset matching the device ABI', () {
    expect(pickApkAsset(_assets(), 'arm64-v8a'), 'u-arm64');
    expect(pickApkAsset(_assets(), 'armeabi-v7a'), 'u-v7a');
    expect(pickApkAsset(_assets(), 'x86_64'), 'u-x64');
  });

  test('falls back to arm64-v8a for an unknown ABI', () {
    expect(pickApkAsset(_assets(), 'mips'), 'u-arm64');
  });

  test('falls back to the first .apk when no abi match', () {
    final assets = [
      {'name': 'notes.txt', 'browser_download_url': 'u-txt'},
      {'name': 'kivo-universal.apk', 'browser_download_url': 'u-apk'},
    ];
    expect(pickApkAsset(assets, 'arm64-v8a'), 'u-apk');
  });

  test('returns null when there is no apk', () {
    expect(pickApkAsset([{'name': 'x.txt', 'browser_download_url': 'u'}], 'arm64-v8a'), null);
    expect(pickApkAsset(const [], 'arm64-v8a'), null);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/update/update_info_test.dart`
Expected: FAIL — not found.

- [ ] **Step 3: Implement**

```dart
// lib/core/update/update_info.dart

/// The latest release, as parsed from GitHub.
class UpdateInfo {
  final String version;   // e.g. "1.0.1" (tag without the leading v)
  final String tagName;   // e.g. "v1.0.1"
  final String? apkUrl;   // direct download for this device's ABI, or null
  final String releaseUrl; // html_url — the release page (browser fallback)
  final String notes;     // release body/changelog
  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.apkUrl,
    required this.releaseUrl,
    required this.notes,
  });
}

/// Chooses the best APK download URL for [abi] from a GitHub release's assets.
String? pickApkAsset(List<Map<String, dynamic>> assets, String abi) {
  String? url(bool Function(String name) match) {
    for (final a in assets) {
      final name = (a['name'] as String?) ?? '';
      if (name.toLowerCase().endsWith('.apk') && match(name.toLowerCase())) {
        return a['browser_download_url'] as String?;
      }
    }
    return null;
  }

  return url((n) => n.contains(abi.toLowerCase())) ??
      url((n) => n.contains('arm64-v8a')) ??
      url((_) => true);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/core/update/update_info_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/update/update_info.dart test/core/update/update_info_test.dart
git commit -m "feat(update): UpdateInfo model + ABI-aware APK asset picker"
```

---

### Task 3: UpdateChecker interface + GitHub impl + fake

**Files:**
- Create: `lib/core/update/update_checker.dart`
- Modify: `test/fakes/fakes.dart` (append `FakeUpdateChecker`)
- Test: `test/core/update/fake_update_checker_test.dart`

**Interfaces:**
- Consumes: `UpdateInfo`, `pickApkAsset` (Task 2).
- Produces:
  - `abstract class UpdateChecker { Future<UpdateInfo?> fetchLatest(); }`
  - `class GithubUpdateChecker implements UpdateChecker { GithubUpdateChecker(this._primaryAbi); final Future<String> Function() _primaryAbi; ... }` — GETs `https://api.github.com/repos/yt-kevincarrera/kivo-player/releases/latest` via `dart:io HttpClient`, parses `tag_name`/`body`/`html_url`/`assets`, returns `UpdateInfo` or `null` on any error.
  - `class FakeUpdateChecker implements UpdateChecker { UpdateInfo? result; bool throwError = false; ... }` (in fakes.dart).

- [ ] **Step 1: Write the interface + GitHub impl**

```dart
// lib/core/update/update_checker.dart
import 'dart:convert';
import 'dart:io';
import 'update_info.dart';

abstract class UpdateChecker {
  /// Latest release, or null on network/parse error (never throws).
  Future<UpdateInfo?> fetchLatest();
}

class GithubUpdateChecker implements UpdateChecker {
  GithubUpdateChecker(this._primaryAbi);
  final Future<String> Function() _primaryAbi;

  static final Uri _endpoint = Uri.parse(
      'https://api.github.com/repos/yt-kevincarrera/kivo-player/releases/latest');

  @override
  Future<UpdateInfo?> fetchLatest() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(_endpoint);
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'kivo-player');
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String?) ?? '';
      if (tag.isEmpty) return null;
      final assets = ((json['assets'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      final abi = await _primaryAbi();
      final version = tag.startsWith('v') || tag.startsWith('V') ? tag.substring(1) : tag;
      return UpdateInfo(
        version: version,
        tagName: tag,
        apkUrl: pickApkAsset(assets, abi),
        releaseUrl: (json['html_url'] as String?) ?? '',
        notes: (json['body'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}
```

- [ ] **Step 2: Append FakeUpdateChecker to test/fakes/fakes.dart**

```dart
// test/fakes/fakes.dart — add import + class (append-only)
// import 'package:kivo_player/core/update/update_checker.dart';
// import 'package:kivo_player/core/update/update_info.dart';

class FakeUpdateChecker implements UpdateChecker {
  UpdateInfo? result;
  bool throwsNull = false; // when true, fetchLatest returns null (error path)
  int calls = 0;
  FakeUpdateChecker({this.result});

  @override
  Future<UpdateInfo?> fetchLatest() async {
    calls++;
    if (throwsNull) return null;
    return result;
  }
}
```

- [ ] **Step 3: Write the fake test**

```dart
// test/core/update/fake_update_checker_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/update/update_info.dart';
import '../../fakes/fakes.dart';

void main() {
  test('FakeUpdateChecker returns its result and counts calls', () async {
    final info = const UpdateInfo(
        version: '1.0.1', tagName: 'v1.0.1', apkUrl: 'u', releaseUrl: 'r', notes: 'n');
    final c = FakeUpdateChecker(result: info);
    expect(await c.fetchLatest(), info);
    expect(c.calls, 1);
    c.throwsNull = true;
    expect(await c.fetchLatest(), null);
  });
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/core/update/fake_update_checker_test.dart`
Expected: PASS. Then run `flutter analyze lib/core/update/update_checker.dart` → No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/core/update/update_checker.dart test/fakes/fakes.dart test/core/update/fake_update_checker_test.dart
git commit -m "feat(update): UpdateChecker interface, GitHub impl (dart:io), fake"
```

---

### Task 4: AppInstaller interface + provider + fake

**Files:**
- Create: `lib/platform/interfaces/app_installer.dart`
- Create: `lib/platform/app_installer_provider.dart`
- Modify: `test/fakes/fakes.dart` (append `FakeAppInstaller`)
- Test: `test/platform/fake_app_installer_test.dart`

**Interfaces:**
- Produces:
  - `enum InstallOutcome { started, needsPermission, failed }`
  - `abstract class AppInstaller { Future<String> appVersion(); Future<String> primaryAbi(); Future<InstallOutcome> downloadAndInstall(String url, String fileName); Future<void> openUrl(String url); }`
  - `final appInstallerProvider = Provider<AppInstaller>((ref) => throw UnimplementedError('appInstallerProvider must be overridden'));`
  - `class FakeAppInstaller implements AppInstaller` — configurable `version`, `abi`, `installOutcome`; records `installed` (url,fileName) and `openedUrls`.

- [ ] **Step 1: Write the interface + provider**

```dart
// lib/platform/interfaces/app_installer.dart

enum InstallOutcome {
  started,          // download enqueued; installer will launch on completion
  needsPermission,  // user must allow "install unknown apps" first
  failed,           // couldn't start (caller should offer the browser fallback)
}

/// Reads the running app's version/ABI and drives APK download + install.
abstract class AppInstaller {
  Future<String> appVersion();   // BuildConfig.VERSION_NAME, e.g. "1.0.0"
  Future<String> primaryAbi();   // Build.SUPPORTED_ABIS[0], e.g. "arm64-v8a"
  Future<InstallOutcome> downloadAndInstall(String url, String fileName);
  Future<void> openUrl(String url);
}
```

```dart
// lib/platform/app_installer_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/app_installer.dart';

final appInstallerProvider = Provider<AppInstaller>((ref) {
  throw UnimplementedError('appInstallerProvider must be overridden');
});
```

- [ ] **Step 2: Append FakeAppInstaller to test/fakes/fakes.dart**

```dart
// test/fakes/fakes.dart — add import + class (append-only)
// import 'package:kivo_player/platform/interfaces/app_installer.dart';

class FakeAppInstaller implements AppInstaller {
  String version;
  String abi;
  InstallOutcome installOutcome;
  final List<(String, String)> installed = [];
  final List<String> openedUrls = [];
  FakeAppInstaller({
    this.version = '1.0.0',
    this.abi = 'arm64-v8a',
    this.installOutcome = InstallOutcome.started,
  });

  @override
  Future<String> appVersion() async => version;
  @override
  Future<String> primaryAbi() async => abi;
  @override
  Future<InstallOutcome> downloadAndInstall(String url, String fileName) async {
    installed.add((url, fileName));
    return installOutcome;
  }
  @override
  Future<void> openUrl(String url) async => openedUrls.add(url);
}
```

- [ ] **Step 3: Write the fake test**

```dart
// test/platform/fake_app_installer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/app_installer.dart';
import '../fakes/fakes.dart';

void main() {
  test('FakeAppInstaller records install + open, honors outcome', () async {
    final i = FakeAppInstaller(version: '1.0.0', abi: 'arm64-v8a')
      ..installOutcome = InstallOutcome.needsPermission;
    expect(await i.appVersion(), '1.0.0');
    expect(await i.primaryAbi(), 'arm64-v8a');
    expect(await i.downloadAndInstall('u', 'kivo.apk'), InstallOutcome.needsPermission);
    expect(i.installed.single, ('u', 'kivo.apk'));
    await i.openUrl('r');
    expect(i.openedUrls.single, 'r');
  });
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/platform/fake_app_installer_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/platform/interfaces/app_installer.dart lib/platform/app_installer_provider.dart test/fakes/fakes.dart test/platform/fake_app_installer_test.dart
git commit -m "feat(update): AppInstaller interface, provider, fake"
```

---

### Task 5: KivoSettings update flags

**Files:**
- Modify: `lib/core/settings/kivo_settings.dart`
- Test: `test/core/settings/kivo_settings_update_test.dart`

**Interfaces:**
- Produces: `bool autoCheckUpdates` (default `true`), `int lastUpdateCheckMs` (default `0`), `String? skippedUpdateVersion` (default `null`).

- [ ] **Step 1: Write the failing test**

```dart
// test/core/settings/kivo_settings_update_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('update flags defaults', () {
    final d = KivoSettings.defaults();
    expect(d.autoCheckUpdates, true);
    expect(d.lastUpdateCheckMs, 0);
    expect(d.skippedUpdateVersion, null);
  });

  test('round-trips through toMap/fromMap + copyWith', () {
    final s = KivoSettings.defaults().copyWith(
      autoCheckUpdates: false,
      lastUpdateCheckMs: 123,
      skippedUpdateVersion: '1.2.3',
    );
    final back = KivoSettings.fromMap(s.toMap());
    expect(back.autoCheckUpdates, false);
    expect(back.lastUpdateCheckMs, 123);
    expect(back.skippedUpdateVersion, '1.2.3');
  });

  test('skippedUpdateVersion can be reset to null via copyWith', () {
    final s = KivoSettings.defaults().copyWith(skippedUpdateVersion: '1.2.3');
    final cleared = s.copyWith(skippedUpdateVersion: null);
    expect(cleared.skippedUpdateVersion, null);
  });

  test('legacy map (no update keys) yields defaults', () {
    final legacy = KivoSettings.defaults().toMap()
      ..remove('autoCheckUpdates')
      ..remove('lastUpdateCheckMs')
      ..remove('skippedUpdateVersion');
    final back = KivoSettings.fromMap(legacy);
    expect(back.autoCheckUpdates, true);
    expect(back.lastUpdateCheckMs, 0);
    expect(back.skippedUpdateVersion, null);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/settings/kivo_settings_update_test.dart`
Expected: FAIL — getters not defined.

- [ ] **Step 3: Add the fields** (in `lib/core/settings/kivo_settings.dart`)

1. Field declarations (after `final bool vaultUninstallWarningShown;`):
```dart
  final bool autoCheckUpdates;
  final int lastUpdateCheckMs;
  final String? skippedUpdateVersion;
```
2. Const ctor (after `required this.vaultUninstallWarningShown,`):
```dart
    required this.autoCheckUpdates,
    required this.lastUpdateCheckMs,
    required this.skippedUpdateVersion,
```
3. `defaults()` (after `vaultUninstallWarningShown: false,`):
```dart
        autoCheckUpdates: true,
        lastUpdateCheckMs: 0,
        skippedUpdateVersion: null,
```
4. `copyWith` params (after `bool? vaultUninstallWarningShown,`):
```dart
    bool? autoCheckUpdates,
    int? lastUpdateCheckMs,
    Object? skippedUpdateVersion = _unset,
```
   and body (after the `vaultUninstallWarningShown: ...` line):
```dart
      autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
      lastUpdateCheckMs: lastUpdateCheckMs ?? this.lastUpdateCheckMs,
      skippedUpdateVersion: identical(skippedUpdateVersion, _unset)
          ? this.skippedUpdateVersion
          : skippedUpdateVersion as String?,
```
5. `toMap` (after `'vaultUninstallWarningShown': vaultUninstallWarningShown,`):
```dart
        'autoCheckUpdates': autoCheckUpdates,
        'lastUpdateCheckMs': lastUpdateCheckMs,
        'skippedUpdateVersion': skippedUpdateVersion,
```
6. `fromMap` (after `vaultUninstallWarningShown: m['vaultUninstallWarningShown'] ?? d.vaultUninstallWarningShown,`):
```dart
      autoCheckUpdates: m['autoCheckUpdates'] ?? d.autoCheckUpdates,
      lastUpdateCheckMs: m['lastUpdateCheckMs'] ?? d.lastUpdateCheckMs,
      skippedUpdateVersion: m['skippedUpdateVersion'] ?? d.skippedUpdateVersion,
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/core/settings/kivo_settings_update_test.dart`
Expected: PASS. Then `flutter test` (full — settings is central) → all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/settings/kivo_settings.dart test/core/settings/kivo_settings_update_test.dart
git commit -m "feat(update): KivoSettings flags (autoCheckUpdates, lastUpdateCheckMs, skippedUpdateVersion)"
```

---

### Task 6: UpdateController + providers + throttle

**Files:**
- Create: `lib/core/update/update_providers.dart`
- Test: `test/core/update/update_controller_test.dart`

**Interfaces:**
- Consumes: `UpdateChecker`+`FakeUpdateChecker` (Task 3), `AppInstaller`+`FakeAppInstaller` (Task 4), `isNewer` (Task 1), `settingsProvider`/`SettingsNotifier` (`lib/core/settings/settings_provider.dart`), `appInstallerProvider` (Task 4).
- Produces:
  - `bool shouldAutoCheck({required bool enabled, required int nowMs, required int lastMs})` — `enabled && nowMs - lastMs >= 86400000`.
  - `enum UpdateStatus { upToDate, available, error }`
  - `class UpdateResult { final UpdateStatus status; final UpdateInfo? info; const UpdateResult(this.status, [this.info]); }`
  - `final updateCheckerProvider = Provider<UpdateChecker>((ref) => GithubUpdateChecker(() => ref.read(appInstallerProvider).primaryAbi()));`
  - `class UpdateController { UpdateController(this._ref); Future<UpdateResult> check({bool manual = false}); Future<InstallOutcome> startUpdate(UpdateInfo info); Future<void> skip(String version); Future<void> openInBrowser(UpdateInfo info); }`
  - `final updateControllerProvider = Provider<UpdateController>((ref) => UpdateController(ref));`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/update/update_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/update/update_info.dart';
import 'package:kivo_player/core/update/update_checker.dart';
import 'package:kivo_player/core/update/update_providers.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import '../../fakes/fakes.dart';

UpdateInfo _info(String v) =>
    UpdateInfo(version: v, tagName: 'v$v', apkUrl: 'u', releaseUrl: 'r', notes: 'n');

Future<ProviderContainer> _c({
  required FakeUpdateChecker checker,
  required FakeAppInstaller installer,
}) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    appInstallerProvider.overrideWithValue(installer),
    updateCheckerProvider.overrideWithValue(checker),
  ]);
}

void main() {
  test('shouldAutoCheck: enabled + >=24h', () {
    const day = 86400000;
    expect(shouldAutoCheck(enabled: true, nowMs: day, lastMs: 0), true);
    expect(shouldAutoCheck(enabled: true, nowMs: day - 1, lastMs: 0), false);
    expect(shouldAutoCheck(enabled: false, nowMs: day * 5, lastMs: 0), false);
  });

  test('check returns available when the release is newer', () async {
    final checker = FakeUpdateChecker(result: _info('1.1.0'));
    final installer = FakeAppInstaller(version: '1.0.0');
    final c = await _c(checker: checker, installer: installer);
    addTearDown(c.dispose);
    final r = await c.read(updateControllerProvider).check();
    expect(r.status, UpdateStatus.available);
    expect(r.info!.version, '1.1.0');
    // throttle timestamp persisted
    expect(c.read(settingsProvider).lastUpdateCheckMs > 0, true);
  });

  test('check returns upToDate when not newer', () async {
    final c = await _c(
      checker: FakeUpdateChecker(result: _info('1.0.0')),
      installer: FakeAppInstaller(version: '1.0.0'),
    );
    addTearDown(c.dispose);
    expect((await c.read(updateControllerProvider).check()).status, UpdateStatus.upToDate);
  });

  test('check returns error when the checker yields null', () async {
    final c = await _c(
      checker: FakeUpdateChecker()..throwsNull = true,
      installer: FakeAppInstaller(version: '1.0.0'),
    );
    addTearDown(c.dispose);
    expect((await c.read(updateControllerProvider).check()).status, UpdateStatus.error);
  });

  test('auto check suppresses a skipped version; manual does not', () async {
    final c = await _c(
      checker: FakeUpdateChecker(result: _info('1.1.0')),
      installer: FakeAppInstaller(version: '1.0.0'),
    );
    addTearDown(c.dispose);
    await c.read(updateControllerProvider).skip('1.1.0');
    expect((await c.read(updateControllerProvider).check()).status, UpdateStatus.upToDate);
    expect((await c.read(updateControllerProvider).check(manual: true)).status, UpdateStatus.available);
  });

  test('startUpdate forwards to the installer with a versioned file name', () async {
    final installer = FakeAppInstaller(version: '1.0.0');
    final c = await _c(checker: FakeUpdateChecker(), installer: installer);
    addTearDown(c.dispose);
    await c.read(updateControllerProvider).startUpdate(_info('1.1.0'));
    expect(installer.installed.single.$1, 'u');
    expect(installer.installed.single.$2, 'kivo-1.1.0.apk');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/update/update_controller_test.dart`
Expected: FAIL — `update_providers.dart` not found.

- [ ] **Step 3: Implement**

```dart
// lib/core/update/update_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings/settings_provider.dart';
import '../../platform/app_installer_provider.dart';
import '../../platform/interfaces/app_installer.dart';
import 'update_checker.dart';
import 'update_info.dart';
import 'version_compare.dart';

const _dayMs = 86400000;

/// Auto-check only when enabled and at least 24h since the last check.
bool shouldAutoCheck({required bool enabled, required int nowMs, required int lastMs}) =>
    enabled && (nowMs - lastMs) >= _dayMs;

enum UpdateStatus { upToDate, available, error }

class UpdateResult {
  final UpdateStatus status;
  final UpdateInfo? info;
  const UpdateResult(this.status, [this.info]);
}

final updateCheckerProvider = Provider<UpdateChecker>(
    (ref) => GithubUpdateChecker(() => ref.read(appInstallerProvider).primaryAbi()));

class UpdateController {
  final Ref _ref;
  UpdateController(this._ref);

  Future<UpdateResult> check({bool manual = false}) async {
    final info = await _ref.read(updateCheckerProvider).fetchLatest();
    // Record the check time regardless of outcome (throttle).
    final settings = _ref.read(settingsProvider);
    await _ref.read(settingsProvider.notifier).set(settings.copyWith(
        lastUpdateCheckMs: DateTime.now().millisecondsSinceEpoch));
    if (info == null) return const UpdateResult(UpdateStatus.error);
    final current = await _ref.read(appInstallerProvider).appVersion();
    if (!isNewer(info.version, current)) return const UpdateResult(UpdateStatus.upToDate);
    // On an automatic check, a version the user chose to skip is suppressed.
    if (!manual && info.version == _ref.read(settingsProvider).skippedUpdateVersion) {
      return const UpdateResult(UpdateStatus.upToDate);
    }
    return UpdateResult(UpdateStatus.available, info);
  }

  Future<InstallOutcome> startUpdate(UpdateInfo info) {
    return _ref.read(appInstallerProvider)
        .downloadAndInstall(info.apkUrl!, 'kivo-${info.version}.apk');
  }

  Future<void> openInBrowser(UpdateInfo info) =>
      _ref.read(appInstallerProvider).openUrl(info.releaseUrl);

  Future<void> skip(String version) async {
    final s = _ref.read(settingsProvider);
    await _ref.read(settingsProvider.notifier).set(s.copyWith(skippedUpdateVersion: version));
  }
}

final updateControllerProvider = Provider<UpdateController>((ref) => UpdateController(ref));
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/core/update/update_controller_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/update/update_providers.dart test/core/update/update_controller_test.dart
git commit -m "feat(update): UpdateController (check/throttle/skip/startUpdate) + providers"
```

---

### Task 7: Native kivo/update channel + AndroidAppInstaller + manifest + wiring

**Files:**
- Create: `lib/platform/android/android_app_installer.dart`
- Create: `android/app/src/main/res/xml/file_paths.xml`
- Modify: `android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `AppInstaller`/`InstallOutcome` (Task 4), `appInstallerProvider` (Task 4).
- Produces: `class AndroidAppInstaller implements AppInstaller` (channel `kivo/update`); `main.dart` overrides `appInstallerProvider`.

Native/wiring task — verified by `flutter analyze` + release build + on-device manual check (no unit test).

- [ ] **Step 1: Write AndroidAppInstaller**

```dart
// lib/platform/android/android_app_installer.dart
import 'package:flutter/services.dart';
import '../interfaces/app_installer.dart';

class AndroidAppInstaller implements AppInstaller {
  static const MethodChannel _channel = MethodChannel('kivo/update');

  @override
  Future<String> appVersion() async =>
      (await _channel.invokeMethod<String>('getAppVersion')) ?? '';

  @override
  Future<String> primaryAbi() async =>
      (await _channel.invokeMethod<String>('primaryAbi')) ?? 'arm64-v8a';

  @override
  Future<InstallOutcome> downloadAndInstall(String url, String fileName) async {
    try {
      final s = await _channel.invokeMethod<String>(
          'downloadAndInstall', {'url': url, 'fileName': fileName});
      return switch (s) {
        'started' => InstallOutcome.started,
        'needsPermission' => InstallOutcome.needsPermission,
        _ => InstallOutcome.failed,
      };
    } catch (_) {
      return InstallOutcome.failed;
    }
  }

  @override
  Future<void> openUrl(String url) async {
    try {
      await _channel.invokeMethod<void>('openUrl', {'url': url});
    } catch (_) {/* fire-and-forget */}
  }
}
```

- [ ] **Step 2: Add the `kivo/update` handler in MainActivity.kt**

Register alongside the other channels in `configureFlutterEngine`:

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kivo/update")
    .setMethodCallHandler { call, result ->
        when (call.method) {
            "getAppVersion" -> result.success(
                try { packageManager.getPackageInfo(packageName, 0).versionName } catch (_: Exception) { "" })
            "primaryAbi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a")
            "openUrl" -> {
                val url = call.argument<String>("url")
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                } catch (e: Exception) { result.error("OPEN_FAILED", e.message, null) }
            }
            "downloadAndInstall" -> {
                val url = call.argument<String>("url")
                val fileName = call.argument<String>("fileName") ?: "update.apk"
                if (url == null) { result.error("INVALID_ARG", "url required", null); return@setMethodCallHandler }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                    // Route the user to enable "install unknown apps" for Kivo, then they retry.
                    try {
                        startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } catch (_: Exception) {}
                    result.success("needsPermission")
                    return@setMethodCallHandler
                }
                try {
                    startApkDownload(url, fileName)
                    result.success("started")
                } catch (e: Exception) {
                    result.success("failed")
                }
            }
            else -> result.notImplemented()
        }
    }
```

- [ ] **Step 3: Add the download+install helper + receiver to MainActivity.kt**

Add these members/methods to the `MainActivity` class:

```kotlin
    private var updateDownloadId = -1L

    private val downloadReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val id = intent?.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L) ?: -1L
            if (id != updateDownloadId || id == -1L) return
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val uri = dm.getUriForDownloadedFile(id) ?: return
            val install = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            try { startActivity(install) } catch (_: Exception) {}
        }
    }

    private fun startApkDownload(url: String, fileName: String) {
        val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        // Download into app external files (no extra storage permission needed).
        val dest = File(getExternalFilesDir(null), fileName).apply { if (exists()) delete() }
        val req = DownloadManager.Request(Uri.parse(url))
            .setTitle("Kivo $fileName")
            .setMimeType("application/vnd.android.package-archive")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationUri(Uri.fromFile(dest))
        updateDownloadId = dm.enqueue(req)
    }
```

Register/unregister the receiver in `onCreate`/`onDestroy` (add to the existing overrides; create `onCreate` if absent):

```kotlin
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(downloadReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(downloadReceiver, filter)
        }
    }
```

In the existing `onDestroy` (before `super.onDestroy()` work), add:
```kotlin
        try { unregisterReceiver(downloadReceiver) } catch (_: Exception) {}
```

Add imports at the top of MainActivity.kt if missing: `import android.app.DownloadManager`.
(`Intent`, `IntentFilter`, `Context`, `Uri`, `Build`, `File`, `BroadcastReceiver` are already imported.)

- [ ] **Step 4: Manifest — permission + FileProvider**

Note: the DownloadManager path writes to `getExternalFilesDir` and installs via `dm.getUriForDownloadedFile` (a `content://downloads` URI DownloadManager grants), so a custom FileProvider is not strictly required for that path. Add the install permission; keep a FileProvider for robustness/future direct-file installs.

In `AndroidManifest.xml`, add under `<manifest>` (with the other `uses-permission`):
```xml
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```
And inside `<application>`:
```xml
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>
```

Create `android/app/src/main/res/xml/file_paths.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <external-files-path name="downloads" path="." />
</paths>
```

`androidx.core:core` is already on the classpath transitively (Flutter embedding); no gradle change needed.

- [ ] **Step 5: Wire main.dart**

Add import `import 'platform/android/android_app_installer.dart';` and `import 'platform/app_installer_provider.dart';`, and add to the `overrides:` list:
```dart
      appInstallerProvider.overrideWithValue(AndroidAppInstaller()),
```

- [ ] **Step 6: Analyze + build**

Run: `flutter analyze lib/platform/android/android_app_installer.dart lib/main.dart`
Expected: No issues.
Run: `flutter build apk --release`
Expected: `√ Built build\app\outputs\flutter-apk\app-release.apk`.

- [ ] **Step 7: Commit**

```bash
git add lib/platform/android/android_app_installer.dart lib/main.dart android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt android/app/src/main/AndroidManifest.xml android/app/src/main/res/xml/file_paths.xml
git commit -m "feat(update): native kivo/update channel (version/abi/download+install/openUrl) + wiring"
```

---

### Task 8: Update dialog

**Files:**
- Create: `lib/ui/update/update_dialog.dart`
- Test: `test/ui/update/update_dialog_test.dart`

**Interfaces:**
- Consumes: `UpdateInfo` (Task 2), `updateControllerProvider`/`InstallOutcome` (Tasks 6/4).
- Produces: `Future<void> showUpdateDialog(BuildContext context, WidgetRef ref, UpdateInfo info)` — dialog with notes + actions Descargar / Ahora no / Omitir esta versión.

- [ ] **Step 1: Write the widget**

```dart
// lib/ui/update/update_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/update/update_info.dart';
import '../../core/update/update_providers.dart';
import '../../platform/interfaces/app_installer.dart';

Future<void> showUpdateDialog(BuildContext context, WidgetRef ref, UpdateInfo info) {
  final controller = ref.read(updateControllerProvider);
  final messenger = ScaffoldMessenger.of(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text('Nueva versión ${info.version}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              info.notes.trim().isEmpty ? 'Hay una versión más reciente disponible.' : info.notes.trim(),
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () { controller.skip(info.version); Navigator.pop(ctx); },
            child: const Text('Omitir esta versión'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ahora no')),
          FilledButton(
            onPressed: info.apkUrl == null
                ? () { controller.openInBrowser(info); Navigator.pop(ctx); }
                : () async {
                    final outcome = await controller.startUpdate(info);
                    Navigator.pop(ctx);
                    switch (outcome) {
                      case InstallOutcome.started:
                        messenger.showSnackBar(const SnackBar(content: Text('Descargando actualización…')));
                      case InstallOutcome.needsPermission:
                        messenger.showSnackBar(const SnackBar(
                            content: Text('Permite instalar apps para continuar, luego reintenta.')));
                      case InstallOutcome.failed:
                        controller.openInBrowser(info);
                        messenger.showSnackBar(const SnackBar(content: Text('Abriendo la descarga en el navegador…')));
                    }
                  },
            child: const Text('Descargar'),
          ),
        ],
      );
    },
  );
}
```

- [ ] **Step 2: Write the failing test**

```dart
// test/ui/update/update_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/update/update_info.dart';
import 'package:kivo_player/core/update/update_checker.dart';
import 'package:kivo_player/core/update/update_providers.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/ui/update/update_dialog.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('Descargar triggers the installer; Omitir persists the skip', (tester) async {
    final installer = FakeAppInstaller(version: '1.0.0');
    final svc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      appInstallerProvider.overrideWithValue(installer),
      updateCheckerProvider.overrideWithValue(FakeUpdateChecker()),
    ]);
    addTearDown(c.dispose);
    const info = UpdateInfo(version: '1.1.0', tagName: 'v1.1.0', apkUrl: 'u', releaseUrl: 'r', notes: 'Novedades');

    late BuildContext dialogHostContext;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Consumer(builder: (ctx, ref, _) {
          return Scaffold(body: Builder(builder: (b) {
            dialogHostContext = b;
            return TextButton(
              onPressed: () => showUpdateDialog(b, ref, info),
              child: const Text('open'),
            );
          }));
        }),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Nueva versión 1.1.0'), findsOneWidget);
    expect(find.text('Novedades'), findsOneWidget);

    await tester.tap(find.text('Descargar'));
    await tester.pumpAndSettle();
    expect(installer.installed.single.$2, 'kivo-1.1.0.apk');
    // ignore: use_build_context_synchronously
    expect(dialogHostContext.mounted, true);
  });
}
```

- [ ] **Step 3: Run to verify it passes**

Run: `flutter test test/ui/update/update_dialog_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/update/update_dialog.dart test/ui/update/update_dialog_test.dart
git commit -m "feat(update): update dialog (download / later / skip)"
```

---

### Task 9: About section — real version, manual check, auto-check toggle

**Files:**
- Modify: `lib/ui/settings/sections/about_section.dart`
- Modify: `lib/ui/settings/settings_screen.dart`
- Test: `test/ui/settings/about_section_test.dart`

**Interfaces:**
- Consumes: `appInstallerProvider` (real version), `updateControllerProvider`+`UpdateStatus` (Task 6), `showUpdateDialog` (Task 8), `settingsProvider` (`autoCheckUpdates`), `SettingSwitch` (`lib/ui/settings/widgets/setting_tiles.dart`).
- Produces: `about_section.dart` as a `ConsumerStatefulWidget`; `kAppVersion` removed.

- [ ] **Step 1: Rewrite about_section.dart**

```dart
// lib/ui/settings/sections/about_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/update/update_providers.dart';
import '../../../platform/app_installer_provider.dart';
import '../../update/update_dialog.dart';
import '../widgets/setting_tiles.dart';

class AboutSection extends ConsumerStatefulWidget {
  const AboutSection({super.key});
  @override
  ConsumerState<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends ConsumerState<AboutSection> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final result = await ref.read(updateControllerProvider).check(manual: true);
    if (!mounted) return;
    setState(() => _checking = false);
    final messenger = ScaffoldMessenger.of(context);
    switch (result.status) {
      case UpdateStatus.available:
        showUpdateDialog(context, ref, result.info!);
      case UpdateStatus.upToDate:
        messenger.showSnackBar(const SnackBar(content: Text('Estás al día ✓')));
      case UpdateStatus.error:
        messenger.showSnackBar(const SnackBar(content: Text('No se pudo comprobar')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auto = ref.watch(settingsProvider.select((s) => s.autoCheckUpdates));
    return Scaffold(
      appBar: AppBar(title: const Text('Acerca de')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 28),
        children: [
          Center(
            child: Column(children: [
              Text('Kivo', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: cs.onSurface)),
              const SizedBox(height: 6),
              FutureBuilder<String>(
                future: ref.read(appInstallerProvider).appVersion(),
                builder: (_, snap) => Text('Versión ${snap.data ?? '…'}',
                    style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
              ),
              const SizedBox(height: 4),
              Text('Reproductor de video local', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              const SizedBox(height: 20),
              Text('Por Kevin Carrera', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(height: 2),
              SelectableText('kevin.ccdo@gmail.com', style: TextStyle(fontSize: 12.5, color: cs.secondary)),
            ]),
          ),
          const SizedBox(height: 28),
          ListTile(
            leading: _checking
                ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: cs.secondary))
                : Icon(Icons.system_update_outlined, color: cs.onSurfaceVariant),
            title: const Text('Buscar actualizaciones'),
            onTap: _checking ? null : _check,
          ),
          SettingSwitch(
            title: 'Buscar automáticamente',
            subtitle: 'Comprueba al abrir, máximo una vez al día',
            value: auto,
            onChanged: (v) => ref.read(settingsProvider.notifier)
                .set(ref.read(settingsProvider).copyWith(autoCheckUpdates: v)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Fix the settings_screen subtitle (kAppVersion removed)**

In `lib/ui/settings/settings_screen.dart:47`, replace the `subtitle: 'Versión $kAppVersion'` with a static subtitle (the real version now lives inside the About screen):
```dart
              icon: Icons.info_outline, title: 'Acerca de', subtitle: 'Versión y actualizaciones',
```
Remove any now-unused `kAppVersion` import/reference. (It was only referenced here and in about_section.)

- [ ] **Step 3: Write the widget test**

```dart
// test/ui/settings/about_section_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/update/update_checker.dart';
import 'package:kivo_player/core/update/update_providers.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/ui/settings/sections/about_section.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('shows the real version and the manual check → up to date', (tester) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      appInstallerProvider.overrideWithValue(FakeAppInstaller(version: '1.2.3')),
      updateCheckerProvider.overrideWithValue(FakeUpdateChecker()..throwsNull = false),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c, child: const MaterialApp(home: AboutSection())));
    await tester.pumpAndSettle();
    expect(find.text('Versión 1.2.3'), findsOneWidget);
    expect(find.text('Buscar actualizaciones'), findsOneWidget);
  });

  testWidgets('toggle flips autoCheckUpdates', (tester) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      appInstallerProvider.overrideWithValue(FakeAppInstaller(version: '1.0.0')),
      updateCheckerProvider.overrideWithValue(FakeUpdateChecker()),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c, child: const MaterialApp(home: AboutSection())));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).autoCheckUpdates, true);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).autoCheckUpdates, false);
  });
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ui/settings/about_section_test.dart`
Expected: PASS. Then `flutter analyze lib/ui/settings/sections/about_section.dart lib/ui/settings/settings_screen.dart` → No issues (no dangling `kAppVersion`).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/sections/about_section.dart lib/ui/settings/settings_screen.dart test/ui/settings/about_section_test.dart
git commit -m "feat(update): About shows real version + manual check + auto-check toggle"
```

---

### Task 10: On-launch auto-check

**Files:**
- Modify: `lib/app.dart`
- Test: `test/ui/app_autocheck_test.dart`

**Interfaces:**
- Consumes: `shouldAutoCheck`/`updateControllerProvider`/`UpdateStatus` (Task 6), `settingsProvider` (`autoCheckUpdates`, `lastUpdateCheckMs`), `showUpdateDialog` (Task 8).
- Produces: `KivoApp` becomes `ConsumerStatefulWidget`; runs one throttled auto-check after first frame.

- [ ] **Step 1: Convert KivoApp + add the auto-check**

Rewrite `lib/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/navigation.dart';
import 'core/settings/settings_provider.dart';
import 'core/theme/kivo_theme.dart';
import 'core/update/update_providers.dart';
import 'player/autoplay/autoplay_coordinator.dart';
import 'player/background/background_playback.dart';
import 'ui/home/home_shell.dart';
import 'ui/update/update_dialog.dart';

class KivoApp extends ConsumerStatefulWidget {
  const KivoApp({super.key});
  @override
  ConsumerState<KivoApp> createState() => _KivoAppState();
}

class _KivoAppState extends ConsumerState<KivoApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoCheck());
  }

  Future<void> _maybeAutoCheck() async {
    final s = ref.read(settingsProvider);
    if (!shouldAutoCheck(
      enabled: s.autoCheckUpdates,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      lastMs: s.lastUpdateCheckMs,
    )) return;
    final result = await ref.read(updateControllerProvider).check();
    if (result.status != UpdateStatus.available) return;
    final ctx = kivoNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    showUpdateDialog(ctx, ref, result.info!);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(backgroundPlaybackProvider);
    ref.watch(autoplayCoordinatorProvider);
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
  }
}
```

- [ ] **Step 2: Write the failing test**

```dart
// test/ui/app_autocheck_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/update/update_providers.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/core/update/update_info.dart';
import 'package:kivo_player/core/navigation.dart';
import 'package:kivo_player/ui/update/update_dialog.dart';
import '../fakes/fakes.dart';

// Minimal host that reproduces KivoApp's post-frame auto-check without the full
// widget tree (HomeShell needs many providers). Verifies the check + dialog.
void main() {
  testWidgets('auto-check shows the dialog when enabled, throttle elapsed, update available', (tester) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    // enabled by default, lastUpdateCheckMs=0 → throttle elapsed
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      appInstallerProvider.overrideWithValue(FakeAppInstaller(version: '1.0.0')),
      updateCheckerProvider.overrideWithValue(FakeUpdateChecker(
        result: const UpdateInfo(version: '1.1.0', tagName: 'v1.1.0', apkUrl: 'u', releaseUrl: 'r', notes: 'x'))),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        navigatorKey: kivoNavigatorKey,
        home: Consumer(builder: (ctx, ref, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final r = await ref.read(updateControllerProvider).check();
            final c2 = kivoNavigatorKey.currentContext;
            if (r.status == UpdateStatus.available && c2 != null) {
              showUpdateDialog(c2, ref, r.info!);
            }
          });
          return const Scaffold(body: SizedBox());
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Nueva versión 1.1.0'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run to verify it passes**

Run: `flutter test test/ui/app_autocheck_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/app.dart test/ui/app_autocheck_test.dart
git commit -m "feat(update): throttled on-launch auto-check that surfaces the update dialog"
```

---

### Task 11: Full suite, build, install, README release note

**Files:**
- Modify: `README.md` (document the release process)

- [ ] **Step 1: Full suite + analyze**

Run: `flutter test`
Expected: All tests pass.
Run: `flutter analyze`
Expected: No new issues (pre-existing deprecations in `grow_rect.dart` are acceptable).

- [ ] **Step 2: Build + install**

Run: `flutter build apk --release`
Expected: `√ Built ...app-release.apk`.
Run: `"$LOCALAPPDATA/Android/sdk/platform-tools/adb.exe" -s 24231FDF6006ST install -r build/app/outputs/flutter-apk/app-release.apk`
Expected: `Success`.

- [ ] **Step 3: Document the release process in the README**

Under the "Build from source" section's release note, expand it:
```markdown
### Releasing a new version

1. Bump `version:` in `pubspec.yaml` (e.g. `1.0.1+2`).
2. `git commit` + `git tag v1.0.1` + `git push origin master --tags`.
3. CI builds the split APKs and publishes the GitHub Release.

In-app, users on an older version get an update prompt (Settings › Acerca de →
"Buscar actualizaciones", or automatically on launch, once a day).
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document the release/versioning process"
```

- [ ] **Step 5: Device checklist (manual)**

On the Pixel 6:
1. Settings › Acerca de shows the **real** version (matches `pubspec`).
2. "Buscar actualizaciones" → with no newer release, shows "Estás al día ✓".
3. Toggle "Buscar automáticamente" persists across a restart.
4. (End-to-end) Publish a test release with a higher version → the manual check
   offers it → "Descargar" downloads (system notification) and launches the
   installer; "Omitir esta versión" suppresses the auto-prompt for that version.

---

## Notes for the executor

- No `Co-Authored-By` trailer on any commit.
- `dart:io` `HttpClient` needs no dependency and works on Android. The GitHub API
  is public for this repo; no token.
- `test/fakes/fakes.dart` is shared — APPEND `FakeUpdateChecker` and
  `FakeAppInstaller` (+ their imports); never rewrite existing fakes.
- `KivoSettings` nullable `skippedUpdateVersion` uses the existing `_unset`
  sentinel in `copyWith` (mirror `preferredSubtitleLanguage`).
- The download uses `getExternalFilesDir` + DownloadManager's own
  `getUriForDownloadedFile` content URI for the install intent, so the manifest
  FileProvider is defensive (not on the hot path) — still add it as specified.
