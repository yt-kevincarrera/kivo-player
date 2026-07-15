# Kivo In-App Update Checker — Design

**Date:** 2026-07-15
**Status:** Approved for implementation

## Goal

Let Kivo check GitHub Releases for a newer version and, when found, download the
matching APK and launch Android's installer — with a one-tap flow. Checking is
automatic (configurable, throttled) and also available manually. Establish a
real semantic-versioning policy so "the version" is a single source of truth.

## 1. Versioning policy (the foundation)

- **Single source of truth:** the hardcoded `kAppVersion = '1.0'` const is
  removed. The app reads its real version from Android `BuildConfig.VERSION_NAME`
  (which Gradle derives from `pubspec.yaml` `version:`), via a native call. The
  About screen and update comparison both use this.
- **Scheme:** `pubspec.yaml` `version: X.Y.Z+B` (semver + build number). Git tag
  `vX.Y.Z`. The existing CI workflow publishes a Release on tag push.
- **Release process:** bump `pubspec` `version:` → `git tag vX.Y.Z` → push tag →
  CI builds split APKs and publishes the Release. Documented in the README.

## 2. Update check (Dart, testable)

- `UpdateInfo` model: `{ String version; String tagName; String? apkUrl;
  String releaseUrl; String notes; }`.
- `compareVersions(a, b) → int` — **pure** semver comparison (major.minor.patch,
  ignores any `+build` suffix and a leading `v`). `isNewer(latest, current)`
  wraps it. Fully unit-tested (equal, patch/minor/major bumps, `v` prefix,
  differing segment counts, non-numeric guards).
- `UpdateChecker` interface: `Future<UpdateInfo?> fetchLatest()` — returns the
  latest release parsed from GitHub, or `null` on network/parse error (never
  throws to the UI).
- `GithubUpdateChecker` impl: GET
  `https://api.github.com/repos/yt-kevincarrera/kivo-player/releases/latest`
  using `dart:io` `HttpClient` (**no new dependency**), header
  `Accept: application/vnd.github+json`. Parses `tag_name`, `body` (notes),
  `html_url` (releaseUrl), and picks the `assets[].browser_download_url` whose
  name contains the device's primary ABI (from native `primaryAbi`), falling
  back to the `arm64-v8a` asset, then any `.apk`.
- The comparison (is the release newer than the running version?) happens in the
  orchestration layer, not the checker, so both are independently testable.

## 3. Download + install (native, `kivo/update` channel)

- `AppInstaller` interface (`lib/platform/interfaces/app_installer.dart`):
  - `Future<String> appVersion()` — `BuildConfig.VERSION_NAME`.
  - `Future<String> primaryAbi()` — `Build.SUPPORTED_ABIS[0]`.
  - `Future<InstallStart> downloadAndInstall(String url, String fileName)` —
    enqueues Android **DownloadManager** (system progress notification, resumable)
    to app external-cache, and on completion fires the install `Intent`
    (`ACTION_VIEW`, mime `application/vnd.android.package-archive`, via a
    **FileProvider** URI + `FLAG_GRANT_READ_URI_PERMISSION`). Returns whether the
    download was started, or a reason it couldn't (see below).
- **Install permission:** needs `REQUEST_INSTALL_PACKAGES`. Before downloading,
  check `packageManager.canRequestPackageInstalls()`; if false, return a
  `needsPermission` result so the UI can route the user to the
  `ACTION_MANAGE_UNKNOWN_APP_SOURCES` settings screen for Kivo, then retry.
- **Fallback:** if DownloadManager/install fails for any reason, the UI offers
  "Abrir en el navegador" → opens `releaseUrl` (via an `ACTION_VIEW` intent on
  the native side — no `url_launcher` dependency).
- Android impl `AndroidAppInstaller` + throws-until-overridden provider, matching
  the platform-boundary pattern; `FakeAppInstaller` in tests.

Manifest additions: `<uses-permission REQUEST_INSTALL_PACKAGES>` and a
`FileProvider` (`androidx.core.content.FileProvider`) with a cache-path
`file_paths.xml` for the downloaded APK.

## 4. Configuration (`KivoSettings`, 6-point pattern)

- `autoCheckUpdates` (bool, default **true**).
- `lastUpdateCheckMs` (int, default 0) — for the 24h throttle.
- `skippedUpdateVersion` (String?, default null) — "omitir esta versión" so a
  declined update doesn't nag again until a newer one appears.

## 5. Orchestration & UI

- `UpdateController` (provider) with:
  - `shouldAutoCheck(nowMs, lastMs, enabled) → bool` — **pure**, true when
    enabled and ≥24h since last check. Unit-tested.
  - `check({bool manual})` — runs `fetchLatest`, compares to `appVersion()`,
    updates `lastUpdateCheckMs`, and returns an `UpdateResult`
    (`upToDate` / `available(UpdateInfo)` / `error`). For an auto-check, a
    result whose version equals `skippedUpdateVersion` is suppressed.
  - `startUpdate(UpdateInfo)` — calls `AppInstaller.downloadAndInstall`, handles
    the `needsPermission` and fallback branches.
  - `skip(version)` — persists `skippedUpdateVersion`.
- **Auto (on launch):** `KivoApp` triggers `check(manual:false)` once after
  startup if `shouldAutoCheck`; on `available` and not skipped, shows the update
  dialog. Silent on `upToDate`/`error`.
- **Manual:** `about_section.dart` becomes a `ConsumerWidget` showing the real
  version, a **"Buscar actualizaciones"** row (spinner while checking → dialog on
  `available`, "Estás al día ✓" on `upToDate`, "No se pudo comprobar" on
  `error`), and a **switch** for `autoCheckUpdates`.
- **Update dialog** (`lib/ui/update/update_dialog.dart`): title "Nueva versión
  X.Y.Z", scrollable release notes, actions **[Descargar]** ·
  [Ahora no] · [Omitir esta versión]. Accent via `colorScheme.secondary`.
  "Descargar" → `startUpdate`; while downloading, a short "Descargando…" state
  (DownloadManager shows the system progress); on `needsPermission`, a prompt to
  enable unknown-sources then retry.

## 6. Testing

- **Pure:** `compareVersions` (broad case table), `shouldAutoCheck` (enabled/off,
  <24h/≥24h), the ABI→asset selection, and the "suppress skipped version" logic.
- **UpdateChecker:** a `FakeUpdateChecker` returning available / up-to-date /
  error; `UpdateController.check` behavior for each, plus the throttle write.
- **Settings:** the three new flags round-trip (defaults, copyWith, toMap,
  fromMap, legacy-map).
- **UI:** About section shows the real version and the toggle; the manual-check
  row transitions checking → result; the update dialog's three actions call the
  right controller methods (`FakeAppInstaller`).

## 7. Files

**New**
- `lib/core/update/update_info.dart` — model.
- `lib/core/update/version_compare.dart` — pure semver compare.
- `lib/core/update/update_checker.dart` — interface + `GithubUpdateChecker`.
- `lib/core/update/update_providers.dart` — `UpdateController`, providers,
  `shouldAutoCheck`.
- `lib/platform/interfaces/app_installer.dart` — interface + `InstallStart`.
- `lib/platform/android/android_app_installer.dart` — channel impl.
- `lib/platform/app_installer_provider.dart` — throws-until-overridden provider.
- `lib/ui/update/update_dialog.dart` — the dialog + download state.

**Modified**
- `lib/core/settings/kivo_settings.dart` (+ the 3 flags).
- `lib/ui/settings/sections/about_section.dart` (real version, manual check,
  toggle; remove `kAppVersion`).
- `lib/ui/settings/settings_screen.dart` (the `Versión $kAppVersion` subtitle now
  reads the real version).
- `lib/app.dart` / `KivoApp` (trigger the throttled auto-check on launch).
- `android/.../MainActivity.kt` (`kivo/update`: `getAppVersion`, `primaryAbi`,
  `downloadAndInstall`, `openUrl`).
- `android/app/src/main/AndroidManifest.xml` (`REQUEST_INSTALL_PACKAGES`,
  FileProvider) + `res/xml/file_paths.xml`.
- `lib/main.dart` (override `appInstallerProvider`).
- `test/fakes/fakes.dart` (`FakeAppInstaller`, `FakeUpdateChecker`).

## 8. Non-goals

- iOS (Android-first; interfaces leave room).
- Delta/partial updates or auto-install without user consent (Android requires
  the user to confirm every APK install).
- A dependency on `http`/`url_launcher`/`package_info_plus` — all avoided via
  `dart:io` + the native channel.
- Background/scheduled checks while the app is closed (only on-launch + manual).
