import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

abstract class PlayedStore {
  bool isPlayed(String key);
  Future<void> markPlayed(String key);
  Set<String> keys();
}

class HivePlayedStore implements PlayedStore {
  final Box box;
  HivePlayedStore(this.box);
  @override
  bool isPlayed(String key) => box.containsKey(key);
  @override
  Future<void> markPlayed(String key) => box.put(key, true);
  @override
  Set<String> keys() => box.keys.map((k) => k.toString()).toSet();
}

class InMemoryPlayedStore implements PlayedStore {
  final Set<String> _s = {};
  @override
  bool isPlayed(String key) => _s.contains(key);
  @override
  Future<void> markPlayed(String key) async => _s.add(key);
  @override
  Set<String> keys() => Set.of(_s);
}

final playedStoreProvider = Provider<PlayedStore>((ref) {
  throw UnimplementedError('playedStoreProvider must be overridden');
});

/// The set of played (ever-opened) video keys. Invalidate on return from the
/// player so a just-played video is no longer "Nuevo".
final playedKeysProvider =
    Provider<Set<String>>((ref) => ref.watch(playedStoreProvider).keys());
