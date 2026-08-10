import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'kivo_failure.dart';

/// One recorded failure, with the device context that makes it diagnosable.
class ErrorLogEntry {
  const ErrorLogEntry({
    required this.code,
    required this.op,
    required this.timestampMs,
    required this.detail,
    required this.appVersion,
    required this.androidSdk,
  });

  final String code;
  final String op;
  final int timestampMs;
  final String detail;
  final String appVersion;
  final int androidSdk;

  Map<String, dynamic> toMap() => {
        'code': code,
        'op': op,
        'timestampMs': timestampMs,
        'detail': detail,
        'appVersion': appVersion,
        'androidSdk': androidSdk,
      };

  factory ErrorLogEntry.fromMap(Map<String, dynamic> m) => ErrorLogEntry(
        code: (m['code'] as String?) ?? '',
        op: (m['op'] as String?) ?? '',
        timestampMs: (m['timestampMs'] as num?)?.toInt() ?? 0,
        detail: (m['detail'] as String?) ?? '',
        appVersion: (m['appVersion'] as String?) ?? '',
        androidSdk: (m['androidSdk'] as num?)?.toInt() ?? 0,
      );
}

abstract class ErrorLogStore {
  List<Map<String, dynamic>> read();
  Future<void> write(List<Map<String, dynamic>> entries);
}

/// One list of maps under a single key — same shape as the settings and
/// resume boxes, no generated adapters.
class HiveErrorLogStore implements ErrorLogStore {
  HiveErrorLogStore(this.box);
  final Box box;
  static const _key = 'entries';

  @override
  List<Map<String, dynamic>> read() {
    final raw = box.get(_key);
    if (raw is! List) return [];
    return raw.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  @override
  Future<void> write(List<Map<String, dynamic>> entries) =>
      box.put(_key, entries);
}

/// A ring buffer of the last [maxEntries] failures, newest first.
///
/// Every store access is wrapped: this is a diagnostic aid, and one that can
/// throw would be worse than none at all.
class ErrorLog {
  ErrorLog(
    this._store, {
    required this.appVersion,
    required this.androidSdk,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const int maxEntries = 20;

  final ErrorLogStore _store;
  final String appVersion;
  final int androidSdk;
  final DateTime Function() _now;

  /// Records [failure] and returns it, so a call site reads
  /// `throw _log.record(KivoFailure(op, e));`. Call it without throwing to
  /// note something that is not fatal to the operation.
  KivoFailure record(KivoFailure failure) {
    try {
      final entry = ErrorLogEntry(
        code: failure.code,
        op: failure.op.name,
        timestampMs: _now().millisecondsSinceEpoch,
        detail: failure.detail,
        appVersion: appVersion,
        androidSdk: androidSdk,
      );
      final next = [entry.toMap(), ..._read()];
      // Not awaited: recording must never slow down reporting a failure, and
      // the box serialises writes itself. But an un-awaited failure would
      // escape the try/catch as an unhandled async error, so it needs its own
      // handler — the whole point is that logging cannot break anything.
      _store.write(next.take(maxEntries).toList()).catchError((Object e) {
        debugPrint('ErrorLog.record write failed: $e');
      });
    } catch (e) {
      debugPrint('ErrorLog.record failed: $e');
    }
    return failure;
  }

  List<ErrorLogEntry> entries() => _read().map(ErrorLogEntry.fromMap).toList();

  Future<void> clear() async {
    try {
      await _store.write([]);
    } catch (e) {
      debugPrint('ErrorLog.clear failed: $e');
    }
  }

  List<Map<String, dynamic>> _read() {
    try {
      return _store.read();
    } catch (e) {
      debugPrint('ErrorLog.read failed: $e');
      return [];
    }
  }
}
