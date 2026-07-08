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
