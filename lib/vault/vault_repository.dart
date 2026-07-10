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

  /// One-time move of legacy vault files into the current (shared, same-volume)
  /// vault dir, rewriting each moved entry's [VaultEntry.privatePath] to its new
  /// location. Safe to call on every load — a no-op once nothing needs moving.
  Future<void> migrateStorage() async {
    final pairs = await _ops.migrate();
    if (pairs.isEmpty) return;
    final remap = {
      for (final p in pairs)
        if (p['old'] is String && p['new'] is String) p['old'] as String: p['new'] as String,
    };
    if (remap.isEmpty) return;
    _entries = _entries
        .map((e) => remap.containsKey(e.privatePath)
            ? VaultEntry(
                id: e.id,
                privatePath: remap[e.privatePath]!,
                displayName: e.displayName,
                originalRelativePath: e.originalRelativePath,
                durationMs: e.durationMs,
                sizeBytes: e.sizeBytes,
                dateAddedMs: e.dateAddedMs,
                width: e.width,
                height: e.height,
              )
            : e)
        .toList();
    await _store.writeAll(_entries);
  }

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
    final succeeded = (await _ops.unhide(entries
            .map((e) => {
                  'privatePath': e.privatePath,
                  'displayName': e.displayName,
                  'relativePath': e.originalRelativePath,
                  'dateAddedMs': e.dateAddedMs,
                })
            .toList()))
        .toSet();
    await _removeByPaths(succeeded);
    return succeeded.length == entries.length;
  }

  Future<bool> deleteForever(List<VaultEntry> entries) async {
    final succeeded =
        (await _ops.deleteForever(entries.map((e) => e.privatePath).toList())).toSet();
    await _removeByPaths(succeeded);
    return succeeded.length == entries.length;
  }

  Future<void> _removeByPaths(Set<String> paths) async {
    _entries = _entries.where((e) => !paths.contains(e.privatePath)).toList();
    await _store.writeAll(_entries);
  }
}
