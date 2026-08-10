import 'package:flutter/services.dart';
import '../../core/errors/error_log.dart';
import '../../core/errors/kivo_failure.dart';
import '../interfaces/media_indexer.dart';

class AndroidMediaIndexer implements MediaIndexer {
  AndroidMediaIndexer(this._log);

  final ErrorLog _log;
  static const MethodChannel _channel = MethodChannel('kivo/media');

  @override
  Future<List<VideoItem>> scan() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('scan') ?? const [];
      return raw.map((e) {
        final m = (e as Map).cast<String, dynamic>();
        return VideoItem(
          id: m['id'] as String,
          uri: m['uri'] as String,
          name: (m['name'] as String?) ?? '',
          folder: (m['folder'] as String?) ?? '',
          durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
          sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
          dateAddedMs: (m['dateAddedMs'] as num?)?.toInt() ?? 0,
          width: (m['width'] as num?)?.toInt() ?? 0,
          height: (m['height'] as num?)?.toInt() ?? 0,
          path: (m['path'] as String?) ?? '',
        );
      }).toList();
    } catch (e) {
      throw _log.record(KivoFailure(KivoOp.libraryScan, e));
    }
  }

  /// Records and returns null rather than throwing: one undecodable video must
  /// not blank out a grid of two hundred tiles.
  @override
  Future<Uint8List?> thumbnail(String id) async {
    try {
      return await _channel.invokeMethod<Uint8List>('thumbnail', {'id': id});
    } catch (e) {
      _log.record(KivoFailure(KivoOp.thumbnail, e));
      return null;
    }
  }
}
