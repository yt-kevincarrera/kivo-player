import 'package:hive/hive.dart';

abstract class ResumeStore {
  int? secondsFor(String key);
  Future<void> put(String key, int seconds);
  Future<void> remove(String key);
}

class HiveResumeStore implements ResumeStore {
  final Box box;
  HiveResumeStore(this.box);

  @override
  int? secondsFor(String key) => box.get(key) as int?;
  @override
  Future<void> put(String key, int seconds) => box.put(key, seconds);
  @override
  Future<void> remove(String key) => box.delete(key);
}
