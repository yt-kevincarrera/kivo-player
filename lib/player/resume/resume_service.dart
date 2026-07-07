import 'resume_store.dart';

class ResumeService {
  final ResumeStore _store;
  final int minSeconds;
  final double finishedTailFraction;

  ResumeService(this._store, {this.minSeconds = 5, this.finishedTailFraction = 0.97});

  Duration? positionFor(String key) {
    final s = _store.secondsFor(key);
    return s == null ? null : Duration(seconds: s);
  }

  Future<void> record(String key, Duration position, Duration total, int nowMs) async {
    final finishedThreshold = total.inMilliseconds * finishedTailFraction;
    if (total.inMilliseconds > 0 && position.inMilliseconds >= finishedThreshold) {
      await _store.remove(key);
      return;
    }
    if (position.inSeconds < minSeconds) return;
    await _store.put(key, position.inSeconds, nowMs);
  }

  List<ResumeEntry> entries() => _store.entries();

  Future<void> clear(String key) => _store.remove(key);

  /// Moves a resume entry from [from] to [to], preserving its recorded seconds
  /// and original timestamp (so a renamed video keeps its place in "continue
  /// watching" instead of jumping to the top). No-op if [from] has no entry.
  Future<void> rename(String from, String to) async {
    ResumeEntry? found;
    for (final e in _store.entries()) {
      if (e.key == from) { found = e; break; }
    }
    if (found == null) return;
    await _store.put(to, found.seconds, found.updatedAtMs);
    await _store.remove(from);
  }
}
