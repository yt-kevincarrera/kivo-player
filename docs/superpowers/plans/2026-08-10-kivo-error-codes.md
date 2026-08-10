# Kivo Error Codes & User-Friendly Failures — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every raw exception the user can see with a friendly Spanish message plus a short stable code (KV-201 etc.), and keep the technical detail in a persisted 20-entry log so a reported code can be traced back to its cause.

**Architecture:** A `KivoFailure` type carries an operation enum; a single catalog maps each operation to its code and copy. Translation happens in the platform adapters, so the UI cannot receive a raw `PlatformException` by construction. An `ErrorLog` service (Hive-backed ring buffer) records every failure at the adapter boundary — including ones no UI is watching. Two widgets (`FailureView`, `failureSnackBar`) render message + code with the raw detail one tap away, and a Settings screen lists the log.

**Tech Stack:** Flutter 3.41, Riverpod (Notifier/Provider), Hive (plain `Map` boxes, no generated adapters), `flutter_test`.

**Spec:** [docs/superpowers/specs/2026-08-10-kivo-error-codes-design.md](../specs/2026-08-10-kivo-error-codes-design.md)

## Global Constraints

- **Codes are append-only.** A shipped code keeps its meaning forever; never renumber or reuse. Retiring an operation retires its number.
- **All user-facing copy is literal Spanish strings.** No i18n layer — match the existing UI (`'No se pudo borrar'`, `'Estás al día ✓'`).
- **The error log may never break a screen.** Every store write is wrapped; failures go to `debugPrint` and are swallowed.
- **No new dependencies.** No telemetry SDK, no crash reporter, no `device_info_plus`.
- **Hive stores use the plain-`Map` pattern** — an abstract store + `Hive…Store` impl over a `Box`, one list of maps under a single key. Mirror `HivePlayedStore` (`lib/player/library/played.dart`) and `HiveSettingsStore`. No generated Hive adapters.
- **Adapters receive `ErrorLog` by constructor**, supplied in `main.dart`'s `ProviderScope` overrides. No singleton, no service locator.
- **`KivoFailure.toString()` must never include the raw cause** — a stray `'$e'` anywhere must not be able to leak technical text.
- Run tests with `flutter test`. Analyze with `flutter analyze` (the repo is warning-clean; keep it that way).

---

### Task 1: The failure type and the code catalog

**Files:**
- Create: `lib/core/errors/kivo_failure.dart`
- Test: `test/core/errors/kivo_failure_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum KivoOp` (values listed below), `const kivoErrorCatalog` of type `Map<KivoOp, ({String code, String message})>`, and `class KivoFailure implements Exception` with `KivoFailure(KivoOp op, Object cause)`, getters `String code`, `String message`, `String detail`. Every later task depends on these exact names.

- [ ] **Step 1: Write the failing test**

Create `test/core/errors/kivo_failure_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';

void main() {
  test('every KivoOp has a catalog entry', () {
    for (final op in KivoOp.values) {
      final entry = kivoErrorCatalog[op];
      expect(entry, isNotNull, reason: 'KivoOp.${op.name} has no catalog entry');
      expect(entry!.code, isNotEmpty, reason: 'KivoOp.${op.name} has an empty code');
      expect(entry.message, isNotEmpty, reason: 'KivoOp.${op.name} has an empty message');
    }
  });

  test('codes are unique across the catalog', () {
    final seen = <String, KivoOp>{};
    for (final op in KivoOp.values) {
      final code = kivoErrorCatalog[op]!.code;
      expect(seen.containsKey(code), isFalse,
          reason: 'code $code is used by both ${seen[code]?.name} and ${op.name}');
      seen[code] = op;
    }
  });

  test('codes follow the KV-nnn format', () {
    final pattern = RegExp(r'^KV-\d{3}$');
    for (final op in KivoOp.values) {
      expect(pattern.hasMatch(kivoErrorCatalog[op]!.code), isTrue,
          reason: '${kivoErrorCatalog[op]!.code} is not KV-nnn');
    }
  });

  test('exposes the code, the message and the raw detail', () {
    final f = KivoFailure(KivoOp.libraryScan, 'no such column relative_path');
    expect(f.code, 'KV-201');
    expect(f.message, 'No pudimos leer tu biblioteca');
    expect(f.detail, contains('relative_path'));
  });

  test('toString never leaks the raw cause', () {
    final f = KivoFailure(KivoOp.libraryScan, 'no such column relative_path');
    expect(f.toString(), isNot(contains('relative_path')));
    expect(f.toString(), contains('KV-201'));
  });
}
```

The last test is the one that matters most: the original bug reached the user because a screen interpolated `'$e'`. Making `toString()` safe means that mistake can't leak again even if someone repeats it.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/errors/kivo_failure_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'kivo_player' … kivo_failure.dart` / target of URI doesn't exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/core/errors/kivo_failure.dart`:

```dart
/// Every operation that can fail in a way the user sees.
///
/// Adding a value here without adding a catalog entry below fails
/// `kivo_failure_test.dart` — that is deliberate.
enum KivoOp {
  mediaAccess,
  libraryScan,
  thumbnail,
  delete,
  rename,
  share,
  vaultHide,
  vaultRestore,
  vaultPurge,
  openVideo,
  updateCheck,
  updateInstall,
}

/// Code and copy for each operation, grouped by domain:
/// 1xx access · 2xx library · 3xx file ops · 4xx vault · 5xx playback · 6xx updates
///
/// Codes are APPEND-ONLY. Users quote them and bug reports refer to them, so a
/// shipped code keeps its meaning forever — never renumber, never reuse.
const kivoErrorCatalog = <KivoOp, ({String code, String message})>{
  KivoOp.mediaAccess:
      (code: 'KV-101', message: 'No pudimos acceder a tus videos'),
  KivoOp.libraryScan:
      (code: 'KV-201', message: 'No pudimos leer tu biblioteca'),
  KivoOp.thumbnail:
      (code: 'KV-202', message: 'No pudimos generar la miniatura'),
  KivoOp.delete: (code: 'KV-301', message: 'No pudimos borrar el video'),
  KivoOp.rename: (code: 'KV-302', message: 'No pudimos renombrar el video'),
  KivoOp.share: (code: 'KV-303', message: 'No pudimos compartir el video'),
  KivoOp.vaultHide: (code: 'KV-401', message: 'No pudimos ocultar el video'),
  KivoOp.vaultRestore:
      (code: 'KV-402', message: 'No pudimos restaurar el video'),
  KivoOp.vaultPurge:
      (code: 'KV-403', message: 'No pudimos borrar el video definitivamente'),
  KivoOp.openVideo: (code: 'KV-501', message: 'No pudimos abrir el video'),
  KivoOp.updateCheck:
      (code: 'KV-601', message: 'No pudimos comprobar si hay actualizaciones'),
  KivoOp.updateInstall:
      (code: 'KV-602', message: 'No pudimos instalar la actualización'),
};

/// A failure the user is allowed to see: a friendly [message], a quotable
/// [code], and the technical [detail] kept separate so it only shows where it
/// was asked for.
class KivoFailure implements Exception {
  const KivoFailure(this.op, this.cause);

  final KivoOp op;

  /// The original exception (or a descriptive string). Never rendered by
  /// [toString] — only reachable through [detail].
  final Object cause;

  String get code => kivoErrorCatalog[op]!.code;
  String get message => kivoErrorCatalog[op]!.message;
  String get detail => cause.toString();

  /// Deliberately omits [cause]. A screen that interpolates `'$failure'` — the
  /// exact mistake that put a SQLite error in front of a user — gets the
  /// friendly text, not the stack.
  @override
  String toString() => '$code $message';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/errors/kivo_failure_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/core/errors/kivo_failure.dart test/core/errors/kivo_failure_test.dart
git commit -m "feat(errors): KivoFailure type and the KV-nnn code catalog"
```

---

### Task 2: The error log

**Files:**
- Create: `lib/core/errors/error_log.dart`
- Modify: `test/fakes/fakes.dart` (append two fakes)
- Test: `test/core/errors/error_log_test.dart`

**Interfaces:**
- Consumes: `KivoFailure`, `KivoOp` from Task 1.
- Produces:
  - `class ErrorLogEntry` with fields `String code, op, detail, appVersion`, `int timestampMs, androidSdk`, plus `Map<String, dynamic> toMap()` and `factory ErrorLogEntry.fromMap(Map<String, dynamic>)`.
  - `abstract class ErrorLogStore { List<Map<String, dynamic>> read(); Future<void> write(List<Map<String, dynamic>> entries); }`
  - `class HiveErrorLogStore implements ErrorLogStore` with `HiveErrorLogStore(Box box)`.
  - `class ErrorLog` with `ErrorLog(ErrorLogStore store, {required String appVersion, required int androidSdk, DateTime Function()? now})`, `static const int maxEntries = 20`, `KivoFailure record(KivoFailure failure)`, `List<ErrorLogEntry> entries()`, `Future<void> clear()`.
- Test fakes produced: `InMemoryErrorLogStore`, `ThrowingErrorLogStore` in `test/fakes/fakes.dart`.

`record` returns the failure it was given so call sites stay one line: `throw _log.record(KivoFailure(op, e));`. Calling `record` **without** throwing is how a partially-successful batch is logged (Task 5).

The `now` injection keeps the timestamp test deterministic.

- [ ] **Step 1: Write the failing test**

Append to `test/fakes/fakes.dart` (add `import 'package:kivo_player/core/errors/error_log.dart';` at the top with the other imports):

```dart
class InMemoryErrorLogStore implements ErrorLogStore {
  List<Map<String, dynamic>> data = [];
  int writeCount = 0;
  @override
  List<Map<String, dynamic>> read() => data;
  @override
  Future<void> write(List<Map<String, dynamic>> entries) async {
    writeCount++;
    data = entries;
  }
}

class ThrowingErrorLogStore implements ErrorLogStore {
  @override
  List<Map<String, dynamic>> read() => throw StateError('read boom');
  @override
  Future<void> write(List<Map<String, dynamic>> entries) async =>
      throw StateError('write boom');
}
```

Create `test/core/errors/error_log_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import '../../fakes/fakes.dart';

ErrorLog _log(ErrorLogStore store, {DateTime Function()? now}) =>
    ErrorLog(store, appVersion: '1.1.0', androidSdk: 28, now: now);

void main() {
  test('record stores code, op, detail and device context', () {
    final store = InMemoryErrorLogStore();
    final log = _log(store, now: () => DateTime.fromMillisecondsSinceEpoch(1000));

    log.record(const KivoFailure(KivoOp.libraryScan, 'no such column relative_path'));

    final entries = log.entries();
    expect(entries, hasLength(1));
    expect(entries.first.code, 'KV-201');
    expect(entries.first.op, 'libraryScan');
    expect(entries.first.detail, contains('relative_path'));
    expect(entries.first.appVersion, '1.1.0');
    expect(entries.first.androidSdk, 28);
    expect(entries.first.timestampMs, 1000);
  });

  test('record returns the failure so call sites can throw it', () {
    const failure = KivoFailure(KivoOp.delete, 'nope');
    expect(_log(InMemoryErrorLogStore()).record(failure), same(failure));
  });

  test('entries come back newest first', () {
    final log = _log(InMemoryErrorLogStore());
    log.record(const KivoFailure(KivoOp.libraryScan, 'first'));
    log.record(const KivoFailure(KivoOp.delete, 'second'));

    expect(log.entries().map((e) => e.detail).toList(), ['second', 'first']);
  });

  test('keeps only the last maxEntries failures', () {
    final log = _log(InMemoryErrorLogStore());
    for (var i = 0; i < ErrorLog.maxEntries + 5; i++) {
      log.record(KivoFailure(KivoOp.libraryScan, 'failure $i'));
    }

    final entries = log.entries();
    expect(entries, hasLength(ErrorLog.maxEntries));
    expect(entries.first.detail, 'failure ${ErrorLog.maxEntries + 4}');
    expect(entries.last.detail, 'failure 5');
  });

  test('survives a round trip through the store', () {
    final store = InMemoryErrorLogStore();
    _log(store).record(const KivoFailure(KivoOp.vaultHide, 'boom'));

    expect(_log(store).entries().single.code, 'KV-401');
  });

  test('clear empties the log', () async {
    final log = _log(InMemoryErrorLogStore());
    log.record(const KivoFailure(KivoOp.share, 'boom'));

    await log.clear();

    expect(log.entries(), isEmpty);
  });

  test('a store that throws never propagates', () {
    final log = _log(ThrowingErrorLogStore());

    expect(() => log.record(const KivoFailure(KivoOp.rename, 'boom')), returnsNormally);
    expect(() => log.entries(), returnsNormally);
    expect(log.entries(), isEmpty);
    expect(log.clear, returnsNormally);
  });
}
```

The last test is load-bearing: a diagnostic aid that can throw is worse than none.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/errors/error_log_test.dart`
Expected: FAIL — target of URI doesn't exist for `core/errors/error_log.dart`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/core/errors/error_log.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'kivo_failure.dart';

/// One recorded failure, with the device context that makes it diagnosable.
class ErrorLogEntry {
  const ErrorLogEntry({
    required this.code,
    required this.op,
    required this.timestampMs,
    required this.detail,
    required this.appVersion,
    required this.androidSdk,
  });

  final String code;
  final String op;
  final int timestampMs;
  final String detail;
  final String appVersion;
  final int androidSdk;

  Map<String, dynamic> toMap() => {
        'code': code,
        'op': op,
        'timestampMs': timestampMs,
        'detail': detail,
        'appVersion': appVersion,
        'androidSdk': androidSdk,
      };

  factory ErrorLogEntry.fromMap(Map<String, dynamic> m) => ErrorLogEntry(
        code: (m['code'] as String?) ?? '',
        op: (m['op'] as String?) ?? '',
        timestampMs: (m['timestampMs'] as num?)?.toInt() ?? 0,
        detail: (m['detail'] as String?) ?? '',
        appVersion: (m['appVersion'] as String?) ?? '',
        androidSdk: (m['androidSdk'] as num?)?.toInt() ?? 0,
      );
}

abstract class ErrorLogStore {
  List<Map<String, dynamic>> read();
  Future<void> write(List<Map<String, dynamic>> entries);
}

/// One list of maps under a single key — same shape as the settings and
/// resume boxes, no generated adapters.
class HiveErrorLogStore implements ErrorLogStore {
  HiveErrorLogStore(this.box);
  final Box box;
  static const _key = 'entries';

  @override
  List<Map<String, dynamic>> read() {
    final raw = box.get(_key);
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
  }

  @override
  Future<void> write(List<Map<String, dynamic>> entries) =>
      box.put(_key, entries);
}

/// A ring buffer of the last [maxEntries] failures, newest first.
///
/// Every store access is wrapped: this is a diagnostic aid, and one that can
/// throw would be worse than none at all.
class ErrorLog {
  ErrorLog(
    this._store, {
    required this.appVersion,
    required this.androidSdk,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const int maxEntries = 20;

  final ErrorLogStore _store;
  final String appVersion;
  final int androidSdk;
  final DateTime Function() _now;

  /// Records [failure] and returns it, so a call site reads
  /// `throw _log.record(KivoFailure(op, e));`. Call it without throwing to
  /// note something that is not fatal to the operation.
  KivoFailure record(KivoFailure failure) {
    try {
      final entry = ErrorLogEntry(
        code: failure.code,
        op: failure.op.name,
        timestampMs: _now().millisecondsSinceEpoch,
        detail: failure.detail,
        appVersion: appVersion,
        androidSdk: androidSdk,
      );
      final next = [entry.toMap(), ..._read()];
      _store.write(next.take(maxEntries).toList());
    } catch (e) {
      debugPrint('ErrorLog.record failed: $e');
    }
    return failure;
  }

  List<ErrorLogEntry> entries() =>
      _read().map(ErrorLogEntry.fromMap).toList();

  Future<void> clear() async {
    try {
      await _store.write([]);
    } catch (e) {
      debugPrint('ErrorLog.clear failed: $e');
    }
  }

  List<Map<String, dynamic>> _read() {
    try {
      return _store.read();
    } catch (e) {
      debugPrint('ErrorLog.read failed: $e');
      return [];
    }
  }
}
```

Note `_store.write` is not awaited inside `record` — recording must never make a
failing operation slower to report, and the Hive box write is already ordered.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/errors/error_log_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/core/errors/error_log.dart test/core/errors/error_log_test.dart test/fakes/fakes.dart
git commit -m "feat(errors): persisted 20-entry error log"
```

---

### Task 3: Wire the log into the app

**Files:**
- Create: `lib/core/errors/error_log_provider.dart`
- Modify: `lib/main.dart:42-80` (open the box, build `ErrorLog`, add the override)
- Modify: `lib/platform/interfaces/app_installer.dart` (add `androidSdk()`)
- Modify: `lib/platform/android/android_app_installer.dart` (implement it)
- Modify: `android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt:798` (add the `androidSdk` method)
- Modify: `test/fakes/fakes.dart` (`FakeAppInstaller` gains `androidSdk`)
- Test: `test/core/errors/error_log_provider_test.dart`

**Interfaces:**
- Consumes: `ErrorLog` from Task 2.
- Produces: `final errorLogProvider = Provider<ErrorLog>(…)` (throws `UnimplementedError` until overridden, matching every other platform provider in this codebase), and `Future<int> androidSdk()` on `AppInstaller`.

Recording the OS version per entry is the whole point: the failure that started
this work was impossible to place because nobody knew the device's Android
version. `AppInstaller` already owns `appVersion()` and `primaryAbi()` on the
`kivo/update` channel, so `androidSdk()` belongs there rather than in a new
device-info dependency.

- [ ] **Step 1: Write the failing test**

Create `test/core/errors/error_log_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/error_log_provider.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import '../../fakes/fakes.dart';

void main() {
  test('errorLogProvider must be overridden', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(() => container.read(errorLogProvider), throwsUnimplementedError);
  });

  test('an overridden log records through the provider', () {
    final store = InMemoryErrorLogStore();
    final container = ProviderContainer(overrides: [
      errorLogProvider.overrideWithValue(
          ErrorLog(store, appVersion: '1.1.0', androidSdk: 28)),
    ]);
    addTearDown(container.dispose);

    container
        .read(errorLogProvider)
        .record(const KivoFailure(KivoOp.libraryScan, 'boom'));

    expect(container.read(errorLogProvider).entries().single.code, 'KV-201');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/errors/error_log_provider_test.dart`
Expected: FAIL — target of URI doesn't exist for `core/errors/error_log_provider.dart`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/core/errors/error_log_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'error_log.dart';

final errorLogProvider = Provider<ErrorLog>((ref) {
  throw UnimplementedError('errorLogProvider must be overridden');
});
```

In `lib/platform/interfaces/app_installer.dart`, add to the `AppInstaller` abstract class:

```dart
  /// The device's Android API level — recorded with every logged failure.
  Future<int> androidSdk();
```

In `lib/platform/android/android_app_installer.dart`, add:

```dart
  @override
  Future<int> androidSdk() async {
    try {
      return (await _channel.invokeMethod<int>('androidSdk')) ?? 0;
    } catch (_) {
      return 0;
    }
  }
```

In `MainActivity.kt`, in the `kivo/update` handler right after the `primaryAbi`
line (currently line 798):

```kotlin
                    "androidSdk" -> result.success(Build.VERSION.SDK_INT)
```

In `test/fakes/fakes.dart`, add to `FakeAppInstaller`:

```dart
  int sdk = 34;
  @override
  Future<int> androidSdk() async => sdk;
```

In `lib/main.dart`, inside `main()` after the existing `Hive.openBox` calls:

```dart
  final errorsBox = await Hive.openBox('errors');
  final installer = AndroidAppInstaller();
  final errorLog = ErrorLog(
    HiveErrorLogStore(errorsBox),
    appVersion: await installer.appVersion(),
    androidSdk: await installer.androidSdk(),
  );
```

Then add to the `overrides` list:

```dart
      errorLogProvider.overrideWithValue(errorLog),
```

and reuse the same instance for the existing installer override — replace
`appInstallerProvider.overrideWithValue(AndroidAppInstaller())` with
`appInstallerProvider.overrideWithValue(installer)` so the app constructs one,
not two. Add the imports for `core/errors/error_log.dart` and
`core/errors/error_log_provider.dart`.

- [ ] **Step 4: Run the full suite**

Run: `flutter test`
Expected: PASS. Adding `androidSdk()` to the `AppInstaller` interface breaks any
other implementer — if a test fake beyond `FakeAppInstaller` implements
`AppInstaller`, give it the same two lines.

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/core/errors/error_log_provider.dart lib/main.dart lib/platform/interfaces/app_installer.dart lib/platform/android/android_app_installer.dart android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt test/fakes/fakes.dart test/core/errors/error_log_provider_test.dart
git commit -m "feat(errors): wire the error log into the app with device context"
```

---

### Task 4: Translate library failures (KV-201, KV-202)

**Files:**
- Modify: `lib/platform/android/android_media_indexer.dart`
- Modify: `lib/main.dart` (pass the log to the adapter)
- Test: `test/platform/android_media_indexer_failure_test.dart`

**Interfaces:**
- Consumes: `KivoFailure`, `KivoOp`, `ErrorLog`.
- Produces: `AndroidMediaIndexer(ErrorLog log)` — the constructor gains a required positional argument. `scan()` throws `KivoFailure(KivoOp.libraryScan, cause)`; `thumbnail(id)` records `KivoOp.thumbnail` and returns `null` rather than throwing (a missing thumbnail must not take down a grid of 200 tiles).

- [ ] **Step 1: Write the failing test**

Create `test/platform/android_media_indexer_failure_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/platform/android/android_media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import '../fakes/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kivo/media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late InMemoryErrorLogStore store;
  late ErrorLog log;

  setUp(() {
    store = InMemoryErrorLogStore();
    log = ErrorLog(store, appVersion: '1.1.0', androidSdk: 28);
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void mockFailure(String code, String message) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: code, message: message);
    });
  }

  test('scan throws KV-201 instead of the PlatformException', () async {
    mockFailure('SCAN_FAILED', 'no such column relative_path');

    await expectLater(
      AndroidMediaIndexer(log).scan(),
      throwsA(isA<KivoFailure>()
          .having((f) => f.code, 'code', 'KV-201')
          .having((f) => f.message, 'message', 'No pudimos leer tu biblioteca')),
    );
  });

  test('a failed scan lands in the log with its technical detail', () async {
    mockFailure('SCAN_FAILED', 'no such column relative_path');

    await AndroidMediaIndexer(log).scan().catchError((_) => <VideoItem>[]);

    final entry = log.entries().single;
    expect(entry.code, 'KV-201');
    expect(entry.op, 'libraryScan');
    expect(entry.detail, contains('relative_path'));
  });

  test('a failed thumbnail is logged as KV-202 but returns null', () async {
    mockFailure('THUMB_FAILED', 'decoder gave up');

    expect(await AndroidMediaIndexer(log).thumbnail('7'), isNull);
    expect(log.entries().single.code, 'KV-202');
  });
}
```

`catchError` needs a callback returning the same element type `scan()` does,
hence the explicit `<VideoItem>[]`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/platform/android_media_indexer_failure_test.dart`
Expected: FAIL — `AndroidMediaIndexer` takes no arguments (1 positional given).

- [ ] **Step 3: Write minimal implementation**

Rewrite `lib/platform/android/android_media_indexer.dart`:

```dart
import 'package:flutter/services.dart';
import '../../core/errors/error_log.dart';
import '../../core/errors/kivo_failure.dart';
import '../interfaces/media_indexer.dart';

class AndroidMediaIndexer implements MediaIndexer {
  AndroidMediaIndexer(this._log);

  final ErrorLog _log;
  static const MethodChannel _channel = MethodChannel('kivo/media');

  @override
  Future<List<VideoItem>> scan() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('scan') ?? const [];
      return raw.map((e) {
        final m = (e as Map).cast<String, dynamic>();
        return VideoItem(
          id: m['id'] as String,
          uri: m['uri'] as String,
          name: (m['name'] as String?) ?? '',
          folder: (m['folder'] as String?) ?? '',
          durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
          sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
          dateAddedMs: (m['dateAddedMs'] as num?)?.toInt() ?? 0,
          width: (m['width'] as num?)?.toInt() ?? 0,
          height: (m['height'] as num?)?.toInt() ?? 0,
          path: (m['path'] as String?) ?? '',
        );
      }).toList();
    } catch (e) {
      throw _log.record(KivoFailure(KivoOp.libraryScan, e));
    }
  }

  /// Records and returns null rather than throwing: one undecodable video must
  /// not blank out a grid of two hundred tiles.
  @override
  Future<Uint8List?> thumbnail(String id) async {
    try {
      return await _channel.invokeMethod<Uint8List>('thumbnail', {'id': id});
    } catch (e) {
      _log.record(KivoFailure(KivoOp.thumbnail, e));
      return null;
    }
  }
}
```

In `lib/main.dart`, change the override to
`mediaIndexerProvider.overrideWithValue(AndroidMediaIndexer(errorLog))`.

- [ ] **Step 4: Run tests**

Run: `flutter test test/platform/android_media_indexer_failure_test.dart`
Expected: PASS, 3 tests.

Run: `flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/platform/android/android_media_indexer.dart lib/main.dart test/platform/android_media_indexer_failure_test.dart
git commit -m "feat(errors): library scan and thumbnail failures become KV-201/KV-202"
```

---

### Task 5: Translate vault failures (KV-401, KV-402, KV-403)

**Files:**
- Modify: `lib/platform/android/android_vault_ops.dart`
- Modify: `lib/main.dart` (pass the log)
- Modify: `android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt` (log skipped uris in `hide`)
- Test: `test/platform/android_vault_ops_failure_test.dart`

**Interfaces:**
- Consumes: `KivoFailure`, `KivoOp`, `ErrorLog`.
- Produces: `AndroidVaultOps(ErrorLog log)`.

Batch semantics, exactly as the spec fixes them — a partially successful batch is
**not** a failure:

| Result | Behaviour |
|---|---|
| Some entries missing from a non-empty request | `record` a `vaultHide` entry naming the counts; **return** what succeeded |
| Zero entries for a non-empty request | `throw KivoFailure(vaultHide, …)` → KV-401 |
| Empty request | return empty, log nothing |

- [ ] **Step 1: Write the failing test**

Create `test/platform/android_vault_ops_failure_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/platform/android/android_vault_ops.dart';
import '../fakes/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kivo/vault');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late ErrorLog log;

  setUp(() => log =
      ErrorLog(InMemoryErrorLogStore(), appVersion: '1.1.0', androidSdk: 28));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void mockReply(Object? Function(MethodCall call) reply) {
    messenger.setMockMethodCallHandler(channel, (call) async => reply(call));
  }

  test('a totally failed hide throws KV-401', () async {
    mockReply((_) => <dynamic>[]);

    await expectLater(
      AndroidVaultOps(log).hide(['uri-1', 'uri-2']),
      throwsA(isA<KivoFailure>().having((f) => f.code, 'code', 'KV-401')),
    );
    expect(log.entries().single.op, 'vaultHide');
  });

  test('a partial hide returns what worked and logs the gap', () async {
    mockReply((_) => <dynamic>[
          {'id': '1', 'privatePath': '/vault/1.mp4'}
        ]);

    final result = await AndroidVaultOps(log).hide(['uri-1', 'uri-2', 'uri-3']);

    expect(result, hasLength(1));
    final entry = log.entries().single;
    expect(entry.code, 'KV-401');
    expect(entry.detail, contains('1'));
    expect(entry.detail, contains('3'));
  });

  test('a fully successful hide logs nothing', () async {
    mockReply((_) => <dynamic>[
          {'id': '1'},
          {'id': '2'}
        ]);

    expect(await AndroidVaultOps(log).hide(['uri-1', 'uri-2']), hasLength(2));
    expect(log.entries(), isEmpty);
  });

  test('an empty request logs nothing and throws nothing', () async {
    mockReply((_) => <dynamic>[]);

    expect(await AndroidVaultOps(log).hide([]), isEmpty);
    expect(log.entries(), isEmpty);
  });

  test('a channel error on unhide throws KV-402', () async {
    messenger.setMockMethodCallHandler(channel,
        (call) async => throw PlatformException(code: 'X', message: 'move failed'));

    await expectLater(
      AndroidVaultOps(log).unhide([
        {'privatePath': '/vault/1.mp4'}
      ]),
      throwsA(isA<KivoFailure>().having((f) => f.code, 'code', 'KV-402')),
    );
  });

  test('a channel error on deleteForever throws KV-403', () async {
    messenger.setMockMethodCallHandler(channel,
        (call) async => throw PlatformException(code: 'X', message: 'unlink failed'));

    await expectLater(
      AndroidVaultOps(log).deleteForever(['/vault/1.mp4']),
      throwsA(isA<KivoFailure>().having((f) => f.code, 'code', 'KV-403')),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/platform/android_vault_ops_failure_test.dart`
Expected: FAIL — `AndroidVaultOps` takes no arguments; `hide` currently returns
`const []` instead of throwing.

- [ ] **Step 3: Write minimal implementation**

Rewrite `lib/platform/android/android_vault_ops.dart`:

```dart
import 'package:flutter/services.dart';
import '../../core/errors/error_log.dart';
import '../../core/errors/kivo_failure.dart';
import '../interfaces/vault_ops.dart';

class AndroidVaultOps implements VaultOps {
  AndroidVaultOps(this._log);

  final ErrorLog _log;
  static const MethodChannel _channel = MethodChannel('kivo/vault');

  /// A partially successful batch is NOT a failure: one unreadable file must
  /// not cost the user the other twenty-nine. The gap is recorded for later;
  /// only a total failure reaches the user as KV-401.
  @override
  Future<List<Map<String, dynamic>>> hide(List<String> uris) async {
    List<Map<String, dynamic>> hidden;
    try {
      final raw =
          await _channel.invokeMethod<List<dynamic>>('hide', {'uris': uris}) ??
              const [];
      hidden = raw.map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (e) {
      throw _log.record(KivoFailure(KivoOp.vaultHide, e));
    }
    if (uris.isEmpty) return hidden;
    if (hidden.isEmpty) {
      throw _log.record(KivoFailure(
          KivoOp.vaultHide, 'hid 0 of ${uris.length}: $uris'));
    }
    if (hidden.length < uris.length) {
      _log.record(KivoFailure(KivoOp.vaultHide,
          'hid ${hidden.length} of ${uris.length}; skipped $uris'));
    }
    return hidden;
  }

  @override
  Future<List<String>> unhide(List<Map<String, dynamic>> entries) async {
    try {
      final raw = await _channel
              .invokeMethod<List<dynamic>>('unhide', {'entries': entries}) ??
          const [];
      return raw.cast<String>();
    } catch (e) {
      throw _log.record(KivoFailure(KivoOp.vaultRestore, e));
    }
  }

  @override
  Future<List<String>> deleteForever(List<String> privatePaths) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
              'deleteForever', {'paths': privatePaths}) ??
          const [];
      return raw.cast<String>();
    } catch (e) {
      throw _log.record(KivoFailure(KivoOp.vaultPurge, e));
    }
  }

  /// Records and returns null: a missing vault thumbnail is cosmetic.
  @override
  Future<Uint8List?> thumbnail(String privatePath) async {
    try {
      return await _channel
          .invokeMethod<Uint8List>('thumbnail', {'path': privatePath});
    } catch (e) {
      _log.record(KivoFailure(KivoOp.thumbnail, e));
      return null;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> migrate() async {
    try {
      final raw =
          await _channel.invokeMethod<List<dynamic>>('migrate') ?? const [];
      return raw.map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (e) {
      _log.record(KivoFailure(KivoOp.vaultRestore, e));
      return const [];
    }
  }
}
```

`migrate()` records but does not throw — it runs at startup with no UI to catch it.

In `MainActivity.kt`, in the `kivo/vault` `hide` handler, replace the silent
per-uri catch:

```kotlin
                                } catch (_: Exception) { /* skip this uri */ }
```

with:

```kotlin
                                } catch (e: Exception) {
                                    // Skip this uri but leave a trace: a batch
                                    // that silently hides fewer files than asked
                                    // is indistinguishable from success.
                                    android.util.Log.w("kivo/vault", "hide skipped $uriStr: ${e.message}")
                                }
```

In `lib/main.dart`, change the override to
`vaultOpsProvider.overrideWithValue(AndroidVaultOps(errorLog))`.

- [ ] **Step 4: Run tests**

Run: `flutter test test/platform/android_vault_ops_failure_test.dart`
Expected: PASS, 6 tests.

Run: `flutter test`
Expected: PASS. `hide` now throws where it used to return `[]`, so any caller or
test that relied on the swallow needs a `try`/`catch` — Task 9 wires the UI ones.

- [ ] **Step 5: Commit**

```bash
git add lib/platform/android/android_vault_ops.dart lib/main.dart android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt test/platform/android_vault_ops_failure_test.dart
git commit -m "feat(errors): vault failures become KV-401/402/403, partial batches logged"
```

---

### Task 6: Translate file-op, permission and update failures

**Files:**
- Modify: `lib/platform/android/android_media_file_ops.dart`
- Modify: `lib/platform/android/permission_handler_media_permission.dart`
- Modify: `lib/core/update/update_checker.dart:49`
- Modify: `lib/main.dart` (pass the log to all three)
- Test: `test/platform/android_media_file_ops_failure_test.dart`

**Interfaces:**
- Produces: `AndroidMediaFileOps(ErrorLog log)`, `PermissionHandlerMediaPermission(ErrorLog log)`.

These adapters return status enums rather than throwing, and their callers already
show friendly copy. So here the win is purely the **log**: today a "No se pudo
borrar" leaves nothing behind. Keep the return contracts exactly as they are —
changing them would ripple through the UI for no gain — and only add recording.

As the spec's follow-up notes, `detail` will be thin for KV-301/KV-302 until the
Kotlin side returns a reason instead of `'error'`. That is out of scope here.

- [ ] **Step 1: Write the failing test**

Create `test/platform/android_media_file_ops_failure_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/platform/android/android_media_file_ops.dart';
import 'package:kivo_player/platform/interfaces/media_file_ops.dart';
import '../fakes/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kivo/media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late ErrorLog log;

  setUp(() => log =
      ErrorLog(InMemoryErrorLogStore(), appVersion: '1.1.0', androidSdk: 28));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void mockThrow() {
    messenger.setMockMethodCallHandler(channel,
        (call) async => throw PlatformException(code: 'X', message: 'denied'));
  }

  void mockReply(Object? value) {
    messenger.setMockMethodCallHandler(channel, (call) async => value);
  }

  test('a thrown delete still returns error, and is logged as KV-301', () async {
    mockThrow();

    expect(await AndroidMediaFileOps(log).delete('uri'), FileOpStatus.error);
    expect(log.entries().single.code, 'KV-301');
  });

  test('an error status from the platform is logged too', () async {
    mockReply('error');

    expect(await AndroidMediaFileOps(log).delete('uri'), FileOpStatus.error);
    expect(log.entries().single.code, 'KV-301');
  });

  test('a cancelled delete is not an error and is not logged', () async {
    mockReply('cancelled');

    expect(await AndroidMediaFileOps(log).delete('uri'), FileOpStatus.cancelled);
    expect(log.entries(), isEmpty);
  });

  test('a thrown rename is logged as KV-302', () async {
    mockThrow();

    final out = await AndroidMediaFileOps(log).rename('uri', 'nuevo');
    expect(out.status, FileOpStatus.error);
    expect(log.entries().single.code, 'KV-302');
  });

  test('a thrown share is logged as KV-303', () async {
    mockThrow();

    await AndroidMediaFileOps(log).share('uri');
    expect(log.entries().single.code, 'KV-303');
  });
}
```

The cancelled test matters: the user tapping "cancel" on the system dialog is not
a failure and must not fill the log with noise.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/platform/android_media_file_ops_failure_test.dart`
Expected: FAIL — `AndroidMediaFileOps` takes no arguments.

- [ ] **Step 3: Write minimal implementation**

Rewrite `lib/platform/android/android_media_file_ops.dart`:

```dart
import 'package:flutter/services.dart';
import '../../core/errors/error_log.dart';
import '../../core/errors/kivo_failure.dart';
import '../interfaces/media_file_ops.dart';

class AndroidMediaFileOps implements MediaFileOps {
  AndroidMediaFileOps(this._log);

  final ErrorLog _log;
  static const MethodChannel _channel = MethodChannel('kivo/media');

  FileOpStatus _status(String? s) => switch (s) {
        'ok' => FileOpStatus.ok,
        'cancelled' => FileOpStatus.cancelled,
        _ => FileOpStatus.error,
      };

  /// Records [op] when [status] is an error. `cancelled` is the user changing
  /// their mind, not a failure — logging it would only add noise.
  FileOpStatus _recordIfError(FileOpStatus status, KivoOp op, Object cause) {
    if (status == FileOpStatus.error) _log.record(KivoFailure(op, cause));
    return status;
  }

  @override
  Future<FileOpStatus> delete(String uri) async {
    try {
      final s = await _channel.invokeMethod<String>('delete', {'uri': uri});
      return _recordIfError(_status(s), KivoOp.delete, 'delete returned $s');
    } catch (e) {
      _log.record(KivoFailure(KivoOp.delete, e));
      return FileOpStatus.error;
    }
  }

  @override
  Future<RenameOutcome> rename(String uri, String newBaseName) async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>(
          'rename', {'uri': uri, 'name': newBaseName});
      final status = _recordIfError(_status(m?['status'] as String?),
          KivoOp.rename, 'rename returned ${m?['status']}');
      return RenameOutcome(status, newName: m?['newName'] as String?);
    } catch (e) {
      _log.record(KivoFailure(KivoOp.rename, e));
      return const RenameOutcome(FileOpStatus.error);
    }
  }

  @override
  Future<void> share(String uri) async {
    try {
      await _channel.invokeMethod<void>('share', {'uri': uri});
    } catch (e) {
      _log.record(KivoFailure(KivoOp.share, e));
    }
  }

  @override
  Future<FileOpStatus> deleteMany(List<String> uris) async {
    try {
      final s = await _channel.invokeMethod<String>('deleteMany', {'uris': uris});
      return _recordIfError(
          _status(s), KivoOp.delete, 'deleteMany(${uris.length}) returned $s');
    } catch (e) {
      _log.record(KivoFailure(KivoOp.delete, e));
      return FileOpStatus.error;
    }
  }

  @override
  Future<void> shareMany(List<String> uris) async {
    try {
      await _channel.invokeMethod<void>('shareMany', {'uris': uris});
    } catch (e) {
      _log.record(KivoFailure(KivoOp.share, e));
    }
  }
}
```

In `lib/platform/android/permission_handler_media_permission.dart`, add the log
and record a denied *request* (a denial the user chose is worth knowing about
when they later report "no me carga nada"):

```dart
class PermissionHandlerMediaPermission implements MediaPermission {
  PermissionHandlerMediaPermission(this._log);

  final ErrorLog _log;
```

and in `request()`, before returning:

```dart
    final access = _combine(
      res[Permission.videos] ?? PermissionStatus.denied,
      res[Permission.storage] ?? PermissionStatus.denied,
    );
    if (access == MediaAccess.denied) {
      _log.record(KivoFailure(KivoOp.mediaAccess,
          'videos=${res[Permission.videos]} storage=${res[Permission.storage]}'));
    }
    return access;
```

Add the two imports. Leave `status()` alone — polling status is not a failure.

In `lib/core/update/update_checker.dart:49`, replace the bare `debugPrint` with a
recorded failure. The checker is a plain class, so give it an optional log to
avoid disturbing its existing tests:

```dart
      _log?.record(KivoFailure(KivoOp.updateCheck, e));
      debugPrint('UpdateChecker.fetchLatest failed: $e');
```

adding `final ErrorLog? _log;` and an optional constructor parameter
`{ErrorLog? log}` assigned to it.

In `lib/main.dart`, update the three overrides to pass `errorLog`:
`mediaFileOpsProvider.overrideWithValue(AndroidMediaFileOps(errorLog))`,
`mediaPermissionImplProvider.overrideWithValue(PermissionHandlerMediaPermission(errorLog))`,
and pass `log: errorLog` where the update checker is constructed.

- [ ] **Step 4: Run tests**

Run: `flutter test test/platform/android_media_file_ops_failure_test.dart`
Expected: PASS, 5 tests.

Run: `flutter test` and `flutter analyze`
Expected: PASS, no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/platform/android/android_media_file_ops.dart lib/platform/android/permission_handler_media_permission.dart lib/core/update/update_checker.dart lib/main.dart test/platform/android_media_file_ops_failure_test.dart
git commit -m "feat(errors): record file-op, permission and update failures"
```

---

### Task 7: `FailureView` and the details sheet

**Files:**
- Create: `lib/ui/widgets/failure_view.dart`
- Modify: `lib/ui/home/library_screen.dart:262-269`
- Test: `test/ui/failure_view_test.dart`

**Interfaces:**
- Produces: `class FailureView extends StatelessWidget` with `const FailureView({super.key, required this.failure, this.onRetry})` taking a `KivoFailure`; and `Future<void> showFailureDetailsSheet(BuildContext context, KivoFailure failure)`.
- `FailureView` also accepts a non-`KivoFailure` error via `FailureView.from(Object error, {VoidCallback? onRetry})`, which wraps anything unrecognised as `KivoFailure(KivoOp.libraryScan, error)`'s neighbour — see below.

Riverpod's `AsyncValue.error` hands us `Object`, so the view needs a total
function from `Object` to something displayable. `FailureView.from` returns a
`FailureView` for a `KivoFailure` and, for anything else, a generic one that still
shows a code — an unrecognised error with no code would be exactly the hole this
work is closing.

- [ ] **Step 1: Write the failing test**

Create `test/ui/failure_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/ui/widgets/failure_view.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  const failure = KivoFailure(KivoOp.libraryScan, 'no such column relative_path');

  testWidgets('shows the friendly message and the code', (tester) async {
    await tester.pumpWidget(_host(const FailureView(failure: failure)));

    expect(find.text('No pudimos leer tu biblioteca'), findsOneWidget);
    expect(find.text('KV-201'), findsOneWidget);
  });

  testWidgets('hides the technical detail until it is asked for', (tester) async {
    await tester.pumpWidget(_host(const FailureView(failure: failure)));

    expect(find.textContaining('relative_path'), findsNothing);

    await tester.tap(find.text('Ver detalles'));
    await tester.pumpAndSettle();

    expect(find.textContaining('relative_path'), findsOneWidget);
  });

  testWidgets('offers a retry when one is given', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
        _host(FailureView(failure: failure, onRetry: () => retried++)));

    await tester.tap(find.text('Reintentar'));
    expect(retried, 1);
  });

  testWidgets('omits retry when none is given', (tester) async {
    await tester.pumpWidget(_host(const FailureView(failure: failure)));
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets('an unknown error still gets a message and a code',
      (tester) async {
    await tester.pumpWidget(
        _host(FailureView.from(StateError('kaboom internals'))));

    expect(find.textContaining('kaboom internals'), findsNothing);
    expect(find.textContaining('KV-'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/failure_view_test.dart`
Expected: FAIL — target of URI doesn't exist for `ui/widgets/failure_view.dart`.

- [ ] **Step 3: Write minimal implementation**

Add to the catalog in `lib/core/errors/kivo_failure.dart` a value for
unclassified errors, keeping the append-only rule (`999` is reserved for it):

```dart
  KivoOp.unknown: (code: 'KV-999', message: 'Algo no salió como esperábamos'),
```

and add `unknown` as the last value of `enum KivoOp`. The Task 1 tests cover it
automatically.

Create `lib/ui/widgets/failure_view.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/errors/kivo_failure.dart';

/// The full-screen failure state: friendly message, quotable code, and the
/// technical detail only where the user asked for it.
class FailureView extends StatelessWidget {
  const FailureView({super.key, required this.failure, this.onRetry});

  /// Total over `Object` — Riverpod's `AsyncValue.error` gives us no guarantees,
  /// and an error with no code would be the very hole this closes.
  factory FailureView.from(Object error, {VoidCallback? onRetry}) => FailureView(
        failure: error is KivoFailure
            ? error
            : KivoFailure(KivoOp.unknown, error),
        onRetry: onRetry,
      );

  final KivoFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              failure.code,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onRetry != null) ...[
                  TextButton(
                    onPressed: onRetry,
                    child: Text('Reintentar',
                        style: TextStyle(color: cs.secondary)),
                  ),
                  const SizedBox(width: 4),
                ],
                TextButton(
                  onPressed: () => showFailureDetailsSheet(context, failure),
                  child: Text('Ver detalles',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The one place raw technical text is rendered.
Future<void> showFailureDetailsSheet(
    BuildContext context, KivoFailure failure) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: cs.surfaceContainerHighest,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(failure.code,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.secondary)),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 19),
                color: cs.onSurfaceVariant,
                onPressed: () => _copyDetail(sheetContext, failure),
              ),
            ]),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 260),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: cs.surface, borderRadius: BorderRadius.circular(10)),
              child: SingleChildScrollView(
                child: SelectableText(
                  failure.detail,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      height: 1.4,
                      color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
```

Add at the bottom of the file:

```dart
Future<void> _copyDetail(BuildContext context, KivoFailure failure) async {
  await Clipboard.setData(
      ClipboardData(text: '${failure.code}\n${failure.detail}'));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Detalle copiado')));
}
```

with `import 'package:flutter/services.dart';` for `Clipboard`.

In `lib/ui/home/library_screen.dart`, replace the error branch (lines 262-269):

```dart
      error: (e, __) => FailureView.from(
        e,
        onRetry: () => ref.invalidate(mediaIndexProvider),
      ),
```

and add `import '../widgets/failure_view.dart';`. Confirm the retry target: if
the provider that feeds `_body()` is named differently, invalidate the one
`ref.watch(mediaIndexProvider)` reads on line 259.

- [ ] **Step 4: Run tests**

Run: `flutter test test/ui/failure_view_test.dart`
Expected: PASS, 5 tests.

Run: `flutter test test/core/errors/kivo_failure_test.dart`
Expected: PASS — the catalog tests now cover `KivoOp.unknown` too.

Run: `flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/failure_view.dart lib/core/errors/kivo_failure.dart lib/ui/home/library_screen.dart test/ui/failure_view_test.dart
git commit -m "feat(errors): FailureView replaces the raw exception on the library screen"
```

---

### Task 8: `failureSnackBar` for the transient failures

**Files:**
- Create: `lib/ui/widgets/failure_snack_bar.dart`
- Modify: `lib/ui/home/widgets/video_options_sheet.dart:131,158`
- Modify: `lib/ui/home/widgets/selection_bottom_bar.dart:72`
- Modify: `lib/ui/settings/sections/about_section.dart:38`
- Modify: `lib/ui/vault/widgets/vault_bottom_bar.dart:38,58`
- Modify: `lib/ui/vault/vault_entry_actions.dart`
- Test: `test/ui/failure_snack_bar_test.dart`

**Interfaces:**
- Produces: `void showFailureSnackBar(BuildContext context, KivoOp op, {Object? cause})` — builds the `KivoFailure`, shows a SnackBar reading `message (code)` with a **Detalles** action that opens `showFailureDetailsSheet`.

Taking a `KivoOp` rather than a `KivoFailure` keeps the call sites short at the
places that only know *which* operation failed, not why — which is most of them,
because the file-op adapters return statuses.

- [ ] **Step 1: Write the failing test**

Create `test/ui/failure_snack_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/ui/widgets/failure_snack_bar.dart';

void main() {
  testWidgets('shows the message with the code and a details action',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFailureSnackBar(context, KivoOp.delete,
                cause: 'SecurityException: denied'),
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.text('No pudimos borrar el video (KV-301)'), findsOneWidget);
    expect(find.textContaining('SecurityException'), findsNothing);

    await tester.tap(find.text('Detalles'));
    await tester.pumpAndSettle();

    expect(find.textContaining('SecurityException'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/failure_snack_bar_test.dart`
Expected: FAIL — target of URI doesn't exist for `ui/widgets/failure_snack_bar.dart`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/ui/widgets/failure_snack_bar.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/errors/kivo_failure.dart';
import 'failure_view.dart';

/// The transient counterpart to [FailureView]: friendly copy plus the code,
/// with the technical detail behind an action rather than in the message.
void showFailureSnackBar(BuildContext context, KivoOp op, {Object? cause}) {
  final failure = KivoFailure(op, cause ?? 'sin detalle técnico');
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('${failure.message} (${failure.code})'),
    action: SnackBarAction(
      label: 'Detalles',
      onPressed: () => showFailureDetailsSheet(context, failure),
    ),
  ));
}
```

Then replace each failure SnackBar. In `video_options_sheet.dart`, line 131:

```dart
          showFailureSnackBar(context, KivoOp.rename);
```

and line 158:

```dart
          showFailureSnackBar(context, KivoOp.delete);
```

In `selection_bottom_bar.dart`, line 72:

```dart
                  showFailureSnackBar(context, KivoOp.delete);
```

In `about_section.dart`, line 38:

```dart
          showFailureSnackBar(context, KivoOp.updateCheck);
```

In `vault_bottom_bar.dart` and `vault_entry_actions.dart`, wrap the vault calls
that now throw (Task 5) so a KV-401/402/403 surfaces instead of an unhandled
async error:

```dart
  try {
    // …existing vault call…
  } on KivoFailure catch (f) {
    if (context.mounted) showFailureSnackBar(context, f.op, cause: f.cause);
  }
```

Read each of these six call sites before editing: keep the surrounding
`mounted` guards and success paths exactly as they are, and only swap the
failure branch. Add the imports for `failure_snack_bar.dart` and, where the
`catch` is used, `core/errors/kivo_failure.dart`.

- [ ] **Step 4: Run tests**

Run: `flutter test test/ui/failure_snack_bar_test.dart`
Expected: PASS.

Run: `flutter test` and `flutter analyze`
Expected: PASS, no issues. Existing widget tests asserting the old copy (e.g.
`'No se pudo borrar'`) will fail — update them to the new string; that is the
intended change, not a regression.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/failure_snack_bar.dart lib/ui/home/widgets/video_options_sheet.dart lib/ui/home/widgets/selection_bottom_bar.dart lib/ui/settings/sections/about_section.dart lib/ui/vault/widgets/vault_bottom_bar.dart lib/ui/vault/vault_entry_actions.dart test/ui/failure_snack_bar_test.dart
git commit -m "feat(errors): transient failures show their code with details on tap"
```

---

### Task 9: The error log screen in Settings

**Files:**
- Create: `lib/ui/settings/sections/error_log_section.dart`
- Modify: `lib/ui/settings/sections/about_section.dart` (add the nav row)
- Test: `test/ui/error_log_section_test.dart`

**Interfaces:**
- Consumes: `errorLogProvider`, `ErrorLogEntry`, `SettingsCard`, `SettingNavRow`.
- Produces: `class ErrorLogSection extends ConsumerStatefulWidget`.

Placed under *Acerca de* next to the version and the update check — the app's
other diagnostic corner — rather than in the Settings root, keeping a
developer-facing tool out of the main list.

- [ ] **Step 1: Write the failing test**

Create `test/ui/error_log_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/error_log_provider.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/ui/settings/sections/error_log_section.dart';
import '../fakes/fakes.dart';

Widget _host(ErrorLog log) => ProviderScope(
      overrides: [errorLogProvider.overrideWithValue(log)],
      child: const MaterialApp(home: ErrorLogSection()),
    );

void main() {
  testWidgets('lists recorded failures newest first', (tester) async {
    final log = ErrorLog(InMemoryErrorLogStore(),
        appVersion: '1.1.0', androidSdk: 28);
    log.record(const KivoFailure(KivoOp.libraryScan, 'sqlite says no'));
    log.record(const KivoFailure(KivoOp.delete, 'permission denied'));

    await tester.pumpWidget(_host(log));

    expect(find.text('KV-301'), findsOneWidget);
    expect(find.text('KV-201'), findsOneWidget);
  });

  testWidgets('shows an empty state when nothing has failed', (tester) async {
    await tester.pumpWidget(_host(ErrorLog(InMemoryErrorLogStore(),
        appVersion: '1.1.0', androidSdk: 28)));

    expect(find.text('Sin errores registrados'), findsOneWidget);
  });

  testWidgets('expanding an entry reveals its technical detail',
      (tester) async {
    final log = ErrorLog(InMemoryErrorLogStore(),
        appVersion: '1.1.0', androidSdk: 28);
    log.record(const KivoFailure(KivoOp.libraryScan, 'sqlite says no'));

    await tester.pumpWidget(_host(log));
    expect(find.textContaining('sqlite says no'), findsNothing);

    await tester.tap(find.text('KV-201'));
    await tester.pumpAndSettle();

    expect(find.textContaining('sqlite says no'), findsOneWidget);
  });

  testWidgets('clearing empties the list', (tester) async {
    final log = ErrorLog(InMemoryErrorLogStore(),
        appVersion: '1.1.0', androidSdk: 28);
    log.record(const KivoFailure(KivoOp.libraryScan, 'sqlite says no'));

    await tester.pumpWidget(_host(log));
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Sin errores registrados'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/error_log_section_test.dart`
Expected: FAIL — target of URI doesn't exist for
`ui/settings/sections/error_log_section.dart`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/ui/settings/sections/error_log_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_log.dart';
import '../../../core/errors/error_log_provider.dart';

/// The last failures Kivo recorded, so a reported code can be traced back to
/// what actually went wrong on that device.
class ErrorLogSection extends ConsumerStatefulWidget {
  const ErrorLogSection({super.key});

  @override
  ConsumerState<ErrorLogSection> createState() => _ErrorLogSectionState();
}

class _ErrorLogSectionState extends ConsumerState<ErrorLogSection> {
  final _expanded = <int>{};

  String _age(int timestampMs) {
    final d = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(timestampMs));
    if (d.inMinutes < 1) return 'ahora mismo';
    if (d.inHours < 1) return 'hace ${d.inMinutes} min';
    if (d.inDays < 1) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  Future<void> _copyAll(List<ErrorLogEntry> entries) async {
    final text = entries
        .map((e) => '${e.code} ${e.op} · Kivo ${e.appVersion} · '
            'API ${e.androidSdk}\n${e.detail}')
        .join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Registro copiado')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final log = ref.watch(errorLogProvider);
    final entries = log.entries();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de errores'),
        actions: [
          if (entries.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: 'Copiar todo',
              onPressed: () => _copyAll(entries),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Borrar registro',
              onPressed: () async {
                await log.clear();
                if (mounted) setState(() => _expanded.clear());
              },
            ),
          ],
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Text('Sin errores registrados',
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _entryTile(entries[i], i, cs),
            ),
    );
  }

  Widget _entryTile(ErrorLogEntry e, int i, ColorScheme cs) {
    final open = _expanded.contains(i);
    return Container(
      decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(13)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(
                () => open ? _expanded.remove(i) : _expanded.add(i)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Text(e.code,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: cs.secondary)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${e.op} · ${_age(e.timestampMs)}',
                        style: TextStyle(
                            fontSize: 11.5, color: cs.onSurfaceVariant)),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more,
                      size: 20, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kivo ${e.appVersion} · Android API ${e.androidSdk}',
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(9)),
                    child: SelectableText(
                      e.detail,
                      style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.4,
                          color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

In `about_section.dart`, add after the "Buscar automáticamente" switch:

```dart
          const SizedBox(height: 20),
          SettingsCard(children: [
            SettingNavRow(
              icon: Icons.bug_report_outlined,
              title: 'Registro de errores',
              subtitle: 'Los últimos fallos, con su detalle técnico',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ErrorLogSection())),
            ),
          ]),
```

with `import 'error_log_section.dart';`. `SettingsCard` and `SettingNavRow` are
already imported there via `../widgets/setting_tiles.dart`.

- [ ] **Step 4: Run tests**

Run: `flutter test test/ui/error_log_section_test.dart`
Expected: PASS, 4 tests.

Run: `flutter test` and `flutter analyze`
Expected: PASS, no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/sections/error_log_section.dart lib/ui/settings/sections/about_section.dart test/ui/error_log_section_test.dart
git commit -m "feat(errors): error log screen under Acerca de"
```

---

### Task 10: Playback open failures (KV-501)

**Files:**
- Modify: `lib/player/engine/media_kit_engine.dart:50-52`
- Modify: `lib/player/autoplay/autoplay_coordinator.dart:72`
- Test: `test/player/open_failure_test.dart`

**Interfaces:**
- Consumes: `KivoFailure`, `KivoOp`, `ErrorLog`.
- Produces: `MediaKitEngine({ErrorLog? log})` — optional so the many existing
  engine tests keep constructing it bare.

Today a throwing `_player.open` is an unhandled async error and the user gets a
black screen with no message at all. This is the one place in the plan that adds a
message where there was none, rather than replacing a bad one.

- [ ] **Step 1: Write the failing test**

Create `test/player/open_failure_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import '../fakes/fakes.dart';

void main() {
  test('a failing open is logged as KV-501 and rethrown as a KivoFailure',
      () async {
    final store = InMemoryErrorLogStore();
    final log = ErrorLog(store, appVersion: '1.1.0', androidSdk: 28);
    final engine = FakePlaybackEngine()..openError = StateError('codec missing');

    await expectLater(
      guardedOpen(engine, '/videos/x.mkv', log),
      throwsA(isA<KivoFailure>().having((f) => f.code, 'code', 'KV-501')),
    );
    expect(log.entries().single.detail, contains('codec missing'));
  });

  test('a successful open logs nothing', () async {
    final log = ErrorLog(InMemoryErrorLogStore(),
        appVersion: '1.1.0', androidSdk: 28);

    await guardedOpen(FakePlaybackEngine(), '/videos/x.mkv', log);

    expect(log.entries(), isEmpty);
  });
}
```

Add to `FakePlaybackEngine` in `test/fakes/fakes.dart`:

```dart
  Object? openError;
```

and at the top of its `open` implementation:

```dart
    if (openError != null) throw openError!;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/player/open_failure_test.dart`
Expected: FAIL — `guardedOpen` is not defined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/player/open/guarded_open.dart`:

```dart
import '../../core/errors/error_log.dart';
import '../../core/errors/kivo_failure.dart';
import '../engine/playback_engine.dart';

/// Opens [path] on [engine], turning an engine failure into a KV-501 the UI can
/// show. Without this a bad file is an unhandled async error and the user just
/// gets a black screen.
Future<void> guardedOpen(
  PlaybackEngine engine,
  String path,
  ErrorLog log, {
  Duration startAt = Duration.zero,
}) async {
  try {
    await engine.open(path, startAt: startAt);
  } catch (e) {
    throw log.record(KivoFailure(KivoOp.openVideo, e));
  }
}
```

Add `import '../open/guarded_open.dart';` and the error-log provider to
`autoplay_coordinator.dart`, and replace line 72:

```dart
      await guardedOpen(engine, next.playbackPath,
          _ref.read(errorLogProvider), startAt: plan.startAt);
```

Then find the player screen's own open call (search for `engine.open(` outside
the coordinator) and route it through `guardedOpen` the same way, catching
`KivoFailure` at the call site to show `showFailureSnackBar(context, f.op,
cause: f.cause)` — a failed open must not replace the whole player with a
full-screen error while something may still be playing.

- [ ] **Step 4: Run tests**

Run: `flutter test test/player/open_failure_test.dart`
Expected: PASS, 2 tests.

Run: `flutter test` and `flutter analyze`
Expected: PASS, no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/player/open/guarded_open.dart lib/player/autoplay/autoplay_coordinator.dart test/player/open_failure_test.dart test/fakes/fakes.dart
git commit -m "feat(errors): a failed video open reports KV-501 instead of a black screen"
```

---

### Task 11: Verify on a device

**Files:** none — verification only.

- [ ] **Step 1: Confirm the suite and the analyzer are clean**

Run: `flutter test`
Expected: PASS, every test.

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 2: Build and install a release APK**

```bash
flutter build apk --release
```

Install on the connected device and open the library.

- [ ] **Step 3: Force a failure and read the code**

The cheapest real failure: revoke Kivo's storage permission in Android settings,
reopen the app, and deny when asked. Expect the friendly message with **KV-101**,
and expect the entry to appear under Ajustes → Acerca de → Registro de errores
with its API level.

- [ ] **Step 4: Confirm the details path**

Tap "Ver detalles" on a failure, confirm the technical text appears, tap copy,
and paste somewhere to confirm the clipboard carries code + detail.

- [ ] **Step 5: Commit nothing; report**

Report the codes seen and whether the log survived an app restart (it must — that
is what the Hive persistence is for).

---

## Self-Review

**Spec coverage.** Walked each spec section against the tasks:

| Spec section | Task |
|---|---|
| 1 — failure type and catalog | 1 (plus `KivoOp.unknown` added in 7) |
| 2 — translation at the adapters | 4 (library), 5 (vault), 6 (file ops, permission, update), 10 (playback) |
| 2 — `ErrorLog` injected by constructor | 3 |
| 2 — vault partial-batch semantics | 5 |
| 3 — 20-entry persisted ring buffer with device context | 2, 3 |
| 3 — log may never break a screen | 2 (`ThrowingErrorLogStore` test) |
| 4 — `FailureView`, `failureSnackBar`, details sheet | 7, 8 |
| 4 — Registro de errores under Acerca de | 9 |
| 5 — catalog integrity, ring buffer, adapter mapping, widget test | 1, 2, 4, 7 |
| Follow-up (thin `detail` for KV-301/302) | noted in 6, deliberately not done |

No gaps found.

**Placeholder scan.** No "TBD"/"TODO"/"handle edge cases". Two were found and
removed on review: a stub type name in Task 4's test with a "replace this after"
note, and a filler test in Task 9 with an instruction to delete it before
committing. Both are now just the real code. Three steps say
"read the call site first" (Tasks 8 and 10) rather than printing the surrounding
code — these are edits into code whose exact current shape matters, and the step
names the file, the line and the precise replacement. Task 10's player-screen
open is the one genuinely open-ended edit: the plan says what to search for and
what to do, because the call site was not read while planning.

**Type consistency.** `record(KivoFailure) → KivoFailure` used identically in
Tasks 4, 5, 6, 10. `KivoOp` value names match the catalog throughout. `ErrorLog`
constructor `(store, {appVersion, androidSdk, now})` matches every test call.
`FailureView.from(Object)` in Task 7 matches its use in `library_screen.dart`.
`showFailureSnackBar(context, KivoOp, {cause})` matches all six call sites in
Task 8 and the two in Task 10. `ErrorLogEntry` field names match between
`toMap`/`fromMap` (Task 2) and the Settings screen (Task 9).

One inconsistency found and fixed while reviewing: Task 2's test called
`ErrorLog(store, appVersion:…, androidSdk:…)` positionally for the store while
the original interface sketch had it named — the plan now uses the positional
store everywhere, matching `HivePlayedStore(box)` in the codebase.
