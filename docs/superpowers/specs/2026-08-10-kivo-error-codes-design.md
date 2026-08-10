# Kivo error codes & user-friendly failures — Design

**Date:** 2026-08-10
**Status:** Approved for implementation

## Goal

Stop showing raw exception text to the user, and give every user-visible failure
a short stable code so a user report ("me sale KV-201") is enough to identify
what broke.

## Why now

A user opened Kivo on a new device, granted storage access, and got this on the
library screen:

```
PlatformException(SCAN_FAILED, no such column relative_path (Sqlite code 1),
while compiling: SELECT _id, _display_name, ... FROM video ORDER BY date_added
DESC, (OS error - 2 No such file or directory), null, null)
```

That string is unusable for a user — and it is on screen because
`library_screen.dart` renders `'Error: $e'` directly. It was, however, exactly
what made the bug diagnosable in one read. Both facts matter, and they set the
shape of this design: **the technical text is valuable, so keep it — just stop
making it the user's problem.**

The mirror-image failure exists too. Every other failure path already shows
friendly Spanish ("No se pudo borrar", "No se pudieron borrar"), but those are
*opaque*: nothing is recorded, so a user reporting "no me deja borrar" leaves
nothing to work from. Worse, some failures are swallowed entirely — the vault's
`hide` catches per-uri exceptions and reports success with an empty list, so on a
pre-Android-10 device it would silently do nothing.

So: friendly message **plus** a code the user can quote, **plus** the raw detail
kept where it can be retrieved.

## Non-goals

Remote telemetry, a crash-reporting SDK, and i18n. The app is Spanish-only today;
messages are literal Spanish strings, same as the rest of the UI.

## 1. The failure type and the catalog

One file, `lib/core/errors/kivo_failure.dart`.

```dart
/// Every operation that can fail in a way the user sees.
enum KivoOp {
  mediaAccess, libraryScan, thumbnail,
  delete, rename, share,
  vaultHide, vaultRestore, vaultPurge,
  openVideo,
  updateCheck, updateInstall,
}

class KivoFailure implements Exception {
  const KivoFailure(this.op, this.cause);
  final KivoOp op;
  final Object cause;   // the raw PlatformException — never in `message`

  String get code;      // 'KV-201'
  String get message;   // 'No pudimos leer tu biblioteca'
  String get detail;    // technical text, for the log and "Ver detalles" only
}
```

The code identifies **the operation that failed**, not the root cause. A cause
taxonomy would have to be guessed up front and would still bottom out in a
generic bucket on every unfamiliar device; the operation is knowable, finite, and
stable. The *why* lives in `detail`, which is one tap away.

Codes are grouped by domain so they read at a glance:

| Range  | Domain          | Codes                                                        |
|--------|-----------------|--------------------------------------------------------------|
| KV-1xx | Access          | 101 `mediaAccess`                                            |
| KV-2xx | Library         | 201 `libraryScan`, 202 `thumbnail`                           |
| KV-3xx | File operations | 301 `delete`, 302 `rename`, 303 `share`                      |
| KV-4xx | Vault           | 401 `vaultHide`, 402 `vaultRestore`, 403 `vaultPurge`        |
| KV-5xx | Playback        | 501 `openVideo`                                              |
| KV-6xx | Updates         | 601 `updateCheck`, 602 `updateInstall`                        |

A single `Map<KivoOp, ({String code, String message})>` in the same file holds
code and copy together — one place to read, one place to extend. Codes are
**append-only**: a code, once shipped, keeps its meaning forever, because users
and bug reports refer to it. Retiring an operation retires its number with it.

## 2. Where translation happens

In the platform adapters, not in the UI: `android_media_indexer.dart`,
`android_media_file_ops.dart`, `android_vault_ops.dart`,
`permission_handler_media_permission.dart`, the update checker, and
`video_source.dart` / `playback_provider.dart` for `openVideo` (KV-501), whose
failures come from the media engine rather than a method channel but reach the
user the same way.

Each adapter takes an `ErrorLog` as a constructor argument, supplied where the
adapters are already constructed in `main.dart`'s `ProviderScope` overrides. No
singleton and no service locator — the log is a dependency like any other, which
is what keeps the adapters testable with a fake.

Each call catches its exception, records it, and throws `KivoFailure(op, cause)`:

```dart
Future<List<VideoItem>> scan() async {
  try {
    final raw = await _channel.invokeMethod<List<dynamic>>('scan') ?? const [];
    return raw.map(_toVideoItem).toList();
  } catch (e) {
    throw _log.record(KivoFailure(KivoOp.libraryScan, e));  // returns the failure
  }
}
```

This is the load-bearing choice in the design. With the boundary at the adapter,
the UI **cannot** receive a raw `PlatformException` — not by convention that the
next screen has to remember, but because nothing else crosses that line. And
because recording happens at the adapter rather than at a catch site in the UI,
failures with no UI watching them still get logged.

That covers the vault `hide` case, which needs stating precisely because a
partially successful batch is not a failure. The per-uri `catch` in Kotlin stays —
one unreadable file must not abort a batch of thirty. On top of that:

- Kotlin logs a warning per skipped uri instead of swallowing it.
- The Dart adapter compares the returned entry count to the uri count. If some
  are missing, it **records** a `vaultHide` entry whose `detail` names the count
  and the skipped uris, and then **returns normally** with the entries that did
  succeed. It does not throw.
- Only a total failure — zero entries returned for a non-empty request — throws
  `KivoFailure(KivoOp.vaultHide, …)` and reaches the user as KV-401.

So the log records "3 of 30 were skipped" for later, while the user sees the 27
that worked. Recording without throwing is the whole reason `record` is separate
from the throw.

`record` returning the failure keeps call sites to one line.

## 3. The error log

`lib/core/errors/error_log.dart`. A ring buffer of the last **20** failures,
newest first, persisted so a failure at startup, an ANR, or a force-close is
still readable afterwards.

Each entry stores:

```
code: String        // 'KV-201'
op: String          // enum name, for grouping
timestampMs: int
detail: String      // the raw technical text
appVersion: String
androidSdk: int
```

`appVersion` and `androidSdk` are recorded per entry, not per report — the whole
point of this exercise was not knowing the OS version of the device that failed.

Storage follows the pattern already in the project: an `ErrorLogStore` interface
with a `HiveErrorLogStore` implementation over a new `errors` box, holding one
list of maps under a single key — same shape as `HiveSettingsStore`,
`resume_store`, and `played`. No generated Hive adapters. The interface keeps the
service testable without Hive.

**The log may never break a screen.** Every write is wrapped and failures are
swallowed to `debugPrint`. A diagnostic aid that can itself throw is worse than
no diagnostic aid.

## 4. What the user sees

- `FailureView` — full-screen, replaces the `'Error: $e'` in
  `library_screen.dart`. Message large, code small and dimmed beneath it,
  "Ver detalles" below that.
- `failureSnackBar(...)` — for the existing SnackBar sites, which keep their
  current copy and gain the code plus a "Detalles" action.
- Both route to one bottom sheet: the raw `detail` in a monospace block with a
  **Copiar** button.
- Settings → Acerca de → **Registro de errores**: the entries as a list (code,
  relative time, operation), tap to expand the detail, with "Copiar todo" and
  "Borrar registro".

Placement in *Acerca de* rather than the Settings root is deliberate: it sits
next to the version number and the update check, which is the other
diagnostic-flavored corner of the app, and it keeps a developer-facing tool out
of the main settings list.

All of it uses the existing segmented dark+gold control language.

## 5. Testing

The test that keeps the system honest, first:

- **Catalog integrity** — iterate every `KivoOp` value; fail if any lacks a
  catalog entry, if any two share a code, or if any message is empty. Without
  this the catalog rots the first time someone adds an enum value in a hurry.

Then:

- **Ring buffer** — keeps at most 20, newest first, `clear()` empties, and a
  store that throws on write does not propagate.
- **Adapter mapping** — with a mocked method channel, a thrown
  `PlatformException` comes out as `KivoFailure` with the right `op`, and the
  entry lands in the log.
- **`FailureView` widget** — renders message and code, and does **not** render
  the raw detail until "Ver detalles" is tapped.

## Open follow-up (not part of this work)

`android_media_file_ops.dart` returns string statuses (`'ok'` / `'error'`) rather
than throwing, so its failures carry no cause to record. Wrapping it in
`KivoFailure` will give `KV-301`/`KV-302` a code but an empty `detail` until the
Kotlin side returns a reason. Worth doing later; called out here so the gap is
not mistaken for a bug in this design.
