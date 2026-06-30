import 'package:hive/hive.dart';

class ResumeEntry {
  final String key;
  final int seconds;
  final int updatedAtMs;
  const ResumeEntry(this.key, this.seconds, this.updatedAtMs);
}

abstract class ResumeStore {
  int? secondsFor(String key);
  Future<void> put(String key, int seconds, int updatedAtMs);
  Future<void> remove(String key);
  List<ResumeEntry> entries();
}

class HiveResumeStore implements ResumeStore {
  final Box box;
  HiveResumeStore(this.box);

  int? _seconds(dynamic raw) {
    if (raw is int) return raw; // legacy: bare seconds
    if (raw is Map) return (raw['s'] as num?)?.toInt();
    return null;
  }

  @override
  int? secondsFor(String key) => _seconds(box.get(key));

  @override
  Future<void> put(String key, int seconds, int updatedAtMs) =>
      box.put(key, {'s': seconds, 'u': updatedAtMs});

  @override
  Future<void> remove(String key) => box.delete(key);

  @override
  List<ResumeEntry> entries() {
    final out = <ResumeEntry>[];
    for (final k in box.keys) {
      final raw = box.get(k);
      final s = _seconds(raw);
      if (s == null) continue;
      final u = raw is Map ? ((raw['u'] as num?)?.toInt() ?? 0) : 0; // legacy → 0
      out.add(ResumeEntry(k.toString(), s, u));
    }
    return out;
  }
}
