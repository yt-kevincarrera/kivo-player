import 'package:flutter/services.dart';
import '../../core/errors/error_log.dart';
import '../../core/errors/kivo_failure.dart';
import '../interfaces/media_file_ops.dart';

class AndroidMediaFileOps implements MediaFileOps {
  AndroidMediaFileOps(this._log);

  final ErrorLog _log;
  static const MethodChannel _channel = MethodChannel('kivo/media');

  /// Android 11 (API 30, R) introduced MediaStore's system trash — see
  /// [MediaFileOps.movesToTrash]. [_log.androidSdk] is the API level already
  /// fetched once via the 'kivo/update' channel at startup (main.dart), so
  /// this needs no extra platform round trip.
  @override
  bool get movesToTrash => _log.androidSdk >= 30;

  FileOpStatus _status(String? s) => switch (s) {
        'ok' => FileOpStatus.ok,
        'cancelled' => FileOpStatus.cancelled,
        _ => FileOpStatus.error,
      };

  /// Records [op] when [status] is an error. `cancelled` is the user changing
  /// their mind, not a failure — logging it would only add noise.
  FileOpStatus _recordIfError(FileOpStatus status, KivoOp op, Object cause) {
    if (status == FileOpStatus.error) _log.record(KivoFailure(op, cause));
    return status;
  }

  @override
  Future<FileOpStatus> delete(String uri) async {
    try {
      final s = await _channel.invokeMethod<String>('delete', {'uri': uri});
      return _recordIfError(_status(s), KivoOp.delete, 'delete returned $s');
    } catch (e) {
      _log.record(KivoFailure(KivoOp.delete, e));
      return FileOpStatus.error;
    }
  }

  @override
  Future<RenameOutcome> rename(String uri, String newBaseName) async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>(
          'rename', {'uri': uri, 'name': newBaseName});
      final status = _recordIfError(_status(m?['status'] as String?),
          KivoOp.rename, 'rename returned ${m?['status']}');
      return RenameOutcome(status, newName: m?['newName'] as String?);
    } catch (e) {
      _log.record(KivoFailure(KivoOp.rename, e));
      return const RenameOutcome(FileOpStatus.error);
    }
  }

  @override
  Future<void> share(String uri) async {
    try {
      await _channel.invokeMethod<void>('share', {'uri': uri});
    } catch (e) {
      _log.record(KivoFailure(KivoOp.share, e));
    }
  }

  @override
  Future<FileOpStatus> deleteMany(List<String> uris) async {
    try {
      final s = await _channel.invokeMethod<String>('deleteMany', {'uris': uris});
      return _recordIfError(
          _status(s), KivoOp.delete, 'deleteMany(${uris.length}) returned $s');
    } catch (e) {
      _log.record(KivoFailure(KivoOp.delete, e));
      return FileOpStatus.error;
    }
  }

  @override
  Future<void> shareMany(List<String> uris) async {
    try {
      await _channel.invokeMethod<void>('shareMany', {'uris': uris});
    } catch (e) {
      _log.record(KivoFailure(KivoOp.share, e));
    }
  }
}
