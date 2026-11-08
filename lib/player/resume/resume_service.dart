import 'dart:async';

import 'resume_store.dart';
import '../library/played.dart';

class ResumeService {
  final ResumeStore _store;
  final int minSeconds;
  final double finishedTailFraction;
  final PlayedStore _completed;
  final _changes = StreamController<int>.broadcast();
  int _revision = 0;

  ResumeService(
    this._store, {
    this.minSeconds = 5,
    this.finishedTailFraction = 0.97,
    PlayedStore? completedStore,
  }) : _completed = completedStore ?? InMemoryPlayedStore();

  Set<String> get completedKeys => _completed.keys();
  Stream<int> get changes => _changes.stream;
  void _notify() => _changes.add(++_revision);

  Future<void> markCompleted(String key) async {
    await _completed.markPlayed(key);
    _notify();
  }
  Future<void> markUnfinished(String key) async {
    await _completed.remove(key);
    _notify();
  }

  /// A genuine end event also covers clips shorter than the periodic save.
  Future<void> finish(String key) async {
    await _completed.markPlayed(key);
    await _store.remove(key);
    _notify();
  }

  /// Restore an exact saved position without applying live playback thresholds.
  Future<void> restore(ResumeEntry entry) async {
    await _store.put(entry.key, entry.seconds, entry.updatedAtMs);
    _notify();
  }

  Duration? positionFor(String key) {
    final s = _store.secondsFor(key);
    return s == null ? null : Duration(seconds: s);
  }

  Future<void> record(
    String key,
    Duration position,
    Duration total,
    int nowMs,
  ) async {
    final finishedThreshold = total.inMilliseconds * finishedTailFraction;
    if (total.inMilliseconds > 0 &&
        position.inMilliseconds >= finishedThreshold) {
      await finish(key);
      return;
    }
    if (position.inSeconds < minSeconds) return;
    if (total > Duration.zero) await _completed.remove(key);
    await _store.put(key, position.inSeconds, nowMs);
    _notify();
  }

  List<ResumeEntry> entries() => _store.entries();

  Future<void> clear(String key) async {
    await _store.remove(key);
    _notify();
  }

  /// Moves a resume entry from [from] to [to], preserving its recorded seconds
  /// and original timestamp (so a renamed video keeps its place in "continue
  /// watching" instead of jumping to the top). No-op if [from] has no entry.
  Future<void> rename(String from, String to) async {
    if (from == to) return;
    if (_completed.isPlayed(from)) {
      await _completed.markPlayed(to);
      await _completed.remove(from);
    }
    ResumeEntry? found;
    for (final e in _store.entries()) {
      if (e.key == from) {
        found = e;
        break;
      }
    }
    if (found == null) {
      _notify();
      return;
    }
    await _store.put(to, found.seconds, found.updatedAtMs);
    await _store.remove(from);
    _notify();
  }
}
