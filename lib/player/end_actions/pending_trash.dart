import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

/// A finished video waiting to go to the trash. Persisted so a deletion that
/// needs Android's consent dialog — or that the app was killed before
/// committing — is asked about later instead of being lost or done blindly.
class PendingTrash {
  final String uri;
  final String name;
  final String id;
  final int stagedAtMs;
  const PendingTrash({
    required this.uri,
    required this.name,
    required this.id,
    required this.stagedAtMs,
  });

  Map<String, Object> toMap() =>
      {'uri': uri, 'name': name, 'id': id, 'stagedAtMs': stagedAtMs};

  static PendingTrash? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final uri = raw['uri'];
    final name = raw['name'];
    if (uri is! String || name is! String) return null;
    return PendingTrash(
      uri: uri,
      name: name,
      id: raw['id'] is String ? raw['id'] as String : '',
      stagedAtMs: raw['stagedAtMs'] is int ? raw['stagedAtMs'] as int : 0,
    );
  }
}

abstract class PendingTrashStore {
  /// Oldest first.
  List<PendingTrash> all();
  Future<void> put(PendingTrash entry);
  Future<void> remove(String uri);
}

class HivePendingTrashStore implements PendingTrashStore {
  final Box box;
  HivePendingTrashStore(this.box);

  @override
  List<PendingTrash> all() => box.values
      .map(PendingTrash.fromMap)
      .whereType<PendingTrash>()
      .toList()
    ..sort((a, b) => a.stagedAtMs.compareTo(b.stagedAtMs));

  @override
  Future<void> put(PendingTrash entry) => box.put(entry.uri, entry.toMap());

  @override
  Future<void> remove(String uri) => box.delete(uri);
}

class InMemoryPendingTrashStore implements PendingTrashStore {
  final Map<String, PendingTrash> _m = {};

  @override
  List<PendingTrash> all() => _m.values.toList()
    ..sort((a, b) => a.stagedAtMs.compareTo(b.stagedAtMs));

  @override
  Future<void> put(PendingTrash entry) async => _m[entry.uri] = entry;

  @override
  Future<void> remove(String uri) async => _m.remove(uri);
}

final pendingTrashStoreProvider = Provider<PendingTrashStore>((ref) {
  throw UnimplementedError('pendingTrashStoreProvider must be overridden');
});
