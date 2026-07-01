import 'package:flutter/services.dart';
import '../interfaces/subtitle_finder.dart';

class AndroidSubtitleFinder implements SubtitleFinder {
  static const _channel = MethodChannel('kivo/media');

  @override
  Future<List<ExternalSubtitle>> findNear(String folder) async {
    final result = await _channel.invokeMethod('findSubtitles', {'folder': folder});
    final list = (result as List?) ?? const [];
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map((m) => ExternalSubtitle(
              uri: m['uri'] as String,
              displayName: m['displayName'] as String,
            ))
        .toList();
  }
}
