import 'package:flutter/services.dart';

import '../../core/errors/error_log.dart';
import '../../core/errors/kivo_failure.dart';
import '../interfaces/subtitle_transcoder.dart';

class AndroidSubtitleTranscoder implements SubtitleTranscoder {
  AndroidSubtitleTranscoder(this._log);

  final ErrorLog _log;
  static const MethodChannel _channel = MethodChannel('kivo/subtitles');

  @override
  Future<PreparedSubtitle> prepare(String uri,
      {String? name, String? encoding}) async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('prepare', {
        'uri': uri,
        'name': name,
        'encoding': encoding,
      });
      final m = (raw ?? const {}).cast<String, dynamic>();
      return PreparedSubtitle(
        uri: (m['path'] as String?) ?? uri,
        encoding: m['encoding'] as String?,
        detected: (m['detected'] as bool?) ?? false,
      );
    } catch (e) {
      throw _log.record(KivoFailure(KivoOp.subtitleLoad, e));
    }
  }

  /// Best-effort: an empty list just means "Más…" has nothing extra to show.
  @override
  Future<List<String>> availableEncodings() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('encodings');
      return (raw ?? const []).cast<String>();
    } catch (e) {
      _log.record(KivoFailure(KivoOp.subtitleLoad, e));
      return const [];
    }
  }
}
