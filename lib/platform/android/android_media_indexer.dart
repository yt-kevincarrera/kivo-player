import 'package:flutter/services.dart';
import '../../core/errors/error_log.dart';
import '../../core/errors/kivo_failure.dart';
import '../interfaces/media_indexer.dart';
import 'media_kit_thumbnailer.dart';

class AndroidMediaIndexer implements MediaIndexer {
  AndroidMediaIndexer(
    this._log, {
    Future<Uint8List?> Function(String uri)? decoderThumbnail,
  }) : _decoderThumbnail = decoderThumbnail ?? MediaKitThumbnailer().thumbnail;

  final ErrorLog _log;
  final Future<Uint8List?> Function(String uri) _decoderThumbnail;
  final _items = <String, VideoItem>{};
  final _versions = <String, Object>{};
  final _thumbnails = <Object, Future<Uint8List?>>{};
  static const MethodChannel _channel = MethodChannel('kivo/media');

  @override
  Future<List<VideoItem>> scan() async {
    try {
      final raw =
          await _channel.invokeMethod<List<dynamic>>('scan') ?? const [];
      final versions = <String, Object>{};
      final items = raw.map((e) {
        final m = (e as Map).cast<String, dynamic>();
        versions[m['id'] as String] = (
          m['uri'],
          m['name'],
          m['sizeBytes'],
          m['dateAddedMs'],
          m['dateModifiedMs'],
        );
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
      _items
        ..clear()
        ..addEntries(items.map((item) => MapEntry(item.id, item)));
      _versions
        ..clear()
        ..addAll(versions);
      final live = versions.values.toSet();
      _thumbnails.removeWhere((key, _) => !live.contains(key));
      return items;
    } catch (e) {
      throw _log.record(KivoFailure(KivoOp.libraryScan, e));
    }
  }

  /// Records and returns null rather than throwing: one undecodable video must
  /// not blank out a grid of two hundred tiles.
  @override
  Future<Uint8List?> thumbnail(String id) {
    final version = _versions[id];
    if (version == null) return _thumbnail(id, null);
    final cached = _thumbnails.remove(version);
    final result = cached ?? _thumbnail(id, _items[id]);
    _thumbnails[version] = result;
    if (cached == null) {
      // A temporary storage/decoder failure must recover on the next request.
      result.then((bytes) {
        if (bytes == null && identical(_thumbnails[version], result)) {
          _thumbnails.remove(version);
        }
      });
    }
    if (_thumbnails.length > 48) _thumbnails.remove(_thumbnails.keys.first);
    return result;
  }

  Future<Uint8List?> _thumbnail(String id, VideoItem? item) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('thumbnail', {
        'id': id,
        if (item != null) 'uri': item.uri,
      });
      if (bytes != null && bytes.isNotEmpty) return bytes;
    } catch (e) {
      _log.record(KivoFailure(KivoOp.thumbnail, e));
    }
    final name = item?.name.toLowerCase() ?? '';
    // Android's thumbnail codecs vary by device. These containers can play
    // in our bundled decoder even when MediaStore cannot produce an image.
    if (item != null &&
        (name.endsWith('.rm') ||
            name.endsWith('.rmvb') ||
            name.endsWith('.avi'))) {
      try {
        return await _decoderThumbnail(item.uri);
      } catch (e) {
        _log.record(KivoFailure(KivoOp.thumbnail, e));
      }
    }
    return null;
  }
}
