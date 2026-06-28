import 'package:hive/hive.dart';

abstract class SettingsStore {
  Map<String, dynamic>? read();
  Future<void> write(Map<String, dynamic> data);
}

class HiveSettingsStore implements SettingsStore {
  final Box box;
  static const _key = 'settings';
  HiveSettingsStore(this.box);

  @override
  Map<String, dynamic>? read() {
    final raw = box.get(_key);
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  @override
  Future<void> write(Map<String, dynamic> data) => box.put(_key, data);
}
