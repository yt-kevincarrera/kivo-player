import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/errors/error_log.dart';
import '../../core/errors/kivo_failure.dart';
import '../interfaces/image_saver.dart';

class AndroidImageSaver implements ImageSaver {
  AndroidImageSaver([this._log]);
  final ErrorLog? _log;

  static const MethodChannel _channel = MethodChannel('kivo/media');

  @override
  Future<String?> save(Uint8List bytes, String fileName) async {
    try {
      return await _channel.invokeMethod<String>(
          'saveImage', {'bytes': bytes, 'fileName': fileName});
    } catch (e) {
      // Never throws: the caller treats a null as "not saved" and reports
      // KV-503 itself, but the reason belongs in the log either way.
      _log?.record(KivoFailure(KivoOp.frameCapture, e));
      debugPrint('AndroidImageSaver.save failed: $e');
      return null;
    }
  }

  @override
  Future<void> view(String uri) async {
    try {
      await _channel.invokeMethod<void>('viewImage', {'uri': uri});
    } catch (e) {
      debugPrint('AndroidImageSaver.view failed: $e');
    }
  }
}
