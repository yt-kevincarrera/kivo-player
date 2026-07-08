# Kivo Vault Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide videos in a private, PIN/biometric-gated Vault: hidden videos vanish from the library and every other app, can be returned to the gallery, or deleted permanently.

**Architecture:** Hiding physically moves the file (instant same-volume `renameTo`) into the app's private external dir and deletes its MediaStore row; metadata is recorded as a `VaultEntry` in Hive so the Vault lists from Hive, not MediaStore. A pure `VaultRepository` orchestrates a `VaultOps` platform interface (Android `MethodChannel('kivo/vault')`). Auth is a pure `VaultAuth` (salted SHA-256 PIN) plus a biometric fast-path via `local_auth`, both behind fakeable interfaces. UI reuses the existing selection/bottom-bar patterns.

**Tech Stack:** Flutter, Riverpod, Hive, media_kit, Android MethodChannel (Kotlin), `local_auth`, `crypto`.

## Global Constraints

- Android-first. iOS is a non-goal; interfaces leave room but no iOS impl.
- Platform boundary pattern: interface in `lib/platform/interfaces/`, Android impl in `lib/platform/android/`, throws-until-overridden provider, overridden in `lib/main.dart`.
- Persistence uses plain `Map<String,dynamic>` in Hive boxes (mirroring `HiveSettingsStore` / `HivePlayedStore`), NOT generated Hive adapters.
- Single configurable accent (gold, `accentColor` default `0xFFE8B84B`); use `Theme.of(context).colorScheme` (`.secondary` is the accent), never hardcoded colors.
- All new logic tested with in-memory fakes and no real IO, matching the existing test style in `test/fakes/fakes.dart`.
- New deps: `local_auth: ^2.3.0`, `crypto: ^3.0.3`.
- PIN stored only as `sha256(salt+pin)` + salt — never in clear.
- The ONLY in-app confirmation kept is permanent delete (irreversible). Hide/unhide are frictionless.
- Spanish UI copy (matches the app).
- TDD: failing test → minimal impl → pass → commit. Frequent commits.

---

### Task 1: VaultEntry model

**Files:**
- Create: `lib/vault/vault_entry.dart`
- Test: `test/vault/vault_entry_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class VaultEntry` with `final String id, privatePath, displayName, originalRelativePath; final int durationMs, sizeBytes, dateAddedMs, width, height;` const ctor with all named-required; `Map<String,dynamic> toMap()`; `factory VaultEntry.fromMap(Map)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/vault/vault_entry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/vault/vault_entry.dart';

void main() {
  const e = VaultEntry(
    id: '42',
    privatePath: '/data/vault/42.mp4',
    displayName: 'clip.mp4',
    originalRelativePath: 'Movies/',
    durationMs: 1000,
    sizeBytes: 2000,
    dateAddedMs: 3000,
    width: 1920,
    height: 1080,
  );

  test('round-trips through toMap/fromMap', () {
    final back = VaultEntry.fromMap(e.toMap());
    expect(back.id, '42');
    expect(back.privatePath, '/data/vault/42.mp4');
    expect(back.displayName, 'clip.mp4');
    expect(back.originalRelativePath, 'Movies/');
    expect(back.durationMs, 1000);
    expect(back.sizeBytes, 2000);
    expect(back.dateAddedMs, 3000);
    expect(back.width, 1920);
    expect(back.height, 1080);
  });

  test('fromMap tolerates a Map<dynamic,dynamic> (Hive read) and missing ints', () {
    final raw = <dynamic, dynamic>{
      'id': '7',
      'privatePath': '/p/7.mkv',
      'displayName': '7.mkv',
      'originalRelativePath': '',
    };
    final entry = VaultEntry.fromMap(Map<String, dynamic>.from(raw));
    expect(entry.id, '7');
    expect(entry.durationMs, 0);
    expect(entry.width, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/vault/vault_entry_test.dart`
Expected: FAIL — `vault_entry.dart` / `VaultEntry` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/vault/vault_entry.dart

/// A video that has been moved into the Vault. Persisted in Hive because once
/// the file leaves MediaStore we no longer get its metadata from a scan.
class VaultEntry {
  final String id;                    // original MediaStore id — stable key
  final String privatePath;           // absolute path inside the vault dir
  final String displayName;           // file name incl. extension — resume key + label
  final String originalRelativePath;  // MediaStore RELATIVE_PATH for restore, '' if unknown
  final int durationMs;
  final int sizeBytes;
  final int dateAddedMs;
  final int width;
  final int height;

  const VaultEntry({
    required this.id,
    required this.privatePath,
    required this.displayName,
    required this.originalRelativePath,
    this.durationMs = 0,
    this.sizeBytes = 0,
    this.dateAddedMs = 0,
    this.width = 0,
    this.height = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'privatePath': privatePath,
        'displayName': displayName,
        'originalRelativePath': originalRelativePath,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
        'dateAddedMs': dateAddedMs,
        'width': width,
        'height': height,
      };

  factory VaultEntry.fromMap(Map<String, dynamic> m) => VaultEntry(
        id: m['id'] as String,
        privatePath: m['privatePath'] as String,
        displayName: m['displayName'] as String,
        originalRelativePath: (m['originalRelativePath'] as String?) ?? '',
        durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
        dateAddedMs: (m['dateAddedMs'] as num?)?.toInt() ?? 0,
        width: (m['width'] as num?)?.toInt() ?? 0,
        height: (m['height'] as num?)?.toInt() ?? 0,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/vault/vault_entry_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/vault/vault_entry.dart test/vault/vault_entry_test.dart
git commit -m "feat(vault): VaultEntry model with map round-trip"
```

---

### Task 2: VaultAuth (PIN hashing) + credential store

**Files:**
- Create: `lib/vault/vault_auth.dart`
- Test: `test/vault/vault_auth_test.dart`
- Modify: `pubspec.yaml` (add `crypto: ^3.0.3`)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `abstract class VaultCredentialStore { String? get hash; String? get salt; Future<void> save(String hash, String salt); Future<void> clear(); }`
  - `class InMemoryVaultCredentialStore implements VaultCredentialStore` (for tests).
  - `class VaultAuth { VaultAuth(this._store); bool get isConfigured; Future<void> setPin(String pin); bool verify(String pin); Future<void> clear(); static String hashPin(String pin, String salt); }`
  - Salt generation uses `Random.secure()` (16 bytes, base64).

- [ ] **Step 1: Add crypto dependency**

Edit `pubspec.yaml` under `dependencies:` (after `permission_handler: ^11.3.1`):

```yaml
  crypto: ^3.0.3
```

Run: `flutter pub get`
Expected: resolves, `crypto` added.

- [ ] **Step 2: Write the failing test**

```dart
// test/vault/vault_auth_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/vault/vault_auth.dart';

void main() {
  test('unconfigured store means not configured', () {
    final auth = VaultAuth(InMemoryVaultCredentialStore());
    expect(auth.isConfigured, false);
    expect(auth.verify('1234'), false);
  });

  test('setPin then verify: correct pin passes, wrong fails', () async {
    final auth = VaultAuth(InMemoryVaultCredentialStore());
    await auth.setPin('2468');
    expect(auth.isConfigured, true);
    expect(auth.verify('2468'), true);
    expect(auth.verify('0000'), false);
  });

  test('hashPin is deterministic for same salt, differs across salts', () {
    final a = VaultAuth.hashPin('1234', 'saltA');
    final b = VaultAuth.hashPin('1234', 'saltA');
    final c = VaultAuth.hashPin('1234', 'saltB');
    expect(a, b);
    expect(a, isNot(c));
  });

  test('two setPin calls with the same pin produce different stored hashes (random salt)', () async {
    final s1 = InMemoryVaultCredentialStore();
    final s2 = InMemoryVaultCredentialStore();
    await VaultAuth(s1).setPin('1234');
    await VaultAuth(s2).setPin('1234');
    expect(s1.hash, isNot(s2.hash));
    // but each still verifies its own pin
    expect(VaultAuth(s1).verify('1234'), true);
    expect(VaultAuth(s2).verify('1234'), true);
  });

  test('clear removes credentials', () async {
    final store = InMemoryVaultCredentialStore();
    final auth = VaultAuth(store);
    await auth.setPin('1234');
    await auth.clear();
    expect(auth.isConfigured, false);
    expect(store.hash, isNull);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/vault/vault_auth_test.dart`
Expected: FAIL — `vault_auth.dart` not found.

- [ ] **Step 4: Write minimal implementation**

```dart
// lib/vault/vault_auth.dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Stores the vault PIN as a salted hash. Never holds the PIN in clear.
abstract class VaultCredentialStore {
  String? get hash;
  String? get salt;
  Future<void> save(String hash, String salt);
  Future<void> clear();
}

class InMemoryVaultCredentialStore implements VaultCredentialStore {
  String? _hash;
  String? _salt;
  @override
  String? get hash => _hash;
  @override
  String? get salt => _salt;
  @override
  Future<void> save(String hash, String salt) async {
    _hash = hash;
    _salt = salt;
  }
  @override
  Future<void> clear() async {
    _hash = null;
    _salt = null;
  }
}

/// PIN auth for the Vault: salted SHA-256, deterministic verification.
class VaultAuth {
  final VaultCredentialStore _store;
  VaultAuth(this._store);

  bool get isConfigured => _store.hash != null && _store.salt != null;

  static String hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt$pin')).toString();

  static String _newSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64Url.encode(bytes);
  }

  Future<void> setPin(String pin) async {
    final salt = _newSalt();
    await _store.save(hashPin(pin, salt), salt);
  }

  bool verify(String pin) {
    final h = _store.hash;
    final s = _store.salt;
    if (h == null || s == null) return false;
    return hashPin(pin, s) == h;
  }

  Future<void> clear() => _store.clear();
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/vault/vault_auth_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/vault/vault_auth.dart test/vault/vault_auth_test.dart
git commit -m "feat(vault): VaultAuth salted-SHA256 PIN + credential store"
```

---

### Task 3: VaultOps interface + FakeVaultOps + provider

**Files:**
- Create: `lib/platform/interfaces/vault_ops.dart`
- Create: `lib/platform/vault_ops_provider.dart`
- Modify: `test/fakes/fakes.dart` (append `FakeVaultOps`)
- Test: `test/vault/fake_vault_ops_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `abstract class VaultOps { Future<List<Map<String,dynamic>>> hide(List<String> uris); Future<bool> unhide(List<String> privatePaths); Future<bool> deleteForever(List<String> privatePaths); Future<Uint8List?> thumbnail(String privatePath); }`
  - `final vaultOpsProvider = Provider<VaultOps>((ref) => throw UnimplementedError(...));`
  - `class FakeVaultOps implements VaultOps` — records calls; `hide` returns one map per uri (echoing an entry); `hideResult` overridable; `unhideResult`/`deleteResult` bools default true; tracks `hiddenUris`, `unhidden`, `deleted`.

- [ ] **Step 1: Write the interface**

```dart
// lib/platform/interfaces/vault_ops.dart
import 'dart:typed_data';

/// Moves video files in and out of the app-private Vault directory. Android
/// impl uses MethodChannel('kivo/vault'); all moves are same-volume renames.
abstract class VaultOps {
  /// Moves each content:// [uris] into the private vault dir and removes its
  /// MediaStore row. Returns one metadata map per SUCCESSFULLY hidden file
  /// (keys: id, privatePath, displayName, originalRelativePath, durationMs,
  /// sizeBytes, dateAddedMs, width, height). Failures are omitted.
  Future<List<Map<String, dynamic>>> hide(List<String> uris);

  /// Moves each private file back to shared storage + re-inserts MediaStore.
  Future<bool> unhide(List<String> privatePaths);

  /// Permanently deletes each private file.
  Future<bool> deleteForever(List<String> privatePaths);

  /// JPEG thumbnail for a private file, or null.
  Future<Uint8List?> thumbnail(String privatePath);
}
```

- [ ] **Step 2: Write the provider**

```dart
// lib/platform/vault_ops_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/vault_ops.dart';

/// Overridden in main() with AndroidVaultOps.
final vaultOpsProvider = Provider<VaultOps>((ref) {
  throw UnimplementedError('vaultOpsProvider must be overridden');
});
```

- [ ] **Step 3: Append FakeVaultOps to test/fakes/fakes.dart**

```dart
// test/fakes/fakes.dart — add import at top and class at bottom
// import 'dart:typed_data'; (add if not already imported)
// import 'package:kivo_player/platform/interfaces/vault_ops.dart';

class FakeVaultOps implements VaultOps {
  final List<String> hiddenUris = [];
  final List<String> unhidden = [];
  final List<String> deleted = [];
  bool unhideResult = true;
  bool deleteResult = true;

  /// Maps each uri -> the metadata map hide() should return. Defaults to a
  /// synthesized entry so callers can just pass uris.
  List<Map<String, dynamic>> Function(List<String> uris)? hideResult;

  @override
  Future<List<Map<String, dynamic>>> hide(List<String> uris) async {
    hiddenUris.addAll(uris);
    if (hideResult != null) return hideResult!(uris);
    return uris.map((u) {
      final id = u.split('/').last; // bare id from a content://.../<id> uri
      return {
              'id': id,
              'privatePath': '/vault/$id.mp4',
              'displayName': '$id.mp4',
              'originalRelativePath': 'Movies/',
              'durationMs': 0,
              'sizeBytes': 0,
              'dateAddedMs': 0,
              'width': 0,
              'height': 0,
      };
    }).toList();
  }

  @override
  Future<bool> unhide(List<String> privatePaths) async {
    unhidden.addAll(privatePaths);
    return unhideResult;
  }

  @override
  Future<bool> deleteForever(List<String> privatePaths) async {
    deleted.addAll(privatePaths);
    return deleteResult;
  }

  @override
  Future<Uint8List?> thumbnail(String privatePath) async => null;
}
```

- [ ] **Step 4: Write the failing test**

```dart
// test/vault/fake_vault_ops_test.dart
import 'package:flutter_test/flutter_test.dart';
import '../fakes/fakes.dart';

void main() {
  test('FakeVaultOps.hide echoes one entry per uri and records the call', () async {
    final ops = FakeVaultOps();
    final maps = await ops.hide(['1', '2']);
    expect(maps.length, 2);
    expect(maps.first['id'], '1');
    expect(ops.hiddenUris, ['1', '2']);
  });

  test('FakeVaultOps records unhide/delete and honors result flags', () async {
    final ops = FakeVaultOps()..deleteResult = false;
    expect(await ops.unhide(['/vault/a.mp4']), true);
    expect(await ops.deleteForever(['/vault/b.mp4']), false);
    expect(ops.unhidden, ['/vault/a.mp4']);
    expect(ops.deleted, ['/vault/b.mp4']);
  });
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/vault/fake_vault_ops_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/platform/interfaces/vault_ops.dart lib/platform/vault_ops_provider.dart test/fakes/fakes.dart test/vault/fake_vault_ops_test.dart
git commit -m "feat(vault): VaultOps interface, provider, FakeVaultOps"
```

---

### Task 4: VaultStore + VaultRepository

**Files:**
- Create: `lib/vault/vault_store.dart`
- Create: `lib/vault/vault_repository.dart`
- Test: `test/vault/vault_repository_test.dart`

**Interfaces:**
- Consumes: `VaultEntry` (Task 1), `VaultOps` + `FakeVaultOps` (Task 3), `VideoItem` (`lib/platform/interfaces/media_indexer.dart`).
- Produces:
  - `abstract class VaultStore { List<VaultEntry> readAll(); Future<void> writeAll(List<VaultEntry> entries); }`
  - `class InMemoryVaultStore implements VaultStore`.
  - `class HiveVaultStore implements VaultStore` (Box, one key `'entries'` holding `List<Map>`).
  - `class VaultRepository { VaultRepository(this._store, this._ops); List<VaultEntry> get entries; Future<List<VaultEntry>> hide(List<VideoItem> videos); Future<bool> unhide(List<VaultEntry> entries); Future<bool> deleteForever(List<VaultEntry> entries); }`
  - `hide`: calls `_ops.hide(uris)`, maps returned maps → `VaultEntry`, merges into store deduped by `id` (new wins), returns the newly hidden entries.
  - `unhide`/`deleteForever`: call ops; on `true`, remove those entries (by `privatePath`) from the store; return the ops result.

- [ ] **Step 1: Write the failing test**

```dart
// test/vault/vault_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/vault/vault_entry.dart';
import 'package:kivo_player/vault/vault_store.dart';
import 'package:kivo_player/vault/vault_repository.dart';
import '../fakes/fakes.dart';

VideoItem _v(String id) => VideoItem(
    id: id, uri: 'content://$id', name: '$id.mp4', folder: 'F',
    durationMs: 1, sizeBytes: 1, dateAddedMs: 1);

void main() {
  test('hide moves ops-returned entries into the store and returns them', () async {
    final store = InMemoryVaultStore();
    final ops = FakeVaultOps();
    final repo = VaultRepository(store, ops);

    final added = await repo.hide([_v('1'), _v('2')]);

    expect(added.map((e) => e.id), ['1', '2']);
    expect(repo.entries.length, 2);
    expect(ops.hiddenUris, ['content://1', 'content://2']);
  });

  test('hide only persists entries the native side actually returned (reconcile)', () async {
    final store = InMemoryVaultStore();
    final ops = FakeVaultOps()
      ..hideResult = ((uris) => [
            {
              'id': '1',
              'privatePath': '/vault/1.mp4',
              'displayName': '1.mp4',
              'originalRelativePath': 'Movies/',
            }
          ]); // uri '2' failed natively -> omitted
    final repo = VaultRepository(store, ops);

    final added = await repo.hide([_v('1'), _v('2')]);

    expect(added.map((e) => e.id), ['1']);
    expect(repo.entries.map((e) => e.id), ['1']);
  });

  test('hide dedupes by id (re-hiding same id does not duplicate)', () async {
    final store = InMemoryVaultStore();
    final repo = VaultRepository(store, FakeVaultOps());
    await repo.hide([_v('1')]);
    await repo.hide([_v('1')]);
    expect(repo.entries.length, 1);
  });

  test('unhide removes entries on success, keeps them on failure', () async {
    final store = InMemoryVaultStore();
    final ops = FakeVaultOps();
    final repo = VaultRepository(store, ops);
    final added = await repo.hide([_v('1'), _v('2')]);

    final ok = await repo.unhide([added.first]);
    expect(ok, true);
    expect(repo.entries.map((e) => e.id), ['2']);
    expect(ops.unhidden, ['/vault/1.mp4']);

    ops.unhideResult = false;
    final ok2 = await repo.unhide([added.last]);
    expect(ok2, false);
    expect(repo.entries.map((e) => e.id), ['2']); // unchanged
  });

  test('deleteForever removes entries on success', () async {
    final store = InMemoryVaultStore();
    final ops = FakeVaultOps();
    final repo = VaultRepository(store, ops);
    final added = await repo.hide([_v('1')]);
    final ok = await repo.deleteForever(added);
    expect(ok, true);
    expect(repo.entries, isEmpty);
    expect(ops.deleted, ['/vault/1.mp4']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/vault/vault_repository_test.dart`
Expected: FAIL — `vault_store.dart` / `vault_repository.dart` not found.

- [ ] **Step 3: Write vault_store.dart**

```dart
// lib/vault/vault_store.dart
import 'package:hive/hive.dart';
import 'vault_entry.dart';

/// Persists the list of vaulted videos. One Hive key holds a List<Map>.
abstract class VaultStore {
  List<VaultEntry> readAll();
  Future<void> writeAll(List<VaultEntry> entries);
}

class InMemoryVaultStore implements VaultStore {
  List<VaultEntry> _entries = [];
  @override
  List<VaultEntry> readAll() => List.of(_entries);
  @override
  Future<void> writeAll(List<VaultEntry> entries) async {
    _entries = List.of(entries);
  }
}

class HiveVaultStore implements VaultStore {
  final Box box;
  static const _key = 'entries';
  HiveVaultStore(this.box);

  @override
  List<VaultEntry> readAll() {
    final raw = box.get(_key);
    if (raw == null) return [];
    return (raw as List)
        .map((e) => VaultEntry.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<void> writeAll(List<VaultEntry> entries) =>
      box.put(_key, entries.map((e) => e.toMap()).toList());
}
```

- [ ] **Step 4: Write vault_repository.dart**

```dart
// lib/vault/vault_repository.dart
import '../platform/interfaces/media_indexer.dart';
import '../platform/interfaces/vault_ops.dart';
import 'vault_entry.dart';
import 'vault_store.dart';

/// Orchestrates moving videos in/out of the Vault and keeps the persisted
/// entry list consistent. Pure over [VaultStore] + [VaultOps] — no Riverpod,
/// no side effects beyond the store, so it is fully unit-testable.
class VaultRepository {
  final VaultStore _store;
  final VaultOps _ops;
  List<VaultEntry> _entries;

  VaultRepository(this._store, this._ops) : _entries = _store.readAll();

  List<VaultEntry> get entries => List.of(_entries);

  Future<List<VaultEntry>> hide(List<VideoItem> videos) async {
    final maps = await _ops.hide(videos.map((v) => v.uri).toList());
    final added = maps.map((m) => VaultEntry.fromMap(m)).toList();
    // Dedup by id: new entries win.
    final byId = {for (final e in _entries) e.id: e};
    for (final e in added) {
      byId[e.id] = e;
    }
    _entries = byId.values.toList();
    await _store.writeAll(_entries);
    return added;
  }

  Future<bool> unhide(List<VaultEntry> entries) async {
    final ok = await _ops.unhide(entries.map((e) => e.privatePath).toList());
    if (ok) await _remove(entries);
    return ok;
  }

  Future<bool> deleteForever(List<VaultEntry> entries) async {
    final ok = await _ops.deleteForever(entries.map((e) => e.privatePath).toList());
    if (ok) await _remove(entries);
    return ok;
  }

  Future<void> _remove(List<VaultEntry> gone) async {
    final paths = gone.map((e) => e.privatePath).toSet();
    _entries = _entries.where((e) => !paths.contains(e.privatePath)).toList();
    await _store.writeAll(_entries);
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/vault/vault_repository_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/vault/vault_store.dart lib/vault/vault_repository.dart test/vault/vault_repository_test.dart
git commit -m "feat(vault): VaultStore + VaultRepository (hide/unhide/delete, dedup, reconcile)"
```

---

### Task 5: Vault providers

**Files:**
- Create: `lib/vault/vault_providers.dart`
- Create: `lib/vault/vault_selection.dart`
- Test: `test/vault/vault_selection_test.dart`

**Interfaces:**
- Consumes: `VaultRepository` (Task 4), `vaultOpsProvider` (Task 3), `VaultAuth`+`VaultCredentialStore` (Task 2), `mediaIndexProvider` (`lib/player/library/media_index.dart`).
- Produces (in `vault_providers.dart`):
  - `final vaultStoreProvider = Provider<VaultStore>((ref)=>throw UnimplementedError());` — overridden in main.
  - `final vaultCredentialStoreProvider = Provider<VaultCredentialStore>((ref)=>throw UnimplementedError());` — overridden in main.
  - `final vaultAuthProvider = Provider<VaultAuth>((ref) => VaultAuth(ref.watch(vaultCredentialStoreProvider)));`
  - `final vaultRepositoryProvider = Provider<VaultRepository>((ref) => VaultRepository(ref.watch(vaultStoreProvider), ref.watch(vaultOpsProvider)));`
  - `class VaultEntriesNotifier extends AsyncNotifier<List<VaultEntry>>` with `build()` returning `repo.entries`; `hide(List<VideoItem>)`, `unhide(List<VaultEntry>)`, `deleteForever(List<VaultEntry>)` — each calls the repo, then `state = AsyncData(repo.entries)` and `ref.invalidate(mediaIndexProvider)`.
  - `final vaultEntriesProvider = AsyncNotifierProvider<VaultEntriesNotifier, List<VaultEntry>>(VaultEntriesNotifier.new);`
  - `final vaultUnlockedProvider = StateProvider<bool>((ref) => false);`
- Produces (in `vault_selection.dart`): `VaultSelectionNotifier extends StateNotifier<Set<String>>` keyed by `privatePath`, with `toggle`, `toggleAll`, `selectAll`, `clear`, `isSelected`, `active` — same shape as `LibrarySelectionNotifier`; `final vaultSelectionProvider = StateNotifierProvider<VaultSelectionNotifier, Set<String>>((ref)=>VaultSelectionNotifier());`

- [ ] **Step 1: Write vault_selection.dart**

```dart
// lib/vault/vault_selection.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Vault multi-select: set of selected privatePaths. Mirrors
/// LibrarySelectionNotifier but is a separate provider so the two never
/// entangle.
class VaultSelectionNotifier extends StateNotifier<Set<String>> {
  VaultSelectionNotifier() : super(const {});

  bool isSelected(String path) => state.contains(path);
  bool get active => state.isNotEmpty;

  void toggle(String path) {
    final next = Set<String>.of(state);
    if (!next.remove(path)) next.add(path);
    state = next;
  }

  void toggleAll(Iterable<String> paths) {
    final group = paths.toSet();
    if (group.isEmpty) return;
    final next = Set<String>.of(state);
    if (group.every(next.contains)) {
      next.removeAll(group);
    } else {
      next.addAll(group);
    }
    state = next;
  }

  void selectAll(Iterable<String> paths) => state = paths.toSet();
  void clear() => state = const {};
}

final vaultSelectionProvider =
    StateNotifierProvider<VaultSelectionNotifier, Set<String>>(
        (ref) => VaultSelectionNotifier());
```

- [ ] **Step 2: Write the failing test (selection logic)**

```dart
// test/vault/vault_selection_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/vault/vault_selection.dart';

void main() {
  test('toggle adds then removes; active tracks non-empty', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(vaultSelectionProvider.notifier);
    expect(n.active, false);
    n.toggle('/vault/a.mp4');
    expect(c.read(vaultSelectionProvider), {'/vault/a.mp4'});
    expect(n.active, true);
    n.toggle('/vault/a.mp4');
    expect(n.active, false);
  });

  test('clear empties the selection', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(vaultSelectionProvider.notifier);
    n.selectAll(['/vault/a.mp4', '/vault/b.mp4']);
    expect(c.read(vaultSelectionProvider).length, 2);
    n.clear();
    expect(c.read(vaultSelectionProvider), isEmpty);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/vault/vault_selection_test.dart`
Expected: FAIL — `vault_selection.dart` not found (until Step 1 saved) then PASS; if Step 1 already saved, this verifies it. Run and confirm PASS.

- [ ] **Step 4: Write vault_providers.dart**

```dart
// lib/vault/vault_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../platform/interfaces/media_indexer.dart';
import '../platform/vault_ops_provider.dart';
import '../player/library/media_index.dart';
import 'vault_auth.dart';
import 'vault_entry.dart';
import 'vault_repository.dart';
import 'vault_store.dart';

/// Overridden in main() with a HiveVaultStore.
final vaultStoreProvider = Provider<VaultStore>((ref) {
  throw UnimplementedError('vaultStoreProvider must be overridden');
});

/// Overridden in main() with a Hive-backed credential store.
final vaultCredentialStoreProvider = Provider<VaultCredentialStore>((ref) {
  throw UnimplementedError('vaultCredentialStoreProvider must be overridden');
});

final vaultAuthProvider =
    Provider<VaultAuth>((ref) => VaultAuth(ref.watch(vaultCredentialStoreProvider)));

final vaultRepositoryProvider = Provider<VaultRepository>((ref) =>
    VaultRepository(ref.watch(vaultStoreProvider), ref.watch(vaultOpsProvider)));

/// Whether the vault is currently unlocked this session. Reset on auto-lock.
final vaultUnlockedProvider = StateProvider<bool>((ref) => false);

class VaultEntriesNotifier extends AsyncNotifier<List<VaultEntry>> {
  VaultRepository get _repo => ref.read(vaultRepositoryProvider);

  @override
  Future<List<VaultEntry>> build() async => _repo.entries;

  Future<void> hide(List<VideoItem> videos) async {
    await _repo.hide(videos);
    state = AsyncData(_repo.entries);
    ref.invalidate(mediaIndexProvider);
  }

  Future<bool> unhide(List<VaultEntry> entries) async {
    final ok = await _repo.unhide(entries);
    state = AsyncData(_repo.entries);
    if (ok) ref.invalidate(mediaIndexProvider);
    return ok;
  }

  Future<bool> deleteForever(List<VaultEntry> entries) async {
    final ok = await _repo.deleteForever(entries);
    state = AsyncData(_repo.entries);
    return ok;
  }
}

final vaultEntriesProvider =
    AsyncNotifierProvider<VaultEntriesNotifier, List<VaultEntry>>(
        VaultEntriesNotifier.new);
```

- [ ] **Step 5: Write a provider integration test**

```dart
// append to test/vault/vault_selection_test.dart
import 'package:kivo_player/platform/vault_ops_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/vault/vault_providers.dart';
import 'package:kivo_player/vault/vault_store.dart';
import 'package:kivo_player/vault/vault_entry.dart';
import '../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

// add inside main():
//   test('vaultEntriesProvider.hide persists and exposes entries', () async {...})
```

Full added test:

```dart
  test('vaultEntriesProvider.hide persists and exposes entries', () async {
    final c = ProviderContainer(overrides: [
      vaultOpsProvider.overrideWithValue(FakeVaultOps()),
      vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(const [])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
    ]);
    addTearDown(c.dispose);

    await c.read(vaultEntriesProvider.future);
    await c.read(vaultEntriesProvider.notifier).hide([
      const VideoItem(id: '9', uri: 'content://9', name: '9.mp4', folder: 'F',
          durationMs: 1, sizeBytes: 1, dateAddedMs: 1),
    ]);
    final entries = c.read(vaultEntriesProvider).valueOrNull ?? const <VaultEntry>[];
    expect(entries.single.id, '9');
  });
```

(Add `import 'package:kivo_player/platform/interfaces/media_indexer.dart';` for `VideoItem`.)

- [ ] **Step 6: Run tests**

Run: `flutter test test/vault/vault_selection_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/vault/vault_providers.dart lib/vault/vault_selection.dart test/vault/vault_selection_test.dart
git commit -m "feat(vault): providers (entries AsyncNotifier, auth, repo, selection, unlocked)"
```

---

### Task 6: Settings flags

**Files:**
- Modify: `lib/core/settings/kivo_settings.dart`
- Test: `test/core/settings/kivo_settings_vault_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: three new `bool` fields on `KivoSettings`: `vaultEntranceHidden` (default `false`), `vaultBiometricEnabled` (default `false`), `vaultUninstallWarningShown` (default `false`) — wired into the const ctor, `defaults()`, `copyWith`, `toMap`, `fromMap` exactly like `offeredAllFilesAccess`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/settings/kivo_settings_vault_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('vault flags default to false', () {
    final d = KivoSettings.defaults();
    expect(d.vaultEntranceHidden, false);
    expect(d.vaultBiometricEnabled, false);
    expect(d.vaultUninstallWarningShown, false);
  });

  test('vault flags round-trip through toMap/fromMap and copyWith', () {
    final s = KivoSettings.defaults().copyWith(
      vaultEntranceHidden: true,
      vaultBiometricEnabled: true,
      vaultUninstallWarningShown: true,
    );
    final back = KivoSettings.fromMap(s.toMap());
    expect(back.vaultEntranceHidden, true);
    expect(back.vaultBiometricEnabled, true);
    expect(back.vaultUninstallWarningShown, true);
  });

  test('fromMap on legacy map (no vault keys) yields false defaults', () {
    final legacy = KivoSettings.defaults().toMap()
      ..remove('vaultEntranceHidden')
      ..remove('vaultBiometricEnabled')
      ..remove('vaultUninstallWarningShown');
    final back = KivoSettings.fromMap(legacy);
    expect(back.vaultEntranceHidden, false);
    expect(back.vaultBiometricEnabled, false);
    expect(back.vaultUninstallWarningShown, false);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/settings/kivo_settings_vault_test.dart`
Expected: FAIL — `vaultEntranceHidden` getter not defined.

- [ ] **Step 3: Add the fields**

In `lib/core/settings/kivo_settings.dart`, in five places (mirror `offeredAllFilesAccess`):

1. Field declarations (after `final bool offeredAllFilesAccess;`):
```dart
  final bool vaultEntranceHidden;
  final bool vaultBiometricEnabled;
  final bool vaultUninstallWarningShown;
```
2. Const ctor params (after `required this.offeredAllFilesAccess,`):
```dart
    required this.vaultEntranceHidden,
    required this.vaultBiometricEnabled,
    required this.vaultUninstallWarningShown,
```
3. `defaults()` (after `offeredAllFilesAccess: false,`):
```dart
        vaultEntranceHidden: false,
        vaultBiometricEnabled: false,
        vaultUninstallWarningShown: false,
```
4. `copyWith` params (after `bool? offeredAllFilesAccess,`):
```dart
    bool? vaultEntranceHidden,
    bool? vaultBiometricEnabled,
    bool? vaultUninstallWarningShown,
```
   and body (after `offeredAllFilesAccess: offeredAllFilesAccess ?? this.offeredAllFilesAccess,`):
```dart
      vaultEntranceHidden: vaultEntranceHidden ?? this.vaultEntranceHidden,
      vaultBiometricEnabled: vaultBiometricEnabled ?? this.vaultBiometricEnabled,
      vaultUninstallWarningShown: vaultUninstallWarningShown ?? this.vaultUninstallWarningShown,
```
5. `toMap` (after `'offeredAllFilesAccess': offeredAllFilesAccess,`):
```dart
        'vaultEntranceHidden': vaultEntranceHidden,
        'vaultBiometricEnabled': vaultBiometricEnabled,
        'vaultUninstallWarningShown': vaultUninstallWarningShown,
```
6. `fromMap` (after `offeredAllFilesAccess: m['offeredAllFilesAccess'] ?? d.offeredAllFilesAccess,`):
```dart
      vaultEntranceHidden: m['vaultEntranceHidden'] ?? d.vaultEntranceHidden,
      vaultBiometricEnabled: m['vaultBiometricEnabled'] ?? d.vaultBiometricEnabled,
      vaultUninstallWarningShown: m['vaultUninstallWarningShown'] ?? d.vaultUninstallWarningShown,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/settings/kivo_settings_vault_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/settings/kivo_settings.dart test/core/settings/kivo_settings_vault_test.dart
git commit -m "feat(vault): KivoSettings vault flags (entranceHidden, biometricEnabled, uninstallWarningShown)"
```

---

### Task 7: Native ops + FlutterFragmentActivity + main.dart wiring

**Files:**
- Create: `lib/platform/android/android_vault_ops.dart`
- Modify: `android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt`
- Modify: `lib/main.dart`
- Modify: `pubspec.yaml` (add `local_auth: ^2.3.0`)

**Interfaces:**
- Consumes: `VaultOps` (Task 3), `vaultOpsProvider`/`vaultStoreProvider`/`vaultCredentialStoreProvider` (Tasks 3,5), `HiveVaultStore` (Task 4), `VaultCredentialStore` (Task 2).
- Produces: `class AndroidVaultOps implements VaultOps` (MethodChannel `kivo/vault`); `class HiveVaultCredentialStore implements VaultCredentialStore`; `main.dart` opens `vault` + `vaultCreds` Hive boxes and overrides the three providers.

This task is native + wiring; it is verified by a release build + manual smoke test (no unit test). Its deliverable: the app builds, launches, and existing channels still work after the `FlutterFragmentActivity` change.

- [ ] **Step 1: Add local_auth dependency**

`pubspec.yaml` under `dependencies:`:
```yaml
  local_auth: ^2.3.0
```
Run: `flutter pub get`

- [ ] **Step 2: Write AndroidVaultOps**

```dart
// lib/platform/android/android_vault_ops.dart
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../interfaces/vault_ops.dart';

class AndroidVaultOps implements VaultOps {
  static const MethodChannel _channel = MethodChannel('kivo/vault');

  @override
  Future<List<Map<String, dynamic>>> hide(List<String> uris) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('hide', {'uris': uris}) ?? const [];
      return raw.map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<bool> unhide(List<String> privatePaths) async {
    try {
      final s = await _channel.invokeMethod<String>('unhide', {'paths': privatePaths});
      return s == 'ok';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> deleteForever(List<String> privatePaths) async {
    try {
      final s = await _channel.invokeMethod<String>('deleteForever', {'paths': privatePaths});
      return s == 'ok';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List?> thumbnail(String privatePath) async {
    try {
      return await _channel.invokeMethod<Uint8List>('thumbnail', {'path': privatePath});
    } catch (_) {
      return null;
    }
  }
}
```

- [ ] **Step 3: Change MainActivity base class**

In `MainActivity.kt`, change the import and class declaration:
```kotlin
// was: import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterFragmentActivity
// ...
class MainActivity : FlutterFragmentActivity() {
```

- [ ] **Step 4: Register the kivo/vault channel handler**

In `MainActivity.configureFlutterEngine` (alongside the `kivo/media` handler registration), add a new channel. The vault dir is `getExternalFilesDir(null)/vault`. Use these handlers (Kotlin):

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kivo/vault")
    .setMethodCallHandler { call, result ->
        when (call.method) {
            "hide" -> {
                val uris = call.argument<List<String>>("uris")
                if (uris == null) { result.error("INVALID_ARG", "uris required", null); return@setMethodCallHandler }
                ioExecutor.execute {
                    val out = ArrayList<HashMap<String, Any>>()
                    val vaultDir = File(getExternalFilesDir(null), "vault").apply { mkdirs() }
                    for (uriStr in uris) {
                        try {
                            val u = Uri.parse(uriStr)
                            val proj = arrayOf(
                                MediaStore.Video.Media._ID,
                                MediaStore.Video.Media.DISPLAY_NAME,
                                MediaStore.Video.Media.DATA,
                                MediaStore.Video.Media.RELATIVE_PATH,
                                MediaStore.Video.Media.DURATION,
                                MediaStore.Video.Media.SIZE,
                                MediaStore.Video.Media.DATE_ADDED,
                                MediaStore.Video.Media.WIDTH,
                                MediaStore.Video.Media.HEIGHT,
                            )
                            contentResolver.query(u, proj, null, null, null)?.use { c ->
                                if (!c.moveToFirst()) return@use
                                val id = c.getString(c.getColumnIndexOrThrow(MediaStore.Video.Media._ID))
                                val name = c.getString(c.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)) ?: "$id"
                                val data = c.getColumnIndex(MediaStore.Video.Media.DATA).let { if (it >= 0) c.getString(it) else null }
                                val rel = c.getColumnIndex(MediaStore.Video.Media.RELATIVE_PATH).let { if (it >= 0) (c.getString(it) ?: "") else "" }
                                val dur = c.getLong(c.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION))
                                val size = c.getLong(c.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE))
                                val date = c.getLong(c.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)) * 1000L
                                val w = c.getColumnIndex(MediaStore.Video.Media.WIDTH).let { if (it >= 0) c.getInt(it) else 0 }
                                val h = c.getColumnIndex(MediaStore.Video.Media.HEIGHT).let { if (it >= 0) c.getInt(it) else 0 }
                                val ext = name.substringAfterLast('.', "mp4")
                                val dest = File(vaultDir, "$id.$ext")
                                var moved = false
                                if (data != null) {
                                    val src = File(data)
                                    moved = src.renameTo(dest) || run {
                                        src.copyTo(dest, overwrite = true); src.delete()
                                    }
                                }
                                if (!moved && data == null) {
                                    // no filesystem path (rare): stream-copy then delete row
                                    contentResolver.openInputStream(u)?.use { input ->
                                        dest.outputStream().use { input.copyTo(it) }
                                    }
                                    moved = dest.exists()
                                }
                                if (moved) {
                                    try { contentResolver.delete(u, null, null) } catch (_: Exception) {}
                                    out.add(hashMapOf(
                                        "id" to id, "privatePath" to dest.absolutePath,
                                        "displayName" to name, "originalRelativePath" to rel,
                                        "durationMs" to dur, "sizeBytes" to size, "dateAddedMs" to date,
                                        "width" to w, "height" to h,
                                    ))
                                }
                            }
                        } catch (_: Exception) { /* skip this uri */ }
                    }
                    runOnUiThread { result.success(out) }
                }
            }
            "unhide" -> {
                val paths = call.argument<List<String>>("paths")
                if (paths == null) { result.error("INVALID_ARG", "paths required", null); return@setMethodCallHandler }
                ioExecutor.execute {
                    var allOk = true
                    for (p in paths) {
                        try {
                            val src = File(p)
                            if (!src.exists()) { allOk = false; continue }
                            val values = android.content.ContentValues().apply {
                                put(MediaStore.Video.Media.DISPLAY_NAME, src.name)
                                put(MediaStore.Video.Media.MIME_TYPE, "video/*")
                                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/")
                                put(MediaStore.Video.Media.IS_PENDING, 1)
                            }
                            val col = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                            val dest = contentResolver.insert(col, values)
                            if (dest == null) { allOk = false; continue }
                            contentResolver.openOutputStream(dest)?.use { out -> src.inputStream().use { it.copyTo(out) } }
                            values.clear(); values.put(MediaStore.Video.Media.IS_PENDING, 0)
                            contentResolver.update(dest, values, null, null)
                            src.delete()
                        } catch (_: Exception) { allOk = false }
                    }
                    runOnUiThread { result.success(if (allOk) "ok" else "error") }
                }
            }
            "deleteForever" -> {
                val paths = call.argument<List<String>>("paths")
                if (paths == null) { result.error("INVALID_ARG", "paths required", null); return@setMethodCallHandler }
                ioExecutor.execute {
                    var allOk = true
                    for (p in paths) { try { if (!File(p).delete()) allOk = false } catch (_: Exception) { allOk = false } }
                    runOnUiThread { result.success(if (allOk) "ok" else "error") }
                }
            }
            "thumbnail" -> {
                val path = call.argument<String>("path")
                if (path == null) { result.error("INVALID_ARG", "path required", null); return@setMethodCallHandler }
                ioExecutor.execute {
                    var bytes: ByteArray? = null
                    try {
                        val mmr = android.media.MediaMetadataRetriever()
                        mmr.setDataSource(path)
                        val bmp = mmr.getFrameAtTime(1_000_000, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                        mmr.release()
                        if (bmp != null) {
                            val scaled = Bitmap.createScaledBitmap(bmp, 320, (320.0 * bmp.height / bmp.width).toInt().coerceAtLeast(1), true)
                            val bos = java.io.ByteArrayOutputStream()
                            scaled.compress(Bitmap.CompressFormat.JPEG, 80, bos)
                            bytes = bos.toByteArray()
                        }
                    } catch (_: Exception) {}
                    runOnUiThread { result.success(bytes) }
                }
            }
            else -> result.notImplemented()
        }
    }
```

Note: `File`, `Uri`, `MediaStore`, `Bitmap`, `ioExecutor` are already imported/available in this file (used by the `kivo/media` handler). If `ContentValues` needs an import, use the fully-qualified `android.content.ContentValues` as above.

- [ ] **Step 5: Wire main.dart**

Add imports:
```dart
import 'vault/vault_store.dart';
import 'vault/vault_auth.dart';
import 'vault/vault_providers.dart';
import 'platform/vault_ops_provider.dart';
import 'platform/android/android_vault_ops.dart';
```
Add a Hive-backed credential store class (in `lib/vault/vault_auth.dart`, so it lives with its interface — add to Task 2's file, but wiring happens here):

```dart
// lib/vault/vault_auth.dart — append
import 'package:hive/hive.dart';

class HiveVaultCredentialStore implements VaultCredentialStore {
  final Box box;
  HiveVaultCredentialStore(this.box);
  @override
  String? get hash => box.get('hash') as String?;
  @override
  String? get salt => box.get('salt') as String?;
  @override
  Future<void> save(String hash, String salt) async {
    await box.put('hash', hash);
    await box.put('salt', salt);
  }
  @override
  Future<void> clear() async {
    await box.delete('hash');
    await box.delete('salt');
  }
}
```

In `main()` after `final playedBox = await Hive.openBox('played');`:
```dart
  final vaultBox = await Hive.openBox('vault');
  final vaultCredsBox = await Hive.openBox('vaultCreds');
```
In the `overrides:` list (after `allFilesAccessProvider...`):
```dart
      vaultOpsProvider.overrideWithValue(AndroidVaultOps()),
      vaultStoreProvider.overrideWithValue(HiveVaultStore(vaultBox)),
      vaultCredentialStoreProvider.overrideWithValue(HiveVaultCredentialStore(vaultCredsBox)),
```

- [ ] **Step 6: Analyze + build to verify wiring**

Run: `flutter analyze lib/main.dart lib/platform/android/android_vault_ops.dart lib/vault/vault_auth.dart`
Expected: No issues.
Run: `flutter build apk --release`
Expected: `√ Built build\app\outputs\flutter-apk\app-release.apk`.

- [ ] **Step 7: Smoke-test existing channels (regression from FlutterFragmentActivity)**

Install and launch; confirm the library scans (kivo/media), a video plays (engine + pip/session channels bind), volume keys work. If any channel silently fails, the base-class change is the suspect.

Run: `"$LOCALAPPDATA/Android/sdk/platform-tools/adb.exe" -s 24231FDF6006ST install -r build/app/outputs/flutter-apk/app-release.apk`

- [ ] **Step 8: Commit**

```bash
git add lib/platform/android/android_vault_ops.dart android/app/src/main/kotlin/dev/selector/kivo_player/MainActivity.kt lib/main.dart lib/vault/vault_auth.dart pubspec.yaml pubspec.lock
git commit -m "feat(vault): native kivo/vault ops, FlutterFragmentActivity, main wiring, local_auth"
```

---

### Task 8: Biometric interface + PIN pad + Vault gate

**Files:**
- Create: `lib/platform/interfaces/biometric_auth.dart`
- Create: `lib/platform/android/local_auth_biometric.dart`
- Create: `lib/platform/biometric_auth_provider.dart`
- Create: `lib/ui/vault/pin_pad.dart`
- Create: `lib/ui/vault/vault_gate.dart`
- Modify: `lib/main.dart` (override `biometricAuthProvider`)
- Modify: `test/fakes/fakes.dart` (append `FakeBiometricAuth`)
- Test: `test/ui/vault/vault_gate_test.dart`

**Interfaces:**
- Consumes: `vaultAuthProvider`, `vaultUnlockedProvider` (Task 5), `settingsProvider` (`vaultBiometricEnabled`) (Task 6).
- Produces:
  - `abstract class BiometricAuth { Future<bool> isAvailable(); Future<bool> authenticate(String reason); }`
  - `class LocalAuthBiometric implements BiometricAuth` (wraps `LocalAuthentication`).
  - `final biometricAuthProvider = Provider<BiometricAuth>((ref)=>throw UnimplementedError());`
  - `class FakeBiometricAuth implements BiometricAuth { bool available; bool willSucceed; ... }`.
  - `PinPad` widget: numeric 0-9 + backspace, `onComplete(String pin)` fired at [length] digits; `title` + optional `error` text; `length` default 4.
  - `VaultGate` widget: on mount, if `isConfigured` && `vaultBiometricEnabled` && biometric available → auto `authenticate`; on success set `vaultUnlockedProvider=true` and show `child`. Otherwise show `PinPad`. If NOT configured → show set-PIN flow (enter twice). Wrong PIN → error, stays locked. `VaultGate({required Widget child})`.

- [ ] **Step 1: Write interfaces + provider + fake**

```dart
// lib/platform/interfaces/biometric_auth.dart
abstract class BiometricAuth {
  Future<bool> isAvailable();
  Future<bool> authenticate(String reason);
}
```
```dart
// lib/platform/android/local_auth_biometric.dart
import 'package:local_auth/local_auth.dart';
import '../interfaces/biometric_auth.dart';

class LocalAuthBiometric implements BiometricAuth {
  final LocalAuthentication _auth = LocalAuthentication();
  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }
  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );
    } catch (_) {
      return false;
    }
  }
}
```
```dart
// lib/platform/biometric_auth_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/biometric_auth.dart';

final biometricAuthProvider = Provider<BiometricAuth>((ref) {
  throw UnimplementedError('biometricAuthProvider must be overridden');
});
```
```dart
// test/fakes/fakes.dart — append (add import 'package:kivo_player/platform/interfaces/biometric_auth.dart';)
class FakeBiometricAuth implements BiometricAuth {
  bool available;
  bool willSucceed;
  int authCalls = 0;
  FakeBiometricAuth({this.available = true, this.willSucceed = true});
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> authenticate(String reason) async {
    authCalls++;
    return willSucceed;
  }
}
```

- [ ] **Step 2: Write PinPad**

```dart
// lib/ui/vault/pin_pad.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Numeric PIN entry. Calls [onComplete] when [length] digits are entered,
/// then clears itself so the parent can show an error and let the user retry.
class PinPad extends StatefulWidget {
  final String title;
  final String? error;
  final int length;
  final ValueChanged<String> onComplete;
  const PinPad({
    super.key,
    required this.title,
    required this.onComplete,
    this.error,
    this.length = 4,
  });

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  void _tap(String d) {
    if (_pin.length >= widget.length) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == widget.length) {
      final done = _pin;
      _pin = '';
      widget.onComplete(done);
    }
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title, style: TextStyle(color: cs.onSurface, fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.length, (i) {
            final filled = i < _pin.length;
            return Container(
              key: Key('pin-dot-$i'),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 14, height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? cs.secondary : Colors.transparent,
                border: Border.all(color: cs.secondary, width: 2),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 20,
          child: widget.error == null
              ? null
              : Text(widget.error!, style: TextStyle(color: cs.error, fontSize: 13)),
        ),
        const SizedBox(height: 12),
        for (final row in const [['1','2','3'],['4','5','6'],['7','8','9']])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) _key(cs, d)],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 76),
            _key(cs, '0'),
            SizedBox(
              width: 76,
              child: IconButton(
                key: const Key('pin-backspace'),
                icon: Icon(Icons.backspace_outlined, color: cs.onSurfaceVariant),
                onPressed: _back,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _key(ColorScheme cs, String d) => SizedBox(
        width: 76, height: 66,
        child: InkWell(
          key: Key('pin-key-$d'),
          borderRadius: BorderRadius.circular(40),
          onTap: () => _tap(d),
          child: Center(child: Text(d, style: TextStyle(color: cs.onSurface, fontSize: 26, fontWeight: FontWeight.w500))),
        ),
      );
}
```

- [ ] **Step 3: Write the failing widget test for VaultGate**

```dart
// test/ui/vault/vault_gate_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/biometric_auth_provider.dart';
import 'package:kivo_player/vault/vault_providers.dart';
import 'package:kivo_player/vault/vault_auth.dart';
import 'package:kivo_player/ui/vault/vault_gate.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _container({
  required bool biometricEnabled,
  required FakeBiometricAuth bio,
  bool pinConfigured = true,
}) async {
  final creds = InMemoryVaultCredentialStore();
  if (pinConfigured) await VaultAuth(creds).setPin('1234');
  final store = InMemorySettingsStore();
  final svc = await SettingsService.load(store);
  await svc.update(svc.current.copyWith(vaultBiometricEnabled: biometricEnabled));
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    vaultCredentialStoreProvider.overrideWithValue(creds),
    biometricAuthProvider.overrideWithValue(bio),
  ]);
}

Widget _app(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: KivoTheme.dark(),
        home: const VaultGate(child: Text('VAULT-CONTENT')),
      ),
    );

void main() {
  testWidgets('biometric success unlocks and shows the child', (tester) async {
    final bio = FakeBiometricAuth(available: true, willSucceed: true);
    final c = await _container(biometricEnabled: true, bio: bio);
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    expect(bio.authCalls, 1);
    expect(find.text('VAULT-CONTENT'), findsOneWidget);
    expect(c.read(vaultUnlockedProvider), true);
  });

  testWidgets('biometric failure falls back to the PIN pad', (tester) async {
    final bio = FakeBiometricAuth(available: true, willSucceed: false);
    final c = await _container(biometricEnabled: true, bio: bio);
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    expect(find.text('VAULT-CONTENT'), findsNothing);
    expect(find.byKey(const Key('pin-key-1')), findsOneWidget);
  });

  testWidgets('correct PIN unlocks; wrong PIN stays locked', (tester) async {
    final bio = FakeBiometricAuth(available: false);
    final c = await _container(biometricEnabled: false, bio: bio);
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();

    // wrong
    for (final d in ['9','9','9','9']) {
      await tester.tap(find.byKey(Key('pin-key-$d')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('VAULT-CONTENT'), findsNothing);

    // right
    for (final d in ['1','2','3','4']) {
      await tester.tap(find.byKey(Key('pin-key-$d')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('VAULT-CONTENT'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/ui/vault/vault_gate_test.dart`
Expected: FAIL — `vault_gate.dart` not found.

- [ ] **Step 5: Write VaultGate**

```dart
// lib/ui/vault/vault_gate.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/biometric_auth_provider.dart';
import '../../vault/vault_auth.dart';
import '../../vault/vault_providers.dart';
import 'pin_pad.dart';

/// Auth barrier. Shows [child] only once unlocked. First run: set a PIN (twice).
/// Returning run: biometric auto-prompt (if enabled+available) with PIN fallback.
/// Re-locks when this route is left or the app is backgrounded.
class VaultGate extends ConsumerStatefulWidget {
  final Widget child;
  const VaultGate({super.key, required this.child});
  @override
  ConsumerState<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends ConsumerState<VaultGate> with WidgetsBindingObserver {
  String? _error;
  String? _firstPin; // set-PIN flow: holds the first entry
  bool _biometricTried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Fresh mount = locked (each openVault pushes a new gate, so re-entry
      // always re-authenticates). Reset in a post-frame, NOT in build/dispose:
      // writing provider state during build throws, and ref in dispose is a
      // known footgun in this codebase.
      ref.read(vaultUnlockedProvider.notifier).state = false;
      _maybeBiometric();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      ref.read(vaultUnlockedProvider.notifier).state = false;
    }
  }

  Future<void> _maybeBiometric() async {
    if (_biometricTried) return;
    _biometricTried = true;
    final auth = ref.read(vaultAuthProvider);
    if (!auth.isConfigured) return; // set-PIN flow instead
    final enabled = ref.read(settingsProvider).vaultBiometricEnabled;
    if (!enabled) return;
    final bio = ref.read(biometricAuthProvider);
    if (!await bio.isAvailable()) return;
    final ok = await bio.authenticate('Desbloquea el Vault');
    if (ok && mounted) {
      ref.read(vaultUnlockedProvider.notifier).state = true;
    }
  }

  void _submitPin(String pin) {
    final auth = ref.read(vaultAuthProvider);
    if (auth.verify(pin)) {
      ref.read(vaultUnlockedProvider.notifier).state = true;
    } else {
      setState(() => _error = 'PIN incorrecto');
    }
  }

  Future<void> _submitSetPin(String pin) async {
    if (_firstPin == null) {
      setState(() { _firstPin = pin; _error = null; });
      return;
    }
    if (_firstPin != pin) {
      setState(() { _firstPin = null; _error = 'Los PIN no coinciden'; });
      return;
    }
    await ref.read(vaultAuthProvider).setPin(pin);
    if (mounted) ref.read(vaultUnlockedProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = ref.watch(vaultUnlockedProvider);
    if (unlocked) return widget.child;

    final auth = ref.watch(vaultAuthProvider);
    final configuring = !auth.isConfigured;
    final title = configuring
        ? (_firstPin == null ? 'Crea un PIN para el Vault' : 'Repite el PIN')
        : 'Introduce tu PIN';

    return Scaffold(
      appBar: AppBar(title: const Text('Vault')),
      body: Center(
        child: PinPad(
          title: title,
          error: _error,
          onComplete: configuring ? _submitSetPin : _submitPin,
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/ui/vault/vault_gate_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 7: Override biometricAuthProvider in main.dart**

Add import `import 'platform/android/local_auth_biometric.dart';` and `import 'platform/biometric_auth_provider.dart';`; add to overrides:
```dart
      biometricAuthProvider.overrideWithValue(LocalAuthBiometric()),
```

- [ ] **Step 8: Commit**

```bash
git add lib/platform/interfaces/biometric_auth.dart lib/platform/android/local_auth_biometric.dart lib/platform/biometric_auth_provider.dart lib/ui/vault/pin_pad.dart lib/ui/vault/vault_gate.dart lib/main.dart test/fakes/fakes.dart test/ui/vault/vault_gate_test.dart
git commit -m "feat(vault): biometric interface, PIN pad, VaultGate (auth + set-PIN + auto-lock)"
```

---

### Task 9: Vault screen + VaultBottomBar

**Files:**
- Create: `lib/ui/vault/vault_screen.dart`
- Create: `lib/ui/vault/widgets/vault_bottom_bar.dart`
- Create: `lib/ui/vault/widgets/vault_thumbnail.dart`
- Test: `test/ui/vault/vault_bottom_bar_test.dart`

**Interfaces:**
- Consumes: `vaultEntriesProvider`, `vaultSelectionProvider`, `vaultOpsProvider` (Tasks 3,5), `VaultEntry` (Task 1), `currentVideoProvider`/`VideoSession` (`lib/player/open/video_source.dart`), `playerRoute` (`lib/ui/player/player_route.dart`).
- Produces:
  - `VaultThumbnail({required String path})` — `FutureBuilder` on `vaultOpsProvider.thumbnail(path)`, memory image or a placeholder icon.
  - `VaultBottomBar` — `ConsumerWidget`; resolves selected entries = `entries ∩ vaultSelectionProvider`; two actions: **Sacar del Vault** (`Icons.lock_open_outlined`) → `vaultEntriesProvider.notifier.unhide(chosen)` + SnackBar + clear; **Borrar del teléfono** (`Icons.delete_forever_outlined`, `cs.error`) → confirm dialog → `deleteForever(chosen)` + SnackBar + clear.
  - `VaultScreen` — `ConsumerWidget`; wraps `VaultGate`; body = grid of entries (tap → play a vault-only session; long-press → select); `bottomNavigationBar` = `VaultBottomBar` when selecting; empty-state text when no entries.

- [ ] **Step 1: Write VaultThumbnail + VaultScreen + VaultBottomBar**

```dart
// lib/ui/vault/widgets/vault_thumbnail.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/vault_ops_provider.dart';

class VaultThumbnail extends ConsumerWidget {
  final String path;
  const VaultThumbnail({super.key, required this.path});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder(
      future: ref.read(vaultOpsProvider).thumbnail(path),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return Container(
            color: cs.surfaceContainerHighest,
            child: Icon(Icons.movie_outlined, color: cs.onSurfaceVariant),
          );
        }
        return Image.memory(bytes, fit: BoxFit.cover);
      },
    );
  }
}
```

```dart
// lib/ui/vault/widgets/vault_bottom_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../vault/vault_entry.dart';
import '../../../vault/vault_providers.dart';
import '../../../vault/vault_selection.dart';

/// Bottom action bar shown while selecting inside the Vault. Mirrors
/// SelectionBottomBar (thumb-reachable). Delete-forever keeps a confirmation
/// because it is irreversible.
class VaultBottomBar extends ConsumerWidget {
  const VaultBottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(vaultSelectionProvider);
    final sel = ref.read(vaultSelectionProvider.notifier);
    final entries = ref.watch(vaultEntriesProvider).valueOrNull ?? const <VaultEntry>[];
    final chosen = entries.where((e) => selected.contains(e.privatePath)).toList();
    final cs = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final enabled = chosen.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _action(cs.onSurface, Icons.lock_open_outlined, 'Sacar del Vault', enabled ? () async {
                final ok = await ref.read(vaultEntriesProvider.notifier).unhide(chosen);
                sel.clear();
                messenger.showSnackBar(SnackBar(content: Text(
                    ok ? '${chosen.length} devueltos a la galería' : 'No se pudieron sacar todos')));
              } : null),
              _action(cs.error, Icons.delete_forever_outlined, 'Borrar del teléfono', enabled ? () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Borrar del teléfono'),
                    content: Text('¿Borrar ${chosen.length} videos para siempre? No se pueden recuperar.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Borrar', style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
                    ],
                  ),
                );
                if (ok != true) return;
                final done = await ref.read(vaultEntriesProvider.notifier).deleteForever(chosen);
                sel.clear();
                messenger.showSnackBar(SnackBar(content: Text(
                    done ? '${chosen.length} borrados' : 'No se pudieron borrar todos')));
              } : null),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(Color color, IconData icon, String label, VoidCallback? onTap) {
    final c = onTap == null ? color.withValues(alpha: 0.4) : color;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: c),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 11, color: c)),
          ],
        ),
      ),
    );
  }
}
```

```dart
// lib/ui/vault/vault_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../player/open/video_source.dart';
import '../player/player_route.dart';
import '../../vault/vault_entry.dart';
import '../../vault/vault_providers.dart';
import '../../vault/vault_selection.dart';
import 'vault_gate.dart';
import 'widgets/vault_bottom_bar.dart';
import 'widgets/vault_thumbnail.dart';

class VaultScreen extends ConsumerWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const VaultGate(child: _VaultContent());
  }
}

class _VaultContent extends ConsumerWidget {
  const _VaultContent();

  void _play(BuildContext context, WidgetRef ref, List<VaultEntry> all, int index) {
    final e = all[index];
    ref.read(currentVideoProvider.notifier).open(VideoSession(
          playbackPath: e.privatePath,
          displayName: e.displayName,
          queue: all.map((v) => v.privatePath).toList(),
          queueNames: all.map((v) => v.displayName).toList(),
          index: index,
        ));
    Navigator.of(context, rootNavigator: true).push(playerRoute());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(vaultEntriesProvider).valueOrNull ?? const <VaultEntry>[];
    final selected = ref.watch(vaultSelectionProvider);
    final selecting = selected.isNotEmpty;
    final sel = ref.read(vaultSelectionProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(selecting ? '${selected.length}' : 'Vault'),
        leading: selecting
            ? IconButton(icon: const Icon(Icons.close), onPressed: sel.clear)
            : null,
      ),
      bottomNavigationBar: selecting ? const VaultBottomBar() : null,
      body: entries.isEmpty
          ? Center(child: Text('Vault vacío', style: TextStyle(color: cs.onSurfaceVariant)))
          : GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 16 / 10),
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                final isSel = selected.contains(e.privatePath);
                return GestureDetector(
                  onTap: () {
                    if (selecting) {
                      HapticFeedback.selectionClick();
                      sel.toggle(e.privatePath);
                    } else {
                      _play(context, ref, entries, i);
                    }
                  },
                  onLongPress: () {
                    HapticFeedback.selectionClick();
                    sel.toggle(e.privatePath);
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(10), child: VaultThumbnail(path: e.privatePath)),
                      if (isSel)
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: cs.secondary.withValues(alpha: 0.35),
                            border: Border.all(color: cs.secondary, width: 2),
                          ),
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(Icons.check_circle, color: cs.secondary),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
```

- [ ] **Step 2: Write the failing test for VaultBottomBar**

```dart
// test/ui/vault/vault_bottom_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/vault_ops_provider.dart';
import 'package:kivo_player/vault/vault_providers.dart';
import 'package:kivo_player/vault/vault_store.dart';
import 'package:kivo_player/vault/vault_selection.dart';
import 'package:kivo_player/ui/vault/widgets/vault_bottom_bar.dart';
import '../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override Future<MediaAccess> status() async => MediaAccess.granted;
  @override Future<MediaAccess> request() async => MediaAccess.granted;
}

void main() {
  testWidgets('Sacar del Vault calls unhide for the selected entries', (tester) async {
    final ops = FakeVaultOps();
    final c = ProviderContainer(overrides: [
      vaultOpsProvider.overrideWithValue(ops),
      vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(const [])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
    ]);
    addTearDown(c.dispose);
    await c.read(vaultEntriesProvider.future);
    await c.read(vaultEntriesProvider.notifier).hide([
      const VideoItem(id: '1', uri: 'content://1', name: '1.mp4', folder: 'F', durationMs: 1, sizeBytes: 1, dateAddedMs: 1),
    ]);
    c.read(vaultSelectionProvider.notifier).selectAll(['/vault/1.mp4']);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(bottomNavigationBar: VaultBottomBar())),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.lock_open_outlined));
    await tester.pump();
    expect(ops.unhidden, ['/vault/1.mp4']);
  });

  testWidgets('Borrar del teléfono confirms then calls deleteForever', (tester) async {
    final ops = FakeVaultOps();
    final c = ProviderContainer(overrides: [
      vaultOpsProvider.overrideWithValue(ops),
      vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(const [])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
    ]);
    addTearDown(c.dispose);
    await c.read(vaultEntriesProvider.future);
    await c.read(vaultEntriesProvider.notifier).hide([
      const VideoItem(id: '2', uri: 'content://2', name: '2.mp4', folder: 'F', durationMs: 1, sizeBytes: 1, dateAddedMs: 1),
    ]);
    c.read(vaultSelectionProvider.notifier).selectAll(['/vault/2.mp4']);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(bottomNavigationBar: VaultBottomBar())),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_forever_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar'));
    await tester.pump();
    expect(ops.deleted, ['/vault/2.mp4']);
  });
}
```

- [ ] **Step 3: Run test to verify it fails then passes**

Run: `flutter test test/ui/vault/vault_bottom_bar_test.dart`
Expected: FAIL first (files missing), then after Step 1 saved, PASS (2 tests).

- [ ] **Step 4: Commit**

```bash
git add lib/ui/vault/vault_screen.dart lib/ui/vault/widgets/vault_bottom_bar.dart lib/ui/vault/widgets/vault_thumbnail.dart test/ui/vault/vault_bottom_bar_test.dart
git commit -m "feat(vault): VaultScreen grid + VaultBottomBar (unhide / delete-forever)"
```

---

### Task 10: Integration — Settings row, reveal gesture, "Mover al Vault"

**Files:**
- Modify: `lib/ui/settings/settings_screen.dart`
- Modify: `lib/ui/home/library_screen.dart`
- Modify: `lib/ui/home/widgets/selection_bottom_bar.dart`
- Modify: `lib/ui/home/widgets/video_options_sheet.dart`
- Create: `lib/ui/vault/vault_entry_actions.dart` (shared "move to vault" helper + uninstall warning + open-gate helper)
- Test: `test/ui/settings/settings_vault_row_test.dart`
- Test: `test/ui/home/library_reveal_gesture_test.dart`

**Interfaces:**
- Consumes: `settingsProvider` (`vaultEntranceHidden`, `vaultUninstallWarningShown`), `vaultEntriesProvider`, `VaultScreen`.
- Produces:
  - `openVault(BuildContext, {rootNavigator})` helper that pushes `const VaultScreen()`.
  - `moveToVault(BuildContext, WidgetRef, List<VideoItem>)` — shows the one-time uninstall warning (gated on `vaultUninstallWarningShown`), then `vaultEntriesProvider.notifier.hide(videos)`, SnackBar.
  - Settings: a `SettingNavRow` "Vault" (icon `Icons.lock_outline`) rendered only when `!vaultEntranceHidden`, navigating via `openVault`.
  - Library: the `'Kivo'` title `Text` (key `ValueKey('title')`) wrapped so a long-press calls `openVault`.
  - `SelectionBottomBar`: a third action **"Mover al Vault"** (`Icons.lock_outline`) → `moveToVault(chosen)` + `sel.clear()`.
  - `video_options_sheet`: a **"Mover al Vault"** row → `moveToVault([v])`.

- [ ] **Step 1: Write vault_entry_actions.dart**

```dart
// lib/ui/vault/vault_entry_actions.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../vault/vault_providers.dart';
import 'vault_screen.dart';

void openVault(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VaultScreen()));
}

/// Moves [videos] into the Vault. Shows a one-time uninstall warning first.
Future<void> moveToVault(BuildContext context, WidgetRef ref, List<VideoItem> videos) async {
  if (videos.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final settings = ref.read(settingsProvider);
  if (!settings.vaultUninstallWarningShown) {
    await ref.read(settingsProvider.notifier)
        .set(settings.copyWith(vaultUninstallWarningShown: true));
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Antes de ocultar'),
        content: const Text(
            'Los videos del Vault viven dentro de Kivo. Si desinstalas la app se '
            'pierden. Sácalos del Vault para devolverlos a tu galería.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
      ),
    );
  }
  await ref.read(vaultEntriesProvider.notifier).hide(videos);
  messenger.showSnackBar(SnackBar(content: Text('${videos.length} movidos al Vault')));
}
```

- [ ] **Step 2: Settings row + test**

In `settings_screen.dart` make `SettingsScreen` read settings and conditionally add the row. Add `import '../vault/vault_entry_actions.dart';`. Inside the first `SettingsCard(children: [...])`, after the "Acerca de" row, insert:
```dart
            if (!ref.watch(settingsProvider).vaultEntranceHidden)
              SettingNavRow(
                icon: Icons.lock_outline, title: 'Vault', subtitle: 'Videos ocultos',
                onTap: () => openVault(context)),
```

Test:
```dart
// test/ui/settings/settings_vault_row_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/ui/settings/settings_screen.dart';
import '../../fakes/fakes.dart';

Future<ProviderContainer> _c(bool hidden) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  await svc.update(svc.current.copyWith(vaultEntranceHidden: hidden));
  return ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(svc)]);
}

void main() {
  testWidgets('Vault row visible when entrance not hidden', (tester) async {
    final c = await _c(false);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const MaterialApp(home: SettingsScreen())));
    await tester.pump();
    expect(find.text('Vault'), findsOneWidget);
  });

  testWidgets('Vault row hidden when entrance hidden', (tester) async {
    final c = await _c(true);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const MaterialApp(home: SettingsScreen())));
    await tester.pump();
    expect(find.text('Vault'), findsNothing);
  });
}
```

- [ ] **Step 3: Library reveal gesture + test**

In `library_screen.dart`, wrap the `'Kivo'` `Text` (the one with `key: const ValueKey('title')`) in a `GestureDetector` with `onLongPress`. Add `import '../vault/vault_entry_actions.dart';`. Replace the `Text('Kivo', key: const ValueKey('title'), ...)` with:
```dart
                    : GestureDetector(
                        key: const ValueKey('title'),
                        behavior: HitTestBehavior.opaque,
                        onLongPress: () {
                          HapticFeedback.selectionClick();
                          openVault(context);
                        },
                        child: Text(
                          'Kivo',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
```
(`HapticFeedback` is from `package:flutter/services.dart`, already imported in this file.)

Test (verifies the long-press pushes a VaultScreen route — assert via presence of the Vault gate's AppBar title 'Vault' after settling; provide the vault/settings overrides):
```dart
// test/ui/home/library_reveal_gesture_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/platform/vault_ops_provider.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/vault/vault_providers.dart';
import 'package:kivo_player/vault/vault_auth.dart';
import 'package:kivo_player/vault/vault_store.dart';
import 'package:kivo_player/platform/biometric_auth_provider.dart';
import 'package:kivo_player/ui/home/library_screen.dart';
import '../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override Future<MediaAccess> status() async => MediaAccess.granted;
  @override Future<MediaAccess> request() async => MediaAccess.granted;
}

void main() {
  testWidgets('long-press on the Kivo title opens the Vault gate', (tester) async {
    final creds = InMemoryVaultCredentialStore();
    await VaultAuth(creds).setPin('1234'); // configured -> gate shows PIN pad
    final svc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      mediaFileOpsProvider.overrideWithValue(FakeMediaFileOps()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(const [])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      vaultOpsProvider.overrideWithValue(FakeVaultOps()),
      vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
      vaultCredentialStoreProvider.overrideWithValue(creds),
      biometricAuthProvider.overrideWithValue(FakeBiometricAuth(available: false)),
    ]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: KivoTheme.dark(), home: const LibraryScreen()),
    ));
    await tester.pump();

    await tester.longPress(find.byKey(const ValueKey('title')));
    await tester.pumpAndSettle();

    // The gate's PIN pad is showing (proves VaultScreen was pushed).
    expect(find.byKey(const Key('pin-key-1')), findsOneWidget);
  });
}
```

- [ ] **Step 4: SelectionBottomBar "Mover al Vault"**

In `selection_bottom_bar.dart` add `import '../../vault/vault_entry_actions.dart';` and a third `_action` (place it first, before Compartir, so the destructive Borrar stays rightmost):
```dart
              _action(cs.onSurface, Icons.lock_outline, 'Al Vault', enabled ? () async {
                await moveToVault(context, ref, chosen);
                sel.clear();
              } : null),
```

- [ ] **Step 5: video_options_sheet "Mover al Vault"**

In `video_options_sheet.dart`, add an `onMoveToVault` callback to `VideoOptionsSheet` and a `_row(context, Icons.lock_outline, 'Mover al Vault', cs.onSurface, onMoveToVault)` after Details. In `showVideoOptions`, wire it:
```dart
      onMoveToVault: () async {
        Navigator.pop(sheetContext);
        await moveToVault(context, ref, [v]);
      },
```
Add `import '../../vault/vault_entry_actions.dart';`. Note `showVideoOptions` already has `ref` in scope.

- [ ] **Step 6: Run the new tests + analyze**

Run: `flutter test test/ui/settings/settings_vault_row_test.dart test/ui/home/library_reveal_gesture_test.dart`
Expected: PASS (3 tests).
Run: `flutter analyze lib/ui/home/library_screen.dart lib/ui/settings/settings_screen.dart lib/ui/home/widgets/selection_bottom_bar.dart lib/ui/home/widgets/video_options_sheet.dart lib/ui/vault/vault_entry_actions.dart`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/settings/settings_screen.dart lib/ui/home/library_screen.dart lib/ui/home/widgets/selection_bottom_bar.dart lib/ui/home/widgets/video_options_sheet.dart lib/ui/vault/vault_entry_actions.dart test/ui/settings/settings_vault_row_test.dart test/ui/home/library_reveal_gesture_test.dart
git commit -m "feat(vault): settings row, reveal gesture, Mover al Vault (multi + single), uninstall warning"
```

---

### Task 11: Vault settings inside the gate + build & install

**Files:**
- Modify: `lib/ui/vault/vault_screen.dart` (add an overflow menu → hide-entrance toggle + biometric toggle + change PIN)
- Test: `test/ui/vault/vault_settings_test.dart`

**Interfaces:**
- Consumes: `settingsProvider`, `vaultAuthProvider`, `biometricAuthProvider`.
- Produces: an `AppBar` actions `PopupMenuButton` on `_VaultContent` (only when not selecting) with: **Ocultar entrada** (toggles `vaultEntranceHidden`, shows a SnackBar explaining the reveal gesture), **Usar biometría** (toggles `vaultBiometricEnabled`), **Cambiar PIN** (pushes a set-PIN screen reusing `PinPad`).

- [ ] **Step 1: Add the overflow menu to _VaultContent**

Add to the `AppBar` (when `!selecting`) an `actions: [ _VaultMenu() ]`. Implement:

```dart
// in lib/ui/vault/vault_screen.dart — add widget
class _VaultMenu extends ConsumerWidget {
  const _VaultMenu();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final messenger = ScaffoldMessenger.of(context);
    return PopupMenuButton<String>(
      onSelected: (v) async {
        final notifier = ref.read(settingsProvider.notifier);
        if (v == 'hide') {
          await notifier.set(settings.copyWith(vaultEntranceHidden: !settings.vaultEntranceHidden));
          messenger.showSnackBar(SnackBar(content: Text(settings.vaultEntranceHidden
              ? 'Entrada visible en Ajustes'
              : 'Entrada oculta. Mantén pulsado el título de Videos para entrar.')));
        } else if (v == 'bio') {
          await notifier.set(settings.copyWith(vaultBiometricEnabled: !settings.vaultBiometricEnabled));
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(value: 'hide', checked: settings.vaultEntranceHidden, child: const Text('Ocultar entrada')),
        CheckedPopupMenuItem(value: 'bio', checked: settings.vaultBiometricEnabled, child: const Text('Usar biometría')),
      ],
    );
  }
}
```

(Requires `import '../../core/settings/settings_provider.dart';` in vault_screen.dart. "Cambiar PIN" is deferred to a follow-up — YAGNI for v1; the toggle set covers the spec's stated controls. If time permits, add a menu item pushing a small set-PIN screen reusing `PinPad` + `vaultAuthProvider.setPin`.)

- [ ] **Step 2: Write the test**

```dart
// test/ui/vault/vault_settings_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/vault_ops_provider.dart';
import 'package:kivo_player/platform/biometric_auth_provider.dart';
import 'package:kivo_player/vault/vault_providers.dart';
import 'package:kivo_player/vault/vault_auth.dart';
import 'package:kivo_player/vault/vault_store.dart';
import 'package:kivo_player/ui/vault/vault_screen.dart';
import '../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override Future<MediaAccess> status() async => MediaAccess.granted;
  @override Future<MediaAccess> request() async => MediaAccess.granted;
}

void main() {
  testWidgets('toggling "Ocultar entrada" flips the setting', (tester) async {
    final creds = InMemoryVaultCredentialStore();
    await VaultAuth(creds).setPin('1234');
    final svc = await SettingsService.load(InMemorySettingsStore());
    await svc.update(svc.current.copyWith(vaultBiometricEnabled: true));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(const [])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
      vaultOpsProvider.overrideWithValue(FakeVaultOps()),
      vaultStoreProvider.overrideWithValue(InMemoryVaultStore()),
      vaultCredentialStoreProvider.overrideWithValue(creds),
      biometricAuthProvider.overrideWithValue(FakeBiometricAuth(available: true, willSucceed: true)),
    ]);
    addTearDown(c.dispose);
    await c.read(vaultEntriesProvider.future);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: KivoTheme.dark(), home: const VaultScreen()),
    ));
    await tester.pumpAndSettle(); // biometric auto-unlock

    expect(c.read(settingsProvider).vaultEntranceHidden, false);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ocultar entrada'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).vaultEntranceHidden, true);
  });
}
```

- [ ] **Step 3: Run test + full suite**

Run: `flutter test test/ui/vault/vault_settings_test.dart`
Expected: PASS (1 test).
Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 4: Analyze, build, install**

Run: `flutter analyze`
Expected: No issues.
Run: `flutter build apk --release`
Expected: `√ Built build\app\outputs\flutter-apk\app-release.apk`.
Run: `"$LOCALAPPDATA/Android/sdk/platform-tools/adb.exe" -s 24231FDF6006ST install -r build/app/outputs/flutter-apk/app-release.apk`
Expected: `Success`.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/vault/vault_screen.dart test/ui/vault/vault_settings_test.dart
git commit -m "feat(vault): in-vault settings (hide entrance, biometric toggle) + full build"
```

- [ ] **Step 6: Device checklist (manual)**

Verify on the Pixel 6:
1. Ajustes → Vault → set a PIN (first run) → lands in an empty Vault.
2. Biblioteca: long-press a video → "Al Vault" → uninstall warning (first time) → video disappears from the library AND from the system gallery.
3. Vault: the video is there with a thumbnail; tap plays it.
4. Vault: select → "Sacar del Vault" → reappears in the library/gallery.
5. Vault: select → "Borrar del teléfono" → confirm → gone (no system dialog).
6. Vault menu → "Ocultar entrada": the Ajustes row disappears; long-press the "Kivo" title on Videos → gate opens.
7. Enable biometric → leave and re-enter → fingerprint prompt appears, PIN pad on cancel.
8. Background the app while in the Vault → returning requires re-auth.

---

## Notes for the executor

- The `dart:typed_data` import is needed in `test/fakes/fakes.dart` for `Uint8List` (FakeVaultOps.thumbnail) — add if absent.
- `KivoTheme.dark()` maps the accent to `colorScheme.secondary`; every new widget uses `cs.secondary` for accent, never a literal.
- `ioExecutor`, `File`, `Uri`, `MediaStore`, `Bitmap`, `Build` are already in scope in `MainActivity.kt`; only `android.content.ContentValues` is written fully-qualified.
- If the `FlutterFragmentActivity` change breaks any existing channel at runtime (Task 7 Step 7), that is the first thing to investigate — do not proceed to Task 8 until the smoke test passes.
