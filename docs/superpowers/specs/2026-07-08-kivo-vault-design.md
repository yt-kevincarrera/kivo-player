# Kivo Vault (ocultar videos) — Design

**Date:** 2026-07-08
**Status:** Approved for implementation

## Goal

Let the user hide videos in a private, auth-gated Vault. Hidden videos disappear
from Kivo's library **and** from every other app (gallery, file managers).
Access is protected by a PIN with biometric fast-unlock. The Vault entrance can
itself be hidden. Inside the Vault, videos can be removed (returned to the
gallery) or deleted permanently from the phone.

## Threat model (scope)

Casual snooping — someone picking up the unlocked phone. **Not** anti-forensics:
files are moved to app-private storage and are not encrypted. A PIN + biometric
gate and a hideable entrance satisfy this. Encryption is explicitly out of scope
(YAGNI).

## 1. Hide mechanism & persistence

Videos come from `MediaStore` (`AndroidMediaIndexer.scan`). A "soft hide" (just
filtering Kivo's list) would leave videos visible in other apps, defeating the
purpose. So hiding **physically moves the file out of MediaStore**.

- **Location:** `getExternalFilesDir(null)/vault/<mediaStoreId>.<ext>` — the app's
  private external dir. Invisible to other apps and file managers on Android 11+.
  Same storage volume as the source, so the move is a `File.renameTo` — instant,
  no byte copy, even for multi-GB videos.
- **Removing from MediaStore:** with `MANAGE_EXTERNAL_STORAGE` (all-files access,
  already implemented) the stale MediaStore row is deleted via
  `contentResolver.delete` with **no system dialog**.
- **Metadata:** once out of MediaStore its metadata is lost, so each hidden video
  is recorded as a `VaultEntry` in Hive, captured from the `VideoItem` at hide
  time. The Vault listing derives from this Hive box, never from MediaStore.
- **Unhide:** move the file back to `Movies/` (create if needed), re-insert a
  MediaStore row (`MediaStore.Video.Media` insert with `RELATIVE_PATH`), remove
  the `VaultEntry`.
- **Delete forever:** delete the private file directly (own app dir → **no
  system dialog**), remove the `VaultEntry`.

### `VaultEntry` (Hive-persisted, stored as a plain `Map`)

```
id: String                 // original MediaStore id (stable key)
privatePath: String        // absolute path inside the vault dir
displayName: String        // file name incl. extension — resume key + label
originalRelativePath: String // MediaStore RELATIVE_PATH for restore, '' if unknown
durationMs: int
sizeBytes: int
dateAddedMs: int
width: int
height: int
```

Persistence uses the existing `Map<String,dynamic>` Hive style (see
`HiveSettingsStore`), NOT generated Hive adapters — a dedicated `Box` holding one
list of maps under a single key, mirroring `resume_store` / `played` patterns.

## 2. Native ops — channel `kivo/vault`

New `MethodChannel('kivo/vault')` handled in `MainActivity` (register alongside
the existing `kivo/media` handler; may live in a helper for clarity).

- `hide({uris: List<String>}) → List<Map>`: for each content URI, resolve its
  `DATA` path + columns, `renameTo` the vault dir, delete the MediaStore row,
  return the captured metadata map (id, privatePath, displayName,
  originalRelativePath, durationMs, sizeBytes, dateAddedMs, width, height). Skips
  (omits from result) any that fail; caller reconciles.
- `unhide({paths: List<String>}) → String` (`'ok'`/`'error'`): move each private
  file back to `Movies/`, insert a MediaStore row, return aggregate status.
- `deleteForever({paths: List<String>}) → String`: delete each private file.
- `thumbnail({path: String}) → ByteArray?`: `MediaMetadataRetriever` frame at
  ~1s, JPEG — mirrors the existing `thumbnail` handler but by path.

Dart interface `VaultOps` (in `lib/platform/interfaces/vault_ops.dart`) with
`AndroidVaultOps` impl + a throws-until-overridden provider overridden in
`main.dart`, matching the platform-boundary pattern used everywhere else. A
`FakeVaultOps` (in-memory) lives in `test/fakes/fakes.dart`.

## 3. Auth — PIN + biometric

New dependency: **`local_auth: ^2.3.0`**.

- **First-run setup:** user enters a PIN twice (4–8 digits). Stored as
  `sha256(salt + pin)` + the random `salt` in Hive (a `vault_auth` box), never in
  clear. Optional toggle to enable biometric.
- **Unlock gate (`VaultGate`):** on entry, if biometric enabled, auto-invoke
  `local_auth.authenticate`. On success → unlocked. On failure/cancel/unavailable
  → show the **PIN pad** (`pin_pad.dart`). Correct PIN → unlocked. The PIN is
  always the fallback, so the user can never be locked out.
- **`VaultAuth` (pure):** `hash(pin, salt)`, `verify(pin)`, `setPin(pin)`,
  `isConfigured`. Fully unit-testable with an in-memory store.
- **Auto-lock:** the Vault re-locks when its screen is popped and when the app is
  backgrounded (`AppLifecycleState.paused/inactive`). Re-entering requires
  re-auth.

**Native requirement:** `local_auth` needs `FlutterFragmentActivity`.
`MainActivity` changes from `FlutterActivity` to `FlutterFragmentActivity`. This
is the one risky integration point — must build & smoke-test that existing
channels (media, pip, session, volume) still bind.

## 4. Entrance & hiding the entrance

- A **"Vault"** row in the Settings list (`settings_screen.dart`), with a lock
  glyph, navigating into the `VaultGate`.
- Setting `vaultEntranceHidden` (bool, default `false`) in `KivoSettings`. When
  `true`, the Settings row is not rendered.
- **Reveal gesture:** a long-press (~600ms, `HapticFeedback` on trigger) on the
  header/title area of the Videos screen opens the `VaultGate`. This gesture
  works whether or not the entrance is hidden, so the user can always get in.
- Toggle for `vaultEntranceHidden` lives **inside** the Vault (so you set it
  after you're already in), plus a hint text explaining the reveal gesture.

## 5. Vault screen & actions

- **`VaultScreen`:** same feed/grid presentation as the library, sourced from the
  `VaultEntry` list. Tap plays (queue = the vault list, in shown order; resume
  keyed by `displayName` as elsewhere). Thumbnails via `VaultOps.thumbnail`.
- **Selection:** reuse the existing long-press → multiselect model. A
  `VaultBottomBar` (thumb-reachable, mirrors `SelectionBottomBar`) with:
  - **Sacar del Vault** (unhide) → moves back to gallery, invalidates
    `mediaIndexProvider`, SnackBar.
  - **Borrar del teléfono** (delete forever) → **in-app confirmation dialog**
    (irreversible), then `deleteForever`, SnackBar. This is the ONE place a
    confirmation is kept, because the action is permanent and unrecoverable.
- The Vault uses its own selection provider (`vaultSelectionProvider`) so it does
  not entangle with `librarySelectionProvider`.

**Adding to the Vault** from the normal library:
- `SelectionBottomBar` gains a **"Mover al Vault"** action (multi-select).
- `video_options_sheet` (⋮) gains a **"Mover al Vault"** item (single).
- Both call `VaultRepository.hide(items)` → native `hide` → persist entries →
  invalidate `mediaIndexProvider`.
- **First-hide warning** (once, tracked by a `vaultUninstallWarningShown` flag):
  "Los videos del Vault viven dentro de Kivo; si desinstalas la app se pierden.
  Sácalos del Vault para devolverlos a tu galería."

## 6. State / providers

- `vaultEntriesProvider` — `AsyncNotifier<List<VaultEntry>>` backed by
  `VaultRepository`, exposes `hide`, `unhide`, `deleteForever`, `refresh`.
- `vaultAuthProvider` — exposes `VaultAuth` + an `unlocked` state notifier.
- `vaultSelectionProvider` — `StateNotifier<Set<String>>` (privatePath keys),
  mirrors `librarySelectionProvider`.
- Settings: `vaultEntranceHidden`, `vaultBiometricEnabled`,
  `vaultUninstallWarningShown` added to `KivoSettings` (+ defaults + copy).

## 7. Files

**New — Dart**
- `lib/vault/vault_entry.dart` — model + `toMap`/`fromMap`.
- `lib/vault/vault_store.dart` — Hive box wrapper (list of maps).
- `lib/vault/vault_repository.dart` — CRUD + orchestration over `VaultOps`.
- `lib/vault/vault_auth.dart` — PIN hashing/verification (pure).
- `lib/vault/vault_providers.dart` — the providers above.
- `lib/platform/interfaces/vault_ops.dart` — `VaultOps` interface.
- `lib/platform/android/android_vault_ops.dart` — channel impl.
- `lib/platform/vault_ops_provider.dart` — throws-until-overridden provider.
- `lib/ui/vault/vault_gate.dart` — auth gate (biometric + PIN fallback).
- `lib/ui/vault/pin_pad.dart` — numeric PIN entry.
- `lib/ui/vault/vault_screen.dart` — the vault feed.
- `lib/ui/vault/widgets/vault_bottom_bar.dart` — unhide / delete-forever bar.

**Modified**
- `android/.../MainActivity.kt` — `FlutterFragmentActivity` + `kivo/vault` handler.
- `lib/main.dart` — override `vaultOpsProvider`; open the vault Hive boxes.
- `lib/core/settings/kivo_settings.dart` (+ store/service) — new flags.
- `lib/ui/settings/settings_screen.dart` — conditional Vault row.
- `lib/ui/home/library_screen.dart` — long-press-header reveal gesture.
- `lib/ui/home/widgets/selection_bottom_bar.dart` — "Mover al Vault".
- `lib/ui/home/widgets/video_options_sheet.dart` — "Mover al Vault".
- `test/fakes/fakes.dart` — `FakeVaultOps`, in-memory vault/auth stores.
- `pubspec.yaml` — `local_auth`.

## 8. Testing

- **Pure/unit:** `VaultAuth` (hash determinism, salt uniqueness, verify pass/fail,
  reconfigure), `VaultRepository` (hide adds entry, unhide removes, deleteForever
  removes, dedup, reconcile on partial native failure) with `FakeVaultOps` +
  in-memory stores.
- **Entrance gating:** Settings row hidden when `vaultEntranceHidden`; long-press
  reveal always opens the gate.
- **Widget:** `VaultGate` (biometric success unlocks; failure falls to PIN; wrong
  PIN stays locked; right PIN unlocks), `VaultBottomBar` (unhide calls
  repo.unhide; delete asks confirmation then calls deleteForever).
- All new logic follows the existing fake-driven, no-real-IO test style.

## 9. Non-goals

- Encryption of vault files.
- iOS support (Android-first; `VaultOps` interface leaves room).
- Per-video passwords, decoy vaults, break-in photos.
- Recovering vault videos after app uninstall (documented warning instead).
