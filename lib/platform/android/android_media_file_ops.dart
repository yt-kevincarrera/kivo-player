import 'package:flutter/services.dart';
import '../interfaces/media_file_ops.dart';

class AndroidMediaFileOps implements MediaFileOps {
  static const MethodChannel _channel = MethodChannel('kivo/media');

  FileOpStatus _status(String? s) => switch (s) {
        'ok' => FileOpStatus.ok,
        'cancelled' => FileOpStatus.cancelled,
        _ => FileOpStatus.error,
      };

  @override
  Future<FileOpStatus> delete(String uri) async {
    try {
      final s = await _channel.invokeMethod<String>('delete', {'uri': uri});
      return _status(s);
    } catch (_) {
      return FileOpStatus.error;
    }
  }

  @override
  Future<RenameOutcome> rename(String uri, String newBaseName) async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>(
          'rename', {'uri': uri, 'name': newBaseName});
      final status = _status(m?['status'] as String?);
      return RenameOutcome(status, newName: m?['newName'] as String?);
    } catch (_) {
      return const RenameOutcome(FileOpStatus.error);
    }
  }

  @override
  Future<void> share(String uri) async {
    try {
      await _channel.invokeMethod<void>('share', {'uri': uri});
    } catch (_) {/* fire-and-forget */}
  }

  @override
  Future<FileOpStatus> deleteMany(List<String> uris) async {
    try {
      final s = await _channel.invokeMethod<String>('deleteMany', {'uris': uris});
      return _status(s);
    } catch (_) {
      return FileOpStatus.error;
    }
  }

  @override
  Future<void> shareMany(List<String> uris) async {
    try {
      await _channel.invokeMethod<void>('shareMany', {'uris': uris});
    } catch (_) {/* fire-and-forget */}
  }
}
