import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Keeps the human filename alongside opaque history keys, including legacy
/// records whose owner cannot be determined. Export only names with history.
abstract class HistoryNames {
  Map<String, String> all();
  Future<void> put(String key, String name);
}

class HiveHistoryNames implements HistoryNames {
  HiveHistoryNames(this.box);
  final Box box;
  @override
  Map<String, String> all() => {
    for (final key in box.keys)
      if (box.get(key) is String) key.toString(): box.get(key) as String,
  };
  @override
  Future<void> put(String key, String name) => box.put(key, name);
}

class InMemoryHistoryNames implements HistoryNames {
  final _names = <String, String>{};
  @override
  Map<String, String> all() => Map.of(_names);
  @override
  Future<void> put(String key, String name) async => _names[key] = name;
}

final historyNamesProvider = Provider<HistoryNames>(
  (ref) => InMemoryHistoryNames(),
);

/// Label persistence must not interrupt playback if storage is unavailable.
Future<void> rememberHistoryName(
  HistoryNames names,
  String key,
  String name,
) async {
  try {
    await names.put(key, name);
  } catch (error) {
    debugPrint('History label could not be saved: $error');
  }
}
