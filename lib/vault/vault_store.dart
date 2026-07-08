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
